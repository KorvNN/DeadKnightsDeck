extends Node
## Kalıcı müzik yöneticisi (autoload). Sahneler arası sürer, duraklatmada çalmaya
## devam eder. İki parça arasında yumuşak geçiş yapar.

const MENU := preload("res://assets/audio/music/menu_music.wav")
const GAME := preload("res://assets/audio/music/game_music.wav")
const EXPLORE := preload("res://assets/audio/music/explore_music.wav")
const CERBERUS := preload("res://assets/audio/music/cerberus_music.wav")
const CLICK := preload("res://assets/audio/sfx/ui_click.wav")
const TRANSITION := preload("res://assets/audio/sfx/stage_advance.wav")

const MENU_DB := -13.0
const GAME_DB := -15.0
const FADE := 1.0

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _cur: AudioStreamPlayer
var _which := ""
var _fade_tween: Tween
var _ui: AudioStreamPlayer  ## kalıcı UI/geçiş sesleri (sahne değişiminde kesilmez)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_loopify(MENU)
	_loopify(GAME)
	_loopify(EXPLORE)
	_loopify(CERBERUS)
	_a = _make_player()
	_b = _make_player()
	_ui = _make_player()
	_ui.volume_db = 0.0
	_cur = _a
	# müzik ayrı bus'ta: ayarlardan bağımsız kısılabilsin (SettingsMenu bus'ı kurar)
	SettingsMenu.load_settings()
	_a.bus = "Music"
	_b.bus = "Music"


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = -40.0
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


func _loopify(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		var ch := 2 if s.stereo else 1
		s.loop_end = s.data.size() / (2 * ch)  # 16-bit


func click() -> void:
	_ui.stream = CLICK
	_ui.volume_db = 2.0
	_ui.play()


func transition() -> void:
	_ui.stream = TRANSITION
	_ui.volume_db = -2.0
	_ui.play()


func play_menu() -> void:
	_crossfade(MENU, "menu", MENU_DB)


func play_game() -> void:
	_crossfade(GAME, "game", GAME_DB)


func play_explore() -> void:
	_crossfade(EXPLORE, "explore", GAME_DB + 2.0)


func play_cerberus() -> void:
	_crossfade(CERBERUS, "cerberus", GAME_DB + 1.0)


func fade_out() -> void:
	## foreshadow: müziği sessizliğe indir (geçici)
	_which = ""
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_cur, "volume_db", -40.0, 1.2)
	_fade_tween.tween_callback(_cur.stop)


func _crossfade(stream: AudioStream, which: String, vol: float) -> void:
	if _which == which and _cur.playing:
		return
	_which = which
	var nxt := _b if _cur == _a else _a
	nxt.stream = stream
	nxt.volume_db = -40.0
	nxt.play()
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel()
	_fade_tween.tween_property(nxt, "volume_db", vol, FADE)
	var old := _cur
	_fade_tween.tween_property(old, "volume_db", -40.0, FADE)
	_fade_tween.chain().tween_callback(old.stop)
	_cur = nxt
