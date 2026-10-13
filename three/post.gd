extends RefCounted
class_name Post
## Tam ekran renk düzenleme katmanı (Compat güvenli: SubViewportContainer
## üzerinde tek canvas_item geçişi). Sahne başına hazır ayarlar.

const SHADER := """
shader_type canvas_item;
uniform vec3 lift = vec3(0.0);
uniform vec3 gain = vec3(1.0);
uniform float gamma = 1.0;
uniform float sat = 1.0;
uniform float contrast = 1.0;
uniform vec3 tint_shadow = vec3(0.0);
uniform vec3 tint_high = vec3(0.0);
uniform float vignette = 0.3;
uniform float grain = 0.03;
uniform float bars = 0.0;
uniform float fade = 0.0;
uniform vec3 fade_col = vec3(0.0);
uniform float flash = 0.0;
uniform float chroma = 0.0;
uniform float rain = 0.0;
uniform float snow = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 c;
	if (chroma > 0.0) {
		vec2 d = (uv - 0.5) * chroma * 0.01;
		c = vec3(texture(TEXTURE, uv + d).r, texture(TEXTURE, uv).g, texture(TEXTURE, uv - d).b);
	} else {
		c = texture(TEXTURE, uv).rgb;
	}
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	// gölge / parlak bölgeye ayrı renk (split toning)
	c += tint_shadow * (1.0 - smoothstep(0.0, 0.45, l)) + tint_high * smoothstep(0.45, 1.0, l);
	c = c * gain + lift * (1.0 - c);
	c = pow(max(c, vec3(0.0)), vec3(1.0 / gamma));
	c = (c - 0.5) * contrast + 0.5;
	l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, sat);
	vec2 q = uv - 0.5;
	float v = 1.0 - dot(q, q) * vignette * 2.2;
	c *= clamp(v, 0.0, 1.0);
	if (grain > 0.0) {
		float g = h(uv * 917.0 + fract(TIME * 7.13) * 31.0) - 0.5;
		c += g * grain;
	}
	if (rain > 0.0) {
		// eğik yağmur çizgileri, iki katman (yakın/uzak)
		for (int k = 0; k < 2; k++) {
			float sc = k == 0 ? 1.0 : 2.3;
			vec2 r = vec2(uv.x * 70.0 * sc + uv.y * 9.0 * sc, uv.y * 3.0 * sc + TIME * (4.2 - float(k) * 1.4));
			vec2 cell = floor(r);
			float rnd = h(cell + float(k) * 13.0);
			float y = fract(r.y);
			float streak = step(0.93, rnd) * smoothstep(0.0, 0.08, y) * (1.0 - smoothstep(0.12, 0.6, y));
			float xw = 1.0 - smoothstep(0.0, 0.18, abs(fract(r.x) - 0.5));
			c += vec3(0.55, 0.6, 0.68) * streak * xw * rain * (k == 0 ? 0.32 : 0.18);
		}
	}
	if (snow > 0.0) {
		for (int k = 0; k < 3; k++) {
			float sc = 6.0 + float(k) * 5.0;
			vec2 r = vec2(uv.x * sc * 1.0 + sin(TIME * 0.7 + uv.y * 5.0 + float(k)) * 0.25, uv.y * sc * 1.7 - TIME * (0.5 + float(k) * 0.25));
			vec2 cell = floor(r);
			vec2 f = fract(r) - 0.5;
			float rnd = h(cell + float(k) * 7.0);
			vec2 o = vec2(h(cell + 3.1), h(cell + 5.7)) - 0.5;
			float d = length(f - o * 0.6);
			float flake = step(0.7, rnd) * (1.0 - smoothstep(0.02, 0.07 - float(k) * 0.015, d));
			c = mix(c, vec3(0.95), flake * snow * (0.9 - float(k) * 0.2));
		}
	}
	c = mix(c, vec3(1.0), flash);
	c = mix(c, fade_col, fade);
	if (bars > 0.0) {
		float b = step(uv.y, bars) + step(1.0 - bars, uv.y);
		c = mix(c, vec3(0.0), b);
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

## Hazır ayarlar: sinematik ama okunabilir. Değerler telefonda denenerek seçildi.
const PRESETS := {
	"night": {"lift": Vector3(0.012, 0.018, 0.035), "gain": Vector3(1.04, 1.02, 1.0), "gamma": 1.04, "sat": 1.12, "contrast": 1.08,
		"tint_shadow": Vector3(-0.006, 0.0, 0.02), "tint_high": Vector3(0.02, 0.012, -0.01), "vignette": 0.42, "grain": 0.025},
	"day": {"lift": Vector3(0.01, 0.01, 0.015), "gain": Vector3(1.05, 1.03, 0.98), "gamma": 1.02, "sat": 1.1, "contrast": 1.06,
		"tint_shadow": Vector3(0.0, 0.004, 0.014), "tint_high": Vector3(0.025, 0.015, -0.01), "vignette": 0.3, "grain": 0.018},
	"rain": {"lift": Vector3(0.02, 0.025, 0.035), "gain": Vector3(0.96, 1.0, 1.04), "gamma": 1.0, "sat": 0.82, "contrast": 1.04,
		"tint_shadow": Vector3(0.0, 0.006, 0.02), "tint_high": Vector3(-0.01, 0.0, 0.01), "vignette": 0.45, "grain": 0.03},
	"office": {"lift": Vector3(0.02, 0.012, 0.004), "gain": Vector3(1.08, 1.0, 0.9), "gamma": 1.06, "sat": 1.05, "contrast": 1.1,
		"tint_shadow": Vector3(0.0, 0.006, 0.018), "tint_high": Vector3(0.03, 0.012, -0.02), "vignette": 0.5, "grain": 0.03},
	"training": {"lift": Vector3(0.012, 0.01, 0.006), "gain": Vector3(1.06, 1.02, 0.95), "gamma": 1.03, "sat": 1.08, "contrast": 1.06,
		"tint_shadow": Vector3(0.0, 0.004, 0.012), "tint_high": Vector3(0.03, 0.016, -0.012), "vignette": 0.34, "grain": 0.02},
	"video": {"lift": Vector3(0.03, 0.03, 0.03), "gain": Vector3(0.98, 1.0, 1.0), "gamma": 1.0, "sat": 0.7, "contrast": 1.12,
		"tint_shadow": Vector3(0.0, 0.0, 0.01), "tint_high": Vector3(0.0, 0.0, 0.0), "vignette": 0.55, "grain": 0.06},
}

static var _sh: Shader

static func make(preset := "night") -> ShaderMaterial:
	if _sh == null:
		_sh = Shader.new()
		_sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _sh
	apply(m, preset)
	return m

static func weather(m: ShaderMaterial, w: String) -> void:
	m.set_shader_parameter("rain", 1.0 if w == "rain" else 0.0)
	m.set_shader_parameter("snow", 1.0 if w == "snow" else 0.0)

static func apply(m: ShaderMaterial, preset: String) -> void:
	var p: Dictionary = PRESETS.get(preset, PRESETS.night)
	var low := Game.quality() == "low"
	for k in p:
		var v = p[k]
		if low and k == "grain":
			v = 0.0
		m.set_shader_parameter(k, v)
