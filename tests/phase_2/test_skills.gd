extends RefCounted
## Gate 2: all 9 skills (§2D) — D27 aiming, locks, buffer and cooldowns, and the
## Area3D each one spawns.

var sim: CombatSim


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if sim != null:
		sim.dispose()
		sim = null


func _new(hero_id: String) -> CombatSim:
	sim = CombatSim.new(_tree(), hero_id)
	return sim


func _skill(s: CombatSim, id: String) -> Dictionary:
	return s.hero.skills.defs[s.hero.skills.index_of(id)]


func _expect_damage(t: TestContext, hit: Dictionary, base: int, label: String) -> void:
	var want := base * 2 if hit.get("crit", false) else base
	t.eq(hit.get("damage", -1), want, "%s damage (crit=%s)" % [label, str(hit.get("crit"))])


func _expect_area(t: TestContext, s: CombatSim, kind: String, radius: float) -> void:
	var nodes := s.spawned_of(kind)
	t.ok(not nodes.is_empty(), "%s spawned an Area3D" % kind)
	if nodes.is_empty():
		return
	var a: Area3D = nodes[0]
	t.near(a.shape_radius(), radius, 1e-6, "%s shape radius" % kind)
	t.eq(a.collision_layer, Combat.LAYER_HERO_ATTACK, "%s on the hero-attack layer" % kind)
	t.ok(a.collision_mask & Combat.LAYER_ENEMY != 0, "%s masks enemies" % kind)


func _expect_cast(t: TestContext, s: CombatSim, id: String) -> void:
	var d := _skill(s, id)
	var i := s.hero.skills.index_of(id)
	t.near(s.hero.skills.cooldowns[i], float(d["cooldown"]), 1e-6, "%s cooldown from heroes.json" % id)
	match str(d["lock_state"]):
		"CASTING_SKILL":
			t.eq(s.hero.state, HeroController.CombatState.CASTING_SKILL, "%s locks as CASTING_SKILL" % id)
			t.near(s.hero.lock_timer, float(d["lock"]), 1e-6, "%s lock time" % id)
		"DASHING":
			t.eq(s.hero.state, HeroController.CombatState.DASHING, "%s locks as DASHING" % id)
			t.near(s.hero.lock_timer, float(d["lock"]), 1e-6, "%s lock time" % id)
		"INSTANT":
			t.ok(not s.hero.is_locked(), "%s is instant" % id)


# --- Brute ------------------------------------------------------------------------

func test_leap_slam_lands_on_nearest_enemy(t: TestContext) -> void:
	var s := _new("BRUTE")
	var d := s.dummy(Vector3(0, 0, 4))
	t.ok(s.cast("LEAP_SLAM"), "Leap Slam casts")
	_expect_cast(t, s, "LEAP_SLAM")
	s.seconds(0.5)
	t.ok(Combat.flat_distance(s.hero.global_position, d.global_position) < 0.3, "landed on the target")
	_expect_area(t, s, "LEAP_SLAM", 2.5)
	t.eq(d.hits.size(), 1, "slam hit once")
	_expect_damage(t, d.hits[0], 30, "Leap Slam")
	t.ok(d.has_status("STUN"), "0.5 s stun applied")
	var at := s.hero.global_position
	s.step(20)
	t.ok(s.hero.global_position.distance_to(at) < 0.001, "no slide after the lock ends")


func test_leap_slam_without_target_goes_5m_forward(t: TestContext) -> void:
	var s := _new("BRUTE")
	s.cast("LEAP_SLAM")
	s.seconds(0.5)
	t.ok(s.hero.global_position.distance_to(Vector3(0, 0, 5)) < 0.25, "5 m along facing: %s" % str(s.hero.global_position))


func test_rending_roar_weakens_and_grants_guard(t: TestContext) -> void:
	var s := _new("BRUTE")
	var near := s.dummy(Vector3(5, 0, 0))
	var far := s.dummy(Vector3(7, 0, 0))
	t.ok(s.cast("RENDING_ROAR"), "Rending Roar casts")
	_expect_cast(t, s, "RENDING_ROAR")
	_expect_area(t, s, "RENDING_ROAR", 6.0)
	t.ok(near.has_status("WEAKEN"), "enemy within 6 m weakened")
	t.near(float(near.status_data("WEAKEN")["damage_mult"]), 0.7, 1e-6, "−30% enemy damage")
	t.near(float(near.status_data("WEAKEN")["duration"]), 5.0, 1e-6, "for 5 s")
	t.ok(not far.has_status("WEAKEN"), "enemy at 7 m unaffected")
	t.near(s.hero.guard_fraction(), 1.0 / 3.0, 1e-6, "one Crimson Guard stack")


func test_vortex_cleave_hits_and_pulls(t: TestContext) -> void:
	var s := _new("BRUTE")
	var inside := s.dummy(Vector3(6, 0, 0))
	var outside := s.dummy(Vector3(8, 0, 0))
	t.ok(s.cast("VORTEX_CLEAVE"), "Vortex Cleave casts")
	_expect_cast(t, s, "VORTEX_CLEAVE")
	_expect_area(t, s, "VORTEX_CLEAVE", 7.0)
	_expect_damage(t, inside.hits[0], 45, "Vortex Cleave")
	t.near(inside.global_position.x, 4.5, 1e-6, "pulled 1.5 m toward the Brute")
	t.eq(outside.hits.size(), 0, "enemy at 8 m untouched")


# --- Rogue ------------------------------------------------------------------------

func test_shadow_vault_dashes_away_with_invulnerability(t: TestContext) -> void:
	var s := _new("ROGUE")
	s.dummy(Vector3(0, 0, 2))
	t.ok(s.cast("SHADOW_VAULT"), "Shadow Vault casts")
	_expect_cast(t, s, "SHADOW_VAULT")
	t.eq(s.hero.take_damage(30), 0, "invulnerable during the vault")
	s.seconds(0.25)
	t.ok(s.hero.global_position.distance_to(Vector3(0, 0, -4)) < 0.25, "4 m directly away: %s" % str(s.hero.global_position))
	t.near(s.hero.next_dagger_bonus, 0.5, 1e-6, "next dagger pair +50%")


func test_shadow_vault_follows_stick_and_boosts_daggers(t: TestContext) -> void:
	var s := _new("ROGUE")
	s.hero.input_vector = Vector2(1, 0)
	s.cast("SHADOW_VAULT")
	s.hero.input_vector = Vector2.ZERO
	s.seconds(0.25)
	t.ok(s.hero.global_position.distance_to(Vector3(4, 0, 0)) < 0.25, "stick direction wins: %s" % str(s.hero.global_position))
	var d := s.dummy(s.hero.global_position + Vector3(2, 0, 0))
	s.step_until(func() -> bool: return d.hits.size() >= 4, 120)
	_expect_damage(t, d.hits[0], 11, "boosted dagger (7 × 1.5 = 10.5 → 11)")
	_expect_damage(t, d.hits[1], 11, "boosted dagger")
	_expect_damage(t, d.hits[2], 7, "bonus used up")


func test_adaptive_barrage_bow_mode(t: TestContext) -> void:
	var s := _new("ROGUE")
	var d := s.dummy(Vector3(0, 0, 8))
	t.ok(s.cast("ADAPTIVE_BARRAGE"), "Barrage casts")
	_expect_cast(t, s, "ADAPTIVE_BARRAGE")
	s.seconds(1.0)
	var arrows := s.spawned_of("ADAPTIVE_BARRAGE_ARROW")
	t.eq(arrows.size(), 5, "5 arrows")
	if not arrows.is_empty():
		t.near(arrows[0].shape_radius(), 0.25, 1e-6, "arrow shape radius")
		t.ok(arrows[0].homing_target == d, "arrows home on the target")
	var barrage := d.hits.filter(func(h: Dictionary) -> bool: return h["source"] == "ADAPTIVE_BARRAGE")
	t.eq(barrage.size(), 5, "all 5 arrows hit")
	for h in barrage:
		_expect_damage(t, h, 8, "Barrage arrow")


func test_adaptive_barrage_dagger_mode(t: TestContext) -> void:
	var s := _new("ROGUE")
	var d := s.dummy(Vector3(0, 0, 2))
	s.step_until(func() -> bool: return s.hero.rogue_mode == HeroController.RogueMode.DAGGERS, 30)
	d.hits.clear()
	s.hero.attack_timer = 99.0
	t.ok(s.cast("ADAPTIVE_BARRAGE"), "Barrage casts in dagger mode")
	_expect_area(t, s, "ADAPTIVE_BARRAGE_DAGGERS", 3.0)
	t.eq(d.hits.size(), 4, "4 slices")
	for h in d.hits:
		_expect_damage(t, h, 10, "Barrage slice")


func test_shatter_mark_needs_a_target(t: TestContext) -> void:
	var s := _new("ROGUE")
	t.ok(not s.cast("SHATTER_MARK"), "no target: no cast")
	t.ok(s.hero.skills.is_ready(s.hero.skills.index_of("SHATTER_MARK")), "cooldown not spent (Q-9)")


func test_shatter_mark_amplifies_and_heals_on_kill(t: TestContext) -> void:
	var s := _new("ROGUE")
	var d := s.dummy(Vector3(0, 0, 6), 15)
	s.hero.hp = 50
	t.ok(s.cast("SHATTER_MARK"), "Shatter Mark casts")
	_expect_cast(t, s, "SHATTER_MARK")
	_expect_area(t, s, "SHATTER_MARK", 0.6)
	t.near(float(d.status_data("MARK")["damage_taken_mult"]), 1.25, 1e-6, "+25% damage taken")
	t.near(float(d.status_data("MARK")["duration"]), 8.0, 1e-6, "for 8 s")
	s.step_until(func() -> bool: return not d.is_alive(), 240)
	t.ok(not d.is_alive(), "marked target killed")
	_expect_damage(t, d.hits[0], 15, "marked arrow (12 × 1.25)")
	t.eq(s.hero.hp, 60, "marked kill heals 10")


# --- Magi -------------------------------------------------------------------------

func test_phase_blink_teleports_and_refreshes_barrier(t: TestContext) -> void:
	var s := _new("MAGI")
	s.dummy(Vector3(0, 0, 2))
	s.hero.take_damage(10)
	t.ok(not s.hero.barrier_up, "barrier broken first")
	t.ok(s.cast("PHASE_BLINK"), "Phase Blink casts")
	_expect_cast(t, s, "PHASE_BLINK")
	t.ok(s.hero.global_position.distance_to(Vector3(0, 0, -4)) < 0.01, "4 m directly away: %s" % str(s.hero.global_position))
	t.ok(s.hero.barrier_up, "barrier refreshed")


func test_gravity_well_pulls_and_ticks(t: TestContext) -> void:
	var s := _new("MAGI")
	var target := s.dummy(Vector3(0, 0, 6))
	var edge := s.dummy(Vector3(2, 0, 6))
	s.hero.attack_timer = 99.0
	t.ok(s.cast("GRAVITY_WELL"), "Gravity Well casts")
	_expect_cast(t, s, "GRAVITY_WELL")
	_expect_area(t, s, "GRAVITY_WELL", 3.0)
	var zone: Hitbox = s.spawned_of("GRAVITY_WELL")[0]
	t.ok(Combat.flat_distance(zone.global_position, Vector3(0, 0, 6)) < 0.01, "centered on the nearest enemy within 8 m")
	s.hero.attack_timer = 99.0
	s.seconds(0.5)
	t.ok(Combat.flat_distance(edge.global_position, zone.global_position) < 1.5, "edge enemy pulled inward")
	s.seconds(4.1)
	var ticks := target.hits.filter(func(h: Dictionary) -> bool: return h["source"] == "GRAVITY_WELL")
	t.eq(ticks.size(), 4, "6 dmg/s for 4 s = 4 ticks")
	for h in ticks:
		_expect_damage(t, h, 6, "Gravity Well tick")


func test_gravity_well_without_target_lands_ahead(t: TestContext) -> void:
	var s := _new("MAGI")
	s.cast("GRAVITY_WELL")
	var zone: Hitbox = s.spawned_of("GRAVITY_WELL")[0]
	t.ok(Combat.flat_distance(zone.global_position, Vector3(0, 0, 3)) < 0.01, "3 m ahead")


func test_shatter_nova_hits_and_knocks_back(t: TestContext) -> void:
	var s := _new("MAGI")
	var inside := s.dummy(Vector3(3, 0, 0))
	var outside := s.dummy(Vector3(5, 0, 0))
	t.ok(s.cast("SHATTER_NOVA"), "Shatter Nova casts")
	_expect_cast(t, s, "SHATTER_NOVA")
	_expect_area(t, s, "SHATTER_NOVA", 4.0)
	_expect_damage(t, inside.hits[0], 40, "Shatter Nova")
	t.near(inside.global_position.x, 6.0, 1e-6, "knocked back 3 m")
	t.eq(outside.hits.size(), 0, "enemy at 5 m untouched")


# --- Shared rules -------------------------------------------------------------------

func test_cooldown_blocks_recast_then_recovers(t: TestContext) -> void:
	var s := _new("BRUTE")
	t.ok(s.cast("RENDING_ROAR"), "first cast")
	s.seconds(1.0)
	t.ok(not s.cast("RENDING_ROAR"), "on cooldown")
	var i := s.hero.skills.index_of("RENDING_ROAR")
	t.near(s.hero.skills.cooldown_fraction(i), 11.0 / 12.0, 0.01, "ring shows remaining cooldown")
	s.seconds(11.05)
	t.ok(s.hero.skills.is_ready(i), "ready after 12 s")
	t.eq(s.hero.skills.cooldown_fraction(i), 0.0, "ring empty when ready")
	t.ok(s.cast("RENDING_ROAR"), "recast")


func test_input_buffer_150ms(t: TestContext) -> void:
	var s := _new("BRUTE")
	var casts: Array[String] = []
	s.hero.skill_cast.connect(func(id: String) -> void: casts.append(id))
	s.cast("LEAP_SLAM")
	s.seconds(0.15)
	t.ok(not s.cast("RENDING_ROAR"), "press 0.3 s before the lock ends is buffered, not cast")
	s.seconds(0.35)
	t.eq(casts, ["LEAP_SLAM"], "a press older than 0.15 s is dropped")
	s.hero.skills.cooldowns[0] = 0.0
	s.cast("LEAP_SLAM")
	s.seconds(0.35)
	s.cast("RENDING_ROAR")
	s.seconds(0.2)
	t.eq(casts, ["LEAP_SLAM", "LEAP_SLAM", "RENDING_ROAR"], "a press within 0.15 s of the lock end fires right after it")


func test_casting_while_moving_is_allowed(t: TestContext) -> void:
	var s := _new("MAGI")
	s.hero.input_vector = Vector2(1, 0)
	s.step(5)
	t.ok(s.cast("SHATTER_NOVA"), "cast while moving (D27)")
	t.eq(s.hero.state, HeroController.CombatState.CASTING_SKILL, "cast lock roots the hero")
	t.eq(s.hero.velocity, Vector3.ZERO, "rooted during the lock")


func test_every_skill_is_data_driven(t: TestContext) -> void:
	var movement_only := ["SHADOW_VAULT", "PHASE_BLINK"]
	var total := 0
	for hero_id in ["BRUTE", "ROGUE", "MAGI"]:
		for skill in GameState.heroes_data["heroes"][hero_id]["skills"]:
			var s := CombatSim.new(_tree(), hero_id)
			s.dummy(Vector3(0, 0, 2.5))
			s.dummy(Vector3(1.5, 0, 2.5))
			var id: String = skill["id"]
			t.ok(s.cast(id), "%s casts with targets nearby" % id)
			_expect_cast(t, s, id)
			s.seconds(0.5)
			if id in movement_only:
				t.eq(s.spawned.size() - s.attacks.size(), 0, "%s spawns no attack area (movement skill, Q-9)" % id)
			else:
				var skill_areas := s.spawned.filter(func(n: Area3D) -> bool: return str(n.get("kind")).begins_with(id))
				t.ok(not skill_areas.is_empty(), "%s spawned its Area3D" % id)
				for a in skill_areas:
					t.ok(a.shape_radius() > 0.0, "%s Area3D has a sphere shape" % id)
			total += 1
			s.dispose()
	t.eq(total, 9, "all 9 skills covered")
