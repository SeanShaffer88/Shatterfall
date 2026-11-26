extends Node
## Barks and the narrator (§2J, D43). One line at a time from data/barks.json:
## at most one every `spacing` seconds, shown for `duration`, skipping lines
## heard in this run or the last `repeat_runs` runs. Vespera's RUN_START lines
## are keyed to the hero who last beat her. A line waits (up to 2 s) while a
## telegraph sits under the bark area (`blocked_check`), then is dropped.

signal line_shown(speaker: String, text: String)

const MAX_WAIT := 2.0

## Set by the HUD: returns true while a telegraph overlaps the bark area.
var blocked_check: Callable
var hero_name: String = ""

var _clock: float = 0.0
var _last_time: float = -1e9
var _run_lines: Array[String] = []
var _room_clears: int = 0
var _queued: Dictionary = {}


func rules() -> Dictionary:
	return GameState.barks_data["rules"]


func begin_run(hero_id: String) -> void:
	hero_name = hero_id.capitalize()
	_run_lines.clear()
	_room_clears = 0
	_queued = {}
	_last_time = -1e9


## Files this run's lines into the save's history (newest first, `repeat_runs` kept).
func end_run() -> void:
	var hist: Array = GameState.bark_history
	hist.push_front(_run_lines.duplicate())
	while hist.size() > int(rules()["repeat_runs"]):
		hist.pop_back()
	_run_lines.clear()


func lines_for(speaker: String, trigger: String, variant: String) -> Array:
	var by_trigger: Dictionary = GameState.barks_data["lines"][speaker].get(trigger, {})
	if by_trigger.has(variant):
		return by_trigger[variant]
	return by_trigger.get("ANY", [])


## Picks and shows (or queues) a line. Returns the chosen text, or "" when
## spacing, the repeat filter or a missing trigger rules it out.
func say(speaker: String, trigger: String, variant: String = "ANY") -> String:
	if _clock - _last_time < float(rules()["spacing"]) or not _queued.is_empty():
		return ""
	var heard: Array = _run_lines.duplicate()
	for run_lines in GameState.bark_history:
		heard.append_array(run_lines)
	var pool: Array = []
	for line in lines_for(speaker, trigger, variant):
		if line not in heard:
			pool.append(line)
	if pool.is_empty():
		return ""
	var text: String = pool[GameState.rng_boons.randi_range(0, pool.size() - 1)]
	text = text.replace("{hero}", hero_name)
	_queued = {"speaker": speaker, "text": text, "wait": MAX_WAIT}
	_try_show()
	return text


## Every `room_clear_every`-th room clear, the Reliquary may comment.
func room_cleared() -> void:
	_room_clears += 1
	if _room_clears % int(rules()["room_clear_every"]) == 0:
		say("RELIQUARY", "ROOM_CLEAR")


func last_shown_time() -> float:
	return _last_time


func clock() -> float:
	return _clock


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	_clock += delta
	if not _queued.is_empty():
		_queued["wait"] -= delta
		if _queued["wait"] <= 0.0:
			_queued = {}
		else:
			_try_show()


func _try_show() -> void:
	if blocked_check.is_valid() and blocked_check.call():
		return
	var q := _queued
	_queued = {}
	_last_time = _clock
	_run_lines.append(q["text"])
	line_shown.emit(q["speaker"], q["text"])
