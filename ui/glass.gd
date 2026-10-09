extends Control
## Buzlu cam arka plan: arkasındaki görüntüyü bulanıklaştırıp renklendirir. Yuvarlak köşeli.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.05, 0.09, 0.07, 0.62);
uniform vec4 border : source_color = vec4(1.0, 1.0, 1.0, 0.08);
uniform float blur = 3.2;
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float radius = 18.0;
float sd_round(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	float d = sd_round(p, rect_size * 0.5, radius);
	float a = 1.0 - smoothstep(-1.0, 0.5, d);
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	vec3 col = mix(c, tint.rgb, tint.a);
	// üst kenar parıltısı
	col += vec3(1.0) * 0.05 * smoothstep(0.0, 1.0, 1.0 - UV.y * 4.0);
	float edge = 1.0 - smoothstep(-2.0, -0.5, d);
	col = mix(col, border.rgb, border.a * (a - edge));
	COLOR = vec4(col, a);
}
"""
static var _shader: Shader

var mat: ShaderMaterial

var solid := false
var solid_col := Color.BLACK
var rad := 18.0
var bcol := Color.TRANSPARENT

func setup(tint := Color(0.05, 0.09, 0.07, 0.62), radius := 18.0, border := Color(1, 1, 1, 0.08)) -> Control:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Game.quality() == "low":
		solid = true
		solid_col = Color(tint.r, tint.g, tint.b, 0.9)
		rad = radius
		bcol = border
		return self
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("border", border)
	material = mat
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	return self

func _on_resized() -> void:
	if mat:
		mat.set_shader_parameter("rect_size", size)

func _draw() -> void:
	if solid:
		var sb := StyleBoxFlat.new()
		sb.bg_color = solid_col
		sb.set_corner_radius_all(int(rad))
		sb.set_border_width_all(1)
		sb.border_color = bcol
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
