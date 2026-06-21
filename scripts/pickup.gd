class_name Pickup
extends Node3D
## Yerden toplanan ganimet: altın (coin) veya XP (yeşil küre).
## Zombi ölünce saçılır, yere düşer; oyuncu pickup_radius içine girince mıknatıs
## gibi oyuncuya uçar ve toplanır.

const COIN_MODEL := "res://addons/kaykit_dungeon_remastered/assets/gltf/coin.gltf.glb"
const SND_GOLD := preload("res://assets/audio/interface/glass_001.ogg")   ## altın: parlak madeni "çın"
const SND_XP := preload("res://assets/audio/interface/pluck_002.ogg")     ## XP: yumuşak emilim "blip"

const COLLECT_DIST := 0.6
const MAGNET_ACCEL := 26.0

static var _coin_scene: PackedScene
static var _xp_mesh: SphereMesh

var kind := "gold"  ## "gold" | "xp"
var value := 5

var _vel := Vector3.ZERO
var _resting := false
var _magnet := false
var _player: Node3D
var _spin: Node3D


static func spawn(parent: Node, pos: Vector3, p_kind: String, p_value: int) -> void:
	var p = new()  # kendi sınıfı; global class cache'e bağımlı kalmamak için Pickup.new() değil
	p.kind = p_kind
	p.value = p_value
	parent.add_child(p)
	p.global_position = pos
	# hafif rastgele saçılma: yukarı + yana zıplar
	p._vel = Vector3(randf_range(-1.6, 1.6), randf_range(3.0, 4.5), randf_range(-1.6, 1.6))


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_spin = Node3D.new()
	add_child(_spin)

	if kind == "gold":
		if _coin_scene == null:
			_coin_scene = load(COIN_MODEL)
		var coin: Node3D = _coin_scene.instantiate()
		coin.scale = Vector3.ONE * 1.6
		coin.position.y = 0.12
		_spin.add_child(coin)
	else:
		if _xp_mesh == null:
			_xp_mesh = SphereMesh.new()
			_xp_mesh.radius = 0.11
			_xp_mesh.height = 0.22
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.35, 1.0, 0.4)
			mat.emission_enabled = true
			mat.emission = Color(0.3, 1.0, 0.35)
			mat.emission_energy_multiplier = 2.2
			_xp_mesh.material = mat
		var orb := MeshInstance3D.new()
		orb.mesh = _xp_mesh
		orb.position.y = 0.16
		_spin.add_child(orb)

		var light := OmniLight3D.new()
		light.light_color = Color(0.3, 1.0, 0.35)
		light.light_energy = 0.5
		light.omni_range = 1.6
		light.position.y = 0.2
		add_child(light)


func _physics_process(delta: float) -> void:
	if _player == null:
		return

	_spin.rotation.y += delta * 2.6

	var to_player := _player.global_position + Vector3(0, 0.9, 0) - global_position
	var dist := to_player.length()
	var radius: float = _player.get("pickup_radius") if _player.get("pickup_radius") != null else 2.2

	if not _magnet and dist <= radius and not _player.dead:
		_magnet = true

	if _magnet:
		# oyuncuya doğru ivmelenerek uç
		_vel = _vel.move_toward(to_player.normalized() * 14.0, MAGNET_ACCEL * delta)
		global_position += _vel * delta
		if dist <= COLLECT_DIST:
			_collect()
		return

	if _resting:
		return

	# saçılma fazı: basit yerçekimi, yere değince dur
	_vel.y -= 14.0 * delta
	global_position += _vel * delta
	if _vel.y < 0.0 and global_position.y <= 0.05:
		global_position.y = 0.05
		_resting = true
		_vel = Vector3.ZERO


func _collect() -> void:
	if kind == "gold":
		Game.add_gold(value)
	else:
		Game.add_xp(value)

	var snd := AudioStreamPlayer.new()
	snd.stream = SND_GOLD if kind == "gold" else SND_XP
	snd.volume_db = -14.0 if kind == "gold" else -13.0
	snd.pitch_scale = randf_range(1.15, 1.35) if kind == "gold" else randf_range(0.95, 1.12)
	get_tree().root.add_child(snd)
	snd.play()
	snd.finished.connect(snd.queue_free)

	queue_free()
