extends RefCounted
## Gate 5: Restore the Reliquary (§2I, D42) — Glass economy, window order,
## costs, and every window's unlock changing its rule.

const STAGE := "stage_01_sunken_nave"

var sim: RunSim


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	SaveManager.save_path = RunSim.SAVE
	GameState.reset_profile()


func after_each() -> void:
	if sim != null:
		sim.dispose()
		sim = null
	GameState.reset_profile()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH


func test_glass_from_rooms_boss_and_salvage(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "BRUTE", 3)
	sim.clear_room()
	t.eq(GameState.glass, 3, "+3 per room clear")
	t.eq(int(sim.saved()["profile"]["glass"]), 3, "saved with the room's drops (D29)")
	sim.activate_boss()
	sim.kill_boss()
	t.eq(GameState.glass, 3 * 4 + 10, "4 rooms + Vespera = 22")
	t.eq(sim.run.summary["glass"], 22, "summary shows Glass gathered")
	var spare := GameState.grant_drop({"weapon_class": "STAFF", "rarity": 1, "level": 1})
	t.ok(GameState.salvage(spare.uid)["ok"], "salvage")
	t.eq(GameState.glass, 23, "+1 per salvage")


func test_glass_is_kept_on_death(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 4)
	sim.clear_room()
	sim.enter_next_room()
	sim.hero.take_damage(9999)
	t.eq(sim.run.result, "DEFEAT", "died")
	t.eq(GameState.glass, 3, "Glass from cleared rooms kept (D42)")
	t.eq(int(sim.saved()["profile"]["glass"]), 3, "and saved")


func test_windows_restore_in_order_with_enough_glass(t: TestContext) -> void:
	t.eq(GameState.next_window()["id"], "LANTERN", "Lantern Window first")
	GameState.glass = 19
	var r := GameState.restore_next_window()
	t.ok(not r["ok"], "19 Glass is not enough for 20")
	t.contains(r["error"], "needs 20 Glass", "plain-English reason")
	GameState.glass = 20
	t.ok(GameState.restore_next_window()["ok"], "20 Glass restores it")
	t.eq([GameState.glass, GameState.windows_restored], [0, 1], "Glass spent, one window")
	t.eq(GameState.next_window()["id"], "CHOIR", "order enforced: Choir next")
	GameState.glass = 1000
	for i in 4:
		GameState.restore_next_window()
	t.eq(GameState.next_window()["id"], "VESPER", "five restored, Vesper Window last")
	r = GameState.restore_next_window()
	t.ok(not r["ok"], "the last window also needs a Vespera essence")
	GameState.inventory.add_essence("VESPERA_ESSENCE", 1)
	t.ok(GameState.restore_next_window()["ok"], "restored with the essence")
	t.eq(GameState.inventory.essence_count("VESPERA_ESSENCE"), 0, "essence consumed")
	t.ok(GameState.reliquary_restored(), "the Reliquary is whole")
	t.ok(not GameState.restore_next_window()["ok"], "nothing left to restore")
	t.eq(GameState.glass, 1000 - (40 + 60 + 80 + 100 + 150), "costs 40/60/80/100/150")


func _restore(n: int) -> void:
	GameState.glass = 10000
	GameState.inventory.add_essence("VESPERA_ESSENCE", 1)
	for i in n:
		GameState.restore_next_window()


func test_each_unlock_changes_its_rule(t: TestContext) -> void:
	t.near(GameState.room_clear_heal(STAGE), 0.15, 1e-9, "base heal 15%")
	t.eq(GameState.echo_cap(), 2, "base Echo cap 2")
	t.eq(GameState.boon_offer_count(STAGE), 3, "base draft 3")
	t.near(GameState.loot_table(STAGE).room_drop_chance(), 0.6, 1e-9, "base drop 60%")
	var stage3 := GameState.forge.stage_entry("GREATAXE", 3)
	t.eq(GameState.forge.shard_cost(stage3), 40, "base Stage 3 cost 40")
	_restore(1)
	t.near(GameState.room_clear_heal(STAGE), 0.20, 1e-9, "Lantern: heal 20%")
	_restore(1)
	t.eq(GameState.echo_cap(), 3, "Choir: Echo cap 3")
	_restore(1)
	t.eq(GameState.boon_offer_count(STAGE), 4, "Ember: draft 4")
	_restore(1)
	t.near(GameState.loot_table(STAGE).room_drop_chance(), 0.7, 1e-9, "Ledger: drop 70%")
	_restore(1)
	t.eq(GameState.forge.shard_cost(stage3), 30, "Forge Window: Stage 3 costs 30")
	t.eq(GameState.forge.shard_cost(GameState.forge.stage_entry("GREATAXE", 2)), 15, "Stage 2 cost unchanged")


func test_unlocks_reach_the_run(t: TestContext) -> void:
	_restore(3)
	sim = RunSim.new(_tree(), "MAGI", 5, "", false)
	t.eq(EchoDirector.cap_per_wave, 3, "Choir Window raises the recording cap in a run")
	sim.hero.hp = 50
	sim.clear_room()
	t.eq(sim.hero.hp, 50 + roundi(110 * 0.20), "Lantern Window: 20% heal on room clear")
	sim.enter_next_room()
	sim.clear_room()
	t.eq(sim.run.draft_offers.size(), 4, "Ember Window: 4 boon offers")


func test_stage3_evolution_at_30_shards(t: TestContext) -> void:
	_restore(5)
	var axe := GameState.inventory.main_for("BRUTE", "GREATAXE")
	axe.level = 10
	axe.evo_stage = 2
	GameState.inventory.add_shards("GREATAXE_SHARD", 30)
	GameState.inventory.add_essence("VESPERA_ESSENCE", 1)
	t.ok(GameState.evolve(axe.uid)["ok"], "30 shards suffice after the Forge Window")
	t.eq(GameState.inventory.shard_count("GREATAXE_SHARD"), 0, "30 consumed")


func test_save_round_trip_and_old_saves(t: TestContext) -> void:
	_restore(2)
	GameState.glass = 17
	SaveManager.save_profile()
	GameState.reset_profile()
	t.eq(SaveManager.load_profile(), "", "load")
	t.eq([GameState.glass, GameState.windows_restored], [17, 2], "Glass and windows round-trip")
	t.eq(GameState.echo_cap(), 3, "unlocks re-applied on load")
	var d := GameState.to_save_dict()
	for k in ["glass", "windows_restored", "runs_started", "evolutions_done", "bark_history"]:
		d["profile"].erase(k)
	SaveManager.write_json_atomic(SaveManager.save_path, d)
	t.eq(SaveManager.load_profile(), "", "a Phase 1–4 save (no Glass fields) still loads")
	t.eq([GameState.glass, GameState.windows_restored], [0, 0], "missing fields start at zero")
	DirAccess.remove_absolute(SaveManager.save_path)
