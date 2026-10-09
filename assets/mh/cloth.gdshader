shader_type spatial;
render_mode cull_disabled;
uniform vec3 c1 : source_color = vec3(0.8, 0.1, 0.12);
uniform vec3 c2 : source_color = vec3(1.0);
uniform int pattern = 0;
uniform float rough = 0.82;
uniform float sheen = 0.25;
varying vec3 lp;
void vertex() { lp = vec3(COLOR.r * 2.0 - 1.0, COLOR.g * 2.0, COLOR.b * 2.0 - 1.0); }
void fragment() {
	vec3 c = c1;
	if (pattern == 1 && fract(lp.x * 9.0 + 0.25) > 0.5) { c = c2; }
	if (pattern == 2 && fract(lp.y * 7.0) > 0.5) { c = c2; }
	if (pattern == 3 && lp.x < 0.0) { c = c2; }
	float knit = 0.95 + 0.05 * sin(UV.x * 2400.0) * sin(UV.y * 2400.0);
	ALBEDO = c * knit;
	ROUGHNESS = rough;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c * rim * sheen * 0.35;
}
