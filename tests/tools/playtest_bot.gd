extends SceneTree
## Scripted windowed playtest (not part of the headless gate). Plays one hero
## through walk → stop-to-attack → skills 1-3 in the real DungeonRun scene on
## the real renderer, saving a screenshot at each beat and printing a log.
##
##   godot --path . --resolution 1200x540 -s res://tests/tools/playtest_bot.gd -- --hero=ROGUE --out=C:/tmp/shots

## A -s script compiles before autoloads exist, so everything that touches
## them (the scene, GameState) is resolved at runtime.
const RUN_SCENE_PATH := "res://scenes/main/DungeonRun.tscn"

var hero_id := "BRUTE"
var out_dir := "user://playtest"
var run: Node3D
var errors: Array[String] = []


class Catcher extends Logger:
	var sink: Array[String]
	func _init(target: Array[String]) -> void:
		sink = target
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_n: bool, _t: int, _b: Array[ScriptBacktrace]) -> void:
		sink.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
	func _log_message(_m: String, _e: bool) -> void:
		pass


func _initialize() -> void:
	OS.add_logger(Catcher.new(errors))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hero="):
			hero_id = arg.trim_prefix("--hero=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	create_timer(60.0).timeout.connect(func() -> void:
		printerr("playtest watchdog")
		quit(2))
	_play.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s_%s.png" % [out_dir, hero_id.to_lower(), label]
	root.get_texture().get_image().save_png(path)
	var h = run.hero
	var dealt := 0
	for d in ["DummyA", "DummyB", "DummyC"]:
		dealt += run.arena.get_node(d).total_damage()
	print("[%5.2fs] %-10s state=%s hp=%d/%d mode=%s guard=%.0f%% barrier=%s dealt=%d attacks_alive=%d -> %s" % [
		Time.get_ticks_msec() / 1000.0, label, ["MOVING", "STOPPED_ATTACKING", "CASTING_SKILL", "DASHING"][h.state], h.hp, h.max_hp,
		["BOW", "DAGGERS"][h.rogue_mode], h.guard_fraction() * 30.0, str(h.barrier_up), dealt,
		get_nodes_in_group("combat_tick").size() - 3, path.get_file()])


func _play() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(out_dir)
	var game_state := root.get_node("GameState")
	game_state.reset_profile()
	game_state.begin_run(hero_id, 42)
	run = (load(RUN_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(run)
	var input: Node = run.hero_input
	input.set_physics_process(false)    # the bot owns input_vector
	var hero = run.hero
	await _wait(0.6)
	await _shot("1_spawn")
	hero.input_vector = Vector2(0, -1)
	await _wait(1.1)
	await _shot("2_walking")
	hero.input_vector = Vector2.ZERO
	await _wait(1.6)
	await _shot("3_attacking")
	for i in 3:
		hero.skills.request(i)
		await _wait(0.22)
		await _shot("%d_skill%d_%s" % [4 + i, i + 1, hero.skills.skill_id(i).to_lower()])
		await _wait(0.9)
	await _wait(1.0)
	await _shot("7_after")
	print("errors logged: %d" % errors.size())
	for e in errors:
		print("  - " + e)
	quit(0 if errors.is_empty() else 1)
