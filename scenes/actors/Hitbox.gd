class_name Hitbox
extends Area3D
## A hero attack area: a real Area3D with a SphereShape3D on the hero-attack
## layer. Instant hitboxes resolve on spawn and linger briefly for visuals;
## zones (Gravity Well) also tick `on_tick` every `tick_interval` and run
## `on_physics(delta)` every step until `duration` ends.

const LINGER := 0.15

var kind: String = ""
var radius: float = 1.0
var duration: float = LINGER
var tick_interval: float = 0.0
var on_tick: Callable
var on_physics: Callable

var _age: float = 0.0
var _next_tick: float = 0.0


static func create(kind_id: String, at: Vector3, area_radius: float, color: Color) -> Hitbox:
	var hb := Hitbox.new()
	hb.kind = kind_id
	hb.radius = area_radius
	hb.name = "Hitbox_" + kind_id
	hb.collision_layer = Combat.LAYER_HERO_ATTACK
	hb.collision_mask = Combat.LAYER_ENEMY
	hb.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = area_radius
	shape.shape = sphere
	hb.add_child(shape)
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = area_radius
	mesh.bottom_radius = area_radius
	mesh.height = 0.04
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color, 0.25)
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hb.add_child(disc)
	hb.position = at
	hb.add_to_group(Combat.TICK_GROUP)
	return hb


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
	_age += delta
	if on_physics.is_valid():
		on_physics.call(delta)
	if tick_interval > 0.0 and on_tick.is_valid():
		while _next_tick + tick_interval <= _age + 1e-6 and _next_tick + tick_interval <= duration + 1e-6:
			_next_tick += tick_interval
			on_tick.call()
	if _age >= duration - 1e-6:
		queue_free()
