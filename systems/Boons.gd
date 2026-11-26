class_name Boons
extends RefCounted
## Run boons (§2F, D14): the 1-of-3 draft before Room 3 and each boon's effect
## on the hero. Effects live on the HeroController of the current run only.


## `count` distinct pool entries, shuffled with the run's boon RNG stream (D25).
static func draft(rng: RandomNumberGenerator, pool: Array, count: int) -> Array:
	var idx: Array[int] = []
	for i in pool.size():
		idx.append(i)
	for i in range(idx.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	var out: Array = []
	for i in mini(count, idx.size()):
		out.append(pool[idx[i]])
	return out


static func apply(hero: HeroController, boon: Dictionary) -> void:
	var v := float(boon["value"])
	match str(boon["effect"]):
		"damage_mult":
			hero.damage_mult *= 1.0 + v
		"max_hp_and_heal":
			hero.max_hp += int(v)
			hero.heal(int(v))
		"move_and_attack_speed":
			hero.move_speed *= 1.0 + v
			hero.attack_speed_mult *= 1.0 + v
		"projectile_damage_taken_mult":
			hero.projectile_taken_mult *= 1.0 - v
		"once_heal_below":
			hero.second_wind = {"threshold": float(boon["threshold"]), "heal": v}
		"cooldown_mult":
			hero.skills.cooldown_mult *= 1.0 - v
		_:
			push_error("Boons.apply: unknown effect '%s'" % boon["effect"])
			return
	hero.boons.append(str(boon["id"]))
