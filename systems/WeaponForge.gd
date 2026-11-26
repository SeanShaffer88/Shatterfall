class_name WeaponForge
extends RefCounted
## Same-type absorption, salvage, Build-Up evolution and weapon power math.
## BLUEPRINT §2C with D5, D16, D17, D18, D25, D26, D31. Driven by data/weapons.json.

var _cfg: Dictionary


func _init(weapons_cfg: Dictionary) -> void:
	_cfg = weapons_cfg


# --- Lookup -----------------------------------------------------------------

func class_order() -> Array:
	return _cfg["class_order"]


func class_cfg(weapon_class: String) -> Dictionary:
	return _cfg["classes"][weapon_class]


func shard_id(weapon_class: String) -> String:
	return class_cfg(weapon_class)["shard_id"]


func stage_entry(weapon_class: String, stage: int) -> Dictionary:
	for e in _cfg["evolutions"][weapon_class]:
		if int(e["stage"]) == stage:
			return e
	return {}


func create_weapon(weapon_class: String, rarity: int = 1, level: int = 1) -> Weapon:
	var w := Weapon.new()
	w.weapon_class = weapon_class
	w.owner_hero = class_cfg(weapon_class)["owner_hero"]
	w.rarity = rarity
	w.level = mini(level, level_cap())
	w.evo_stage = 1
	w.weapon_id = stage_entry(weapon_class, 1)["weapon_id"]
	return w


# --- Power (D16, D17, D25) --------------------------------------------------

func atk_eff(w: Weapon) -> float:
	var g: Dictionary = _cfg["growth"]
	return float(class_cfg(w.weapon_class)["base_atk"]) \
		* pow(float(g["atk_per_level"]), w.level - 1) \
		* pow(float(g["atk_per_stage"]), w.evo_stage - 1) \
		* (1.0 + float(g["atk_per_stack"]) * w.atk_stacks)


## coeff = level-1 listed damage ÷ class base ATK (D25).
func coeff(weapon_class: String, damage_l1: float) -> float:
	return damage_l1 / float(class_cfg(weapon_class)["base_atk"])


func damage(w: Weapon, damage_l1: float, boon_mult: float = 1.0, mark_mult: float = 1.0, crit: bool = false) -> int:
	var crit_mult: float = float(_cfg["growth"]["crit_multiplier"]) if crit else 1.0
	var raw := atk_eff(w) * coeff(w.weapon_class, damage_l1) * boon_mult * mark_mult * crit_mult
	return maxi(1, roundi(raw))


func crit_chance(w: Weapon) -> float:
	var g: Dictionary = _cfg["growth"]
	return float(g["crit_base"]) + float(g["crit_per_stack"]) * w.crit_stacks


func hp_bonus(w: Weapon) -> int:
	return int(_cfg["growth"]["hp_per_stack"]) * w.hp_stacks


# --- XP (D31) ---------------------------------------------------------------

func level_cap() -> int:
	return int(_cfg["xp"]["level_cap"])


## XP needed to go from `level` to `level + 1`; 0 at the cap.
func xp_to_next(level: int) -> int:
	if level >= level_cap():
		return 0
	var x: Dictionary = _cfg["xp"]
	return roundi(float(x["base"]) * pow(float(x["growth"]), level - 1))


func absorb_xp_value(fodder: Weapon) -> int:
	var x: Dictionary = _cfg["xp"]
	var base_xp: int = int(x["base_xp_by_rarity"][fodder.rarity - 1])
	return base_xp + fodder.level * int(x["per_fodder_level"])


# --- Absorb (D5, D16, D18) --------------------------------------------------

## Same weapon class AND different uid AND same owner hero (§2C).
func can_absorb(main: Weapon, fodder: Weapon) -> bool:
	return main != null and fodder != null \
		and main.weapon_class == fodder.weapon_class \
		and main.uid != fodder.uid \
		and fodder.owner_hero == main.owner_hero


## Absorbs `fodder_uid` into the equipped main `main_uid`. Mutates the inventory.
## Result: { ok, error, xp_gained, levels_gained, xp_discarded, substat }.
func absorb(inv: Inventory, main_uid: String, fodder_uid: String) -> Dictionary:
	var main := inv.get_weapon(main_uid)
	var fodder := inv.get_weapon(fodder_uid)
	if main == null or fodder == null:
		return _fail("unknown weapon")
	if not inv.is_main(main_uid):
		return _fail("absorb target must be an equipped main")
	if inv.is_main(fodder_uid):
		return _fail("an equipped main cannot be absorbed")
	if not can_absorb(main, fodder):
		return _fail("fodder must match the main's weapon class and owner hero")
	var gained := absorb_xp_value(fodder)
	var xp_result := _apply_xp(main, gained)
	var substat := _apply_substat(main)
	inv.remove_weapon(fodder_uid)
	return {
		"ok": true, "error": "",
		"xp_gained": gained,
		"levels_gained": xp_result["levels"],
		"xp_discarded": xp_result["discarded"],
		"substat": substat,
	}


## XP the main would discard if `fodder` were absorbed now (for the at-cap warning, D31).
func would_discard_xp(main: Weapon, fodder: Weapon) -> int:
	var probe := Weapon.from_dict(main.to_dict())
	return _apply_xp(probe, absorb_xp_value(fodder))["discarded"]


func _apply_xp(w: Weapon, amount: int) -> Dictionary:
	var cap := level_cap()
	var levels := 0
	w.xp += amount
	while w.level < cap and w.xp >= xp_to_next(w.level):
		w.xp -= xp_to_next(w.level)
		w.level += 1
		levels += 1
	var discarded := 0
	if w.level >= cap:
		discarded = w.xp
		w.xp = 0
	return {"levels": levels, "discarded": discarded}


## Grants the next sub-stat in the fixed rotation, skipping capped ones (D16).
## Returns the sub-stat granted, or "" when all three are capped.
func _apply_substat(w: Weapon) -> String:
	var order: Array = _cfg["growth"]["substat_order"]
	var cap := int(_cfg["growth"]["substat_cap"])
	for i in order.size():
		var idx := (w.next_substat + i) % order.size()
		var s: String = order[idx]
		if w.stacks_of(s) < cap:
			w.add_stack(s)
			w.next_substat = (idx + 1) % order.size()
			return s
	return ""


# --- Salvage (D31) ----------------------------------------------------------

func salvage_yield(w: Weapon) -> int:
	return int(_cfg["salvage"]["base_shards"]) + w.rarity


## Destroys a non-main weapon (any class) for its own class shards.
func salvage(inv: Inventory, uid: String) -> Dictionary:
	var w := inv.get_weapon(uid)
	if w == null:
		return _fail("unknown weapon")
	if inv.is_main(uid):
		return _fail("an equipped main cannot be salvaged")
	var n := salvage_yield(w)
	var sid := shard_id(w.weapon_class)
	inv.add_shards(sid, n)
	inv.remove_weapon(uid)
	return {"ok": true, "error": "", "shard_id": sid, "shards": n}


# --- Build-Up evolution (D26, D31) ------------------------------------------

## The next stage's recipe, or {} at the final stage.
func next_evolution(w: Weapon) -> Dictionary:
	return stage_entry(w.weapon_class, w.evo_stage + 1)


## Per-requirement status, also used later for the AD8 rune ignition.
func evolution_status(inv: Inventory, w: Weapon) -> Dictionary:
	var recipe := next_evolution(w)
	if recipe.is_empty():
		return {"available": false, "final": true, "level_ok": false, "shards_ok": false, "essence_ok": false, "recipe": {}}
	var essence_id: String = recipe.get("boss_essence_id", "")
	var level_ok := w.level >= int(recipe["req_level"])
	var shards_ok := inv.shard_count(shard_id(w.weapon_class)) >= int(recipe["shard_cost"])
	var essence_ok := essence_id == "" or inv.essence_count(essence_id) >= 1
	return {
		"available": level_ok and shards_ok and essence_ok, "final": false,
		"level_ok": level_ok, "shards_ok": shards_ok, "essence_ok": essence_ok,
		"recipe": recipe,
	}


## Evolves an equipped main: consumes shards (and essence), keeps level and sub-stats.
func evolve(inv: Inventory, uid: String) -> Dictionary:
	var w := inv.get_weapon(uid)
	if w == null:
		return _fail("unknown weapon")
	if not inv.is_main(uid):
		return _fail("only an equipped main can evolve")
	var status := evolution_status(inv, w)
	if status["final"]:
		return _fail("already at the final evolution stage")
	if not status["available"]:
		return _fail("evolution requirements not met")
	var recipe: Dictionary = status["recipe"]
	inv.add_shards(shard_id(w.weapon_class), -int(recipe["shard_cost"]))
	var essence_id: String = recipe.get("boss_essence_id", "")
	if essence_id != "":
		inv.add_essence(essence_id, -1)
	w.evo_stage = int(recipe["stage"])
	w.weapon_id = recipe["weapon_id"]
	return {"ok": true, "error": "", "weapon_id": w.weapon_id, "evo_stage": w.evo_stage}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}
