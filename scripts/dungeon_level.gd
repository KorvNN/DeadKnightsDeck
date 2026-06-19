extends Node3D
## Kat üreticisi — biome'a göre üç mod:
##  - garden (kat 1-5): açık havada çim/çit (hedge) labirenti, gün ışığı
##  - garden_boss (kat 6): şato bahçesi arenası, Çürümüş Bahçıvan boss'u
##  - castle (kat 7-11): mevcut şato zindanı (KayKit)
## Çıkış portalı kilitli başlar: kat kotası kadar zombi ölünce açılır.

const CELL := 4.0
const WALL_H := 4.0
const HEDGE_H := 3.7  ## zıplayınca üstünden çıkış görünmesin diye yüksek
const ARENA_CELLS := 9  ## boss arenası kenarı (hücre; tek sayı → kapı tam ortada)
const KAYKIT := "res://addons/kaykit_dungeon_remastered/assets/gltf/"
const HW := "res://addons/kaykit_halloween_bits/Assets/gltf/"  ## mezarlık/bahçe süs paketi
const SKELETON_MINION := "res://addons/kaykit_character_pack_skeletons/Characters/gltf/Skeleton_Minion.glb"
const SKELETON_WARRIOR := "res://addons/kaykit_character_pack_skeletons/Characters/gltf/Skeleton_Warrior.glb"
const SKELETON_BASE_SCALE := 0.85  ## iskelet modeli bu ölçekte ~1.85m (zombi 0.6 gibi)
const CHEST_SCRIPT := preload("res://scripts/chest.gd")
const ENEMY_VARIANTS := preload("res://scripts/enemy_variants.gd")
const RUN_SUMMARY := preload("res://scripts/run_summary.gd")
const CERBERUS_WOLF := "res://assets/characters/Cerberus_Wolf.glb"
const CERBERUS_HEADS := preload("res://scripts/cerberus_heads.gd")
const SND_BOSS_ROAR := preload("res://assets/audio/sfx/boss_roar.wav")        # iskelet: kemik kükremesi
const SND_BOSS_RUMBLE := preload("res://assets/audio/sfx/boss_rumble.wav")    # iskelet: yer gümbürtüsü
const SND_BOSS_GROAN := preload("res://assets/audio/sfx/boss_groan.wav")      # bahçıvan: ıslak çürük inilti
const SND_BOSS_SQUELCH := preload("res://assets/audio/sfx/boss_squelch.wav")  # bahçıvan: çamur/filiz patlaması
# (iskelet dövüş sesleri zombie.gd'de model yolundan otomatik atanır — boss + normal iskeletler)

const OUTER_TREES := [
	"tree_pine_yellow_large.gltf", "tree_pine_orange_large.gltf",
	"tree_pine_orange_medium.gltf", "tree_dead_large.gltf", "tree_dead_medium.gltf",
]
const NATURE := "res://addons/kenney_nature_kit/"  ## çim/çiçek/mantar modelleri (CC0)

const FLOOR_PIECES := {
	"floor_tile_large.gltf.glb": 90,
	"floor_tile_large_rocks.gltf.glb": 10,
}
const WALL_PIECES := {
	"wall.gltf.glb": 90,
	"wall_cracked.gltf.glb": 10,
}
const PROP_PIECES := [
	"barrel_large.gltf.glb", "box_stacked.gltf.glb", "crates_stacked.gltf.glb",
]
const MAX_TORCHES := 30

@export var zombie_scene: PackedScene
@export var maze_w := 9
@export var maze_h := 9

@onready var nav: NavigationRegion3D = $NavRegion

var maze := {}
var rng := RandomNumberGenerator.new()
var player: Node3D
var _biome := "castle"
var _alive := 0
var _stage_over := false
var _torch_count := 0
var _piece_cache := {}
var _stage_label: Label
var _stage_title: Label  ## kat giriş başlığı ("ŞATO BAHÇESİ — BÖLÜM 1" vb.)
var _quota_label: Label  ## kat başlığı altında zombi kotası ("ZOMBİ 3/12")
var _fade: ColorRect
var _intro_active := false  ## açılış hikâye ekranı gösteriliyor
var _intro_can_dismiss := false  ## E ancak "[E] DEVAM" belirince çalışır (spam koruması)
var _story_layer: CanvasLayer
var _story_tween: Tween
var _story_flag := "intro_shown"  ## dismiss'te Game'de işaretlenecek bayrak
var _exit_near := false
var _exit_prompt: Label3D
var _exit_screen_prompt: Control
var _exit_action_label: Label
var _exit_open := Vector3(0, 0, 1)   ## koridorun çıkışa bağlandığı açık yön
var _exit_back := Vector3(0, 0, -1)  ## kemerin/odanın açıldığı arka yön

# çıkış kilidi: kota kadar zombi ölmeden portal açılmaz
var _kills_needed := 0
var _kills_done := 0
var _exit_unlocked := false
var _ring_mat: StandardMaterial3D
var _disc_mat: StandardMaterial3D
var _portal_light: OmniLight3D

# boss arenası
var _boss: Node3D
var _boss_phase2 := false
var _cerb_heads: Node3D  ## Cerberus kafa katmanı (faz 2 öfke için)
var _boss_bar: ProgressBar
var _boss_name := ""
var _arena_size := Vector2.ZERO  ## boss alanının (x, z) boyutu
var _gate_pos := Vector3.ZERO    ## boss ölünce portalın doğacağı nokta
var _gate_leaves: Array[Node3D] = []  ## kemer kapı kanatları (arkadan kapanır)
var _gate_leaf_cols: Array[Node] = []
var _gate_body: StaticBody3D
var _gate_closed := false
var _chest_cells := {}           ## sandık konan çıkmaz hücreler (süs çakışmasın)
var _choice_made := false        ## cennet/cehennem portalı seçildi mi
var _afterlife_done := false     ## cennet/cehennem platformunda bitiş tetiklendi mi
var _portal_near := ""           ## yakınında olunan portalın türü (heaven/hell), "" = uzak
var _hedge_mats: Array[StandardMaterial3D] = []
var _nature_mesh_cache := {}  ## Kenney nature kit: dosya -> Mesh (MultiMesh için)
var _grass_mat: StandardMaterial3D  ## çim zemin materyali (koridor zemini de kullanır)
var _hedge_top_xforms: Array[Transform3D] = []   ## çit üstünden taşan öbekler
var _hedge_face_xforms: Array[Transform3D] = []  ## çit yüzünden fışkıran filizler


func _ready() -> void:
	if Game.run_seed == 0:
		Game.run_seed = randi()
	rng.seed = Game.run_seed + Game.stage * 7919
	Music.play_game()
	_biome = Game.biome()

	player = get_tree().get_first_node_in_group("player")
	player.died.connect(_on_player_died)

	# el feneri zindan içindir; gün ışığında yakındaki açık taşları patlatıp
	# gökyüzüne karıştırıyor (kemer görünmezliği bu yüzdendi)
	if _biome == "garden" or _biome == "garden_boss":
		var lantern := player.get_node_or_null("Camera/Lantern")
		if lantern != null:
			lantern.visible = false

	if _biome == "garden_boss":
		_build_boss_arena()
		return
	if _biome == "castle_boss":
		_build_castle_hall()
		return
	if _biome == "cerberus":
		_build_cerberus_arena()
		return
	if _biome == "heaven" or _biome == "hell":
		_build_afterlife(_biome)
		return

	var grow := mini(Game.biome_stage() - 1, 4) + (2 if _biome == "castle" else 0)
	maze = MazeGen.generate(maze_w + grow, maze_h + grow, rng.randi(), 0.25)
	if _biome == "castle":
		maze.v_walls[0][0] = false  # batı sınırı: şato giriş kapısı buraya açılır

	player.global_position = _cell_center(Vector2i.ZERO) + Vector3(0, 0.2, 0)
	for d: Vector2i in MazeGen.DIRS:
		var n: Vector2i = Vector2i.ZERO + d
		if n.x >= 0 and n.x < int(maze.w) and n.y >= 0 and n.y < int(maze.h) \
				and not MazeGen.has_wall_between(maze.v_walls, maze.h_walls, Vector2i.ZERO, n):
			player.rotation.y = atan2(-float(d.x), -float(d.y))
			break

	_kills_needed = clampi(6 + 2 * Game.stage, 8, 22)
	Game.start_timer()  # speedrun süresi oyun (dungeon) yüklenince işler

	if _biome == "garden":
		_setup_garden_environment()
		_pick_garden_exit()  # çıkış labirent ortasına değil, kenara (dışa açılan) gelsin
	_compute_exit_dirs()
	_build_floors_and_walls()
	if _biome == "castle":
		_build_ceiling()
	_build_exit()
	_build_rooms()
	_build_props_and_chests()
	if _biome == "garden":
		_decorate_garden()
		_flush_wall_tufts()
	elif _biome == "castle":
		_build_castle_entrance()
	_build_stage_ui()
	_update_exit_lock()

	nav.bake_navigation_mesh()
	await nav.bake_finished

	var timer := Timer.new()
	timer.wait_time = maxf(2.4 - 0.2 * (Game.stage - 1), 0.9)
	timer.timeout.connect(_spawn_zombie)
	add_child(timer)
	timer.start()
	_spawn_zombie()


# ---------- inşaat ----------

func _build_floors_and_walls() -> void:
	var walls_body := StaticBody3D.new()
	walls_body.name = "WallColliders"
	nav.add_child(walls_body)

	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(maze.w * CELL + 8.0, 1.0, maze.h * CELL + 8.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(maze.w * CELL / 2.0, -0.5, maze.h * CELL / 2.0)
	walls_body.add_child(floor_shape)

	if _biome == "garden":
		_build_grass_floor(Vector2(maze.w * CELL, maze.h * CELL))
	else:
		for x in maze.w:
			for y in maze.h:
				# çıkış hücresi: halkanın altı pürüzsüz kalsın diye hep düz karo
				var fp := "floor_tile_large.gltf.glb" if Vector2i(x, y) == maze.exit \
						else _pick_weighted(FLOOR_PIECES)
				var tile := _spawn_piece(fp, nav)
				tile.position = _cell_center(Vector2i(x, y))
				# tutarlı ızgara görünümü: serbest dönüş yok

	for x in maze.w + 1:
		for y in maze.h:
			if maze.v_walls[x][y]:
				_place_wall(walls_body, Vector3(x * CELL, 0, (y + 0.5) * CELL), true)
	for x in maze.w:
		for y in maze.h + 1:
			if maze.h_walls[x][y]:
				_place_wall(walls_body, Vector3((x + 0.5) * CELL, 0, y * CELL), false)

	if _biome == "garden":
		return  # çitler köşelerde zaten taşarak birleşiyor, sütun gerekmez

	# kavşak noktalarına sütun: dik duvarların buluştuğu köşe boşluklarını kapatır
	for x in maze.w + 1:
		for y in maze.h + 1:
			var v_count := 0
			var h_count := 0
			if y < int(maze.h) and maze.v_walls[x][y]:
				v_count += 1
			if y > 0 and maze.v_walls[x][y - 1]:
				v_count += 1
			if x < int(maze.w) and maze.h_walls[x][y]:
				h_count += 1
			if x > 0 and maze.h_walls[x - 1][y]:
				h_count += 1
			if v_count > 0 and h_count > 0:
				var pillar := _spawn_piece("pillar.gltf.glb", nav)
				pillar.position = Vector3(x * CELL, 0, y * CELL)


func _place_wall(walls_body: StaticBody3D, pos: Vector3, vertical: bool) -> void:
	if _biome == "garden":
		_place_hedge(pos, vertical)
	else:
		var piece := _spawn_piece(_pick_weighted(WALL_PIECES), nav)
		piece.position = pos
		if vertical:
			piece.rotation.y = PI / 2.0
		# tutarlı yönelim: rastgele çevirme yok

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# bahçede çarpışma çit görseliyle eşleşsin: görselden hafif kalın (kafa girmesin),
	# yükseklik çit üstünü aşsın (zıplayınca geçilemesin)
	var ch := WALL_H
	var ct := 1.0
	var cl := CELL
	if _biome == "garden":
		ch = HEDGE_H + 0.8
		ct = 1.3
		cl = CELL + 0.35  # uçları/köşeleri kapat: çit görselini tam sar
	box.size = Vector3(cl, ch, ct) if not vertical else Vector3(ct, ch, cl)
	col.shape = box
	col.position = pos + Vector3(0, ch / 2.0, 0)
	walls_body.add_child(col)

	if _biome == "garden":
		return  # gün ışığında meşale olmaz

	if _torch_count < MAX_TORCHES and rng.randf() < 0.16:
		_torch_count += 1
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var offset := Vector3(side * 0.62, 0, 0) if vertical else Vector3(0, 0, side * 0.62)
		var torch := _spawn_piece("torch_mounted.gltf.glb", nav)
		torch.position = pos + offset + Vector3(0, 2.4, 0)
		torch.rotation.y = (0.0 if vertical else PI / 2.0) + (PI if side < 0 else 0.0)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.62, 0.3)
		light.light_energy = 2.4
		light.omni_range = 6.0
		light.position = torch.position + offset.normalized() * 0.4 + Vector3(0, 0.45, 0)
		nav.add_child(light)


# ---------- bahçe (hedge) biome'u ----------

func _place_hedge(pos: Vector3, vertical: bool, height := HEDGE_H, length := CELL + 0.2) -> void:
	## İngiliz bahçesi çiti: noise dokulu yeşil kutu — köşeler kapansın diye hücreden uzun
	if _hedge_mats.is_empty():
		# yaprak kümesi görünümü: hücresel noise (yumru yumru) + koyu-açık yeşil renk rampası
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		noise.frequency = 0.09
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.03, 0.10, 0.03))   # derin gölge yeşili
		ramp.set_color(1, Color(0.58, 0.78, 0.30))   # güneş vuran uç yapraklar
		ramp.add_point(0.42, Color(0.10, 0.30, 0.08))
		ramp.add_point(0.72, Color(0.30, 0.55, 0.18))
		var albedo_tex := NoiseTexture2D.new()
		albedo_tex.noise = noise
		albedo_tex.seamless = true
		albedo_tex.color_ramp = ramp
		var normal_tex := NoiseTexture2D.new()
		normal_tex.noise = noise
		normal_tex.seamless = true
		normal_tex.as_normal_map = true
		normal_tex.bump_strength = 16.0
		for tint in [Color(1.0, 1.0, 1.0), Color(0.88, 0.95, 0.84), Color(1.06, 1.04, 0.92)]:
			var m := StandardMaterial3D.new()
			m.albedo_color = tint  # renk rampadan gelir; ton farkı çit çeşitliliği verir
			m.albedo_texture = albedo_tex
			m.normal_enabled = true
			m.normal_texture = normal_tex
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.1, 1.1, 1.1)  # iri yumrular: uzaktan da okunur
			m.roughness = 1.0
			_hedge_mats.append(m)

	var hedge := MeshInstance3D.new()
	var box := BoxMesh.new()
	var h := height  # üniform yükseklik: köşelerde boy uyumsuzluğu/iç içe geçme olmasın
	box.size = Vector3(length, h, 1.25)
	box.material = _hedge_mats[rng.randi() % _hedge_mats.size()]
	hedge.mesh = box
	hedge.position = pos + Vector3(0, h / 2.0, 0)
	if vertical:
		hedge.rotation.y = PI / 2.0
	nav.add_child(hedge)

	# çitin üstünden taşan öbekler + yüzeyden fışkıran filizler ("hafif çim efekti")
	var along := Vector3(0, 0, 1) if vertical else Vector3(1, 0, 0)
	var normal := Vector3(1, 0, 0) if vertical else Vector3(0, 0, 1)
	for i in rng.randi_range(2, 4):
		var t := rng.randf_range(-length / 2.0 + 0.3, length / 2.0 - 0.3)
		var s := rng.randf_range(1.4, 2.2)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		_hedge_top_xforms.append(Transform3D(b,
				pos + along * t + normal * rng.randf_range(-0.25, 0.25) + Vector3(0, h - 0.05, 0)))
	for side: float in [-1.0, 1.0]:
		if rng.randf() < 0.6:
			var t2 := rng.randf_range(-length / 2.0 + 0.3, length / 2.0 - 0.3)
			var yy := rng.randf_range(0.5, h - 0.5)
			# dışarı doğru eğik filiz: UP'ı duvar normaline yatır
			var lean: Vector3 = (Vector3.UP * 0.55 + normal * side).normalized()
			var b2 := Basis(Quaternion(Vector3.UP, lean)) \
					.scaled(Vector3.ONE * rng.randf_range(1.0, 1.8))
			_hedge_face_xforms.append(Transform3D(b2,
					pos + along * t2 + normal * side * 0.5 + Vector3(0, yy, 0)))


func _build_grass_floor(size_xz: Vector2) -> void:
	# gerçek çim fotoğraf dokusu (ambientCG Grass004, CC0) + normal map
	var grass := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size_xz.x + 8.0, 0.1, size_xz.y + 8.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/grass/grass_color.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/grass/grass_normal.jpg")
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)  # ~2.9 m'de bir döşenir
	mat.roughness = 1.0
	_grass_mat = mat
	box.material = mat
	grass.mesh = box
	grass.position = Vector3(size_xz.x / 2.0, -0.045, size_xz.y / 2.0)
	nav.add_child(grass)

	_scatter_ground_tufts(size_xz)


func _nature_mesh(file: String) -> Mesh:
	## Kenney glb'sinden Mesh'i çıkar (MultiMesh tek Mesh ister).
	## DİKKAT: Kenney GLB'leri metallic=1 + camgöbeği folaj rengiyle geliyor —
	## metalik kapatılır, folaj yüzeyleri sahnedeki yeşile boyanır (kırmızı/beyaz kalır).
	if not _nature_mesh_cache.has(file):
		var inst: Node = (load(NATURE + file) as PackedScene).instantiate()
		var mis := inst.find_children("*", "MeshInstance3D", true, false)
		if inst is MeshInstance3D:
			mis.push_front(inst)
		var mesh: Mesh = (mis[0] as MeshInstance3D).mesh.duplicate()
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				var m: BaseMaterial3D = mat.duplicate()
				m.metallic = 0.0
				m.roughness = 1.0
				var c := m.albedo_color
				if c.b > 0.5 and c.r < 0.6 and c.g > 0.7:  # camgöbeği "grass" yüzeyi
					m.albedo_color = Color(0.30, 0.52, 0.20)
				mesh.surface_set_material(i, m)
		_nature_mesh_cache[file] = mesh
		inst.free()
	return _nature_mesh_cache[file]


func _spawn_multimesh(mesh: Mesh, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _scatter_model(file: String, count: int, smin: float, smax: float, size_xz: Vector2) -> void:
	var xforms: Array[Transform3D] = []
	for i in count:
		var s := rng.randf_range(smin, smax)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		xforms.append(Transform3D(b, Vector3(rng.randf_range(0.4, size_xz.x - 0.4), 0.0,
				rng.randf_range(0.4, size_xz.y - 0.4))))
	_spawn_multimesh(_nature_mesh(file), xforms)


func _scatter_ground_tufts(size_xz: Vector2) -> void:
	## gerçek çim hissi: Kenney çim öbekleri + harita başına tek tür çiçek + tek tük mantar
	var area := size_xz.x * size_xz.y
	_scatter_model("grass.glb", mini(int(area * 0.30), 650), 1.2, 2.2, size_xz)
	_scatter_model("grass_large.glb", mini(int(area * 0.15), 320), 1.1, 2.0, size_xz)
	_scatter_model("grass_leafsLarge.glb", mini(int(area * 0.06), 150), 1.0, 1.8, size_xz)
	var flower: String = ["flower_purpleA.glb", "flower_redA.glb",
			"flower_yellowA.glb", "flower_yellowC.glb"][rng.randi() % 4]
	_scatter_model(flower, mini(int(area * 0.04), 100), 1.3, 2.0, size_xz)
	var mushroom: String = "mushroom_red.glb" if rng.randf() < 0.5 else "mushroom_tan.glb"
	_scatter_model(mushroom, mini(int(area * 0.012), 30), 1.2, 1.8, size_xz)


func _flush_wall_tufts() -> void:
	## çit üstü/yüzü için biriktirilen yeşillik transformlarını iki MultiMesh'te bas
	_spawn_multimesh(_nature_mesh("grass_large.glb"), _hedge_top_xforms)
	_spawn_multimesh(_nature_mesh("grass_leafs.glb"), _hedge_face_xforms)
	_hedge_top_xforms = []
	_hedge_face_xforms = []


func _setup_garden_environment(boss := false) -> void:
	## zindan ortamını açık hava bahçesine çevir (resource paylaşımlı: önce kopyala)
	var we: WorldEnvironment = $WorldEnvironment
	var env: Environment = we.environment.duplicate()
	we.environment = env

	var sky_mat := ProceduralSkyMaterial.new()
	if boss:
		# boss arenası: altın saat — dramatik gün batımı
		sky_mat.sky_top_color = Color(0.25, 0.32, 0.55)
		sky_mat.sky_horizon_color = Color(0.95, 0.62, 0.38)
		sky_mat.ground_horizon_color = Color(0.85, 0.58, 0.38)
	else:
		sky_mat.sky_top_color = Color(0.33, 0.52, 0.82)
		sky_mat.sky_horizon_color = Color(0.72, 0.80, 0.86)
		sky_mat.ground_horizon_color = Color(0.66, 0.74, 0.78)
	sky_mat.ground_bottom_color = Color(0.18, 0.26, 0.13)
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.5  # gölgedeki çit yüzlerinde doku kaybolmasın
	env.fog_light_color = Color(0.92, 0.74, 0.55) if boss else Color(0.76, 0.83, 0.88)
	env.fog_density = 0.005

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24.0 if boss else -46.0, -38.0, 0)
	sun.light_color = Color(1.0, 0.72, 0.45) if boss else Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)


func _outer_tree_ring(size_xz: Vector2, south_gap_x := -1000.0) -> void:
	## çit duvarların DIŞINA çam/ölü ağaç silüeti — labirente derinlik katar (collision yok)
	## south_gap_x: güney sırada bu x civarı boş bırakılır (arena çıkış koridoru için)
	var step := 6.5
	var t := -4.0
	while t < size_xz.x + 4.0:
		for z in [-3.2, size_xz.y + 3.2]:
			if z > 0.0 and absf(t - south_gap_x) < 5.5:
				continue  # koridorun üstüne ağaç dikme
			if rng.randf() < 0.8:
				var tr := _spawn_piece(HW + OUTER_TREES[rng.randi() % OUTER_TREES.size()], self)
				tr.position = Vector3(t + rng.randf_range(-1.6, 1.6), 0, z + signf(z) * rng.randf_range(0.0, 2.5))
				tr.rotation.y = rng.randf() * TAU
		t += step
	t = -4.0
	while t < size_xz.y + 4.0:
		for x in [-3.2, size_xz.x + 3.2]:
			if rng.randf() < 0.8:
				var tr := _spawn_piece(HW + OUTER_TREES[rng.randi() % OUTER_TREES.size()], self)
				tr.position = Vector3(x + signf(x) * rng.randf_range(0.0, 2.5), 0, t + rng.randf_range(-1.6, 1.6))
				tr.rotation.y = rng.randf() * TAU
		t += step


func _build_garden_vista(size: Vector2) -> void:
	## bahçenin çevresinde iki katmanlı uzak manzara: yakın ormanlık tepeler + puslu mavi dağlar
	## (gündüz; atmosferik perspektif derinliği — çitlerin üstünden görünür)
	var cx := size.x * 0.5
	var cz := size.y * 0.5
	var radius := maxf(size.x, size.y)
	var near_mat := StandardMaterial3D.new()
	near_mat.albedo_color = Color(0.18, 0.28, 0.16)  # koyu yeşil orman
	near_mat.roughness = 1.0
	var far_mat := StandardMaterial3D.new()
	far_mat.albedo_color = Color(0.47, 0.55, 0.62)  # puslu mavi-gri dağ
	far_mat.roughness = 1.0
	for ring in 2:
		var mat: StandardMaterial3D = near_mat if ring == 0 else far_mat
		for i in 12:
			var ang := TAU * i / 12.0 + rng.randf_range(-0.12, 0.12) + ring * 0.26
			var dist := radius * (0.85 if ring == 0 else 1.45) + rng.randf_range(8.0, 28.0)
			var hh := rng.randf_range(14.0, 26.0) if ring == 0 else rng.randf_range(30.0, 54.0)
			var peak := MeshInstance3D.new()
			var pc := CylinderMesh.new()
			pc.top_radius = 0.1
			pc.bottom_radius = (rng.randf_range(16.0, 26.0) if ring == 0
					else rng.randf_range(24.0, 40.0))
			pc.height = hh
			pc.material = mat
			peak.mesh = pc
			peak.position = Vector3(cx + cos(ang) * dist, hh * 0.5 - 5.0, cz + sin(ang) * dist)
			add_child(peak)


func _decorate_garden() -> void:
	_outer_tree_ring(Vector2(maze.w * CELL, maze.h * CELL))
	_build_garden_vista(Vector2(maze.w * CELL, maze.h * CELL))

	# sandık çıkmamış çıkmaz sokaklara mezar
	for cell: Vector2i in maze.dead_ends:
		if _chest_cells.has(cell) or rng.randf() > 0.55:
			continue
		var piece: String = ["grave_A.gltf", "grave_B.gltf", "gravestone.gltf"][rng.randi() % 3]
		_spawn_prop(HW + piece, _cell_center(cell) + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)),
				rng.randf_range(-0.3, 0.3))

	# koridor kenarlarına küçük süsler: haç, kafatası, balkabağı, fener (yol kapatmaz)
	for cell: Vector2i in maze.dist:
		if cell == Vector2i.ZERO or cell == maze.exit \
				or maze.room_cells.has(cell) or _chest_cells.has(cell):
			continue
		var r := rng.randf()
		if r > 0.16:
			continue
		# duvar olan bir yön bul, süsü o kenara yasla
		var side := Vector2i.ZERO
		for d: Vector2i in MazeGen.DIRS:
			var n: Vector2i = cell + d
			var outside: bool = n.x < 0 or n.x >= int(maze.w) or n.y < 0 or n.y >= int(maze.h)
			if outside or MazeGen.has_wall_between(maze.v_walls, maze.h_walls, cell, n):
				side = d
				break
		if side == Vector2i.ZERO:
			continue
		var pos := _cell_center(cell) + Vector3(side.x, 0, side.y) * 1.35
		var yaw := atan2(-side.x, -side.y)  # süs koridora baksın
		if r < 0.08:
			var deco := _spawn_piece(HW + ("gravemarker_A.gltf" if rng.randf() < 0.6 else "gravemarker_B.gltf"), self)
			deco.position = pos
			deco.rotation.y = yaw + rng.randf_range(-0.25, 0.25)
		elif r < 0.12:
			var deco := _spawn_piece(HW + ("skull.gltf" if rng.randf() < 0.5 else "pumpkin_orange_small.gltf"), self)
			deco.position = pos
			deco.rotation.y = rng.randf() * TAU
		else:
			var deco := _spawn_piece(HW + "lantern_standing.gltf", self)
			deco.position = pos
			deco.rotation.y = yaw


func _close_arena_gate() -> void:
	## oyuncu arenaya inince demir kanatlar gürültüyle kapanır — geri dönüş yok
	if _gate_closed:
		return
	_gate_closed = true
	var tween := create_tween()
	tween.set_parallel()
	for leaf in _gate_leaves:
		tween.tween_property(leaf, "rotation:y", 0.0, 0.55) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		var snd := AudioStreamPlayer3D.new()
		snd.stream = load("res://assets/audio/sfx/gate_close.ogg")
		snd.unit_size = 5.0
		snd.volume_db = 2.0
		add_child(snd)
		snd.global_position = _gate_body.global_position + Vector3(0, 1.4, 0)
		snd.play()
		snd.finished.connect(snd.queue_free))
	# V hunisi collision'ları yerine düz kapalı kapı çubuğu
	for c in _gate_leaf_cols:
		c.queue_free()
	_gate_leaf_cols.clear()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 2.7, 0.18)
	col.shape = box
	col.position = Vector3(0, 1.35, 0)
	_gate_body.add_child(col)


func _mist_plane(pos: Vector3, size: Vector2, color: Color, yaw := 0.0) -> void:
	## ucuz "sis perdesi": yarı saydam düzlem — arkası mesafeyle kaybolur hissi
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	add_child(mi)


func _build_castle_silhouette(w: float) -> void:
	## kuzey kapının ardında, gün batımına karşı kara şato silüeti
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.10, 0.16)
	mat.roughness = 1.0
	var cx := w / 2.0

	var keep := MeshInstance3D.new()
	var kbox := BoxMesh.new()
	kbox.size = Vector3(14.0, 13.0, 6.0)
	kbox.material = mat
	keep.mesh = kbox
	keep.position = Vector3(cx, 6.5, -16.0)
	add_child(keep)

	for t in [[cx - 9.0, 16.0, 2.4, -14.0], [cx + 9.0, 16.0, 2.4, -14.0],
			[cx - 15.0, 11.0, 1.8, -17.0], [cx + 15.0, 11.0, 1.8, -17.0]]:
		var tower := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = t[2]
		cyl.bottom_radius = t[2] * 1.15
		cyl.height = t[1]
		cyl.material = mat
		tower.mesh = cyl
		tower.position = Vector3(t[0], t[1] / 2.0, t[3])
		add_child(tower)
		var roof := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = t[2] * 1.35
		cone.height = 3.6
		cone.material = mat
		roof.mesh = cone
		roof.position = Vector3(t[0], t[1] + 1.8, t[3])
		add_child(roof)

	# birkaç sıcak pencere ışığı: silüet ölü durmasın
	var win_mat := StandardMaterial3D.new()
	win_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	win_mat.albedo_color = Color(1.0, 0.72, 0.3)
	for i in 5:
		var win := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.9)
		q.material = win_mat
		win.mesh = q
		win.position = Vector3(cx + rng.randf_range(-6.0, 6.0),
				rng.randf_range(3.0, 11.0), -12.9)
		add_child(win)


func _decorate_arena(w: float) -> void:
	_build_castle_silhouette(w)
	_outer_tree_ring(Vector2(w, w), w / 2.0)
	_build_garden_vista(Vector2(w, w))

	# batı duvarının dışında dev mezar evi (crypt 6×8×8) — çitlerin üstünden görünür
	var crypt := _spawn_piece(HW + "crypt.gltf", self)
	crypt.position = Vector3(-7.0, 0, w * 0.42)
	crypt.rotation.y = -PI / 2.0
	var crypt2 := _spawn_piece(HW + "crypt.gltf", self)
	crypt2.position = Vector3(w + 7.0, 0, w * 0.66)
	crypt2.rotation.y = PI / 2.0

	# şato kapısının iki yanına fenerli direkler + sıcak ışık (gün batımında yanar)
	for sx in [-4.2, 4.2]:
		_spawn_prop(HW + "post_lantern.gltf", Vector3(w / 2.0 + sx, 0, 1.5), PI)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.72, 0.35)
		light.light_energy = 1.6
		light.omni_range = 7.0
		light.position = Vector3(w / 2.0 + sx, 3.0, 3.0)
		add_child(light)

	# koridordan kapıya uzanan taş yol + koridor ağzında (çitlerin arasında) mezarlık kemeri
	var pz := w + 2.5
	while pz > 4.5:
		var tile := _spawn_piece(HW + ["path_A.gltf", "path_B.gltf", "path_C.gltf", "path_D.gltf"][rng.randi() % 4], self)
		tile.position = Vector3(w / 2.0 + rng.randf_range(-0.35, 0.35), 0.01, pz)
		tile.rotation.y = (rng.randi() % 4) * PI / 2.0
		pz -= 1.9
	# koridor ağzında demir kapılı mezarlık kemeri: çit hattına gömülü durur,
	# kanatları HAFİF ARALIK — ortadaki boşluktan sığarak geçilir, demirlerden geçilmez
	var arch := _spawn_piece(HW + "arch_gate.gltf", self)
	var arch_z := w - 1.0
	arch.position = Vector3(w / 2.0, 0, arch_z)
	var leaf_open := deg_to_rad(58.0)
	var left_leaf: Node3D = arch.find_child("arch_gate_left", true, false)
	var right_leaf: Node3D = arch.find_child("arch_gate_right", true, false)
	if left_leaf != null:
		left_leaf.rotation.y = leaf_open
		_gate_leaves.append(left_leaf)
	if right_leaf != null:
		right_leaf.rotation.y = -leaf_open
		_gate_leaves.append(right_leaf)

	_gate_body = StaticBody3D.new()
	nav.add_child(_gate_body)
	_gate_body.global_position = Vector3(w / 2.0, 0, arch_z)
	for sgn: float in [-1.0, 1.0]:
		# sütunlar
		var pcol := CollisionShape3D.new()
		var pbox := BoxShape3D.new()
		pbox.size = Vector3(0.7, 4.4, 0.7)
		pcol.shape = pbox
		pcol.position = Vector3(sgn * 1.75, 2.2, 0)
		_gate_body.add_child(pcol)
		# aralık duran demir kanat: menteşeden koridora doğru V hunisi gibi açılır
		# (kanat mesh'leri +z / koridor yönüne savruluyor — AABB ölçümüyle doğrulandı)
		var dir := Vector3(-sgn * cos(leaf_open), 0, sin(leaf_open))
		var lcol := CollisionShape3D.new()
		var lbox := BoxShape3D.new()
		lbox.size = Vector3(1.5, 2.6, 0.14)
		lcol.shape = lbox
		lcol.position = Vector3(sgn * 1.5, 1.3, 0) + dir * 0.75
		lcol.rotation.y = atan2(-dir.z, dir.x)
		_gate_body.add_child(lcol)
		_gate_leaf_cols.append(lcol)

	# kapıdan geçip arenaya inince kanatlar arkadan ÇARPARAK kapanır
	var trigger := Area3D.new()
	var tshape := CollisionShape3D.new()
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(4.0, 3.0, 1.2)
	tshape.shape = tbox
	trigger.add_child(tshape)
	trigger.position = Vector3(w / 2.0, 1.4, arch_z - 2.0)
	trigger.body_entered.connect(func(body: Node3D) -> void:
		if body.is_in_group("player"):
			_close_arena_gate())
	add_child(trigger)

	# köşelere çitle çevrili mini mezarlıklar (kapı tarafı köşeleri)
	for cx in [6.0, w - 6.0]:
		for i in 3:
			_spawn_prop(HW + ("grave_A.gltf" if rng.randf() < 0.5 else "grave_B.gltf"),
					Vector3(cx + (i - 1) * 2.4, 0, 5.5 + rng.randf_range(-0.3, 0.3)), PI + rng.randf_range(-0.12, 0.12))
		var marker := _spawn_piece(HW + "gravemarker_B.gltf", self)
		marker.position = Vector3(cx, 0, 8.0)
		marker.rotation.y = PI
		# mezarlığın önüne demir çit + payanda
		for fx in [-2.0, 2.0]:
			var fence := _spawn_piece(HW + ("fence.gltf" if rng.randf() < 0.7 else "fence_broken.gltf"), self)
			fence.position = Vector3(cx + fx, 0, 9.2)
		var fpost := _spawn_piece(HW + "fence_pillar.gltf", self)
		fpost.position = Vector3(cx, 0, 9.2)

	# yan kenarlara mum dolu sunaklar + sıcak ışık
	for sxs in [[7.0, 0.0], [w - 7.0, PI]]:
		_spawn_prop(HW + "shrine_candles.gltf", Vector3(sxs[0], 0, w * 0.55), PI / 2.0 + sxs[1])
		var slight := OmniLight3D.new()
		slight.light_color = Color(1.0, 0.7, 0.35)
		slight.light_energy = 1.0
		slight.omni_range = 5.0
		slight.position = Vector3(sxs[0], 1.6, w * 0.55)
		add_child(slight)

	# yol kenarına banklar, içeride ölü ağaçlar (collision'lı)
	_spawn_prop(HW + "bench_decorated.gltf", Vector3(w / 2.0 - 3.2, 0, w * 0.62), PI / 2.0)
	_spawn_prop(HW + "bench.gltf", Vector3(w / 2.0 + 3.2, 0, w * 0.74), -PI / 2.0)
	for tp in [Vector3(8.5, 0, w * 0.52), Vector3(w - 9.0, 0, w * 0.42), Vector3(10.5, 0, w * 0.8)]:
		_spawn_prop(HW + ("tree_dead_large.gltf" if rng.randf() < 0.5 else "tree_dead_medium.gltf"),
				tp, rng.randf() * TAU)

	# köşelerde sırıtan balkabağı fenerleri (içi ışıklı)
	for jp in [Vector3(4.0, 0, w - 4.5), Vector3(w - 4.0, 0, w - 4.5),
			Vector3(4.5, 0, w * 0.35), Vector3(w - 4.5, 0, w * 0.35)]:
		var jack := _spawn_piece(HW + ("pumpkin_orange_jackolantern.gltf" if rng.randf() < 0.5
				else "pumpkin_yellow_jackolantern.gltf"), self)
		jack.position = jp
		jack.rotation.y = rng.randf() * TAU
		var jlight := OmniLight3D.new()
		jlight.light_color = Color(1.0, 0.55, 0.15)
		jlight.light_energy = 0.8
		jlight.omni_range = 3.5
		jlight.position = jp + Vector3(0, 0.6, 0)
		add_child(jlight)

	# çimde dağınık toprak/mezar yamaları — zemini tek renk olmaktan kurtarır
	for i in 7:
		var dirt := _spawn_piece(HW + ["floor_dirt.gltf", "floor_dirt_grave.gltf",
				"floor_dirt_small.gltf"][rng.randi() % 3], self)
		dirt.position = Vector3(rng.randf_range(6.0, w - 6.0), 0.02, rng.randf_range(10.0, w - 7.0))
		dirt.rotation.y = (rng.randi() % 4) * PI / 2.0

	# siper küplerinin dibine balkabağı/kemik kırıntıları
	for off in [Vector3(w * 0.3, 0, w * 0.38), Vector3(w * 0.7, 0, w * 0.38),
			Vector3(w * 0.3, 0, w * 0.72), Vector3(w * 0.7, 0, w * 0.72)]:
		var deco := _spawn_piece(HW + ["pumpkin_orange_small.gltf", "pumpkin_yellow_small.gltf",
				"bone_A.gltf", "ribcage.gltf"][rng.randi() % 4], self)
		deco.position = off + Vector3(rng.randf_range(1.6, 2.2), 0, rng.randf_range(-1.0, 1.0))
		deco.rotation.y = rng.randf() * TAU

	# arenanın ortasına yakın dağınık kemikler
	for i in 9:
		var bone := _spawn_piece(HW + ["bone_A.gltf", "bone_B.gltf", "skull.gltf"][rng.randi() % 3], self)
		bone.position = Vector3(rng.randf_range(8.0, w - 8.0), 0, rng.randf_range(10.0, w - 8.0))
		bone.rotation.y = rng.randf() * TAU


func _build_ceiling() -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maze.w * CELL + 8.0, 0.5, maze.h * CELL + 8.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.09, 0.085)
	box.material = mat
	mesh.mesh = box
	mesh.position = Vector3(maze.w * CELL / 2.0, WALL_H + 0.25, maze.h * CELL / 2.0)
	add_child(mesh)


func _pick_garden_exit() -> void:
	## bahçede çıkışı labirentin ÇEVRE kenarındaki en uzak ulaşılabilir hücreye taşı
	## (ortada kalıp çevre çitlerine karışmasın; dışa açılan temiz bir kapı olsun)
	var best: Vector2i = maze.exit
	var best_d := -1
	for x in int(maze.w):
		for y in int(maze.h):
			var c := Vector2i(x, y)
			var on_edge: bool = x == 0 or x == int(maze.w) - 1 or y == 0 or y == int(maze.h) - 1
			if not on_edge or c == Vector2i.ZERO or not maze.dist.has(c):
				continue
			var d: int = maze.dist[c]
			if d > best_d:
				best_d = d
				best = c
	if best_d >= 0:
		maze.exit = best


func _compute_exit_dirs() -> void:
	var exit: Vector2i = maze.exit
	# tercih: arka yön ızgaranın dışına (sınır kenarına) baksın → oda dışarı açılır
	var boundary_back := Vector2i.ZERO
	var have_boundary := false
	for d: Vector2i in MazeGen.DIRS:
		var n: Vector2i = exit + d
		if n.x < 0 or n.x >= int(maze.w) or n.y < 0 or n.y >= int(maze.h):
			boundary_back = d
			have_boundary = true
			break
	if have_boundary:
		_exit_back = Vector3(boundary_back.x, 0, boundary_back.y)
		_exit_open = -_exit_back
	else:
		var open_dir := Vector2i(0, 1)
		for d: Vector2i in MazeGen.DIRS:
			var n: Vector2i = exit + d
			if n.x >= 0 and n.x < int(maze.w) and n.y >= 0 and n.y < int(maze.h) \
					and not MazeGen.has_wall_between(maze.v_walls, maze.h_walls, exit, n):
				open_dir = d
				break
		_exit_open = Vector3(open_dir.x, 0, open_dir.y)
		_exit_back = -_exit_open
	# arka (dış) duvarı kaldır: kapı/kemer açıklığı oraya gelir
	# bahçede çıkış kenara zorlandığı için çevre çitinde gerçek bir açıklık açılır
	var back_cell := exit + Vector2i(int(_exit_back.x), int(_exit_back.z))
	_set_wall_open(exit, back_cell)


func _set_wall_open(a: Vector2i, b: Vector2i) -> void:
	if b.x == a.x + 1:
		maze.v_walls[a.x + 1][a.y] = false
	elif b.x == a.x - 1:
		maze.v_walls[a.x][a.y] = false
	elif b.y == a.y + 1:
		maze.h_walls[a.x][a.y + 1] = false
	else:
		maze.h_walls[a.x][a.y] = false


func _build_exit() -> void:
	var center := _cell_center(maze.exit)
	var open_dir := _exit_open
	var back_dir := _exit_back

	if _biome == "castle":
		# açık kemerli geçit — içi görünür, arkadaki odaya bakar (arkası artık duvar değil)
		var arch := _spawn_piece("wall_doorway.glb", self)
		arch.position = center + back_dir * (CELL / 2.0)
		arch.rotation.y = atan2(open_dir.x, open_dir.z)
		_build_exit_beyond(center, open_dir, back_dir)
		_spawn_portal(center + back_dir * 0.4)
	elif _biome == "garden":
		# çit labirenti çıkışı: boşlukta portal değil — çimende ışıklı bir kapı
		_spawn_garden_door(center, open_dir, back_dir)
	else:
		_spawn_portal(center + back_dir * 0.4)


func _spawn_garden_door(center: Vector3, _open_dir: Vector3, back_dir: Vector3) -> void:
	# back_dir = labirent KENARINDAN dışarı bakan yön; kapı oraya, eşik duvarına gelir
	var out_dir := back_dir
	var perp := Vector3(-out_dir.z, 0, out_dir.x)
	var yaw_out := atan2(out_dir.x, out_dir.z)
	var wall_vertical := absf(out_dir.x) > absf(out_dir.z)
	var edge := center + out_dir * (CELL * 0.5)  # hücrenin dış kenarı (boundary)

	# açılan çevre duvarını kapı boşluğu hariç çitle doldur (kapı bir duvara dayalı olur)
	for s in [-1.0, 1.0]:
		_place_hedge(edge + perp * s * (CELL * 0.5 + 0.6), wall_vertical, HEDGE_H + 0.3, CELL)

	# demir kapı — kenar eşiğinde, dışarı bakar
	var gate := _spawn_piece(HW + "arch_gate.gltf", self)
	gate.position = edge
	gate.rotation.y = yaw_out

	# kapının ardı (labirent dışı) sise gömülü — açık havada açık gri sis
	_mist_plane(edge + out_dir * 2.0 + Vector3(0, 2.0, 0),
			Vector2(CELL * 1.3, HEDGE_H + 2.0), Color(0.72, 0.78, 0.85, 0.22), yaw_out)
	_mist_plane(edge + out_dir * 3.6 + Vector3(0, 2.0, 0),
			Vector2(CELL * 1.5, HEDGE_H + 2.6), Color(0.78, 0.83, 0.9, 0.5), yaw_out)
	_mist_plane(edge + out_dir * 5.2 + Vector3(0, 2.2, 0),
			Vector2(CELL * 1.8, HEDGE_H + 3.2), Color(0.85, 0.89, 0.94, 0.96), yaw_out)

	# kapı boşluğunda dikey ışık perdesi (kilit geri bildirimi bunda)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.35)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.3, 0.75, 1.0)
	_ring_mat.emission_energy_multiplier = 3.0
	_disc_mat = _ring_mat  # _update_exit_lock ikisini de boyar; aynı materyal sorun değil
	var curtain := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 3.4)
	curtain.mesh = quad
	curtain.material_override = _ring_mat
	curtain.position = edge + Vector3(0, 1.7, 0)
	curtain.rotation.y = atan2(-out_dir.x, -out_dir.z)  # yüzü içeri (oyuncuya)
	add_child(curtain)
	var sway := curtain.create_tween().set_loops()
	sway.tween_property(_ring_mat, "emission_energy_multiplier", 4.2, 1.0)
	sway.tween_property(_ring_mat, "emission_energy_multiplier", 2.4, 1.0)

	_portal_light = OmniLight3D.new()
	_portal_light.light_color = Color(0.3, 0.7, 1.0)
	_portal_light.light_energy = 3.0
	_portal_light.omni_range = 6.0
	_portal_light.position = edge + Vector3(0, 2.0, 0)
	add_child(_portal_light)

	_exit_prompt = Label3D.new()
	_exit_prompt.text = "ÇIKIŞ"
	_exit_prompt.font = MenuUI.FONT
	_exit_prompt.font_size = 110
	_exit_prompt.pixel_size = 0.006
	_exit_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_exit_prompt.modulate = Color(0.45, 0.85, 1.0)
	_exit_prompt.outline_size = 18
	_exit_prompt.position = edge + Vector3(0, 3.7, 0)
	add_child(_exit_prompt)

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CELL * 0.7, 3.0, CELL * 0.7)
	shape.shape = box
	area.add_child(shape)
	area.position = center + Vector3(0, 1.0, 0)
	area.body_entered.connect(_on_exit_near.bind(true))
	area.body_exited.connect(_on_exit_near.bind(false))
	add_child(area)


func _spawn_portal(pos: Vector3) -> void:
	## yerde yatay parlayan neon halka; kilitliyken kırmızı, açılınca mavi
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(0.25, 0.7, 1.0)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.3, 0.75, 1.0)
	_ring_mat.emission_energy_multiplier = 4.0
	var torus := TorusMesh.new()
	torus.inner_radius = 0.95
	torus.outer_radius = 1.25
	var ring := MeshInstance3D.new()
	ring.mesh = torus  # varsayılan: yatay (XZ düzlemi) — tam istenen
	ring.material_override = _ring_mat
	ring.position = pos + Vector3(0, 0.12, 0)
	add_child(ring)

	# içteki parıltı diski (yerde)
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_disc_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.3)
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.95
	disc_mesh.bottom_radius = 0.95
	disc_mesh.height = 0.02
	disc.mesh = disc_mesh
	disc.material_override = _disc_mat
	disc.position = ring.position
	add_child(disc)

	_portal_light = OmniLight3D.new()
	_portal_light.light_color = Color(0.3, 0.7, 1.0)
	_portal_light.light_energy = 3.0
	_portal_light.omni_range = 6.0
	_portal_light.shadow_enabled = true
	_portal_light.position = ring.position + Vector3(0, 1.6, 0)
	add_child(_portal_light)

	var spin := ring.create_tween().set_loops()
	spin.tween_method(func(a: float) -> void: ring.rotation.y = a, 0.0, TAU, 5.0)
	var pulse := _portal_light.create_tween().set_loops()
	pulse.tween_property(_portal_light, "light_energy", 4.0, 1.1)
	pulse.tween_property(_portal_light, "light_energy", 2.0, 1.1)

	_exit_prompt = Label3D.new()
	_exit_prompt.text = "ÇIKIŞ"
	_exit_prompt.font = MenuUI.FONT
	_exit_prompt.font_size = 110
	_exit_prompt.pixel_size = 0.006
	_exit_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_exit_prompt.modulate = Color(0.45, 0.85, 1.0)
	_exit_prompt.outline_size = 18
	_exit_prompt.position = ring.position + Vector3(0, 2.4, 0)
	add_child(_exit_prompt)

	# yakınlık alanı: girince [E] yaz, çıkınca "ÇIKIŞ"
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CELL * 0.7, 3.0, CELL * 0.7)
	shape.shape = box
	area.add_child(shape)
	area.position = ring.position + Vector3(0, 1.0, 0)
	area.body_entered.connect(_on_exit_near.bind(true))
	area.body_exited.connect(_on_exit_near.bind(false))
	add_child(area)


func _update_exit_lock() -> void:
	## kota dolana kadar portal kırmızı + kilitli; dolunca maviye döner
	if _exit_unlocked or _exit_prompt == null:
		return
	if _kills_done >= _kills_needed:
		_exit_unlocked = true
		_ring_mat.albedo_color = Color(0.25, 0.7, 1.0)
		_ring_mat.emission = Color(0.3, 0.75, 1.0)
		_disc_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.3)
		_portal_light.light_color = Color(0.3, 0.7, 1.0)
		_exit_prompt.text = "ÇIKIŞ"
		_exit_prompt.modulate = Color(0.45, 0.85, 1.0)
		if _exit_near:
			_exit_screen_prompt.visible = true
	else:
		_ring_mat.albedo_color = Color(0.95, 0.28, 0.22)
		_ring_mat.emission = Color(1.0, 0.3, 0.22)
		_disc_mat.albedo_color = Color(1.0, 0.3, 0.22, 0.25)
		_portal_light.light_color = Color(1.0, 0.35, 0.25)
		_exit_prompt.text = "KİLİTLİ — %d ZOMBİ" % (_kills_needed - _kills_done)
		_exit_prompt.modulate = Color(1.0, 0.45, 0.38)


func _build_exit_beyond(center: Vector3, _open_dir: Vector3, back_dir: Vector3) -> void:
	# kemerin arkasında salt görsel oda: aşağı inen merdiven + sıcak ışık →
	# "başka bir yere" açılıyormuş hissi. Navmesh'e dahil değil (self'e eklenir).
	var perp := Vector3(-back_dir.z, 0, back_dir.x)
	var yaw := atan2(back_dir.x, back_dir.z)

	var landing := _spawn_piece(_pick_weighted(FLOOR_PIECES), self)
	landing.position = center + back_dir * CELL

	var stairs := _spawn_piece("stairs_wide.gltf.glb", self)
	stairs.position = center + back_dir * (CELL * 1.9) + Vector3(0, -0.05, 0)
	stairs.rotation.y = yaw

	var lower := _spawn_piece(_pick_weighted(FLOOR_PIECES), self)
	lower.position = center + back_dir * (CELL * 2.9) + Vector3(0, -1.5, 0)

	# karanlık çerçeve: yan duvarlar + arka + tavan (dış boşluk görünmesin)
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.06, 0.055, 0.05)
	for s in [-1.0, 1.0]:
		var side := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(1.0, WALL_H + 1.0, CELL * 3.2)
		side.mesh = sbox
		side.material_override = frame_mat
		side.position = center + back_dir * (CELL * 1.8) \
				+ perp * s * (CELL * 0.55) + Vector3(0, WALL_H / 2.0 - 0.8, 0)
		side.rotation.y = yaw
		add_child(side)
	var back_wall := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(CELL * 1.5, WALL_H + 1.0, 1.0)
	back_wall.mesh = bbox
	back_wall.material_override = frame_mat
	back_wall.position = center + back_dir * (CELL * 3.4) + Vector3(0, WALL_H / 2.0 - 0.8, 0)
	back_wall.rotation.y = yaw
	add_child(back_wall)
	var top := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(CELL * 1.5, 0.5, CELL * 3.4)
	top.mesh = tbox
	top.material_override = frame_mat
	top.position = center + back_dir * (CELL * 1.8) + Vector3(0, WALL_H - 0.3, 0)
	top.rotation.y = yaw
	add_child(top)

	# derinde sıcak titrek ışık + meşale
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.66, 0.32)
	glow.light_energy = 2.6
	glow.omni_range = 7.0
	glow.position = center + back_dir * (CELL * 2.6) + Vector3(0, 0.5, 0)
	add_child(glow)
	var torch := _spawn_piece("torch_mounted.gltf.glb", self)
	torch.position = center + back_dir * (CELL * 3.25) + Vector3(0, 2.2, 0)
	torch.rotation.y = yaw + PI
	var flick := glow.create_tween().set_loops()
	flick.tween_property(glow, "light_energy", 3.1, 0.5)
	flick.tween_property(glow, "light_energy", 2.2, 0.6)


func _build_castle_entrance() -> void:
	## spawn'ın arkası boş duvar olmasın: kemerli giriş + sise kaybolan loş koridor
	## + kapıdan içeri vuran soluk ışık hüzmesi ("buradan girdik" hissi)
	var base := Vector3(0, 0, CELL * 0.5)
	var doorway := _spawn_piece("wall_doorway.glb", self)
	doorway.position = base
	doorway.rotation.y = PI / 2.0  # açıklık doğuya (labirentin içine) bakar
	# modelin kapalı kapı kanadını gizle: boşluktan sis + ışık hüzmesi görünsün
	var door_leaf := doorway.find_child("wall_doorway_door", true, false)
	if door_leaf != null:
		(door_leaf as Node3D).visible = false

	for k in [0.5, 1.5]:  # kapı ağzından itibaren kesintisiz zemin (boşluk siyah bant yapıyordu)
		var tile := _spawn_piece("floor_tile_large.gltf.glb", self)
		tile.position = base + Vector3(-CELL * k, 0, 0)

	# karanlık çerçeve: koridorun yanları + tavanı (dış boşluk görünmesin)
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.05, 0.045, 0.04)
	for s: float in [-1.0, 1.0]:
		var side := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(CELL * 2.4, WALL_H + 1.0, 1.0)
		side.mesh = sbox
		side.material_override = frame_mat
		side.position = base + Vector3(-CELL * 1.2, WALL_H / 2.0 - 0.5, s * CELL * 0.55)
		add_child(side)
	var top := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(CELL * 2.4, 0.5, CELL * 1.3)
	top.mesh = tbox
	top.material_override = frame_mat
	top.position = base + Vector3(-CELL * 1.2, WALL_H - 0.25, 0)
	add_child(top)

	# koridor sise/karanlığa kaybolur
	# loş zindanda sis koyu olmalı; açık gri uzak düzlem "duvar" gibi okunuyor
	_mist_plane(base + Vector3(-2.2, 1.8, 0), Vector2(4.4, 3.8), Color(0.30, 0.33, 0.42, 0.20), PI / 2.0)
	_mist_plane(base + Vector3(-4.2, 1.8, 0), Vector2(4.4, 3.8), Color(0.16, 0.18, 0.26, 0.50), PI / 2.0)
	_mist_plane(base + Vector3(-6.2, 1.8, 0), Vector2(4.6, 4.0), Color(0.05, 0.05, 0.09, 0.97), PI / 2.0)

	# kapı ağzından içeri süzülen soluk ay ışığı hüzmesi
	var beam := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.5
	bcyl.bottom_radius = 1.3
	bcyl.height = 5.0
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.albedo_color = Color(0.85, 0.88, 1.0, 0.07)
	beam.mesh = bcyl
	beam.material_override = bmat
	beam.position = base + Vector3(0.9, 2.0, 0)
	beam.rotation.z = deg_to_rad(38.0)  # tepesi kapıya, eteği labirent zeminine
	add_child(beam)
	var blight := OmniLight3D.new()
	blight.light_color = Color(0.8, 0.85, 1.0)
	blight.light_energy = 1.1
	blight.omni_range = 6.0
	blight.position = base + Vector3(1.5, 1.8, 0)
	add_child(blight)

	# collision: koridor yanları + uç kapak + zemin
	var body := StaticBody3D.new()
	nav.add_child(body)
	for s: float in [-1.0, 1.0]:
		var scol := CollisionShape3D.new()
		var scbox := BoxShape3D.new()
		scbox.size = Vector3(CELL * 2.4, WALL_H, 1.0)
		scol.shape = scbox
		scol.position = base + Vector3(-CELL * 1.2, WALL_H / 2.0, s * CELL * 0.55)
		body.add_child(scol)
	var capc := CollisionShape3D.new()
	var capb := BoxShape3D.new()
	capb.size = Vector3(1.0, WALL_H, CELL * 1.3)
	capc.shape = capb
	capc.position = base + Vector3(-7.0, WALL_H / 2.0, 0)
	body.add_child(capc)
	var fcol := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(CELL * 2.4, 1.0, CELL * 1.2)
	fcol.shape = fbox
	fcol.position = base + Vector3(-CELL * 1.2, -0.5, 0)
	body.add_child(fcol)


func _build_rooms() -> void:
	for room: Dictionary in maze.rooms:
		var rect: Rect2i = room.rect
		var center := Vector3(
				(rect.position.x + rect.size.x / 2.0) * CELL, 0,
				(rect.position.y + rect.size.y / 2.0) * CELL)
		if _biome == "garden":
			# bahçe açıklığı: sandık köşesi / mini mezarlık / türbe
			var roll := rng.randf()
			if roll < 0.35:
				var chest := StaticBody3D.new()
				chest.set_script(CHEST_SCRIPT)
				nav.add_child(chest)
				chest.position = center
				chest.rotation.y = (rng.randi() % 4) * PI / 2.0
				for i in 2:
					_spawn_prop(HW + ("gravestone.gltf" if i == 0 else "gravemarker_A.gltf"),
							center + _scatter(rect), rng.randf_range(-0.4, 0.4))
			elif roll < 0.7:
				# mini mezarlık: mezar sırası + ölü ağaç + fener
				for gx in 2:
					for gz in 2:
						_spawn_prop(HW + ("grave_A.gltf" if rng.randf() < 0.5 else "grave_B.gltf"),
								center + Vector3(gx * 2.4 - 1.2, 0, gz * 2.0 - 1.0),
								rng.randf_range(-0.15, 0.15))
				_spawn_prop(HW + "tree_dead_medium.gltf", center + _scatter(rect), rng.randf() * TAU)
				_spawn_prop(HW + "lantern_standing.gltf", center + _scatter(rect), 0.0)
			else:
				# türbe açıklığı: mum dolu sunak + bank + balkabakları
				_spawn_prop(HW + "shrine_candles.gltf", center, (rng.randi() % 4) * PI / 2.0)
				_spawn_prop(HW + "bench.gltf", center + _scatter(rect), rng.randf() * TAU)
				for i in rng.randi_range(1, 3):
					_spawn_prop(HW + "pumpkin_orange_small.gltf", center + _scatter(rect), rng.randf() * TAU)
			continue
		match room.type:
			"depo":
				for i in rng.randi_range(3, 5):
					_spawn_prop(PROP_PIECES[rng.randi() % PROP_PIECES.size()],
							center + _scatter(rect), rng.randf() * TAU)
			"sapel":
				_spawn_prop("table_long_tablecloth.gltf.glb", center, 0.0)
				var candle := _spawn_piece("candle_triple.gltf.glb", nav)
				candle.position = center + Vector3(0, 1.0, 0)
				var banner := _spawn_piece("banner_patternA_blue.gltf.glb", nav)
				banner.position = center + Vector3(0, 1.8, -2.4)
			"yemekhane":
				_spawn_prop("table_long_decorated_A.gltf.glb", center + Vector3(-1.2, 0, 0), 0.0)
				_spawn_prop("table_long_tablecloth_decorated_A.gltf.glb", center + Vector3(1.6, 0, 0), 0.0)
				_spawn_prop("keg_decorated.gltf.glb", center + _scatter(rect), rng.randf() * TAU)
			"yatakhane":
				for i in rng.randi_range(2, 3):
					_spawn_prop("bed_decorated.gltf.glb", center + _scatter(rect), (rng.randi() % 4) * PI / 2.0)
			"hazine":
				var chest := StaticBody3D.new()
				chest.set_script(CHEST_SCRIPT)
				nav.add_child(chest)
				chest.position = center
				for i in rng.randi_range(2, 4):
					var coins := _spawn_piece("coin_stack_medium.gltf.glb", nav)
					coins.position = center + _scatter(rect)
				var glow := OmniLight3D.new()
				glow.light_color = Color(1.0, 0.85, 0.45)
				glow.light_energy = 1.4
				glow.omni_range = 5.0
				glow.position = center + Vector3(0, 2.0, 0)
				nav.add_child(glow)


func _scatter(rect: Rect2i) -> Vector3:
	# prop'ları odanın KENARINA yasla, merkez geçit açık kalsın (tıkanma olmasın)
	var hw := rect.size.x * CELL / 2.0 - 1.0
	var hh := rect.size.y * CELL / 2.0 - 1.0
	if rng.randf() < 0.5:
		return Vector3((hw if rng.randf() < 0.5 else -hw), 0, rng.randf_range(-hh, hh))
	return Vector3(rng.randf_range(-hw, hw), 0, (hh if rng.randf() < 0.5 else -hh))


func _spawn_prop(piece_file: String, pos: Vector3, rot: float) -> void:
	var body := StaticBody3D.new()
	nav.add_child(body)
	body.position = pos
	body.rotation.y = rot
	var model := _spawn_piece(piece_file, body)
	model.position = Vector3.ZERO

	# collision'ı modelin gerçek AABB'sine göre boyutla (içine girilemesin)
	var aabb := _local_aabb(body, model)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(aabb.size.x, 0.4), maxf(aabb.size.y, 0.6), maxf(aabb.size.z, 0.4))
	col.shape = box
	col.position = aabb.position + aabb.size * 0.5
	body.add_child(col)


func _local_aabb(body: Node3D, model: Node3D) -> AABB:
	var binv := body.global_transform.affine_inverse()
	var merged := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var a := (binv * mesh.global_transform) * mesh.get_aabb()
		merged = a if first else merged.merge(a)
		first = false
	return merged


func _build_props_and_chests() -> void:
	# çıkmaz sokaklara SADECE sandık (yolu tıkamaz; terminal hücre).
	# barreller koridorlara konmuyor — geçişi engelliyordu.
	for cell: Vector2i in maze.dead_ends:
		if rng.randf() < 0.5:
			_chest_cells[cell] = true
			var chest := StaticBody3D.new()
			chest.set_script(CHEST_SCRIPT)
			nav.add_child(chest)
			chest.position = _cell_center(cell)
			chest.rotation.y = (rng.randi() % 4) * PI / 2.0


func _build_stage_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	_stage_label = Label.new()
	match _biome:
		"garden":
			_stage_label.text = "BAHÇE %d/%d" % [Game.biome_stage(), Game.GARDEN_STAGES]
		"garden_boss":
			_stage_label.text = "BOSS — ŞATO BAHÇESİ"
		"castle_boss":
			_stage_label.text = "BOSS — TAHT SALONU"
		"cerberus":
			_stage_label.text = "BOSS — BALKON"
		"heaven":
			_stage_label.text = "GÖKLER"
		"hell":
			_stage_label.text = "CEHENNEM"
		_:
			_stage_label.text = "KAT %d/%d" % [Game.biome_stage(), Game.CASTLE_STAGES]
	_stage_label.add_theme_font_override("font", MenuUI.FONT)
	_stage_label.add_theme_font_size_override("font_size", 26)
	# tam genişlik + metin ortalama: metin uzunluğu değişse de ortada kalır
	_stage_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_stage_label.offset_top = 36.0
	_stage_label.offset_bottom = 70.0
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_stage_label)

	# zombi kotası: portal kilidinin durumu portala gitmeden görünsün
	if _biome == "garden" or _biome == "castle":
		_quota_label = Label.new()
		_quota_label.add_theme_font_override("font", MenuUI.FONT)
		_quota_label.add_theme_font_size_override("font_size", 18)
		_quota_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_quota_label.offset_top = 72.0
		_quota_label.offset_bottom = 98.0
		_quota_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(_quota_label)
		_update_quota_label()

	_build_exit_screen_prompt(layer)

	# kat giriş animasyonu: siyahtan açıl + büyük başlık
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)

	_stage_title = Label.new()
	match _biome:
		"garden":
			_stage_title.text = "ŞATO BAHÇESİ — BÖLÜM %d" % Game.biome_stage()
		"garden_boss":
			_stage_title.text = "ŞATO BAHÇESİ — ARENA"
		"castle_boss":
			_stage_title.text = "ŞATO — TAHT SALONU"
		"cerberus":
			_stage_title.text = "ŞATONUN BALKONU"
		"heaven":
			_stage_title.text = "BULUTLARIN ÖTESİ"
		"hell":
			_stage_title.text = "LAV DİYARI"
		_:
			_stage_title.text = "ŞATO — KAT %d" % Game.biome_stage()
	_stage_title.add_theme_font_override("font", MenuUI.FONT)
	_stage_title.add_theme_font_size_override("font_size", 64)
	_stage_title.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	# elle ofsetli sahte ortalama uzun başlıklarda sağa kayıyordu — gerçek ortalama
	_stage_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage_title.offset_bottom = -80.0  # hafif yukarıda dursun
	layer.add_child(_stage_title)

	# hikâye ekranı gösterilecekse kat geçiş animasyonu onun sonunda tetiklenir
	if Game.stage == 1 and not Game.intro_shown:
		_story_flag = "intro_shown"
		_show_story_intro([
			"GÜN BATARKEN LANETLİ ŞATONUN BAHÇESİNE VARDIN.",
			"ÇİT LABİRENTİNİN DERİNLİKLERİNDE ÖLÜLER UYANIYOR.",
			"ŞATOYA GİREBİLMEK İÇİN BAHÇENİN BEKÇİSİNİ GEÇMELİSİN.",
		])
	elif _biome == "castle" and Game.biome_stage() == 1 and not Game.castle_intro_shown:
		_story_flag = "castle_intro_shown"
		_show_story_intro([
			"BAHÇENİN BEKÇİSİ DEVRİLDİ. DEMİR KAPI ARDINA KADAR AÇILDI.",
			"ŞATONUN TAŞ KORİDORLARINDA ÖLÜM SESSİZCE DOLAŞIYOR.",
			"LANETİN KAYNAĞI DERİNLERDE, TAHT SALONUNDA SENİ BEKLİYOR.",
		])
	else:
		_play_stage_fade()


func _play_stage_fade() -> void:
	var tween := create_tween()
	tween.tween_interval(0.9)
	tween.set_parallel()
	tween.tween_property(_fade, "color:a", 0.0, 0.8)
	tween.tween_property(_stage_title, "modulate:a", 0.0, 1.1)


func _show_story_intro(lines: Array) -> void:
	## bölüm girişlerinde oyuna ısındıran ekran: karanlık + hikâye satırları + [E]
	_intro_active = true
	player.process_mode = Node.PROCESS_MODE_DISABLED  # bakış/ateş/hareket kilitli

	_story_layer = CanvasLayer.new()
	_story_layer.layer = 12
	add_child(_story_layer)

	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_story_layer.add_child(black)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_story_layer.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 34)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var tween := create_tween()
	_story_tween = tween
	tween.tween_interval(0.7)
	for text in lines:
		var line := Label.new()
		line.text = text
		line.add_theme_font_override("font", MenuUI.FONT)
		line.add_theme_font_size_override("font_size", 30)
		line.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.modulate.a = 0.0
		vbox.add_child(line)
		tween.tween_property(line, "modulate:a", 1.0, 0.8)
		tween.tween_interval(0.65)

	var prompt := Label.new()
	prompt.text = "[E]  DEVAM"
	prompt.add_theme_font_override("font", MenuUI.FONT)
	prompt.add_theme_font_size_override("font_size", 26)
	prompt.add_theme_color_override("font_color", Color(0.5, 0.95, 0.4))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.modulate.a = 0.0
	vbox.add_child(prompt)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.6)
	tween.tween_callback(func() -> void:
		_intro_can_dismiss = true  # buton göründü, E artık geçerli
		if not is_instance_valid(prompt):
			return
		var pulse := prompt.create_tween().set_loops()
		pulse.tween_property(prompt, "modulate:a", 0.45, 0.7)
		pulse.tween_property(prompt, "modulate:a", 1.0, 0.7))


func _dismiss_story_intro() -> void:
	Game.set(_story_flag, true)
	_intro_active = false
	if _story_tween != null:
		_story_tween.kill()
	player.process_mode = Node.PROCESS_MODE_INHERIT
	var tween := _story_layer.create_tween()
	tween.tween_property(_story_layer.get_child(0), "modulate:a", 0.0, 0.6)
	for child in _story_layer.get_children():
		if child != _story_layer.get_child(0):
			tween.parallel().tween_property(child, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_story_layer.queue_free)
	_play_stage_fade()


func _build_exit_screen_prompt(layer: CanvasLayer) -> void:
	# çıkışa yaklaşınca alt-ortada beliren etkileşim promptu: [E] SONRAKİ KATA GEÇ
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -150
	holder.offset_bottom = -90
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false
	layer.add_child(holder)
	_exit_screen_prompt = holder

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	center.add_child(row)

	# [E] tuş rozeti
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	sb.set_corner_radius_all(7)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.5, 0.95, 0.4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	badge.add_theme_stylebox_override("panel", sb)
	row.add_child(badge)

	var key := Label.new()
	key.text = "E"
	key.add_theme_font_override("font", MenuUI.FONT)
	key.add_theme_font_size_override("font_size", 34)
	key.add_theme_color_override("font_color", Color(0.6, 1.0, 0.5))
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(key)

	var text := Label.new()
	match _biome:
		"garden_boss":
			text.text = "ŞATOYA GİR"
		"castle_boss":
			text.text = "DERİNLERE İN"
		_:
			text.text = "SONRAKİ KATA GEÇ"
	_exit_action_label = text
	text.add_theme_font_override("font", MenuUI.FONT)
	text.add_theme_font_size_override("font_size", 30)
	text.add_theme_color_override("font_color", Color(0.92, 0.95, 0.9))
	text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	text.add_theme_constant_override("outline_size", 6)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)

	# nazik nabız: dikkat çeksin ama rahatsız etmesin
	var pulse := holder.create_tween().set_loops()
	pulse.tween_property(holder, "modulate:a", 0.55, 0.7)
	pulse.tween_property(holder, "modulate:a", 1.0, 0.7)


# ---------- akış ----------

func _spawn_zombie() -> void:
	if _stage_over or _intro_active or _alive >= 10 + 3 * Game.stage:
		return
	# sadece oyuncuya yol bağlantısı olan (ulaşılabilir) hücrelerden doğur
	var cell := Vector2i(rng.randi() % int(maze.w), rng.randi() % int(maze.h))
	var tries := 0
	while not maze.dist.has(cell) and tries < 12:
		cell = Vector2i(rng.randi() % int(maze.w), rng.randi() % int(maze.h))
		tries += 1
	if not maze.dist.has(cell):
		return
	var pos := _cell_center(cell) + Vector3(0, 0.1, 0)
	if pos.distance_to(player.global_position) < 9.0:
		return
	var z := zombie_scene.instantiate()
	var variant := ENEMY_VARIANTS.roll(_biome, Game.stage, rng)
	ENEMY_VARIANTS.apply(z, variant, Game.stage, rng)
	add_child(z)
	z.global_position = pos
	_alive += 1
	z.died.connect(_on_zombie_died)


func _on_zombie_died() -> void:
	_alive -= 1
	_kills_done += 1
	_update_exit_lock()
	_update_quota_label()


func _update_quota_label() -> void:
	if _quota_label == null:
		return
	if _kills_done >= _kills_needed:
		_quota_label.text = "ÇIKIŞ AÇIK"
		_quota_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.4))
	else:
		_quota_label.text = "ZOMBİ %d/%d" % [_kills_done, _kills_needed]
		_quota_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.4))


func _process(_delta: float) -> void:
	if _intro_active:
		if _intro_can_dismiss and Input.is_action_just_pressed("interact"):
			_dismiss_story_intro()
		return
	if _exit_near and _exit_unlocked and not _stage_over \
			and Input.is_action_just_pressed("interact"):
		_finish_stage()
	if _portal_near != "" and not _choice_made \
			and Input.is_action_just_pressed("interact"):
		_on_choice_portal(_portal_near)


func _on_exit_near(body: Node3D, near: bool) -> void:
	if not body.is_in_group("player"):
		return
	_exit_near = near
	if _stage_over:
		return
	_exit_screen_prompt.visible = near and _exit_unlocked
	if _exit_unlocked:
		_exit_prompt.modulate = Color(0.5, 0.95, 0.4) if near else Color(0.45, 0.85, 1.0)


func _finish_stage() -> void:
	_stage_over = true
	_exit_screen_prompt.visible = false
	Music.transition()  # E'ye basınca anında geçiş sesi
	var done_text: String
	match _biome:
		"garden":
			done_text = "BÖLÜM %d TAMAMLANDI!" % Game.biome_stage()
		"garden_boss":
			done_text = "ŞATOYA GİRİLİYOR..."
		"castle_boss":
			done_text = "DERİNLERE İNİLİYOR..."
		_:
			done_text = "KAT %d TAMAMLANDI!" % Game.biome_stage()
	_exit_prompt.text = done_text
	_stage_label.text = done_text
	_stage_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.4))
	_stage_label.scale = Vector2(1.5, 1.5)
	var pop := _stage_label.create_tween()
	pop.tween_property(_stage_label, "scale", Vector2.ONE, 0.4)
	# kısa gecikme sonrası hızlı karart, sonra sonraki kata geç
	var tween := create_tween()
	tween.tween_interval(0.35)
	tween.tween_property(_fade, "color:a", 1.0, 0.65)
	await tween.finished
	if player != null:  # can + mermiyi sonraki kata taşı (sıfırlanmasın)
		Game.carry_health = player.health
		Game.carry_ammo = (player.get_node("%Gun") as Node).export_ammo()
	Game.next_stage()
	get_tree().reload_current_scene()


func _on_player_died() -> void:
	await get_tree().create_timer(2.0).timeout
	var tween := create_tween()
	tween.tween_property(_fade, "color", Color(0.25, 0.0, 0.0, 1.0), 1.2)
	await tween.finished
	# ana menüye atmadan önce koşu-özeti ekranı (statlar + leaderboard + karakter)
	add_child(RUN_SUMMARY.new())


# ---------- boss arenası (şato bahçesi) ----------

func _build_boss_arena() -> void:
	_setup_garden_environment(true)
	var w := ARENA_CELLS * CELL  # arena kenarı (m)

	var walls_body := StaticBody3D.new()
	walls_body.name = "WallColliders"
	nav.add_child(walls_body)

	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(w + 8.0, 1.0, w + 8.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(w / 2.0, -0.5, w / 2.0)
	walls_body.add_child(floor_shape)
	_build_grass_floor(Vector2(w, w))

	# çevre: kuzey kenarın ortası taş şato cephesi (ortada parmaklıklı kapı), kalanı çit.
	# Güney kenarın ortası AÇIK: oyuncu çit koridorundan (labirentten) çıkıp arenaya girer.
	var gate_i := ARENA_CELLS / 2  # taş kapı segmenti
	for i in ARENA_CELLS:
		var xc := (i + 0.5) * CELL
		if i == gate_i:
			var gate := _spawn_piece("wall_gated.gltf.glb", nav)
			gate.position = Vector3(xc, 0, 0)
		elif i == gate_i - 1 or i == gate_i + 1:
			var stone := _spawn_piece("wall.gltf.glb", nav)
			stone.position = Vector3(xc, 0, 0)
		else:
			_place_hedge(Vector3(xc, 0, 0), false, HEDGE_H + 0.6)
		if i != gate_i:  # güneyde orta segment koridor ağzı olarak açık kalır
			_place_hedge(Vector3(xc, 0, w), false, HEDGE_H + 0.6)
		_place_hedge(Vector3(0, 0, xc), true, HEDGE_H + 0.6)
		_place_hedge(Vector3(w, 0, xc), true, HEDGE_H + 0.6)
	for px in [float(gate_i - 1) * CELL, float(gate_i + 2) * CELL]:
		var pillar := _spawn_piece("pillar.gltf.glb", nav)
		pillar.position = Vector3(px, 0, 0)

	# çevre collision: kuzey + iki yan tam kutu, güney ortası boşluklu iki parça
	for side in 3:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var vertical := side >= 1
		box.size = Vector3(1.0, WALL_H + 2.0, w + 2.0) if vertical else Vector3(w + 2.0, WALL_H + 2.0, 1.0)
		col.shape = box
		col.position = (Vector3(0.0 if side == 1 else w, WALL_H / 2.0, w / 2.0) if vertical
				else Vector3(w / 2.0, WALL_H / 2.0, 0.0))
		walls_body.add_child(col)
	var gap_half := 2.0
	for sgn: float in [-1.0, 1.0]:
		var seg_len := w / 2.0 - gap_half + 1.0
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(seg_len, WALL_H + 2.0, 1.0)
		col.shape = box
		var center_x := (w / 2.0 + sgn * gap_half) + sgn * seg_len / 2.0
		col.position = Vector3(center_x, WALL_H / 2.0, w)
		walls_body.add_child(col)

	# güney çıkış koridoru: iki çit duvar + arka kapak — labirentten geliyormuş hissi
	var cx0 := w / 2.0
	for sgn: float in [-1.0, 1.0]:
		_place_hedge(Vector3(cx0 + sgn * 2.35, 0, w + 2.8), true, HEDGE_H + 0.6, 7.0)
		var ccol := CollisionShape3D.new()
		var cbox := BoxShape3D.new()
		cbox.size = Vector3(1.0, WALL_H, 7.2)
		ccol.shape = cbox
		ccol.position = Vector3(cx0 + sgn * 2.35, WALL_H / 2.0, w + 2.8)
		walls_body.add_child(ccol)
	# görünmez bariyer: oyuncu sise yürüyemez (görsel koridor ise sise devam eder)
	var capcol := CollisionShape3D.new()
	var capbox := BoxShape3D.new()
	capbox.size = Vector3(5.9, WALL_H, 1.0)
	capcol.shape = capbox
	capcol.position = Vector3(cx0, WALL_H / 2.0, w + 6.0)
	walls_body.add_child(capcol)
	# arkaya dönünce boş duvar değil; sise kaybolan çit koridoru görünsün
	for sgn: float in [-1.0, 1.0]:
		_place_hedge(Vector3(cx0 + sgn * 2.35, 0, w + 9.7), true, HEDGE_H + 0.6, 7.0)
	_place_hedge(Vector3(cx0, 0, w + 13.0), false, HEDGE_H + 0.6, 5.9)
	_mist_plane(Vector3(cx0, 1.9, w + 5.4), Vector2(5.6, 4.2), Color(0.88, 0.79, 0.70, 0.30))
	_mist_plane(Vector3(cx0, 1.9, w + 7.4), Vector2(5.6, 4.2), Color(0.89, 0.80, 0.72, 0.60))
	_mist_plane(Vector3(cx0, 1.9, w + 9.6), Vector2(5.8, 4.4), Color(0.90, 0.82, 0.74, 0.95))
	# koridor zemini (görsel sise kadar uzar; collision bariyere kadar yeter)
	var cfloor := MeshInstance3D.new()
	var cfbox := BoxMesh.new()
	cfbox.size = Vector3(5.4, 0.1, 14.0)
	cfbox.material = _grass_mat
	cfloor.mesh = cfbox
	cfloor.position = Vector3(cx0, -0.045, w + 6.3)
	nav.add_child(cfloor)
	var cfcol := CollisionShape3D.new()
	var cfshape := BoxShape3D.new()
	cfshape.size = Vector3(5.4, 1.0, 7.2)
	cfcol.shape = cfshape
	cfcol.position = Vector3(cx0, -0.5, w + 2.9)
	walls_body.add_child(cfcol)

	# içeride simetrik 4 çit küpü: siper
	for off in [Vector3(w * 0.3, 0, w * 0.38), Vector3(w * 0.7, 0, w * 0.38),
			Vector3(w * 0.3, 0, w * 0.72), Vector3(w * 0.7, 0, w * 0.72)]:
		var cube := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(2.4, 1.7, 2.4)
		if _hedge_mats.is_empty():
			_place_hedge(Vector3(0, -50, 0), false)  # mat cache'i doldur (görünmez)
		cbox.material = _hedge_mats[rng.randi() % _hedge_mats.size()]
		cube.mesh = cbox
		cube.position = off + Vector3(0, 0.85, 0)
		nav.add_child(cube)
		var ccol := CollisionShape3D.new()
		var cshape := BoxShape3D.new()
		cshape.size = cbox.size
		ccol.shape = cshape
		ccol.position = cube.position
		walls_body.add_child(ccol)

	_decorate_arena(w)
	_flush_wall_tufts()

	# oyuncu koridorun içinde doğar, çitlerin arasından arenaya yürüyerek çıkar
	player.global_position = Vector3(w / 2.0, 0.2, w + 3.4)
	player.rotation.y = 0.0  # kuzeye, şato kapısına bakar

	_arena_size = Vector2(w, w)
	_gate_pos = Vector3(w / 2.0, 0, 2.6)
	_boss_name = "ÇÜRÜMÜŞ BAHÇIVAN"
	_build_stage_ui()
	_build_boss_bar()

	nav.bake_navigation_mesh()
	await nav.bake_finished
	await get_tree().create_timer(1.6).timeout
	if not _stage_over:
		await _boss_intro("ÇÜRÜMÜŞ BAHÇIVAN",
				"BAHÇEME HOŞ GELDİN. ÇÜRÜYEN HER ŞEY GİBİ SEN DE BURADA KALACAKSIN.",
				Color(0.55, 0.9, 0.45), SND_BOSS_GROAN)
		if not _stage_over:
			_spawn_boss(Vector3(w / 2.0, 0.1, 9.0), {
				"hp": 1200.0, "speed": 2.3, "damage": 24.0, "range": 3.2,
				"cooldown": 1.7, "xp": 350, "gold": 160, "scale": 1.5,
				"roar_pitch": 1.0, "fx_color": Color(0.55, 0.9, 0.45),
				"entrance": "garden", "roar": SND_BOSS_GROAN,
			})


func _build_boss_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)

	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	holder.offset_top = 70
	holder.offset_left = -260
	holder.offset_right = 260
	layer.add_child(holder)

	var name_label := Label.new()
	name_label.text = _boss_name
	name_label.add_theme_font_override("font", MenuUI.FONT)
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.3))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(name_label)

	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(520, 22)
	_boss_bar.show_percentage = false
	_boss_bar.max_value = 1.0
	_boss_bar.value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.06, 0.06, 0.85)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.82, 0.18, 0.12)
	fill.set_corner_radius_all(4)
	_boss_bar.add_theme_stylebox_override("background", bg)
	_boss_bar.add_theme_stylebox_override("fill", fill)
	holder.add_child(_boss_bar)

	holder.modulate.a = 0.0  # boss doğunca görünür


func _spawn_boss(pos: Vector3, cfg: Dictionary) -> void:
	_boss = zombie_scene.instantiate()
	_boss.is_boss = true
	_boss.model_path = cfg.get("model", "")
	_boss.base_scale = cfg.get("base", 0.6)
	_boss.model_scale = cfg.get("scale", 1.5)
	_boss.max_health = cfg.get("hp", 1200.0)
	_boss.speed = cfg.get("speed", 2.3)
	_boss.attack_damage = cfg.get("damage", 24.0)
	_boss.attack_range = cfg.get("range", 3.2)
	_boss.attack_cooldown = cfg.get("cooldown", 1.7)
	_boss.xp_value = cfg.get("xp", 350)
	_boss.gold_value = cfg.get("gold", 160)
	if cfg.has("voice"):  # boss'a özel dövüş sesi seti (iskelet: kemik takırtısı)
		var v: Dictionary = cfg["voice"]
		_boss.voice_groan = v.get("groan", _boss.voice_groan)
		_boss.voice_attack = v.get("attack", _boss.voice_attack)
		_boss.voice_hurt = v.get("hurt", _boss.voice_hurt)
		_boss.voice_death = v.get("death", _boss.voice_death)
	add_child(_boss)
	_boss.global_position = pos
	_boss.health_changed.connect(_on_boss_health)
	_boss.died.connect(_on_boss_died)

	# dramatik beliriş: türüne göre (iskelet: gümbürtü+toz / bahçıvan: çamur+spor) + ses + yükseliş
	_boss_entrance_fx(pos, cfg.get("fx_color", Color(0.85, 0.7, 0.4)), cfg.get("entrance", "skeleton"))
	var roar := AudioStreamPlayer3D.new()
	roar.stream = cfg.get("roar", SND_BOSS_ROAR)
	roar.pitch_scale = cfg.get("roar_pitch", 1.0)
	roar.unit_size = 16.0
	roar.max_db = 6.0
	roar.position = pos + Vector3(0, 1.6, 0)
	add_child(roar)
	roar.play()
	roar.finished.connect(roar.queue_free)
	var full_scale: Vector3 = _boss.scale
	_boss.scale = full_scale * Vector3(0.7, 0.04, 0.7)  # yerden fışkırarak büyür
	var rise := _boss.create_tween()
	rise.tween_property(_boss, "scale", full_scale, 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var bar_holder := _boss_bar.get_parent() as Control
	var show_bar := bar_holder.create_tween()
	show_bar.tween_property(bar_holder, "modulate:a", 1.0, 0.8)

	# faz 2 destek çağrısı zamanlayıcısı (faz 2'de aktifleşir)
	var summon := Timer.new()
	summon.name = "SummonTimer"
	summon.wait_time = 8.0
	summon.timeout.connect(_summon_minions)
	add_child(summon)


func _on_boss_health(health: float, max_health: float) -> void:
	if _boss_bar != null:
		_boss_bar.value = health / max_health
	if not _boss_phase2 and health <= max_health * 0.5 and health > 0.0:
		# FAZ 2: öfke — hızlanır ve destek çağırır
		_boss_phase2 = true
		_boss.speed *= 1.45
		($SummonTimer as Timer).start()
		_summon_minions()
		_stage_label.text = "%s ÖFKELENDİ!" % _boss_name
		_stage_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		if _biome == "cerberus":
			_cerberus_enrage()


func _summon_minions() -> void:
	if _stage_over or _boss == null or _alive >= 5:
		return
	var w := _arena_size.x
	var d := _arena_size.y
	# arena ortasında açık zemine, halka üzerinde rastgele aç → süslerin üstüne denk gelmez
	var cx := w * 0.5
	var cz := d * 0.5
	var ring := minf(w, d) * 0.30
	for i in 2:
		var z := zombie_scene.instantiate()
		if _biome == "cerberus":
			# balkonda Cerberus cehennem kurtları çağırır (iskelet değil)
			z.model_path = CERBERUS_WOLF
			z.base_scale = 1.05
			z.model_scale = 0.72
			z.max_health = 90.0
			z.speed = 4.6
			z.attack_logical = "Punch"
			z.skip_rise = true
			z.xp_value = 35
			z.gold_value = 12
		elif _biome == "castle_boss":
			# taht salonunda İskelet Lord iskelet askerleri çağırır
			z.model_path = SKELETON_MINION
			z.base_scale = SKELETON_BASE_SCALE
			z.model_scale = SKELETON_BASE_SCALE
			z.max_health = 75.0
			z.speed = 4.0
			z.xp_value = 30
			z.gold_value = 10
		else:
			z.max_health = 60.0
			z.speed = 3.6
			z.xp_value = 25
			z.gold_value = 8
		add_child(z)
		var ang := rng.randf() * TAU
		z.global_position = Vector3(cx + cos(ang) * ring, 0.6, cz + sin(ang) * ring)
		_alive += 1
		z.died.connect(_on_zombie_died)


func _on_boss_died() -> void:
	if has_node("SummonTimer"):
		($SummonTimer as Timer).stop()
	var bar_holder := _boss_bar.get_parent() as Control
	var hide_bar := bar_holder.create_tween()
	hide_bar.tween_property(bar_holder, "modulate:a", 0.0, 1.0)

	_stage_label.text = "%s YENİLDİ!" % _boss_name
	_stage_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.4))
	_stage_label.scale = Vector2(1.5, 1.5)
	var pop := _stage_label.create_tween()
	pop.tween_property(_stage_label, "scale", Vector2.ONE, 0.4)

	if _biome == "cerberus":
		_on_cerberus_defeated()
		return

	# boss ganimeti: BEDAVA yüksek rarity sandık + kapının önünde portal
	var chest := StaticBody3D.new()
	chest.set_script(CHEST_SCRIPT)
	chest.set("free_chest", true)
	chest.set("rarity_boost", 3 if _biome == "castle_boss" else 2)
	nav.add_child(chest)
	chest.position = _gate_pos + Vector3(-4.0, 0, 2.4)
	chest.rotation.y = PI * 0.15

	_spawn_portal(_gate_pos)
	_exit_unlocked = true
	_exit_prompt.text = "DERİNLERE İNİŞ" if _biome == "castle_boss" else "ŞATO KAPISI"


# ---------- şato taht salonu (kat 12 boss'u) ----------

func _build_castle_hall() -> void:
	var hw := 9
	var hd := 6
	var w := hw * CELL
	var d := hd * CELL
	maze = {"w": hw, "h": hd}  # _build_ceiling boyutları buradan okur

	var walls_body := StaticBody3D.new()
	walls_body.name = "WallColliders"
	nav.add_child(walls_body)

	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(w + 8.0, 1.0, d + 8.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(w / 2.0, -0.5, d / 2.0)
	walls_body.add_child(floor_shape)

	for x in hw:
		for y in hd:
			var tile := _spawn_piece(_pick_weighted(FLOOR_PIECES), nav)
			tile.position = _cell_center(Vector2i(x, y))

	# çevre duvarları (taş; meşaleler _place_wall içinden gelir) + köşe sütunları
	for i in hw:
		_place_wall(walls_body, Vector3((i + 0.5) * CELL, 0, 0), false)
		if i != hw / 2:  # güney ortası: mahzen kapısı boşluğu
			_place_wall(walls_body, Vector3((i + 0.5) * CELL, 0, d), false)
	_build_castle_gate(w, d)  # giriş kapısı (oyuncu girince arkadan kapanır)
	# yan duvarlar boyunca bir sıra kemerli vitray penceresi (katedral hissi)
	var win_cols := [Color(0.95, 0.72, 0.28), Color(0.42, 0.6, 1.0),
			Color(0.88, 0.28, 0.32), Color(0.5, 0.85, 0.6)]
	for j in hd:
		var zc := (j + 0.5) * CELL
		if j >= 1 and j <= 4:  # köşeler (taht ucu / kapı ucu) hariç hepsi pencere
			var wc: Color = win_cols[(j - 1) % win_cols.size()]
			_place_castle_window(walls_body, Vector3(0, 0, zc), 1.0, wc)
			_place_castle_window(walls_body, Vector3(w, 0, zc), -1.0, wc)
		else:
			_place_wall(walls_body, Vector3(0, 0, zc), true)
			_place_wall(walls_body, Vector3(w, 0, zc), true)
	for cx in [0.0, w]:
		for cz in [0.0, d]:
			var corner := _spawn_piece("pillar.gltf.glb", nav)
			corner.position = Vector3(cx, 0, cz)

	_build_ceiling()

	# iç sütun sıraları: salona ritim + siper
	for px in [w / 3.0, 2.0 * w / 3.0]:
		for pz in [d / 3.0, 2.0 * d / 3.0]:
			var pillar := _spawn_piece("pillar.gltf.glb", nav)
			pillar.position = Vector3(px, 0, pz)
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.2, WALL_H, 1.2)
			col.shape = box
			col.position = Vector3(px, WALL_H / 2.0, pz)
			walls_body.add_child(col)
			# her iç sütunun tepesinde sıcak ışık kazanı — salon artık karanlık değil
			_pillar_fire(Vector3(px, 3.4, pz))

	_light_castle_hall(w, d)

	# taht ucu (kuzey): kızıl sancaklar arkasında yükselen taş taht
	var cxm := w / 2.0
	for bx in [-4.0, 0.0, 4.0]:
		var banner := _spawn_piece("banner_patternA_red.gltf.glb", nav)
		banner.position = Vector3(cxm + bx, 2.6, 0.6)
	_build_throne(Vector3(cxm, 0.0, 2.0))

	# tahtın önünden kapıya uzanan kızıl halı (zeminin biraz üstünde, taşlara gömülmez)
	var carpet := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(3.4, 0.06, d - 9.0)  # taht kaidesinin önünde başlar
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.45, 0.07, 0.07)
	cmat.roughness = 1.0
	cbox.material = cmat
	carpet.mesh = cbox
	carpet.position = Vector3(cxm, 0.07, (5.0 + (d - 2.0)) / 2.0)
	add_child(carpet)
	# halı kenarı: ince altın şeritler
	for ex: float in [-1.7, 1.7]:
		var trim := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.14, 0.07, d - 9.0)
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.72, 0.56, 0.2)
		tmat.metallic = 0.7
		tmat.roughness = 0.35
		tb.material = tmat
		trim.mesh = tb
		trim.position = Vector3(cxm + ex, 0.075, (5.0 + (d - 2.0)) / 2.0)
		add_child(trim)

	# ziyafet masaları (devrik sandalyeli) — sütun sıralarının iç hattında
	for tx in [cxm - 7.5, cxm + 7.5]:
		_spawn_prop("table_long_decorated_A.gltf.glb", Vector3(tx, 0, d * 0.45), PI / 2.0)
		_spawn_prop("table_long_tablecloth_decorated_A.gltf.glb", Vector3(tx, 0, d * 0.68), PI / 2.0)
		var tcandle := _spawn_piece("candle_lit.gltf.glb", nav)
		tcandle.position = Vector3(tx, 1.0, d * 0.45)
		var tskull := _spawn_piece(HW + "skull.gltf", nav)
		tskull.position = Vector3(tx, 1.0, d * 0.68)
		for i in 2:
			_spawn_prop("chair.gltf.glb", Vector3(tx + rng.randf_range(-1.2, 1.2), 0,
					d * rng.randf_range(0.5, 0.62)), rng.randf() * TAU)

	# güney duvar dipleri: raflar + fıçı/kasa yığınları
	_spawn_prop("shelf_large.gltf.glb", Vector3(5.0, 0, d - 1.0), PI)
	_spawn_prop("shelf_small_candles.gltf.glb", Vector3(w - 5.0, 0, d - 1.0), PI)
	_spawn_prop("barrel_small_stack.gltf.glb", Vector3(2.5, 0, d - 2.5), rng.randf() * TAU)
	_spawn_prop("crates_stacked.gltf.glb", Vector3(w - 2.5, 0, d - 2.5), rng.randf() * TAU)

	# sütun diplerine mumlar
	for px in [w / 3.0, 2.0 * w / 3.0]:
		var pcandle := _spawn_piece("candle_triple.gltf.glb", nav)
		pcandle.position = Vector3(px + 0.9, 0, d / 3.0 + 0.9)

	# duvar diplerine tabutlar + yerlere kemik kırıntıları
	for sx in [-8.0, 8.0]:
		_spawn_prop(HW + "coffin.gltf", Vector3(cxm + sx, 0, 2.4), 0.0)
	_spawn_prop(HW + "coffin_decorated.gltf", Vector3(2.2, 0, d * 0.5), PI / 2.0)
	_spawn_prop(HW + "coffin.gltf", Vector3(w - 2.2, 0, d * 0.58), PI / 2.0)
	for i in 10:
		var bone := _spawn_piece(HW + ["bone_A.gltf", "bone_B.gltf", "skull.gltf", "ribcage.gltf"][rng.randi() % 4], self)
		bone.position = Vector3(rng.randf_range(4.0, w - 4.0), 0, rng.randf_range(7.0, d - 5.0))
		bone.rotation.y = rng.randf() * TAU

	player.global_position = Vector3(cxm, 0.2, d - 3.0)
	player.rotation.y = 0.0  # tahta doğru bakar

	_arena_size = Vector2(w, d)
	_gate_pos = Vector3(cxm, 0, d * 0.5)  # portal salon ortasına (taht/masa önüne değil)
	_boss_name = "İSKELET LORDU"
	_build_stage_ui()
	_build_boss_bar()

	nav.bake_navigation_mesh()
	await nav.bake_finished
	await get_tree().create_timer(0.8).timeout
	_close_arena_gate()  # mahzen kapısı arkadan çarparak kapanır — geri dönüş yok
	await get_tree().create_timer(1.2).timeout
	if not _stage_over:
		await _boss_intro("İSKELET LORDU",
				"DİZ ÇÖK, FÂNİ. BU TAHT VE BU LANET EBEDİYEN BENİMDİR.",
				Color(0.62, 0.82, 1.0), SND_BOSS_ROAR)
		if not _stage_over:
			_spawn_boss(Vector3(cxm, 0.1, 8.0), {
				"model": SKELETON_WARRIOR, "base": SKELETON_BASE_SCALE, "scale": 1.8,
				"hp": 2400.0, "speed": 2.6, "damage": 30.0, "range": 3.4,
				"cooldown": 1.5, "xp": 600, "gold": 320,
				"roar_pitch": 0.82, "fx_color": Color(0.6, 0.82, 1.0),
			})


func _build_throne(base: Vector3) -> void:
	## taş taht: basamaklı kaide + yüksek arkalık + kızıl minder + altın süs + iki ateş kazanı.
	## +z'ye (oyuncuya) bakar; arkalık kuzeye, sancakların önüne gelir.
	var root := Node3D.new()
	root.position = base
	add_child(root)

	# taht çarpışması: oyuncu/zombi tahta giremesin (kaide + koltuk hacmi)
	var body := StaticBody3D.new()
	nav.add_child(body)
	body.global_position = base
	var bcol := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(5.6, 4.6, 4.0)
	bcol.shape = bbox
	bcol.position = Vector3(0, 2.3, -0.2)
	body.add_child(bcol)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.17, 0.17, 0.2)
	stone.roughness = 0.95
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.72, 0.56, 0.2)
	gold.metallic = 0.85
	gold.roughness = 0.32
	gold.emission_enabled = true
	gold.emission = Color(0.5, 0.36, 0.08)
	gold.emission_energy_multiplier = 0.25
	var cushion := StandardMaterial3D.new()
	cushion.albedo_color = Color(0.46, 0.06, 0.06)
	cushion.roughness = 1.0

	var add_box := func(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		mi.position = pos
		root.add_child(mi)

	# basamaklı taş kaide (geniş → dar)
	add_box.call(Vector3(6.4, 0.4, 4.4), Vector3(0, 0.2, 0.4), stone)
	add_box.call(Vector3(4.8, 0.4, 3.2), Vector3(0, 0.6, 0.1), stone)
	# oturak + yüksek arkalık + kol dayama
	add_box.call(Vector3(2.0, 0.5, 1.7), Vector3(0, 1.05, 0.1), stone)
	add_box.call(Vector3(2.0, 2.8, 0.35), Vector3(0, 2.2, -0.65), stone)
	for sx: float in [-0.95, 0.95]:
		add_box.call(Vector3(0.32, 0.7, 1.6), Vector3(sx, 1.55, 0.1), stone)
	# kızıl minderler (oturak + sırt)
	add_box.call(Vector3(1.7, 0.2, 1.4), Vector3(0, 1.38, 0.15), cushion)
	add_box.call(Vector3(1.6, 1.7, 0.18), Vector3(0, 2.1, -0.45), cushion)
	# altın süs: arkalık tepesi + iki tepe topuzu + basamak şeridi
	add_box.call(Vector3(2.2, 0.22, 0.5), Vector3(0, 3.65, -0.6), gold)
	for sx: float in [-0.85, 0.85]:
		add_box.call(Vector3(0.34, 0.55, 0.34), Vector3(sx, 3.95, -0.6), gold)
	add_box.call(Vector3(4.8, 0.08, 0.2), Vector3(0, 0.82, 1.6), gold)

	# tahtı çevreleyen iki ateş kazanı (sıcak ışık + alev)
	for sx: float in [-2.7, 2.7]:
		var bowl := _spawn_piece("torch_lit.gltf.glb", root)
		bowl.position = Vector3(sx, 0.8, 1.4)
		_pillar_fire(base + Vector3(sx, 1.0, 1.4))

	# tahtın üstüne odaklı sıcak ışık (kahraman aydınlatması)
	var key := OmniLight3D.new()
	key.light_color = Color(1.0, 0.74, 0.4)
	key.light_energy = 2.6
	key.omni_range = 11.0
	key.position = base + Vector3(0, 4.4, 1.5)
	add_child(key)


func _place_castle_window(walls_body: StaticBody3D, pos: Vector3, inward: float, glass_col: Color) -> void:
	## kemerli vitray penceresi (inward: +1 batı duvarı, -1 doğu duvarı).
	## yan duvarlar Z boyunca uzanır → normal duvarla aynı yön (rot.y = PI/2).
	var win := _spawn_piece("wall_archedwindow_open.gltf.glb", nav)
	win.position = pos
	win.rotation.y = PI / 2.0

	# duvar çarpışması (pencere açık olsa da oyuncu/zombi geçemesin)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, WALL_H, CELL)
	col.shape = box
	col.position = pos + Vector3(0, WALL_H / 2.0, 0)
	walls_body.add_child(col)

	# vitray cam: pencere boşluğunu dolduran renkli, parlayan panel (odaya bakar)
	var glass := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.7, 2.8)
	glass.mesh = q
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(glass_col.r, glass_col.g, glass_col.b, 0.85)
	gm.emission_enabled = true
	gm.emission = glass_col
	gm.emission_energy_multiplier = 1.6
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = gm
	glass.position = pos + Vector3(inward * 0.06, 2.2, 0)
	glass.rotation.y = -inward * PI / 2.0  # panel normali odaya döner
	add_child(glass)

	# camdan içeri sızan renkli ışık
	var light := OmniLight3D.new()
	light.light_color = glass_col.lightened(0.15)
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.position = pos + Vector3(inward * 1.0, 2.4, 0)
	add_child(light)


func _light_castle_hall(w: float, d: float) -> void:
	## taht salonuna genel sıcak dolgu ışığı — köşeler ve orta hat artık karanlık kalmaz
	for zc: float in [d * 0.25, d * 0.5, d * 0.78]:
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.78, 0.5)
		fill.light_energy = 1.4
		fill.omni_range = 14.0
		fill.position = Vector3(w * 0.5, 3.4, zc)
		add_child(fill)


func _boss_intro(boss_name: String, taunt: String, color: Color, snd: AudioStream) -> void:
	## boss belirmeden önce sinematik isim/replik kartı (letterbox + sese göre kükreme/inilti)
	var layer := CanvasLayer.new()
	layer.layer = 11
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.modulate.a = 0.0
	layer.add_child(root)

	var top := ColorRect.new()
	top.color = Color(0, 0, 0, 0.9)
	top.anchor_right = 1.0
	top.offset_bottom = 80.0
	root.add_child(top)
	var bot := ColorRect.new()
	bot.color = Color(0, 0, 0, 0.9)
	bot.anchor_top = 1.0
	bot.anchor_right = 1.0
	bot.anchor_bottom = 1.0
	bot.offset_top = -80.0
	root.add_child(bot)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	root.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = boss_name
	name_lbl.add_theme_font_override("font", MenuUI.FONT)
	name_lbl.add_theme_font_size_override("font_size", 80)
	name_lbl.add_theme_color_override("font_color", color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var taunt_lbl := Label.new()
	taunt_lbl.text = "“%s”" % taunt
	taunt_lbl.add_theme_font_override("font", MenuUI.FONT)
	taunt_lbl.add_theme_font_size_override("font_size", 26)
	taunt_lbl.add_theme_color_override("font_color", Color(0.86, 0.83, 0.74))
	taunt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(taunt_lbl)

	var roar := AudioStreamPlayer.new()
	roar.stream = snd
	roar.volume_db = -3.0
	add_child(roar)
	roar.play()
	roar.finished.connect(roar.queue_free)

	var tin := root.create_tween()
	tin.tween_property(root, "modulate:a", 1.0, 0.5)
	await get_tree().create_timer(2.7).timeout
	var tout := root.create_tween()
	tout.tween_property(root, "modulate:a", 0.0, 0.6)
	await tout.finished
	layer.queue_free()


func _boss_entrance_fx(pos: Vector3, color: Color, kind: String) -> void:
	## yerden beliriş — türe göre farklı:
	##  iskelet: taş gümbürtüsü + gri toz/moloz patlaması (sert, mineral)
	##  bahçıvan: ıslak çamur sesi + yukarı süzülen yeşil spor/yaprak bulutu (organik)
	var garden := kind == "garden"

	var snd := AudioStreamPlayer3D.new()
	snd.stream = SND_BOSS_SQUELCH if garden else SND_BOSS_RUMBLE
	snd.unit_size = 18.0
	snd.max_db = 8.0
	snd.position = pos
	add_child(snd)
	snd.play()
	snd.finished.connect(snd.queue_free)

	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 0.0
	flash.omni_range = 13.0
	flash.position = pos + Vector3(0, 1.6, 0)
	add_child(flash)
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 7.0 if garden else 8.0, 0.14 if garden else 0.12)
	ft.tween_property(flash, "light_energy", 0.0, 1.1 if garden else 0.9)
	ft.tween_callback(flash.queue_free)

	var p := CPUParticles3D.new()
	p.position = pos + Vector3(0, 0.2, 0)
	p.one_shot = true
	p.explosiveness = 0.7 if garden else 0.92
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if garden:
		# yeşil spor bulutu: bol, hafif, yukarı süzülüp asılı kalır
		p.amount = 70
		p.lifetime = 2.0
		p.direction = Vector3(0, 1, 0)
		p.spread = 85.0
		p.initial_velocity_min = 1.2
		p.initial_velocity_max = 3.5
		p.gravity = Vector3(0, -0.6, 0)  # neredeyse asılı kalan sporlar
		p.damping_min = 1.2
		p.damping_max = 2.5
		p.scale_amount_min = 0.1
		p.scale_amount_max = 0.3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.5, 0.85, 0.3, 0.9))
		ramp.set_color(1, Color(0.25, 0.55, 0.15, 0.0))
		p.color_ramp = ramp
		pmat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		pmat.albedo_color = Color(0.55, 0.85, 0.35, 0.9)
	else:
		# gri toz/moloz: sert patlama, hızlı düşer
		p.amount = 48
		p.lifetime = 1.2
		p.direction = Vector3(0, 1, 0)
		p.spread = 78.0
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 6.5
		p.gravity = Vector3(0, -8, 0)
		p.scale_amount_min = 0.15
		p.scale_amount_max = 0.45
		pmat.albedo_color = Color(0.42, 0.37, 0.3, 0.85)
	var pmesh := QuadMesh.new()
	pmesh.size = Vector2(0.5, 0.5)
	pmesh.material = pmat
	p.mesh = pmesh
	add_child(p)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


func _build_castle_gate(w: float, d: float) -> void:
	## güney girişe mahzen kapısı: açık başlar, oyuncu girince _close_arena_gate kapatır
	var cxm := w / 2.0
	var frame := _spawn_piece("wall_doorway.glb", nav)
	frame.position = Vector3(cxm, 0, d)
	_gate_body = StaticBody3D.new()
	nav.add_child(_gate_body)
	_gate_body.global_position = Vector3(cxm, 0, d)
	for sgn: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(cxm + sgn * 1.55, 0, d)
		nav.add_child(hinge)
		var leaf := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(1.5, 2.7, 0.16)
		leaf.mesh = lb
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.17, 0.13, 0.1)
		lm.metallic = 0.4
		lm.roughness = 0.7
		leaf.material_override = lm
		leaf.position = Vector3(-sgn * 0.75, 1.35, 0)  # menteşeden açıklığa uzanır
		hinge.add_child(leaf)
		hinge.rotation.y = sgn * deg_to_rad(95.0)  # açık: salon içine savrulmuş
		_gate_leaves.append(hinge)


# ---------- yardımcılar ----------

func _cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0, (c.y + 0.5) * CELL)


func _spawn_piece(piece_file: String, parent: Node) -> Node3D:
	if not _piece_cache.has(piece_file):
		# tam yol verilmişse (örn. Halloween paketi) olduğu gibi, yoksa KayKit zindan klasöründen
		var full := piece_file if piece_file.begins_with("res://") else KAYKIT + piece_file
		_piece_cache[piece_file] = load(full)
	var node: Node3D = (_piece_cache[piece_file] as PackedScene).instantiate()
	parent.add_child(node)
	return node


func _pick_weighted(table: Dictionary) -> String:
	var total := 0
	for k: String in table:
		total += table[k]
	var roll := rng.randi() % total
	for k: String in table:
		roll -= table[k]
		if roll < 0:
			return k
	return table.keys()[0]


# ---------- gökyüzü ortamları (balkon / cennet / cehennem) ----------

func _setup_sky_environment(kind: String) -> void:
	var we: WorldEnvironment = $WorldEnvironment
	var env: Environment = we.environment.duplicate()
	we.environment = env
	var sky := ProceduralSkyMaterial.new()
	var sun := DirectionalLight3D.new()
	if kind == "hell":
		sky.sky_top_color = Color(0.14, 0.03, 0.02)
		sky.sky_horizon_color = Color(0.62, 0.14, 0.04)
		sky.ground_horizon_color = Color(0.5, 0.1, 0.02)
		sky.ground_bottom_color = Color(0.22, 0.03, 0.0)
		env.fog_light_color = Color(0.7, 0.22, 0.06)
		sun.light_color = Color(1.0, 0.45, 0.2)
		sun.rotation_degrees = Vector3(-34, -28, 0)
	elif kind == "heaven":
		sky.sky_top_color = Color(0.42, 0.6, 0.92)
		sky.sky_horizon_color = Color(0.96, 0.98, 1.0)
		sky.ground_horizon_color = Color(0.92, 0.95, 1.0)
		sky.ground_bottom_color = Color(0.82, 0.88, 0.97)
		env.fog_light_color = Color(0.95, 0.97, 1.0)
		sun.light_color = Color(1.0, 0.98, 0.92)
		sun.rotation_degrees = Vector3(-52, 40, 0)
	else:  # cerberus: bulutların üstünde gece
		sky.sky_top_color = Color(0.04, 0.05, 0.14)
		sky.sky_horizon_color = Color(0.2, 0.17, 0.34)
		sky.ground_horizon_color = Color(0.12, 0.12, 0.22)
		sky.ground_bottom_color = Color(0.05, 0.05, 0.12)
		env.fog_light_color = Color(0.3, 0.3, 0.5)
		sun.light_color = Color(0.55, 0.6, 0.95)
		sun.rotation_degrees = Vector3(-42, 25, 0)
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.3
	env.fog_density = 0.004
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)


func _cloud_puff(pos: Vector3, size: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = load("res://assets/fx/flame.png")  # yumuşak radyal → bulut öbeği
	m.albedo_color = col
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_cloud_sea(center: Vector2, kind: String) -> void:
	var col := Color(1, 1, 1, 0.92) if kind == "heaven" else Color(0.55, 0.58, 0.72, 0.85)
	# alt bulut denizi (büyük yatay düzlem)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = col * Color(1, 1, 1, 0.7)
	sea.mesh = pm
	sea.material_override = sm
	sea.position = Vector3(center.x, -6.0, center.y)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	# çevreleyen öbekler
	for i in 60:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(26.0, 90.0)
		var p := Vector3(center.x + cos(ang) * rad, rng.randf_range(-6.0, 1.5),
				center.y + sin(ang) * rad)
		_cloud_puff(p, rng.randf_range(7.0, 18.0), col)


func _build_lava_sea(center: Vector2) -> void:
	# kızgın lav düzlemi + kor parıltısı
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.5, 0.08, 0.02)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.35, 0.05)
	sm.emission_energy_multiplier = 1.6
	sm.roughness = 0.6
	sea.mesh = pm
	sea.material_override = sm
	sea.position = Vector3(center.x, -3.0, center.y)
	add_child(sea)
	for i in 18:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(20.0, 80.0)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.4, 0.1)
		l.light_energy = rng.randf_range(1.5, 3.0)
		l.omni_range = 14.0
		l.position = Vector3(center.x + cos(ang) * rad, -2.0, center.y + sin(ang) * rad)
		add_child(l)


func _brazier(pos: Vector3, color: Color) -> void:
	var stand := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.18
	cyl.height = 1.1
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.1, 0.09, 0.1)
	bm.metallic = 0.6
	cyl.material = bm
	stand.mesh = cyl
	stand.position = pos + Vector3(0, 0.55, 0)
	add_child(stand)
	var fire := CPUParticles3D.new()
	fire.amount = 16
	fire.lifetime = 0.55
	fire.position = pos + Vector3(0, 1.15, 0)
	fire.direction = Vector3(0, 1, 0)
	fire.spread = 18.0
	fire.gravity = Vector3(0, 1.0, 0)
	fire.initial_velocity_min = 0.4
	fire.initial_velocity_max = 1.0
	fire.scale_amount_min = 0.25
	fire.scale_amount_max = 0.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	ramp.set_color(1, color * Color(1, 1, 1, 0.0))
	fire.color_ramp = ramp
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.albedo_texture = load("res://assets/fx/flame.png")
	fire.mesh = QuadMesh.new()
	fire.material_override = fm
	add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.position = pos + Vector3(0, 1.3, 0)
	add_child(light)


func _pillar_fire(pos: Vector3) -> void:
	## sütun tepesinde titreyen ateş kazanı (sıcak ışık + alev)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.22)
	light.light_energy = 2.2
	light.omni_range = 8.0
	light.position = pos + Vector3(0, 0.4, 0)
	add_child(light)
	var fl := light.create_tween().set_loops()
	fl.tween_property(light, "light_energy", 1.7, 0.18)
	fl.tween_property(light, "light_energy", 2.4, 0.22)
	var fire := CPUParticles3D.new()
	fire.amount = 10
	fire.lifetime = 0.5
	fire.position = pos
	fire.direction = Vector3(0, 1, 0)
	fire.spread = 16.0
	fire.gravity = Vector3(0, 0.9, 0)
	fire.initial_velocity_min = 0.3
	fire.initial_velocity_max = 0.8
	fire.scale_amount_min = 0.18
	fire.scale_amount_max = 0.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	ramp.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
	fire.color_ramp = ramp
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.albedo_texture = load("res://assets/fx/flame.png")
	fire.mesh = QuadMesh.new()
	fire.material_override = fm
	add_child(fire)


func _decorate_cerberus_arena(w: float) -> void:
	## geniş balkonu doldurur: sütunlar, ölü ağaçlar, mezar taşları, kemikler, mum
	# yan duvarlar boyunca görkemli sütunlar + tepelerinde ateş kazanı
	for sx in [3.0, w - 3.0]:
		for sz in [6.0, 13.0, 20.0, 27.0, 34.0]:
			var pil := _spawn_piece("pillar.gltf.glb", nav)
			pil.position = Vector3(sx, 0, sz)
			var bowl := _spawn_piece("torch_lit.gltf.glb", nav)
			bowl.position = Vector3(sx, 3.4, sz)
			_pillar_fire(Vector3(sx, 3.6, sz))
	# yan duvarlara kızıl sancaklar
	for bz in [10.0, 22.0, 34.0]:
		var be := _spawn_piece("banner_triple_red.gltf.glb", nav)
		be.position = Vector3(1.0, 2.6, bz)
		be.rotation.y = -PI / 2.0
		var bw := _spawn_piece("banner_triple_red.gltf.glb", nav)
		bw.position = Vector3(w - 1.0, 2.6, bz)
		bw.rotation.y = PI / 2.0
	# kuzey köşeler: devasa ölü ağaçlar (sky'a karşı silüet)
	var t1 := _spawn_piece(HW + "tree_dead_large.gltf", nav)
	t1.position = Vector3(7.0, 0, 6.0)
	t1.rotation.y = rng.randf() * TAU
	var t2 := _spawn_piece(HW + "tree_dead_large.gltf", nav)
	t2.position = Vector3(w - 7.0, 0, 6.0)
	t2.rotation.y = rng.randf() * TAU
	# kuzey: kafataslı kazıklar (cehennem kapısı çerçevesi)
	for px in [w / 2.0 - 7.0, w / 2.0 + 7.0]:
		var post := _spawn_piece(HW + "post_skull.gltf", nav)
		post.position = Vector3(px, 0, 3.0)
	# eşik teması: mezar taşları
	var g1 := _spawn_piece(HW + "gravestone.gltf", nav)
	g1.position = Vector3(w / 2.0 - 10.0, 0, 5.0)
	g1.rotation.y = 0.4
	var g2 := _spawn_piece(HW + "gravemarker_A.gltf", nav)
	g2.position = Vector3(w / 2.0 + 10.0, 0, 6.0)
	g2.rotation.y = -0.5
	var g3 := _spawn_piece(HW + "gravemarker_B.gltf", nav)
	g3.position = Vector3(w / 2.0 - 3.0, 0, 4.0)
	g3.rotation.y = 0.2
	# moloz yığınları
	var r1 := _spawn_piece("rubble_large.gltf.glb", nav)
	r1.position = Vector3(11.0, 0, 4.0)
	var r2 := _spawn_piece("rubble_large.gltf.glb", nav)
	r2.position = Vector3(w - 11.0, 0, 4.0)
	var r3 := _spawn_piece("rubble_half.gltf.glb", nav)
	r3.position = Vector3(4.0, 0, 19.0)
	var r4 := _spawn_piece("rubble_half.gltf.glb", nav)
	r4.position = Vector3(w - 4.0, 0, 19.0)
	# kafatası mumu (ürkütücü yeşilimsi ışık, moloz tepesinde)
	for mp: Vector3 in [Vector3(11.0, 1.0, 4.0), Vector3(w - 11.0, 1.0, 4.0)]:
		var sc := _spawn_piece(HW + "skull_candle.gltf", nav)
		sc.position = mp
		var cl := OmniLight3D.new()
		cl.light_color = Color(0.6, 0.85, 0.5)
		cl.light_energy = 1.2
		cl.omni_range = 4.0
		cl.position = mp + Vector3(0, 0.4, 0)
		add_child(cl)
	# saçılmış kemikler (canavar yuvası)
	var bones := ["bone_A.gltf", "bone_B.gltf", "bone_C.gltf", "skull.gltf"]
	for i in 22:
		var b := _spawn_piece(HW + bones[rng.randi() % bones.size()], nav)
		b.position = Vector3(rng.randf_range(6.0, w - 6.0), 0.05,
				rng.randf_range(3.0, 13.0))
		b.rotation.y = rng.randf() * TAU
		b.scale = Vector3.ONE * rng.randf_range(0.7, 1.0)
	# güney + yan: yaşanmışlık (sandık/varil/tabut)
	var cr := _spawn_piece("crates_stacked.gltf.glb", nav)
	cr.position = Vector3(8.0, 0, w - 3.0)
	var ba := _spawn_piece("barrel_large.gltf.glb", nav)
	ba.position = Vector3(w - 8.0, 0, w - 3.0)
	var bs := _spawn_piece("barrel_small_stack.gltf.glb", nav)
	bs.position = Vector3(w - 10.5, 0, w - 3.2)
	var cof := _spawn_piece(HW + "coffin.gltf", nav)
	cof.position = Vector3(5.0, 0, 28.0)
	cof.rotation.y = 0.3


func _perimeter_collision(walls_body: StaticBody3D, w: float) -> void:
	for spec in [[Vector3(w / 2.0, 0, 0), Vector3(w + 2.0, WALL_H + 3.0, 1.0)],
			[Vector3(w / 2.0, 0, w), Vector3(w + 2.0, WALL_H + 3.0, 1.0)],
			[Vector3(0, 0, w / 2.0), Vector3(1.0, WALL_H + 3.0, w + 2.0)],
			[Vector3(w, 0, w / 2.0), Vector3(1.0, WALL_H + 3.0, w + 2.0)]]:
		var c := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[1]
		c.shape = b
		c.position = (spec[0] as Vector3) + Vector3(0, (spec[1] as Vector3).y / 2.0, 0)
		walls_body.add_child(c)


func _build_terrace_parapet(w: float, cells: int) -> void:
	## kuzey/doğu/batı: alçak korkuluk (bulut manzarası görünür); güney castle cephesidir
	for i in cells:
		var xc := (i + 0.5) * CELL
		var north := _spawn_piece("wall_half.gltf.glb", nav)
		north.position = Vector3(xc, 0, 0)
		var east := _spawn_piece("wall_half.gltf.glb", nav)
		east.position = Vector3(0, 0, xc)
		east.rotation.y = PI / 2.0
		var west := _spawn_piece("wall_half.gltf.glb", nav)
		west.position = Vector3(w, 0, xc)
		west.rotation.y = PI / 2.0
	for cx in [0.0, w]:
		for cz in [0.0, w]:
			var pil := _spawn_piece("pillar.gltf.glb", nav)
			pil.position = Vector3(cx, 0, cz)


func _build_balcony_vista(w: float) -> void:
	## balkonun yüksekte, KOCAMAN bir şatonun parçası olduğunu gösteren dış manzara:
	## güneyde (girişin ardında) ana kale gövdesi + kuleler, yanlarda alçak kanatlar,
	## ufukta dağ silüetleri ve büyük bir ay (bulutların üstünde gece).
	var cx := w / 2.0
	# uzak silüet: neredeyse kara taş (atmosferde silüet okunur, ucuz kutu gibi durmaz)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.05, 0.05, 0.09)
	stone.roughness = 1.0
	var win_mat := StandardMaterial3D.new()
	win_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	win_mat.albedo_color = Color(1.0, 0.66, 0.28)

	var add_box := func(size: Vector3, pos: Vector3) -> void:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		b.material = stone
		mi.mesh = b
		mi.position = pos
		add_child(mi)
	# mazgallı duvar tepesi (merlon dizisi) → kutu değil, kale duvarı okunur
	var crenellate := func(cx0: float, top_y: float, z: float, span: float) -> void:
		var n := int(span / 2.4)
		for k in n:
			var m := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(1.1, 1.4, 1.2)
			b.material = stone
			m.mesh = b
			m.position = Vector3(cx0 - span * 0.5 + (k + 0.5) * (span / n), top_y, z)
			add_child(m)
	var add_tower := func(x: float, z: float, h: float, r: float) -> void:
		var t := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r * 1.12
		cyl.height = h
		cyl.material = stone
		t.mesh = cyl
		t.position = Vector3(x, h / 2.0, z)
		add_child(t)
		var roof := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = r * 1.5
		cone.height = r * 2.6
		cone.material = stone
		roof.mesh = cone
		roof.position = Vector3(x, h + r * 1.3, z)
		add_child(roof)

	# güney: girişin ardında yükselen ana kale gövdesi + mazgallar + kuleler + arka burç
	add_box.call(Vector3(34.0, 30.0, 16.0), Vector3(cx, 15.0, w + 22.0))
	crenellate.call(cx, 30.6, w + 22.0, 32.0)
	add_box.call(Vector3(22.0, 48.0, 12.0), Vector3(cx, 24.0, w + 30.0))
	crenellate.call(cx, 48.6, w + 30.0, 20.0)
	add_tower.call(cx - 19.0, w + 18.0, 46.0, 3.6)
	add_tower.call(cx + 19.0, w + 18.0, 46.0, 3.6)
	# kaleden balkona bakan sıcak pencere ışıkları (yaşayan kale)
	for i in 14:
		var win := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 1.1)
		q.material = win_mat
		win.mesh = q
		win.position = Vector3(cx + rng.randf_range(-14.0, 14.0),
				rng.randf_range(6.0, 26.0), w + 13.9)
		add_child(win)

	# doğu & batı: UZAK kale kanatları (parapetin çok ötesinde, koyu silüet — yakın kutu değil)
	for sgn: float in [-1.0, 1.0]:
		var ex := cx + sgn * (w * 0.5 + 30.0)
		add_box.call(Vector3(22.0, 30.0, 56.0), Vector3(ex, 9.0, cx))
		add_tower.call(ex - sgn * 6.0, cx - 18.0, 36.0, 3.2)
		add_tower.call(ex - sgn * 6.0, cx + 18.0, 36.0, 3.2)

	# ufuk: bulutların üstünden çıkan dağ silüetleri (uzak halka)
	var mtn := StandardMaterial3D.new()
	mtn.albedo_color = Color(0.06, 0.06, 0.11)
	mtn.roughness = 1.0
	for i in 10:
		var ang := TAU * i / 10.0 + rng.randf_range(-0.12, 0.12)
		var dist := rng.randf_range(100.0, 145.0)
		var mh := rng.randf_range(40.0, 72.0)
		var peak := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.1
		pc.bottom_radius = rng.randf_range(18.0, 32.0)
		pc.height = mh
		pc.material = mtn
		peak.mesh = pc
		peak.position = Vector3(cx + cos(ang) * dist, mh * 0.5 - 20.0, cx + sin(ang) * dist)
		add_child(peak)

	# büyük solgun ay (yuvarlak küre, kare değil) — kuzeyde yüksekte
	var moon := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 11.0
	ms.height = 22.0
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.88, 0.91, 1.0)
	mm.emission_enabled = true
	mm.emission = Color(0.72, 0.8, 1.0)
	mm.emission_energy_multiplier = 1.1
	ms.material = mm
	moon.mesh = ms
	moon.position = Vector3(cx - 30.0, 58.0, -100.0)
	add_child(moon)
	# ay halesi (yumuşak parıltı diski)
	var halo := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(40.0, 40.0)
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hmat.albedo_color = Color(0.5, 0.6, 0.9, 0.25)
	hq.material = hmat
	halo.mesh = hq
	halo.position = moon.position
	add_child(halo)
	var ml := DirectionalLight3D.new()
	ml.light_color = Color(0.55, 0.62, 0.95)
	ml.light_energy = 0.3
	ml.rotation_degrees = Vector3(-42, 205, 0)
	add_child(ml)

	# ufukta dağılmış bulut öbekleri (derinlik)
	for i in 12:
		var ang2 := rng.randf() * TAU
		var dd := rng.randf_range(48.0, 90.0)
		_cloud_puff(Vector3(cx + cos(ang2) * dd, rng.randf_range(-3.0, 5.0), cx + sin(ang2) * dd),
				rng.randf_range(12.0, 24.0), Color(0.5, 0.52, 0.7, 0.5))


func _build_water_features(w: float) -> void:
	## yerin içinden geçen DAR su akıntısı (doğu-batı, boydan boya) + üstünde 3 köprü.
	## Su üstünden geçilemez: kanalı GÖRÜNMEZ engel kaplar (visible=false mesh → navmesh engeli
	## + collision → oyuncu giremez). Görünür taş set YOK. Orta köprü boss'un tam karşısında
	## (x=w/2) → boss düz koşar, engele takılmaz; geçişler yalnız köprülerden.
	var cx := w * 0.5
	var cz := w * 0.5            # akıntı orta hatta
	var half := 0.75            # dar akıntı yarı genişliği (su "akıntısı")
	var block_half := 1.0       # görünmez engel yarı genişliği (sudan biraz geniş)
	var bridges: Array[float] = [w * 0.22, w * 0.5, w * 0.78]  # ORTA köprü boss'un karşısında
	var bridge_hw := 3.0        # köprü yarı genişliği
	var gap := 3.2              # engel boşluğu yarısı (köprü altı tamamen açık)

	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.12, 0.4, 0.62, 0.72)  # yarı saydam → zemin "yatak" gibi görünür
	water_mat.metallic = 0.5
	water_mat.roughness = 0.04
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.emission_enabled = true
	water_mat.emission = Color(0.12, 0.34, 0.55)
	water_mat.emission_energy_multiplier = 0.3
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = Color(0.07, 0.09, 0.12)  # koyu ıslak yatak
	bed_mat.roughness = 1.0
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.30, 0.30, 0.34)
	stone.roughness = 0.9

	# yalnız görsel (navmesh/collision yok) — self altına
	var add_box := func(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		b.material = mat
		mi.mesh = b
		mi.position = pos
		add_child(mi)

	# GÖRÜNMEZ engel: visible=false mesh (bake'te navmesh engeli) + StaticBody collision (oyuncu geçemez)
	var add_block := func(size: Vector3, pos: Vector3) -> void:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		mi.mesh = b
		mi.position = pos
		mi.visible = false  # görünmez ama navmesh bake yine de geometriyi okur
		nav.add_child(mi)
		var body := StaticBody3D.new()
		# YALNIZ oyuncuyu durdur: katman 3 (bit 4), player maskesi (5) görür; zombie/boss maskesi (3) görmez
		body.collision_layer = 4
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.position = pos
		body.add_child(cs)
		nav.add_child(body)

	# yürünür köprü döşemesi: ince görünür mesh (navmesh'te yürünür) + collision (üstünde durulur)
	var add_deck := func(size: Vector3, pos: Vector3) -> void:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		b.material = stone
		mi.mesh = b
		mi.position = pos
		nav.add_child(mi)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.position = pos
		body.add_child(cs)
		nav.add_child(body)

	# segment hesaplayıcı: köprü boşlukları dışında kalan [x0,x1] su parçaları
	var stops := bridges.duplicate()
	stops.sort()
	var segments: Array = []
	var seg_a := 0.3
	for bx2: float in stops:
		var seg_b: float = bx2 - gap
		if seg_b > seg_a:
			segments.append([seg_a, seg_b])
		seg_a = bx2 + gap
	if w - 0.3 > seg_a:
		segments.append([seg_a, w - 0.3])

	# koyu ıslak yatak (zemine gömülü) + üstünde yarı saydam ince su tabakası (boydan boya)
	add_box.call(Vector3(w, 0.10, half * 2.0), Vector3(cx, -0.03, cz), bed_mat)
	add_box.call(Vector3(w, 0.06, half * 2.0 - 0.1), Vector3(cx, 0.02, cz), water_mat)

	# görünmez engel: köprü boşlukları hariç tüm kanalı kaplar (suya girilemez, etrafından dolanılamaz)
	for seg: Array in segments:
		var s0: float = seg[0]
		var s1: float = seg[1]
		add_block.call(Vector3(s1 - s0, 2.0, block_half * 2.0),
				Vector3((s0 + s1) * 0.5, 1.0, cz))

	# 3 köprü: düz döşeme (navmesh'te yürünür, kuzey-güneyi bağlar) + görsel korkuluk
	var deck_z := half * 2.0 + 2.6
	for bx: float in bridges:
		add_deck.call(Vector3(bridge_hw * 2.0, 0.18, deck_z), Vector3(bx, 0.09, cz))
		for s: float in [-1.0, 1.0]:
			# köprü kenar korkuluğu (doğu-batı boyu; yürüyüşü engellemez)
			add_box.call(Vector3(0.2, 0.7, deck_z), Vector3(bx + s * (bridge_hw - 0.2), 0.45, cz), stone)
			# korkuluk babaları (dört köşe)
			for ez: float in [-1.0, 1.0]:
				add_box.call(Vector3(0.36, 0.95, 0.36),
						Vector3(bx + s * (bridge_hw - 0.2), 0.55, cz + ez * (deck_z * 0.5 - 0.2)), stone)

	# akıntı köpüğü: SADECE su segmentlerinde (köprülerin üstünde partikül olmaz)
	var framp := Gradient.new()
	framp.set_color(0, Color(0.85, 0.95, 1.0, 0.0))
	framp.add_point(0.2, Color(0.9, 0.97, 1.0, 0.6))
	framp.set_color(1, Color(0.7, 0.85, 1.0, 0.0))
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	for seg: Array in segments:
		var s0: float = seg[0]
		var s1: float = seg[1]
		if s1 - s0 < 1.0:
			continue
		var flow := CPUParticles3D.new()
		flow.amount = maxi(6, int((s1 - s0) * 1.4))
		flow.lifetime = 1.6
		flow.position = Vector3((s0 + s1) * 0.5, 0.07, cz)  # köprü döşemesi altında kalır
		flow.direction = Vector3(1, 0, 0)
		flow.spread = 4.0
		flow.gravity = Vector3.ZERO
		flow.initial_velocity_min = 0.8
		flow.initial_velocity_max = 1.6
		flow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		flow.emission_box_extents = Vector3((s1 - s0) * 0.5 - 0.2, 0.02, half * 0.7)
		flow.scale_amount_min = 0.05
		flow.scale_amount_max = 0.12
		flow.color_ramp = framp
		flow.mesh = QuadMesh.new()
		flow.material_override = fm
		add_child(flow)


# ---------- balkon: Cerberus boss arenası ----------

func _build_cerberus_arena() -> void:
	_setup_sky_environment("cerberus")
	var cells := 11  # Cerberus arenası daha geniş (44 m) → hızlı boss'a kaçış alanı
	var w := cells * CELL

	var walls_body := StaticBody3D.new()
	walls_body.name = "WallColliders"
	nav.add_child(walls_body)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(w + 8.0, 1.0, w + 8.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(w / 2.0, -0.5, w / 2.0)
	walls_body.add_child(floor_shape)

	for x in cells:
		for y in cells:
			var tile := _spawn_piece(_pick_weighted(FLOOR_PIECES), nav)
			tile.position = _cell_center(Vector2i(x, y))

	_perimeter_collision(walls_body, w)
	_build_terrace_parapet(w, cells)

	# güney: şato cephesi + ortada geldiğin balkon kapısı
	var gate_i := cells / 2
	for i in cells:
		var xc := (i + 0.5) * CELL
		if i == gate_i:
			var door := _spawn_piece("wall_doorway.glb", nav)
			door.position = Vector3(xc, 0, w)
		else:
			var seg := _spawn_piece(_pick_weighted(WALL_PIECES), nav)
			seg.position = Vector3(xc, 0, w)
	# güney duvar boyu kızıl sancaklar
	for bx in [-6.0, 0.0, 6.0]:
		var banner := _spawn_piece("banner_patternA_red.gltf.glb", nav)
		banner.position = Vector3(w / 2.0 + bx, 2.6, w - 0.6)

	_build_cloud_sea(Vector2(w / 2.0, w / 2.0), "cerberus")

	# köşelere ateş kazanları (sıcak kontrast)
	for cx in [4.0, w - 4.0]:
		for cz in [4.0, w - 4.0]:
			_brazier(Vector3(cx, 0, cz), Color(1.0, 0.55, 0.2))

	_decorate_cerberus_arena(w)
	_build_balcony_vista(w)
	_build_water_features(w)

	player.global_position = Vector3(w / 2.0, 0.2, w - 3.0)
	player.rotation.y = 0.0  # kuzeye, arenaya bakar

	_arena_size = Vector2(w, w)
	_gate_pos = Vector3(w * 0.5, 0, w * 0.5)  # orta köprünün üstünde (su üstünde değil)
	_boss_name = "CERBERUS"
	_build_stage_ui()
	_build_boss_bar()

	nav.bake_navigation_mesh()
	await nav.bake_finished
	await _cerberus_intro()
	if not _stage_over:
		_spawn_cerberus(Vector3(w / 2.0, 0.1, 8.0))


func _cerberus_intro() -> void:
	## foreshadow: müzik kesilir, karanlık, hırıltı, satırlar — sonra boss belirir
	_intro_active = true
	player.process_mode = Node.PROCESS_MODE_DISABLED
	Music.fade_out()

	var layer := CanvasLayer.new()
	layer.layer = 13
	add_child(layer)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 26)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(vbox)

	var t := create_tween()
	t.tween_property(black, "color:a", 0.82, 1.0)
	await t.finished

	var snd := AudioStreamPlayer.new()
	snd.stream = load("res://assets/audio/sfx/cerberus_growl.wav")
	snd.volume_db = 2.0
	add_child(snd)
	snd.play()

	for line_text in ["Bulutların ardından derin bir hırlama yükseliyor...",
			"ÜÇ BAŞLI BİR GÖLGE KARANLIKTAN SIYRILIYOR.", "CERBERUS UYANDI."]:
		var l := Label.new()
		l.text = line_text
		l.add_theme_font_override("font", MenuUI.FONT)
		l.add_theme_font_size_override("font_size", 32)
		l.add_theme_color_override("font_color", Color(0.95, 0.45, 0.3))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.modulate.a = 0.0
		vbox.add_child(l)
		var lt := create_tween()
		lt.tween_property(l, "modulate:a", 1.0, 0.7)
		await lt.finished
		await get_tree().create_timer(0.7).timeout

	Music.play_cerberus()
	var t2 := create_tween()
	t2.tween_property(black, "color:a", 0.0, 1.0)
	for c in vbox.get_children():
		t2.parallel().tween_property(c, "modulate:a", 0.0, 0.7)
	await t2.finished
	layer.queue_free()
	if is_instance_valid(snd):
		snd.queue_free()
	player.process_mode = Node.PROCESS_MODE_INHERIT
	_intro_active = false


func _spawn_cerberus(pos: Vector3) -> void:
	_boss = zombie_scene.instantiate()
	_boss.is_boss = true
	_boss.skip_rise = true
	_boss.model_path = CERBERUS_WOLF
	_boss.base_scale = 1.05
	_boss.model_scale = 1.05
	_boss.max_health = 2800.0
	_boss.speed = 4.2
	_boss.attack_damage = 32.0
	_boss.attack_range = 3.6
	_boss.attack_cooldown = 1.2
	_boss.attack_logical = "Punch"
	_boss.xp_value = 800
	_boss.gold_value = 500
	add_child(_boss)
	_boss.global_position = pos
	_boss.health_changed.connect(_on_boss_health)
	_boss.died.connect(_on_boss_died)
	_fire_burst(pos)
	_set_cerberus_collision()
	call_deferred("_attach_cerberus_heads")

	var bar_holder := _boss_bar.get_parent() as Control
	var show_bar := bar_holder.create_tween()
	show_bar.tween_property(bar_holder, "modulate:a", 1.0, 0.8)
	var summon := Timer.new()
	summon.name = "SummonTimer"
	summon.wait_time = 9.0
	summon.timeout.connect(_summon_minions)
	add_child(summon)


func _cerberus_enrage() -> void:
	## faz 2 dramı: üç kafa alevlenir, gözler parlar, ateş şok dalgası + öfke hırıltısı
	if _cerb_heads != null and is_instance_valid(_cerb_heads):
		_cerb_heads.enrage()
	if _boss != null and is_instance_valid(_boss):
		_fire_burst(_boss.global_position)
	var snd := AudioStreamPlayer.new()
	snd.stream = load("res://assets/audio/sfx/cerberus_growl.wav")
	snd.volume_db = 4.0
	add_child(snd)
	snd.play()
	snd.finished.connect(snd.queue_free)


func _attach_cerberus_heads() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var mount: Node = _boss.get_node_or_null("ModelMount")
	if mount == null or mount.get_child_count() == 0:
		return
	var model: Node3D = mount.get_child(0)
	var heads := CERBERUS_HEADS.new()
	mount.add_child(heads)
	# model 180° dönük (zombie.gd) → burun = -model.basis.z
	heads.setup(model, 1.05, -1.0)
	_cerb_heads = heads


func _set_cerberus_collision() -> void:
	var col: CollisionShape3D = _boss.get_node_or_null("Collision")
	if col == null:
		return
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.6, 4.6)
	col.shape = box
	col.position = Vector3(0, 1.3, 0)


func _fire_burst(pos: Vector3) -> void:
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.emitting = true
	ps.amount = 46
	ps.lifetime = 0.8
	ps.explosiveness = 0.9
	ps.position = pos + Vector3(0, 0.6, 0)
	ps.direction = Vector3(0, 1, 0)
	ps.spread = 80.0
	ps.gravity = Vector3(0, -1.5, 0)
	ps.initial_velocity_min = 2.5
	ps.initial_velocity_max = 6.5
	ps.scale_amount_min = 0.5
	ps.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.4, 1.0))
	ramp.set_color(1, Color(0.85, 0.1, 0.02, 0.0))
	ps.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = load("res://assets/fx/flame.png")
	ps.mesh = QuadMesh.new()
	ps.material_override = m
	add_child(ps)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.5, 0.2)
	flash.light_energy = 6.0
	flash.omni_range = 12.0
	flash.position = pos + Vector3(0, 1.0, 0)
	add_child(flash)
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 1.0)
	ft.tween_callback(flash.queue_free)
	get_tree().create_timer(1.2).timeout.connect(ps.queue_free)


# ---------- Cerberus yenildi → cennet/cehennem seçimi ----------

func _on_cerberus_defeated() -> void:
	Music.fade_out()
	await get_tree().create_timer(0.7).timeout
	Music.play_explore()
	var w := _arena_size.x
	var hz := w * 0.42
	_spawn_choice_portal(Vector3(w * 0.32, 0, hz), "heaven")
	_spawn_choice_portal(Vector3(w * 0.68, 0, hz), "hell")
	_stage_label.text = "BİR KAPI SEÇ — CENNET YA DA CEHENNEM"
	_stage_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.7))


func _spawn_choice_portal(pos: Vector3, kind: String) -> void:
	var heaven := kind == "heaven"
	# cennet açık camgöbeği (aynı kaldı), cehennem KIRMIZI (kıvılcımlar da kırmızı)
	var edge_col := Color(0.5, 0.82, 1.0) if heaven else Color(1.0, 0.28, 0.12)
	var core_col := Color(0.88, 0.96, 1.0) if heaven else Color(1.0, 0.58, 0.3)
	var deep_col := Color(0.55, 0.78, 1.0, 0.6) if heaven else Color(0.34, 0.04, 0.03, 0.8)
	var root := Node3D.new()
	root.position = pos + Vector3(0, 1.85, 0)
	add_child(root)
	root.rotation.y = PI if pos.x > _arena_size.x * 0.5 else 0.0  # iki portal da oyuncuya bakar

	# yardımcı: dikey oval düzlem (QuadMesh, XY düzleminde, Y'de uzun)
	var make_disc := func(rad: float, z: float, tex_path: String, col: Color,
			add: bool) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(rad * 2.0, rad * 2.0)
		mi.mesh = q
		mi.scale = Vector3(1.0, 1.45, 1.0)  # dikey oval
		mi.position = Vector3(0, 0, z)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = col
		if tex_path != "":
			m.albedo_texture = load(tex_path)
		if add:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mi.material_override = m
		root.add_child(mi)
		return mi

	# 1) dolu membran (arkaplan derinliği — gökyüzü görünmesin)
	var VTX := "res://assets/fx/portal_vortex.png"
	make_disc.call(0.95, -0.05, VTX, deep_col, false)
	# 2) iki dönen girdap katmanı (parallax derinlik), zıt yönlerde
	var va: MeshInstance3D = make_disc.call(0.95, 0.0, VTX, core_col, true)
	var sa := va.create_tween().set_loops()
	sa.tween_property(va, "rotation:z", va.rotation.z - TAU, 9.0)
	var vb: MeshInstance3D = make_disc.call(0.7, 0.05, VTX, core_col.lightened(0.15), true)
	var sb := vb.create_tween().set_loops()
	sb.tween_property(vb, "rotation:z", vb.rotation.z + TAU, 5.5)

	# 3) çerçeve: dış koyu taş halka + iç parlayan ışık halkası (dikey oval)
	var stone := MeshInstance3D.new()
	var stm := TorusMesh.new()
	stm.inner_radius = 0.98
	stm.outer_radius = 1.2
	stone.mesh = stm
	stone.rotation.x = PI / 2.0
	stone.scale = Vector3(1.0, 1.0, 1.45)
	var stmat := StandardMaterial3D.new()
	stmat.albedo_color = Color(0.16, 0.15, 0.18)
	stmat.roughness = 0.9
	stone.material_override = stmat
	root.add_child(stone)

	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	ring.mesh = tm
	ring.rotation.x = PI / 2.0
	ring.scale = Vector3(1.0, 1.0, 1.45)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = edge_col
	rmat.emission_enabled = true
	rmat.emission = edge_col
	rmat.emission_energy_multiplier = 5.0
	ring.material_override = rmat
	root.add_child(ring)
	var rpulse := ring.create_tween().set_loops()
	rpulse.tween_property(rmat, "emission_energy_multiplier", 3.0, 1.3)
	rpulse.tween_property(rmat, "emission_energy_multiplier", 5.5, 1.3)

	# parıltı nabzı
	var glow := OmniLight3D.new()
	glow.light_color = edge_col
	glow.light_energy = 3.0
	glow.omni_range = 7.0
	root.add_child(glow)
	var pulse := glow.create_tween().set_loops()
	pulse.tween_property(glow, "light_energy", 4.5, 1.0)
	pulse.tween_property(glow, "light_energy", 2.4, 1.0)

	# yükselen kıvılcımlar
	var sp := CPUParticles3D.new()
	sp.amount = 18
	sp.lifetime = 1.6
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 10.0
	sp.gravity = Vector3(0, 0.6, 0)
	sp.initial_velocity_min = 0.5
	sp.initial_velocity_max = 1.2
	sp.scale_amount_min = 0.08
	sp.scale_amount_max = 0.18
	sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 0.8
	var sramp := Gradient.new()
	sramp.set_color(0, core_col)
	sramp.set_color(1, edge_col * Color(1, 1, 1, 0.0))
	sp.color_ramp = sramp
	var spm := StandardMaterial3D.new()
	spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spm.albedo_texture = load("res://assets/fx/flame.png")
	sp.mesh = QuadMesh.new()
	sp.material_override = spm
	root.add_child(sp)

	# etiket
	var label := Label3D.new()
	label.text = "CENNET" if heaven else "CEHENNEM"
	label.font = MenuUI.FONT
	label.font_size = 96
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = edge_col
	label.outline_size = 16
	label.position = Vector3(0, 1.9, 0)
	root.add_child(label)

	# "[E] GİR" ipucu (sadece yakındayken görünür)
	var prompt := Label3D.new()
	prompt.text = "[E] GİR"
	prompt.font = MenuUI.FONT
	prompt.font_size = 56
	prompt.pixel_size = 0.006
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt.modulate = Color(0.97, 0.95, 0.7)
	prompt.outline_size = 12
	prompt.position = Vector3(0, 1.3, 0)
	prompt.visible = false
	root.add_child(prompt)

	# zemin altlığı (portalın durduğu disk)
	var pad := _spawn_piece("floor_tile_large.gltf.glb", self)
	pad.position = pos

	# yakınlık alanı: gir/çık → _portal_near + ipucu (E ile _process tetikler)
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = Vector3(3.0, 3.4, 3.0)
	shape.shape = sbox
	area.add_child(shape)
	area.position = pos + Vector3(0, 1.5, 0)
	area.body_entered.connect(func(body: Node3D) -> void:
		if body.is_in_group("player") and not _choice_made:
			_portal_near = kind
			prompt.visible = true)
	area.body_exited.connect(func(body: Node3D) -> void:
		if body.is_in_group("player"):
			prompt.visible = false
			if _portal_near == kind:
				_portal_near = "")
	add_child(area)


func _on_choice_portal(kind: String) -> void:
	if _choice_made:
		return
	_choice_made = true
	Game.afterlife = kind
	Music.transition()
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.8)
	await tween.finished
	if player != null:
		Game.carry_health = player.health
		Game.carry_ammo = (player.get_node("%Gun") as Node).export_ammo()
	Game.next_stage()
	get_tree().reload_current_scene()


# ---------- cennet / cehennem platformu (şimdilik bitiş) ----------

func _build_afterlife(kind: String) -> void:
	_setup_sky_environment(kind)
	var hell := kind == "hell"
	var w := 7 * CELL

	var walls_body := StaticBody3D.new()
	walls_body.name = "WallColliders"
	nav.add_child(walls_body)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(w + 8.0, 1.0, w + 8.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(w / 2.0, -0.5, w / 2.0)
	walls_body.add_child(floor_shape)

	for x in 7:
		for y in 7:
			var tile := _spawn_piece(_pick_weighted(FLOOR_PIECES), nav)
			tile.position = _cell_center(Vector2i(x, y))

	_perimeter_collision(walls_body, w)
	for i in 7:
		var xc := (i + 0.5) * CELL
		for spec in [Vector3(xc, 0, 0), Vector3(xc, 0, w)]:
			var p := _spawn_piece("wall_half.gltf.glb", nav)
			p.position = spec
		for spec2 in [Vector3(0, 0, xc), Vector3(w, 0, xc)]:
			var p2 := _spawn_piece("wall_half.gltf.glb", nav)
			p2.position = spec2
			p2.rotation.y = PI / 2.0

	if hell:
		_build_lava_sea(Vector2(w / 2.0, w / 2.0))
		for cx in [3.0, w - 3.0]:
			_brazier(Vector3(cx, 0, w - 3.0), Color(1.0, 0.4, 0.1))
	else:
		_build_cloud_sea(Vector2(w / 2.0, w / 2.0), "heaven")

	player.global_position = Vector3(w / 2.0, 0.2, w - 3.0)
	player.rotation.y = 0.0

	_build_stage_ui()

	# kuzeyde parlak ışık hüzmesi: hedef
	var beam_col := Color(1.0, 0.45, 0.15) if hell else Color(0.8, 0.95, 1.0)
	var beam := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.1
	bcyl.bottom_radius = 1.3
	bcyl.height = 9.0
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.albedo_color = beam_col * Color(1, 1, 1, 0.4)
	beam.mesh = bcyl
	beam.material_override = bmat
	beam.position = Vector3(w / 2.0, 4.5, 5.0)
	add_child(beam)
	var blight := OmniLight3D.new()
	blight.light_color = beam_col
	blight.light_energy = 3.0
	blight.omni_range = 10.0
	blight.position = Vector3(w / 2.0, 2.0, 5.0)
	add_child(blight)

	_stage_label.text = "IŞIĞA DOĞRU YÜRÜ"
	_stage_label.add_theme_color_override("font_color", beam_col)

	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = Vector3(4.0, 3.0, 2.0)
	shape.shape = sbox
	area.add_child(shape)
	area.position = Vector3(w / 2.0, 1.5, 5.0)
	area.body_entered.connect(_afterlife_finish)
	add_child(area)

	nav.bake_navigation_mesh()
	await nav.bake_finished


func _afterlife_finish(body: Node3D) -> void:
	if _afterlife_done or not body.is_in_group("player"):
		return
	_afterlife_done = true
	_stage_over = true
	Game.won = true
	Music.transition()
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 1.0)
	await tween.finished
	add_child(RUN_SUMMARY.new())
