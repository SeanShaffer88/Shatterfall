extends RefCounted
## Gate 3: star conditions (D7, D9, D37) evaluated deterministically, persisted
## on victory only, and the Grudge installed by each clear (D11, §2H).

const STAGE := "stage_01_sunken_nave"

var sim: RunSim


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if sim != null:
		sim.dispose()
		sim = null


func _at_boss(hero_id: String, last_clearer: String = "") -> RunSim:
	sim = RunSim.new(_tree(), hero_id, 5, last_clearer)
	sim.activate_boss()
	sim.run.boss._attack_cd = 1e9      # keep the fight scripted
	sim.hero.attack_timer = 1e9
	return sim


func test_cleave_master_guard_uptime(t: TestContext) -> void:
	var s := _at_boss("BRUTE")
	for i in 120:
		if i < 66:
			s.hero.add_guard_stack()
		else:
			s.hero.guard = 0.0
		s.step()
	var p := s.run.star_progress()
	t.near(p["value"], 0.55, 0.02, "Guard up 55% of the fight")
	t.ok(p["met"], "≥ 50% earns Cleave Master")
	s.kill_boss()
	t.ok(GameState.has_star(STAGE, "BRUTE"), "star persisted on victory")
	t.ok(s.run.summary["star_earned"], "summary says earned")


func test_cleave_master_not_met_below_half(t: TestContext) -> void:
	var s := _at_boss("BRUTE")
	for i in 120:
		if i < 54:
			s.hero.add_guard_stack()
		else:
			s.hero.guard = 0.0
		s.step()
	t.ok(not s.run.star_progress()["met"], "45% is not enough")
	s.kill_boss()
	t.ok(not GameState.has_star(STAGE, "BRUTE"), "no star")
	t.contains(s.run.hud.summary_label.text, "progress: 45% / 50%", "summary shows progress")


func test_close_work_counts_only_live_dagger_hits_in_the_fight(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 5)
	sim.hero.hit_dealt.emit(null, {"source": "DAGGER_FLURRY"})
	t.eq(sim.run.dagger_hits, 0, "hits before the fight do not count")
	sim.activate_boss()
	sim.run.boss._attack_cd = 1e9
	for i in 59:
		sim.hero.hit_dealt.emit(sim.run.boss, {"source": "DAGGER_FLURRY"})
	sim.hero.hit_dealt.emit(sim.run.boss, {"source": "DAGGER_FLURRY", "is_echo": true})
	sim.hero.hit_dealt.emit(sim.run.boss, {"source": "BOW_ARROW"})
	t.ok(not sim.run.star_progress()["met"], "59 live dagger hits (echo and bow excluded)")
	sim.hero.hit_dealt.emit(sim.run.boss, {"source": "ADAPTIVE_BARRAGE", "mode": "DAGGERS"})
	t.ok(sim.run.star_progress()["met"], "60th: dagger-mode Barrage slices count")
	sim.kill_boss()
	t.ok(GameState.has_star(STAGE, "ROGUE"), "Close Work persisted")


func test_untouched_prism(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "MAGI", 5)
	sim.clear_room()
	sim.enter_next_room()
	sim.hero.take_damage(20)
	t.eq(sim.hero.hp, sim.hero.max_hp, "barrier-absorbed hit loses no HP")
	sim.clear_room()
	t.ok(sim.run.star_progress()["met"], "no HP lost in Room 2 → condition met")
	sim.dispose()
	sim = RunSim.new(_tree(), "MAGI", 5)
	sim.clear_room()
	sim.enter_next_room()
	sim.hero.barrier_up = false
	sim.hero.take_damage(5)
	sim.clear_room()
	t.ok(not sim.run.star_progress()["met"], "5 HP lost in Room 2 → not met")


func test_star_needs_a_clear_with_that_hero(t: TestContext) -> void:
	var s := _at_boss("ROGUE")
	for i in 70:
		s.hero.hit_dealt.emit(s.run.boss, {"source": "DAGGER_FLURRY"})
	t.ok(s.run.star_progress()["met"], "condition met")
	s.hero.take_damage(9999)
	t.eq(s.run.result, "DEFEAT", "but the hero died")
	t.ok(not GameState.has_star(STAGE, "ROGUE"), "no star without the clear (D7)")
	sim.dispose()
	var s2 := _at_boss("MAGI")
	s2.kill_boss()
	t.ok(not GameState.has_star(STAGE, "ROGUE"), "a Magi clear never awards the Rogue's star")


func test_victory_installs_grudge_and_flips_the_bias(t: TestContext) -> void:
	var s := _at_boss("BRUTE")
	t.eq(s.run.grudge_hero, "", "no grudge before the first clear")
	s.kill_boss()
	t.eq(s.run.result, "VICTORY", "victory")
	t.eq(GameState.get_last_clearing_hero(STAGE), "BRUTE", "Brute is the last clearer")
	t.eq(s.run.summary["adaptation"], "Spiked Carapace", "summary names the new adaptation")
	t.eq(s.run.summary["essence"], "VESPERA_ESSENCE", "Vespera essence granted")
	t.eq(GameState.inventory.essence_count("VESPERA_ESSENCE"), 1, "essence in the inventory")
	t.ok(GameState.forge_unlocked, "first boss kill unlocks the Forge (D13)")
	var last: Dictionary = s.run.summary["drops"][-1]
	t.eq(int(last["level"]), 2, "guaranteed level-2 boss weapon")
	var saved := s.saved()
	t.eq(saved["profile"]["last_clearing_hero"].get(STAGE, ""), "BRUTE", "grudge saved")
	sim.dispose()
	var s2 := _at_boss("MAGI", "BRUTE")
	t.eq(s2.run.boss.adaptation_id(), "SPIKED_CARAPACE", "next run faces Spiked Carapace")
	var w1 := GameState.loot_table(STAGE).class_weights("MAGI", s2.run.grudge_hero)
	s2.kill_boss()
	t.eq(GameState.get_last_clearing_hero(STAGE), "MAGI", "replaced, never stacked")
	t.eq(GameState.active_adaptation(STAGE)["id"], "RUNIC_DAMPENING", "Magi clear → Runic Dampening")
	var w2 := GameState.loot_table(STAGE).class_weights("MAGI", "MAGI")
	t.ok(w1["GREATAXE"] < w1["DAGGERS"], "after a Brute clear the Greataxe is not boosted")
	t.ok(w2["STAFF"] < w1["STAFF"], "after a Magi clear the Staff loses its boost")


func test_full_scripted_run_to_victory(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 9)
	var rooms_started := []
	sim.run.room_started.connect(func(r: int) -> void: rooms_started.append(r))
	sim.activate_boss()
	t.eq(rooms_started, [1, 2, 3], "walked Rooms 2–4 (Room 1 started before connecting)")
	t.eq(sim.hero.boons.size(), 1, "took one boon")
	sim.kill_boss()
	t.eq(sim.run.result, "VICTORY", "victory")
	t.ok(sim.run.hud.summary_panel.visible, "summary shown")
	t.contains(sim.run.hud.summary_label.text, "Vespera falls.", "summary headline")
	t.eq(GameState.clear_count(STAGE, "ROGUE"), 1, "clear recorded")
