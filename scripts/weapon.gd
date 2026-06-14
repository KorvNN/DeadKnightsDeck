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

const IMPACT_SCENE := preload("res://scenes/fx/impact.tscn")
const AMMO_PER_KILL := 3  ## her öldürmede yedeğe dönen mermi

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


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or owner.dead:
		return

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
		switch_slot()


# ---- kart arayüzü ----

func add_weapon_mod(mul: Dictionary, add: Dictionary) -> void:
	weapon_mods.append({"mul": mul, "add": add})
	_recompute()


func equip(new_base: WeaponData) -> void:
	## evrim: yeni silah HEP slot 1'e gelir (tabanca slot 0'da sabit kalır)
	_cancel_reload()
	_save_active()
	if _models[1] != null:
		_models[1].queue_free()
		_models[1] = null
	_slot_states[1] = {"base": new_base.duplicate(), "ammo": -1, "reserve": -1}
	active_slot = 1
	_activate_slot()


func switch_slot() -> void:
	if _slot_states[1] == null:
		return  # henüz ikinci silah yok
	_cancel_reload()
	_save_active()
	active_slot = 1 - active_slot
	_activate_slot()
	$DryFireSfx.play()  # hafif mekanik tık: silah değişti hissi


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
