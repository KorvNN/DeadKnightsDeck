extends CanvasLayer
## ESC ile aç/kapa duraklatma menüsü. Kart ekranı duraklatmışsa devreye girmez.
## Sol sütun: butonlar. Sağ panel: sekmeler — STATLAR / KARTLAR / SİLAH YOLLARI.
## Kartlar seçim ekranındaki görünümle (rarity çerçevesi + ikon + açıklama) listelenir;
## silah yolları kutu-kutu zincir, hiç alınmamış adımlar "?" kalır.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const SettingsMenuScript := preload("res://scripts/settings_menu.gd")
const CHAR_VIEW := preload("res://scripts/character_view.gd")

const RARITY_COLORS: Array[Color] = [
	Color(0.55, 0.58, 0.62),
	Color(0.30, 0.58, 0.95),
	Color(0.68, 0.36, 0.90),
	Color(0.97, 0.72, 0.20),
]
const RARITY_NAMES := ["SIRADAN", "NADİR", "EPİK", "EFSANEVİ"]

var _root: Control
var _stats_tab: Control
var _cards_tab: Control
var _paths_tab: Control
var _pages: Array[ScrollContainer] = []
var _tab_buttons: Array[Button] = []
var _pool: Array[UpgradeCard] = []


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	for file in DirAccess.get_files_at("res://resources/cards"):
		_pool.append(load("res://resources/cards/" + file.trim_suffix(".remap")))
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _root.visible:
		_resume()
	elif not get_tree().paused:
		_pause()
	# tree başka bir şeyce duraklatıldıysa (kart ekranı) dokunma
	get_viewport().set_input_as_handled()


func _pause() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play_menu()
	_refresh_tabs()
	_root.show()


func _resume() -> void:
	_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Music.play_game()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.hide()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.07, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var split := HBoxContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.offset_left = 70.0
	split.offset_top = 56.0
	split.offset_right = -70.0
	split.offset_bottom = -56.0
	split.add_theme_constant_override("separation", 56)
	_root.add_child(split)

	# --- sol: başlık + butonlar ---
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 16)
	left.custom_minimum_size = Vector2(330, 0)
	split.add_child(left)

	left.add_child(MenuUI.make_title("DURAKLATILDI", 42))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	left.add_child(spacer)

	left.add_child(MenuUI.make_button("DEVAM ET", _resume))
	left.add_child(MenuUI.make_button("AYARLAR", _open_settings))
	left.add_child(MenuUI.make_button("YENİDEN BAŞLA", _restart))
	left.add_child(MenuUI.make_button("ANA MENÜ", _to_menu))
	left.add_child(MenuUI.make_button("ÇIKIŞ", get_tree().quit))

	# --- sağ: büyük sekme butonları + içerik paneli ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	split.add_child(right)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 12)
	right.add_child(tab_row)
	for i in 3:
		var btn := Button.new()
		btn.text = ["STATLAR", "KARTLAR", "SİLAH YOLLARI"][i]
		btn.custom_minimum_size = Vector2(0, 56)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_override("font", MenuUI.FONT)
		btn.add_theme_font_size_override("font_size", 23)
		var idx := i
		btn.pressed.connect(func() -> void:
			Music.click()
			_select_page(idx))
		tab_row.add_child(btn)
		_tab_buttons.append(btn)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.07, 0.08, 0.11, 0.94)
	panel_sb.border_color = MenuUI.GOLD
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(8)
	panel_sb.content_margin_left = 24
	panel_sb.content_margin_right = 24
	panel_sb.content_margin_top = 20
	panel_sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", panel_sb)
	right.add_child(panel)

	_stats_tab = _make_page(panel)
	_cards_tab = _make_page(panel)
	_paths_tab = _make_page(panel)
	_select_page(0)


func _make_page(panel: PanelContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_pages.append(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	scroll.add_child(box)
	return box


func _select_page(idx: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == idx
	for i in _tab_buttons.size():
		var btn := _tab_buttons[i]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(2)
		sb.border_color = MenuUI.GOLD
		if i == idx:
			# seçili sekme: dolu altın, koyu yazı
			sb.bg_color = MenuUI.GOLD
			btn.add_theme_color_override("font_color", Color(0.10, 0.08, 0.04))
		else:
			sb.bg_color = MenuUI.STEEL
			btn.add_theme_color_override("font_color", MenuUI.TEXT)
		btn.add_theme_stylebox_override("normal", sb)
		var hover := sb.duplicate() as StyleBoxFlat
		hover.bg_color = MenuUI.BLOOD          # üzerine gelince kan kırmızısı
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		btn.add_theme_color_override("font_hover_color", MenuUI.TEXT_HI)
		btn.add_theme_color_override("font_pressed_color", MenuUI.TEXT_HI)


func _refresh_tabs() -> void:
	for tab in [_stats_tab, _cards_tab, _paths_tab]:
		for c in tab.get_children():
			c.queue_free()

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var weapon: Node = player.get_node_or_null("%Gun")
	_fill_stats(player, weapon)
	_fill_cards()
	_fill_paths(weapon)


# ---------- STATLAR ----------

func _fill_stats(player: Node, weapon: Node) -> void:
	# Üst düzen: solda dikey karakter kutusu, sağda tüm stat bölümleri
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_tab.add_child(split)

	# --- KARAKTER: altın şövalye, solda boylamasına altın borderli kutu ---
	if weapon != null:
		var cv: SubViewportContainer = CHAR_VIEW.new()
		cv.setup(weapon)
		cv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(220, 420)
		panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.1, 0.09)
		sb.border_color = MenuUI.GOLD
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(8)
		panel.add_theme_stylebox_override("panel", sb)
		panel.add_child(cv)
		split.add_child(panel)

	# sağ sütun: tüm bölümler buraya
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 16)
	split.add_child(col)

	# --- SİLAHLAR: iki slot, aktif vurgulu + mermi, pasif sönük ---
	if weapon != null:
		col.add_child(_section("SİLAHLAR"))
		var wrow := HBoxContainer.new()
		wrow.add_theme_constant_override("separation", 14)
		col.add_child(wrow)
		wrow.add_child(_weapon_box(str(weapon.data.display_name),
				"AKTİF — %d / %d" % [weapon.current_ammo, weapon.reserve], true))
		var passive_name: String = weapon.inactive_slot_name()
		if passive_name != "":
			var pammo: Vector2i = weapon.inactive_slot_ammo()
			wrow.add_child(_weapon_box(passive_name,
					"Q • %d / %d" % [pammo.x, pammo.y], false))

	col.add_child(_section("OYUNCU"))
	var pgrid := _stat_grid()
	col.add_child(pgrid)
	_add_stat_box(pgrid, "CAN", "%d / %d" % [ceili(player.health), roundi(player.max_health)], Color(0.9, 0.35, 0.3))
	if player.max_shield > 0.0:
		_add_stat_box(pgrid, "KALKAN", "%d / %d" % [ceili(player.shield), roundi(player.max_shield)], Color(0.75, 0.78, 0.83))
	_add_stat_box(pgrid, "DAYANIKLILIK", "%d" % roundi(player.max_stamina), Color(0.4, 0.85, 0.95))
	_add_stat_box(pgrid, "HIZ", "%.1f" % player.walk_speed, Color(0.6, 0.9, 0.5))
	_add_stat_box(pgrid, "KOŞU HIZI", "%.1f" % player.sprint_speed, Color(0.6, 0.9, 0.5))
	_add_stat_box(pgrid, "TOPLAMA", "%.1f m" % player.pickup_radius, Color(0.8, 0.6, 0.95))
	if player.lifesteal > 0.0:
		_add_stat_box(pgrid, "CAN ÇALMA", "%%%d" % roundi(player.lifesteal * 100), Color(0.9, 0.3, 0.45))
	if player.thorns > 0.0:
		_add_stat_box(pgrid, "DİKEN", "%d" % roundi(player.thorns), Color(0.85, 0.75, 0.4))

	if weapon == null:
		return
	col.add_child(_section("SİLAH — %s" % str(weapon.data.display_name).to_upper()))
	var wgrid := _stat_grid()
	col.add_child(wgrid)
	_add_stat_box(wgrid, "HASAR", "%.1f" % weapon.data.damage, Color(0.95, 0.6, 0.3))
	_add_stat_box(wgrid, "ATIŞ HIZI", "%.1f /sn" % weapon.data.fire_rate, Color(0.95, 0.85, 0.4))
	_add_stat_box(wgrid, "ŞARJÖR", "%d" % weapon.data.mag_size, Color(0.7, 0.75, 0.8))
	_add_stat_box(wgrid, "DOLDURMA", "%.1f sn" % weapon.data.reload_time, Color(0.7, 0.75, 0.8))
	_add_stat_box(wgrid, "KAFA ÇARPANI", "×%.1f" % weapon.data.headshot_mult, Color(0.9, 0.45, 0.35))
	if weapon.data.crit_chance > 0.0:
		_add_stat_box(wgrid, "KRİTİK", "%%%d ×%.0f" % [roundi(weapon.data.crit_chance * 100), weapon.data.crit_mult], Color(0.97, 0.72, 0.2))
	if weapon.data.pellets > 1:
		_add_stat_box(wgrid, "SAÇMA", "%d" % weapon.data.pellets, Color(0.7, 0.75, 0.8))


func _weapon_icon(display_name: String) -> Texture2D:
	## tabanca özel ikon; evrim silahları kendi evrim kartının ikonunu kullanır
	if display_name == "Tabanca":
		return load("res://assets/ui/cards/pistol.png")
	for c in _pool:
		if c.new_weapon != null and c.new_weapon.display_name == display_name:
			return c.icon()
	return null


func _weapon_box(display_name: String, sub: String, active: bool) -> PanelContainer:
	var accent := MenuUI.GOLD if active else Color(0.5, 0.52, 0.58)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.16) if active else Color(0.09, 0.10, 0.13)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(250, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var icon_tex := _weapon_icon(display_name)
	if icon_tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.custom_minimum_size = Vector2(44, 44)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.modulate = accent if active else Color(0.6, 0.62, 0.66)
		row.add_child(icon_rect)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	row.add_child(v)

	var n := Label.new()
	n.text = display_name
	n.add_theme_font_override("font", MenuUI.FONT)
	n.add_theme_font_size_override("font_size", 19)
	n.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98) if active else Color(0.65, 0.67, 0.7))
	v.add_child(n)

	var s := Label.new()
	s.text = sub
	s.add_theme_font_override("font", MenuUI.FONT)
	s.add_theme_font_size_override("font_size", 14)
	s.add_theme_color_override("font_color", accent)
	v.add_child(s)
	return box


func _stat_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 14)
	return g


func _add_stat_box(grid: GridContainer, name_text: String, value_text: String, accent: Color) -> void:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.16)
	sb.border_color = accent * Color(1, 1, 1, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(190, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # boş gri alan kalmasın, satıra yayıl

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	box.add_child(v)

	var n := Label.new()
	n.text = name_text
	n.add_theme_font_override("font", MenuUI.FONT)
	n.add_theme_font_size_override("font_size", 14)
	n.add_theme_color_override("font_color", Color(0.55, 0.57, 0.62))
	v.add_child(n)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_override("font", MenuUI.FONT)
	val.add_theme_font_size_override("font_size", 27)
	val.add_theme_color_override("font_color", accent)
	v.add_child(val)
	grid.add_child(box)


# ---------- KARTLAR ----------

func _fill_cards() -> void:
	var owned: Array[UpgradeCard] = []
	for card in _pool:
		if Game.card_count(card.id) > 0:
			owned.append(card)
	if owned.is_empty():
		var none := Label.new()
		none.text = "Henüz kart seçilmedi — zombi öldür, seviye atla."
		none.add_theme_font_override("font", MenuUI.FONT)
		none.add_theme_font_size_override("font_size", 17)
		none.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		_cards_tab.add_child(none)
		return

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	_cards_tab.add_child(grid)
	for card in owned:
		grid.add_child(_make_mini_card(card))


func _make_mini_card(card: UpgradeCard) -> PanelContainer:
	## seçim ekranındaki kart görünümünün küçük hali + sahip olunan yığın sayısı
	var color := RARITY_COLORS[card.rarity]
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.14)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(200, 205)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	box.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	var rar := Label.new()
	rar.text = RARITY_NAMES[card.rarity]
	rar.add_theme_font_override("font", MenuUI.FONT)
	rar.add_theme_font_size_override("font_size", 12)
	rar.add_theme_color_override("font_color", color)
	rar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rar)
	var stacks := Label.new()
	stacks.text = "×%d/%d" % [Game.card_count(card.id), card.max_stacks]
	stacks.add_theme_font_override("font", MenuUI.FONT)
	stacks.add_theme_font_size_override("font_size", 13)
	stacks.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	top.add_child(stacks)

	var icon_tex := card.icon()
	if icon_tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.custom_minimum_size = Vector2(0, 38)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.modulate = color
		v.add_child(icon_rect)

	var title := Label.new()
	title.text = card.title
	title.add_theme_font_override("font", MenuUI.FONT)
	title.add_theme_font_size_override("font_size", 17)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)

	var desc := Label.new()
	desc.text = card.description
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.74, 0.76, 0.8))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)
	return box


# ---------- SİLAH YOLLARI ----------

func _fill_paths(weapon: Node) -> void:
	var current := str(weapon.data.display_name) if weapon != null else ""
	var info := Label.new()
	info.text = "Kuşanılan: %s — evrim adımları kart seçiminden açılır." % current
	info.add_theme_font_override("font", MenuUI.FONT)
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Color(0.55, 0.57, 0.62))
	_paths_tab.add_child(info)

	for card in _pool:
		if card.new_weapon == null:
			continue
		_paths_tab.add_child(_make_path_row(card))


func _make_path_row(evo: UpgradeCard) -> HBoxContainer:
	## kutu → kutu → kutu zinciri; hiç dokunulmamış adımlar "?" kutusu
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var owned := Game.card_count(evo.id) > 0
	row.add_child(_path_box("TABANCA", "", null, Color(0.5, 0.95, 0.4), false))

	var prereqs_met := true
	for req_id: String in evo.requires:
		var have := Game.card_count(req_id)
		var need := int(evo.requires[req_id])
		if have < need:
			prereqs_met = false
		row.add_child(_path_arrow())
		var req_card: UpgradeCard = null
		for c in _pool:
			if c.id == req_id:
				req_card = c
				break
		if have <= 0 and not owned:
			row.add_child(_path_box("?", "", null, Color(0.45, 0.45, 0.5), true))
		else:
			var state_color := MenuUI.GOLD if have >= need else Color(0.95, 0.85, 0.4)
			var req_title := req_card.title if req_card != null else req_id
			var req_icon := req_card.icon() if req_card != null else null
			row.add_child(_path_box(req_title, "%d/%d" % [mini(have, need), need], req_icon, state_color, false))

	row.add_child(_path_arrow())
	if owned:
		row.add_child(_path_box(evo.title, "KUŞANILDI", evo.icon(), Color(0.5, 0.95, 0.4), false))
	elif prereqs_met:
		row.add_child(_path_box(evo.title, "ÇIKABİLİR!", evo.icon(), Color(0.97, 0.72, 0.2), false))
	else:
		row.add_child(_path_box("?", "", null, Color(0.45, 0.45, 0.5), true))
	return row


func _path_box(title: String, sub: String, icon_tex: Texture2D, accent: Color, unknown: bool) -> PanelContainer:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.16) if not unknown else Color(0.09, 0.09, 0.12)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(180, 108)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 3)
	box.add_child(v)

	if unknown:
		var q := Label.new()
		q.text = "?"
		q.add_theme_font_override("font", MenuUI.FONT)
		q.add_theme_font_size_override("font_size", 42)
		q.add_theme_color_override("font_color", accent)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(q)
		return box

	if icon_tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.custom_minimum_size = Vector2(0, 32)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.modulate = accent
		v.add_child(icon_rect)

	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", MenuUI.FONT)
	t.add_theme_font_size_override("font_size", 16)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)

	if sub != "":
		var s := Label.new()
		s.text = sub
		s.add_theme_font_override("font", MenuUI.FONT)
		s.add_theme_font_size_override("font_size", 13)
		s.add_theme_color_override("font_color", accent)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	return box


func _path_arrow() -> Label:
	var l := Label.new()
	l.text = "→"
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(0.5, 0.52, 0.58))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuUI.FONT)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", MenuUI.GOLD)
	return l


func _open_settings() -> void:
	Music.click()
	# ayarlar paneli açıkken duraklatma menüsünü gizle (layer çakışması da önlenir)
	_root.hide()
	var settings: CanvasLayer = SettingsMenuScript.new()
	settings.layer = 21
	add_child(settings)  # child olarak: PROCESS_MODE_ALWAYS miras alır, pause'da çalışır
	settings.closed.connect(_root.show)


func _restart() -> void:
	get_tree().paused = false
	Game.reset()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)
