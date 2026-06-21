extends SubViewportContainer
## Borderli kutuda gösterilen 3D karakter: ana menüdeki altın şövalye.
## Hem ESC stat menüsünde hem ölüm/özet ekranında kullanılır.
## Sade duruş — üstünde silah/aksesuar yok, dik ayakta Idle.
## Kamera figürün gerçek boyutuna (AABB) göre kurulur → model ne boyda olursa
## olsun tam kutuya sığar (kafa kesilmez, havada durmaz).

const KNIGHT_MODEL := "res://assets/characters/Knight_Golden_Male.gltf"
const FRAME_MARGIN := 1.12  # boy + üst/alt boşluk payı


func setup(_weapon: Node = null) -> void:
	stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)

	var cam := Camera3D.new()
	cam.fov = 36.0
	vp.add_child(cam)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.8, 2.2, 1.8)
	rim.light_energy = 4.0
	rim.omni_range = 9.0
	rim.light_color = Color(1.0, 0.88, 0.7)  # sıcak altın rim
	vp.add_child(rim)

	var fig: Node3D = (load(KNIGHT_MODEL) as PackedScene).instantiate()
	fig.rotation.y = 0.35  # model ön yüzü +Z → kameraya dönük; hafif 3/4 açı
	vp.add_child(fig)

	# --- figürü ölçüp kamerayı tam sığdır ---
	var aabb := _figure_aabb(fig)
	var cy: float = aabb.position.y + aabb.size.y * 0.5     # dikey merkez (ayak→kafa ortası)
	var half_h: float = aabb.size.y * 0.5 * FRAME_MARGIN
	var dist: float = half_h / tan(deg_to_rad(cam.fov) * 0.5)
	cam.look_at_from_position(Vector3(0, cy, dist), Vector3(0, cy, 0), Vector3.UP)

	var ap: AnimationPlayer = fig.find_child("AnimationPlayer", true, false)
	if ap != null:
		for a: String in ["Idle", "Walk", "Victory"]:
			if ap.has_animation(a):
				ap.play(a)
				break


## figürün tüm mesh'lerini birleştirip yerel AABB döndürür (ağaca girmeden çalışır)
func _figure_aabb(fig: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: VisualInstance3D in fig.find_children("*", "VisualInstance3D", true, false):
		var box := mi.get_aabb()
		var box_in_fig := _local_xform(mi, fig) * box
		if first:
			out = box_in_fig
			first = false
		else:
			out = out.merge(box_in_fig)
	if first:  # hiç mesh yoksa makul varsayılan (insan boyu)
		return AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.9, 0.8))
	return out


## node'un fig'e göre (fig hariç) birikmiş transformu — sahne ağacına ihtiyaç duymaz
func _local_xform(node: Node3D, fig: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != fig:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
