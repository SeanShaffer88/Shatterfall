extends RefCounted
## Gate 2: stop-to-attack controller (§2A), reach (D28), Rogue hysteresis + AD3
## flash, cleave/Crimson Guard (AD2), barrier/orb (AD4) and damage intake (D29).

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


func _expect_damage(t: TestContext, hit: Dictionary, base: int, label: String) -> void:
	var want := base * 2 if hit.get("crit", false) else base
	t.eq(hit.get("damage", -1), want, "%s damage (crit=%s)" % [label, str(hit.get("crit"))])


func test_constants_mirror_heroes_json(t: TestContext) -> void:
	var h: Dictionary = GameState.heroes_data["heroes"]
	var c: Dictionary = GameState.heroes_data["combat"]
	t.eq(HeroController.STOP_VELOCITY, c["stop_velocity"], "stop velocity")
	t.eq(HeroController.GRACE_TIME, c["attack_grace"], "attack grace")
	t.eq(HeroController.BRUTE_RANGE, h["BRUTE"]["primary"][0]["reach"], "cleave reach")
	t.eq(HeroController.DAGGER_ENTER, h["ROGUE"]["primary"][0]["params"]["mode_enter"], "dagger enter")
	t.eq(HeroController.DAGGER_EXIT, h["ROGUE"]["primary"][0]["params"]["mode_exit"], "dagger exit")
	t.eq(HeroController.DAGGER_EXIT, h["ROGUE"]["primary"][0]["reach"], "dagger reach == exit threshold")
	t.eq(HeroController.BOW_RANGE, h["ROGUE"]["primary"][1]["reach"], "bow reach")
	t.eq(HeroController.MAGI_RANGE, h["MAGI"]["primary"][0]["reach"], "bolt reach")
	var cases := [["BRUTE", Vector3(0, 0, 2), "CLEAVE"], ["ROGUE", Vector3(0, 0, 2), "DAGGER_FLURRY"],
		["ROGUE", Vector3(0, 0, 8), "BOW_ARROW"], ["MAGI", Vector3(0, 0, 8), "PRISM_BOLT"]]
	for c2 in cases:
		var s := _new(c2[0])
		s.dummy(c2[1])
		s.step_until(func() -> bool: return not s.attacks.is_empty(), 60)
		var cadence: float = s.hero.primary(c2[2])["cadence"]
		t.near(s.hero.attack_timer, cadence, 1e-6, "%s cadence from heroes.json" % c2[2])
		s.dispose()
	sim = null


func test_auto_attack_within_100ms_of_full_stop(t: TestContext) -> void:
	var s := _new("BRUTE")
	s.dummy(Vector3(2, 0, 0))
	s.hero.input_vector = Vector2(0, -1)
	s.step(6)
	t.eq(s.attacks.size(), 0, "no attack while moving")
	s.hero.input_vector = Vector2.ZERO
	var to_stop := s.step_until(func() -> bool: return s.hero.velocity.length() <= HeroController.STOP_VELOCITY, 60)
	var t_stop := s.time
	t.ok(to_stop >= 0, "hero comes to a full stop")
	t.eq(s.attacks.size(), 0, "no attack before full stop")
	s.step_until(func() -> bool: return not s.attacks.is_empty(), 60)
	var latency := s.time - t_stop
	t.ok(latency <= 0.10 + 1e-9, "auto-attack %.3f s after full stop (gate ≤ 0.10 s)" % latency)
	t.ok(latency >= HeroController.GRACE_TIME - CombatSim.DT - 1e-9, "grace buffer honored (%.3f s)" % latency)
	t.eq(s.hero.state, HeroController.CombatState.STOPPED_ATTACKING, "state")


func test_movement_reacquires_same_frame(t: TestContext) -> void:
	var s := _new("BRUTE")
	s.dummy(Vector3(2, 0, 0))
	s.step(20)
	t.eq(s.hero.state, HeroController.CombatState.STOPPED_ATTACKING, "attacking while still")
	var before := s.attacks.size()
	s.hero.input_vector = Vector2(1, 0)
	s.step(1)
	t.eq(s.hero.state, HeroController.CombatState.MOVING, "MOVING on the very next frame")
	t.near(s.hero.velocity.x, s.hero.move_speed, 1e-6, "full speed immediately")
	t.eq(s.attacks.size(), before, "no attack on the frame movement resumes")


func test_sub_deadzone_input_counts_as_stopped(t: TestContext) -> void:
	var s := _new("MAGI")
	s.dummy(Vector3(0, 0, 6))
	s.hero.input_vector = Vector2(0.15, 0)
	s.step(20)
	t.near(s.hero.velocity.length(), 0.0, 1e-6, "0.15 stick is below the 0.18 deadzone")
	t.ok(not s.attacks.is_empty(), "hero attacks with a resting thumb")


func test_no_swing_beyond_reach(t: TestContext) -> void:
	var cases := [["BRUTE", 3.3, 3.1], ["ROGUE", 10.6, 10.4], ["MAGI", 14.2, 13.8]]
	for c in cases:
		var s := _new(c[0])
		var d := s.dummy(Vector3(c[1], 0, 0))
		s.step(120)
		t.eq(s.attacks.size(), 0, "%s: no attack at %.1f m" % [c[0], c[1]])
		d.global_position = Vector3(c[2], 0, 0)
		s.step(10)
		t.ok(not s.attacks.is_empty(), "%s: attacks at %.1f m" % [c[0], c[2]])
		s.dispose()
	sim = null


func test_rogue_hysteresis_and_swap_flash(t: TestContext) -> void:
	var s := _new("ROGUE")
	var d := s.dummy(Vector3(5, 0, 0))
	var changes: Array[int] = []
	s.hero.rogue_mode_changed.connect(func(m: int) -> void: changes.append(m))
	var BOW := HeroController.RogueMode.BOW
	var DAG := HeroController.RogueMode.DAGGERS
	var steps := [[5.0, BOW], [2.7, BOW], [2.6, DAG], [2.9, DAG], [3.0, DAG], [3.01, BOW], [2.61, BOW], [2.5, DAG]]
	for st in steps:
		d.global_position = Vector3(st[0], 0, 0)
		s.step(12)
		t.eq(s.hero.rogue_mode, st[1], "mode at %.2f m" % st[0])
	t.eq(changes, [DAG, BOW, DAG], "exactly one signal per mode change")
	t.eq(s.hero.visuals.flash_count, 3, "AD3 trim flash fired once per swap")
	d.global_position = Vector3(5, 0, 0)
	s.step(1)
	t.ok(s.hero.visuals.is_flashing(), "flash active right after a swap")
	t.near(s.hero.visuals.accent_energy(), HeroVisuals.TRIM_FLASH, 1e-6, "flash energy")
	s.step(10)
	t.ok(not s.hero.visuals.is_flashing(), "flash ends after 0.15 s")
	t.near(s.hero.visuals.accent_energy(), HeroVisuals.TRIM_BASE, 1e-6, "trim returns to base")


func test_dagger_and_bow_damage(t: TestContext) -> void:
	var s := _new("ROGUE")
	var d := s.dummy(Vector3(2, 0, 0))
	s.step_until(func() -> bool: return d.hits.size() >= 2, 60)
	t.eq(d.hits.size(), 2, "a flurry is 2 hits")
	for h in d.hits:
		_expect_damage(t, h, 7, "dagger hit")
		t.eq(h["source"], "DAGGER_FLURRY", "source")
	d.hits.clear()
	d.global_position = Vector3(8, 0, 0)
	s.step_until(func() -> bool: return not d.hits.is_empty(), 120)
	t.eq(d.hits.size(), 1, "one arrow hit")
	_expect_damage(t, d.hits[0], 12, "bow arrow")
	t.eq(s.spawned_of("BOW_ARROW").size() > 0, true, "arrow was a spawned projectile")


func test_cleave_arc_and_crimson_guard(t: TestContext) -> void:
	var s := _new("BRUTE")
	var front := s.dummy(Vector3(0, 0, 1.8))
	var behind := s.dummy(Vector3(0, 0, -2.2))
	s.step_until(func() -> bool: return not s.attacks.is_empty(), 60)
	t.eq(front.hits.size(), 1, "front dummy hit")
	t.eq(behind.hits.size(), 0, "dummy behind is outside the 110° arc")
	_expect_damage(t, front.hits[0], 22, "cleave")
	t.ok(not s.hero.guard_active(), "one target grants no Crimson Guard")
	var side := s.dummy(Vector3(0.8, 0, 2.0))
	s.attacks.clear()
	s.step_until(func() -> bool: return not s.attacks.is_empty(), 90)
	t.eq(side.hits.size(), 1, "second front dummy hit")
	t.near(s.hero.guard_fraction(), 1.0 / 3.0, 1e-6, "2+ targets: one Guard stack (10% of 30%)")
	t.near(s.hero.guard, 14.0, 1e-6, "stack = 10% of 140 max HP")
	t.near(s.hero.visuals.accent_energy(), HeroVisuals.EMBER_MAX / 3.0, 1e-6, "AD2 embers dim at 10%")


func test_guard_cap_decay_and_absorption(t: TestContext) -> void:
	var s := _new("BRUTE")
	for i in 4:
		s.hero.add_guard_stack()
	t.near(s.hero.guard_fraction(), 1.0, 1e-6, "capped at 3 stacks")
	t.near(s.hero.visuals.accent_energy(), HeroVisuals.EMBER_MAX, 1e-6, "AD2 embers fully lit at 30%")
	t.eq(s.hero.take_damage(30), 0, "Guard (42) absorbs a 30 hit")
	t.near(s.hero.guard, 12.0, 1e-6, "Guard left")
	t.eq(s.hero.take_damage(30), 0, "0.4 s hit invulnerability")
	s.seconds(0.45)
	t.eq(s.hero.take_damage(30), 18, "Guard 12 absorbed, 18 to HP")
	t.eq(s.hero.hp, 122, "HP after hit")
	s.hero.add_guard_stack()
	s.seconds(6.05)
	t.ok(not s.hero.guard_active(), "Guard breaks after 6 s without a qualifying hit")
	t.near(s.hero.visuals.accent_energy(), 0.0, 1e-6, "AD2 embers dark when Guard is gone")


func test_barrier_absorbs_one_hit_and_orb_tracks(t: TestContext) -> void:
	var s := _new("MAGI")
	t.ok(s.hero.barrier_up, "barrier starts up")
	t.near(s.hero.visuals.accent_energy(), HeroVisuals.ORB_UP, 1e-6, "AD4 orb bright while up")
	t.eq(s.hero.take_damage(50), 0, "barrier absorbs the whole hit")
	t.eq(s.hero.hp, 110, "no HP lost")
	t.ok(not s.hero.barrier_up, "barrier broken")
	t.near(s.hero.visuals.accent_energy(), HeroVisuals.ORB_DOWN, 1e-6, "AD4 orb dark while recharging")
	s.seconds(0.5)
	t.eq(s.hero.take_damage(20), 20, "next hit lands on HP")
	s.seconds(5.6)
	t.ok(s.hero.barrier_up, "barrier refreshes 6 s after breaking")
	t.near(s.hero.visuals.accent_energy(), HeroVisuals.ORB_UP, 1e-6, "orb bright again")


func test_prism_bolt_leaves_from_the_orb(t: TestContext) -> void:
	var s := _new("MAGI")
	var d := s.dummy(Vector3(0, 0, 8))
	s.step_until(func() -> bool: return not s.spawned_of("PRISM_BOLT").is_empty(), 60)
	var i := s.spawned.find(s.spawned_of("PRISM_BOLT")[0])
	t.ok(s.spawn_positions[i].distance_to(s.hero.visuals.beam_origin()) < 0.05, "AD4: bolt origin is the orb")
	s.step_until(func() -> bool: return not d.hits.is_empty(), 120)
	_expect_damage(t, d.hits[0], 15, "prism bolt")


func test_death_emits_once(t: TestContext) -> void:
	var s := _new("ROGUE")
	var deaths := [0]
	s.hero.died.connect(func() -> void: deaths[0] += 1)
	s.hero.take_damage(500)
	s.seconds(0.5)
	s.hero.take_damage(500)
	t.eq(s.hero.hp, 0, "HP floors at 0")
	t.eq(deaths[0], 1, "died emitted once")
	t.ok(not s.hero.skills.request(0), "a dead hero cannot cast")
