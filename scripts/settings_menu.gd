class_name SettingsMenu
extends CanvasLayer

## Ayarlar: ses seviyeleri + nişangah (seçili şekiller ve renkler arasından).
## ConfigFile ile kalıcı kaydeder: user://settings.cfg

const CFG_PATH := "user://settings.cfg"
const FONT := preload("res://assets/fonts/ui_font.tres")  # Kenney + Türkçe (İŞĞ) fallback

## Sunulan nişangah şekilleri — oyuncu yalnızca bunlardan seçebilir
const CROSSHAIRS: Array[String] = [
	"res://assets/crosshairs/crosshair001.png",  # nokta
	"res://assets/crosshairs/crosshair002.png",  # mini artı
	"res://assets/crosshairs/crosshair007.png",  # klasik artı (varsayılan)
	"res://assets/crosshairs/crosshair026.png",  # köşe braketleri
	"res://assets/crosshairs/crosshair030.png",  # braket + nokta
	"res://assets/crosshairs/crosshair038.png",  # kesik daire
	"res://assets/crosshairs/crosshair061.png",  # dürbün
	"res://assets/crosshairs/crosshair084.png",  # X
]

## Sunulan renkler: [ad, renk]
const COLORS: Array = [
	["BEYAZ", Color(1.0, 1.0, 1.0)],
	["YEŞİL", Color(0.45, 1.0, 0.45)],
	["CAMGÖBEĞİ", Color(0.35, 0.95, 1.0)],
	["SARI", Color(1.0, 0.9, 0.35)],
	["KIRMIZI", Color(1.0, 0.32, 0.28)],
	["PEMBE", Color(1.0, 0.45, 0.85)],
]

# Kaydedilen ayarlar (global erişim için statik)
static var crosshair_path := "res://assets/crosshairs/crosshair007.png"
static var crosshair_color := Color(1.0, 1.0, 1.0)
static var music_volume := 0.8   ## 0..1
static var master_volume := 1.0  ## 0..1
static var _loaded := false

signal closed

var _shape_buttons: Array[TextureButton] = []
var _color_buttons: Array[Button] = []
var _preview: TextureRect


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		crosshair_path = cfg.get_value("display", "crosshair", crosshair_path)
		crosshair_color = cfg.get_value("display", "crosshair_color", crosshair_color)
		music_volume = cfg.get_value("audio", "music", music_volume)
		master_volume = cfg.get_value("audio", "master", master_volume)
	if not CROSSHAIRS.has(crosshair_path):
		crosshair_path = CROSSHAIRS[2]  # eski kayıtlardan gelen serbest seçimleri törpüle
	apply_audio()


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("display", "crosshair", crosshair_path)
	cfg.set_value("display", "crosshair_color", crosshair_color)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "master", master_volume)
	cfg.save(CFG_PATH)


static func apply_audio() -> void:
	## Music bus'ını (yoksa) kur ve seviyeleri uygula
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	var music_idx := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(music_idx, linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_mute(music_idx, music_volume <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)


func _ready() -> void:
	load_settings()
	_build_ui()


func _build_ui() -> void:
	layer = 10

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.set_deferred("custom_minimum_size", Vector2(700, 540))
	root.position = Vector2(-350, -270)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var title := Label.new()
	title.text = "AYARLAR"
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.5, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(HSeparator.new())

	# --- SES ---
	root.add_child(_section_label("SES"))
	root.add_child(_volume_row("MÜZİK", music_volume,
			func(v: float) -> void: SettingsMenu.music_volume = v))
	root.add_child(_volume_row("GENEL SES", master_volume,
			func(v: float) -> void: SettingsMenu.master_volume = v))
	root.add_child(HSeparator.new())

	# --- NİŞANGAH ---
	root.add_child(_section_label("NİŞANGAH"))

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	root.add_child(split)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)

	# Şekiller: tek sıra
	var shape_row := HBoxContainer.new()
	shape_row.add_theme_constant_override("separation", 8)
	left.add_child(shape_row)
	_shape_buttons.clear()
	for i in CROSSHAIRS.size():
		var btn := TextureButton.new()
		btn.texture_normal = load(CROSSHAIRS[i])
		btn.custom_minimum_size = Vector2(56, 56)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.pressed.connect(_on_select_shape.bind(i))
		shape_row.add_child(btn)
		_shape_buttons.append(btn)

	# Renkler: tek sıra yuvarlak örnekler
	var color_label := Label.new()
	color_label.text = "RENK"
	color_label.add_theme_font_override("font", FONT)
	color_label.add_theme_font_size_override("font_size", 18)
	color_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	left.add_child(color_label)

	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 10)
	left.add_child(color_row)
	_color_buttons.clear()
	for i in COLORS.size():
		var c: Color = COLORS[i][1]
		var cbtn := Button.new()
		cbtn.custom_minimum_size = Vector2(48, 48)
		cbtn.tooltip_text = COLORS[i][0]
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(24)
		cbtn.add_theme_stylebox_override("normal", sb)
		cbtn.add_theme_stylebox_override("hover", sb)
		cbtn.add_theme_stylebox_override("pressed", sb)
		cbtn.pressed.connect(_on_select_color.bind(i))
		color_row.add_child(cbtn)
		_color_buttons.append(cbtn)

	# Sağ: büyük önizleme
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(150, 0)
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)

	var pv_label := Label.new()
	pv_label.text = "ÖNİZLEME"
	pv_label.add_theme_font_override("font", FONT)
	pv_label.add_theme_font_size_override("font_size", 18)
	pv_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	pv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(pv_label)

	var pv_frame := PanelContainer.new()
	var pv_sb := StyleBoxFlat.new()
	pv_sb.bg_color = Color(0.12, 0.12, 0.16)
	pv_sb.set_corner_radius_all(8)
	pv_frame.add_theme_stylebox_override("panel", pv_sb)
	pv_frame.custom_minimum_size = Vector2(150, 130)
	right.add_child(pv_frame)

	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(90, 90)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv_frame.add_child(_preview)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	# Geri butonu
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(btn_row)

	var back_btn := Button.new()
	back_btn.text = "KAPAT"
	back_btn.add_theme_font_override("font", FONT)
	back_btn.add_theme_font_size_override("font_size", 24)
	back_btn.custom_minimum_size = Vector2(180, 44)
	back_btn.pressed.connect(_on_close)
	btn_row.add_child(back_btn)

	_refresh_selection()


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	return l


func _volume_row(text: String, value: float, setter: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	l.custom_minimum_size = Vector2(140, 0)
	row.add_child(l)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(380, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var pct := Label.new()
	pct.text = "%d%%" % roundi(value * 100)
	pct.add_theme_font_override("font", FONT)
	pct.add_theme_font_size_override("font_size", 18)
	pct.add_theme_color_override("font_color", Color(0.55, 0.85, 0.4))
	pct.custom_minimum_size = Vector2(60, 0)
	row.add_child(pct)

	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		pct.text = "%d%%" % roundi(v * 100)
		SettingsMenu.apply_audio()
		SettingsMenu.save_settings())
	slider.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			Music.click())  # yeni seviyeyi duyur
	return row


func _on_select_shape(index: int) -> void:
	Music.click()
	crosshair_path = CROSSHAIRS[index]
	save_settings()
	_refresh_selection()
	_push_to_hud()


func _on_select_color(index: int) -> void:
	Music.click()
	crosshair_color = COLORS[index][1]
	save_settings()
	_refresh_selection()
	_push_to_hud()


func _refresh_selection() -> void:
	for i in _shape_buttons.size():
		var sel := CROSSHAIRS[i] == crosshair_path
		_shape_buttons[i].modulate = crosshair_color if sel else Color(1, 1, 1, 0.4)
	for i in _color_buttons.size():
		var csel: bool = COLORS[i][1] == crosshair_color
		_color_buttons[i].modulate = Color(1, 1, 1) if csel else Color(0.5, 0.5, 0.5)
	_preview.texture = load(crosshair_path)
	_preview.modulate = crosshair_color


func _push_to_hud() -> void:
	## HUD nişangahını canlı güncelle (oyun içindeyse)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var hud: Node = player.get_node_or_null("HUD")
		if hud and hud.has_method("update_crosshair"):
			hud.update_crosshair(crosshair_path)


func _on_close() -> void:
	Music.click()
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# aynı ESC basışı duraklatma menüsüne de ulaşıp oyunu devam ettirmesin
		get_viewport().set_input_as_handled()
		_on_close()
