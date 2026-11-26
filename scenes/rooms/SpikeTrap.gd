class_name SpikeTrap
extends Node3D
## Room 3 floor spikes (D33): a 2×2 m panel on a 4 s cycle —
## 1.0 s warning (AD7 telegraph) → 0.4 s active (10 dmg once per activation)
## → 2.6 s idle. Panels in group 1 run 2 s behind group 0. Hurts the hero only
## and only while `armed` (its room is in combat).

var trap_id: String = ""
var group: int = 0
var cfg: Dictionary = {}       # stages.json -> stage.traps.spike
var hero: HeroController
var armed: bool = false

var _t: float = 0.0
var _hit_this_cycle: bool = false
var _telegraph: Telegraph
var _spikes: MeshInstance3D


func setup(id: String, group_index: int, spike_cfg: Dictionary) -> void:
	trap_id = id
	group = group_index
	cfg = spike_cfg
	name = id
	add_to_group(Combat.TICK_GROUP)
	var size := float(cfg["size"])
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(size, 0.04, size)
	plate.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#3A3036")
	plate.material_override = mat
	add_child(plate)
	_spikes = MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(size * 0.9, 0.5, size * 0.9)
	_spikes.mesh = sm
	_spikes.position.y = 0.25
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color("#B8B0B4")
	_spikes.material_override = smat
	_spikes.visible = false
	add_child(_spikes)


func arm(on: bool) -> void:
	armed = on
	_t = 0.0
	_hit_this_cycle = false
	if not on:
		_clear_telegraph()
		_spikes.visible = false


func cycle_time() -> float:
	return fposmod(_t - float(cfg["group_offset"]) * group, float(cfg["cycle"]))


## "WARNING", "ACTIVE", "IDLE" or "OFF".
func phase_name() -> String:
	if not armed or _t < float(cfg["group_offset"]) * group:
		return "OFF" if not armed else "IDLE"
	var c := cycle_time()
	var warn := float(cfg["warning"])
	if c < warn:
		return "WARNING"
	if c < warn + float(cfg["active"]):
		return "ACTIVE"
	return "IDLE"


func covers(point: Vector3) -> bool:
	var half := float(cfg["size"]) * 0.5
	var d := Combat.flat(point - global_position)
	return absf(d.x) <= half and absf(d.z) <= half


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if not armed:
		return
	_t += delta
	var phase := phase_name()
	match phase:
		"WARNING":
			_spikes.visible = false
			if _telegraph == null:
				_hit_this_cycle = false
				_telegraph = Telegraph.rect(float(cfg["size"]), float(cfg["size"]), float(cfg["warning"]))
				add_child(_telegraph)
			_telegraph.elapsed = cycle_time()
			_telegraph.tick(0.0)
		"ACTIVE":
			_clear_telegraph()
			_spikes.visible = true
			if not _hit_this_cycle and is_instance_valid(hero) and covers(hero.global_position):
				_hit_this_cycle = true
				hero.take_damage(int(cfg["damage"]), {"source": "SPIKE_TRAP"})
		_:
			_clear_telegraph()
			_spikes.visible = false


func _clear_telegraph() -> void:
	if _telegraph != null:
		_telegraph.queue_free()
		_telegraph = null
