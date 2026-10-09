shader_type spatial;
render_mode cull_back;
uniform sampler2D detail : source_color, filter_linear_mipmap;
uniform sampler2D detail2 : filter_linear_mipmap;
uniform vec3 skin : source_color = vec3(0.78, 0.6, 0.5);
uniform vec3 hair_col : source_color = vec3(0.1, 0.07, 0.05);
uniform float beard = 0.0;
uniform float brow = 1.0;
uniform float scalp_amt = 0.0;
uniform float wrap = 0.35;
varying float vlum;
void fragment() {
	vec4 d = texture(detail, UV);
	vec4 d2 = texture(detail2, UV);
	vec3 col = skin;
	col *= 0.93 + 0.14 * d2.a;
	col *= 1.0 - 0.22 * d2.r;
	col = mix(col, vec3(0.16, 0.05, 0.05), d2.g * 0.9);
	float lipk = d.r * 0.7;
	col = mix(col, col * vec3(0.86, 0.66, 0.64), lipk);
	col = mix(col, mix(col, vec3(0.92, 0.78, 0.74), 0.5), d2.b * 0.7);
	col = mix(col, hair_col * 0.55 + col * 0.25, clamp(d.b * beard * 1.2, 0.0, 0.92));
	col = mix(col, hair_col * 0.6, clamp(d.g * brow, 0.0, 1.0));
	col = mix(col, hair_col * 0.8 + col * 0.1, clamp(d.a * scalp_amt, 0.0, 1.0));
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(0.62 - lipk * 0.12 + (1.0 - d2.a) * 0.08, 0.2, 1.0);
	SPECULAR = 0.32;
}
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wr = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// deri altı saçılma hissi: gölge sınırında hafif kırmızı
	vec3 sss = vec3(1.0, 0.45, 0.35) * (wr - clamp(ndl, 0.0, 1.0)) * 0.6;
	DIFFUSE_LIGHT += (vec3(clamp(ndl, 0.0, 1.0)) * 0.6 + vec3(wr) * 0.4 + sss) * ATTENUATION * LIGHT_COLOR / PI;
	vec3 hv = normalize(VIEW + LIGHT);
	float sp = pow(clamp(dot(NORMAL, hv), 0.0, 1.0), mix(80.0, 12.0, ROUGHNESS));
	SPECULAR_LIGHT += sp * (1.0 - ROUGHNESS) * 0.16 * ATTENUATION * LIGHT_COLOR * clamp(ndl * 4.0, 0.0, 1.0);
}
