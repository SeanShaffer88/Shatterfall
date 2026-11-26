class_name EchoPlayer
extends Node
## Plays the other two heroes' recorded Echoes during a run (§2B; D35, D36, D41).
## For the live (room, wave), from `t − 1.0` s it looks for a target (every
## tick until one appears) and shows a cyan cue; at `t` a SpectralEcho casts. Smart snap: the nearest living enemy within
## 3.5 m of the recorded target point, else the nearest in the room within the
## skill's reach of the recorded position, else the event is skipped. At most
## 2 Echo actors at once (AD12): extras wait up to 1.5 s, then drop. Events
## whose wave ends first drop. During a cue the player may conduct the Echo:
## a tap moves its cast up to 6 m (once). Driven by DungeonRun.tick.

signal cue_shown(event: Dictionary)
signal echo_cast(event: Dictionary, actor: SpectralEcho)
signal event_dropped(event: Dictionary, reason: String)
signal conducted(event: Dictionary)

const CUE_TIME := 1.0
const SNAP_RADIUS := 3.5
const MAX_ACTORS := 2
const MAX_WAIT := 1.5
const CONDUCT_RANGE := 6.0
const CUE_RADIUS := 1.0
const CUE_CYAN := Color("#5FD4E6")
const CONDUCT_GOLD := Color("#E8C45F")
## Fallback reach (m) from the recorded hero position, per skill (§2D).
const REACH := {
	"LEAP_SLAM": 5.0, "RENDING_ROAR": 6.0, "VORTEX_CLEAVE": 7.0, "SHATTER_NOVA": 4.0,
	"GRAVITY_WELL": 8.0, "SHATTER_MARK": 10.5, "ADAPTIVE_BARRAGE": 10.5,
}
## Skills whose Echo stands where the hero stood (ranged/targeted); the rest
## appear at the resolved point.
const FROM_RECORDED_POSITION := ["ADAPTIVE_BARRAGE", "SHATTER_MARK", "GRAVITY_WELL"]

enum State { PENDING, CUE, WAITING, DONE, DROPPED }

var run: DungeonRun
var events: Array[Dictionary] = []
var actors: Array[SpectralEcho] = []


func setup(owner_run: DungeonRun, recorded: Array[Dictionary]) -> void:
	run = owner_run
	events.clear()
	for ev in recorded:
		var e := ev.duplicate()
		e["state"] = State.PENDING
		e["conducted"] = false
		e["wait"] = 0.0
		e["point"] = Vector3.ZERO
		e["target_node"] = null
		e["cue"] = null
		events.append(e)


## Visible Echo actors (AD12 cap); a faded Echo finishing a zone doesn't count.
func live_actors() -> Array[SpectralEcho]:
	var out: Array[SpectralEcho] = []
	for a in actors:
		if is_instance_valid(a) and not a.is_queued_for_deletion() and a.visible:
			out.append(a)
	actors = out
	return out


func tick(delta: float, room: int, wave: int, elapsed: float) -> void:
	for e in events:
		if e["state"] in [State.DONE, State.DROPPED] or e["room"] != room or e["wave"] != wave:
			continue
		match e["state"]:
			State.PENDING:
				if elapsed >= float(e["t"]) - CUE_TIME - 1e-9:
					_resolve(e, elapsed >= float(e["t"]) - 1e-9)
			State.CUE:
				if elapsed >= float(e["t"]) - 1e-9:
					if live_actors().size() < MAX_ACTORS:
						_cast(e)
					else:
						e["state"] = State.WAITING
						e["wait"] = MAX_WAIT
			State.WAITING:
				e["wait"] -= delta
				if live_actors().size() < MAX_ACTORS:
					_cast(e)
				elif e["wait"] <= 0.0:
					_drop(e, "no_slot")


## The wave ended before these events could fire (D35).
func on_wave_ended(room: int, wave: int) -> void:
	for e in events:
		if e["room"] == room and e["wave"] == wave and e["state"] in [State.PENDING, State.CUE, State.WAITING]:
			_drop(e, "wave_ended")


func _anchor(room: int) -> Vector3:
	return run.stage.echo_anchor(room).global_position


## Looks for a target from `t − 1.0` on; with none yet the event stays pending
## and keeps looking every tick, and is skipped only if there is still none at
## `t` (`final`). The cue opens the moment a target is found.
func _resolve(e: Dictionary, final: bool) -> void:
	var tree := run.get_tree()
	var target_world: Vector3 = _anchor(e["room"]) + e["target"]
	var pos_world: Vector3 = _anchor(e["room"]) + e["pos"]
	var pick: Node3D = Combat.nearest_enemy(tree, target_world, SNAP_RADIUS)
	if pick == null:
		var best := INF
		var rect := run.stage.room_rect(e["room"])
		for enemy in Combat.living_enemies(tree):
			if not rect.has_point(Vector2(enemy.global_position.x, enemy.global_position.z)):
				continue
			var d := Combat.flat_distance(pos_world, enemy.global_position)
			if d <= float(REACH.get(e["skill"], 6.0)) and d < best:
				best = d
				pick = enemy
	if pick == null:
		if final:
			_drop(e, "no_target")
		return
	e["target_node"] = pick
	e["point"] = Combat.flat(pick.global_position)
	e["origin"] = Combat.flat(pos_world)
	e["state"] = State.CUE
	var cue := _make_cue()
	run.stage.add_child(cue)
	cue.global_position = e["point"] + Vector3(0, 0.04, 0)
	e["cue"] = cue
	cue_shown.emit(e)


## Moves the nearest live cue's cast to `world_point` (clamped to 6 m), once.
## Returns true when a cue was conducted (D41).
func conduct(world_point: Vector3) -> bool:
	var best: Dictionary = {}
	var best_d := INF
	for e in events:
		if e["state"] in [State.CUE, State.WAITING] and not e["conducted"]:
			var d := Combat.flat_distance(world_point, e["point"])
			if d < best_d:
				best_d = d
				best = e
	if best.is_empty():
		return false
	var to := Combat.flat(world_point - best["point"])
	if to.length() > CONDUCT_RANGE:
		to = to.normalized() * CONDUCT_RANGE
	best["point"] = Combat.flat(best["point"]) + to
	best["conducted"] = true
	best["target_node"] = null
	if is_instance_valid(best["cue"]):
		best["cue"].global_position = best["point"] + Vector3(0, 0.04, 0)
		(best["cue"].material_override as StandardMaterial3D).albedo_color = Color(CONDUCT_GOLD, 0.8)
	conducted.emit(best)
	return true


func has_live_cue() -> bool:
	for e in events:
		if e["state"] in [State.CUE, State.WAITING]:
			return true
	return false


func _cast(e: Dictionary) -> void:
	var point: Vector3 = e["point"]
	if not e["conducted"] and is_instance_valid(e["target_node"]) and not e["target_node"].is_queued_for_deletion() and e["target_node"].is_alive():
		point = Combat.flat(e["target_node"].global_position)
	var actor := SpectralEcho.new()
	actor.setup(e["hero"], e["skill"], e["mode"], run.hero)
	run.stage.add_child(actor)
	actor.global_position = e["origin"] if e["skill"] in FROM_RECORDED_POSITION else point
	actors.append(actor)
	_clear_cue(e)
	e["state"] = State.DONE
	var target: Node3D = null
	if not e["conducted"] and is_instance_valid(e["target_node"]) and not e["target_node"].is_queued_for_deletion():
		target = e["target_node"]
	actor.cast(point, target)
	echo_cast.emit(e, actor)


func _drop(e: Dictionary, reason: String) -> void:
	_clear_cue(e)
	e["state"] = State.DROPPED
	event_dropped.emit(e, reason)


func _clear_cue(e: Dictionary) -> void:
	if is_instance_valid(e["cue"]):
		e["cue"].queue_free()
	e["cue"] = null


## AD6: the cue is cyan, never the AD7 crimson-white, so it can't read as danger.
func _make_cue() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = "EchoCue"
	var ring := TorusMesh.new()
	ring.inner_radius = CUE_RADIUS * 0.8
	ring.outer_radius = CUE_RADIUS
	m.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(CUE_CYAN, 0.8)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_to_group("echo_cues")
	return m
