class_name LootTable
extends RefCounted
## Stage drop rolls (D19, D30) with the Grudge class bias (D11).
## Drops are plain descriptors; GameState turns them into inventory weapons.

var _drops: Dictionary     # stages.json -> stage.drops
var _weapons: Dictionary   # weapons.json
var _essence_id: String


func _init(stage_cfg: Dictionary, weapons_cfg: Dictionary) -> void:
	_drops = stage_cfg["drops"]
	_essence_id = stage_cfg["boss"]["essence_id"]
	_weapons = weapons_cfg


## Normalized class probabilities. `grudge_hero` is the stage's last clearing
## hero ("" before the first clear): every class it does not own gets ×bias.
func class_weights(run_hero: String, grudge_hero: String) -> Dictionary:
	var own: Array = []
	var other: Array = []
	for cls in _weapons["class_order"]:
		if _owner(cls) == run_hero:
			own.append(cls)
		else:
			other.append(cls)
	var w := {}
	for cls in own:
		w[cls] = float(_drops["hero_class_weight"]) / own.size()
	for cls in other:
		w[cls] = float(_drops["other_class_weight"]) / other.size()
	if grudge_hero != "":
		for cls in w:
			if _owner(cls) != grudge_hero:
				w[cls] *= float(_drops["grudge_bias"])
	var total := 0.0
	for cls in w:
		total += w[cls]
	for cls in w:
		w[cls] /= total
	return w


## {} for no drop, else { weapon_class, rarity, level }.
func roll_room_drop(rng: RandomNumberGenerator, run_hero: String, grudge_hero: String) -> Dictionary:
	if rng.randf() >= float(_drops["room_drop_chance"]):
		return {}
	return _roll_weapon(rng, run_hero, grudge_hero, int(_drops["room_drop_level"]))


## Vespera always drops one weapon and one essence (D19).
func roll_boss_drop(rng: RandomNumberGenerator, run_hero: String, grudge_hero: String) -> Dictionary:
	return {
		"weapon": _roll_weapon(rng, run_hero, grudge_hero, int(_drops["boss_drop_level"])),
		"essence_id": _essence_id,
	}


func _roll_weapon(rng: RandomNumberGenerator, run_hero: String, grudge_hero: String, level: int) -> Dictionary:
	var probs := class_weights(run_hero, grudge_hero)
	var order: Array = _weapons["class_order"]
	var weights := PackedFloat32Array()
	for cls in order:
		weights.append(probs[cls])
	var cls: String = order[rng.rand_weighted(weights)]
	var rarity := rng.rand_weighted(PackedFloat32Array(_drops["rarity_weights"])) + 1
	return {"weapon_class": cls, "rarity": rarity, "level": level}


func _owner(cls: String) -> String:
	return _weapons["classes"][cls]["owner_hero"]
