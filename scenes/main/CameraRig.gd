class_name CameraRig
extends Node3D
## D3 camera: fixed isometric 3/4 follow (Q-11). Camera3D on a boom (pitch −55°,
## length 30 m, FOV 30° for a flat, long-lens look) on a pivot turned 45° about
## the vertical, so the room grid runs diagonally across the screen. The pivot
## follows the hero's position with 0.15 s smoothing. The rig is top-level and
## its orientation is fixed: no zoom, no rotation. HeroInput turns the stick by
## the same yaw, so "stick up" always means "up on screen".

@export var yaw_deg: float = 45.0
@export var pitch_deg: float = 55.0
@export var boom_length: float = 30.0
@export var fov: float = 30.0
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
	global_rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	camera.position = Vector3(0.0, boom_length * sin(p), boom_length * cos(p))
	camera.rotation = Vector3(-p, 0.0, 0.0)
	camera.fov = fov
	camera.far = boom_length * 3.0
	camera.current = true


func follow(node: Node3D) -> void:
	target = node
	snap()


func snap() -> void:
	if is_instance_valid(target):
		global_position = Combat.flat(target.global_position)


## A screen-space stick vector (x right, y down) as the §2A world input vector.
func screen_to_world(stick: Vector2) -> Vector2:
	return stick.rotated(-deg_to_rad(yaw_deg))


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var k := 1.0 - exp(-delta / maxf(smoothing, 0.0001))
	global_position = global_position.lerp(Combat.flat(target.global_position), k)
	global_rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
