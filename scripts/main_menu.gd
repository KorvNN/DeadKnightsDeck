extends Control
## Ana menü: oyunu başlat / çık. Arka planda ateş ışığında dinlenen yalnız bir
## figürün olduğu, sisli, atmosferik 3B zindan dioraması döner.

const LEVEL_SCENE := "res://scenes/main/dungeon.tscn"
const SettingsMenuScript := preload("res://scripts/settings_menu.gd")
const KAYKIT := "res://addons/kaykit_dungeon_remastered/assets/gltf/"
const KNIGHT_MODEL := "res://assets/characters/Knight_Golden_Male.gltf"
const WEAPONS := "res://assets/weapons/"

var _cam: Camera3D
var _cam_base := Vector3(0.0, 1.7, 0.9)      ## geriden, hafif yukarıdan genel plan
var _cam_target := Vector3(0.0, 0.8, -5.2)   ## duvara dik bakış → dünya-x = ekran-x
var _fire_light: OmniLight3D
var _fire_base := 2.1
var _fig: Node3D       ## ateşin başında dinlenen figür (nefes alıp veriyormuş gibi)
var _fig_rot := 0.0
var _t := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.reset()
	Music.play_menu()
	_build()
	# debug: --stage=N ile açıldıysa menüyü atlayıp doğrudan koşuya gir
	if Game.debug_stage > 0:
		call_deferred("_on_start")


func _process(delta: float) -> void:
	_t += delta
	if _fire_light:
		# meşale titremesi: hızlı küçük + yavaş büyük dalgalanma
		var flick := sin(_t * 17.0) * 0.25 + sin(_t * 6.3) * 0.4 + randf() * 0.2
		_fire_light.light_energy = _fire_base + flick
	if _fig:
		# yorgun nefes alıp verme: çok hafif öne-arkaya salınım
		_fig.rotation_degrees.x = _fig_rot + sin(_t * 1.1) * 1.2
	if _cam:
		# çerçeveyi koruyup hafifçe salla → sahne canlı, kadraj sabit
		var off := Vector3(sin(_t * 0.16) * 0.3, sin(_t * 0.24) * 0.08, 0.0)
		_cam.look_at_from_position(_cam_base + off, _cam_target, Vector3.UP)


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_build_background()

	# sahneyi hafifçe karart → menü okunaklı kalsın, sahne görünür kalsın
	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.05, 0.26)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# --- başlık: en üstte, ortada ---
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.offset_top = 130
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.add_child(_pop(MenuUI.make_title("DEAD KNIGHT'S", 116)))
	top.add_child(_pop(MenuUI.make_title("DECK", 116)))

	var subtitle := _pop(MenuUI.make_title("DESTENİ KUR, KARANLIĞA İN", 26, Color(0.80, 0.72, 0.55)))
	subtitle.add_theme_constant_override("outline_size", 6)
	top.add_child(subtitle)

	# --- menü: ortada, dikeyde merkezin biraz altında ---
	var menu := VBoxContainer.new()
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu.position += Vector2(0, 104)  # başlığın/alt başlığın altında, net boşlukla
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 16)
	add_child(menu)
	menu.add_child(MenuUI.make_button("BAŞLA", _on_start))
	menu.add_child(MenuUI.make_button("İSTATİSTİKLER", _on_stats))
	menu.add_child(MenuUI.make_button("AYARLAR", _on_settings))
	menu.add_child(MenuUI.make_button("ÇIKIŞ", _on_quit))

	# --- alt ipucu: en altta, ortada ---
	var hint := _pop(MenuUI.make_title(
			"WASD HAREKET     •     FARE NİŞAN     •     SOL TIK ATEŞ     •     R DOLDUR     •     ESC DURAKLAT",
			16, Color(0.62, 0.64, 0.67)))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -58
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


## metni 3B sahnenin üzerinde okunaklı kılmak için koyu dış hat ekler
func _pop(label: Label) -> Label:
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 8)
	return label


# ---------- 3B arka plan dioraması ----------

func _build_background() -> void:
	var world := Node3D.new()
	world.name = "Background3D"
	add_child(world)
	move_child(world, 0)  # her şeyin arkasında kalsın

	# ortam: koyu, sıcak ışıklı, sisli
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.018, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.22, 0.20)
	env.ambient_light_energy = 0.42
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.05, 0.07)
	env.fog_light_energy = 0.6
	env.fog_density = 0.05
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	world.add_child(we)

	_cam = Camera3D.new()
	_cam.fov = 56.0
	world.add_child(_cam)
	_cam.look_at_from_position(_cam_base, _cam_target, Vector3.UP)
	_cam.make_current()

	# hafif soğuk dolgu ışığı (şekil okunsun)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 35, 0)
	key.light_color = Color(0.45, 0.5, 0.62)
	key.light_energy = 0.32
	world.add_child(key)

	# zemin (düz kareler — yön bağımsız)
	for ix in range(-2, 3):
		for iz in range(-3, 2):
			_place(world, "floor_tile_large.gltf.glb", Vector3(ix * 4.0, 0, iz * 4.0))

	# arka duvar — zombinin yaslandığı duvar (sis içinde sönükleşir)
	for ix in range(-2, 3):
		_place(world, "wall.gltf.glb", Vector3(ix * 4.0, 0, -6.0), 0.0)

	# sütunlar — duvarın iki ucunda, kadrajı çerçeveler
	_place(world, "column.gltf.glb", Vector3(-4.4, 0, -5.3))
	_place(world, "column.gltf.glb", Vector3(4.6, 0, -5.3))

	# --- ateşin başında taburede oturan yorgun şövalye ---
	# SitDown son karesinde kemik ölçümü (prob): kalça lokal (0, 0.57, -0.42),
	# ayaklar yerde (y 0.02, z -0.05). Scale 0.9 → kalça 0.51 yükseklikte,
	# root'un 0.38 gerisinde. Tabure üstü 0.5 → fig_y ≈ 0, tabure kalçanın altında
	# (yaw -20°'ye göre döndürülmüş offset: +0.13x, -0.36z).
	var fig_pos := Vector3(2.3, -0.01, -4.5)
	_place(world, "stool.gltf.glb", Vector3(fig_pos.x + 0.13, 0, fig_pos.z - 0.36), -20.0)
	_fig = (load(KNIGHT_MODEL) as PackedScene).instantiate()
	_fig.scale = Vector3.ONE * 0.9
	_fig.position = fig_pos
	# GLTF modelin doğal yüzü +Z (zombie.gd'den kanıtlı). Ateş sol-önde →
	# hafif sola dönük (-20°) ateşe bakar.
	_fig.rotation_degrees.y = -20.0
	_fig_rot = -6.0                   # geriye, duvara yaslanmış
	world.add_child(_fig)
	var fig_anim: AnimationPlayer = _fig.find_child("AnimationPlayer", true, false)
	if fig_anim and fig_anim.has_animation("SitDown"):
		var sit := fig_anim.get_animation("SitDown")
		sit.loop_mode = Animation.LOOP_NONE
		fig_anim.play("SitDown")
		fig_anim.seek(sit.length, true)  # oturmuş son karede dondur
		fig_anim.pause()

	# --- kamp ateşi: zombinin sol-önünde, kadrajda butonların sağında ---
	_build_campfire(world, Vector3(1.5, 0, -3.85))
	# çevre proplar: sol taraf boş kalmasın → kasa + fıçı + duvarda meşale
	_place(world, "crates_stacked.gltf.glb", Vector3(-3.2, 0, -4.5), 8.0)
	_place(world, "barrel_small.gltf.glb", Vector3(-2.1, 0, -4.2), -20.0)
	_place(world, "torch_lit.gltf.glb", Vector3(-1.55, 1.45, -5.45))
	var torch_light := OmniLight3D.new()
	torch_light.light_color = Color(1.0, 0.6, 0.25)
	torch_light.light_energy = 1.1
	torch_light.omni_range = 4.5
	torch_light.position = Vector3(-1.55, 2.05, -5.0)
	world.add_child(torch_light)
	_place(world, "barrel_large.gltf.glb", Vector3(4.75, 0, -4.6))

	# --- dinlenen savaşçının silahları ---
	# Tüfek + pompalı: zombinin iki yanında duvara yaslı. Prob renderdan kanıtlı:
	# uzun eksen lokal Z, rotX=90 → namlu yukarı dik, 90-18=72 → tepe duvara
	# yatık. 0.3 scale ≈ 1m gerçek boy (0.12 minicikti, o yüzden görünmüyordu).
	# rotZ=90 (roll, namlu ekseni etrafında) → yassı profil kameraya döner,
	# yoksa silah inceltilmiş çubuk gibi kenarından görünür.
	# Tüfek dik yaslanınca hep kenarından (ince çubuk) okunuyor → yere seriyoruz;
	# yatayken üstten profili net (prob renderdan kanıtlı), kamera da yukarıdan bakıyor.
	# Varilden uzak (varil yarıçapı 0.9, sol kenarı x≈3.85) → dipçik girmesin.
	# yaw 200 → namlu ucu kameraya (ekrana) dönük, ateşten uzak
	_place_weapon(world, "Rifle.fbx", Vector3(3.0, 0, -4.25), Vector3(0, 200, 0), 0.3)
	_place_weapon(world, "Shotgun.fbx", Vector3(1.55, 0, -5.25), Vector3(72, 10, 90), 0.3)
	# Tabanca: ateşin sağında açık zeminde (tabanca modeli içsel ~4x büyük → 0.07)
	# rotX=90 → yan yatar (dik durmasın/havada görünmesin), uzun ekseni lokal X
	_place_weapon(world, "Pistol.fbx", Vector3(0.8, 0.08, -3.35), Vector3(90, -35, 0), 0.07)


func _build_campfire(world: Node3D, pos: Vector3) -> void:
	# taş halkası — pürüzlü, düzensiz taşlar (küp gibi durmasın)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.17, 0.17, 0.19)
	stone.roughness = 0.95
	for i in 10:
		var ang := TAU * i / 10.0 + randf_range(-0.12, 0.12)
		var s := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.14
		bm.height = 0.24
		bm.radial_segments = 5  # az yüzey → kaba taş hissi
		bm.rings = 3
		s.mesh = bm
		s.material_override = stone
		s.scale = Vector3(randf_range(0.8, 1.3), randf_range(0.6, 0.9), randf_range(0.8, 1.3))
		s.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		s.position = pos + Vector3(cos(ang) * 0.52, 0.06, sin(ang) * 0.52)
		world.add_child(s)

	# çapraz yatık kütükler
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.24, 0.15, 0.08)
	wood.roughness = 0.95
	for i in 3:
		var logm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.06
		cyl.height = 0.8
		logm.mesh = cyl
		logm.material_override = wood
		logm.position = pos + Vector3(0, 0.1, 0)
		logm.rotation = Vector3(deg_to_rad(90), PI * i / 3.0, 0)
		world.add_child(logm)

	# alev parçacıkları
	var flame := GPUParticles3D.new()
	flame.position = pos + Vector3(0, 0.12, 0)
	flame.amount = 18
	flame.lifetime = 0.5
	flame.preprocess = 1.0
	var fm := ParticleProcessMaterial.new()
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fm.emission_box_extents = Vector3(0.14, 0.03, 0.14)
	fm.direction = Vector3(0, 1, 0)
	fm.spread = 8.0
	fm.initial_velocity_min = 0.5
	fm.initial_velocity_max = 1.0
	fm.gravity = Vector3(0, 0.5, 0)
	fm.scale_min = 0.5
	fm.scale_max = 0.85
	var fgrad := Gradient.new()
	fgrad.set_color(0, Color(1.0, 0.78, 0.32))
	fgrad.set_color(1, Color(0.7, 0.1, 0.02, 0.0))
	fgrad.add_point(0.45, Color(1.0, 0.45, 0.1, 0.85))
	var framp := GradientTexture1D.new()
	framp.gradient = fgrad
	fm.color_ramp = framp
	flame.process_material = fm
	var fquad := QuadMesh.new()
	fquad.size = Vector2(0.2, 0.2)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.vertex_color_use_as_albedo = true
	fmat.albedo_color = Color(1, 1, 1)
	fquad.material = fmat
	flame.draw_pass_1 = fquad
	world.add_child(flame)

	# titreyen sıcak ışık + yükselen közler
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.62, 0.28)
	_fire_light.light_energy = _fire_base
	_fire_light.omni_range = 9.5
	_fire_light.omni_attenuation = 1.3
	_fire_light.shadow_enabled = true
	_fire_light.position = pos + Vector3(0, 0.6, 0)
	world.add_child(_fire_light)
	_build_embers(world, pos + Vector3(0, 0.4, 0))


func _build_embers(world: Node3D, pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = 36
	p.lifetime = 2.6
	p.preprocess = 1.5

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.35
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 25.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 1.1
	mat.gravity = Vector3(0, 0.6, 0)  # közler yükselsin
	mat.scale_min = 0.4
	mat.scale_max = 1.0
	mat.color = Color(1.0, 0.55, 0.2)
	p.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_color = Color(1.0, 0.6, 0.25)
	qm.emission_enabled = true
	qm.emission = Color(1.0, 0.5, 0.15)
	qm.emission_energy_multiplier = 3.0
	quad.material = qm
	p.draw_pass_1 = quad
	world.add_child(p)


func _place(world: Node3D, file: String, pos: Vector3, yaw_deg := 0.0) -> void:
	var scene: PackedScene = load(KAYKIT + file)
	if scene == null:
		return
	var node: Node3D = scene.instantiate()
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	world.add_child(node)


func _place_weapon(world: Node3D, file: String, pos: Vector3, rot_deg: Vector3, scl := 0.05) -> void:
	var scene: PackedScene = load(WEAPONS + file)
	if scene == null:
		return
	var node: Node3D = scene.instantiate()
	node.scale = Vector3.ONE * scl
	node.position = pos
	node.rotation_degrees = rot_deg
	# parlak çelik → ateş ışığını yakalasın, sönük durmasın
	var gunmetal := StandardMaterial3D.new()
	gunmetal.albedo_color = Color(0.52, 0.55, 0.60)
	gunmetal.metallic = 0.9
	gunmetal.metallic_specular = 0.65
	gunmetal.roughness = 0.28
	gunmetal.emission_enabled = true
	gunmetal.emission = Color(0.16, 0.15, 0.14)
	gunmetal.emission_energy_multiplier = 0.5
	world.add_child(node)
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = gunmetal
		# gölge yayma kapalı → ateş ışığını boğup sahneyi karartmasınlar
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _on_start() -> void:
	Game.reset()
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _on_settings() -> void:
	var settings: CanvasLayer = SettingsMenuScript.new()
	add_child(settings)


func _on_stats() -> void:
	var runs := Game.leaderboard()
	var font: Font = load("res://assets/fonts/ui_font.tres")
	var green := MenuUI.GOLD

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = MenuUI.STEEL_PANEL
	sb.border_color = green
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(34)
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size = Vector2(560, 0)
	panel.add_child(col)

	var _lbl := func(t: String, s: int, c: Color) -> Label:
		var l := Label.new()
		l.text = t
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", s)
		l.add_theme_color_override("font_color", c)
		return l

	var title: Label = _lbl.call("İSTATİSTİKLER", 40, green)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	if runs.is_empty():
		col.add_child(_lbl.call("Henüz tamamlanmış koşu yok.\nBir koşuya başla, ölünce buraya işlenir.", 20, Color(0.7, 0.72, 0.76)))
	else:
		# --- özet ---
		var best: Dictionary = runs[0]  # stage↓ time↑ sıralı
		var total_kills := 0
		for r: Dictionary in runs:
			total_kills += int(r.get("kills", 0))
		var bt: float = best.get("time", 0.0)
		col.add_child(_lbl.call("ÖZET", 24, Color(0.85, 0.8, 0.4)))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 30)
		grid.add_theme_constant_override("v_separation", 6)
		col.add_child(grid)
		var rows := [
			["En İyi İlerleme", "Kat %d" % int(best.get("stage", 1))],
			["En İyi Süre (o kat)", "%02d:%02d" % [int(bt) / 60, int(bt) % 60]],
			["Tamamlanan Koşu", str(runs.size())],
			["Toplam Öldürme", str(total_kills)],
		]
		for rw: Array in rows:
			grid.add_child(_lbl.call(rw[0], 19, Color(0.72, 0.74, 0.78)))
			var v: Label = _lbl.call(rw[1], 19, Color(0.95, 0.95, 0.98))
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(v)

		# --- sıralama ---
		col.add_child(_lbl.call("SIRALAMA (SPEEDRUN)", 22, Color(0.85, 0.8, 0.4)))
		for i in mini(runs.size(), 8):
			var rn: Dictionary = runs[i]
			var t: float = rn.get("time", 0.0)
			var line := "%d.  Kat %d   %02d:%02d   %d kill   %s" % [
				i + 1, int(rn.get("stage", 1)), int(t) / 60, int(t) % 60,
				int(rn.get("kills", 0)), str(rn.get("date", ""))]
			col.add_child(_lbl.call(line, 16, Color(0.82, 0.84, 0.88) if i > 0 else green))

	var close := MenuUI.make_button("KAPAT", overlay.queue_free)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(close)


func _on_quit() -> void:
	get_tree().quit()
