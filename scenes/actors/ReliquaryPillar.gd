class_name ReliquaryPillar
extends Node3D
## One of Vespera's Twin Reliquaries (D41): a glass pillar that breaks on any
## single hit (hero or Echo, melee or ranged). It is a targetable enemy for
## auto-attack and Echo snap, but never feeds stars (DungeonRun filters it).
## An AD7 countdown ring shows the time left to break the pair.

signal broken(pillar: ReliquaryPillar)

var intact: bool = true
var broken_by_echo: bool = false
var ring: Telegraph


func setup(time_limit: float, radius: float) -> void:
	name = "Reliquary"
	add_to_group(Combat.ENEMY_GROUP)
	add_to_group(Combat.TICK_GROUP)
	var area := Area3D.new()
	area.collision_layer = Combat.LAYER_ENEMY
	area.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 3.0
	shape.shape = cyl
	shape.position.y = 1.5
	area.add_child(shape)
	add_child(area)
	var mesh := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(radius * 2.0, 3.0, radius * 2.0)
	mesh.mesh = prism
	mesh.position.y = 1.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#8F4FD4")
	mat.emission_enabled = true
	mat.emission = Color("#8F4FD4")
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	ring = Telegraph.circle(radius + 0.6, time_limit)
	add_child(ring)


func is_alive() -> bool:
	return intact and not is_queued_for_deletion()


func take_hit(hit: Dictionary) -> void:
	if not intact:
		return
	intact = false
	broken_by_echo = hit.get("is_echo", false)
	visible = false
	broken.emit(self)


func has_status(_id: String) -> bool:
	return false


func status_data(_id: String) -> Dictionary:
	return {}


func apply_status(_id: String, _data: Dictionary) -> void:
	pass


func displace(_offset: Vector3) -> void:
	pass


func tick(delta: float) -> void:
	if intact and ring != null:
		ring.tick(delta)
