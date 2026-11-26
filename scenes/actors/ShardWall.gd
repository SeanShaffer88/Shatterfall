class_name ShardWall
extends StaticBody3D
## Vespera's phase-2 shard wall (§2E): 6 m × 0.6 m, raised 3 m from her toward
## the hero. 0.6 s AD7 rise telegraph (not solid yet), then 5 s solid: blocks
## hero movement (world collision layer) and every hero/echo projectile.

var cfg: Dictionary = {}       # stages.json -> boss.attacks.SHARD_WALL
var solid: bool = false
var _t: float = 0.0
var _telegraph: Telegraph
var _shape: CollisionShape3D
var _mesh: MeshInstance3D


func setup(wall_cfg: Dictionary) -> void:
	cfg = wall_cfg
	name = "ShardWall"
	collision_layer = 0
	collision_mask = 0
	add_to_group(Combat.TICK_GROUP)
	var size := Vector3(float(cfg["length"]), 3.0, float(cfg["thickness"]))
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	_shape.position.y = 1.5
	add_child(_shape)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	_mesh.mesh = bm
	_mesh.position.y = 1.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.85, 0.95, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = mat
	_mesh.visible = false
	add_child(_mesh)
	_telegraph = Telegraph.rect(size.x, size.z + 0.4, float(cfg["rise_telegraph"]))
	add_child(_telegraph)


## True when a projectile of `radius` at `point` overlaps the solid wall.
func blocks(point: Vector3, radius: float) -> bool:
	if not solid:
		return false
	var local := global_transform.affine_inverse() * point
	return absf(local.x) <= float(cfg["length"]) * 0.5 + radius \
		and absf(local.z) <= float(cfg["thickness"]) * 0.5 + radius


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if is_queued_for_deletion():
		return
	_t += delta
	var rise := float(cfg["rise_telegraph"])
	if not solid and _t >= rise:
		solid = true
		collision_layer = Combat.LAYER_WORLD
		add_to_group(Projectile.BLOCKER_GROUP)
		_mesh.visible = true
		if _telegraph != null:
			_telegraph.queue_free()
			_telegraph = null
	elif _telegraph != null:
		_telegraph.tick(delta)
	if _t >= rise + float(cfg["duration"]):
		queue_free()
