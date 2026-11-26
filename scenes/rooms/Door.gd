class_name Door
extends StaticBody3D
## A room gate: solid (world layer) while closed, no collision and hidden while open.

var is_open: bool = false
var _mesh: MeshInstance3D


func setup(width: float, height: float, thickness: float) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, thickness)
	shape.shape = box
	shape.position.y = height * 0.5
	add_child(shape)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, height, thickness)
	_mesh.mesh = bm
	_mesh.position.y = height * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#5A2A30")
	mat.emission_enabled = true
	mat.emission = Color("#D92638")
	mat.emission_energy_multiplier = 0.4
	_mesh.material_override = mat
	add_child(_mesh)
	close()


func open() -> void:
	is_open = true
	collision_layer = 0
	_mesh.visible = false


func close() -> void:
	is_open = false
	collision_layer = Combat.LAYER_WORLD
	_mesh.visible = true
