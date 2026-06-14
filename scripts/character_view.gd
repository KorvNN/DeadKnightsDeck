extends SubViewportContainer
## Yeşil borderli kutuda gösterilen 3D karakter: oyuncunun mevcut silahını tutan
## zombi. Alınan kartlara göre aksesuar (bomba, ikincil silah) eklenir.
## Hem ESC stat menüsünde hem ölüm/özet ekranında kullanılır.

const GUNMETAL := Color(0.12, 0.13, 0.15)


func setup(weapon: Node) -> void:
	stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)

	var cam := Camera3D.new()
	cam.fov = 36.0
	vp.add_child(cam)
	# ağaca girmeden kurulabilsin diye look_at_from_position (özet ekranı view'ı detached kurar)
	cam.look_at_from_position(Vector3(0, 1.0, 6.0), Vector3(0, 1.0, 0), Vector3.UP)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.8, 2.2, 1.8)
	rim.light_energy = 4.0
	rim.omni_range = 9.0
	rim.light_color = Color(0.7, 0.85, 1.0)
	vp.add_child(rim)

	var z: Node3D = (load("res://assets/characters/Zombie_Male.gltf") as PackedScene).instantiate()
	z.scale = Vector3.ONE * 1.02
	z.rotation.y = 0.35  # model ön yüzü +Z → kameraya dönük; hafif 3/4 açı
	vp.add_child(z)
	var ap: AnimationPlayer = z.find_child("AnimationPlayer", true, false)
	if ap != null:
		for a: String in ["Idle", "Walk_Carry", "Run_Carry"]:
			if ap.has_animation(a):
				ap.play(a)
				ap.seek(0.4, true)
				ap.pause()
				break

	_attach_weapon(vp, weapon)
	# aksesuarlar: bomba açıldıysa belde bir bomba
	var player: Node = weapon.owner if weapon != null else null
	if player != null and int(player.get("max_grenades")) > 0:
		_add_grenade(vp)
	# ikincil silah varsa sırtta
	if weapon != null and weapon.has_method("has_secondary") and weapon.has_secondary():
		_attach_back_weapon(vp, weapon)


func _attach_weapon(vp: SubViewport, weapon: Node) -> void:
	var data: WeaponData = weapon.data if weapon != null else null
	var has_model: bool = data != null and data.model_scene != null
	var scene: PackedScene = data.model_scene if has_model else load("res://assets/weapons/Pistol.fbx")
	if scene == null:
		return
	var vs: float = (data.view_scale if has_model else 0.06) * 1.0
	var vr: Vector3 = data.view_rot_deg if data != null else Vector3.ZERO
	var m: Node3D = scene.instantiate()
	m.scale = Vector3.ONE * vs
	m.rotation_degrees = vr + Vector3(0, 90, 0)  # namlu sağa/ileri
	m.position = Vector3(0.22, 0.95, 0.5)
	_darken(m)
	vp.add_child(m)


func _attach_back_weapon(vp: SubViewport, weapon: Node) -> void:
	var st = weapon.get("_slot_states")
	if st == null or st.size() < 2 or st[1] == null:
		return
	var base: WeaponData = st[1]["base"] if weapon.active_slot == 0 else (weapon.get("_slot_states")[0]["base"])
	# pasif slotun silahı (aktif olmayan)
	var other_idx := 1 - int(weapon.active_slot)
	var other = st[other_idx]
	if other == null:
		return
	var od: WeaponData = other["base"]
	if od == null or od.model_scene == null:
		return
	var m: Node3D = od.model_scene.instantiate()
	m.scale = Vector3.ONE * od.view_scale * 0.9
	m.rotation_degrees = od.view_rot_deg + Vector3(0, 90, 20)
	m.position = Vector3(-0.1, 1.15, -0.35)  # sırtta
	_darken(m)
	vp.add_child(m)


func _add_grenade(vp: SubViewport) -> void:
	var g := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	g.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.18, 0.28, 0.16)
	mm.metallic = 0.3
	g.material_override = mm
	g.position = Vector3(-0.28, 0.72, 0.34)  # belde/cepte
	vp.add_child(g)


func _darken(root: Node) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GUNMETAL
	mat.metallic = 0.5
	mat.roughness = 0.5
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = mat
