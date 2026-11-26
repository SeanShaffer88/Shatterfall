class_name HeroInput
extends Node
## Feeds the hero: virtual stick (touch) or WASD / arrows (desktop fallback)
## into `input_vector`, and J/K/L or 1/2/3 into the three skills.

const ACTIONS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"skill_1": [KEY_J, KEY_1],
	"skill_2": [KEY_K, KEY_2],
	"skill_3": [KEY_L, KEY_3],
}

var hero: HeroController
var stick: VirtualStick
var camera: CameraRig          # optional: turns screen-space input into world space


## Registers the input actions at runtime so project.godot stays hand-editable.
static func ensure_actions() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _ready() -> void:
	ensure_actions()


func bind(target_hero: HeroController, target_stick: VirtualStick, rig: CameraRig = null) -> void:
	hero = target_hero
	stick = target_stick
	camera = rig


func current_vector() -> Vector2:
	if stick != null and stick.is_active():
		return stick.output
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## The §2A input vector: screen-space input turned by the camera yaw (Q-11).
func world_vector() -> Vector2:
	var v := current_vector()
	return camera.screen_to_world(v) if camera != null else v


func _physics_process(_delta: float) -> void:
	if hero != null:
		hero.input_vector = world_vector()


func _unhandled_input(event: InputEvent) -> void:
	if hero == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	for i in 3:
		if event.is_action("skill_%d" % (i + 1)):
			hero.skills.request(i)
			get_viewport().set_input_as_handled()
			return
