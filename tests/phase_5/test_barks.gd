extends RefCounted
## Gate 5: barks and narrator (§2J, D43) — spacing, repeat filter, grudge-keyed
## selection, {hero} names, holding a line while a telegraph is under it.

var shown: Array = []
var sim: RunSim


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _on_line(speaker: String, text: String) -> void:
	shown.append([speaker, text])


func before_each() -> void:
	GameState.reset_profile()
	GameState.begin_run("ROGUE", 3)
	BarkDirector.begin_run("ROGUE")
	BarkDirector.blocked_check = Callable()
	BarkDirector.tick(100.0)
	shown.clear()
	BarkDirector.line_shown.connect(_on_line)


func after_each() -> void:
	BarkDirector.line_shown.disconnect(_on_line)
	BarkDirector.blocked_check = Callable()
	if sim != null:
		sim.dispose()
		sim = null
	GameState.reset_profile()


func test_data_meets_the_minimums(t: TestContext) -> void:
	var lines: Dictionary = GameState.barks_data["lines"]
	for trig in DataSchema.BARK_SPEAKERS["VESPERA"]:
		for variant in lines["VESPERA"][trig]:
			t.ok(lines["VESPERA"][trig][variant].size() >= 4, "Vespera %s/%s has ≥ 4 lines" % [trig, variant])
	for trig in DataSchema.BARK_SPEAKERS["RELIQUARY"]:
		t.ok(lines["RELIQUARY"][trig]["ANY"].size() >= 3, "Reliquary %s has ≥ 3 lines" % trig)
	for h in ["BRUTE", "ROGUE", "MAGI", "FIRST"]:
		t.ok(lines["VESPERA"]["RUN_START"].has(h), "RUN_START keyed for %s" % h)


func test_grudge_keyed_selection(t: TestContext) -> void:
	var line := BarkDirector.say("VESPERA", "RUN_START", "BRUTE")
	t.ok(line in GameState.barks_data["lines"]["VESPERA"]["RUN_START"]["BRUTE"], "a Brute-grudge line: %s" % line)
	t.eq(shown, [["VESPERA", line]], "shown")


func test_spacing_12s(t: TestContext) -> void:
	t.ok(BarkDirector.say("RELIQUARY", "ROOM_CLEAR") != "", "first line")
	BarkDirector.tick(11.9)
	t.eq(BarkDirector.say("RELIQUARY", "DEATH"), "", "nothing within 12 s")
	BarkDirector.tick(0.2)
	t.ok(BarkDirector.say("RELIQUARY", "DEATH") != "", "allowed after 12 s")
	t.eq(shown.size(), 2, "two lines shown")


func test_repeat_filter_within_run_and_across_runs(t: TestContext) -> void:
	var pool: Array = GameState.barks_data["lines"]["RELIQUARY"]["DEATH"]["ANY"]
	var heard := []
	for i in pool.size():
		heard.append(BarkDirector.say("RELIQUARY", "DEATH"))
		BarkDirector.tick(12.1)
	heard.sort()
	var sorted_pool := pool.duplicate()
	sorted_pool.sort()
	t.eq(heard, sorted_pool, "every line once before any repeats")
	t.eq(BarkDirector.say("RELIQUARY", "DEATH"), "", "all heard this run: silence, no repeat")
	BarkDirector.end_run()
	t.eq(GameState.bark_history.size(), 1, "run filed into history")
	BarkDirector.begin_run("ROGUE")
	BarkDirector.tick(13.0)
	t.eq(BarkDirector.say("RELIQUARY", "DEATH"), "", "heard in the last run: still filtered")
	for i in 3:
		BarkDirector.end_run()
		BarkDirector.begin_run("ROGUE")
	t.eq(GameState.bark_history.size(), 3, "history keeps the last 3 runs")
	BarkDirector.tick(13.0)
	t.ok(BarkDirector.say("RELIQUARY", "DEATH") != "", "after 3 quiet runs the lines return")


func test_hero_name_substitution(t: TestContext) -> void:
	var lines: Array = GameState.barks_data["lines"]["VESPERA"]["DEFEAT"]["ANY"]
	var templated: String = ""
	for l in lines:
		if "{hero}" in l:
			templated = l
	for l in lines:
		if l != templated:
			GameState.bark_history.append([l])
	var line := BarkDirector.say("VESPERA", "DEFEAT")
	t.eq(line, templated.replace("{hero}", "Rogue"), "{hero} becomes the playing hero's name")


func test_waits_while_a_telegraph_is_under_the_line(t: TestContext) -> void:
	var blocked := [true]
	BarkDirector.blocked_check = func() -> bool: return blocked[0]
	var line := BarkDirector.say("RELIQUARY", "ROOM_CLEAR")
	t.ok(line != "", "line chosen")
	t.eq(shown.size(), 0, "held back while a telegraph is under it")
	BarkDirector.tick(1.0)
	t.eq(shown.size(), 0, "still held")
	blocked[0] = false
	BarkDirector.tick(0.1)
	t.eq(shown.size(), 1, "shown once clear")
	BarkDirector.tick(13.0)
	blocked[0] = true
	BarkDirector.say("RELIQUARY", "DEATH")
	BarkDirector.tick(2.1)
	blocked[0] = false
	BarkDirector.tick(0.1)
	t.eq(shown.size(), 1, "dropped after waiting 2 s")


func test_run_hud_detects_a_telegraph_under_the_bark(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "BRUTE", 2)
	var hud := sim.run.hud
	t.ok(not hud.telegraph_under_bark(), "nothing under the bark area yet")
	var cam := sim.run.camera_rig.camera
	var center := hud.bark_label.get_global_rect().get_center()
	var origin := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var ground := origin + dir * (-origin.y / dir.y)
	var tg := Telegraph.circle(1.0, 1.0)
	sim.run.stage.add_child(tg)
	tg.global_position = ground
	t.ok(hud.telegraph_under_bark(), "a telegraph projected under the bark line is detected")
	tg.free()


func test_room_clear_comment_every_third_clear(t: TestContext) -> void:
	for i in 2:
		BarkDirector.room_cleared()
	t.eq(shown.size(), 0, "not on clears 1–2")
	BarkDirector.room_cleared()
	t.eq(shown.size(), 1, "on the 3rd clear")
	t.eq(shown[0][0], "RELIQUARY", "the Reliquary speaks")


func test_first_run_line_and_vespera_reacts(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "MAGI", 6)
	t.eq(shown.size(), 1, "one line at run start")
	t.eq(shown[0][0], "RELIQUARY", "first run: the narrator speaks")
	t.ok(shown[0][1] in GameState.barks_data["lines"]["RELIQUARY"]["FIRST_RUN"]["ANY"], "a FIRST_RUN line")
	sim.activate_boss()
	BarkDirector.tick(13.0)
	sim.run.boss.take_hit({"damage": 801, "source": "TEST"})
	t.eq(shown[-1][0], "VESPERA", "Vespera reacts to phase 2")
	t.ok(shown[-1][1] in GameState.barks_data["lines"]["VESPERA"]["PHASE_TWO"]["ANY"], "a PHASE_TWO line")
