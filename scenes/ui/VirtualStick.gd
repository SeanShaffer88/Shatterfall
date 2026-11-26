class_name VirtualStick
extends Control
## Floating virtual joystick (D1: bottom-left). The first touch that lands in
## this control's rect becomes the stick origin; dragging sets `output`
## (length ≤ 1). Multi-touch safe: it tracks one finger index and ignores the
## others (the skill buttons use their own fingers).

@export var radius: float = 160.0        # px of drag for full deflection

var output: Vector2 = Vector2.ZERO
var _finger: int = -1
var _origin: Vector2 = Vector2.ZERO
var _knob: Vector2 = Vector2.ZERO


func is_active() -> bool:
	return _finger >= 0


func _input(event: InputEvent) -> void:
	handle(event)


## Returns true when the event belonged to the stick.
func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0 and get_global_rect().has_point(event.position):
			_finger = event.index
			_origin = event.position
			_knob = event.position
			output = Vector2.ZERO
			queue_redraw()
			return true
		if not event.pressed and event.index == _finger:
			_finger = -1
			output = Vector2.ZERO
			queue_redraw()
			return true
	elif event is InputEventScreenDrag and event.index == _finger:
		var offset: Vector2 = event.position - _origin
		output = offset.limit_length(radius) / radius
		_knob = _origin + offset.limit_length(radius)
		queue_redraw()
		return true
	return false


func _draw() -> void:
	if _finger < 0:
		var hint := Vector2(radius + 40.0, size.y - radius - 40.0)
		draw_arc(hint, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 4.0)
		return
	var o := _origin - global_position
	draw_arc(o, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 4.0)
	draw_circle(_knob - global_position, radius * 0.38, Color(0.85, 0.15, 0.22, 0.55))
