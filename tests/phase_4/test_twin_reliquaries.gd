extends RefCounted
## Gate 4: Vespera's Twin Reliquaries and Shatter Shield (D41, §2B).

const STAGE := "stage_01_sunken_nave"

var sim: CombatSim


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if sim != null:
		sim.dispose()
		sim = null


func _phase_two_boss() -> BossVespera:
	sim = CombatSim.new(_tree(), "ROGUE")
	sim.hero.attack_timer = 1e9
	var cfg: Dictionary = GameState.stage_cfg(STAGE)
	var b := BossVespera.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	b.setup_boss(cfg["boss"], {}, sim.hero, Rect2(-9, -9, 18, 18), rng)
	sim.root.add_child(b)
	b.global_position = Vector3(0, 0, 6)
	b.activate()
	b._attack_cd = 1e9
	b.take_hit({"damage": 801, "source": "TEST"})
	return b


func test_pillars_rise_every_20s_10m_apart(t: TestContext) -> void:
	var b := _phase_two_boss()
	var raised := []
	b.reliquaries_raised.connect(func(p: Array) -> void: raised.append(p))
	sim.seconds(19.9)
	t.eq(raised.size(), 0, "none before 20 s")
	sim.seconds(0.2)
	t.eq(raised.size(), 1, "a pair at 20 s")
	var ps: Array = raised[0]
	t.eq(ps.size(), 2, "two pillars")
	t.near(Combat.flat_distance(ps[0].global_position, ps[1].global_position), 10.0, 1e-4, "10 m apart")
	t.ok(ps[0].is_in_group(Combat.ENEMY_GROUP), "targetable like an enemy")
	t.eq(ps[0].ring.duration, 6.0, "6 s countdown ring")


func test_breaking_both_within_window_shatters_harmlessly(t: TestContext) -> void:
	var b := _phase_two_boss()
	var results := []
	b.reliquaries_resolved.connect(func(ok: bool) -> void: results.append(ok))
	b.raise_reliquaries()
	var ps := b.pillars.duplicate()
	ps[0].take_hit({"damage": 1, "source": "BOW_ARROW"})
	sim.seconds(1.0)
	ps[1].take_hit({"damage": 1, "source": "DAGGER_FLURRY"})
	t.eq(results, [true], "both within 1.5 s: success")
	t.ok(not b.is_shielded(), "no Shatter Shield")
	t.eq(b.pillars.size(), 0, "pillars cleared")


func test_too_slow_or_missed_grants_shatter_shield(t: TestContext) -> void:
	var b := _phase_two_boss()
	var results := []
	b.reliquaries_resolved.connect(func(ok: bool) -> void: results.append(ok))
	b.raise_reliquaries()
	var ps := b.pillars.duplicate()
	ps[0].take_hit({"damage": 1})
	sim.seconds(2.0)
	ps[1].take_hit({"damage": 1})
	t.eq(results, [false], "2 s apart: failed")
	t.ok(b.is_shielded(), "Shatter Shield up")
	var hp0 := b.hp
	b.take_hit({"damage": 100, "source": "TEST"})
	t.eq(b.hp, hp0 - 25, "−75% damage taken while shielded")
	sim.seconds(8.05)
	t.ok(not b.is_shielded(), "shield lasts 8 s")
	b.raise_reliquaries()
	b.pillars[0].take_hit({"damage": 1})
	sim.seconds(6.05)
	t.eq(results, [false, false], "only one broken in 6 s: failed")
	t.ok(b.is_shielded(), "shield again — never fatal")


func test_an_echo_strike_counts(t: TestContext) -> void:
	var b := _phase_two_boss()
	var results := []
	b.reliquaries_resolved.connect(func(ok: bool) -> void: results.append(ok))
	b.raise_reliquaries()
	var ps := b.pillars.duplicate()
	ps[0].take_hit({"damage": 1, "source": "BOW_ARROW"})
	ps[1].take_hit({"damage": 1, "source": "SHATTER_NOVA", "is_echo": true})
	t.ok(ps[1].broken_by_echo, "the second pillar was broken by an Echo")
	t.eq(results, [true], "you + your Echo solve it together")


func test_pillar_hits_never_feed_stars(t: TestContext) -> void:
	var rs := RunSim.new(_tree(), "ROGUE", 2)
	rs.activate_boss()
	rs.run.boss._attack_cd = 1e9
	rs.run.boss.take_hit({"damage": 801, "source": "TEST"})
	rs.run.boss.raise_reliquaries()
	var pillar: ReliquaryPillar = rs.run.boss.pillars[0]
	rs.hero.hit_dealt.emit(pillar, {"source": "DAGGER_FLURRY"})
	t.eq(rs.run.dagger_hits, 0, "dagger hits on a pillar do not count toward Close Work")
	rs.hero.hit_dealt.emit(rs.run.boss, {"source": "DAGGER_FLURRY"})
	t.eq(rs.run.dagger_hits, 1, "hits on Vespera still count")
	rs.dispose()
