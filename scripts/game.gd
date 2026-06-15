extends Node
## Autoload "Game": XP, level, kill sayacı ve seçilen kartların kaydı.

signal xp_changed(xp: int, needed: int)
signal leveled_up(new_level: int)
signal kills_changed(kills: int)
signal gold_changed(gold: int)
signal bonus_draw(rarity_boost: int)  ## sandıktan bedava kart çekimi (boost>0 = yüksek rarity)

## Koşu akışı: 1-5 bahçe labirenti → 6 bahçe boss arenası → 7-11 şato katları → (sonra: şato boss)
const GARDEN_STAGES := 5
const CASTLE_STAGES := 5

var level := 1
var xp := 0
var kills := 0
var picked_cards := {}  ## kart id -> kaç kez seçildi
var picked_order: Array[String] = []  ## seçim sırası — kat geçişinde sırayla yeniden uygulanır
var carry_health := -1.0  ## kat geçişinde taşınan can (<0: tam dolu başla)
var carry_ammo := {}      ## kat geçişinde taşınan mermi (slot -> Vector2i(şarjör, yedek))
var stage := 1  ## global ilerleme sayacı (tüm bölümler boyunca artar)
var run_seed := 0  ## bu oyunun labirent tohumu
var gold := 0
var intro_shown := false  ## açılış hikâye ekranı (koşu başına bir kez)
var castle_intro_shown := false  ## şatoya giriş hikâye ekranı
var afterlife := ""  ## Cerberus sonrası seçim: "heaven" (bulutlar) / "hell" (lav)
var won := false  ## koşu zaferle bitti mi (koşu-özeti ekranı bunu okur)
var debug_stage := 0  ## geliştirme kısayolu: --stage=N ile koşu o kattan başlar (play2.bat)
var debug_cards: Array[String] = []  ## --cards=id1,id2 ile koşuya hazır silah seti/yükseltme

var run_time := 0.0       ## bu koşunun aktif (duraklatma hariç) oyun süresi — speedrun
var _run_active := false
const LB_PATH := "user://leaderboard.cfg"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):
			debug_stage = maxi(arg.get_slice("=", 1).to_int(), 0)
		elif arg.begins_with("--cards="):
			debug_cards.clear()
			for cid: String in arg.get_slice("=", 1).split(",", false):
				debug_cards.append(cid.strip_edges())


func _process(delta: float) -> void:
	if _run_active:
		run_time += delta  # duraklatmada (kart/ESC) autoload da durur → süre saymaz


func start_timer() -> void:
	_run_active = true


func end_run() -> Array:
	## koşuyu bitir, leaderboard'a kaydet, sıralı listeyi döndür
	_run_active = false
	var cfg := ConfigFile.new()
	cfg.load(LB_PATH)
	var runs: Array = cfg.get_value("board", "runs", [])
	runs.append({
		"stage": stage, "kills": kills, "level": level, "gold": gold,
		"time": run_time, "date": Time.get_date_string_from_system(),
	})
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["stage"] != b["stage"]:
			return a["stage"] > b["stage"]  # daha ileri kat üstte
		return a["time"] < b["time"])       # eşit katta daha hızlı üstte
	runs = runs.slice(0, 10)
	cfg.set_value("board", "runs", runs)
	cfg.save(LB_PATH)
	return runs


func leaderboard() -> Array:
	var cfg := ConfigFile.new()
	cfg.load(LB_PATH)
	return cfg.get_value("board", "runs", [])


func biome() -> String:
	if stage <= GARDEN_STAGES:
		return "garden"
	if stage == GARDEN_STAGES + 1:
		return "garden_boss"
	if stage == GARDEN_STAGES + CASTLE_STAGES + 2:  # kat 12: taht salonu
		return "castle_boss"
	if stage == GARDEN_STAGES + CASTLE_STAGES + 3:  # kat 13: balkon — Cerberus
		return "cerberus"
	if stage == GARDEN_STAGES + CASTLE_STAGES + 4:  # kat 14: cennet/cehennem
		return afterlife if afterlife != "" else "heaven"
	return "castle"


func biome_stage() -> int:
	## bulunulan bölümün kaçıncı katı (1'den başlar)
	if stage <= GARDEN_STAGES:
		return stage
	if stage == GARDEN_STAGES + 1:
		return 1
	if stage <= GARDEN_STAGES + CASTLE_STAGES + 1:
		return stage - GARDEN_STAGES - 1
	if stage >= GARDEN_STAGES + CASTLE_STAGES + 2:
		return 1  # taht salonu / Cerberus / cennet-cehennem
	return stage - GARDEN_STAGES - 2  # boss sonrası şato derinleri (kat 6+)


func next_stage() -> void:
	stage += 1


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func xp_needed() -> int:
	# daha dik eğri: ilk bölümde 1-2 kartı geçmeyecek şekilde yavaş ilerleme
	return 60 + (level - 1) * 50


func add_kill() -> void:
	## sadece sayaç — XP/altın artık yerden pickup olarak toplanıyor
	kills += 1
	kills_changed.emit(kills)


func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		leveled_up.emit(level)
	xp_changed.emit(xp, xp_needed())


func card_count(id: String) -> int:
	return picked_cards.get(id, 0)


func reset() -> void:
	level = 1
	xp = 0
	kills = 0
	picked_cards.clear()
	picked_order.clear()
	carry_health = -1.0
	carry_ammo = {}
	stage = maxi(debug_stage, 1)
	# debug: --cards ile gelen seti koşu başına hazır kur (silah evrimi dahil)
	for cid: String in debug_cards:
		picked_order.append(cid)
		picked_cards[cid] = picked_cards.get(cid, 0) + 1
	run_seed = randi()
	gold = 0
	intro_shown = false
	castle_intro_shown = false
	afterlife = ""
	won = false
	run_time = 0.0
	_run_active = false  # oyun (dungeon) yüklenince start_timer ile başlar
