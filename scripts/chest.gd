extends StaticBody3D
## Loot sandığı. Görsel durum dili:
##  - boss sandığı (free_chest): ALTIN model + ışık huzmesi + nabız — yazısız fark edilir
##  - alınabilir (altın yetiyor): sıcak altın parıltı
##  - alınamaz (altın yetmiyor): sönük kırmızı kor
##  - açılmış: kararmış model, ışık yok
const CHEST_MODEL := "res://addons/kaykit_dungeon_remastered/assets/gltf/chest.glb"
const GOLD_MODEL := "res://addons/kaykit_dungeon_remastered/assets/gltf/chest_gold.glb"
const OPEN_SND := preload("res://assets/audio/sfx/chest_open.wav")

var cost := 30
var free_chest := false  ## boss ganimeti: bedava + garantili yüksek rarity kart
var rarity_boost := 0
var opened := false
var _player_near := false
var _player: Node3D
var _prompt: Label3D
var _model: Node3D
var _glow: OmniLight3D
var _pulse: Tween
var _beam: MeshInstance3D


func _ready() -> void:
	cost = 0 if free_chest else 25 + 10 * (Game.stage - 1)

	_model = (load(GOLD_MODEL if free_chest else CHEST_MODEL) as PackedScene).instantiate()
	add_child(_model)
	if free_chest:
		_model.scale = Vector3.ONE * 1.5

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 1.3, 1.5)
	col.shape = box
	col.position.y = 0.65
	add_child(col)

	var area := Area3D.new()
	var ashape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.2
	ashape.shape = sphere
	area.add_child(ashape)
	area.position.y = 0.6
	area.body_entered.connect(_on_enter)
	area.body_exited.connect(_on_exit)
	add_child(area)

	_prompt = Label3D.new()
	_prompt.font_size = 64
	_prompt.pixel_size = 0.004
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.outline_size = 12
	_prompt.position.y = 1.9
	_prompt.visible = false
	add_child(_prompt)

	_glow = OmniLight3D.new()
	_glow.position.y = 1.0
	add_child(_glow)

	if free_chest:
		_build_beam()

	Game.gold_changed.connect(func(_g: int) -> void: _update_visuals())
	_update_visuals()


func _build_beam() -> void:
	## boss sandığı: gökyüzüne uzanan altın ışık huzmesi
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.16)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.85
	cyl.height = 7.0
	_beam = MeshInstance3D.new()
	_beam.mesh = cyl
	_beam.material_override = mat
	_beam.position.y = 3.5
	add_child(_beam)


func _update_visuals() -> void:
	if _pulse != null:
		_pulse.kill()
		_pulse = null

	if opened:
		_glow.light_energy = 0.0
		return

	if free_chest:
		_glow.light_color = Color(1.0, 0.82, 0.35)
		_glow.omni_range = 7.0
		_glow.light_energy = 2.4
		_pulse = _glow.create_tween().set_loops()
		_pulse.tween_property(_glow, "light_energy", 3.4, 0.9)
		_pulse.tween_property(_glow, "light_energy", 2.0, 0.9)
	elif Game.gold >= cost:
		# alınabilir: sıcak altın parıltı
		_glow.light_color = Color(1.0, 0.85, 0.4)
		_glow.omni_range = 4.5
		_glow.light_energy = 1.2
	else:
		# para yetmiyor: sönük kırmızı kor
		_glow.light_color = Color(0.8, 0.22, 0.16)
		_glow.omni_range = 3.0
		_glow.light_energy = 0.55

	if _player_near:
		_refresh_prompt()


func _process(_delta: float) -> void:
	if _player_near and not opened and Input.is_action_just_pressed("interact"):
		_try_open()


func _on_enter(body: Node3D) -> void:
	if body.is_in_group("player") and not opened:
		_player_near = true
		_player = body
		_prompt.visible = true
		_refresh_prompt()


func _on_exit(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_near = false
		_prompt.visible = false


func _refresh_prompt() -> void:
	if free_chest:
		_prompt.text = "[E] AÇ"
		_prompt.modulate = Color(0.97, 0.72, 0.2)
	elif Game.gold >= cost:
		_prompt.text = "[E] AÇ — %d ALTIN" % cost
		_prompt.modulate = Color(0.5, 0.95, 0.4)
	else:
		_prompt.text = "%d ALTIN GEREK (sende %d)" % [cost, Game.gold]
		_prompt.modulate = Color(0.9, 0.35, 0.3)


func _try_open() -> void:
	_refresh_prompt()
	if not free_chest and not Game.spend_gold(cost):
		return
	opened = true

	var snd := AudioStreamPlayer3D.new()
	snd.stream = OPEN_SND
	snd.unit_size = 3.0
	snd.volume_db = -4.0
	snd.position.y = 0.6
	add_child(snd)
	snd.play()
	snd.finished.connect(snd.queue_free)

	# açılış parlaması → sonra sön; sandık kararıp "boş" görünür
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	_glow.light_color = Color(1.0, 0.85, 0.4)
	_glow.light_energy = 3.5
	var fade := _glow.create_tween()
	fade.tween_property(_glow, "light_energy", 0.0, 1.6)
	if _beam != null:
		var beam_fade := _beam.create_tween()
		beam_fade.tween_property(_beam, "scale", Vector3(0.01, 1.0, 0.01), 1.2)
		beam_fade.tween_callback(_beam.queue_free)
	_darken_model()

	_give_loot()


func _darken_model() -> void:
	## açılmış sandık: koyu gri tonlama — uzaktan "bitti" okunur
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var count := mesh.get_surface_override_material_count()
		for i in count:
			var base := mesh.mesh.surface_get_material(i)
			if base is StandardMaterial3D:
				var m: StandardMaterial3D = base.duplicate()
				m.albedo_color = m.albedo_color * Color(0.35, 0.33, 0.32)
				mesh.set_surface_override_material(i, m)


func _give_loot() -> void:
	if free_chest:
		# boss ganimeti: garantili yüksek rarity kart çekimi
		await get_tree().create_timer(0.5).timeout
		Game.bonus_draw.emit(rarity_boost)
		_prompt.visible = false
		return

	var roll := randf()
	if roll < 0.40:
		_prompt.text = "BONUS KART!"
		_prompt.modulate = Color(0.7, 0.5, 1.0)
		await get_tree().create_timer(0.6).timeout
		Game.bonus_draw.emit(0)
	elif roll < 0.70:
		_prompt.text = "+50 CAN"
		_prompt.modulate = Color(0.4, 0.95, 0.4)
		_player.heal(50.0)
	else:
		_prompt.text = "+80 MERMİ"
		_prompt.modulate = Color(0.95, 0.9, 0.4)
		var weapon := _player.get_node("%Gun")
		if weapon.has_secondary():
			_choose_weapon_ammo(weapon, 80)  # iki silah var → hangisine?
		else:
			weapon.add_reserve(weapon.active_slot, 80)
			weapon.refresh_stats()
	await get_tree().create_timer(2.0).timeout
	_prompt.visible = false


func _choose_weapon_ammo(weapon: Node, amount: int) -> void:
	## iki silah varken yedek mermiyi hangisine ekleyeceğini seçtiren küçük pencere
	var font: Font = load("res://assets/fonts/ui_font.tres")
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(layer)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 18)
	layer.add_child(vbox)

	var title := Label.new()
	title.text = "+%d MERMİ — HANGİ SİLAHA?" % amount
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for slot in [weapon.active_slot, 1 - weapon.active_slot]:
		var nm: String = weapon.slot_name(slot)
		if nm == "":
			continue
		var rsv: int = weapon.reserve if slot == weapon.active_slot \
				else weapon.inactive_slot_ammo().y
		var btn := Button.new()
		btn.text = "%s   (yedek: %d → %d)" % [nm, rsv, rsv + amount]
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 26)
		btn.custom_minimum_size = Vector2(420, 56)
		btn.pressed.connect(func() -> void:
			weapon.add_reserve(slot, amount)
			weapon.refresh_stats()
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			layer.queue_free())
		vbox.add_child(btn)
