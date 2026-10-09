shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// UBC gövdesi: ten dokusu seçilen ten rengine boyanır; kıyafet bölgeleri
// dinlenme (T-poz) konumundan hesaplanır (vertex rengi = dinlenme konumu).
uniform sampler2D tex_body : source_color, filter_linear_mipmap;
uniform sampler2D tex_norm : hint_normal, filter_linear_mipmap;
uniform vec3 c_skin : source_color = vec3(0.8, 0.6, 0.5);
uniform vec3 c_shirt : source_color = vec3(0.8, 0.1, 0.1);
uniform vec3 c_shorts : source_color = vec3(1.0);
uniform vec3 c_socks : source_color = vec3(0.8, 0.1, 0.1);
uniform vec3 c_boots : source_color = vec3(0.05);
uniform vec3 c_hair : source_color = vec3(0.1, 0.07, 0.05);
uniform float sleeve = 0.33;
uniform bool long_pants = false;
uniform int pattern = 0;          // 0 düz, 1 dikey çubuk, 2 yatay şerit, 3 yarım
uniform vec3 c_shirt2 : source_color = vec3(1.0);

varying vec3 rp;

void vertex() {
	rp = vec3(COLOR.r * 2.0 - 1.0, COLOR.g * 2.0, COLOR.b * 2.0 - 1.0);
}

void fragment() {
	vec3 tx = texture(tex_body, UV).rgb;
	vec3 skin = c_skin * clamp(tx / vec3(0.84, 0.6, 0.46), vec3(0.55), vec3(1.35));
	float fold = clamp(dot(tx, vec3(0.333)) / 0.6, 0.9, 1.06);
	vec3 shirt = c_shirt;
	if (pattern == 1) { shirt = mix(c_shirt, c_shirt2, step(0.5, fract(rp.x * 7.0 + 0.25))); }
	else if (pattern == 2) { shirt = mix(c_shirt, c_shirt2, step(0.5, fract(rp.y * 6.0))); }
	else if (pattern == 3) { shirt = mix(c_shirt, c_shirt2, step(0.0, rp.x)); }
	vec3 c = shirt * fold;
	float r = 0.82;
	bool is_skin = false;
	float ax = abs(rp.x);
	if (ax > 0.22 && rp.y > 1.2) {
		if (ax > sleeve) { is_skin = true; }
	} else if (rp.y > 1.535 && ax < 0.095) {
		is_skin = true;
	} else if (rp.y > 1.04) {
		c = shirt * fold;
	} else if (rp.y > 0.72) {
		c = c_shorts * fold;
	} else if (rp.y > 0.49) {
		if (long_pants) { c = c_shorts * fold; } else { is_skin = true; }
	} else if (rp.y > 0.15) {
		c = (long_pants ? c_shorts : c_socks) * fold; r = 0.88;
	} else {
		c = c_boots; r = 0.35;
	}
	if (is_skin) { c = skin; r = 0.55; }
	ALBEDO = c;
	ROUGHNESS = r;
	NORMAL_MAP = texture(tex_norm, UV).rgb;
	NORMAL_MAP_DEPTH = is_skin ? 0.8 : 0.35;
}
