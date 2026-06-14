extends RefCounted
## Düşman varyant tablosu. Biome + stage'e göre ağırlıklı seçim yapar ve
## zombie.gd örneğine statları uygular. Yeni düşman = TABLE'a satır ekle.

const SK := "res://addons/kaykit_character_pack_skeletons/Characters/gltf/"
const SK_BASE := 0.85  ## iskelet modeli bu ölçekte ~1.85m

## Çarpanlar TABAN statlara göre (taban: hp 40, hız 3.0, hasar 10, xp 20, gold ~stage).
## size: model ölçeği (base_scale × size). behavior: melee / ranged / exploder.
const TABLE := {
	"walker": {
		"name": "Sürünen", "model": "", "size": 1.0,
		"hp": 1.0, "speed": 1.0, "dmg": 1.0, "xp": 1.0, "gold": 1.0,
		"behavior": "melee", "attack": "Punch",
		"weight": 100, "min_stage": 1, "biomes": ["garden", "castle", "cloud"],
	},
	"runner": {
		"name": "Koşucu", "model": "", "size": 0.92,
		"hp": 0.5, "speed": 1.6, "dmg": 0.7, "xp": 0.9, "gold": 0.9,
		"behavior": "melee", "attack": "Punch", "tint": Color(0.72, 0.4, 0.34),
		"weight": 46, "min_stage": 2, "biomes": ["garden", "castle", "cloud"],
	},
	"brute": {
		"name": "Ezici", "model": "", "size": 1.55,
		"hp": 3.2, "speed": 0.6, "dmg": 2.4, "xp": 2.2, "gold": 2.4,
		"behavior": "melee", "attack": "Slash", "tint": Color(0.4, 0.5, 0.32),
		"weight": 14, "min_stage": 3, "biomes": ["garden", "castle", "cloud"],
	},
	"exploder": {
		"name": "Patlayan", "model": "", "size": 1.05,
		"hp": 0.65, "speed": 1.25, "dmg": 0.4, "xp": 1.4, "gold": 1.3,
		"behavior": "exploder", "attack": "Punch", "tint": Color(0.78, 0.85, 0.2),
		"explode_radius": 3.6, "explode_damage": 38.0,
		"weight": 22, "min_stage": 4, "biomes": ["garden", "castle", "cloud"],
	},
	"skeleton_warrior": {
		"name": "İskelet Savaşçı", "model": SK + "Skeleton_Warrior.glb", "base": SK_BASE, "size": 1.0,
		"hp": 1.5, "speed": 0.92, "dmg": 1.4, "xp": 1.3, "gold": 1.3,
		"behavior": "melee", "attack": "Slash",
		"weight": 34, "min_stage": 7, "biomes": ["castle", "cloud"],
	},
	"skeleton_rogue": {
		"name": "İskelet Haydut", "model": SK + "Skeleton_Rogue.glb", "base": SK_BASE, "size": 0.95,
		"hp": 0.6, "speed": 1.75, "dmg": 0.85, "xp": 1.1, "gold": 1.1,
		"behavior": "melee", "attack": "Slash",
		"weight": 30, "min_stage": 7, "biomes": ["castle", "cloud"],
	},
	"skeleton_mage": {
		"name": "İskelet Büyücü", "model": SK + "Skeleton_Mage.glb", "base": SK_BASE, "size": 1.0,
		"hp": 0.85, "speed": 0.8, "dmg": 0.5, "xp": 1.6, "gold": 1.5,
		"behavior": "ranged", "attack": "Cast",
		"ranged_range": 18.0, "ranged_keep": 7.5, "cooldown": 2.3,
		"pdmg": 13.0, "pspeed": 16.0, "pcolor": Color(0.65, 0.35, 1.0),
		"weight": 22, "min_stage": 8, "biomes": ["castle", "cloud"],
	},
}


static func roll(biome: String, stage: int, rng: RandomNumberGenerator) -> String:
	biome = biome.trim_suffix("_boss")  # boss arenası ambient spawn'ları ana havuzu kullansın
	var pool: Array[String] = []
	var weights: Array[int] = []
	var total := 0
	for id: String in TABLE:
		var c: Dictionary = TABLE[id]
		if stage < int(c["min_stage"]):
			continue
		if not (c["biomes"] as Array).has(biome):
			continue
		pool.append(id)
		weights.append(int(c["weight"]))
		total += int(c["weight"])
	if pool.is_empty():
		return "walker"
	var pick := rng.randi_range(0, total - 1)
	for i in pool.size():
		pick -= weights[i]
		if pick < 0:
			return pool[i]
	return pool[0]


static func apply(z: Node, id: String, stage: int, rng: RandomNumberGenerator) -> void:
	var c: Dictionary = TABLE[id]
	var hp_scale := 1.0 + 0.15 * (stage - 1)
	var base: float = c.get("base", 0.6)

	z.variant = id
	z.model_path = c["model"]
	z.base_scale = base
	z.model_scale = base * float(c["size"])
	z.max_health = 40.0 * hp_scale * float(c["hp"])
	z.speed = (3.0 + 0.15 * (stage - 1)) * float(c["speed"]) * rng.randf_range(0.92, 1.08)
	z.attack_damage = 10.0 * float(c["dmg"])
	z.xp_value = int((12 + 5 * (stage - 1)) * float(c["xp"]))
	z.gold_value = int((4 + stage) * float(c["gold"])) + rng.randi() % 3
	z.behavior = c["behavior"]
	z.attack_logical = c["attack"]
	if c.has("tint"):
		z.tint = c["tint"]
	if c["behavior"] == "ranged":
		z.ranged_range = c["ranged_range"]
		z.ranged_keep = c["ranged_keep"]
		z.attack_cooldown = c["cooldown"]
		z.projectile_damage = c["pdmg"]
		z.projectile_speed = c["pspeed"]
		z.projectile_color = c["pcolor"]
	elif c["behavior"] == "exploder":
		z.explode_radius = c["explode_radius"]
		z.explode_damage = c["explode_damage"]
