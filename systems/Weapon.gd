class_name Weapon
extends RefCounted
## One weapon instance: the BLUEPRINT §2C data model (D16, D17, D26).
## `xp_to_next` is derived by WeaponForge, never stored.

const FIELDS: Array[String] = [
	"uid", "weapon_id", "weapon_class", "owner_hero", "rarity", "evo_stage",
	"level", "xp", "atk_stacks", "crit_stacks", "hp_stacks", "next_substat",
]

var uid: String = ""
var weapon_id: String = ""
var weapon_class: String = ""
var owner_hero: String = ""
var rarity: int = 1
var evo_stage: int = 1
var level: int = 1
var xp: int = 0
var atk_stacks: int = 0
var crit_stacks: int = 0
var hp_stacks: int = 0
var next_substat: int = 0


func stacks_of(substat: String) -> int:
	match substat:
		"ATK":
			return atk_stacks
		"CRIT":
			return crit_stacks
		"HP":
			return hp_stacks
	push_error("Weapon.stacks_of: unknown sub-stat '%s'" % substat)
	return 0


func add_stack(substat: String) -> void:
	match substat:
		"ATK":
			atk_stacks += 1
		"CRIT":
			crit_stacks += 1
		"HP":
			hp_stacks += 1
		_:
			push_error("Weapon.add_stack: unknown sub-stat '%s'" % substat)


func to_dict() -> Dictionary:
	var d := {}
	for f in FIELDS:
		d[f] = get(f)
	return d


## Returns "" when `d` can be loaded, else a precise field error.
static func validate_dict(d: Dictionary) -> String:
	for f in FIELDS:
		if not d.has(f):
			return "%s: missing" % f
	for f in ["uid", "weapon_id", "weapon_class", "owner_hero"]:
		if typeof(d[f]) != TYPE_STRING or str(d[f]) == "":
			return "%s: expected non-empty string" % f
	for f in FIELDS.slice(4):
		if typeof(d[f]) not in [TYPE_INT, TYPE_FLOAT]:
			return "%s: expected number" % f
	return ""


## JSON numbers parse as floats, so every integer field is cast back here.
static func from_dict(d: Dictionary) -> Weapon:
	var w := Weapon.new()
	w.uid = str(d["uid"])
	w.weapon_id = str(d["weapon_id"])
	w.weapon_class = str(d["weapon_class"])
	w.owner_hero = str(d["owner_hero"])
	w.rarity = int(d["rarity"])
	w.evo_stage = int(d["evo_stage"])
	w.level = int(d["level"])
	w.xp = int(d["xp"])
	w.atk_stacks = int(d["atk_stacks"])
	w.crit_stacks = int(d["crit_stacks"])
	w.hp_stacks = int(d["hp_stacks"])
	w.next_substat = int(d["next_substat"])
	return w
