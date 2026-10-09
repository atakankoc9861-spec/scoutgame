shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// UBC gövdesi: ten bölgeleri dokudan, forma bölgeleri dinlenme konumundan (vertex rengi)
uniform sampler2D tex_body : source_color, filter_linear_mipmap;
uniform sampler2D tex_norm : hint_normal, filter_linear_mipmap;
uniform vec3 skin_mul = vec3(1.0);
uniform vec3 c_shirt : source_color = vec3(0.8, 0.1, 0.1);
uniform vec3 c_shirt2 : source_color = vec3(1.0);
uniform int pattern = 0;   // 0 düz, 1 dikey çubuk, 2 yatay şerit, 3 yarım, 4 omuz bandı
uniform vec3 c_shorts : source_color = vec3(1.0);
uniform vec3 c_socks : source_color = vec3(0.8, 0.1, 0.1);
uniform vec3 c_boots : source_color = vec3(0.05);
uniform float sleeve = 0.33;
uniform float y_neck = 1.53;
uniform float y_shirt = 1.045;
uniform float y_shorts = 0.722;
uniform float y_knee = 0.50;
uniform float y_sock = 0.125;

varying vec3 rp;

void vertex() {
	rp = vec3(COLOR.r * 2.0 - 1.0, COLOR.g * 2.0, COLOR.b * 2.0 - 1.0);
}

void fragment() {
	vec3 tb = texture(tex_body, UV).rgb;
	vec3 c = tb * skin_mul;
	float r = 0.55;
	float nd = 1.0;
	float ax = abs(rp.x);
	bool kit = false;
	if (ax > 0.215 && rp.y > 1.25) {
		if (ax < sleeve) { c = c_shirt; kit = true; }
	} else if (rp.y > y_neck && ax < 0.11) {
		// ten (yüz/boyun)
	} else if (rp.y > y_shirt) {
		c = c_shirt; kit = true;
		if (pattern == 1 && fract(rp.x * 9.0) > 0.5) c = c_shirt2;
		else if (pattern == 2 && fract(rp.y * 7.0) > 0.5) c = c_shirt2;
		else if (pattern == 3 && rp.x < 0.0) c = c_shirt2;
		else if (pattern == 4 && rp.y > 1.36) c = c_shirt2;
	} else if (rp.y > y_shorts) {
		c = c_shorts; kit = true;
	} else if (rp.y > y_knee) {
		// ten (diz)
	} else if (rp.y > y_sock) {
		c = c_socks; kit = true; r = 0.85;
	} else {
		c = c_boots; kit = true; r = 0.35;
	}
	if (kit) {
		nd = 0.35;
		r = max(r, 0.75);
		c *= 0.88 + 0.24 * dot(tb, vec3(0.333));
	}
	ALBEDO = c;
	ROUGHNESS = r;
	NORMAL_MAP = texture(tex_norm, UV).rgb;
	NORMAL_MAP_DEPTH = nd;
}
