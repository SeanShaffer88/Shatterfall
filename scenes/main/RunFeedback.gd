class_name RunFeedback
extends Node3D
## Combat feedback for a run: floating damage numbers and hit-stop.
##   Numbers: warm white for hero hits, gold for crits, cyan for Echo hits
##   (AD6); rise 1.2 m and fade over 0.7 s; at most 24 alive (oldest recycled).
##   Hit-stop (D36): only heavy non-skill crits (a primary attack crit) dip
##   Engine.time_scale for 60 ms of real time. Every gameplay timer runs on
##   scaled delta, so the dip shifts nothing in game time.

const PRIMARY_SOURCES := ["CLEAVE", "DAGGER_FLURRY", "BOW_ARROW", "PRISM_BOLT"]
const MAX_NUMBERS := 24
const LIFE := 0.7
const RISE := 1.2
const HIT_STOP_SCALE := 0.2
const HIT_STOP_REAL := 0.06
const WARM := Color(1.0, 0.93, 0.85)
const CRIT_GOLD := Color("#E8C45F")
const ECHO_CYAN := Color("#5FD4E6")

var numbers: Array[Label3D] = []
var hit_stops: int = 0
var _stop_left: float = 0.0
var _last_usec: int = 0


func _ready() -> void:
	add_to_group(Combat.TICK_GROUP)
	_last_usec = Time.get_ticks_usec()


func on_hero_hit(target: Node3D, hit: Dictionary) -> void:
	if not is_instance_valid(target):
		return
	spawn_number(target.global_position, int(hit.get("damage", 0)), CRIT_GOLD if hit.get("crit", false) else WARM)
	if hit.get("crit", false) and not hit.get("is_echo", false) and str(hit.get("source", "")) in PRIMARY_SOURCES:
		start_hit_stop()


func on_echo_hit(target: Node3D, hit: Dictionary) -> void:
	if is_instance_valid(target):
		spawn_number(target.global_position, int(hit.get("damage", 0)), ECHO_CYAN)


func spawn_number(at: Vector3, amount: int, color: Color) -> Label3D:
	if numbers.size() >= MAX_NUMBERS:
		var oldest: Label3D = numbers.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var l := Label3D.new()
	l.text = str(amount)
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.outline_size = 12
	l.pixel_size = 0.01
	l.set_meta("age", 0.0)
	l.set_meta("base_y", at.y + 2.0)
	add_child(l)
	l.global_position = Vector3(at.x, at.y + 2.0, at.z)
	numbers.append(l)
	return l


func start_hit_stop() -> void:
	hit_stops += 1
	_stop_left = HIT_STOP_REAL
	Engine.time_scale = HIT_STOP_SCALE


## Real-time countdown (unaffected by the dip itself).
func real_tick(real_seconds: float) -> void:
	if _stop_left > 0.0:
		_stop_left -= real_seconds
		if _stop_left <= 0.0:
			end_hit_stop()


func end_hit_stop() -> void:
	_stop_left = 0.0
	Engine.time_scale = 1.0


func is_hit_stopped() -> bool:
	return _stop_left > 0.0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	real_tick((now - _last_usec) / 1_000_000.0)
	_last_usec = now


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	for l in numbers.duplicate():
		if not is_instance_valid(l) or l.is_queued_for_deletion():
			numbers.erase(l)
			continue
		var age: float = l.get_meta("age") + delta
		l.set_meta("age", age)
		l.position.y = float(l.get_meta("base_y")) + RISE * clampf(age / LIFE, 0.0, 1.0)
		l.modulate.a = 1.0 - clampf(age / LIFE, 0.0, 1.0)
		if age >= LIFE:
			numbers.erase(l)
			l.queue_free()


func _exit_tree() -> void:
	if _stop_left > 0.0:
		end_hit_stop()
