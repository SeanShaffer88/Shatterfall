extends RefCounted
## Gate 5: the Hub — cards, Stage Briefing, Forge tome (AD8, D13, D16–D20),
## dais glow (AD9), the evolution moment (AD10), windows (D42) and the full
## brief → commit → run → summary → hub loop with no orphaned state.

const STAGE := "stage_01_sunken_nave"
const HUB_SCENE := preload("res://scenes/main/MainHub.tscn")

var hub: MainHub
var sim: RunSim
var lines: Array = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _on_line(speaker: String, text: String) -> void:
	lines.append([speaker, text])


func before_each() -> void:
	SaveManager.save_path = RunSim.SAVE
	EchoDirector.echo_dir = RunSim.ECHOES
	GameState.reset_profile()
	BarkDirector.begin_run("BRUTE")       # fresh spacing for each test
	lines.clear()
	BarkDirector.line_shown.connect(_on_line)


func after_each() -> void:
	BarkDirector.line_shown.disconnect(_on_line)
	if is_instance_valid(hub):
		hub.free()
	hub = null
	if sim != null:
		sim.dispose()
		sim = null
	GameState.reset_profile()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	EchoDirector.echo_dir = EchoDirector.DEFAULT_DIR


func _hub() -> MainHub:
	hub = HUB_SCENE.instantiate()
	_tree().root.add_child(hub)
	return hub


func test_hero_cards_and_grudge_warning(t: TestContext) -> void:
	GameState.record_victory(STAGE, "BRUTE", true)
	var h := _hub()
	var brute := h.hero_card("BRUTE")
	t.eq([brute["weapon"], brute["stage"], brute["level"], brute["atk"]], ["Ashen Cleaver", 1, 1, 20], "weapon, stage, level, ATK")
	t.ok(brute["star"], "Brute's star shown")
	t.eq(brute["grudge"], "Vespera adapted to you: Spiked Carapace", "grudge warning on the last clearer's card")
	t.ok(brute["tip"] != "", "with a counter tip")
	t.eq(h.hero_card("MAGI")["grudge"], "", "no warning on the other cards")
	t.contains(h.ui.cards["BRUTE"].text, "Spiked Carapace", "card UI shows it")


func test_stage_briefing(t: TestContext) -> void:
	var h := _hub()
	var b := h.briefing("ROGUE")
	t.eq(b["stage"], "The Sunken Nave", "stage name")
	t.contains(b["hazards"], "spike traps in Room 3", "hazards")
	t.eq(b["stars"].size(), 3, "all three star conditions")
	t.contains(b["stars"][1]["condition"], "60 dagger hits", "Close Work condition in plain English")
	t.eq(b["echo_text"], "No echoes yet — clear this stage with another hero", "first-run message (§2B)")
	t.eq(b["adaptation"], "None yet", "no adaptation before the first clear")
	EchoDirector.begin_recording(STAGE, "MAGI")
	EchoDirector.record(0, 0, 1.0, Vector3.ZERO, Vector3.ONE, "GRAVITY_WELL")
	EchoDirector.record(0, 0, 2.0, Vector3.ZERO, Vector3.ONE, "SHATTER_NOVA")
	EchoDirector.commit_victory("lorelight_rod")
	b = h.briefing("ROGUE")
	t.eq(b["echo_text"], "Echoes ready: Magi (2 casts)", "the other heroes' recorded echoes")
	t.eq(h.briefing("MAGI")["echo_text"], "No echoes yet — clear this stage with another hero", "a hero never sees its own")
	for f in DirAccess.get_files_at(RunSim.ECHOES):
		DirAccess.remove_absolute(RunSim.ECHOES + "/" + f)


func test_forge_locked_until_first_boss_kill(t: TestContext) -> void:
	var h := _hub()
	var w := GameState.grant_drop({"weapon_class": "GREATAXE", "rarity": 1, "level": 1})
	t.ok(h.forge_locked(), "locked before Vespera falls (D13)")
	var r := h.absorb(w.uid)
	t.ok(not r["ok"], "absorb refused")
	t.contains(r["error"], "The Forge wakes once Vespera falls", "locked tooltip text")
	t.eq(h.ui.forge_button.text, "Forge (locked)", "button shows locked")
	GameState.record_victory(STAGE, "BRUTE", false)
	h.ui.refresh()
	t.ok(not h.forge_locked(), "unlocked after the first boss kill")
	t.ok(h.absorb(w.uid)["ok"], "absorb works")


func test_hub_actions_match_the_core_forge(t: TestContext) -> void:
	GameState.forge_unlocked = true
	var f1 := GameState.grant_drop({"weapon_class": "GREATAXE", "rarity": 2, "level": 1})
	var f2 := GameState.grant_drop({"weapon_class": "STAFF", "rarity": 3, "level": 1})
	var mirror := Inventory.new()
	t.eq(mirror.load_dict(GameState.inventory.to_dict()), "", "mirror inventory")
	var core_absorb := GameState.forge.absorb(mirror, mirror.main_for("BRUTE", "GREATAXE").uid, f1.uid)
	var core_salvage := GameState.forge.salvage(mirror, f2.uid)
	var h := _hub()
	var ui_absorb := h.absorb(f1.uid)
	var ui_salvage := h.salvage(f2.uid)
	t.eq(ui_absorb["xp_gained"], core_absorb["xp_gained"], "same XP as the core function")
	t.eq(GameState.inventory.main_for("BRUTE", "GREATAXE").to_dict(), mirror.main_for("BRUTE", "GREATAXE").to_dict(), "same main weapon afterwards")
	t.eq([ui_salvage["shard_id"], ui_salvage["shards"]], [core_salvage["shard_id"], core_salvage["shards"]], "same salvage result")
	t.eq(GameState.inventory.shards, mirror.shards, "same shards")
	t.eq(GameState.glass, 1, "salvage also gives 1 Glass (D42)")
	t.ok(SaveManager.has_save(), "Forge actions are saved")


func test_salvage_only_items_are_listed(t: TestContext) -> void:
	GameState.forge_unlocked = true
	GameState.grant_drop({"weapon_class": "GREATAXE", "rarity": 1, "level": 1})
	GameState.grant_drop({"weapon_class": "STAFF", "rarity": 1, "level": 1})
	var h := _hub()
	var items := h.forge_items()
	t.eq(items["absorbable"].size(), 1, "the Greataxe can be absorbed by the Brute")
	t.eq(items["salvage_only"].size(), 1, "the Staff is 'Not usable — salvage only' (D5)")


func test_at_cap_absorb_warns_first(t: TestContext) -> void:
	GameState.forge_unlocked = true
	var main := GameState.inventory.main_for("BRUTE", "GREATAXE")
	main.level = 10
	var f := GameState.grant_drop({"weapon_class": "GREATAXE", "rarity": 1, "level": 1})
	var h := _hub()
	var r := h.absorb(f.uid)
	t.ok(not r["ok"] and r["needs_confirm"], "first tap warns")
	t.eq(r["discard"], 45, "says how much XP would be lost")
	t.ok(GameState.inventory.get_weapon(f.uid) != null, "nothing absorbed yet")
	t.ok(h.absorb(f.uid)["ok"], "second tap confirms")
	t.eq(main.crit_stacks + main.atk_stacks + main.hp_stacks, 1, "sub-stat still granted")


func test_runes_track_recipe_progress(t: TestContext) -> void:
	GameState.forge_unlocked = true
	var main := GameState.inventory.main_for("MAGI", "STAFF")
	var h := _hub()
	h.select_hero("MAGI")
	var r := h.rune_state()
	t.eq([r["level"], r["shards"], r["available"]], [false, false, false], "Stage 2 runes dark")
	main.level = 5
	t.eq(h.rune_state()["level"], true, "level rune ignites at level 5")
	GameState.inventory.add_shards("STAFF_SHARD", 15)
	r = h.rune_state()
	t.eq([r["shards"], r["available"], r["needs_essence"]], [true, true, false], "all Stage 2 runes lit")
	main.evo_stage = 2
	main.level = 10
	GameState.inventory.add_shards("STAFF_SHARD", 25)
	r = h.rune_state()
	t.ok(r["needs_essence"] and not r["essence"] and r["stage3_orb"], "Stage 3: essence rune dark, reliquary orb shown")
	GameState.inventory.add_essence("VESPERA_ESSENCE", 1)
	t.ok(h.rune_state()["available"], "essence rune lights: ready")


func test_dais_glow_and_evolution_moment(t: TestContext) -> void:
	GameState.forge_unlocked = true
	var main := GameState.inventory.main_for("BRUTE", "GREATAXE")
	var h := _hub()
	var g := h.dais_glow()
	t.eq(g["stage"], 1, "Base stage")
	t.near(g["energy"], MainHub.DAIS_GLOW[1], 1e-5, "Base: dim smoky glow (AD9)")
	t.ok(g["color"].is_equal_approx(MainHub.SMOKY), "smoky colour")
	main.level = 5
	GameState.inventory.add_shards("GREATAXE_SHARD", 15)
	var finished := []
	h.evolution_sequence_finished.connect(func(id: String) -> void: finished.append(id))
	t.ok(h.evolve()["ok"], "evolve")
	t.ok(h.is_sequence_playing(), "AD10 sequence starts")
	t.eq(h.dais_glow()["stage"], 1, "old glow until the wash")
	h.tick(0.5 + 0.35)
	t.ok(h.ui.wash.color.a > 0.5, "stained-glass wash")
	t.eq(h.dais_glow()["stage"], 2, "new weapon revealed inside the wash")
	h.tick(1.0)
	t.eq(finished, ["cinderheart_maul"], "sequence finished once")
	h.tick(2.0)
	t.eq(finished.size(), 1, "never fires twice for one evolution")
	g = h.dais_glow()
	t.near(g["energy"], MainHub.DAIS_GLOW[2], 1e-5, "Stage 2: brighter")
	t.ok(g["color"].is_equal_approx(MainHub.CLASS_COLORS["GREATAXE"]), "in the class colour")
	t.eq(lines.size(), 1, "first evolution: the narrator speaks")
	t.eq(lines[0][0], "RELIQUARY", "Reliquary line")
	main.evo_stage = 3
	h.select_hero("BRUTE")
	t.near(h.dais_glow()["energy"], MainHub.DAIS_GLOW[3], 1e-5, "Stage 3: full radiant bloom")


func test_window_restoration_in_the_hub(t: TestContext) -> void:
	var h := _hub()
	t.ok(h.ui.restore_button.disabled, "can't restore without Glass")
	t.near(h.window_energy(0), 0.05, 1e-6, "Lantern Window dark")
	GameState.glass = 25
	h.ui.refresh()
	t.ok(not h.ui.restore_button.disabled, "enough Glass")
	t.contains(h.ui.window_label.text, "Room-clear heal rises from 15% to 20%", "next unlock in plain English")
	t.ok(h.restore_window()["ok"], "restored")
	t.near(h.window_energy(0), 2.5, 1e-6, "lit")
	t.near(h.window_energy(1), 0.05, 1e-6, "the next stays dark")
	t.eq(lines[-1][0], "RELIQUARY", "the Reliquary remarks on it")
	t.eq(int(SaveManager.read_json(RunSim.SAVE)["data"]["profile"]["windows_restored"]), 1, "saved")


func test_brief_commit_run_summary_hub_loop(t: TestContext) -> void:
	for ending in ["VICTORY", "DEFEAT", "ABANDONED"]:
		GameState.reset_profile()
		var h := _hub()
		h.select_hero("ROGUE")
		h.commit_run(false)
		t.eq(GameState.active_hero, "ROGUE", "%s: committed one hero" % ending)
		sim = RunSim.new(_tree(), "ROGUE", 3, "", false)
		h.free()
		hub = null
		sim.clear_room()
		match ending:
			"VICTORY":
				sim.activate_boss()
				sim.kill_boss()
			"DEFEAT":
				sim.hero.take_damage(9999)
			_:
				sim.run.abandon()
		t.eq(sim.run.result, ending, ending)
		sim.run.prepare_return()
		t.ok(not _tree().paused, "%s: unpaused" % ending)
		t.near(Engine.time_scale, 1.0, 1e-9, "%s: no hit-stop left behind" % ending)
		t.eq(GameState.active_hero, "", "%s: no active hero left behind" % ending)
		t.eq(EchoDirector.recorded().size(), 0, "%s: no echo buffer left behind" % ending)
		var before := JSON.stringify(GameState.to_save_dict(), "", true)
		GameState.reset_profile()
		t.eq(SaveManager.load_profile(), "", "%s: save loads" % ending)
		t.eq(JSON.stringify(GameState.to_save_dict(), "", true), before, "%s: saved state is complete" % ending)
		var back := _hub()                    # the Hub loads on the state the run left behind
		t.eq(back.forge_locked(), ending != "VICTORY", "%s: Forge state carried back to the Hub" % ending)
		t.ok(GameState.glass >= 3, "%s: Glass carried back" % ending)
		t.eq(back.selected_hero, "BRUTE", "%s: Hub opens with no hero committed" % ending)
		back.free()
		hub = null
		sim.dispose()
		sim = null
