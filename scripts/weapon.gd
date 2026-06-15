extends Node3D
## Hitscan silah. İki katman:
##  - base_data: şu an kuşanılan silahın temel statları (evrimle değişir)
##  - weapon_mods: kartlardan biriken çarpan/eklemeler (silah değişse de korunur)
## data = base_data + tüm mods → her atışta okunan efektif statlar.
## İKİ SLOT: tabanca sabit slot 0; evrim silahları slot 1'e gelir (yenisi eskisini
## değiştirir). Q ile geçiş; mermi/şarjör durumu slot başına saklanır.

signal ammo_changed(current: int, reserve: int)
signal hit_confirmed(headshot: bool)
signal weapon_changed(display_name: String)
signal slots_changed(active_name: String, inactive_name: String)
signal reload_started(duration: float)
signal reload_finished
signal loadout_changed(items: Array)  ## HUD'daki sol silah listesi için tam kuşanım

const IMPACT_SCENE := preload("res://scenes/fx/impact.tscn")
const AMMO_PER_KILL := 3  ## her öldürmede yedeğe dönen mermi
const KNIFE_ICON := preload("res://assets/weapons/icons/knife.png")

@export var data: WeaponData  ## başlangıç silahı (pistol)

@onready var ray: RayCast3D = %Ray
@onready var muzzle_flash: MeshInstance3D = %MuzzleFlash
@onready var muzzle_light: OmniLight3D = %MuzzleLight

var base_data: WeaponData
var weapon_mods: Array[Dictionary] = []  ## her biri {mul:{}, add:{}}

var current_ammo := 0
var reserve := 0

var active_slot := 0
var _slot_states: Array = [null, null]  ## {base: WeaponData, ammo: int, reserve: int}
var _models: Array = [null, null]  ## slot başına görüş modeli (pistol gömülü, gizle/göster)
var _reload_token := 0  ## slot değişince eski reload'un await'i mermi eklemesin
var _pistol_stream: AudioStream
var _pistol_db := 0.0

var _cooldown := 0.0
var _reloading := false
var _base_z := 0.0
var _gun_anim: AnimationPlayer

# bıçak (mermi bitince son çare yakın dövüş)
# sol tık = hızlı jab; sağ tık = ağır saplama (daha uzun bekleme + animasyon + hasar)
const MELEE_DAMAGE := 55.0
const MELEE_RANGE := 2.8
const MELEE_COOLDOWN := 0.55
const HEAVY_DAMAGE := 95.0
const HEAVY_RANGE := 3.3
const HEAVY_COOLDOWN := 1.05
const HEAVY_WINDUP := 0.18  ## saplamadan önce geri çekme (vuruş bu sürenin sonunda iner)
var _melee_cd := 0.0
var _knife := false  ## bıçak elde mi (scroll ile geçilir; sol/sağ tık saldırır)
var _knife_swing: AudioStreamPlayer
var _knife_hit: AudioStreamPlayer
var _knife_model: Node3D       ## bıçak 3D modeli (Gun'a çocuk, normalde gizli)
var _knife_base_pos := Vector3.ZERO
var _knife_base_rot := Vector3.ZERO
var _knife_tween: Tween
var _last_view := 0            ## Q ile dönülecek en son silah/görünüm (0,1 veya 2=bıçak)


func _ready() -> void:
	base_data = data.duplicate()
	_base_z = position.z
	ray.add_exception(owner)
	# slot 0 = tabanca: modeli sahneye gömülü, sesi ShootSfx'in varsayılanı
	_slot_states[0] = {"base": base_data, "ammo": -1, "reserve": -1}
	_models[0] = get_node_or_null("GunModel")
	_pistol_stream = $ShootSfx.stream
	_pistol_db = $ShootSfx.volume_db
	_grab_model_anim()
	if _models[0] != null:
		_apply_gunmetal(_models[0])  # başlangıç silahı da metal görünsün (beyaz kalmasın)
	_recompute(false)
	Game.kills_changed.connect(_on_kill)
	_knife_swing = AudioStreamPlayer.new()
	_knife_swing.stream = load("res://assets/audio/weapons/knife_swing.wav")
	_knife_swing.volume_db = -6.0
	add_child(_knife_swing)
	_knife_hit = AudioStreamPlayer.new()
	_knife_hit.stream = load("res://assets/audio/weapons/knife_hit.wav")
	_knife_hit.volume_db = -3.0
	add_child(_knife_hit)
	_build_knife_model()
	_emit_loadout()


func _build_knife_model() -> void:
	## hançer: ele yatık tutulur, ağzı yukarı-ileri bakar (doğal çelik/bakır görünüm — metalle boyanmaz)
	var scn := load("res://assets/weapons/dagger.gltf") as PackedScene
	if scn == null:
		return
	_knife_model = scn.instantiate()
	_knife_model.scale = Vector3.ONE * 0.19
	_knife_model.rotation_degrees = Vector3(-70.0, 16.0, 10.0)
	_knife_model.position = Vector3(-0.05, 0.03, -0.02)
	_knife_model.visible = false
	add_child(_knife_model)
	_knife_base_pos = _knife_model.position
	_knife_base_rot = _knife_model.rotation


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_melee_cd = maxf(_melee_cd - delta, 0.0)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or owner.dead:
		return

	if _knife:
		# bıçak elde: sol tık hızlı jab, sağ tık ağır saplama (mermi gerekmez)
		if _melee_cd == 0.0:
			if Input.is_action_pressed("heavy_attack"):
				_melee(true)
			elif Input.is_action_pressed("shoot"):
				_melee(false)
	else:
		var wants_fire := Input.is_action_pressed("shoot") if data.auto \
				else Input.is_action_just_pressed("shoot")
		if wants_fire and _cooldown == 0.0 and not _reloading:
			if current_ammo > 0:
				_fire()
			elif reserve > 0:
				reload()  # şarjör boş ama yedek var → otomatik doldur
			elif Input.is_action_just_pressed("shoot"):
				$DryFireSfx.play()  # tamamen boş → kuru tetik tıkı
				_cooldown = 0.25
		if Input.is_action_just_pressed("reload"):
			reload()

	if Input.is_action_just_pressed("switch_weapon"):
		_switch_to_last()


func _input(event: InputEvent) -> void:
	## fare tekerleği ile silah döngüsü (ana silah → tabanca → bıçak, sarmalı)
	## _input kullanıyoruz ki nişangah/HUD Control'leri tekerlek olayını yutmasın
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or owner.dead:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle(1)


# ---- kart arayüzü ----

func add_weapon_mod(mul: Dictionary, add: Dictionary) -> void:
	weapon_mods.append({"mul": mul, "add": add})
	_recompute()


func equip(new_base: WeaponData) -> void:
	## evrim: yeni silah HEP slot 1'e gelir (tabanca slot 0'da sabit kalır)
	_cancel_reload()
	if _knife and _knife_model != null:
		_knife_model.visible = false
	_knife = false
	_last_view = 0  # evrim sonrası Q tabancaya dönsün
	_save_active()
	if _models[1] != null:
		_models[1].queue_free()
		_models[1] = null
	_slot_states[1] = {"base": new_base.duplicate(), "ammo": -1, "reserve": -1}
	active_slot = 1
	_activate_slot()


func switch_slot() -> void:
	_cycle(1)  # ileri döngü


func _current_view() -> int:
	return 2 if _knife else active_slot


func _switch_to_last() -> void:
	## Q: en son kullanılan silaha/görünüme dön (scroll ise tüm döngüyü gezer)
	var target := _last_view
	if target == _current_view():
		return  # zaten oradayız — başka geçerli görünüm yoksa bir şey yapma
	if target == 1 and _slot_states[1] == null:
		target = 0  # ikincil yoksa tabancaya düş
	_set_view(target)


func _cycle(dir: int) -> void:
	## silah döngüsü: tabanca → (ikincil varsa) → bıçak → ...
	var views := [0]
	if _slot_states[1] != null:
		views.append(1)
	views.append(2)  # 2 = bıçak
	if views.size() <= 1:
		return
	var cur := _current_view()
	var i: int = views.find(cur)
	i = (i + dir + views.size()) % views.size()
	_set_view(views[i])


func _set_view(view: int) -> void:
	var cur := _current_view()
	if view == cur:
		return
	_last_view = cur  # mevcut görünümü "son silah" olarak hatırla (Q geri döner)
	if view == 2:
		_enter_knife()
		return
	if _knife:
		_exit_knife()
		if view == active_slot:
			$DryFireSfx.play()
			return
	_cancel_reload()
	_save_active()
	active_slot = view
	_activate_slot()
	$DryFireSfx.play()


func _enter_knife() -> void:
	if _knife:
		return
	_cancel_reload()
	_save_active()  # silahın mermisini koru
	_knife = true
	for m in _models:
		if m != null:
			(m as Node3D).visible = false
	if _knife_model != null:
		_knife_model.visible = true
		_knife_model.position = _knife_base_pos
		_knife_model.rotation = _knife_base_rot
	weapon_changed.emit("Bıçak")
	slots_changed.emit("Bıçak", data.display_name)
	ammo_changed.emit(-1, -1)  # HUD: mermisiz göster
	_emit_loadout()
	$DryFireSfx.play()


func _exit_knife() -> void:
	_knife = false
	if _knife_model != null:
		_knife_model.visible = false
	for i in 2:
		if _models[i] != null:
			(_models[i] as Node3D).visible = i == active_slot
	weapon_changed.emit(data.display_name)
	slots_changed.emit(data.display_name, inactive_slot_name())
	ammo_changed.emit(current_ammo, reserve)
	_emit_loadout()


func loadout() -> Array:
	## HUD listesi (sıra: ana silah → varsayılan tabanca → bıçak), aktif olan işaretli
	var cur := _current_view()
	var items: Array = []
	if _slot_states[1] != null:  # ana silah (evrim) en üstte
		items.append({"name": slot_name(1), "icon": _slot_icon(1), "active": cur == 1})
	items.append({"name": slot_name(0), "icon": _slot_icon(0), "active": cur == 0})  # varsayılan tabanca
	items.append({"name": "Bıçak", "icon": KNIFE_ICON, "active": cur == 2})
	return items


func _slot_icon(slot: int) -> Texture2D:
	if slot == active_slot:
		return data.icon
	if _slot_states[slot] == null:
		return null
	return (_slot_states[slot]["base"] as WeaponData).icon


func _emit_loadout() -> void:
	loadout_changed.emit(loadout())


func has_secondary() -> bool:
	return _slot_states[1] != null


func inactive_slot_name() -> String:
	var other := 1 - active_slot
	if _slot_states[other] == null:
		return ""
	return (_slot_states[other]["base"] as WeaponData).display_name


func inactive_slot_ammo() -> Vector2i:
	## pasif slotun (mermi, yedek) durumu; slot boşsa (-1,-1)
	var other := 1 - active_slot
	if _slot_states[other] == null:
		return Vector2i(-1, -1)
	var st: Dictionary = _slot_states[other]
	if int(st["ammo"]) < 0:  # hiç kuşanılmadı: dolu gelecek
		var b := st["base"] as WeaponData
		return Vector2i(b.mag_size, b.reserve_ammo)
	return Vector2i(int(st["ammo"]), int(st["reserve"]))


func _save_active() -> void:
	_slot_states[active_slot] = {"base": base_data, "ammo": current_ammo, "reserve": reserve}


func slot_name(slot: int) -> String:
	if slot == active_slot:
		return data.display_name
	if _slot_states[slot] == null:
		return ""
	return (_slot_states[slot]["base"] as WeaponData).display_name


func add_reserve(slot: int, amount: int) -> void:
	## belirli slotun yedek mermisine ekle (pasif slot da olabilir)
	if slot == active_slot:
		reserve += amount
		ammo_changed.emit(current_ammo, reserve)
	elif _slot_states[slot] != null:
		var st: Dictionary = _slot_states[slot]
		if int(st["reserve"]) < 0:  # henüz hiç kuşanılmadı → dolu + ekstra
			var b := st["base"] as WeaponData
			st["ammo"] = b.mag_size
			st["reserve"] = b.reserve_ammo + amount
		else:
			st["reserve"] = int(st["reserve"]) + amount


func export_ammo() -> Dictionary:
	## her iki slotun mermi durumunu kat geçişi için dışa aktar
	_save_active()
	var out := {"active": active_slot}
	for i in 2:
		if _slot_states[i] != null:
			out[i] = Vector2i(int(_slot_states[i]["ammo"]), int(_slot_states[i]["reserve"]))
	return out


func import_ammo(d: Dictionary) -> void:
	## kat geçişinden taşınan mermiyi geri yükle (kartlar uygulandıktan SONRA çağrılır)
	if d.is_empty():
		return
	for i in 2:
		if d.has(i) and _slot_states[i] != null:
			var v: Vector2i = d[i]
			_slot_states[i]["ammo"] = v.x
			_slot_states[i]["reserve"] = v.y
	if d.has("active") and _slot_states[int(d["active"])] != null:
		active_slot = int(d["active"])
	_activate_slot()


func _cancel_reload() -> void:
	_reload_token += 1
	if _reloading:
		_reloading = false
		reload_finished.emit()


func _activate_slot() -> void:
	var st: Dictionary = _slot_states[active_slot]
	base_data = st["base"]

	# model: slot 0 sahneye gömülü tabanca (gizle/göster), slot 1 data'dan instance
	if active_slot == 1 and _models[1] == null:
		_models[1] = _instance_model(base_data)
	for i in 2:
		if _models[i] != null:
			(_models[i] as Node3D).visible = i == active_slot
	_gun_anim = (_models[active_slot] as Node).find_child("AnimationPlayer", true, false) \
			if _models[active_slot] != null else null

	# ses: tabanca sahnedeki varsayılan stream'i kullanır
	if active_slot == 0 or base_data.fire_sound == null:
		$ShootSfx.stream = _pistol_stream
		$ShootSfx.volume_db = _pistol_db
	else:
		$ShootSfx.stream = base_data.fire_sound
		$ShootSfx.volume_db = base_data.fire_volume_db

	if int(st["ammo"]) < 0:
		_recompute(false)  # ilk kuşanma: dolu şarjör
	else:
		_recompute(true)
		current_ammo = int(st["ammo"])
		reserve = int(st["reserve"])
		ammo_changed.emit(current_ammo, reserve)
	weapon_changed.emit(data.display_name)
	slots_changed.emit(data.display_name, inactive_slot_name())
	_emit_loadout()


func refresh_stats() -> void:
	ammo_changed.emit(current_ammo, reserve)


# ---- iç mantık ----

func _recompute(keep_ammo := true) -> void:
	data = base_data.duplicate()
	for m in weapon_mods:
		for k: String in m["mul"]:
			data.set(k, data.get(k) * m["mul"][k])
		for k: String in m["add"]:
			data.set(k, data.get(k) + m["add"][k])
	if not keep_ammo:
		current_ammo = data.mag_size
		reserve = data.reserve_ammo
	current_ammo = mini(current_ammo, data.mag_size)
	ammo_changed.emit(current_ammo, reserve)


func _fire() -> void:
	current_ammo -= 1
	_cooldown = 1.0 / data.fire_rate
	ammo_changed.emit(current_ammo, reserve)
	_kick()
	_muzzle_flash()
	owner.add_recoil()
	_play_gun_anim("Fire")
	$ShootSfx.pitch_scale = randf_range(0.95, 1.05)
	$ShootSfx.play()

	var any_hit := false
	var any_headshot := false
	for i in maxi(data.pellets, 1):
		if _fire_ray():
			any_hit = true
			if _last_headshot:
				any_headshot = true
	if any_hit:
		hit_confirmed.emit(any_headshot)
		$HitSfx.pitch_scale = 1.5 if any_headshot else 1.0
		$HitSfx.play()


var _last_headshot := false

func _fire_ray() -> bool:
	# ışın yönü: ray node'unun -Z'si; saçılma varsa küçük açıyla sapt
	var b := ray.global_transform.basis
	var dir := -b.z.normalized()
	if data.spread_deg > 0.0:
		var s := deg_to_rad(data.spread_deg)
		dir = dir.rotated(b.x.normalized(), randf_range(-s, s)).rotated(b.y.normalized(), randf_range(-s, s))
	_last_headshot = false

	var space := ray.get_world_3d().direct_space_state
	var mask := ray.collision_mask
	var from := ray.global_position
	var exclude: Array[RID] = [owner.get_rid()]
	var pierces_left := data.pierce
	var hit_any := false

	while true:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0, mask)
		q.exclude = exclude
		var res := space.intersect_ray(q)
		if res.is_empty():
			break
		var collider: Object = res.collider
		var point: Vector3 = res.position
		_spawn_impact(point, res.normal)
		if collider != null and collider.has_method("take_damage"):
			var headshot: bool = collider.has_method("is_headshot") and collider.is_headshot(point)
			var dmg: float = data.damage * (data.headshot_mult if headshot else 1.0)
			if data.crit_chance > 0.0 and randf() < data.crit_chance:
				dmg *= data.crit_mult
			collider.take_damage(dmg, headshot)
			owner.on_dealt_damage(dmg)
			_apply_bullet_status(collider)
			_last_headshot = _last_headshot or headshot
			hit_any = true
			if pierces_left > 0:  # delici: bir sonraki düşmana geç
				pierces_left -= 1
				exclude.append(res.rid)
				from = point + dir * 0.06
				continue
			break
		break  # duvar/dünya: dur
	return hit_any


func _melee(heavy := false) -> void:
	## bıçak yakın dövüş — mermi gerektirmez (son çare)
	##  hafif (sol tık): hızlı jab, kısa bekleme
	##  ağır (sağ tık): geri çekip saplama — daha uzun bekleme/animasyon, ~1.7x hasar
	_melee_cd = HEAVY_COOLDOWN if heavy else MELEE_COOLDOWN
	_knife_swing.pitch_scale = 0.82 if heavy else randf_range(0.95, 1.08)
	_knife_swing.play()
	owner.add_recoil()  # küçük kamera vuruşu
	_knife_anim(heavy)
	if heavy:
		# ağır saldırıda vuruş geri-çekmenin sonunda iner (windup)
		await get_tree().create_timer(HEAVY_WINDUP).timeout
		if not is_instance_valid(self) or not _knife:
			return
	_melee_hit(HEAVY_DAMAGE if heavy else MELEE_DAMAGE, HEAVY_RANGE if heavy else MELEE_RANGE)


func _melee_hit(dmg_base: float, range_m: float) -> void:
	var b := ray.global_transform.basis
	var dir := -b.z.normalized()
	var from := ray.global_position
	var space := ray.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * range_m, ray.collision_mask)
	q.exclude = [owner.get_rid()]
	var res := space.intersect_ray(q)
	if res.is_empty():
		return
	var collider: Object = res.collider
	if collider != null and collider.has_method("take_damage"):
		var dmg := dmg_base
		if data.crit_chance > 0.0 and randf() < data.crit_chance:
			dmg *= data.crit_mult
		collider.take_damage(dmg)
		owner.on_dealt_damage(dmg)
		_knife_hit.play()
		hit_confirmed.emit(false)  # bıçak isabetinde de hit marker çaksın
		_spawn_impact(res.position, res.normal)


func _knife_anim(heavy: bool) -> void:
	## bıçak modelini elde saplama hareketiyle oynat (model AnimationPlayer'sız — tween ile)
	if _knife_model == null:
		return
	if _knife_tween:
		_knife_tween.kill()
	_knife_model.position = _knife_base_pos
	_knife_model.rotation = _knife_base_rot
	_knife_tween = create_tween()
	if heavy:
		# geri çekme (windup) → güçlü saplama → yavaş dönüş
		var back_pos := _knife_base_pos + Vector3(0.04, 0.05, 0.10)
		var back_rot := _knife_base_rot + Vector3(deg_to_rad(25.0), 0.0, 0.0)
		var stab_pos := _knife_base_pos + Vector3(0.0, -0.02, -0.24)
		var stab_rot := _knife_base_rot + Vector3(deg_to_rad(-32.0), 0.0, 0.0)
		_knife_tween.tween_property(_knife_model, "position", back_pos, HEAVY_WINDUP)
		_knife_tween.parallel().tween_property(_knife_model, "rotation", back_rot, HEAVY_WINDUP)
		_knife_tween.tween_property(_knife_model, "position", stab_pos, 0.08)
		_knife_tween.parallel().tween_property(_knife_model, "rotation", stab_rot, 0.08)
		_knife_tween.tween_property(_knife_model, "position", _knife_base_pos, 0.38)
		_knife_tween.parallel().tween_property(_knife_model, "rotation", _knife_base_rot, 0.38)
	else:
		# hızlı jab
		var jab_pos := _knife_base_pos + Vector3(0.0, -0.01, -0.15)
		var jab_rot := _knife_base_rot + Vector3(deg_to_rad(-18.0), 0.0, 0.0)
		_knife_tween.tween_property(_knife_model, "position", jab_pos, 0.07)
		_knife_tween.parallel().tween_property(_knife_model, "rotation", jab_rot, 0.07)
		_knife_tween.tween_property(_knife_model, "position", _knife_base_pos, 0.18)
		_knife_tween.parallel().tween_property(_knife_model, "rotation", _knife_base_rot, 0.18)


func _apply_bullet_status(enemy: Object) -> void:
	if data.burn_dps > 0.0 and enemy.has_method("ignite"):
		enemy.ignite(data.burn_dps, 3.0)
	if data.chill > 0.0 and enemy.has_method("chill"):
		enemy.chill(data.chill, 2.5)


func _muzzle_flash() -> void:
	muzzle_flash.rotation.z = randf() * TAU
	muzzle_flash.scale = Vector3.ONE * randf_range(0.8, 1.3)
	muzzle_flash.visible = true
	muzzle_light.visible = true
	await get_tree().create_timer(0.05).timeout
	muzzle_flash.visible = false
	muzzle_light.visible = false


func _spawn_impact(point: Vector3, normal: Vector3) -> void:
	var fx := IMPACT_SCENE.instantiate()
	get_tree().current_scene.add_child(fx)
	fx.global_position = point
	if normal.length() > 0.01:
		# normal tam dikeyse UP ile çakışıp uyarı verir; o durumda başka eksen kullan
		var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		fx.look_at(point + normal, up)


func reload() -> void:
	if _reloading or current_ammo == data.mag_size or reserve <= 0:
		return
	_reloading = true
	if data.reload_sound:
		$ReloadSfx.stream = data.reload_sound
		$ReloadSfx.volume_db = -6.0
	$ReloadSfx.play()
	_play_gun_anim("Reload", data.reload_time)
	reload_started.emit(data.reload_time)
	var token := _reload_token
	await get_tree().create_timer(data.reload_time).timeout
	if not is_instance_valid(self) or token != _reload_token:
		return  # bu arada slot değişti/evrim oldu — eski reload'u yok say
	var taken: int = mini(data.mag_size - current_ammo, reserve)
	current_ammo += taken
	reserve -= taken
	_reloading = false
	reload_finished.emit()
	ammo_changed.emit(current_ammo, reserve)


func _on_kill(_total: int) -> void:
	reserve += AMMO_PER_KILL
	ammo_changed.emit(current_ammo, reserve)


func _instance_model(new_data: WeaponData) -> Node3D:
	var model: Node3D = new_data.model_scene.instantiate()
	model.name = "GunModelSlot1"
	add_child(model)
	move_child(model, 0)
	model.transform = new_data.view_transform()
	_apply_gunmetal(model)
	return model


func _grab_model_anim() -> void:
	var gm: Node = _models[active_slot]
	_gun_anim = gm.find_child("AnimationPlayer", true, false) if gm else null


func _apply_gunmetal(root: Node) -> void:
	# koyu, mat silah metali — parlayıp beyaza patlamaz, net "silah" okunur
	var gunmetal := StandardMaterial3D.new()
	gunmetal.albedo_color = Color(0.11, 0.12, 0.14)
	gunmetal.metallic = 0.45
	gunmetal.metallic_specular = 0.4
	gunmetal.roughness = 0.55
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = gunmetal


func _play_gun_anim(action: String, fit_time := 0.0) -> void:
	if _gun_anim == null:
		return
	for anim_name in _gun_anim.get_animation_list():
		# "Armature|FireWBullet" gibi adlar → "|" sonrası parça aksiyonla başlasın yeter
		# (Fire → Fire/FireWBullet/FireWOBullet hepsini yakalar)
		var part: String = anim_name.substr(anim_name.rfind("|") + 1)
		if part.begins_with(action):
			_gun_anim.stop()
			if fit_time > 0.0:
				var alen := _gun_anim.get_animation(anim_name).length
				_gun_anim.speed_scale = alen / fit_time
			else:
				_gun_anim.speed_scale = 1.0
			_gun_anim.play(anim_name)
			return


func _kick() -> void:
	position.z = _base_z + 0.07
	var tween := create_tween()
	tween.tween_property(self, "position:z", _base_z, 0.08)
