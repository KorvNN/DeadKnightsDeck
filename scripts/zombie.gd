extends CharacterBody3D
## Temel düşman: yerden doğar, oyuncuyu kovalar, yakına gelince yumruk atar.

signal died

enum State { SPAWNING, CHASE, ATTACK, DEAD }

const MODELS := [
	"res://assets/characters/Zombie_Male.gltf",
	"res://assets/characters/Zombie_Female.gltf",
]
const MODEL_SCALE := 0.6
const HEAD_HEIGHT := 1.35  ## bu yüksekliğin üstüne isabet = kafa vuruşu

## mantıksal anim adı -> aday listesi: zombi modeli ilkini, KayKit iskeletleri ikincisini bulur
const ANIM_FALLBACKS := {
	"Run": ["Run", "Running_A", "Gallop", "Walk"],  # kurt: Gallop/Walk
	"Idle": ["Idle"],
	"Punch": ["Punch", "Unarmed_Melee_Attack_Punch_A", "Attack"],  # kurt: Attack
	"Slash": ["SwordSlash", "1H_Melee_Attack_Slice_Diagonal", "Attack", "Punch", "Unarmed_Melee_Attack_Punch_A"],
	"Cast": ["Spellcast_Shoot", "Spellcasting", "Shoot_OneHanded", "Punch"],
	"Death": ["Death", "Death_A"],
	"RecieveHit": ["RecieveHit", "Hit_A", "Idle_HitReact_Left"],
	"StandUp": ["StandUp", "Spawn_Ground"],  # kurt: yok → skip_rise ile atlanır
}
const PROJECTILE := preload("res://scripts/enemy_projectile.gd")

const SND_GROAN := [
	preload("res://assets/audio/zombie/zombie_groan_0.wav"),
	preload("res://assets/audio/zombie/zombie_groan_1.wav"),
	preload("res://assets/audio/zombie/zombie_groan_2.wav"),
]
const SND_ATTACK := [
	preload("res://assets/audio/zombie/zombie_attack_0.wav"),
	preload("res://assets/audio/zombie/zombie_attack_1.wav"),
]
const SND_HURT := [
	preload("res://assets/audio/zombie/zombie_hurt_0.wav"),
	preload("res://assets/audio/zombie/zombie_hurt_1.wav"),
]
const SND_DEATH := preload("res://assets/audio/zombie/zombie_death.wav")
# iskelet sesleri: kemik takırtısı (model yolu "skeleton" içeren TÜM düşmanlar kullanır)
const SKEL_GROAN := [preload("res://assets/audio/zombie/skel_groan_0.wav"),
		preload("res://assets/audio/zombie/skel_groan_1.wav")]
const SKEL_ATTACK := [preload("res://assets/audio/zombie/skel_attack_0.wav"),
		preload("res://assets/audio/zombie/skel_attack_1.wav")]
const SKEL_HURT := [preload("res://assets/audio/zombie/skel_hurt_0.wav"),
		preload("res://assets/audio/zombie/skel_hurt_1.wav")]
const SKEL_DEATH := preload("res://assets/audio/zombie/skel_death.wav")
const PICKUP := preload("res://scripts/pickup.gd")

@export var max_health := 30.0
@export var speed := 3.0
@export var attack_damage := 10.0
@export var attack_range := 1.8
@export var attack_cooldown := 1.3
@export var xp_value := 20
@export var gold_value := 6
@export var model_path := ""  ## boşsa rastgele zombi; iskelet vb. için doldur
@export var model_scale := 0.6  ## boss için büyütülür
@export var base_scale := 0.6  ## modelin "normal insan boyu" ölçeği (zombi 0.6, iskelet 0.85)
@export var is_boss := false
@export var skip_rise := false  ## true: topraktan çıkış yok (Cerberus gibi dramatik girişler)

## boss'a özel dövüş sesi seti (varsayılan: zombi). İskelet bossu kemik takırtısı kullanır.
var voice_groan: Array = SND_GROAN
var voice_attack: Array = SND_ATTACK
var voice_hurt: Array = SND_HURT
var voice_death: AudioStream = SND_DEATH

## --- varyant sistemi (enemy_variants.gd doldurur) ---
@export var variant := "walker"
@export var behavior := "melee"  ## melee / ranged / exploder
@export var attack_logical := "Punch"  ## saldırı animasyonu (Punch/Slash/Cast)
@export var tint := Color(0, 0, 0, 0)  ## a>0 ise zombi derisini bu renge boya
@export var glow := Color(0, 0, 0, 0)  ## a>0 ise modele bu renkte parlama (boss: hayaletimsi okuma)
# menzilli
@export var ranged_range := 18.0  ## bu mesafeye kadar ateş eder
@export var ranged_keep := 7.5  ## bundan yakına gelirse geri çekilir
@export var projectile_damage := 13.0
@export var projectile_speed := 16.0
@export var projectile_color := Color(0.65, 0.35, 1.0)
# patlayan
@export var explode_radius := 3.6
@export var explode_damage := 38.0
# boss özel saldırısı: melee bosslar düz koşmasın → dönemsel mermi yelpazesi savurur
@export var special_shots := 0       ## 0 = özel yok; >0: bu kadar mermilik yelpaze
@export var special_cd := 6.0        ## özel saldırı arası bekleme
@export var special_spread := 26.0   ## yelpaze toplam açısı (derece)
@export var special_type := "nova"   ## skill türü: "nova" (360° patlama) / "volley" (oyuncuya nişanlı seri)
@export var proj_style := "orb"      ## skill mermisi görseli: "orb" (küre) / "skull" (uçan kafatası)
@export var proj_life := 7.0         ## skill mermisi ömrü (uzun → karşıya kadar gider)
var skill_sound: AudioStream = null  ## skill anında çalan tematik ses (boss'a özel)
var skill_burst_sound: AudioStream = null  ## volley'de ani üçlü patlama anının farklı sesi

signal health_changed(health: float, max_health: float)

@onready var agent: NavigationAgent3D = $Agent
@onready var mount: Node3D = $ModelMount

var state := State.SPAWNING
var health: float
var anim: AnimationPlayer
var _anim := {}  ## mantıksal ad -> bu modeldeki gerçek anim adı
var player: Node3D
var _attack_timer := 0.0
var _hit_flash_timer := 0.0
var _hurt_cd := 0.0      ## hurt sesi tekrar aralığı (ses spam'ini önler)
var _react_cd := 0.0     ## irkilme animasyonu tekrar aralığı (titremeyi önler)
var _knockback := Vector3.ZERO  ## vuruşta geri itilme (sönümlenir)
var _voice: AudioStreamPlayer3D
var _groan_timer := 0.0
var _vocal := false  ## sadece bazı zombiler ara ara homurdanır
var _special_timer := 0.0  ## boss özel saldırı bekleme sayacı
var _repath := 0.0  ## rota yeniden hesaplama seyreltme (her kare repath salınım/bug yapıyordu)
var _stuck_t := 0.0  ## yerinde sayma süresi (sıkışma algısı)
var _unstuck := 0.0  ## >0: kenara yalpalayarak köşeden/objeden kurtulma süresi
var _last_pos := Vector3.ZERO  ## bir önceki kareki konum (ilerleme ölçümü)

# özel mermi durumları (yakıcı/dondurucu)
var _burn_dps := 0.0
var _burn_time := 0.0
var _chill_time := 0.0
var _speed_mul := 1.0
var _status_light: OmniLight3D
var _burn_ps: CPUParticles3D
var _chill_ps: CPUParticles3D
var _ice_block: Node3D
static var _ice_mat: StandardMaterial3D


func _ready() -> void:
	health = max_health
	speed *= randf_range(0.85, 1.25)
	player = get_tree().get_first_node_in_group("player")

	# model: belirtilmişse o (iskelet vb.), yoksa rastgele erkek/dişi zombi
	var path: String = model_path if model_path != "" else MODELS[randi() % MODELS.size()]
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.scale = Vector3.ONE * model_scale
	model.rotation_degrees.y = 180.0
	mount.add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	for logical: String in ANIM_FALLBACKS:
		for cand: String in ANIM_FALLBACKS[logical]:
			if anim.has_animation(cand):
				_anim[logical] = cand
				break

	# boss: collision kapsülü model oranında büyüsün
	if model_scale > base_scale + 0.01:
		var k := model_scale / base_scale
		var cap: CapsuleShape3D = $Collision.shape.duplicate()
		cap.radius *= k
		cap.height *= k
		$Collision.shape = cap
		$Collision.position.y *= k

	if model_path == "":
		_apply_zombie_skin(model)  # yeşil tonlama sadece zombilere
	elif path.to_lower().contains("skeleton"):
		# iskelet (kale düşmanı, minion, boss): zombi iniltisi yerine kemik takırtısı
		voice_groan = SKEL_GROAN
		voice_attack = SKEL_ATTACK
		voice_hurt = SKEL_HURT
		voice_death = SKEL_DEATH

	if glow.a > 0.0:
		_apply_glow(model)  # modele renkli parlama (boss → hayaletimsi, kafataslarıyla uyumlu)

	_voice = AudioStreamPlayer3D.new()
	# boss sesi duyulur ama abartısız (silah/müzik altında boğulmasın, her yerden bağırmasın)
	_voice.unit_size = 5.0 if is_boss else 3.5
	_voice.max_distance = 34.0 if is_boss else 24.0
	_voice.volume_db = 0.0 if is_boss else -8.0
	_voice.position.y = 1.2
	add_child(_voice)
	_vocal = true if is_boss else randf() < 0.45  # boss HER ZAMAN sesli (sessiz boss olmaz)
	_groan_timer = randf_range(1.5, 4.0) if is_boss else randf_range(4.0, 12.0)

	if skip_rise:
		# dramatik giriş: topraktan çıkış yok, yerinde belir ve hemen kovala
		mount.position.y = 0.0
		if _anim.has("Idle"):
			anim.play(_anim["Idle"])
		await get_tree().create_timer(0.1).timeout
		if state != State.DEAD:
			state = State.CHASE
			anim.play(_anim["Run"])
		return
	# topraktan yükselme efekti (boss daha derinden çıkar — modeli gömülü kalmasın)
	mount.position.y = -1.6 * (model_scale / base_scale)
	if _anim.has("StandUp"):
		anim.play(_anim["StandUp"])
	var rise := create_tween()
	rise.tween_property(mount, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_CUBIC)
	await rise.finished
	if state != State.DEAD:
		state = State.CHASE
		anim.play(_anim["Run"])
		anim.speed_scale = randf_range(0.9, 1.2)


func _apply_zombie_skin(model: Node3D) -> void:
	# varyant kendi rengini dayatmışsa onu, yoksa rastgele yeşilimsi/soluk zombi tonu
	var skin: Color = tint if tint.a > 0.0 else (Color(0.45, 0.55, 0.38) if randf() < 0.5 else Color(0.5, 0.5, 0.55))
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.get_surface_override_material_count():
			var base := mesh.mesh.surface_get_material(i)
			if base is StandardMaterial3D:
				var m: StandardMaterial3D = base.duplicate()
				m.albedo_color = m.albedo_color * skin
				mesh.set_surface_override_material(i, m)


func _apply_glow(model: Node3D) -> void:
	## modelin tüm yüzeylerine renkli emission ekler (orijinal doku korunur, üstüne parlama)
	## → boss karanlıkta hayaletimsi okunur, fırlattığı kafataslarıyla aynı paletten parlar
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var base := mesh.mesh.surface_get_material(i)
			var m: StandardMaterial3D = base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
			m.emission_enabled = true
			m.emission = Color(glow.r, glow.g, glow.b)
			m.emission_energy_multiplier = glow.a * 1.4  # alfa = parlama şiddeti
			mesh.set_surface_override_material(i, m)


func _physics_process(delta: float) -> void:
	if state == State.DEAD or player == null:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta

	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_hurt_cd = maxf(_hurt_cd - delta, 0.0)
	_react_cd = maxf(_react_cd - delta, 0.0)
	_special_timer = maxf(_special_timer - delta, 0.0)
	_repath = maxf(_repath - delta, 0.0)
	_unstuck = maxf(_unstuck - delta, 0.0)
	_knockback = _knockback.move_toward(Vector3.ZERO, delta * 14.0)

	# sıkışma algısı: kovalarken ilerlemek isteyip yerinde sayıyorsa kenara yalpala
	if state == State.CHASE:
		var expected := speed * _speed_mul * delta
		if expected > 0.001 and global_position.distance_to(_last_pos) < expected * 0.35:
			_stuck_t += delta
			if _stuck_t > 0.3:
				_unstuck = 0.55
				_stuck_t = 0.0
		else:
			_stuck_t = 0.0
	_last_pos = global_position

	# yakıcı/dondurucu mermi durumları
	if _burn_time > 0.0 or _chill_time > 0.0:
		if _burn_time > 0.0:
			_burn_time -= delta
			health -= _burn_dps * delta
			health_changed.emit(maxf(health, 0.0), max_health)
			if health <= 0.0:
				_die()
				return
		if _chill_time > 0.0:
			_chill_time -= delta
			anim.speed_scale = maxf(_speed_mul, 0.3)  # donunca animasyon da yavaşlar (görünür)
			if _chill_time <= 0.0:
				_speed_mul = 1.0
				anim.speed_scale = 1.0
		_update_status_fx()

	if _vocal and (state == State.CHASE or state == State.ATTACK):
		_groan_timer -= delta
		if _groan_timer <= 0.0:
			if is_boss:
				# boss kovalarken sık + pes homurdanır → sürekli tehdit/korku hissi
				_groan_timer = randf_range(3.0, 6.0)
				_say(voice_groan, 0.72, 0.86, true)
			else:
				_groan_timer = randf_range(9.0, 20.0)
				_say(voice_groan, 0.82, 1.18)

	if state == State.SPAWNING:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist > 0.1:
		look_at(player.global_position * Vector3(1, 0, 1) + global_position * Vector3(0, 1, 0), Vector3.UP)

	if behavior == "ranged":
		_ranged_step(to_player, dist)
		move_and_slide()
		return

	# boss özel saldırısı: belirli aralıkla durur, oyuncuya mermi yelpazesi savurur (düz koşmaz)
	# menzil farketmez (yapışıkken bile atar) — yalnız görüş hattı + bekleme dolmuş olmalı
	# nova 360° → görüş hattı gerekmez (sütun arkasından da atar)
	if is_boss and special_shots > 0 and _special_timer == 0.0 \
			and state != State.ATTACK and dist <= 34.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_boss_special()
		move_and_slide()
		return

	if dist <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attack_timer == 0.0 and not player.dead:
			_attack()
	elif state != State.ATTACK or not anim.is_playing():
		state = State.CHASE
		var dir := _chase_dir(to_player)
		velocity.x = dir.x * speed * _speed_mul
		velocity.z = dir.z * speed * _speed_mul
		if anim.current_animation != _anim["Run"]:
			anim.play(_anim["Run"])

	velocity.x += _knockback.x
	velocity.z += _knockback.z
	move_and_slide()


func _chase_dir(to_player: Vector3) -> Vector3:
	## kovalama yönü: navmesh rotasını izle; rota biterse/bozuksa doğrudan
	## oyuncuya yönel; fiziksel sıkışma varsa yana yalpalayarak köşeden kurtul.
	if _repath <= 0.0:  # rotayı her kare değil ~0.25 sn'de bir hesapla (salınım/bug önler)
		_repath = 0.25
		agent.target_position = player.global_position
	var beeline := to_player.normalized()
	var dir := beeline
	if not agent.is_navigation_finished():
		var next := agent.get_next_path_position()
		var nd := next - global_position
		nd.y = 0.0
		if nd.length() > 0.05:  # rota düğümü dejenere değilse onu izle
			dir = nd.normalized()
	if _unstuck > 0.0:  # sıkıştık → hedefe doğru ama bir yana kayarak duvar/obje boyunca süzül
		var perp := Vector3(-beeline.z, 0.0, beeline.x)
		dir = (dir + perp * 1.3).normalized()
	return dir


func _ranged_step(to_player: Vector3, dist: float) -> void:
	## büyücü/okçu: menzilde tut, görüş hattı varsa ateşle, çok yaklaşınca geri çekil
	velocity.x = 0.0
	velocity.z = 0.0
	if state == State.ATTACK:
		return  # büyü yaparken sabit dur
	var run: String = _anim.get("Run")
	if _attack_timer == 0.0 and dist <= ranged_range and not player.dead and _has_los():
		_shoot()
	elif dist < ranged_keep:
		var away := (-to_player).normalized()
		velocity.x = away.x * speed * _speed_mul
		velocity.z = away.z * speed * _speed_mul
		if anim.current_animation != run:
			anim.play(run)
	elif dist > ranged_range or not _has_los():
		state = State.CHASE
		var dir := _chase_dir(to_player)
		velocity.x = dir.x * speed * _speed_mul
		velocity.z = dir.z * speed * _speed_mul
		if anim.current_animation != run:
			anim.play(run)
	else:
		var idle: String = _anim.get("Idle", run)
		if anim.current_animation != idle:
			anim.play(idle)


func _has_los() -> bool:
	if player == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.2, 0)
	var to := player.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)  # yalnızca dünya/duvarlar
	q.exclude = [self]
	return space.intersect_ray(q).is_empty()


func _shoot() -> void:
	state = State.ATTACK
	_attack_timer = attack_cooldown
	anim.play(_anim.get(attack_logical, _anim.get("Punch", _anim["Run"])))
	if randf() < 0.6:
		_say(voice_attack, 0.9, 1.1, true)
	await get_tree().create_timer(0.55).timeout
	if state == State.DEAD or player == null:
		return
	if _has_los():
		var origin := global_position + Vector3(0, 1.2, 0)
		var target := player.global_position + Vector3(0, 1.0, 0)
		var dir := (target - origin).normalized()
		var proj := PROJECTILE.new()
		proj.damage = projectile_damage
		proj.velocity = dir * projectile_speed
		proj.color = projectile_color
		get_parent().add_child(proj)
		proj.global_position = origin + dir * 1.0
	await get_tree().create_timer(0.3).timeout
	if state == State.ATTACK:
		state = State.CHASE


func _boss_special() -> void:
	## boss skill: durup özel saldırı yapar (düz koşmaya alternatif tehdit).
	## türe göre dallanır: "nova" 360° patlama / "volley" oyuncuya nişanlı seri atış.
	state = State.ATTACK
	_attack_timer = attack_cooldown
	_special_timer = special_cd
	anim.play(_anim.get(attack_logical, _anim.get("Punch", _anim["Run"])))
	_play_skill_sound()  # tematik "skill" sesi (boss'a özel)
	await get_tree().create_timer(0.55).timeout
	if state == State.DEAD or player == null:
		return
	if special_type == "volley":
		await _special_volley()
	else:
		_special_nova()
	await get_tree().create_timer(0.35).timeout
	if state == State.ATTACK:
		state = State.CHASE


func _play_skill_sound() -> void:
	## skill'e özel ses; tanımlı değilse pes, tehditkâr dövüş sesine düşer
	if skill_sound != null:
		_say(skill_sound, 0.92, 1.04, true)
	else:
		_say(voice_attack, 0.66, 0.82, true)


func _spawn_enemy_proj(origin: Vector3, dir: Vector3, scale := 1.0) -> void:
	var proj := PROJECTILE.new()
	proj.damage = projectile_damage
	proj.velocity = dir * projectile_speed
	proj.color = projectile_color
	proj.style = proj_style
	proj.life = proj_life
	get_parent().add_child(proj)
	proj.global_position = origin + dir * 1.6
	proj.scale = Vector3.ONE * scale


func _special_nova() -> void:
	## DAİRESEL NOVA (bahçıvan): 360° dışa açılan iri yavaş spor mermileri → her yöne kaçılır
	var origin := global_position + Vector3(0, 1.3, 0)
	for i in special_shots:
		var ang := TAU * float(i) / float(special_shots)
		_spawn_enemy_proj(origin, Vector3(cos(ang), 0.0, sin(ang)), 1.7)


func _special_volley() -> void:
	## NİŞANLI SERİ (iskelet lord): oyuncuya kafatası fırlatır — çoğunlukla TEK TEK nişanlı,
	## ama ara ara BİR ANDA 3 kafatasını üst üste savurur (ayrı, daha sert bir ses) →
	## ritmi bozan, kaçması zor "yoğunluk anları" yaratır. Kafatasları karşıya kadar gider.
	var spread := deg_to_rad(special_spread) * 0.5
	for i in special_shots:
		if state == State.DEAD or player == null:
			return
		var origin := global_position + Vector3(0, 1.3, 0)
		var target := player.global_position + Vector3(0, 1.0, 0)
		var base_dir := (target - origin).normalized()
		var triple := i > 0 and i % 3 == 0  # her 3. atışta ani üçlü salvo
		if triple:
			# ani 3'lü: sıkı yelpazeyle üst üste, farklı (daha sert) ses
			if skill_burst_sound != null:
				_say(skill_burst_sound, 0.92, 1.02, true)
			else:
				_say(voice_attack, 0.7, 0.8, true)
			for j in 3:
				var off := deg_to_rad(11.0) * (j - 1)  # -11°, 0°, +11°
				_spawn_enemy_proj(origin, base_dir.rotated(Vector3.UP, off), 1.3)
			await get_tree().create_timer(0.5).timeout  # salvo sonrası kısa nefes
		else:
			var dir := base_dir.rotated(Vector3.UP, randf_range(-spread, spread))
			_spawn_enemy_proj(origin, dir, 1.15)
			if i % 2 == 0:  # atlamalı kısa kemik takırtısı (takırtı spam'i olmasın)
				_say(voice_attack, 1.05, 1.2)
			await get_tree().create_timer(0.22).timeout


func _attack() -> void:
	state = State.ATTACK
	_attack_timer = attack_cooldown
	anim.play(_anim.get(attack_logical, _anim.get("Punch", _anim["Run"])))
	if randf() < 0.5:  # her vuruşta değil — sürekli ses sinir bozucu oluyordu
		_say(voice_attack, 0.95, 1.12, true)
	await get_tree().create_timer(0.45).timeout
	if state == State.DEAD or player == null:
		return
	if global_position.distance_to(player.global_position) <= attack_range + 0.5:
		player.take_damage(attack_damage, self)  # self: Diken Zırh yansıması için
	await get_tree().create_timer(0.3).timeout
	if state == State.ATTACK:
		state = State.CHASE


func ignite(dps: float, dur: float) -> void:
	if state == State.DEAD:
		return
	_burn_dps = maxf(_burn_dps, dps)
	_burn_time = maxf(_burn_time, dur)


func chill(factor: float, dur: float) -> void:
	if state == State.DEAD:
		return
	_speed_mul = 1.0 - clampf(factor, 0.0, 0.8)
	_chill_time = maxf(_chill_time, dur)


func _update_status_fx() -> void:
	var burning := _burn_time > 0.0
	var chilled := _chill_time > 0.0
	# ışık
	if _status_light == null:
		_status_light = OmniLight3D.new()
		_status_light.omni_range = 3.0
		_status_light.position.y = 1.0
		add_child(_status_light)
	_status_light.visible = burning or chilled
	if burning:
		_status_light.light_color = Color(1.0, 0.45, 0.1)
		_status_light.light_energy = 2.5 + randf() * 1.5
	elif chilled:
		_status_light.light_color = Color(0.4, 0.7, 1.0)
		_status_light.light_energy = 1.8
	# alev partikülleri (yükselen, additive, sarı→kırmızı sönen)
	if burning and _burn_ps == null:
		_burn_ps = _make_flame_ps()
	if _burn_ps != null:
		_burn_ps.emitting = burning
	# buz partikülleri (aşağı süzülen mavi-beyaz kristal)
	if chilled and _chill_ps == null:
		_chill_ps = _make_frost_ps()
	if _chill_ps != null:
		_chill_ps.emitting = chilled
	# buz küpü: düşmanı saran yarı saydam buz bloğu (içine hapsolmuş gibi)
	if chilled and _ice_block == null:
		_ice_block = _make_ice_block()
	if _ice_block != null:
		_ice_block.visible = chilled


func _make_flame_ps() -> CPUParticles3D:
	var ps := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.62, 0.62)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = load("res://assets/fx/flame.png")
	mat.vertex_color_use_as_albedo = true
	qm.material = mat
	ps.mesh = qm
	ps.amount = 20
	ps.lifetime = 0.6
	ps.local_coords = false
	ps.direction = Vector3.UP
	ps.spread = 16.0
	ps.gravity = Vector3(0, 3.2, 0)  # yükselen alev
	ps.initial_velocity_min = 0.5
	ps.initial_velocity_max = 1.3
	ps.scale_amount_min = 0.7
	ps.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.55, 1.0))
	ramp.set_color(1, Color(1.0, 0.18, 0.04, 0.0))
	ramp.add_point(0.5, Color(1.0, 0.5, 0.12, 0.85))
	ps.color_ramp = ramp
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ps.emission_box_extents = Vector3(0.35, 0.6, 0.35)
	ps.position = Vector3(0, 0.7, 0)
	add_child(ps)
	return ps


func _ice_material() -> StandardMaterial3D:
	## ışık kıran, kristalli, donuk buz — tüm düşmanlar paylaşır (ucuz)
	if _ice_mat != null:
		return _ice_mat
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.12
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.seamless = true
	ntex.as_normal_map = true
	ntex.bump_strength = 6.0
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.66, 0.85, 1.0, 0.4)
	m.roughness = 0.06
	m.metallic = 0.0
	m.metallic_specular = 0.95
	m.normal_enabled = true
	m.normal_texture = ntex
	m.refraction_enabled = true          # arka planı bük → kalın cam/buz hissi
	m.refraction_scale = 0.05
	m.refraction_texture = ntex
	m.rim_enabled = true                 # kenarlarda soğuk parlama
	m.rim = 1.0
	m.rim_tint = 0.4
	m.emission_enabled = true
	m.emission = Color(0.4, 0.7, 1.0)
	m.emission_energy_multiplier = 0.45
	_ice_mat = m
	return m


func _make_ice_block() -> Node3D:
	## kristalli buz: fazetli gövde (iç içe iki kutu) + sivri tepe + fışkıran dikenler
	## boyut görünür düşman boyuna otursun: yükseklik ~1.8×model_scale
	var root := Node3D.new()
	var ice := _ice_material()
	var h := 1.8 * model_scale * 1.12   # görünür yükseklik payı
	var wd := 0.78 * model_scale        # genişlik/derinlik

	var core := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(wd, h, wd)
	cb.material = ice
	core.mesh = cb
	root.add_child(core)

	var facet := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(wd * 0.82, h * 0.98, wd * 0.82)
	fb.material = ice
	facet.mesh = fb
	facet.rotation.y = PI / 4.0  # 45° dönük ikinci kutu → sekizgen silüet
	root.add_child(facet)

	var top := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(wd * 1.05, h * 0.3, wd * 1.05)
	pm.material = ice
	top.mesh = pm
	top.position.y = h * 0.58
	top.rotation.y = PI / 4.0
	root.add_child(top)

	var r := RandomNumberGenerator.new()
	r.seed = get_instance_id()
	for i in 5:  # yanlardan fışkıran buz dikenleri
		var spike := MeshInstance3D.new()
		var sm := PrismMesh.new()
		sm.size = Vector3(wd * 0.3, r.randf_range(0.28, 0.45) * h, wd * 0.3)
		sm.material = ice
		spike.mesh = sm
		var ang := r.randf() * TAU
		spike.position = Vector3(cos(ang) * wd * 0.5, r.randf_range(-0.15, 0.35) * h, sin(ang) * wd * 0.5)
		spike.rotation = Vector3(r.randf_range(-1.1, 1.1), ang, r.randf_range(-1.1, 1.1))
		root.add_child(spike)

	root.position.y = h * 0.5
	add_child(root)
	return root


func _make_frost_ps() -> CPUParticles3D:
	var ps := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.42, 0.42)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = load("res://assets/fx/frost.png")
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission_texture = load("res://assets/fx/frost.png")
	mat.emission = Color(0.5, 0.75, 1.0)
	mat.emission_energy_multiplier = 1.5
	qm.material = mat
	ps.mesh = qm
	ps.amount = 16
	ps.lifetime = 1.1
	ps.local_coords = false
	ps.direction = Vector3.DOWN
	ps.spread = 25.0
	ps.gravity = Vector3(0, -1.3, 0)
	ps.initial_velocity_min = 0.2
	ps.initial_velocity_max = 0.6
	ps.scale_amount_min = 0.5
	ps.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.95, 1.0, 0.0))
	ramp.set_color(1, Color(0.5, 0.78, 1.0, 0.0))
	ramp.add_point(0.4, Color(0.7, 0.9, 1.0, 0.95))
	ps.color_ramp = ramp
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = 0.55
	ps.position = Vector3(0, 1.2, 0)
	add_child(ps)
	return ps


func is_headshot(point: Vector3) -> bool:
	return point.y - global_position.y > HEAD_HEIGHT * (model_scale / base_scale)


func take_damage(amount: float, _headshot := false) -> void:
	if state == State.DEAD:
		return
	health -= amount
	health_changed.emit(maxf(health, 0.0), max_health)
	_blood_burst()
	if health <= 0.0:
		_die()
		return
	# geri itilme (oyuncudan uzağa); boss'ta çok hafif → ezilmez ama tepki verir
	if player != null:
		var away := global_position - player.global_position
		away.y = 0.0
		if away.length() > 0.01:
			_knockback = away.normalized() * (0.7 if is_boss else 3.0)
	# irkilme animasyonu: boss'ta YOK (yürüyüşü bozup titretiyordu), normal
	# düşmanda aralıklı (her mermide baştan oynamasın)
	if _react_cd <= 0.0:
		_react_cd = 0.3
		if not is_boss and state != State.ATTACK:
			anim.play(_anim["RecieveHit"])
	# hurt sesi: aralıklı ve kendini kesmeden (ağaağa spam'i biter)
	if _hurt_cd <= 0.0:
		_hurt_cd = randf_range(0.45, 0.7)
		_say(voice_hurt, 0.92, 1.15, is_boss)  # boss: vuruşta sesi kesip mutlaka inle


func _blood_burst() -> void:
	## vuruş geri bildirimi: gövde hizasında kısa kan sıçraması (oyuncuya doğru)
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.emitting = true
	ps.amount = 8
	ps.lifetime = 0.35
	ps.explosiveness = 1.0
	ps.position = Vector3(0, 1.1, 0)
	ps.gravity = Vector3(0, -6.0, 0)
	ps.initial_velocity_min = 1.5
	ps.initial_velocity_max = 3.5
	ps.spread = 55.0
	if player != null:
		var d := global_position - player.global_position
		d.y = 0.0
		if d.length() > 0.01:
			ps.direction = d.normalized() + Vector3(0, 0.4, 0)
	ps.scale_amount_min = 0.12
	ps.scale_amount_max = 0.28
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.6, 0.02, 0.02, 1.0))
	ramp.set_color(1, Color(0.25, 0.0, 0.0, 0.0))
	ps.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = load("res://assets/fx/blood_dot.png")
	mat.vertex_color_use_as_albedo = true
	ps.mesh = QuadMesh.new()
	ps.material_override = mat
	add_child(ps)
	get_tree().create_timer(0.6).timeout.connect(ps.queue_free)


func _say(streams, lo: float, hi: float, force := false) -> void:
	if _voice == null or (_voice.playing and not force):
		return
	_voice.stream = streams[randi() % streams.size()] if streams is Array else streams
	_voice.pitch_scale = randf_range(lo, hi)
	_voice.play()


func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	$Collision.set_deferred("disabled", true)
	anim.speed_scale = 1.0
	anim.play(_anim["Death"])
	_say(voice_death, 0.85, 1.05, true)
	if behavior == "exploder":
		_explode()
	Game.add_kill()
	_drop_loot()
	died.emit()
	await get_tree().create_timer(2.0).timeout
	var tween := create_tween()
	tween.tween_property(mount, "position:y", -1.5, 0.8)
	tween.tween_callback(queue_free)


func _explode() -> void:
	## patlayan zombi: büyüyen ışıklı küre + yakındaki oyuncuya alan hasarı
	var col := Color(0.78, 0.9, 0.25)
	var fx := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	fx.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.albedo_color = Color(col.r, col.g, col.b, 0.55)
	m.emission = col
	m.emission_energy_multiplier = 3.0
	fx.material_override = m
	get_parent().add_child(fx)
	fx.global_position = global_position + Vector3(0, 1.0, 0)
	var lt := OmniLight3D.new()
	lt.light_color = col
	lt.light_energy = 6.0
	lt.omni_range = explode_radius * 2.0
	fx.add_child(lt)
	var t := fx.create_tween()
	t.set_parallel(true)
	t.tween_property(fx, "scale", Vector3.ONE * explode_radius * 2.0, 0.35)
	t.tween_property(m, "albedo_color:a", 0.0, 0.35)
	t.tween_property(lt, "light_energy", 0.0, 0.35)
	t.chain().tween_callback(fx.queue_free)
	if player != null and not player.dead and global_position.distance_to(player.global_position) <= explode_radius:
		player.take_damage(explode_damage)


func _drop_loot() -> void:
	## XP küresi + altın yere saçılır; oyuncu yürüyerek/mıknatısla toplar
	var origin := global_position + Vector3(0, 1.0, 0)
	var holder := get_parent()
	PICKUP.spawn(holder, origin, "xp", xp_value)
	var gold_left := gold_value
	var coins := 1 + randi() % 2 if not is_boss else 6
	for i in coins:
		var amount := gold_left / (coins - i)
		gold_left -= amount
		if amount > 0:
			PICKUP.spawn(holder, origin, "gold", amount)
