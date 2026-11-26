class_name Projectile
extends Area3D
## A hero projectile: a real Area3D with a SphereShape3D on the hero-attack layer.
## Straight (arrows) or homing (Prism Bolts, Barrage arrows). Hits the first
## living enemy it touches (center distance <= radius + Combat body radius),
## then frees itself; also frees after `max_distance`.

const ENEMY_BODY_RADIUS := 0.5
const HOMING_TURN_RATE := 9.0   # rad/s
const BLOCKER_GROUP := "projectile_blockers"   # nodes with blocks(point, radius) -> bool

var kind: String = ""
var speed: float = 20.0
var radius: float = 0.25
var max_distance: float = 12.0
var direction: Vector3 = Vector3.FORWARD
var homing_target: Node3D = null
var on_hit: Callable

var _travelled: float = 0.0


static func create(kind_id: String, from: Vector3, dir: Vector3, move_speed: float, reach: float, color: Color) -> Projectile:
	var p := Projectile.new()
	p.kind = kind_id
	p.name = "Projectile_" + kind_id
	p.speed = move_speed
	p.max_distance = reach
	p.direction = Combat.flat(dir).normalized() if Combat.flat(dir).length() > 0.001 else Vector3(0, 0, 1)
	p.collision_layer = Combat.LAYER_HERO_ATTACK
	p.collision_mask = Combat.LAYER_ENEMY | Combat.LAYER_WORLD
	p.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = p.radius
	shape.shape = sphere
	p.add_child(shape)
	var mesh_i := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = p.radius
	mesh.height = p.radius * 2.0
	mesh_i.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.albedo_color = color
	mesh_i.material_override = mat
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mesh_i)
	p.position = from
	p.add_to_group(Combat.TICK_GROUP)
	return p


func shape_radius() -> float:
	for c in get_children():
		if c is CollisionShape3D and c.shape is SphereShape3D:
			return c.shape.radius
	return -1.0


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(homing_target) and homing_target.is_alive():
		var want := Combat.flat(homing_target.global_position - global_position).normalized()
		if want.length() > 0.001:
			var angle := direction.signed_angle_to(want, Vector3.UP)
			var step := clampf(angle, -HOMING_TURN_RATE * delta, HOMING_TURN_RATE * delta)
			direction = direction.rotated(Vector3.UP, step).normalized()
	var move := direction * speed * delta
	global_position += move
	_travelled += move.length()
	for blocker in get_tree().get_nodes_in_group(BLOCKER_GROUP):
		if blocker.blocks(global_position, radius):
			queue_free()
			return
	for e in Combat.living_enemies(get_tree()):
		if Combat.flat_distance(global_position, e.global_position) <= radius + ENEMY_BODY_RADIUS:
			if on_hit.is_valid():
				on_hit.call(e)
			queue_free()
			return
	if _travelled >= max_distance:
		queue_free()
