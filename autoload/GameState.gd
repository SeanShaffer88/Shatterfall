extends Node
## Global game state: loaded data, player profile, stars, Grudge state and the
## seeded RNG streams (BLUEPRINT §2H; D7, D11, D13, D25).

const HEROES: Array[String] = ["BRUTE", "ROGUE", "MAGI"]
const DATA_DIR := "res://data/"

var heroes_data: Dictionary = {}
var weapons_data: Dictionary = {}
var stages_data: Dictionary = {}
var forge: WeaponForge

var inventory: Inventory
var active_hero: String = ""
var stars: Dictionary = {}                # stage_id -> { hero -> true }  (D7)
var clears: Dictionary = {}               # stage_id -> { hero -> int }
var last_clearing_hero: Dictionary = {}   # stage_id -> hero  (Grudge, D11)
var forge_unlocked: bool = false          # D13: unlocked by the first boss kill

# Seeded per run (D25). Separate streams keep loot rolls independent of combat rolls.
var run_seed: int = 0
var rng_combat := RandomNumberGenerator.new()
var rng_loot := RandomNumberGenerator.new()
var rng_boons := RandomNumberGenerator.new()


func _ready() -> void:
	var err := load_data()
	if err != "":
		push_error("GameState: data load failed (D22):\n" + err)
		get_tree().quit(1)
		return
	reset_profile()
	SaveManager.load_profile()


## Loads and validates every data file. Returns "" or the first file's errors.
func load_data() -> String:
	var files := {
		"heroes.json": DataSchema.validate_heroes,
		"weapons.json": DataSchema.validate_weapons,
		"stages.json": DataSchema.validate_stages,
	}
	var loaded := {}
	for name in files:
		var r := DataLoader.load_file(DATA_DIR + name, files[name])
		if not r["ok"]:
			return r["error"]
		loaded[name] = r["data"]
	heroes_data = loaded["heroes.json"]
	weapons_data = loaded["weapons.json"]
	stages_data = loaded["stages.json"]
	forge = WeaponForge.new(weapons_data)
	return ""


## Fresh profile: one level-1 base main per weapon class (D18), nothing earned.
func reset_profile() -> void:
	inventory = Inventory.new()
	for cls in forge.class_order():
		inventory.set_main(inventory.add_weapon(forge.create_weapon(cls)))
	active_hero = ""
	stars = {}
	clears = {}
	last_clearing_hero = {}
	forge_unlocked = false


func stage_cfg(stage_id: String) -> Dictionary:
	return stages_data["stages"][stage_id]


func loot_table(stage_id: String) -> LootTable:
	return LootTable.new(stage_cfg(stage_id), weapons_data)


# --- Runs (D25) --------------------------------------------------------------

func begin_run(hero: String, seed_value: int) -> void:
	assert(hero in HEROES, "unknown hero '%s'" % hero)
	active_hero = hero
	run_seed = seed_value
	rng_combat.seed = seed_value
	rng_loot.seed = seed_value + 1_000_003
	rng_boons.seed = seed_value + 2_000_006


## Turns a LootTable descriptor into an inventory weapon.
func grant_drop(drop: Dictionary) -> Weapon:
	var w := forge.create_weapon(drop["weapon_class"], int(drop["rarity"]), int(drop["level"]))
	return inventory.add_weapon(w)


# --- Grudge, stars, progress (D7, D11, D13) -----------------------------------

## The hero whose clear installed the stage boss's adaptation; "" before any clear.
func get_last_clearing_hero(stage_id: String) -> String:
	return last_clearing_hero.get(stage_id, "")


## The single active adaptation (§2H), or {} before the first clear.
func active_adaptation(stage_id: String) -> Dictionary:
	var hero := get_last_clearing_hero(stage_id)
	if hero == "":
		return {}
	return stage_cfg(stage_id)["grudge"][hero]


## Records a stage victory: replaces the adaptation (never stacks), awards the
## hero's star only when its condition was met, and unlocks the Forge.
func record_victory(stage_id: String, hero: String, star_condition_met: bool) -> void:
	assert(hero in HEROES, "unknown hero '%s'" % hero)
	if not clears.has(stage_id):
		clears[stage_id] = {}
	clears[stage_id][hero] = int(clears[stage_id].get(hero, 0)) + 1
	last_clearing_hero[stage_id] = hero
	if star_condition_met:
		if not stars.has(stage_id):
			stars[stage_id] = {}
		stars[stage_id][hero] = true
	forge_unlocked = true


func has_star(stage_id: String, hero: String) -> bool:
	return stars.get(stage_id, {}).get(hero, false)


func star_count(stage_id: String) -> int:
	return stars.get(stage_id, {}).size()


func clear_count(stage_id: String, hero: String) -> int:
	return int(clears.get(stage_id, {}).get(hero, 0))


## Base HP plus +HP sub-stat stacks on every equipped main of that hero (D16).
func hero_max_hp(hero: String) -> int:
	var hp := int(heroes_data["heroes"][hero]["hp"])
	for w in inventory.mains_of(hero):
		hp += forge.hp_bonus(w)
	return hp


# --- Persistence (D15, D23) ----------------------------------------------------

func to_save_dict() -> Dictionary:
	return {
		"profile": {
			"stars": stars.duplicate(true),
			"clears": clears.duplicate(true),
			"last_clearing_hero": last_clearing_hero.duplicate(),
			"forge_unlocked": forge_unlocked,
		},
		"inventory": inventory.to_dict(),
	}


## Returns "" on success, else a precise field error (state is left unchanged).
func apply_save_dict(d: Dictionary) -> String:
	for key in ["profile", "inventory"]:
		if typeof(d.get(key)) != TYPE_DICTIONARY:
			return "%s: missing or not an object" % key
	var p: Dictionary = d["profile"]
	for key in ["stars", "clears", "last_clearing_hero"]:
		if typeof(p.get(key)) != TYPE_DICTIONARY:
			return "profile.%s: missing or not an object" % key
	if typeof(p.get("forge_unlocked")) != TYPE_BOOL:
		return "profile.forge_unlocked: missing or not a bool"
	var inv := Inventory.new()
	var err := inv.load_dict(d["inventory"])
	if err != "":
		return err
	for uid in inv.weapons:
		var w: Weapon = inv.weapons[uid]
		if w.weapon_class not in forge.class_order():
			return "inventory.weapons.%s.weapon_class: unknown class '%s'" % [uid, w.weapon_class]
	for cls in forge.class_order():
		if inv.main_for(forge.class_cfg(cls)["owner_hero"], cls) == null:
			return "inventory.mains: no equipped main for %s" % cls
	inventory = inv
	stars = p["stars"].duplicate(true)
	clears = {}
	for stage_id in p["clears"]:
		clears[stage_id] = {}
		for hero in p["clears"][stage_id]:
			clears[stage_id][hero] = int(p["clears"][stage_id][hero])
	last_clearing_hero = p["last_clearing_hero"].duplicate()
	forge_unlocked = p["forge_unlocked"]
	return ""
