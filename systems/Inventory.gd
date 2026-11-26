class_name Inventory
extends RefCounted
## Weapons, equipped mains, shards and essences (D18, D20). Uncapped in the slice.

var weapons: Dictionary = {}    # uid -> Weapon
var mains: Dictionary = {}      # hero -> { weapon_class -> uid }
var shards: Dictionary = {}     # shard_id -> int
var essences: Dictionary = {}   # essence_id -> int
var next_uid: int = 1


## Assigns a uid when the weapon has none, then stores it.
func add_weapon(w: Weapon) -> Weapon:
	if w.uid == "":
		w.uid = "w%06d" % next_uid
		next_uid += 1
	weapons[w.uid] = w
	return w


func get_weapon(uid: String) -> Weapon:
	return weapons.get(uid)


## Strictly one main per weapon class per hero (D18).
func set_main(w: Weapon) -> void:
	if not weapons.has(w.uid):
		add_weapon(w)
	if not mains.has(w.owner_hero):
		mains[w.owner_hero] = {}
	mains[w.owner_hero][w.weapon_class] = w.uid


func main_for(hero: String, weapon_class: String) -> Weapon:
	var by_class: Dictionary = mains.get(hero, {})
	return get_weapon(by_class.get(weapon_class, ""))


func mains_of(hero: String) -> Array[Weapon]:
	var out: Array[Weapon] = []
	for uid in mains.get(hero, {}).values():
		out.append(get_weapon(uid))
	return out


func is_main(uid: String) -> bool:
	for by_class in mains.values():
		if uid in by_class.values():
			return true
	return false


## Every stored weapon that is not an equipped main.
func fodder() -> Array[Weapon]:
	var out: Array[Weapon] = []
	for uid in weapons:
		if not is_main(uid):
			out.append(weapons[uid])
	return out


## Refuses to remove an equipped main.
func remove_weapon(uid: String) -> bool:
	if is_main(uid) or not weapons.has(uid):
		return false
	weapons.erase(uid)
	return true


func shard_count(shard_id: String) -> int:
	return shards.get(shard_id, 0)


func add_shards(shard_id: String, amount: int) -> void:
	shards[shard_id] = shard_count(shard_id) + amount


func essence_count(essence_id: String) -> int:
	return essences.get(essence_id, 0)


func add_essence(essence_id: String, amount: int) -> void:
	essences[essence_id] = essence_count(essence_id) + amount


func to_dict() -> Dictionary:
	var list := []
	for uid in weapons:
		list.append(weapons[uid].to_dict())
	return {
		"weapons": list,
		"mains": mains.duplicate(true),
		"shards": shards.duplicate(),
		"essences": essences.duplicate(),
		"next_uid": next_uid,
	}


## Returns "" on success, else a precise field error (the inventory is left unchanged).
func load_dict(d: Dictionary) -> String:
	for key in ["weapons", "mains", "shards", "essences", "next_uid"]:
		if not d.has(key):
			return "inventory.%s: missing" % key
	if typeof(d["weapons"]) != TYPE_ARRAY:
		return "inventory.weapons: expected array"
	var loaded := {}
	for i in d["weapons"].size():
		var wd = d["weapons"][i]
		if typeof(wd) != TYPE_DICTIONARY:
			return "inventory.weapons[%d]: expected object" % i
		var err := Weapon.validate_dict(wd)
		if err != "":
			return "inventory.weapons[%d].%s" % [i, err]
		var w := Weapon.from_dict(wd)
		loaded[w.uid] = w
	var new_mains := {}
	for hero in d["mains"]:
		new_mains[hero] = {}
		for cls in d["mains"][hero]:
			var uid := str(d["mains"][hero][cls])
			if not loaded.has(uid):
				return "inventory.mains.%s.%s: unknown weapon uid '%s'" % [hero, cls, uid]
			new_mains[hero][cls] = uid
	weapons = loaded
	mains = new_mains
	shards = _int_map(d["shards"])
	essences = _int_map(d["essences"])
	next_uid = int(d["next_uid"])
	return ""


static func _int_map(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[str(k)] = int(src[k])
	return out
