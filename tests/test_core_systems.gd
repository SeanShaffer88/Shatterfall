extends SceneTree
## Headless gate runner (D38). Runs every suite under res://tests/phase_N/ and
## exits 0 when all tests pass, 1 otherwise.
##
##   godot --headless --path . --import          # fresh clone only
##   godot --headless --path . -s res://tests/test_core_systems.gd
##
## Any engine or script error logged while a test runs fails that test, unless
## the test declared it with `t.expect_errors(n)`. A watchdog exits 1 if the run
## stalls, so a broken test can never hang CI.

const SUITE_ROOT := "res://tests"
const WATCHDOG_SECONDS := 120.0


## Captures errors logged while each test runs (Godot 4.5+ Logger API).
class ErrorCatcher extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var msg := rationale if rationale != "" else code
		_mutex.lock()
		errors.append("%s (%s:%d in %s)" % [msg, file.get_file(), line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array[String]:
		_mutex.lock()
		var out: Array[String] = []
		out.assign(errors)
		errors.clear()
		_mutex.unlock()
		return out


var _catcher := ErrorCatcher.new()


func _initialize() -> void:
	OS.add_logger(_catcher)
	create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	_run.call_deferred()


func _on_watchdog() -> void:
	printerr("WATCHDOG: test run exceeded %d s; aborting" % WATCHDOG_SECONDS)
	quit(1)


func _run() -> void:
	await process_frame  # let autoloads finish _ready()
	var startup_errors := _catcher.take()
	var passed := 0
	var failed := 0
	if not startup_errors.is_empty():
		failed += 1
		print("FAIL startup: errors while loading autoloads")
		for e in startup_errors:
			print("       - " + e)
	for path in _discover_suites():
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL %s: suite failed to load" % path)
			continue
		print("%s" % path.trim_prefix(SUITE_ROOT + "/"))
		var suite: Object = script.new()
		var names: Array[String] = []
		for m in suite.get_method_list():
			if str(m["name"]).begins_with("test_"):
				names.append(m["name"])
		names.sort()
		for test_name in names:
			var t := TestContext.new(test_name)
			if suite.has_method("before_each"):
				suite.call("before_each")
			_catcher.take()
			suite.call(test_name, t)
			var logged := _catcher.take()
			if suite.has_method("after_each"):
				suite.call("after_each")
			t.settle_errors(logged)
			if t.passed():
				passed += 1
				print("  ok    %s (%d checks)" % [test_name, t.checks])
			else:
				failed += 1
				print("  FAIL  %s" % test_name)
				for f in t.failures:
					print("        - " + f)
		if not (suite is RefCounted):
			suite.free()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 and passed > 0 else 1)


func _discover_suites() -> Array[String]:
	var out: Array[String] = []
	var phases := DirAccess.get_directories_at(SUITE_ROOT)
	phases.sort()
	for dir_name in phases:
		if not dir_name.begins_with("phase_"):
			continue
		var files := DirAccess.get_files_at("%s/%s" % [SUITE_ROOT, dir_name])
		files.sort()
		for f in files:
			if f.begins_with("test_") and f.ends_with(".gd"):
				out.append("%s/%s/%s" % [SUITE_ROOT, dir_name, f])
	return out
