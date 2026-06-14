extends CharacterBody3D
## Temel düşman: yerden doğar, oyuncuyu kovalar, yakına gelince yumruk atar.

signal died

enum State { SPAWNING, CHASE, ATTACK, DEAD }

const MODELS := [
	"res://assets/characters/Zombie_Male.gltf",
	"res://assets/characters/Zombie_Female.gltf",
]
const MODEL_SCALE := 0.6
const HEAD_HEIGHT := 1.35  ## bu yüksekliğin üstüne isabet = kafa vuruşu

## mantıksal anim adı -> aday listesi: zombi modeli ilkini, KayKit iskeletleri ikincisini bulur
const ANIM_FALLBACKS := {
	"Run": ["Run", "Running_A", "Gallop", "Walk"],  # kurt: Gallop/Walk
	"Idle": ["Idle"],
	"Punch": ["Punch", "Unarmed_Melee_Attack_Punch_A", "Attack"],  # kurt: Attack
	"Slash": ["SwordSlash", "1H_Melee_Attack_Slice_Diagonal", "Attack", "Punch", "Unarmed_Melee_Attack_Punch_A"],
	"Cast": ["Spellcast_Shoot", "Spellcasting", "Shoot_OneHanded", "Punch"],
	"Death": ["Death", "Death_A"],
	"RecieveHit": ["RecieveHit", "Hit_A", "Idle_HitReact_Left"],
	"StandUp": ["StandUp", "Spawn_Ground"],  # kurt: yok → skip_rise ile atlanır
}
const PROJECTILE := preload("res://scripts/enemy_projectile.gd")

const SND_GROAN := [
	preload("res://assets/audio/zombie/zombie_groan_0.wav"),
	preload("res://assets/audio/zombie/zombie_groan_1.wav"),
	preload("res://assets/audio/zombie/zombie_groan_2.wav"),
]
const SND_ATTACK := [
	preload("res://assets/audio/zombie/zombie_attack_0.wav"),
	preload("res://assets/audio/zombie/zombie_attack_1.wav"),
]
const SND_HURT := [
	preload("res://assets/audio/zombie/zombie_hurt_0.wav"),
	preload("res://assets/audio/zombie/zombie_hurt_1.wav"),
]
const SND_DEATH := preload("res://assets/audio/zombie/zombie_death.wav")
const PICKUP := preload("res://scripts/pickup.gd")

@export var max_health := 30.0
@export var speed := 3.0
@export var attack_damage := 10.0
@export var attack_range := 1.8
@export var attack_cooldown := 1.3
@export var xp_value := 20
@export var gold_value := 6
@export var model_path := ""  ## boşsa rastgele zombi; iskelet vb. için doldur
@export var model_scale := 0.6  ## boss için büyütülür
@export var base_scale := 0.6  ## modelin "normal insan boyu" ölçeği (zombi 0.6, iskelet 0.85)
@export var is_boss := false
@export var skip_rise := false  ## true: topraktan çıkış yok (Cerberus gibi dramatik girişler)

## --- varyant sistemi (enemy_variants.gd doldurur) ---
@export var variant := "walker"
@export var behavior := "melee"  ## melee / ranged / exploder
@export var attack_logical := "Punch"  ## saldırı animasyonu (Punch/Slash/Cast)
@export var tint := Color(0, 0, 0, 0)  ## a>0 ise zombi derisini bu renge boya
# menzilli
@export var ranged_range := 18.0  ## bu mesafeye kadar ateş eder
@export var ranged_keep := 7.5  ## bundan yakına gelirse geri çekilir
@export var projectile_damage := 13.0
@export var projectile_speed := 16.0
@export var projectile_color := Color(0.65, 0.35, 1.0)
# patlayan
@export var explode_radius := 3.6
@export var explode_damage := 38.0

signal health_changed(health: float, max_health: float)

@onready var agent: NavigationAgent3D = $Agent
@onready var mount: Node3D = $ModelMount

var state := State.SPAWNING
var health: float
var anim: AnimationPlayer
var _anim := {}  ## mantıksal ad -> bu modeldeki gerçek anim adı
var player: Node3D
var _attack_timer := 0.0
var _hit_flash_timer := 0.0
var _voice: AudioStreamPlayer3D
var _groan_timer := 0.0
var _vocal := false  ## sadece bazı zombiler ara ara homurdanır

# özel mermi durumları (yakıcı/dondurucu)
var _burn_dps := 0.0
var _burn_time := 0.0
var _chill_time := 0.0
var _speed_mul := 1.0
var _status_light: OmniLight3D
var _burn_ps: CPUParticles3D
var _chill_ps: CPUParticles3D
var _ice_block: Node3D
static var _ice_mat: StandardMaterial3D


func _ready() -> void:
	health = max_health
	speed *= randf_range(0.85, 1.25)
	player = get_tree().get_first_node_in_group("player")

	# model: belirtilmişse o (iskelet vb.), yoksa rastgele erkek/dişi zombi
	var path: String = model_path if model_path != "" else MODELS[randi() % MODELS.size()]
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.scale = Vector3.ONE * model_scale
	model.rotation_degrees.y = 180.0
	mount.add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	for logical: String in ANIM_FALLBACKS:
		for cand: String in ANIM_FALLBACKS[logical]:
			if anim.has_animation(cand):
				_anim[logical] = cand
				break

	# boss: collision kapsülü model oranında büyüsün
	if model_scale > base_scale + 0.01:
		var k := model_scale / base_scale
		var cap: CapsuleShape3D = $Collision.shape.duplicate()
		cap.radius *= k
		cap.height *= k
		$Collision.shape = cap
		$Collision.position.y *= k

	if model_path == "":
		_apply_zombie_skin(model)  # yeşil tonlama sadece zombilere

	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = 3.5
	_voice.max_distance = 24.0
	_voice.volume_db = -8.0
	_voice.position.y = 1.2
	add_child(_voice)
	_vocal = randf() < 0.45
	_groan_timer = randf_range(4.0, 12.0)

	if skip_rise:
		# dramatik giriş: topraktan çıkış yok, yerinde belir ve hemen kovala
		mount.position.y = 0.0
		if _anim.has("Idle"):
			anim.play(_anim["Idle"])
		await get_tree().create_timer(0.1).timeout
		if state != State.DEAD:
			state = State.CHASE
			anim.play(_anim["Run"])
		return
	# topraktan yükselme efekti (boss daha derinden çıkar — modeli gömülü kalmasın)
	mount.position.y = -1.6 * (model_scale / base_scale)
	if _anim.has("StandUp"):
		anim.play(_anim["StandUp"])
	var rise := create_tween()
	rise.tween_property(mount, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_CUBIC)
	await rise.finished
	if state != State.DEAD:
		state = State.CHASE
		anim.play(_anim["Run"])
		anim.speed_scale = randf_range(0.9, 1.2)


func _apply_zombie_skin(model: Node3D) -> void:
	# varyant kendi rengini dayatmışsa onu, yoksa rastgele yeşilimsi/soluk zombi tonu
	var skin: Color = tint if tint.a > 0.0 else (Color(0.45, 0.55, 0.38) if randf() < 0.5 else Color(0.5, 0.5, 0.55))
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.get_surface_override_material_count():
			var base := mesh.mesh.surface_get_material(i)
			if base is StandardMaterial3D:
				var m: StandardMaterial3D = base.duplicate()
				m.albedo_color = m.albedo_color * skin
				mesh.set_surface_override_material(i, m)


func _physics_process(delta: float) -> void:
	if state == State.DEAD or player == null:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta

	_attack_timer = maxf(_attack_timer - delta, 0.0)

	# yakıcı/dondurucu mermi durumları
	if _burn_time > 0.0 or _chill_time > 0.0:
		if _burn_time > 0.0:
			_burn_time -= delta
			health -= _burn_dps * delta
			health_changed.emit(maxf(health, 0.0), max_health)
			if health <= 0.0:
				_die()
				return
		if _chill_time > 0.0:
			_chill_time -= delta
			anim.speed_scale = maxf(_speed_mul, 0.3)  # donunca animasyon da yavaşlar (görünür)
			if _chill_time <= 0.0:
				_speed_mul = 1.0
				anim.speed_scale = 1.0
		_update_status_fx()

	if _vocal and (state == State.CHASE or state == State.ATTACK):
		_groan_timer -= delta
		if _groan_timer <= 0.0:
			_groan_timer = randf_range(9.0, 20.0)
			_say(SND_GROAN, 0.82, 1.18)

	if state == State.SPAWNING:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist > 0.1:
		look_at(player.global_position * Vector3(1, 0, 1) + global_position * Vector3(0, 1, 0), Vector3.UP)

	if behavior == "ranged":
		_ranged_step(to_player, dist)
		move_and_slide()
		return

	if dist <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attack_timer == 0.0 and not player.dead:
			_attack()
	elif state != State.ATTACK or not anim.is_playing():
		state = State.CHASE
		agent.target_position = player.global_position
		var next := agent.get_next_path_position()
		var dir := next - global_position
		dir.y = 0.0
		dir = dir.normalized()
		velocity.x = dir.x * speed * _speed_mul
		velocity.z = dir.z * speed * _speed_mul
		if anim.current_animation != _anim["Run"]:
			anim.play(_anim["Run"])

	move_and_slide()


func _ranged_step(to_player: Vector3, dist: float) -> void:
	## büyücü/okçu: menzilde tut, görüş hattı varsa ateşle, çok yaklaşınca geri çekil
	velocity.x = 0.0
	velocity.z = 0.0
	if state == State.ATTACK:
		return  # büyü yaparken sabit dur
	var run: String = _anim.get("Run")
	if _attack_timer == 0.0 and dist <= ranged_range and not player.dead and _has_los():
		_shoot()
	elif dist < ranged_keep:
		var away := (-to_player).normalized()
		velocity.x = away.x * speed * _speed_mul
		velocity.z = away.z * speed * _speed_mul
		if anim.current_animation != run:
			anim.play(run)
	elif dist > ranged_range or not _has_los():
		state = State.CHASE
		agent.target_position = player.global_position
		var next := agent.get_next_path_position()
		var dir := next - global_position
		dir.y = 0.0
		dir = dir.normalized()
		velocity.x = dir.x * speed * _speed_mul
		velocity.z = dir.z * speed * _speed_mul
		if anim.current_animation != run:
			anim.play(run)
	else:
		var idle: String = _anim.get("Idle", run)
		if anim.current_animation != idle:
			anim.play(idle)


func _has_los() -> bool:
	if player == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.2, 0)
	var to := player.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)  # yalnızca dünya/duvarlar
	q.exclude = [self]
	return space.intersect_ray(q).is_empty()


func _shoot() -> void:
	state = State.ATTACK
	_attack_timer = attack_cooldown
	anim.play(_anim.get(attack_logical, _anim.get("Punch", _anim["Run"])))
	if randf() < 0.6:
		_say(SND_ATTACK, 0.9, 1.1, true)
	await get_tree().create_timer(0.55).timeout
	if state == State.DEAD or player == null:
		return
	if _has_los():
		var origin := global_position + Vector3(0, 1.2, 0)
		var target := player.global_position + Vector3(0, 1.0, 0)
		var dir := (target - origin).normalized()
		var proj := PROJECTILE.new()
		proj.damage = projectile_damage
		proj.velocity = dir * projectile_speed
		proj.color = projectile_color
		get_parent().add_child(proj)
		proj.global_position = origin + dir * 1.0
	await get_tree().create_timer(0.3).timeout
	if state == State.ATTACK:
		state = State.CHASE


func _attack() -> void:
	state = State.ATTACK
	_attack_timer = attack_cooldown
	anim.play(_anim.get(attack_logical, _anim.get("Punch", _anim["Run"])))
	if randf() < 0.5:  # her vuruşta değil — sürekli ses sinir bozucu oluyordu
		_say(SND_ATTACK, 0.95, 1.12, true)
	await get_tree().create_timer(0.45).timeout
	if state == State.DEAD or player == null:
		return
	if global_position.distance_to(player.global_position) <= attack_range + 0.5:
		player.take_damage(attack_damage, self)  # self: Diken Zırh yansıması için
	await get_tree().create_timer(0.3).timeout
	if state == State.ATTACK:
		state = State.CHASE


func ignite(dps: float, dur: float) -> void:
	if state == State.DEAD:
		return
	_burn_dps = maxf(_burn_dps, dps)
	_burn_time = maxf(_burn_time, dur)


func chill(factor: float, dur: float) -> void:
	if state == State.DEAD:
		return
	_speed_mul = 1.0 - clampf(factor, 0.0, 0.8)
	_chill_time = maxf(_chill_time, dur)


func _update_status_fx() -> void:
	var burning := _burn_time > 0.0
	var chilled := _chill_time > 0.0
	# ışık
	if _status_light == null:
		_status_light = OmniLight3D.new()
		_status_light.omni_range = 3.0
		_status_light.position.y = 1.0
		add_child(_status_light)
	_status_light.visible = burning or chilled
	if burning:
		_status_light.light_color = Color(1.0, 0.45, 0.1)
		_status_light.light_energy = 2.5 + randf() * 1.5
	elif chilled:
		_status_light.light_color = Color(0.4, 0.7, 1.0)
		_status_light.light_energy = 1.8
	# alev partikülleri (yükselen, additive, sarı→kırmızı sönen)
	if burning and _burn_ps == null:
		_burn_ps = _make_flame_ps()
	if _burn_ps != null:
		_burn_ps.emitting = burning
	# buz partikülleri (aşağı süzülen mavi-beyaz kristal)
	if chilled and _chill_ps == null:
		_chill_ps = _make_frost_ps()
	if _chill_ps != null:
		_chill_ps.emitting = chilled
	# buz küpü: düşmanı saran yarı saydam buz bloğu (içine hapsolmuş gibi)
	if chilled and _ice_block == null:
		_ice_block = _make_ice_block()
	if _ice_block != null:
		_ice_block.visible = chilled


func _make_flame_ps() -> CPUParticles3D:
	var ps := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.62, 0.62)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = load("res://assets/fx/flame.png")
	mat.vertex_color_use_as_albedo = true
	qm.material = mat
	ps.mesh = qm
	ps.amount = 20
	ps.lifetime = 0.6
	ps.local_coords = false
	ps.direction = Vector3.UP
	ps.spread = 16.0
	ps.gravity = Vector3(0, 3.2, 0)  # yükselen alev
	ps.initial_velocity_min = 0.5
	ps.initial_velocity_max = 1.3
	ps.scale_amount_min = 0.7
	ps.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.55, 1.0))
	ramp.set_color(1, Color(1.0, 0.18, 0.04, 0.0))
	ramp.add_point(0.5, Color(1.0, 0.5, 0.12, 0.85))
	ps.color_ramp = ramp
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ps.emission_box_extents = Vector3(0.35, 0.6, 0.35)
	ps.position = Vector3(0, 0.7, 0)
	add_child(ps)
	return ps


func _ice_material() -> StandardMaterial3D:
	## ışık kıran, kristalli, donuk buz — tüm düşmanlar paylaşır (ucuz)
	if _ice_mat != null:
		return _ice_mat
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.12
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.seamless = true
	ntex.as_normal_map = true
	ntex.bump_strength = 6.0
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.66, 0.85, 1.0, 0.4)
	m.roughness = 0.06
	m.metallic = 0.0
	m.metallic_specular = 0.95
	m.normal_enabled = true
	m.normal_texture = ntex
	m.refraction_enabled = true          # arka planı bük → kalın cam/buz hissi
	m.refraction_scale = 0.05
	m.refraction_texture = ntex
	m.rim_enabled = true                 # kenarlarda soğuk parlama
	m.rim = 1.0
	m.rim_tint = 0.4
	m.emission_enabled = true
	m.emission = Color(0.4, 0.7, 1.0)
	m.emission_energy_multiplier = 0.45
	_ice_mat = m
	return m


func _make_ice_block() -> Node3D:
	## kristalli buz: fazetli gövde (iç içe iki kutu) + sivri tepe + fışkıran dikenler
	## boyut görünür düşman boyuna otursun: yükseklik ~1.8×model_scale
	var root := Node3D.new()
	var ice := _ice_material()
	var h := 1.8 * model_scale * 1.12   # görünür yükseklik payı
	var wd := 0.78 * model_scale        # genişlik/derinlik

	var core := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(wd, h, wd)
	cb.material = ice
	core.mesh = cb
	root.add_child(core)

	var facet := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(wd * 0.82, h * 0.98, wd * 0.82)
	fb.material = ice
	facet.mesh = fb
	facet.rotation.y = PI / 4.0  # 45° dönük ikinci kutu → sekizgen silüet
	root.add_child(facet)

	var top := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(wd * 1.05, h * 0.3, wd * 1.05)
	pm.material = ice
	top.mesh = pm
	top.position.y = h * 0.58
	top.rotation.y = PI / 4.0
	root.add_child(top)

	var r := RandomNumberGenerator.new()
	r.seed = get_instance_id()
	for i in 5:  # yanlardan fışkıran buz dikenleri
		var spike := MeshInstance3D.new()
		var sm := PrismMesh.new()
		sm.size = Vector3(wd * 0.3, r.randf_range(0.28, 0.45) * h, wd * 0.3)
		sm.material = ice
		spike.mesh = sm
		var ang := r.randf() * TAU
		spike.position = Vector3(cos(ang) * wd * 0.5, r.randf_range(-0.15, 0.35) * h, sin(ang) * wd * 0.5)
		spike.rotation = Vector3(r.randf_range(-1.1, 1.1), ang, r.randf_range(-1.1, 1.1))
		root.add_child(spike)

	root.position.y = h * 0.5
	add_child(root)
	return root


func _make_frost_ps() -> CPUParticles3D:
	var ps := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.42, 0.42)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = load("res://assets/fx/frost.png")
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission_texture = load("res://assets/fx/frost.png")
	mat.emission = Color(0.5, 0.75, 1.0)
	mat.emission_energy_multiplier = 1.5
	qm.material = mat
	ps.mesh = qm
	ps.amount = 16
	ps.lifetime = 1.1
	ps.local_coords = false
	ps.direction = Vector3.DOWN
	ps.spread = 25.0
	ps.gravity = Vector3(0, -1.3, 0)
	ps.initial_velocity_min = 0.2
	ps.initial_velocity_max = 0.6
	ps.scale_amount_min = 0.5
	ps.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.95, 1.0, 0.0))
	ramp.set_color(1, Color(0.5, 0.78, 1.0, 0.0))
	ramp.add_point(0.4, Color(0.7, 0.9, 1.0, 0.95))
	ps.color_ramp = ramp
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = 0.55
	ps.position = Vector3(0, 1.2, 0)
	add_child(ps)
	return ps


func is_headshot(point: Vector3) -> bool:
	return point.y - global_position.y > HEAD_HEIGHT * (model_scale / base_scale)


func take_damage(amount: float, _headshot := false) -> void:
	if state == State.DEAD:
		return
	health -= amount
	health_changed.emit(maxf(health, 0.0), max_health)
	if health <= 0.0:
		_die()
	elif state != State.ATTACK:
		# kısa irkilme animasyonu
		anim.play(_anim["RecieveHit"])
		if randf() < 0.5:
			_say(SND_HURT, 0.95, 1.15, true)


func _say(streams, lo: float, hi: float, force := false) -> void:
	if _voice == null or (_voice.playing and not force):
		return
	_voice.stream = streams[randi() % streams.size()] if streams is Array else streams
	_voice.pitch_scale = randf_range(lo, hi)
	_voice.play()


func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	$Collision.set_deferred("disabled", true)
	anim.speed_scale = 1.0
	anim.play(_anim["Death"])
	_say(SND_DEATH, 0.85, 1.05, true)
	if behavior == "exploder":
		_explode()
	Game.add_kill()
	_drop_loot()
	died.emit()
	await get_tree().create_timer(2.0).timeout
	var tween := create_tween()
	tween.tween_property(mount, "position:y", -1.5, 0.8)
	tween.tween_callback(queue_free)


func _explode() -> void:
	## patlayan zombi: büyüyen ışıklı küre + yakındaki oyuncuya alan hasarı
	var col := Color(0.78, 0.9, 0.25)
	var fx := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	fx.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.albedo_color = Color(col.r, col.g, col.b, 0.55)
	m.emission = col
	m.emission_energy_multiplier = 3.0
	fx.material_override = m
	get_parent().add_child(fx)
	fx.global_position = global_position + Vector3(0, 1.0, 0)
	var lt := OmniLight3D.new()
	lt.light_color = col
	lt.light_energy = 6.0
	lt.omni_range = explode_radius * 2.0
	fx.add_child(lt)
	var t := fx.create_tween()
	t.set_parallel(true)
	t.tween_property(fx, "scale", Vector3.ONE * explode_radius * 2.0, 0.35)
	t.tween_property(m, "albedo_color:a", 0.0, 0.35)
	t.tween_property(lt, "light_energy", 0.0, 0.35)
	t.chain().tween_callback(fx.queue_free)
	if player != null and not player.dead and global_position.distance_to(player.global_position) <= explode_radius:
		player.take_damage(explode_damage)


func _drop_loot() -> void:
	## XP küresi + altın yere saçılır; oyuncu yürüyerek/mıknatısla toplar
	var origin := global_position + Vector3(0, 1.0, 0)
	var holder := get_parent()
	PICKUP.spawn(holder, origin, "xp", xp_value)
	var gold_left := gold_value
	var coins := 1 + randi() % 2 if not is_boss else 6
	for i in coins:
		var amount := gold_left / (coins - i)
		gold_left -= amount
		if amount > 0:
			PICKUP.spawn(holder, origin, "gold", amount)
