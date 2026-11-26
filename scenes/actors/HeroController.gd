class_name HeroController
extends CharacterBody3D

enum HeroClass { BRUTE, ROGUE, MAGI }
enum CombatState { MOVING, STOPPED_ATTACKING, CASTING_SKILL, DASHING }
enum RogueMode { BOW, DAGGERS }

signal rogue_mode_changed(mode: RogueMode)   # drives the AD3 trim flash

@export var hero_class: HeroClass = HeroClass.BRUTE
@export var move_speed: float = 4.2          # m/s, tunable
@export var input_deadzone: float = 0.18

# Values mirror data/heroes.json; the JSON is authoritative at runtime.
const STOP_VELOCITY: float = 0.25            # m/s
const GRACE_TIME: float = 0.08               # s before auto-attack starts
const DAGGER_ENTER: float = 2.6              # Bow -> Daggers at <= 2.6 m (D28)
const DAGGER_EXIT: float = 3.0               # Daggers -> Bow at > 3.0 m (D28)
const BOW_RANGE: float = 10.5
const BRUTE_RANGE: float = 3.2
const MAGI_RANGE: float = 14.0

var state: CombatState = CombatState.MOVING
var input_vector: Vector2 = Vector2.ZERO
var attack_timer: float = 0.0
var stop_timer: float = 0.0
var lock_timer: float = 0.0                  # remaining CASTING_SKILL / DASHING time (D27)
var rogue_mode: RogueMode = RogueMode.BOW
var current_target: Node3D = null

func _physics_process(delta: float) -> void:
	if state == CombatState.CASTING_SKILL or state == CombatState.DASHING:
		lock_timer -= delta
		if lock_timer <= 0.0:
			state = CombatState.MOVING
			stop_timer = 0.0
			velocity = Vector3.ZERO          # a lock never leaves leftover leap/dash momentum
		move_and_slide()
		return

	if input_vector.length() > input_deadzone:
		stop_timer = 0.0
		state = CombatState.MOVING
		var dir := Vector3(input_vector.x, 0.0, input_vector.y).normalized()
		velocity = dir * move_speed
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 14.0 * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, 40.0 * delta)
		if velocity.length() <= STOP_VELOCITY:
			stop_timer += delta
			if stop_timer >= GRACE_TIME:
				state = CombatState.STOPPED_ATTACKING
				_process_auto_attack(delta)
		else:
			stop_timer = 0.0

	move_and_slide()

func begin_lock(lock_state: CombatState, duration: float, lock_velocity: Vector3) -> void:
	state = lock_state
	lock_timer = duration
	velocity = lock_velocity                 # Vector3.ZERO roots the hero

func _process_auto_attack(delta: float) -> void:
	current_target = _find_nearest_enemy()   # nearest living enemy in the current room
	if not is_instance_valid(current_target):
		return

	var to_target := current_target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if hero_class == HeroClass.ROGUE:
		_update_rogue_mode(dist)
	if dist > _max_range():
		return                               # out of reach: no swing (D28)

	rotation.y = lerp_angle(rotation.y, atan2(to_target.x, to_target.z), 18.0 * delta)
	attack_timer -= delta
	if attack_timer <= 0.0:
		_execute_primary_attack()

func _update_rogue_mode(dist: float) -> void:
	var next := rogue_mode
	if rogue_mode == RogueMode.BOW and dist <= DAGGER_ENTER:
		next = RogueMode.DAGGERS
	elif rogue_mode == RogueMode.DAGGERS and dist > DAGGER_EXIT:
		next = RogueMode.BOW
	if next != rogue_mode:
		rogue_mode = next
		rogue_mode_changed.emit(rogue_mode)

func _max_range() -> float:
	match hero_class:
		HeroClass.BRUTE:
			return BRUTE_RANGE
		HeroClass.ROGUE:
			return DAGGER_EXIT if rogue_mode == RogueMode.DAGGERS else BOW_RANGE
		_:
			return MAGI_RANGE

func _execute_primary_attack() -> void:
	match hero_class:
		HeroClass.BRUTE:
			attack_timer = 0.9
			_fire_cleave_arc()
		HeroClass.ROGUE:
			if rogue_mode == RogueMode.DAGGERS:
				attack_timer = 0.5
				_fire_dagger_flurry(current_target)
			else:
				attack_timer = 0.55
				_fire_bow_arrow(current_target)
		HeroClass.MAGI:
			attack_timer = 0.7
			_fire_prism_bolt(current_target)


# =============================================================================
# Everything above is BLUEPRINT §2A verbatim. Below: hero kit, damage intake and
# passives (§2D, D25, D27, D29), driven by data/heroes.json.
# =============================================================================

signal primary_attack_fired(attack_id: String, target: Node3D)
signal skill_cast(skill_id: String)
signal attack_spawned(node: Area3D)          # every Hitbox / Projectile the hero creates
signal damaged(hp_lost: int, absorbed_by: String)
signal died
signal guard_changed(fraction: float)
signal barrier_changed(up: bool)
signal hit_dealt(target: Node3D, hit: Dictionary)   # every hit this hero lands (stars, D9)
signal second_wind_triggered

const ARROW_SPEED := 30.0                    # m/s (Q-9)
const BOLT_SPEED := 16.0                     # m/s (Q-9)
const ARROW_OVERSHOOT := 1.5                 # projectiles fly a little past their reach

var hero_id: String = ""
var cfg: Dictionary = {}                     # data/heroes.json -> heroes.<id>
var weapons: Dictionary = {}                 # weapon_class -> Weapon (equipped mains, D18)
var max_hp: int = 1
var hp: int = 1
var guard: float = 0.0                       # Crimson Guard shield pool (HP)
var guard_decay: float = 0.0
var barrier_up: bool = false                 # Arcane Glass Barrier
var barrier_timer: float = 0.0
var invuln_timer: float = 0.0
var next_dagger_bonus: float = 0.0           # Shadow Vault: next dagger pair +50%

# Run-only boon state (§2F, D14). A new run spawns a new hero, so nothing carries over.
var boons: Array[String] = []
var damage_mult: float = 1.0                 # Crimson Surcharge
var attack_speed_mult: float = 1.0           # Tempest Heart
var projectile_taken_mult: float = 1.0       # Amber Ward
var second_wind: Dictionary = {}             # Second Wind: {threshold, heal}, cleared when used

@onready var skills: HeroSkills = $Skills
@onready var visuals: HeroVisuals = $Visuals


## Configures the hero from data and the player's equipped mains.
func setup(id: String) -> void:
	hero_id = id
	hero_class = HeroClass[id]
	cfg = GameState.heroes_data["heroes"][id]
	move_speed = float(cfg["move_speed"])
	input_deadzone = float(GameState.heroes_data["combat"]["input_deadzone"])
	weapons = {}
	for cls in cfg["weapon_classes"]:
		weapons[cls] = GameState.inventory.main_for(id, cls)
	max_hp = GameState.hero_max_hp(id)
	hp = max_hp
	guard = 0.0
	barrier_up = hero_class == HeroClass.MAGI
	rogue_mode = RogueMode.BOW
	state = CombatState.MOVING
	attack_timer = 0.0
	skills.setup(self)
	visuals.build(self)


func is_locked() -> bool:
	return state == CombatState.CASTING_SKILL or state == CombatState.DASHING


func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


func face(point: Vector3) -> void:
	var to := Combat.flat(point - global_position)
	if to.length() > 0.001:
		rotation.y = atan2(to.x, to.z)


func stick_dir() -> Vector3:
	if input_vector.length() > input_deadzone:
		return Vector3(input_vector.x, 0.0, input_vector.y).normalized()
	return Vector3.ZERO


## D27: stick direction when held, else facing.
func aim_dir() -> Vector3:
	var s := stick_dir()
	return s if s != Vector3.ZERO else forward()


## D27 (Shadow Vault, Phase Blink): stick direction, else directly away from the
## nearest enemy, else backwards.
func escape_dir() -> Vector3:
	var s := stick_dir()
	if s != Vector3.ZERO:
		return s
	var e := Combat.nearest_enemy(get_tree(), global_position)
	if e != null:
		var away := Combat.flat(global_position - e.global_position)
		if away.length() > 0.001:
			return away.normalized()
	return -forward()


func teleport(offset: Vector3) -> void:
	move_and_collide(Combat.flat(offset))


func primary(attack_id: String) -> Dictionary:
	for a in cfg["primary"]:
		if a["id"] == attack_id:
			return a
	return {}


# --- Damage dealing (D25) ------------------------------------------------------

## Rolls crit, applies Shatter Mark, deals one hit and handles the marked-kill heal.
func deal(target: Node3D, weapon_class: String, damage_l1: float, source: String, extra: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(target) or not target.is_alive():
		return {}
	var w: Weapon = weapons[weapon_class]
	var crit := GameState.rng_combat.randf() < GameState.forge.crit_chance(w)
	var mark_mult := 1.0
	var marked: bool = target.has_status("MARK")
	if marked:
		mark_mult = float(target.status_data("MARK").get("damage_taken_mult", 1.0))
	var hit := {
		"damage": GameState.forge.damage(w, damage_l1, damage_mult, mark_mult, crit),   # D25 boon_mult
		"crit": crit,
		"source": source,
		"hero": hero_id,
		"is_echo": false,
		"weapon_class": weapon_class,
	}
	hit["origin"] = global_position
	hit.merge(extra)
	var killed := Combat.apply_hit(target, hit)
	hit_dealt.emit(target, hit)
	if killed and marked:
		heal(int(target.status_data("MARK").get("kill_heal", 0)))
	return hit


func spawn_hitbox(kind_id: String, at: Vector3, area_radius: float) -> Hitbox:
	var hb := Hitbox.create(kind_id, at, area_radius, visuals.accent_color)
	get_parent().add_child(hb)
	hb.global_position = Vector3(at.x, global_position.y, at.z)
	attack_spawned.emit(hb)
	return hb


func spawn_projectile(kind_id: String, from: Vector3, dir: Vector3, speed: float, reach: float, homing: Node3D, on_hit: Callable) -> Projectile:
	var p := Projectile.create(kind_id, from, dir, speed, reach, visuals.accent_color)
	p.homing_target = homing
	p.on_hit = on_hit
	get_parent().add_child(p)
	p.global_position = from
	attack_spawned.emit(p)
	return p


func _aim_point_dir() -> Vector3:
	if is_instance_valid(current_target):
		var to := Combat.flat(current_target.global_position - global_position)
		if to.length() > 0.001:
			return to.normalized()
	return forward()


func _find_nearest_enemy() -> Node3D:
	return Combat.nearest_enemy(get_tree(), global_position)


func _fire_cleave_arc() -> void:
	var a := primary("CLEAVE")
	var reach := float(a["reach"])
	# The arc centers on the target so the first swing never misses while the
	# body is still turning toward it.
	var hits := Combat.in_arc(get_tree(), global_position, _aim_point_dir(), reach, float(a["params"]["arc_deg"]))
	spawn_hitbox("CLEAVE", global_position + _aim_point_dir() * reach * 0.5, reach)
	for e in hits:
		deal(e, "GREATAXE", float(a["damage_l1"]), "CLEAVE")
	if hits.size() >= int(cfg["passive"]["params"]["min_targets"]):
		add_guard_stack()
	primary_attack_fired.emit("CLEAVE", current_target)
	attack_timer /= attack_speed_mult      # Tempest Heart (§2A sets the base cadence)


func _fire_dagger_flurry(target: Node3D) -> void:
	var a := primary("DAGGER_FLURRY")
	var dmg := float(a["damage_l1"]) * (1.0 + next_dagger_bonus)
	next_dagger_bonus = 0.0
	spawn_hitbox("DAGGER_FLURRY", target.global_position, 0.6)
	for i in int(a["hits"]):
		deal(target, "DAGGERS", dmg, "DAGGER_FLURRY")
	primary_attack_fired.emit("DAGGER_FLURRY", target)
	attack_timer /= attack_speed_mult      # Tempest Heart (§2A sets the base cadence)


func _fire_bow_arrow(target: Node3D) -> void:
	var a := primary("BOW_ARROW")
	var dmg := float(a["damage_l1"])
	spawn_projectile("BOW_ARROW", global_position + Vector3(0, 1.2, 0), _aim_point_dir(), ARROW_SPEED,
		float(a["reach"]) + ARROW_OVERSHOOT, null,
		func(e: Node3D) -> void: deal(e, "SHORTBOW", dmg, "BOW_ARROW"))
	primary_attack_fired.emit("BOW_ARROW", target)
	attack_timer /= attack_speed_mult      # Tempest Heart (§2A sets the base cadence)


## AD4: every Prism Bolt leaves from the staff's orb-tipped focus.
func _fire_prism_bolt(target: Node3D) -> void:
	var a := primary("PRISM_BOLT")
	var dmg := float(a["damage_l1"])
	spawn_projectile("PRISM_BOLT", visuals.beam_origin(), _aim_point_dir(), BOLT_SPEED,
		float(a["reach"]) + ARROW_OVERSHOOT, target,
		func(e: Node3D) -> void: deal(e, "STAFF", dmg, "PRISM_BOLT"))
	primary_attack_fired.emit("PRISM_BOLT", target)
	attack_timer /= attack_speed_mult      # Tempest Heart (§2A sets the base cadence)


# --- Damage intake and passives (§2D, D29) -----------------------------------------

## Order: invulnerability → Arcane Glass Barrier (absorbs the whole hit) →
## Crimson Guard → HP. Any hit grants 0.4 s invulnerability. Returns HP lost.
func take_damage(amount: int, source: Dictionary = {}) -> int:
	if hp <= 0 or invuln_timer > 0.0:
		return 0
	if source.get("projectile", false):
		amount = maxi(1, roundi(amount * projectile_taken_mult))   # Amber Ward
	invuln_timer = float(GameState.heroes_data["combat"]["hit_invulnerability"])
	if barrier_up:
		_set_barrier(false)
		damaged.emit(0, "BARRIER")
		return 0
	var absorbed := minf(guard, float(amount))
	if absorbed > 0.0:
		guard -= absorbed
		guard_changed.emit(guard_fraction())
	var lost := int(roundf(float(amount) - absorbed))
	hp = maxi(0, hp - lost)
	damaged.emit(lost, "GUARD" if absorbed > 0.0 else "")
	if hp == 0:
		died.emit()
	else:
		_check_second_wind()
	return lost


## Spiked Carapace recoil (§2H): Crimson Guard soaks it first; it never drops the
## hero below 1 HP, ignores and never grants hit invulnerability.
func apply_recoil(amount: int) -> int:
	if hp <= 0 or amount <= 0:
		return 0
	var absorbed := minf(guard, float(amount))
	if absorbed > 0.0:
		guard -= absorbed
		guard_changed.emit(guard_fraction())
	var lost := mini(int(roundf(float(amount) - absorbed)), hp - 1)
	hp -= lost
	if lost > 0:
		damaged.emit(lost, "RECOIL")
		_check_second_wind()
	return lost


func _check_second_wind() -> void:
	if not second_wind.is_empty() and hp > 0 and hp < max_hp * float(second_wind["threshold"]):
		var amount := roundi(max_hp * float(second_wind["heal"]))
		second_wind = {}
		heal(amount)
		second_wind_triggered.emit()


func heal(amount: int) -> void:
	if hp > 0:
		hp = mini(max_hp, hp + amount)


func _guard_stack_hp() -> float:
	return float(cfg["passive"]["params"]["stack_hp_pct"]) * max_hp


## Crimson Guard: +10% max HP shield per stack, capped at 3 stacks (§2D).
func add_guard_stack() -> void:
	if hero_class != HeroClass.BRUTE:
		return
	var p: Dictionary = cfg["passive"]["params"]
	guard = minf(guard + _guard_stack_hp(), _guard_stack_hp() * float(p["max_stacks"]))
	guard_decay = float(p["decay_after"])
	guard_changed.emit(guard_fraction())


func guard_fraction() -> float:
	if hero_class != HeroClass.BRUTE:
		return 0.0
	return guard / (_guard_stack_hp() * float(cfg["passive"]["params"]["max_stacks"]))


func guard_active() -> bool:
	return guard > 0.0


func refresh_barrier() -> void:
	if hero_class == HeroClass.MAGI:
		_set_barrier(true)


func _set_barrier(up: bool) -> void:
	barrier_up = up
	barrier_timer = 0.0 if up else float(cfg["passive"]["params"]["refresh"])
	barrier_changed.emit(up)


## Ticked by HeroSkills every physics step (§2A's _physics_process stays verbatim).
func tick_status(delta: float) -> void:
	invuln_timer = maxf(0.0, invuln_timer - delta)
	if guard > 0.0:
		guard_decay -= delta
		if guard_decay <= 0.0:
			guard = 0.0
			guard_changed.emit(0.0)
	if hero_class == HeroClass.MAGI and not barrier_up:
		barrier_timer -= delta
		if barrier_timer <= 0.0:
			_set_barrier(true)
