extends Node3D
## Atılabilir bomba: yerçekimiyle yay çizer, duvara çarpınca seker, fitil
## bitince patlar — çevredeki düşmanlara alan hasarı. molotov=true ise patlama
## sonrası birkaç saniye yanan bir alan bırakır (saniyelik hasar).

const GRAVITY := 18.0
const EXPLOSION := preload("res://assets/audio/sfx/explosion.wav")
const FIRE_SND := preload("res://assets/audio/sfx/fire_ignite.wav")
const THROW_SND := preload("res://assets/audio/sfx/grenade_throw.wav")
const BOUNCE_SND := [
	preload("res://assets/audio/impact/impactMetal_light_000.ogg"),
	preload("res://assets/audio/impact/impactMetal_light_002.ogg"),
	preload("res://assets/audio/impact/impactMetal_light_004.ogg"),
]
var _bounce_cd := 0.0  ## sekme sesi spam'ini önler

var velocity := Vector3.ZERO
var fuse := 1.4
var damage := 90.0
var radius := 4.5
var molotov := false

var _state := "fly"  ## fly / fire / done
var _fire_time := 0.0
var _tick := 0.0
var _mesh: MeshInstance3D
var _light: OmniLight3D


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	_mesh.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.12, 0.06) if molotov else Color(0.13, 0.15, 0.11)
	m.metallic = 0.4
	m.roughness = 0.6
	_mesh.material_override = m
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.35, 0.12)
	_light.omni_range = 2.5
	_light.light_energy = 0.0
	add_child(_light)

	_play(THROW_SND, 0.7, randf_range(0.95, 1.08))  # fırlatma hışırtısı


func _physics_process(delta: float) -> void:
	if _state != "fly":
		return
	_bounce_cd = maxf(_bounce_cd - delta, 0.0)
	fuse -= delta
	_light.light_energy = 1.6 if fmod(fuse, 0.24) < 0.1 else 0.0  # yanıp sönen fitil

	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(q)
	if hit:
		var n: Vector3 = hit.normal
		global_position = hit.position + n * 0.12
		var impact_speed := velocity.length()
		velocity = velocity.bounce(n) * 0.42  # sekme + sönüm
		if impact_speed > 3.8 and _bounce_cd <= 0.0:  # yalnız SERT çarpmada, kısık tıngırtı
			_bounce_cd = 0.25
			_play(BOUNCE_SND[randi() % BOUNCE_SND.size()],
					clampf(impact_speed / 20.0, 0.12, 0.4), randf_range(0.85, 1.05))
	else:
		global_position = to

	if fuse <= 0.0:
		_explode()


func _process(delta: float) -> void:
	if _state != "fire":
		return
	_fire_time -= delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_damage_enemies(damage * 0.16, radius)
	if _light != null:
		_light.light_energy = 2.2 + randf() * 1.2  # alev titremesi
	if _fire_time <= 0.0:
		_state = "done"
		queue_free()


func _explode() -> void:
	_mesh.visible = false
	_damage_enemies(damage, radius)
	_play(EXPLOSION, 0.5, 1.05 if not molotov else 0.8)
	_blast_flash(Color(1.0, 0.55, 0.15) if not molotov else Color(1.0, 0.4, 0.1))
	if molotov:
		_state = "fire"
		_fire_time = 4.5
		_play(FIRE_SND, 0.4, 1.0)
		_spawn_fire_patch()
	else:
		_state = "done"
		set_physics_process(false)
		await get_tree().create_timer(0.5).timeout
		queue_free()


func _damage_enemies(amount: float, r: float) -> void:
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		var d := global_position.distance_to(e.global_position)
		if d <= r:
			var falloff: float = 1.0 - (d / r) * 0.5  # merkez tam, kenar yarı
			e.take_damage(amount * falloff)


func _blast_flash(col: Color) -> void:
	## büyüyen ışıklı küre — grenade node'undan bağımsız, kendini siler
	var fx := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	fx.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.albedo_color = Color(col.r, col.g, col.b, 0.7)
	m.emission = col
	m.emission_energy_multiplier = 4.0
	fx.material_override = m
	get_parent().add_child(fx)
	fx.global_position = global_position
	var lt := OmniLight3D.new()
	lt.light_color = col
	lt.light_energy = 8.0
	lt.omni_range = radius * 2.2
	fx.add_child(lt)
	var t := fx.create_tween()
	t.set_parallel(true)
	t.tween_property(fx, "scale", Vector3.ONE * radius * 1.8, 0.32)
	t.tween_property(m, "albedo_color:a", 0.0, 0.32)
	t.tween_property(lt, "light_energy", 0.0, 0.32)
	t.chain().tween_callback(fx.queue_free)

	# yere yayılan şok dalgası halkası
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.5
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.emission_enabled = true
	rm.albedo_color = Color(1.0, 0.8, 0.4, 0.8)
	rm.emission = Color(1.0, 0.7, 0.3)
	rm.emission_energy_multiplier = 3.0
	ring.material_override = rm
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.15, 0)
	var rt := ring.create_tween()
	rt.set_parallel(true)
	rt.tween_property(ring, "scale", Vector3.ONE * radius * 2.4, 0.35)
	rt.tween_property(rm, "albedo_color:a", 0.0, 0.35)
	rt.chain().tween_callback(ring.queue_free)

	# saçılan kıvılcım/duman partikülleri (tek seferlik patlama)
	var ps := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.28, 0.28)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.albedo_texture = load("res://assets/fx/flame.png")
	pm.vertex_color_use_as_albedo = true
	qm.material = pm
	qm.size = Vector2(0.7, 0.7)
	ps.mesh = qm
	ps.emitting = true
	ps.one_shot = true
	ps.explosiveness = 0.92
	ps.amount = 36
	ps.lifetime = 0.7
	ps.local_coords = false
	ps.direction = Vector3.UP
	ps.spread = 85.0
	ps.gravity = Vector3(0, -7.0, 0)
	ps.initial_velocity_min = 4.0
	ps.initial_velocity_max = 11.0
	ps.scale_amount_min = 0.7
	ps.scale_amount_max = 1.6
	var pr := Gradient.new()
	pr.set_color(0, Color(1.0, 0.95, 0.55, 1.0))
	pr.set_color(1, Color(0.5, 0.12, 0.04, 0.0))
	pr.add_point(0.45, Color(1.0, 0.45, 0.1, 0.85))
	ps.color_ramp = pr
	get_parent().add_child(ps)
	ps.global_position = global_position + Vector3(0, 0.3, 0)
	ps.get_tree().create_timer(1.0).timeout.connect(ps.queue_free)


func _spawn_fire_patch() -> void:
	## yere yapışık titreyen turuncu disk (görsel; hasarı _process veriyor)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.08
	disc.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.albedo_color = Color(1.0, 0.45, 0.1, 0.55)
	m.emission = Color(1.0, 0.4, 0.08)
	m.emission_energy_multiplier = 2.5
	disc.material_override = m
	add_child(disc)
	disc.position.y = 0.05
	var t := disc.create_tween()
	t.tween_interval(_fire_time - 0.8)
	t.tween_property(m, "albedo_color:a", 0.0, 0.8)


func _play(stream: AudioStream, vol_lin: float, pitch: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = 6.0
	p.max_distance = 40.0
	p.volume_db = linear_to_db(vol_lin)
	p.pitch_scale = pitch
	get_parent().add_child(p)
	p.global_position = global_position
	p.play()
	p.finished.connect(p.queue_free)
