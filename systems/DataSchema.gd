class_name DataSchema
extends RefCounted
## Field validators for data/heroes.json, weapons.json and stages.json (D22).
## Each validator returns an Array of "field.path: problem" strings; empty = valid.

const HEROES: Array[String] = ["BRUTE", "ROGUE", "MAGI"]
const LOCK_STATES: Array[String] = ["CASTING_SKILL", "DASHING", "INSTANT"]


## Collects errors while walking a parsed JSON tree.
class Checker:
	var errors: Array[String] = []

	func _at(path: String, key) -> String:
		var k := "[%d]" % key if typeof(key) == TYPE_INT else str(key)
		if path == "":
			return k
		return path + k if k.begins_with("[") else "%s.%s" % [path, k]

	func _fetch(container, key, path: String):
		var p := _at(path, key)
		if typeof(container) == TYPE_DICTIONARY:
			if not container.has(key):
				errors.append("%s: missing" % p)
				return null
			return container[key]
		if typeof(container) == TYPE_ARRAY and typeof(key) == TYPE_INT and key < container.size():
			return container[key]
		errors.append("%s: missing" % p)
		return null

	func obj(container, key, path: String) -> Dictionary:
		var v = _fetch(container, key, path)
		if v == null:
			return {}
		if typeof(v) != TYPE_DICTIONARY:
			errors.append("%s: expected object, got %s" % [_at(path, key), type_string(typeof(v))])
			return {}
		return v

	func arr(container, key, path: String, min_size: int = 0) -> Array:
		var v = _fetch(container, key, path)
		if v == null:
			return []
		if typeof(v) != TYPE_ARRAY:
			errors.append("%s: expected array, got %s" % [_at(path, key), type_string(typeof(v))])
			return []
		if v.size() < min_size:
			errors.append("%s: expected at least %d entries, got %d" % [_at(path, key), min_size, v.size()])
		return v

	func num(container, key, path: String, min_v: float = -INF, max_v: float = INF) -> float:
		var v = _fetch(container, key, path)
		if v == null:
			return 0.0
		if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("%s: expected number, got %s" % [_at(path, key), type_string(typeof(v))])
			return 0.0
		if float(v) < min_v or float(v) > max_v:
			errors.append("%s: %s is outside [%s, %s]" % [_at(path, key), str(v), str(min_v), str(max_v)])
		return float(v)

	func text(container, key, path: String, allowed: Array = []) -> String:
		var v = _fetch(container, key, path)
		if v == null:
			return ""
		if typeof(v) != TYPE_STRING:
			errors.append("%s: expected string, got %s" % [_at(path, key), type_string(typeof(v))])
			return ""
		if not allowed.is_empty() and v not in allowed:
			errors.append("%s: '%s' is not one of %s" % [_at(path, key), v, str(allowed)])
		return v

	func numbers(container, key, path: String) -> void:
		var d := obj(container, key, path)
		for k in d:
			num(d, k, _at(path, key))


static func validate_heroes(data: Dictionary) -> Array[String]:
	var c := Checker.new()
	var combat := c.obj(data, "combat", "")
	for k in ["hit_invulnerability", "skill_input_buffer", "stop_velocity", "attack_grace", "input_deadzone"]:
		c.num(combat, k, "combat", 0.0)
	var heroes := c.obj(data, "heroes", "")
	for hero in HEROES:
		var p := "heroes.%s" % hero
		var h := c.obj(heroes, hero, "heroes")
		if h.is_empty():
			continue
		c.num(h, "hp", p, 1.0)
		c.num(h, "move_speed", p, 0.1)
		var classes := c.arr(h, "weapon_classes", p, 1)
		for i in classes.size():
			c.text(classes, i, p + ".weapon_classes")
		var primary := c.arr(h, "primary", p, 1)
		for i in primary.size():
			var ap := "%s.primary[%d]" % [p, i]
			var a := c.obj(primary, i, p + ".primary")
			c.text(a, "id", ap)
			c.text(a, "weapon_class", ap, classes)
			c.num(a, "damage_l1", ap, 0.0)
			c.num(a, "hits", ap, 1.0)
			c.num(a, "cadence", ap, 0.01)
			c.num(a, "reach", ap, 0.1)
			c.numbers(a, "params", ap)
		var skills := c.arr(h, "skills", p, 3)
		for i in skills.size():
			var sp := "%s.skills[%d]" % [p, i]
			var s := c.obj(skills, i, p + ".skills")
			c.text(s, "id", sp)
			c.num(s, "cooldown", sp, 0.1)
			c.num(s, "lock", sp, 0.0)
			c.text(s, "lock_state", sp, LOCK_STATES)
			if typeof(s.get("recorded")) != TYPE_BOOL:
				c.errors.append("%s.recorded: expected bool" % sp)
			var dmg := c.arr(s, "damage", sp)
			for j in dmg.size():
				var dp := "%s.damage[%d]" % [sp, j]
				var d := c.obj(dmg, j, sp + ".damage")
				c.text(d, "weapon_class", dp, classes)
				c.num(d, "damage_l1", dp, 0.0)
				c.num(d, "hits", dp, 1.0)
				c.text(d, "mode", dp)
			c.numbers(s, "params", sp)
		var passive := c.obj(h, "passive", p)
		c.text(passive, "id", p + ".passive")
		c.numbers(passive, "params", p + ".passive")
	return c.errors


static func validate_weapons(data: Dictionary) -> Array[String]:
	var c := Checker.new()
	var order := c.arr(data, "class_order", "", 1)
	var classes := c.obj(data, "classes", "")
	for cls in order:
		var p := "classes.%s" % cls
		var cc := c.obj(classes, cls, "classes")
		if cc.is_empty():
			continue
		c.text(cc, "owner_hero", p, HEROES)
		c.num(cc, "base_atk", p, 0.01)
		c.text(cc, "shard_id", p)
	for cls in classes:
		if cls not in order:
			c.errors.append("classes.%s: not listed in class_order" % cls)
	var g := c.obj(data, "growth", "")
	for k in ["atk_per_level", "atk_per_stage", "crit_multiplier"]:
		c.num(g, k, "growth", 1.0)
	for k in ["atk_per_stack", "crit_base", "crit_per_stack"]:
		c.num(g, k, "growth", 0.0, 1.0)
	c.num(g, "hp_per_stack", "growth", 0.0)
	c.num(g, "substat_cap", "growth", 1.0)
	var subs := c.arr(g, "substat_order", "growth", 1)
	for i in subs.size():
		c.text(subs, i, "growth.substat_order", ["ATK", "CRIT", "HP"])
	var x := c.obj(data, "xp", "")
	c.num(x, "base", "xp", 1.0)
	c.num(x, "growth", "xp", 1.0)
	c.num(x, "level_cap", "xp", 2.0)
	c.num(x, "per_fodder_level", "xp", 0.0)
	var bx := c.arr(x, "base_xp_by_rarity", "xp", 3)
	for i in bx.size():
		c.num(bx, i, "xp.base_xp_by_rarity", 0.0)
	c.num(c.obj(data, "salvage", ""), "base_shards", "salvage", 0.0)
	var evo := c.obj(data, "evolutions", "")
	for cls in order:
		var line := c.arr(evo, cls, "evolutions", 3)
		for i in line.size():
			var ep := "evolutions.%s[%d]" % [cls, i]
			var e := c.obj(line, i, "evolutions.%s" % cls)
			if c.num(e, "stage", ep, 1.0) != i + 1:
				c.errors.append("%s.stage: expected %d" % [ep, i + 1])
			c.text(e, "weapon_id", ep)
			c.text(e, "name", ep)
			if i > 0:
				c.num(e, "req_level", ep, 1.0, c.num(x, "level_cap", "xp"))
				c.num(e, "shard_cost", ep, 0.0)
				c.text(e, "boss_essence_id", ep)
	return c.errors


static func validate_stages(data: Dictionary) -> Array[String]:
	var c := Checker.new()
	var enemies := c.obj(data, "enemies", "")
	for e in enemies:
		c.numbers(enemies, e, "enemies")
		c.num(enemies[e], "hp", "enemies.%s" % e, 1.0)
	c.numbers(data, "wave_rules", "")
	var boons := c.arr(data, "boons", "", 3)
	for i in boons.size():
		var b := c.obj(boons, i, "boons")
		c.text(b, "id", "boons[%d]" % i)
		c.text(b, "effect", "boons[%d]" % i)
		c.num(b, "value", "boons[%d]" % i, 0.0)
	var stages := c.obj(data, "stages", "")
	for sid in stages:
		var p := "stages.%s" % sid
		var s := c.obj(stages, sid, "stages")
		c.text(s, "name", p)
		c.num(s, "room_clear_heal", p, 0.0, 1.0)
		var rooms := c.arr(s, "rooms", p, 1)
		c.num(s, "boon_draft_before_room", p, 0.0, rooms.size() - 1)
		c.num(s, "boon_offer_count", p, 1.0, boons.size())
		for r in rooms.size():
			var rp := "%s.rooms[%d]" % [p, r]
			var room := c.obj(rooms, r, p + ".rooms")
			var waves := c.arr(room, "waves", rp, 1)
			for w in waves.size():
				var wave = waves[w]
				if typeof(wave) != TYPE_ARRAY or wave.is_empty():
					c.errors.append("%s.waves[%d]: expected non-empty array" % [rp, w])
					continue
				for k in wave.size():
					var gp := "%s.waves[%d][%d]" % [rp, w, k]
					c.text(wave[k], "enemy", gp, enemies.keys())
					c.num(wave[k], "count", gp, 1.0)
			c.arr(room, "traps", rp)
		var boss := c.obj(s, "boss", p)
		c.num(boss, "hp", p + ".boss", 1.0)
		c.text(boss, "essence_id", p + ".boss")
		c.arr(boss, "phases", p + ".boss", 1)
		c.obj(boss, "attacks", p + ".boss")
		var drops := c.obj(s, "drops", p)
		var dp := p + ".drops"
		c.num(drops, "room_drop_chance", dp, 0.0, 1.0)
		c.num(drops, "hero_class_weight", dp, 0.0)
		c.num(drops, "other_class_weight", dp, 0.0)
		c.num(drops, "grudge_bias", dp, 0.0)
		c.num(drops, "room_drop_level", dp, 1.0)
		c.num(drops, "boss_drop_level", dp, 1.0)
		var rw := c.arr(drops, "rarity_weights", dp, 3)
		for i in rw.size():
			c.num(rw, i, dp + ".rarity_weights", 0.0)
		var stars := c.obj(s, "stars", p)
		var grudge := c.obj(s, "grudge", p)
		for hero in HEROES:
			var st := c.obj(stars, hero, p + ".stars")
			c.text(st, "id", "%s.stars.%s" % [p, hero])
			c.text(st, "metric", "%s.stars.%s" % [p, hero])
			c.num(st, "threshold", "%s.stars.%s" % [p, hero], 0.0)
			var gr := c.obj(grudge, hero, p + ".grudge")
			c.text(gr, "id", "%s.grudge.%s" % [p, hero])
			c.text(gr, "tip", "%s.grudge.%s" % [p, hero])
			c.numbers(gr, "params", "%s.grudge.%s" % [p, hero])
	return c.errors
