extends RefCounted
## Gate 3: Vespera (§2E, D32) and her Grudge Adaptations (§2H, D11).

const STAGE := "stage_01_sunken_nave"

var sim: CombatSim
var run_sim: RunSim


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if sim != null:
		sim.dispose()
		sim = null
	if run_sim != null:
		run_sim.dispose()
		run_sim = null


func _boss(hero_id: String, adaptation_of: String = "") -> BossVespera:
	sim = CombatSim.new(_tree(), hero_id)
	sim.hero.attack_timer = 1e9
	var cfg: Dictionary = GameState.stage_cfg(STAGE)
	var adapt: Dictionary = cfg["grudge"][adaptation_of] if adaptation_of != "" else {}
	var b := BossVespera.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	b.setup_boss(cfg["boss"], adapt, sim.hero, Rect2(-9, -9, 18, 18), rng)
	sim.root.add_child(b)
	b.global_position = Vector3(0, 0, 6)
	return b


func test_boss_activates_1_5s_after_the_door_locks(t: TestContext) -> void:
	run_sim = RunSim.new(_tree(), "BRUTE")
	run_sim.to_boss()
	t.eq(run_sim.run.phase, DungeonRun.Phase.BOSS_INTRO, "intro phase on entry")
	t.ok(not run_sim.run.stage.doors[3].is_open, "arena door locked behind the hero")
	t.eq(run_sim.run.boss.hp, 1600, "1600 HP (D32)")
	run_sim.seconds(1.4)
	t.ok(not run_sim.run.boss.active, "inactive at 1.4 s")
	run_sim.seconds(0.15)
	t.ok(run_sim.run.boss.active, "active at 1.55 s")
	t.ok(run_sim.run.hud.boss_bar.visible, "boss health bar shown")


func test_immune_to_stun_pull_and_knockback(t: TestContext) -> void:
	var b := _boss("MAGI")
	b.activate()
	b.apply_status("STUN", {"duration": 1.0})
	t.ok(not b.has_status("STUN"), "stun ignored")
	var at := b.global_position
	b.displace(Vector3(3, 0, 0))
	t.eq(b.global_position, at, "pull/knockback ignored")
	b.take_hit({"damage": 40, "source": "SHATTER_NOVA"})
	t.eq(b.hp, 1560, "the skills' damage still lands")


func test_sweep_and_rain_telegraphs_by_phase(t: TestContext) -> void:
	var b := _boss("ROGUE")
	b.activate()
	b._start_attack("SWEEP")
	t.near(b.current_attack["full"], 0.9, 1e-6, "phase 1 sweep telegraph 0.9 s")
	t.eq(b.current_attack["telegraphs"][0].shape, "cone", "120° cone")
	sim.hero.global_position = Vector3(0, 0, 2)
	sim.seconds(0.95)
	t.eq(sim.hero.hp, 70, "sweep hits for 30 inside the cone")
	b._start_attack("SHARD_RAIN")
	t.near(b.current_attack["full"], 1.2, 1e-6, "phase 1 rain telegraph 1.2 s")
	t.eq(b.current_attack["telegraphs"].size(), 3, "3 zones")
	t.ok(Combat.flat_distance(b.current_attack["zones"][0], sim.hero.global_position) < 0.01, "one zone on the hero")
	sim.seconds(1.25)
	t.eq(sim.hero.hp, 60, "10 per zone the hero stands in")
	b.take_hit({"damage": 800, "source": "TEST"})
	t.eq(b.phase_index, 1, "phase 2 at ≤ 50% HP")
	b._start_attack("SWEEP")
	t.near(b.current_attack["full"], 0.65, 1e-6, "phase 2 sweep telegraph 0.65 s")
	b._cancel_attack()
	b._start_attack("SHARD_RAIN")
	t.near(b.current_attack["full"], 0.9, 1e-6, "phase 2 rain telegraph 0.9 s")
	t.near(float(b.phase_cfg()["attack_interval"]), 1.8, 1e-6, "attacks every 1.8 s in phase 2")


func test_sweep_misses_outside_the_cone(t: TestContext) -> void:
	var b := _boss("ROGUE")
	b.activate()
	b._start_attack("SWEEP")
	sim.hero.global_position = Vector3(0, 0, 12)
	sim.seconds(0.95)
	t.eq(sim.hero.hp, 100, "out of range: no damage")


func test_phase_two_adds_once_and_shard_walls(t: TestContext) -> void:
	var b := _boss("ROGUE")
	b.activate()
	var adds := []
	b.adds_requested.connect(func(g: Array) -> void: adds.append(g))
	b.take_hit({"damage": 801, "source": "TEST"})
	b.take_hit({"damage": 10, "source": "TEST"})
	t.eq(adds.size(), 1, "adds requested once")
	t.eq(adds[0], [{"enemy": "CRAWLER", "count": 4}], "4 Crawlers")
	var walls := []
	b.wall_raised.connect(func(w: ShardWall) -> void: walls.append(w))
	b._attack_cd = 1e9
	sim.seconds(11.9)
	t.eq(walls.size(), 0, "no wall before 12 s")
	sim.seconds(0.2)
	t.eq(walls.size(), 1, "a shard wall every 12 s")
	var wall: ShardWall = walls[0]
	t.eq(wall.collision_layer, 0, "not solid during its 0.6 s rise telegraph")
	sim.seconds(0.65)
	t.ok(wall.solid and wall.collision_layer == Combat.LAYER_WORLD, "solid: blocks hero movement")
	t.ok(wall.blocks(wall.global_position, 0.25), "blocks projectiles at its center")
	t.ok(not wall.blocks(wall.global_position + Vector3(0, 0, 2), 0.25), "not 2 m away")


func test_hero_projectiles_stop_at_the_wall(t: TestContext) -> void:
	var b := _boss("ROGUE")
	b.activate()
	b.take_hit({"damage": 801, "source": "TEST"})
	b._attack_cd = 1e9
	sim.hero.global_position = Vector3(0, 0, -2)
	var wall := ShardWall.new()
	wall.setup(GameState.stage_cfg(STAGE)["boss"]["attacks"]["SHARD_WALL"])
	sim.root.add_child(wall)
	wall.global_position = Vector3(0, 0, 2)
	sim.seconds(0.65)
	var hp0 := b.hp
	sim.hero.attack_timer = 0.0
	sim.seconds(1.5)
	t.eq(b.hp, hp0, "arrows break on the wall instead of hitting Vespera")


func test_spiked_carapace_recoil(t: TestContext) -> void:
	var b := _boss("BRUTE", "BRUTE")
	t.eq(b.adaptation_id(), "SPIKED_CARAPACE", "Brute clear → Spiked Carapace")
	b.take_hit({"damage": 100, "source": "CLEAVE"})
	t.eq(sim.hero.hp, 125, "15% recoil on a melee hit")
	b.take_hit({"damage": 100, "source": "BOW_ARROW"})
	t.eq(sim.hero.hp, 125, "no recoil on ranged hits")
	b.take_hit({"damage": 100, "source": "CLEAVE", "is_echo": true})
	t.eq(sim.hero.hp, 125, "echo hits never recoil")
	sim.hero.add_guard_stack()
	b.take_hit({"damage": 60, "source": "LEAP_SLAM"})
	t.eq(sim.hero.hp, 125, "Crimson Guard soaks recoil first")
	sim.hero.hp = 3
	sim.hero.guard = 0.0
	b.take_hit({"damage": 200, "source": "VORTEX_CLEAVE"})
	t.eq(sim.hero.hp, 1, "recoil never drops the hero below 1 HP")


func test_mirage_veil_restarts_with_full_warning(t: TestContext) -> void:
	var b := _boss("ROGUE", "ROGUE")
	b.activate()
	b._attack_cd = 1e9
	b._start_attack("SWEEP")
	sim.seconds(0.5)
	t.near(b.current_attack["t"], 0.4, 0.02, "half-way through the warning")
	var from := b.global_position
	b._veil_t = float(b.adaptation["params"]["interval"]) - 0.001
	sim.step()
	t.near(Combat.flat_distance(from, b.global_position), 3.0, 0.05, "blinks 3 m sideways")
	# The blink happens at the start of the tick; the same tick then counts one step down.
	t.near(b.current_attack["t"], b.current_attack["full"] - CombatSim.DT, 1e-6, "warning restarted in full")
	t.ok(b.current_attack["telegraphs"][0].progress() < 0.03, "telegraph redrawn from zero")
	t.ok(Combat.flat_distance(b.current_attack["origin"], b.global_position) < 0.01, "redrawn from her new position")


func test_runic_dampening(t: TestContext) -> void:
	var b := _boss("MAGI", "MAGI")
	var c := b.global_position
	b.take_hit({"damage": 40, "aoe_center": c + Vector3(3.5, 0, 0), "aoe_radius": 4.0})
	t.eq(b.hp, 1600, "outside 70% of a 4 m radius: no hit")
	b.take_hit({"damage": 40, "aoe_center": c + Vector3(2.5, 0, 0), "aoe_radius": 4.0})
	t.eq(b.hp, 1560, "inside 2.8 m: hits")
	b.take_hit({"damage": 6, "aoe_center": c, "aoe_radius": 3.0, "zone_age": 3.0, "zone_duration": 4.0})
	t.eq(b.hp, 1560, "Gravity Well tick after 70% of its life: no hit")
	b.take_hit({"damage": 6, "aoe_center": c, "aoe_radius": 3.0, "zone_age": 2.0, "zone_duration": 4.0})
	t.eq(b.hp, 1554, "earlier tick: hits")
	b.apply_status("MARK", {"duration": 8.0, "damage_taken_mult": 1.25})
	t.near(float(b.status_data("MARK")["duration"]), 5.6, 1e-6, "durations on her last 70%")
