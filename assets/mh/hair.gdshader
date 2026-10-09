shader_type spatial;
render_mode cull_back;
uniform vec3 hair_col : source_color = vec3(0.1, 0.07, 0.05);
uniform sampler2D detail : filter_linear_mipmap;
varying float edge;
void vertex() { edge = COLOR.r; }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float n = texture(detail, UV).a;
	vec2 q = UV * vec2(4200.0, 1400.0);
	float grain = h21(floor(q));
	float strand = 0.8 + 0.3 * grain;
	ALBEDO = hair_col * (0.8 + 0.3 * n) * strand;
	ROUGHNESS = 0.75;
	SPECULAR = 0.22;
	// saç çizgisi: kenara doğru seyrelen uçlar
	ALPHA = clamp(edge * 1.6 - grain * 0.6 + 0.15, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
