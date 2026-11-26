// Spectral Echo look (AD6): translucent stained glass in cold cyan.
// Fresnel rim + a lead-came cell pattern; `dissolve` fades the echo out.
// The slice's one custom shader (art policy). Mobile-renderer friendly.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform vec4 echo_color : source_color = vec4(0.373, 0.831, 0.902, 1.0);
uniform float fresnel_power = 2.0;
uniform vec2 cells = vec2(6.0, 10.0);
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	vec2 cell = fract(UV * cells);
	float glass = step(0.08, cell.x) * step(0.08, cell.y);
	ALBEDO = echo_color.rgb * (0.35 + 0.65 * fres) * mix(0.5, 1.0, glass);
	ALPHA = (0.25 + 0.6 * fres) * (1.0 - dissolve);
}
