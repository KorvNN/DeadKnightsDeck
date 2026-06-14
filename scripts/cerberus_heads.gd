extends Node3D
## Cerberus görsel katmanı: Quaternius Kurt modelini cehennem köpeğine çevirir.
## - gövde + orta kafa: kurt modeli (animasyonlu), koyu kürk + kızıl kor
## - 3 kafa için kızıl gözler + ağız ateşi; 2 yan kafa primitiflerden stilize
## Yön modelin baktığı yönden alınır (bone yerel ekseni güvenilmez/ölçekli),
## konum ise "Head" bone'unun dünya konumundan (animasyonla birlikte hareket eder).
## Kullanım: Node3D oluştur, modelle KARDEŞ olarak ekle, setup(model, scale) çağır.

const FUR := Color(0.07, 0.055, 0.065)
const EYE := Color(1.0, 0.25, 0.08)

var _model: Node3D
var _head_bone: Node3D
var _scale := 0.7
var _snout_sign := 1.0  ## burun yönü = model.basis.z * sign (180° dönük modelde -1)
var _parts := []   # [{node, lateral, fwd, up, yaw}]
var _bob := 0.0
var _fires: Array[CPUParticles3D] = []        # faz 2 öfkesinde büyür
var _eye_mats: Array[StandardMaterial3D] = []  # faz 2 öfkesinde parlar
var _body_mats: Array[StandardMaterial3D] = [] # faz 2'de daha kızıl kor


func setup(model: Node3D, world_scale: float, snout_sign := 1.0) -> void:
	_model = model
	_scale = world_scale
	_snout_sign = snout_sign
	_head_bone = model.find_child("Head", true, false)
	_darken_body()
	# orta kafa: kurt kafasının üstüne sadece gözler + ağız ateşi (en yüksek, en önde)
	var center := _make_head(false)
	add_child(center)
	_parts.append({"node": center, "lateral": 0.0, "fwd": 0.30, "up": 0.12, "yaw": 0.0})
	# iki yan kafa: tam primitif kafa, AŞAĞI-DIŞA açılı (yelpaze) → ayrı boyunlar
	for sgn in [-1.0, 1.0]:
		var h := _make_head(true)
		add_child(h)
		_parts.append({"node": h, "lateral": sgn * 0.66, "fwd": -0.04,
				"up": -0.10, "yaw": sgn * deg_to_rad(40.0)})


func _darken_body() -> void:
	var mesh: MeshInstance3D = _model.find_child("Wolf", true, false)
	if mesh == null:
		return
	for i in mesh.mesh.get_surface_count():
		var m := StandardMaterial3D.new()
		m.albedo_color = FUR
		m.roughness = 0.85
		m.metallic = 0.0
		m.emission_enabled = true
		m.emission = Color(0.3, 0.05, 0.02)
		m.emission_energy_multiplier = 0.18
		mesh.set_surface_override_material(i, m)
		_body_mats.append(m)


func _make_head(full: bool) -> Node3D:
	## yerel +Z = burun yönü. full=false: sadece göz+ateş (kurt kafasının üstüne).
	var head := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FUR
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.05, 0.02)
	mat.emission_energy_multiplier = 0.18

	if full:
		# boyun bağlantısı: kafadan geriye (gövdeye doğru) uzanır → "ayrı boyun" hissi
		var neck := _box(mat, Vector3(0.22, 0.24, 0.62), Vector3(0, -0.07, -0.38))
		head.add_child(neck)
		# kafatası
		head.add_child(_box(mat, Vector3(0.30, 0.30, 0.30), Vector3(0, 0, 0)))
		# kaş çıkıntısı (kızgın hat)
		head.add_child(_box(mat, Vector3(0.30, 0.09, 0.12), Vector3(0, 0.11, 0.15)))
		# burun köprüsü (uzun)
		head.add_child(_box(mat, Vector3(0.18, 0.15, 0.40), Vector3(0, -0.01, 0.31)))
		# burun ucu (daralan)
		head.add_child(_box(mat, Vector3(0.13, 0.12, 0.13), Vector3(0, -0.03, 0.54)))
		# alt çene
		head.add_child(_box(mat, Vector3(0.16, 0.07, 0.34), Vector3(0, -0.12, 0.29)))
		# sivri kulaklar
		for ex in [-1.0, 1.0]:
			var ear := MeshInstance3D.new()
			var eb := PrismMesh.new()
			eb.size = Vector3(0.11, 0.26, 0.06)
			ear.mesh = eb
			ear.material_override = mat
			ear.position = Vector3(ex * 0.11, 0.24, -0.05)
			ear.rotation = Vector3(-0.18, 0, ex * -0.30)
			head.add_child(ear)

	# gözler (yerel öne/yukarı)
	var eye_z := 0.22 if full else 0.06
	for ex in [-1.0, 1.0]:
		var eye := _make_eye()
		eye.position = Vector3(ex * 0.10, 0.05 if full else 0.03, eye_z)
		head.add_child(eye)

	# ağız ateşi (yerel öne — burun ucunda)
	var fire := _make_fire(0.42 if full else 0.42)
	fire.position = Vector3(0, -0.07 if full else -0.05, 0.56 if full else 0.22)
	head.add_child(fire)
	return head


func _box(mat: StandardMaterial3D, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	return mi


func _make_eye() -> MeshInstance3D:
	var eye := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.032
	sm.height = 0.064
	eye.mesh = sm
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = EYE
	em.emission_enabled = true
	em.emission = EYE
	em.emission_energy_multiplier = 2.4
	eye.material_override = em
	_eye_mats.append(em)
	var l := OmniLight3D.new()
	l.light_color = EYE
	l.light_energy = 0.6
	l.omni_range = 0.6
	eye.add_child(l)
	return eye


func _make_fire(scale_amt: float) -> CPUParticles3D:
	var ps := CPUParticles3D.new()
	ps.amount = 10
	ps.lifetime = 0.45
	ps.local_coords = false
	ps.direction = Vector3(0, 0.7, 1.0)
	ps.spread = 14.0
	ps.gravity = Vector3(0, 0.5, 0)
	ps.initial_velocity_min = 0.25 * scale_amt
	ps.initial_velocity_max = 0.7 * scale_amt
	ps.scale_amount_min = 0.35 * scale_amt
	ps.scale_amount_max = 0.8 * scale_amt
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	ramp.set_color(1, Color(0.9, 0.12, 0.03, 0.0))
	ramp.add_point(0.5, Color(1.0, 0.4, 0.08, 0.85))
	ps.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = load("res://assets/fx/flame.png")
	ps.mesh = QuadMesh.new()
	(ps.mesh as QuadMesh).size = Vector2(0.26, 0.26)
	ps.material_override = mat
	_fires.append(ps)
	return ps


func enrage() -> void:
	## faz 2: üç kafanın ateşi büyür, gözler kor gibi parlar, gövde kızıllaşır
	for f in _fires:
		f.amount = int(f.amount * 1.8)
		f.lifetime *= 1.25
		f.initial_velocity_min *= 1.4
		f.initial_velocity_max *= 1.4
		f.scale_amount_min *= 1.55
		f.scale_amount_max *= 1.55
		(f.mesh as QuadMesh).size *= 1.5
	for em in _eye_mats:
		em.emission_energy_multiplier = 5.0
		em.albedo_color = Color(1.0, 0.4, 0.1)
		em.emission = Color(1.0, 0.4, 0.1)
	for bm in _body_mats:
		bm.emission = Color(0.55, 0.1, 0.03)
		bm.emission_energy_multiplier = 0.4


func _process(delta: float) -> void:
	if _head_bone == null or _model == null:
		return
	_bob += delta
	var origin := _head_bone.global_transform.origin
	# yön: modelin baktığı yön (+Z yerel), yataya indirilmiş
	var mz := _model.global_transform.basis.z * _snout_sign
	var fwd := Vector3(mz.x, 0.0, mz.z)
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, 1)
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	for p in _parts:
		var node: Node3D = p["node"]
		var yaw: float = p["yaw"]
		var lateral: float = p["lateral"]
		var fwd_off: float = p["fwd"]
		var up_off: float = p["up"]
		var bob := sin(_bob * 1.8 + lateral * 6.0) * 0.02 * _scale
		var pos := origin + fwd * (fwd_off * _scale) \
				+ right * (lateral * _scale) \
				+ Vector3(0, up_off * _scale + bob, 0)
		var dir := fwd.rotated(Vector3.UP, yaw).normalized()
		var xd := Vector3.UP.cross(dir).normalized()
		var yd := dir.cross(xd)
		node.global_position = pos
		var hs: float = 1.05 if absf(yaw) > 0.01 else 1.0  # yan kafalar hafif iri
		node.global_transform.basis = Basis(xd, yd, dir).scaled(Vector3.ONE * (_scale * hs))
