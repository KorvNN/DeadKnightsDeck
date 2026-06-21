extends Node3D
## Menzilli düşman mermisi (büyü/ok): ileri uçar, oyuncuya değince hasar verir,
## duvara çarpınca söner. Görselini kendi kurar — sahne dosyası gerekmez.

const SKULL_MODEL := preload("res://addons/kaykit_halloween_bits/Assets/gltf/skull.gltf")
const POTION_MODEL := preload("res://addons/kaykit_dungeon_remastered/Assets/gltf/bottle_A_green.gltf.glb")

var velocity := Vector3.ZERO
var damage := 12.0
var life := 7.0           ## yaşam süresi (uzun → karşıya kadar gider, hemen yok olmaz)
var color := Color(0.6, 0.3, 1.0)
var style := "orb"        ## görsel: "orb" (küre) / "skull" (kafatası) / "potion" (zehir şişesi)

var _player: Node3D
var _light: OmniLight3D
var _spin: Node3D         ## model stillerinde (skull/potion) dönen gövde


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")

	if style == "skull" or style == "potion":
		_spin = Node3D.new()
		add_child(_spin)
		var model: Node3D = (SKULL_MODEL if style == "skull" else POTION_MODEL).instantiate()
		model.scale = Vector3.ONE * (1.2 if style == "skull" else 2.6)
		# skill rengiyle parlama → karanlıkta net okunur, tehlike hissi verir
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(0.92, 0.93, 0.85) if style == "skull" else Color(0.5, 0.85, 0.35)
		glow.emission_enabled = true
		glow.emission = color
		glow.emission_energy_multiplier = 0.9 if style == "skull" else 1.6
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = glow
		_spin.add_child(model)
	else:
		var mesh := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.32
		mesh.mesh = sph
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.albedo_color = color
		m.emission = color
		m.emission_energy_multiplier = 4.0
		mesh.material_override = m
		add_child(mesh)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 2.2
	_light.omni_range = 4.5
	add_child(_light)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_pop()
		return
	if _spin != null:  # uçan kafatası kendi etrafında dönsün (canlı görünüm)
		_spin.rotation.y += delta * 6.0
		_spin.rotation.x += delta * 3.0

	var from := global_position
	var to := from + velocity * delta

	# duvar/zemin kontrolü (yalnızca dünya = layer 1)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(q)
	if hit:
		global_position = hit.position
		_pop()
		return

	global_position = to

	if _player != null and not _player.dead:
		var head := _player.global_position + Vector3(0, 1.0, 0)
		if global_position.distance_to(head) < 0.85:
			_player.take_damage(damage)
			_pop()


func _pop() -> void:
	set_physics_process(false)
	var t := create_tween()
	if _light != null:
		t.tween_property(_light, "light_energy", 0.0, 0.15)
	t.tween_callback(queue_free)
