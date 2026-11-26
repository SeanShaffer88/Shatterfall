class_name TrainingDummy
extends StaticBody3D
## Gray-box target that implements the Combat enemy contract. No AI and no
## attacks — real enemies arrive in Phase 3. Records hits for tests and
## optionally revives for manual feel testing.

signal hit_taken(hit: Dictionary)

@export var max_hp: int = 1000
@export var revive_after: float = -1.0   # < 0: stay dead

var hp: int
var hits: Array[Dictionary] = []
var statuses: Dictionary = {}   # id -> data (with "time_left")
var _dead_time: float = 0.0


func _ready() -> void:
	hp = max_hp
	add_to_group(Combat.ENEMY_GROUP)
	add_to_group(Combat.TICK_GROUP)
	collision_layer = Combat.LAYER_ENEMY
	collision_mask = 0
	if get_child_count() == 0:
		_build_graybox()


func _build_graybox() -> void:
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.5
	cyl.height = 1.6
	shape.shape = cyl
	shape.position.y = 0.8
	add_child(shape)
	var mesh_i := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.5
	mesh.height = 1.6
	mesh_i.mesh = mesh
	mesh_i.position.y = 0.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#2A2C33")
	mesh_i.material_override = mat
	add_child(mesh_i)


func is_alive() -> bool:
	return hp > 0


func take_hit(hit: Dictionary) -> void:
	if not is_alive():
		return
	hits.append(hit)
	hp = maxi(0, hp - int(hit.get("damage", 0)))
	hit_taken.emit(hit)


func total_damage() -> int:
	var sum := 0
	for h in hits:
		sum += int(h.get("damage", 0))
	return sum


func has_status(id: String) -> bool:
	return statuses.has(id)


func status_data(id: String) -> Dictionary:
	return statuses.get(id, {})


func apply_status(id: String, data: Dictionary) -> void:
	var d := data.duplicate()
	d["time_left"] = float(data.get("duration", 0.0))
	statuses[id] = d


func displace(offset: Vector3) -> void:
	global_position += Combat.flat(offset)


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	for id in statuses.keys():
		statuses[id]["time_left"] -= delta
		if statuses[id]["time_left"] <= 0.0:
			statuses.erase(id)
	if not is_alive() and revive_after >= 0.0:
		_dead_time += delta
		if _dead_time >= revive_after:
			_dead_time = 0.0
			hp = max_hp
