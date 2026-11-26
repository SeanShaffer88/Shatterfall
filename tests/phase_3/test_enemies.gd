extends RefCounted
## Gate 3: Crawler, Spitter and Bulwark behavior (§2E, D33), WEAKEN/STUN, and
## the AD7 alarm look of every telegraph.

var sim: CombatSim


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if sim != null:
		sim.dispose()
		sim = null


func _new(hero_id: String) -> CombatSim:
	sim = CombatSim.new(_tree(), hero_id)
	sim.hero.attack_timer = 1e9          # the hero holds fire so enemies live
	return sim


func _enemy(s: CombatSim, type: String, at: Vector3) -> EnemyBase:
	var e := EnemyBase.new()
	e.setup(type, GameState.stages_data["enemies"][type], s.hero, Rect2(-20, -20, 40, 40))
	s.root.add_child(e)
	e.global_position = at
	return e


func test_crawler_chases_and_hits_once_per_second(t: TestContext) -> void:
	var s := _new("ROGUE")
	var c := _enemy(s, "CRAWLER", Vector3(0, 0, 5))
	s.seconds(1.0)
	t.near(c.global_position.z, 3.0, 0.05, "chases at 2.0 m/s")
	s.step_until(func() -> bool: return s.hero.hp < 100, 240)
	t.eq(s.hero.hp, 92, "8 contact damage")
	s.seconds(0.9)
	t.eq(s.hero.hp, 92, "no second hit inside 1.0 s")
	s.seconds(0.15)
	t.eq(s.hero.hp, 84, "next hit after 1.0 s")


func test_weaken_and_stun(t: TestContext) -> void:
	var s := _new("ROGUE")
	var c := _enemy(s, "CRAWLER", Vector3(0, 0, 0.9))
	c.apply_status("WEAKEN", {"duration": 5.0, "damage_mult": 0.7})
	s.step()
	t.eq(s.hero.hp, 94, "Rending Roar: 8 × 0.7 = 5.6 → 6")
	var c2 := _enemy(s, "CRAWLER", Vector3(6, 0, 0))
	c2.apply_status("STUN", {"duration": 0.5})
	s.seconds(0.45)
	t.near(c2.global_position.x, 6.0, 1e-6, "stunned enemies do not move")
	s.seconds(0.2)
	t.ok(c2.global_position.x < 6.0, "moves again after the stun")


func test_spitter_keeps_its_band_and_fires(t: TestContext) -> void:
	var s := _new("ROGUE")
	var near := _enemy(s, "SPITTER", Vector3(0, 0, 3))
	var far := _enemy(s, "SPITTER", Vector3(12, 0, 0))
	s.seconds(3.0)                       # 4 m at 1.6 m/s takes 2.5 s
	t.ok(Combat.flat_distance(near.global_position, s.hero.global_position) >= 4.95, "retreats to ≥ 5 m")
	t.ok(Combat.flat_distance(far.global_position, s.hero.global_position) <= 8.05, "closes to ≤ 8 m")
	var shots := []
	var seen_glow := [false]
	for i in 240:
		s.step()
		if near._windup > 0.0 and near._body_mat.emission_energy_multiplier > 0.0:
			seen_glow[0] = true
		for n in s.root.get_children():
			if n is EnemyProjectile and n not in shots:
				shots.append(n)
	t.ok(seen_glow[0], "0.4 s wind-up glow telegraphs the shot")
	t.ok(not shots.is_empty(), "fires projectiles")
	if not shots.is_empty():
		t.near(shots[0].speed, 9.0, 1e-6, "9 m/s")
		t.eq(shots[0].collision_layer, Combat.LAYER_ENEMY_ATTACK, "enemy-attack layer")
	t.ok(s.hero.hp < 100 and (100 - s.hero.hp) % 6 == 0, "6 damage per shot (lost %d)" % (100 - s.hero.hp))


func test_amber_ward_reduces_projectile_damage(t: TestContext) -> void:
	var s := _new("ROGUE")
	Boons.apply(s.hero, GameState.stages_data["boons"][3])
	t.eq(s.hero.take_damage(6, {"projectile": true}), 5, "6 × 0.85 = 5.1 → 5")
	s.seconds(0.5)
	t.eq(s.hero.take_damage(6), 6, "melee unaffected")


func test_bulwark_frontal_shield(t: TestContext) -> void:
	var s := _new("BRUTE")
	var b := _enemy(s, "BULWARK", Vector3(0, 0, 4))
	b.facing = Vector3(0, 0, -1)
	b.take_hit({"damage": 22, "origin": Vector3(0, 0, 0)})
	t.eq(b.hp, 49, "hit from the front: 50% reduction (22 → 11)")
	b.take_hit({"damage": 22, "origin": Vector3(0, 0, 8)})
	t.eq(b.hp, 27, "hit from behind: full damage")
	b.take_hit({"damage": 22, "origin": Vector3(4, 0, 4)})
	t.eq(b.hp, 5, "90° to the side is outside ±60°: full damage")


func test_bulwark_bash_is_telegraphed_and_dodgeable(t: TestContext) -> void:
	var s := _new("ROGUE")
	var b := _enemy(s, "BULWARK", Vector3(0, 0, 1.5))
	b.facing = Vector3(0, 0, -1)
	s.step()
	t.ok(b._telegraph != null, "bash telegraph shown")
	t.eq(b._telegraph.shape, "cone", "frontal cone")
	s.seconds(0.85)
	t.eq(s.hero.hp, 88, "12 damage after the 0.8 s telegraph")
	s.seconds(0.5)
	s.step_until(func() -> bool: return b._telegraph != null, 240)
	s.hero.global_position = Vector3(0, 0, -3)
	s.seconds(0.85)
	t.eq(s.hero.hp, 88, "stepping out of reach dodges the bash")


func test_telegraphs_use_the_ad7_alarm_language(t: TestContext) -> void:
	var tg := Telegraph.circle(1.8, 1.0)
	t.ok(tg.is_in_group(Telegraph.GROUP), "in the telegraph group")
	var mat := tg.material_override as StandardMaterial3D
	t.eq(mat.render_priority, Telegraph.RENDER_PRIORITY, "drawn above decorative materials")
	t.ok(mat.no_depth_test, "never hidden by geometry")
	t.eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "unaffected by stained-glass lighting")
	var start := tg.alarm_color()
	t.ok(start.r > 0.8 and start.g < 0.25 and start.b < 0.3, "starts crimson")
	tg.tick(1.0)
	var end := tg.alarm_color()
	t.ok(end.r > 0.95 and end.g > 0.85 and end.b > 0.85, "ramps to white as the hit lands")
	t.ok(end.a > start.a, "grows more opaque")
	tg.free()
