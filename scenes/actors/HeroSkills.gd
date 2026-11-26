class_name HeroSkills
extends Node
## The hero's 3 manual skills (§2D) with D27 tap-to-cast auto-aim, cast locks,
## the 0.15 s input buffer and cooldowns. Also ticks the hero's statuses, so
## HeroController._physics_process can stay §2A-verbatim.
##
## A cast that finds no valid target (only Shatter Mark needs one) does nothing
## and keeps its cooldown ready (Q-9).

const MARK_RANGE := 10.5        # Shatter Mark targets within bow reach (Q-9)
const VORTEX_PULL := 1.5        # m, "slight pull" toward the Brute
const NOVA_KNOCKBACK := 3.0     # m
const WELL_PULL_SPEED := 2.0    # m/s toward the well's center
const BARRAGE_STAGGER := 0.06   # s between Barrage arrows
const FAN_ARC := 120.0          # degrees, dagger-mode Barrage slices

var hero: HeroController
var defs: Array = []
var cooldowns: Array[float] = [0.0, 0.0, 0.0]
var cooldown_mult: float = 1.0  # Fracture Focus hooks in here (Phase 3)

var _buffered: int = -1
var _buffer_left: float = 0.0
var _pending: Array[Dictionary] = []   # { "t": seconds left, "fn": Callable }


func setup(owner_hero: HeroController) -> void:
	hero = owner_hero
	defs = hero.cfg["skills"]
	cooldowns = [0.0, 0.0, 0.0]
	_buffered = -1
	_pending.clear()


func skill_id(i: int) -> String:
	return defs[i]["id"]


func index_of(id: String) -> int:
	for i in defs.size():
		if defs[i]["id"] == id:
			return i
	return -1


func cooldown_of(i: int) -> float:
	return float(defs[i]["cooldown"]) * cooldown_mult


## 1.0 right after a cast, 0.0 when ready (drives the radial rings).
func cooldown_fraction(i: int) -> float:
	return clampf(cooldowns[i] / cooldown_of(i), 0.0, 1.0)


func is_ready(i: int) -> bool:
	return cooldowns[i] <= 0.0


## A tap on skill button `i`. Returns true when the skill cast right now.
func request(i: int) -> bool:
	if i < 0 or i >= defs.size() or not is_ready(i) or hero.hp <= 0:
		return false
	if hero.is_locked():
		_buffered = i
		_buffer_left = float(GameState.heroes_data["combat"]["skill_input_buffer"])
		return false
	return _cast(i)


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	for i in cooldowns.size():
		cooldowns[i] = maxf(0.0, cooldowns[i] - delta)
	for p in _pending.duplicate():
		p["t"] -= delta
		if p["t"] <= 1e-6:
			_pending.erase(p)
			p["fn"].call()
	if _buffered >= 0:
		if not hero.is_locked():
			var i := _buffered
			_buffered = -1
			if is_ready(i):
				_cast(i)
		else:
			_buffer_left -= delta
			if _buffer_left <= 0.0:
				_buffered = -1
	hero.tick_status(delta)


func _after(seconds: float, fn: Callable) -> void:
	if seconds <= 0.0:
		fn.call()
	else:
		_pending.append({"t": seconds, "fn": fn})


func _cast(i: int) -> bool:
	var d: Dictionary = defs[i]
	var ok: bool = call("_cast_" + str(d["id"]).to_lower(), d)
	if ok:
		cooldowns[i] = cooldown_of(i)
		hero.skill_cast.emit(d["id"])
	return ok


func _lock(d: Dictionary, lock_velocity: Vector3 = Vector3.ZERO) -> void:
	match str(d["lock_state"]):
		"CASTING_SKILL":
			hero.begin_lock(HeroController.CombatState.CASTING_SKILL, float(d["lock"]), lock_velocity)
		"DASHING":
			hero.begin_lock(HeroController.CombatState.DASHING, float(d["lock"]), lock_velocity)


func _damage(d: Dictionary, mode: String = "") -> Dictionary:
	for e in d["damage"]:
		if str(e["mode"]) == mode or (mode == "" and str(e["mode"]) in ["", "PER_SECOND"]):
			return e
	return {}


func _tree() -> SceneTree:
	return hero.get_tree()


# --- Brute ------------------------------------------------------------------------

## Leaps onto the nearest enemy within 5 m, else 5 m along stick/facing, and
## slams on landing.
func _cast_leap_slam(d: Dictionary) -> bool:
	var p: Dictionary = d["params"]
	var leap := float(p["leap"])
	var target := Combat.nearest_enemy(_tree(), hero.global_position, leap)
	var land: Vector3
	if target != null:
		land = Combat.flat(target.global_position)
	else:
		land = Combat.flat(hero.global_position) + hero.aim_dir() * leap
	land.y = hero.global_position.y
	hero.face(land)
	var lock := float(d["lock"])
	_lock(d, Combat.flat(land - hero.global_position) / lock)
	var dmg := _damage(d)
	_after(lock, func() -> void:
		var at := hero.global_position
		hero.spawn_hitbox("LEAP_SLAM", at, float(p["radius"]))
		for e in Combat.in_radius(_tree(), at, float(p["radius"])):
			hero.deal(e, dmg["weapon_class"], float(dmg["damage_l1"]), "LEAP_SLAM")
			e.apply_status("STUN", {"duration": float(p["stun"])}))
	return true


func _cast_rending_roar(d: Dictionary) -> bool:
	var p: Dictionary = d["params"]
	var at := hero.global_position
	hero.spawn_hitbox("RENDING_ROAR", at, float(p["radius"]))
	for e in Combat.in_radius(_tree(), at, float(p["radius"])):
		e.apply_status("WEAKEN", {"duration": float(p["duration"]), "damage_mult": float(p["enemy_damage_mult"])})
	for s in int(p["guard_stacks"]):
		hero.add_guard_stack()
	_lock(d)
	return true


func _cast_vortex_cleave(d: Dictionary) -> bool:
	var p: Dictionary = d["params"]
	var at := hero.global_position
	var dmg := _damage(d)
	hero.spawn_hitbox("VORTEX_CLEAVE", at, float(p["radius"]))
	for e in Combat.in_radius(_tree(), at, float(p["radius"])):
		hero.deal(e, dmg["weapon_class"], float(dmg["damage_l1"]), "VORTEX_CLEAVE")
		var to_hero := Combat.flat(at - e.global_position)
		var pull := minf(VORTEX_PULL, maxf(0.0, to_hero.length() - 1.0))
		if pull > 0.0:
			e.displace(to_hero.normalized() * pull)
	_lock(d)
	return true


# --- Rogue ------------------------------------------------------------------------

func _cast_shadow_vault(d: Dictionary) -> bool:
	var p: Dictionary = d["params"]
	var dir := hero.escape_dir()
	_lock(d, dir * float(p["dash"]) / float(d["lock"]))
	hero.invuln_timer = maxf(hero.invuln_timer, float(p["invulnerability"]))
	hero.next_dagger_bonus = float(p["next_dagger_bonus"])
	return true


## Bow mode: 5 homing arrows. Dagger mode: 4 slices in a frontal fan.
func _cast_adaptive_barrage(d: Dictionary) -> bool:
	var daggers := hero.rogue_mode == HeroController.RogueMode.DAGGERS
	var reach := HeroController.DAGGER_EXIT if daggers else HeroController.BOW_RANGE
	var target := Combat.nearest_enemy(_tree(), hero.global_position, reach)
	if target != null:
		hero.face(target.global_position)
	var dir := hero.forward()
	if daggers:
		var dmg := _damage(d, "DAGGERS")
		hero.spawn_hitbox("ADAPTIVE_BARRAGE_DAGGERS", hero.global_position + dir * reach * 0.5, reach)
		var hits := Combat.in_arc(_tree(), hero.global_position, dir, reach, FAN_ARC)
		for i in int(dmg["hits"]):
			for e in hits:
				hero.deal(e, "DAGGERS", float(dmg["damage_l1"]), "ADAPTIVE_BARRAGE", {"mode": "DAGGERS"})
	else:
		var dmg := _damage(d, "BOW")
		for i in int(dmg["hits"]):
			var spread := deg_to_rad((i - (int(dmg["hits"]) - 1) * 0.5) * 8.0)
			var arrow_dir := dir.rotated(Vector3.UP, spread)
			_after(i * BARRAGE_STAGGER, func() -> void:
				hero.spawn_projectile("ADAPTIVE_BARRAGE_ARROW", hero.global_position + Vector3(0, 1.2, 0), arrow_dir,
					HeroController.ARROW_SPEED, reach + HeroController.ARROW_OVERSHOOT, target,
					func(e: Node3D) -> void: hero.deal(e, "SHORTBOW", float(dmg["damage_l1"]), "ADAPTIVE_BARRAGE", {"mode": "BOW"})))
	_lock(d)
	return true


func _cast_shatter_mark(d: Dictionary) -> bool:
	var p: Dictionary = d["params"]
	var target := Combat.nearest_enemy(_tree(), hero.global_position, MARK_RANGE)
	if target == null:
		return false
	hero.face(target.global_position)
	hero.spawn_hitbox("SHATTER_MARK", target.global_position, 0.6)
	target.apply_status("MARK", {
		"duration": float(p["duration"]),
		"damage_taken_mult": float(p["damage_taken_mult"]),
		"kill_heal": int(p["kill_heal"]),
		"hero": hero.hero_id,
	})
	_lock(d)
	return true


# --- Magi -------------------------------------------------------------------------

func _cast_phase_blink(d: Dictionary) -> bool:
	hero.teleport(hero.escape_dir() * float(d["params"]["distance"]))
	hero.refresh_barrier()
	return true


## Centered on the nearest enemy within 8 m, else 3 m ahead. Pulls and ticks
## 6 damage per second for 4 s.
func _cast_gravity_well(d: Dictionary) -> bool:
	var p: Dictionary = d["params"]
	var target := Combat.nearest_enemy(_tree(), hero.global_position, float(p["cast_range"]))
	var center: Vector3
	if target != null:
		center = Combat.flat(target.global_position)
	else:
		center = Combat.flat(hero.global_position + hero.aim_dir() * 3.0)
	hero.face(center)
	var radius := float(p["radius"])
	var dmg := _damage(d)
	var zone := hero.spawn_hitbox("GRAVITY_WELL", center, radius)
	zone.duration = float(p["duration"])
	zone.tick_interval = 1.0
	zone.on_tick = func() -> void:
		for e in Combat.in_radius(_tree(), zone.global_position, radius):
			hero.deal(e, dmg["weapon_class"], float(dmg["damage_l1"]), "GRAVITY_WELL")
	zone.on_physics = func(delta: float) -> void:
		for e in Combat.in_radius(_tree(), zone.global_position, radius):
			var to_center := Combat.flat(zone.global_position - e.global_position)
			if to_center.length() > 0.05:
				e.displace(to_center.normalized() * minf(WELL_PULL_SPEED * delta, to_center.length()))
	_lock(d)
	return true


func _cast_shatter_nova(d: Dictionary) -> bool:
	var p: Dictionary = d["params"]
	var at := hero.global_position
	var dmg := _damage(d)
	hero.spawn_hitbox("SHATTER_NOVA", at, float(p["radius"]))
	for e in Combat.in_radius(_tree(), at, float(p["radius"])):
		hero.deal(e, dmg["weapon_class"], float(dmg["damage_l1"]), "SHATTER_NOVA")
		var away := Combat.flat(e.global_position - at)
		e.displace((away.normalized() if away.length() > 0.001 else hero.forward()) * NOVA_KNOCKBACK)
	_lock(d)
	return true
