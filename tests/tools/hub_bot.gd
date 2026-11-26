extends SceneTree
## Windowed Hub walkthrough (not part of the headless gate): Hub → select a
## hero → restore a window → Forge (evolve, AD10 wash) → Enter the Nave →
## abandon → summary → Continue → back in the Hub. Saves screenshots and logs
## every engine error. Uses its own save and echo folder.
##
##   godot --path . --resolution 1200x540 -s res://tests/tools/hub_bot.gd -- --out=C:/tmp/hub

## A -s script compiles before autoloads exist: resolve them at runtime.
const HUB := "res://scenes/main/MainHub.tscn"

var out_dir := "user://hub_bot"
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
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		print("WATCHDOG")
		_done(2))
	_walk.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/hub_%s.png" % [out_dir, label]
	root.get_texture().get_image().save_png(path)
	print("screenshot ", path.get_file(), "  scene=", current_scene.name if current_scene else "none")


func _walk() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(out_dir)
	var gs := root.get_node("GameState")
	root.get_node("SaveManager").save_path = out_dir + "/bot_save.json"
	root.get_node("EchoDirector").echo_dir = out_dir + "/echoes"
	gs.reset_profile()
	gs.active_hero = ""
	change_scene_to_file(HUB)
	await _wait(0.8)
	var hub = current_scene
	await _shot("1_hub")
	hub.select_hero("ROGUE")
	await _wait(0.3)
	await _shot("2_rogue_selected")
	gs.glass = 25
	print("restore: ", hub.restore_window())
	await _wait(0.5)
	await _shot("3_window_restored")
	gs.record_victory("stage_01_sunken_nave", "BRUTE", true)
	hub.select_hero("BRUTE")
	var main = gs.inventory.main_for("BRUTE", "GREATAXE")
	main.level = 5
	gs.inventory.add_shards("GREATAXE_SHARD", 15)
	gs.grant_drop({"weapon_class": "GREATAXE", "rarity": 2, "level": 1})
	gs.grant_drop({"weapon_class": "STAFF", "rarity": 1, "level": 1})
	hub.ui.forge_panel.visible = true
	hub.ui.refresh()
	await _wait(0.4)
	await _shot("4_forge_tome")
	hub.ui.forge_panel.visible = false
	print("evolve: ", hub.evolve())
	await _wait(0.8)
	await _shot("5_evolution_wash")
	await _wait(1.2)
	await _shot("6_evolved_dais")
	print("card: ", hub.hero_card("BRUTE"))
	hub.select_hero("MAGI")
	hub.commit_run()
	await _wait(2.5)
	await _shot("7_in_run")
	var run = current_scene
	print("run scene: ", run.name, " hero: ", run.hero.hero_id)
	run.abandon()
	await _wait(0.5)
	await _shot("8_summary")
	run.restart()
	await _wait(1.0)
	await _shot("9_back_in_hub")
	print("back in hub: ", current_scene.name, " active_hero='", gs.active_hero, "' time_scale=", Engine.time_scale, " paused=", paused)
	_done(0)


func _done(code: int) -> void:
	print("errors logged: %d" % errors.size())
	for e in errors.slice(0, 15):
		print("  - " + e)
	quit(code if errors.is_empty() else 1)
