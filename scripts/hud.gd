extends CanvasLayer
## HUD: can, XP, mermi, kill sayacı ve hasar vinyeti.

const SettingsMenuScript := preload("res://scripts/settings_menu.gd")
const DEATH_SND := preload("res://assets/audio/sfx/player_death.wav")

@onready var ammo_label: Label = $AmmoLabel
@onready var weapon_label: Label = $WeaponLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_value: Label = $HealthBar/HealthValue
@onready var shield_bar: ProgressBar = $ShieldBar
@onready var shield_value: Label = $ShieldBar/ShieldValue
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var xp_bar: ProgressBar = $XPBar
@onready var level_label: Label = $LevelLabel
@onready var kills_label: Label = $KillsLabel
@onready var gold_label: Label = $GoldLabel
@onready var vignette: ColorRect = $HurtVignette
@onready var death_label: Label = $DeathLabel

@onready var player: Node = get_parent()
@onready var weapon: Node = get_node("%Gun")

var _reload_bar: ProgressBar
var _reload_label: Label
var _reload_tween: Tween
var _blood_overlay: TextureRect  ## hasarda ekran kenarı kan sıçraması
var _blood_tween: Tween
var _lowhp_overlay: TextureRect  ## az canda nabız atan kanlı kenar
var _lowhp := 0.0                ## düşük can şiddeti (0 kapalı .. 1 ölüm eşiği)
var _pulse_t := 0.0
const LOW_HP := 0.30             ## bu oranın altında nabız başlar


func _ready() -> void:
	weapon.ammo_changed.connect(_on_ammo_changed)
	weapon.weapon_changed.connect(_on_weapon_changed)
	weapon.slots_changed.connect(_on_slots_changed)
	weapon.reload_started.connect(_on_reload_started)
	weapon.reload_finished.connect(_on_reload_finished)
	weapon.loadout_changed.connect(_on_loadout_changed)
	weapon.hit_confirmed.connect(_on_hit_confirmed)
	_build_hit_marker()
	_build_reload_ui()
	_build_blood_overlay()
	_build_weapon_list()
	$PassiveWeaponLabel.visible = false  # yerini soldaki silah listesi aldı
	_on_loadout_changed(weapon.loadout())
	weapon_label.text = weapon.data.display_name
	SettingsMenuScript.load_settings()
	update_crosshair(SettingsMenuScript.crosshair_path)
	player.health_changed.connect(_on_health_changed)
	player.shield_changed.connect(_on_shield_changed)
	player.stamina_changed.connect(_on_stamina_changed)
	player.hurt.connect(_on_hurt)
	player.died.connect(_on_died)
	_build_grenade_label()
	player.grenades_changed.connect(_on_grenades_changed)
	_on_grenades_changed(player.grenades, player.max_grenades)
	Game.xp_changed.connect(_on_xp_changed)
	Game.leveled_up.connect(_on_leveled_up)
	Game.kills_changed.connect(_on_kills_changed)
	Game.gold_changed.connect(_on_gold_changed)
	gold_label.text = "%d ⬤" % Game.gold

	_on_ammo_changed(weapon.current_ammo, weapon.reserve)
	_on_health_changed(player.health, player.max_health)
	_on_xp_changed(Game.xp, Game.xp_needed())
	level_label.text = "SEVİYE %d" % Game.level
	kills_label.text = "KILL: %d" % Game.kills


func _on_ammo_changed(current: int, reserve: int) -> void:
	if current < 0:
		ammo_label.text = "—"  # bıçak: mermi yok
	else:
		ammo_label.text = "%d / %d" % [current, reserve]


func _build_reload_ui() -> void:
	# nişangahın hemen altında: "DOLDURULUYOR" + dolan çubuk
	_reload_label = Label.new()
	_reload_label.text = "DOLDURULUYOR"
	_reload_label.add_theme_font_override("font", load("res://assets/fonts/ui_font.tres"))
	_reload_label.add_theme_font_size_override("font_size", 18)
	_reload_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reload_label.set_anchors_preset(Control.PRESET_CENTER)
	_reload_label.position = Vector2(-100, 34)
	_reload_label.custom_minimum_size = Vector2(200, 0)
	_reload_label.visible = false
	add_child(_reload_label)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	bar_bg.set_corner_radius_all(3)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.95, 0.82, 0.35)
	bar_fill.set_corner_radius_all(3)

	_reload_bar = ProgressBar.new()
	_reload_bar.show_percentage = false
	_reload_bar.add_theme_stylebox_override("background", bar_bg)
	_reload_bar.add_theme_stylebox_override("fill", bar_fill)
	_reload_bar.set_anchors_preset(Control.PRESET_CENTER)
	_reload_bar.position = Vector2(-70, 58)
	_reload_bar.custom_minimum_size = Vector2(140, 8)
	_reload_bar.size = Vector2(140, 8)
	_reload_bar.max_value = 1.0
	_reload_bar.visible = false
	add_child(_reload_bar)


var _grenade_label: Label


func _build_grenade_label() -> void:
	# bomba sayacı: silah sütununun üstünde (sağ-alt), turuncu
	_grenade_label = Label.new()
	_grenade_label.add_theme_font_override("font", load("res://assets/fonts/ui_font.tres"))
	_grenade_label.add_theme_font_size_override("font_size", 22)
	_grenade_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	_grenade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_grenade_label.anchor_left = 1.0
	_grenade_label.anchor_right = 1.0
	_grenade_label.anchor_top = 1.0
	_grenade_label.anchor_bottom = 1.0
	_grenade_label.offset_left = -260.0
	_grenade_label.offset_top = -154.0
	_grenade_label.offset_right = -24.0
	_grenade_label.offset_bottom = -126.0
	add_child(_grenade_label)


func _on_grenades_changed(count: int, maxc: int) -> void:
	_grenade_label.visible = maxc > 0  # bomba açılmadıysa gösterge yok
	_grenade_label.text = "✦ %d/%d  [G]" % [count, maxc]
	_grenade_label.modulate.a = 1.0 if count > 0 else 0.5


func _on_reload_started(duration: float) -> void:
	_reload_label.visible = true
	_reload_bar.visible = true
	_reload_bar.value = 0.0
	if _reload_tween:
		_reload_tween.kill()
	_reload_tween = create_tween()
	_reload_tween.tween_property(_reload_bar, "value", 1.0, duration)


func _on_reload_finished() -> void:
	_reload_label.visible = false
	_reload_bar.visible = false


func _on_weapon_changed(display_name: String) -> void:
	weapon_label.text = display_name
	# kısa parlama
	weapon_label.scale = Vector2(1.4, 1.4)
	var tween := create_tween()
	tween.tween_property(weapon_label, "scale", Vector2.ONE, 0.3)


func _on_slots_changed(_active_name: String, _inactive_name: String) -> void:
	# pasif silah artık soldaki listede gösteriliyor (_on_loadout_changed)
	pass


var _weapon_list: VBoxContainer


func _build_weapon_list() -> void:
	# SAĞDA dikey silah listesi: tüm silahlar ikonlu, üst üste, aktif olan vurgulu
	_weapon_list = VBoxContainer.new()
	_weapon_list.anchor_left = 1.0
	_weapon_list.anchor_right = 1.0
	_weapon_list.anchor_top = 0.5
	_weapon_list.anchor_bottom = 0.5
	_weapon_list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_weapon_list.grow_vertical = Control.GROW_DIRECTION_BOTH
	_weapon_list.offset_left = -288.0
	_weapon_list.offset_right = -20.0
	_weapon_list.add_theme_constant_override("separation", 8)
	add_child(_weapon_list)


func _on_loadout_changed(items: Array) -> void:
	if _weapon_list == null:
		return
	for c in _weapon_list.get_children():
		c.queue_free()
	var font: Font = load("res://assets/fonts/ui_font.tres")
	for it: Dictionary in items:
		var active := bool(it["active"])
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = BoxContainer.ALIGNMENT_END  # sağ kenara yasla
		row.add_theme_constant_override("separation", 10)

		var lbl := Label.new()
		lbl.text = it["name"]
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.add_theme_font_override("font", font)
		if active:
			lbl.add_theme_font_size_override("font_size", 22)
			lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
		else:
			lbl.add_theme_font_size_override("font_size", 18)
			lbl.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		row.add_child(lbl)

		var icon := TextureRect.new()
		icon.texture = it.get("icon")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var sz := 44.0 if active else 30.0
		icon.custom_minimum_size = Vector2(sz, sz)
		icon.modulate = Color(1.0, 0.92, 0.5) if active else Color(0.55, 0.57, 0.62, 0.9)
		row.add_child(icon)

		_weapon_list.add_child(row)


func _on_health_changed(health: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	health_value.text = "%d / %d" % [ceili(health), roundi(max_health)]
	# az can nabzı: eşik altında şiddet 0→1 (ölüme yaklaştıkça artar)
	var ratio := health / max_health if max_health > 0.0 else 0.0
	if not player.dead and ratio > 0.0 and ratio <= LOW_HP:
		_lowhp = clampf((LOW_HP - ratio) / LOW_HP, 0.05, 1.0)
	else:
		_lowhp = 0.0
		if _lowhp_overlay != null:
			_lowhp_overlay.modulate.a = 0.0


func _on_shield_changed(shield: float, max_shield: float) -> void:
	# kalkan barı sadece Kalkan kartı alınınca belirir
	shield_bar.visible = max_shield > 0.0
	shield_bar.max_value = maxf(max_shield, 1.0)
	shield_bar.value = shield
	shield_value.text = "%d / %d" % [ceili(shield), roundi(max_shield)]


func _on_stamina_changed(stamina: float, max_stamina: float) -> void:
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina


func _on_xp_changed(xp: int, needed: int) -> void:
	xp_bar.max_value = needed
	xp_bar.value = xp


func _on_leveled_up(new_level: int) -> void:
	level_label.text = "SEVİYE %d" % new_level


func _on_kills_changed(kills: int) -> void:
	kills_label.text = "KILL: %d" % kills


func _on_gold_changed(gold: int) -> void:
	gold_label.text = "%d ⬤" % gold
	gold_label.scale = Vector2(1.2, 1.2)
	var tween := create_tween()
	tween.tween_property(gold_label, "scale", Vector2.ONE, 0.15)


func _on_hurt() -> void:
	$HurtSfx.play()
	if _blood_overlay != null:
		_blood_overlay.modulate.a = 0.75
		if _blood_tween:
			_blood_tween.kill()
		_blood_tween = create_tween()
		_blood_tween.tween_property(_blood_overlay, "modulate:a", 0.0, 0.7)
	if player.dead:
		return  # ölümde vignette kalıcı, soldurma
	vignette.modulate.a = 0.55
	var tween := create_tween()
	tween.tween_property(vignette, "modulate:a", 0.0, 0.4)


func _build_blood_overlay() -> void:
	# az can nabzı (altta) — kanlı kenar, sürekli nabız atar
	_lowhp_overlay = TextureRect.new()
	_lowhp_overlay.texture = load("res://assets/fx/blood_screen.png")
	_lowhp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lowhp_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_lowhp_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lowhp_overlay.modulate = Color(1, 1, 1, 0.0)
	add_child(_lowhp_overlay)
	move_child(_lowhp_overlay, 0)
	# hasar sıçraması (üstte) — anlık flash
	_blood_overlay = TextureRect.new()
	_blood_overlay.texture = load("res://assets/fx/blood_screen.png")
	_blood_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blood_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_blood_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blood_overlay.modulate.a = 0.0
	add_child(_blood_overlay)
	move_child(_blood_overlay, 1)  # diğer HUD öğelerinin arkasında


func _process(delta: float) -> void:
	if _lowhp > 0.0 and _lowhp_overlay != null:
		# can ne kadar azsa nabız o kadar hızlı + güçlü (kalp atışı hissi)
		_pulse_t += delta * (3.0 + _lowhp * 5.0)
		var amp := 0.18 + _lowhp * 0.5
		_lowhp_overlay.modulate.a = (sin(_pulse_t) * 0.5 + 0.5) * amp


var _hit_marker: TextureRect
var _hit_tween: Tween
var _hit_sfx: AudioStreamPlayer


func _build_hit_marker() -> void:
	# isabet işareti: nişangahın üstünde kısa süre çakan X (vücut: beyaz, kafa: altın)
	_hit_marker = TextureRect.new()
	_hit_marker.texture = load("res://assets/fx/hitmarker.png")
	_hit_marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_marker.custom_minimum_size = Vector2(40, 40)
	_hit_marker.size = Vector2(40, 40)
	_hit_marker.pivot_offset = Vector2(20, 20)
	_hit_marker.set_anchors_preset(Control.PRESET_CENTER)
	_hit_marker.position = Vector2(-20, -20)
	_hit_marker.modulate.a = 0.0
	add_child(_hit_marker)
	_hit_sfx = AudioStreamPlayer.new()
	_hit_sfx.stream = load("res://assets/audio/impact/impactGeneric_light_000.ogg")
	_hit_sfx.volume_db = -8.0
	add_child(_hit_sfx)


func _on_hit_confirmed(headshot: bool) -> void:
	if _hit_marker == null:
		return
	_hit_marker.modulate = Color(1.0, 0.8, 0.2, 1.0) if headshot else Color(1, 1, 1, 1.0)
	_hit_marker.scale = Vector2(1.5, 1.5) if headshot else Vector2(1.25, 1.25)
	_hit_sfx.pitch_scale = 1.5 if headshot else 1.1
	_hit_sfx.play()
	if _hit_tween:
		_hit_tween.kill()
	_hit_tween = create_tween().set_parallel()
	_hit_tween.tween_property(_hit_marker, "scale", Vector2.ONE, 0.18)
	_hit_tween.tween_property(_hit_marker, "modulate:a", 0.0, 0.32)


func update_crosshair(path: String) -> void:
	var tex: Texture2D = load(path)
	if tex:
		$Crosshair.texture = tex
	$Crosshair.modulate = SettingsMenuScript.crosshair_color


func _on_died() -> void:
	# az can nabzını durdur (ölüm vignette'i devralır)
	_lowhp = 0.0
	if _lowhp_overlay != null:
		_lowhp_overlay.modulate.a = 0.0
	# nişangah ve oyun göstergeleri ölüyken anlamsız
	$Crosshair.hide()
	ammo_label.hide()
	$WeaponLabel.hide()
	_reload_label.hide()
	_reload_bar.hide()

	var snd := AudioStreamPlayer.new()
	snd.stream = DEATH_SND
	snd.volume_db = -3.0
	add_child(snd)
	snd.play()

	# kırmızı karartma kademeli koyulaşsın
	var vt := create_tween()
	vt.tween_property(vignette, "modulate:a", 0.6, 1.2)

	# animasyonlu "ÖLDÜN": büyükten otursun + sürekli hafif nabız
	death_label.pivot_offset = Vector2(300, 60)
	death_label.scale = Vector2(2.6, 2.6)
	death_label.modulate.a = 0.0
	death_label.show()
	var t := create_tween().set_parallel()
	t.tween_property(death_label, "scale", Vector2.ONE, 0.6) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(death_label, "modulate:a", 1.0, 0.45)
	t.chain().tween_callback(_pulse_death)


func _pulse_death() -> void:
	var p := death_label.create_tween().set_loops()
	p.tween_property(death_label, "scale", Vector2(1.06, 1.06), 0.7).set_trans(Tween.TRANS_SINE)
	p.tween_property(death_label, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
