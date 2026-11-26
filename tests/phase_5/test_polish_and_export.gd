extends RefCounted
## Gate 5: hit-stop (D36), damage numbers, AD13 assembly, and the export
## presets / project identity (D24, D40).

var sim: RunSim


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	Engine.time_scale = 1.0
	if sim != null:
		sim.dispose()
		sim = null


func test_hit_stop_only_on_heavy_non_skill_crits(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "BRUTE", 2)
	var fb := sim.run.feedback
	var target := Node3D.new()
	sim.run.stage.add_child(target)
	fb.on_hero_hit(target, {"damage": 44, "crit": true, "source": "LEAP_SLAM"})
	t.ok(not fb.is_hit_stopped(), "a skill crit never hit-stops")
	fb.on_hero_hit(target, {"damage": 22, "crit": false, "source": "CLEAVE"})
	t.ok(not fb.is_hit_stopped(), "a normal hit never hit-stops")
	fb.on_hero_hit(target, {"damage": 44, "crit": true, "source": "CLEAVE", "is_echo": true})
	t.ok(not fb.is_hit_stopped(), "an Echo hit never hit-stops")
	fb.on_hero_hit(target, {"damage": 44, "crit": true, "source": "CLEAVE"})
	t.ok(fb.is_hit_stopped(), "a primary-attack crit does")
	t.near(Engine.time_scale, RunFeedback.HIT_STOP_SCALE, 1e-6, "time scale dips")
	fb.real_tick(0.07)
	t.near(Engine.time_scale, 1.0, 1e-9, "restored after 60 ms of real time")
	fb.on_hero_hit(target, {"damage": 44, "crit": true, "source": "BOW_ARROW"})
	sim.hero.take_damage(9999)
	t.near(Engine.time_scale, 1.0, 1e-9, "the run ending always clears a dip")


func test_damage_numbers(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 3)
	var fb := sim.run.feedback
	var at := Node3D.new()
	sim.run.stage.add_child(at)
	var n1 := fb.spawn_number(Vector3.ZERO, 12, RunFeedback.WARM)
	fb.on_hero_hit(at, {"damage": 24, "crit": true, "source": "SHATTER_MARK"})
	fb.on_echo_hit(at, {"damage": 5})
	t.eq(fb.numbers.size(), 3, "three numbers")
	t.ok(fb.numbers[1].modulate.is_equal_approx(RunFeedback.CRIT_GOLD), "crits in gold")
	t.ok(fb.numbers[2].modulate.is_equal_approx(RunFeedback.ECHO_CYAN), "Echo hits in cyan (AD6)")
	var y0 := n1.position.y
	fb.tick(0.35)
	t.ok(n1.position.y > y0 and n1.modulate.a < 1.0, "rises and fades")
	fb.tick(0.4)
	t.eq(fb.numbers.size(), 0, "gone after 0.7 s")
	for i in 30:
		fb.spawn_number(Vector3.ZERO, i, RunFeedback.WARM)
	t.eq(fb.numbers.size(), RunFeedback.MAX_NUMBERS, "capped at 24 (oldest recycled)")


func test_echo_hits_show_cyan_numbers_in_a_run(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "BRUTE", 4)
	sim.step_until(func() -> bool: return sim.run.wave_live and not sim.run.alive_enemies().is_empty(), 300)
	sim.stun_all()
	sim.hero.attack_timer = 1e9
	var e0 := sim.run.alive_enemies()[0].global_position
	var evs: Array[Dictionary] = [{"hero": "MAGI", "room": 0, "wave": 0, "t": sim.run.wave_elapsed + 1.05, "pos": e0, "target": e0, "skill": "SHATTER_NOVA", "mode": ""}]
	sim.run.echo_player.setup(sim.run, evs)
	sim.seconds(1.1)
	var cyan := sim.run.feedback.numbers.filter(func(l: Label3D) -> bool:
		return Color(l.modulate.r, l.modulate.g, l.modulate.b).is_equal_approx(Color(RunFeedback.ECHO_CYAN.r, RunFeedback.ECHO_CYAN.g, RunFeedback.ECHO_CYAN.b)))
	t.ok(not cyan.is_empty(), "the Echo's Nova produced cyan numbers")


func test_room_assembles_before_its_first_wave(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "MAGI", 5)
	sim.clear_room()
	sim.enter_next_room()
	t.ok(sim.run.stage.is_assembling(1), "Room 2 assembles on entry (AD13)")
	var marked := [-1.0]
	sim.run.wave_spawning.connect(func(_r: int, _w: int, _p: Array) -> void:
		if marked[0] < 0.0:
			marked[0] = 1.0 if sim.run.stage.is_assembling(1) else 0.0)
	sim.seconds(1.0)
	t.eq(marked[0], 0.0, "assembly done before the first wave telegraph")


func test_export_presets_match_d24_d40(t: TestContext) -> void:
	var cfg := ConfigFile.new()
	t.eq(cfg.load("res://export_presets.cfg"), OK, "export_presets.cfg parses")
	t.eq(cfg.get_value("preset.0", "platform"), "Android", "Android preset")
	t.eq(cfg.get_value("preset.0.options", "package/unique_name"), "com.seanshaffer88.shatterfall", "package id (D24)")
	t.eq(cfg.get_value("preset.0.options", "version/name"), "0.1.0", "version (D24)")
	t.eq(cfg.get_value("preset.0.options", "version/code"), 1, "version code")
	t.eq(cfg.get_value("preset.0.options", "package/name"), "Shatterfall", "display name")
	t.eq([cfg.get_value("preset.0.options", "architectures/arm64-v8a"), cfg.get_value("preset.0.options", "architectures/armeabi-v7a"),
		cfg.get_value("preset.0.options", "architectures/x86"), cfg.get_value("preset.0.options", "architectures/x86_64")],
		[true, false, false, false], "arm64-v8a only (D40)")
	for k in ["keystore/debug", "keystore/release", "keystore/release_password"]:
		t.eq(cfg.get_value("preset.0.options", k), "", "%s not stored in the repo" % k)
	t.eq(cfg.get_value("preset.1", "platform"), "Windows Desktop", "Windows dev preset")
	t.eq(ProjectSettings.get_setting("display/window/handheld/orientation"), 4, "sensor-landscape")
	t.ok(ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc"), "ETC2/ASTC enabled for Android")
	t.eq(ProjectSettings.get_setting("application/config/icon"), "res://icon.svg", "project icon set")
	t.eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/main/MainHub.tscn", "the game opens in the Hub")


func test_no_signing_material_in_the_project(t: TestContext) -> void:
	var gi := FileAccess.get_file_as_string("res://.gitignore")
	for pat in ["*.keystore", "*.jks", "export_credentials.cfg", "/build/"]:
		t.contains(gi, pat, ".gitignore covers %s" % pat)
	var found := []
	var stack := ["res://"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for d in DirAccess.get_directories_at(dir):
			if not d.begins_with("."):
				stack.append(dir.path_join(d))
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".keystore") or f.ends_with(".jks"):
				found.append(dir.path_join(f))
	t.eq(found, [], "no keystore files in the project")
