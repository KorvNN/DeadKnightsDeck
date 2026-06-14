class_name UpgradeCard
extends Resource
## Bir upgrade kartı.
##  - stat kartı: weapon_mul/add (silaha) + player_mul/add (oyuncuya)
##  - evrim kartı: new_weapon dolu → silahı tamamen değiştirir
## requires: {kart_id: en az kaç kez seçilmiş} ile dal/önkoşul sistemi.

@export var id := ""
@export var title := ""
@export_multiline var description := ""
@export_range(0, 3) var rarity := 0  ## 0 sıradan, 1 nadir, 2 epik, 3 efsanevi
@export var max_stacks := 5
@export var requires: Dictionary = {}

@export_group("Stat etkileri")
@export var weapon_mul: Dictionary = {}
@export var weapon_add: Dictionary = {}
@export var player_mul: Dictionary = {}
@export var player_add: Dictionary = {}

@export_group("Silah evrimi")
@export var new_weapon: WeaponData  ## doluysa bu kart silahı değiştirir


func icon() -> Texture2D:
	## kart ikonu: assets/ui/cards/<id>.png (beyaz siluet, UI rarity rengine boyar)
	var path := "res://assets/ui/cards/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path)
	return null


func is_available() -> bool:
	if Game.card_count(id) >= max_stacks:
		return false
	for req_id: String in requires:
		if Game.card_count(req_id) < int(requires[req_id]):
			return false
	return true


func apply(player: Node, weapon: Node) -> void:
	if new_weapon != null:
		weapon.equip(new_weapon)
		return
	if not weapon_mul.is_empty() or not weapon_add.is_empty():
		weapon.add_weapon_mod(weapon_mul, weapon_add)
	for k: String in player_mul:
		player.set(k, player.get(k) * player_mul[k])
	for k: String in player_add:
		player.set(k, player.get(k) + player_add[k])
