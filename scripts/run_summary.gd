extends CanvasLayer
## Ölünce ana menüye atmadan önce gelen koşu-özeti: bu run'un statları,
## speedrun leaderboard'u, silah tutan 3D zombi ve yeniden başlat/menü/çıkış.

const CHAR_VIEW := preload("res://scripts/character_view.gd")
const GREEN := Color(0.45, 0.85, 0.4)

var _font: Font
var _runs: Array = []


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_font = load("res://assets/fonts/ui_font.tres")
	_runs = Game.end_run()  # leaderboard'a kaydet + sıralı liste al
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.04, 0.97) if Game.won else Color(0.06, 0.02, 0.03, 0.97)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# tepede hikâyeyle ilgili temalı satır
	var story := _label(_story_line(), 22, Color(0.78, 0.7, 0.5))
	story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size = Vector2(720, 0)
	col.add_child(story)

	var title_text := "ÖLDÜN"
	var title_col := Color(0.95, 0.3, 0.28)
	if Game.won:
		title_text = "CEHENNEME İNDİN" if Game.afterlife == "hell" else "GÖKLERE YÜKSELDİN"
		title_col = Color(0.95, 0.45, 0.2) if Game.afterlife == "hell" else Color(0.55, 0.9, 0.95)
	var title := _label(title_text, 56, title_col)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	# --- sol: yeşil borderli karakter kutusu (boylamasına) ---
	row.add_child(_bordered(_make_char_view(), Vector2(260, 380)))

	# --- orta: bu koşunun statları (kutu ızgarası) ---
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 12)
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mid)
	mid.add_child(_label("BU KOŞU", 24, GREEN))
	mid.add_child(_stat_grid())

	# --- sağ: speedrun sıralaması ---
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	right.add_child(_label("SIRALAMA (SPEEDRUN)", 22, Color(0.85, 0.8, 0.4)))
	right.add_child(_leaderboard_box())

	# --- butonlar ---
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 16)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btns)
	btns.add_child(MenuUI.make_button("YENİDEN BAŞLA", _restart))
	btns.add_child(MenuUI.make_button("ANA MENÜ", _menu))
	btns.add_child(MenuUI.make_button("ÇIKIŞ", _quit))


func _make_char_view() -> Control:
	var cv: SubViewportContainer = CHAR_VIEW.new()
	var player := get_tree().get_first_node_in_group("player")
	var weapon: Node = player.get_node_or_null("%Gun") if player != null else null
	cv.setup(weapon)
	return cv


func _bordered(inner: Control, min_size: Vector2) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.09)
	sb.border_color = GREEN
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	inner.custom_minimum_size = min_size
	panel.add_child(inner)
	return panel


func _stat_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var t := Game.run_time
	var rows := [
		["İLERLEME", "Kat %d" % Game.stage, Color(0.6, 0.9, 0.5)],
		["SÜRE", "%02d:%02d" % [int(t) / 60, int(t) % 60], Color(0.4, 0.85, 0.95)],
		["ÖLDÜRÜLEN", str(Game.kills), Color(0.9, 0.45, 0.35)],
		["SEVİYE", str(Game.level), Color(0.8, 0.6, 0.95)],
		["ALTIN", str(Game.gold), Color(0.97, 0.72, 0.2)],
	]
	for r: Array in rows:
		grid.add_child(_stat_box(r[0], r[1], r[2]))
	return grid


func _stat_box(name_text: String, value_text: String, accent: Color) -> PanelContainer:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.16)
	sb.border_color = accent * Color(1, 1, 1, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(165, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	box.add_child(v)
	var n := _label(name_text, 14, Color(0.55, 0.57, 0.62))
	v.add_child(n)
	var val := _label(value_text, 26, accent)
	v.add_child(val)
	return box


func _leaderboard_box() -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.13)
	sb.border_color = Color(0.85, 0.8, 0.4, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(360, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	if _runs.is_empty():
		box.add_child(_label("— henüz kayıt yok —", 16, Color(0.6, 0.62, 0.66)))
		return panel
	for i in mini(_runs.size(), 6):
		var rn: Dictionary = _runs[i]
		var t: float = rn.get("time", 0.0)
		var is_this := int(rn.get("stage", 0)) == Game.stage and absf(t - Game.run_time) < 0.05
		var c := GREEN if is_this else Color(0.82, 0.84, 0.88)
		var line_row := HBoxContainer.new()
		line_row.add_theme_constant_override("separation", 10)
		box.add_child(line_row)
		var rank := _label("%d." % (i + 1), 17, Color(0.6, 0.62, 0.66) if not is_this else GREEN)
		rank.custom_minimum_size = Vector2(26, 0)
		line_row.add_child(rank)
		var info := _label("Kat %d   •   %02d:%02d   •   %d öldürme" % [
			int(rn.get("stage", 1)), int(t) / 60, int(t) % 60, int(rn.get("kills", 0))], 17, c)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_row.add_child(info)
	return panel


func _story_line() -> String:
	## bulunulan bölüme göre temalı, hikâyeye bağlı kapanış cümlesi
	if Game.won:
		if Game.afterlife == "hell":
			return "Cehennemin alev kapısı ardından kapandı.\nLav denizinin ötesinde yeni bir lanet seni bekliyor."
		return "Bulutların kapısı açıldı ve seni içine aldı.\nGöklerin sessizliğinde yolculuğun sürüyor."
	match Game.biome():
		"garden", "garden_boss":
			return "Çürümüş bahçenin toprağı bir bedeni daha kendine çekti.\nAma lanet, sen düşsen de uyumuyor."
		"castle", "castle_boss":
			return "Şatonun soğuk taşları son nefesini yuttu.\nBulutların ardındaki kapı bir sonraki cesareti bekliyor."
		_:
			return "Yolculuğun burada bitti — fakat hikâye henüz tamamlanmadı."


func _label(txt: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _restart() -> void:
	get_tree().paused = false
	Game.reset()
	get_tree().change_scene_to_file("res://scenes/main/dungeon.tscn")


func _menu() -> void:
	get_tree().paused = false
	Game.reset()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _quit() -> void:
	get_tree().quit()
