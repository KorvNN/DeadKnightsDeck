class_name MenuUI
extends RefCounted
## Menü butonu/başlık üretimi için ortak yardımcılar (ana menü + duraklatma).

const FONT := preload("res://assets/fonts/ui_font.tres")  # Kenney + Türkçe (İŞĞ) fallback

# --- "Dead Knight's Deck" paleti: soluk ALTIN + koyu ÇELİK + kan KIRMIZISI ---
const GOLD := Color(0.84, 0.67, 0.28)        # birincil vurgu (başlık, kenarlık)
const GOLD_DIM := Color(0.60, 0.47, 0.20)    # sönük altın
const STEEL := Color(0.12, 0.13, 0.16)       # koyu çelik (buton/panel zemini)
const STEEL_PANEL := Color(0.08, 0.085, 0.10, 0.98)  # panel arka planı
const BLOOD := Color(0.56, 0.07, 0.07)       # kan kırmızısı (hover/vurgu)
const BLOOD_DK := Color(0.38, 0.04, 0.04)    # koyu kan (basılı)
const TEXT := Color(0.90, 0.88, 0.82)        # sıcak kirli beyaz yazı
const TEXT_HI := Color(0.97, 0.94, 0.88)     # kan üstünde açık yazı


static func make_title(text: String, size := 84, color := GOLD) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func make_button(text: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(340, 58)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", FONT)
	btn.add_theme_font_size_override("font_size", 26)

	var normal := StyleBoxFlat.new()
	normal.bg_color = STEEL
	normal.border_color = GOLD
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BLOOD             # üzerine gelince kan kırmızısı dolar
	hover.border_color = GOLD
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = BLOOD_DK

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT_HI)
	btn.add_theme_color_override("font_pressed_color", TEXT_HI)

	# tıklama sesi (kalıcı autoload'dan çalar → sahne değişse de kesilmez), sonra eylem
	btn.pressed.connect(func() -> void:
		Music.click()
		on_press.call())
	return btn
