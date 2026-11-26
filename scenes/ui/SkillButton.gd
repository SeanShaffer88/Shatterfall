class_name SkillButton
extends Control
## One round skill button with a radial cooldown ring (D1, §3.1). A touch
## inside the circle requests the skill; the ring sweeps from full to empty as
## the cooldown runs out.

signal pressed_skill(index: int)

@export var index: int = 0
@export var label_text: String = ""

var skills: HeroSkills


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(hero_skills: HeroSkills) -> void:
	skills = hero_skills
	label_text = skills.skill_id(index).replace("_", " ")
	queue_redraw()


func ring_fraction() -> float:
	return skills.cooldown_fraction(index) if skills != null else 0.0


func _input(event: InputEvent) -> void:
	handle(event)


func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch and event.pressed:
		var center := get_global_rect().get_center()
		if event.position.distance_to(center) <= minf(size.x, size.y) * 0.5:
			press()
			return true
	return false


func press() -> void:
	pressed_skill.emit(index)
	if skills != null:
		skills.request(index)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var can_cast := skills != null and skills.is_ready(index)
	draw_circle(c, r, Color("#2A2C33") if can_cast else Color("#1A1B20"))
	draw_arc(c, r - 3.0, 0.0, TAU, 48, Color("#D92638") if can_cast else Color(1, 1, 1, 0.15), 4.0)
	var f := ring_fraction()
	if f > 0.0:
		draw_arc(c, r - 10.0, -PI / 2.0, -PI / 2.0 + TAU * f, 48, Color("#E8912D"), 8.0)
	var font := get_theme_default_font()
	var fs := 22
	var w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)
