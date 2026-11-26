class_name Telegraph
extends MeshInstance3D
## Enemy attack warning in the shared AD7 alarm language: a crimson → white
## ramp as the attack approaches, unshaded, drawn above all decorative light
## (high render priority, no depth test). Shapes: circle, cone, rectangle.
## The owner frees it when the attack resolves or is cancelled.

const CRIMSON := Color("#D92638")
const ALARM_WHITE := Color(1.0, 0.92, 0.92)
const RENDER_PRIORITY := 100            # above every decorative material (AD7)
const GROUP := "telegraphs"

var shape: String = ""
var duration: float = 1.0
var elapsed: float = 0.0
var size_param: Vector2 = Vector2.ONE   # circle: (r, 0); cone: (range, arc_deg); rect: (length, width)

var _mat: StandardMaterial3D


static func circle(radius: float, warn_time: float) -> Telegraph:
	var t := Telegraph.new()
	t.shape = "circle"
	t.size_param = Vector2(radius, 0)
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 0.02
	m.radial_segments = 32
	t.mesh = m
	return t._init_common(warn_time)


static func cone(reach: float, arc_deg: float, warn_time: float) -> Telegraph:
	var t := Telegraph.new()
	t.shape = "cone"
	t.size_param = Vector2(reach, arc_deg)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 16
	var half := deg_to_rad(arc_deg) * 0.5
	for i in steps:
		var a0 := -half + (2.0 * half) * i / steps
		var a1 := -half + (2.0 * half) * (i + 1) / steps
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a1), 0, cos(a1)) * reach)
		st.add_vertex(Vector3(sin(a0), 0, cos(a0)) * reach)
	t.mesh = st.commit()
	return t._init_common(warn_time)


static func rect(length: float, width: float, warn_time: float) -> Telegraph:
	var t := Telegraph.new()
	t.shape = "rect"
	t.size_param = Vector2(length, width)
	var m := BoxMesh.new()
	m.size = Vector3(length, 0.02, width)
	t.mesh = m
	return t._init_common(warn_time)


func _init_common(warn_time: float) -> Telegraph:
	duration = warn_time
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = true
	_mat.render_priority = RENDER_PRIORITY
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = 0.03
	add_to_group(GROUP)
	_refresh()
	return self


## 0 at the start of the warning, 1 when the attack lands.
func progress() -> float:
	return clampf(elapsed / maxf(duration, 0.0001), 0.0, 1.0)


func alarm_color() -> Color:
	return _mat.albedo_color


## Restarts the warning from zero (Mirage Veil, §2H).
func restart(warn_time: float) -> void:
	duration = warn_time
	elapsed = 0.0
	_refresh()


func tick(delta: float) -> void:
	elapsed += delta
	_refresh()


func _refresh() -> void:
	var c := CRIMSON.lerp(ALARM_WHITE, progress())
	c.a = 0.35 + 0.45 * progress()
	_mat.albedo_color = c
