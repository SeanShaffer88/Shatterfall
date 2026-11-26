class_name CameraRig
extends Node3D
## D3 camera: fixed top-down follow. Camera3D on a boom (pitch −40°, length
## 11 m, FOV 45°) whose pivot follows the hero's position with 0.15 s smoothing.
## The rig is top-level, so it never inherits the hero's rotation: fixed
## orientation, no zoom, no rotation.

@export var pitch_deg: float = 40.0
@export var boom_length: float = 11.0
@export var fov: float = 45.0
@export var smoothing: float = 0.15      # s (exponential time constant)

var target: Node3D
var camera: Camera3D


func _ready() -> void:
	top_level = true
	camera = Camera3D.new()
	camera.name = "Camera3D"
	add_child(camera)
	_apply_boom()


func _apply_boom() -> void:
	var p := deg_to_rad(pitch_deg)
	camera.position = Vector3(0.0, boom_length * sin(p), boom_length * cos(p))
	camera.rotation = Vector3(-p, 0.0, 0.0)
	camera.fov = fov
	camera.current = true


func follow(node: Node3D) -> void:
	target = node
	snap()


func snap() -> void:
	if is_instance_valid(target):
		global_position = Combat.flat(target.global_position)


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var k := 1.0 - exp(-delta / maxf(smoothing, 0.0001))
	global_position = global_position.lerp(Combat.flat(target.global_position), k)
	global_rotation = Vector3.ZERO
