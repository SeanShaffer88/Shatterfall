extends SceneTree
## Autopilot playthrough of a full Stage 1 run on the real renderer (not part of
## the headless gate). A naive player: walk into reach of the nearest enemy,
## stop to auto-attack, cast every skill when ready, walk through open doors,
## take the first boon. Logs run events and saves screenshots at key beats.
##
##   godot --path . --resolution 1200x540 -s res://tests/tools/run_bot.gd -- --hero=BRUTE --out=C:/tmp/run --speed=3

## A -s script compiles before autoloads exist: resolve them at runtime.
const RUN_SCENE_PATH := "res://scenes/main/DungeonRun.tscn"
const PHASE_NAMES := ["ROOM", "ROOM_CLEARED", "DRAFT", "BOSS_INTRO", "BOSS", "ENDED"]

var hero_id := "BRUTE"
var out_dir := "user://run_bot"
var speed := 3.0
var seed_value := 1
var run: Node3D
var errors: Array[String] = []
var _shots_taken := {}
var _start_ms := 0


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
		elif arg.begins_with("--speed="):
			speed = float(arg.trim_prefix("--speed="))
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		_log("WATCHDOG: run did not finish")
		_finish(2))
	_start.call_deferred()


func _game_time() -> float:
	return (Time.get_ticks_msec() - _start_ms) / 1000.0 * speed


func _log(msg: String) -> void:
	print("[%6.1fs] %s" % [_game_time(), msg])


func _start() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(out_dir)
	var gs := root.get_node("GameState")
	root.get_node("SaveManager").save_path = out_dir + "/bot_save.json"
	gs.reset_profile()
	gs.begin_run(hero_id, seed_value)
	run = (load(RUN_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(run)
	run.hero_input.set_physics_process(false)
	Engine.time_scale = speed
	_start_ms = Time.get_ticks_msec()
	run.room_started.connect(func(r: int) -> void: _log("room %d started (HP %d/%d)" % [r + 1, run.hero.hp, run.hero.max_hp]))
	run.wave_started.connect(func(r: int, w: int) -> void: _log("  room %d wave %d: %d enemies" % [r + 1, w + 1, run.alive_enemies().size()]))
	run.room_cleared.connect(func(r: int) -> void: _log("room %d cleared (HP %d/%d, drops so far %d)" % [r + 1, run.hero.hp, run.hero.max_hp, run.run_drops.size()]))
	run.draft_opened.connect(func(o: Array) -> void: _log("boon draft: %s" % ", ".join(o.map(func(b): return b["id"]))))
	run.boon_taken.connect(func(id: String) -> void: _log("took boon %s" % id))
	run.boss_activated.connect(func() -> void: _log("Vespera active (adaptation: '%s')" % run.boss.adaptation_id()))
	run.run_ended.connect(_on_end)
	physics_frame.connect(_drive)


var _next_status := 10.0


func _drive() -> void:
	if run == null or not is_instance_valid(run) or run.phase == 5:
		return
	var hero = run.hero
	if _game_time() >= _next_status:
		_next_status += 10.0
		var boss_txt := ""
		if run.boss != null and is_instance_valid(run.boss):
			boss_txt = " boss_hp=%d boss_dist=%.1f boss_attack=%s" % [run.boss.hp,
				hero.global_position.distance_to(run.boss.global_position), str(run.boss.current_attack.get("id", "-"))]
		_log("status phase=%s room=%d hp=%d state=%d pos=(%.1f,%.1f) vel=%.2f enemies=%d input=%s%s" % [
			PHASE_NAMES[run.phase], run.room + 1, hero.hp, hero.state, hero.global_position.x, hero.global_position.z,
			hero.velocity.length(), run.alive_enemies().size(), str(hero.input_vector), boss_txt])
	match run.phase:
		0, 4:
			_fight(hero)
			if run.phase == 0 and run.room == 0:
				_maybe_shot("1_room1_combat", run.alive_enemies().size() >= 3)
			if run.phase == 0 and run.room == 2:
				_maybe_shot("3_room3_traps", run.alive_enemies().size() >= 2)
			if run.phase == 4:
				_maybe_shot("4_boss_fight", run.boss.current_attack.size() > 0)
		1:
			# Line up on the corridor first (x≈0), then walk through it into the next room.
			var door_z: float = run.stage.door_z(run.room)
			var target: Vector3 = run.stage.room_center(run.room + 1)
			if absf(hero.global_position.x) > 0.6 and hero.global_position.z > door_z:
				target = Vector3(0, 0, hero.global_position.z)
			var to: Vector3 = target - hero.global_position
			hero.input_vector = Vector2(to.x, to.z).normalized()
		2:
			hero.input_vector = Vector2.ZERO
			if _maybe_shot("2_boon_draft", true):
				return
			run.pick_boon(0)
		3:
			hero.input_vector = Vector2.ZERO


func _fight(hero) -> void:
	var foe: Node3D = null
	var best := INF
	for e in run.alive_enemies():
		var d: float = hero.global_position.distance_to(e.global_position)
		if d < best:
			best = d
			foe = e
	if run.phase == 4 and is_instance_valid(run.boss) and run.boss.is_alive() and foe == null:
		foe = run.boss
		best = hero.global_position.distance_to(foe.global_position)
	if foe == null:
		hero.input_vector = Vector2.ZERO
		return
	var reach: float = hero._max_range() * 0.8
	if best > reach:
		var to: Vector3 = foe.global_position - hero.global_position
		hero.input_vector = Vector2(to.x, to.z).normalized()
	else:
		hero.input_vector = Vector2.ZERO
	for i in 3:
		hero.skills.request(i)


func _maybe_shot(label: String, condition: bool) -> bool:
	if not condition or _shots_taken.has(label):
		return false
	_shots_taken[label] = true
	_shot(label)
	return true


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s_%s.png" % [out_dir, hero_id.to_lower(), label]
	root.get_texture().get_image().save_png(path)
	_log("screenshot %s" % path.get_file())


func _on_end(summary: Dictionary) -> void:
	_log("RUN %s — hero HP %d/%d, drops %d, star %s (%s / %s), boons lost %s" % [
		summary["result"], run.hero.hp, run.hero.max_hp, summary["drops"].size(),
		"earned" if summary["star_earned"] else "not earned",
		str(snappedf(float(summary["star"]["value"]), 0.01)), str(summary["star"]["threshold"]),
		str(summary["boons_lost"])])
	await create_timer(0.5, true, false, true).timeout
	await _shot("5_summary")
	_finish(0)


func _finish(code: int) -> void:
	Engine.time_scale = 1.0
	print("errors logged: %d" % errors.size())
	for e in errors:
		print("  - " + e)
	quit(code if errors.is_empty() else 1)
