extends CharacterBody3D
## First-person oyuncu: hareket, can, kart statları (hız, can çalma).

signal health_changed(health: float, max_health: float)
signal shield_changed(shield: float, max_shield: float)
signal stamina_changed(stamina: float, max_stamina: float)
signal grenades_changed(count: int, maxc: int)
signal hurt
signal died

const GRENADE := preload("res://scripts/grenade.gd")

@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export var max_health := 100.0

const FOOTSTEPS := [
	preload("res://assets/audio/impact/footstep_concrete_000.ogg"),
	preload("res://assets/audio/impact/footstep_concrete_001.ogg"),
	preload("res://assets/audio/impact/footstep_concrete_002.ogg"),
	preload("res://assets/audio/impact/footstep_concrete_003.ogg"),
	preload("res://assets/audio/impact/footstep_concrete_004.ogg"),
]

var health: float
var max_shield := 0.0  ## Kalkan kartıyla açılır; hasarı candan önce emer
var shield := 0.0
var max_stamina := 100.0
var stamina := 100.0
var lifesteal := 0.0  ## kartlarla artar; verilen hasarın bu oranı kadar iyileşir
var thorns := 0.0  ## Diken Zırh kartı: vuran zombiye bu kadar hasar yansır
var pickup_radius := 2.2  ## yerdeki altın/XP'nin mıknatıslanma mesafesi (Mıknatıs kartıyla artar)
var dead := false

## --- atılabilir bomba (G) — varsayılan KAPALI, "El Bombası" kartıyla açılır ---
var grenades := 0
var max_grenades := 0
var grenade_damage := 90.0
var grenade_radius := 4.5
var molotov_level := 0  ## >0 ise bombalar yakıcı (alan ateşi bırakır)
const NADE_REGEN := 16.0  ## boş bombanın dolması için saniye
var _nade_cd := 0.0

const SPRINT_DRAIN := 16.0     ## koşarken stamina/sn
const STAMINA_REGEN := 13.0    ## dinlenirken stamina/sn
const SHIELD_REGEN := 5.0      ## kalkan/sn (hasarsız bekleme sonrası)
const SHIELD_DELAY := 6.0      ## kalkanın dolmaya başlaması için hasarsız süre
var _winded := false           ## stamina dibe vurdu; %30'a kadar koşu kilitli
var _shield_cd := 0.0          ## son hasardan beri geçen süre

var _step_player: AudioStreamPlayer
var _step_dist := 0.0  ## son adımdan beri yürünen mesafe

@onready var camera: Camera3D = %Camera

var _aim_pitch := 0.0              ## mouse ile kontrol edilen dikey bakış
var _recoil := Vector2.ZERO        ## geçici recoil ofseti (pitch, yaw)
var _shake := 0.0                  ## anlık sarsıntı şiddeti


func _ready() -> void:
	health = max_health
	stamina = max_stamina
	# HUD (çocuk node) bizden ÖNCE ready olur ve o anda statlar 0 okur —
	# gerçek değerleri sinyallerle duyur
	refresh_stats()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	_step_player = AudioStreamPlayer.new()
	_step_player.volume_db = -15.0
	add_child(_step_player)


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_aim_pitch = clampf(_aim_pitch - event.relative.y * mouse_sensitivity, -PI / 2.0, PI / 2.0)


func _process(delta: float) -> void:
	# recoil yumuşakça sıfıra döner
	_recoil = _recoil.lerp(Vector2.ZERO, delta * 8.0)
	_shake = move_toward(_shake, 0.0, delta * 3.0)
	var shake_off := Vector2(randf() - 0.5, randf() - 0.5) * _shake
	camera.rotation.x = _aim_pitch + _recoil.y + shake_off.y
	camera.rotation.z = _recoil.x * 0.3 + shake_off.x


func add_recoil() -> void:
	_recoil += Vector2(randf_range(-0.006, 0.006), 0.018)
	_shake = minf(_shake + 0.05, 0.12)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if dead:
		velocity.x = move_toward(velocity.x, 0.0, walk_speed)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed)
		move_and_slide()
		return

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# bomba: zamanla yavaşça dolar, G ile atılır
	if grenades < max_grenades:
		_nade_cd += delta
		if _nade_cd >= NADE_REGEN:
			_nade_cd = 0.0
			grenades += 1
			grenades_changed.emit(grenades, max_grenades)
	if Input.is_action_just_pressed("throw_grenade") and grenades > 0:
		_throw_grenade()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# stamina: koşu tüketir, dinlenme doldurur; dibe vurunca %30'a kadar koşu kilitli
	if _winded and stamina >= max_stamina * 0.3:
		_winded = false
	var sprinting: bool = Input.is_action_pressed("sprint") \
			and direction != Vector3.ZERO and not _winded and stamina > 0.0
	if sprinting:
		stamina = maxf(stamina - SPRINT_DRAIN * delta, 0.0)
		if stamina == 0.0:
			_winded = true
			sprinting = false
		stamina_changed.emit(stamina, max_stamina)
	elif stamina < max_stamina:
		stamina = minf(stamina + STAMINA_REGEN * delta, max_stamina)
		stamina_changed.emit(stamina, max_stamina)
	var speed := sprint_speed if sprinting else walk_speed

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	_update_footsteps(delta)

	# kalkan: hasarsız geçen süre sonrası yavaşça dolar
	if max_shield > 0.0 and shield < max_shield:
		_shield_cd += delta
		if _shield_cd >= SHIELD_DELAY:
			shield = minf(shield + SHIELD_REGEN * delta, max_shield)
			shield_changed.emit(shield, max_shield)


func _update_footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed < 1.0:
		_step_dist = 1.8  # durunca: bir sonraki adım hemen çalsın
		return
	_step_dist += hspeed * delta
	if _step_dist >= 2.4:
		_step_dist = 0.0
		_step_player.stream = FOOTSTEPS[randi() % FOOTSTEPS.size()]
		_step_player.pitch_scale = randf_range(0.88, 1.12)
		_step_player.play()


func take_damage(amount: float, attacker: Node3D = null) -> void:
	if dead or get_tree().paused:
		return  # kart seçimi / ESC menüsü açıkken hasar alma
	_shield_cd = 0.0
	if thorns > 0.0 and attacker != null and attacker.has_method("take_damage"):
		attacker.take_damage(thorns)
	if shield > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
		shield_changed.emit(shield, max_shield)
	if amount > 0.0:
		health = maxf(health - amount, 0.0)
		health_changed.emit(health, max_health)
	hurt.emit()
	if health == 0.0:
		_die()


func heal(amount: float) -> void:
	if dead:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


func on_dealt_damage(amount: float) -> void:
	if lifesteal > 0.0:
		heal(amount * lifesteal)


func _throw_grenade() -> void:
	grenades -= 1
	grenades_changed.emit(grenades, max_grenades)
	var g := GRENADE.new()
	g.damage = grenade_damage
	g.radius = grenade_radius
	g.molotov = molotov_level > 0
	var fwd := -camera.global_transform.basis.z
	get_parent().add_child(g)
	g.global_position = camera.global_position + fwd * 0.6
	g.velocity = fwd * 14.0 + Vector3.UP * 3.0 + velocity * 0.4  # ileri + hafif yukarı + momentum


func refresh_stats() -> void:
	## kart seçimi sonrası: yeni kalkan kapasitesi hemen dolar (seçim anında ödül hissi)
	shield = max_shield
	grenades = max_grenades  # bombalar da dolar
	health_changed.emit(health, max_health)
	shield_changed.emit(shield, max_shield)
	stamina_changed.emit(stamina, max_stamina)
	grenades_changed.emit(grenades, max_grenades)


func _die() -> void:
	dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	died.emit()
