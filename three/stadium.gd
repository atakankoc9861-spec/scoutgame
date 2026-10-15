extends Node3D
## Prosedürel stadyum v3. Saha: X uzunluk (-52.5..52.5), Z genişlik (-34..34).
## tier: 0 arena, 1 orta stadyum, 2 küçük kasaba sahası, 3 tesis/altyapı sahası
## tod: day / dusk / night   weather: clear / rain / snow

var home_c1 := Color("#d4a017")
var home_c2 := Color("#14213d")
var away_c1 := Color("#b5121b")
var crowd_mat: ShaderMaterial
var led_mat: ShaderMaterial
var led_mats: Array = []
var pitch_mat: ShaderMaterial
var net_mats := []
var confetti: Array = []
var flares: Array = []
var lens: Array = []
var sun: DirectionalLight3D
var env: Environment
var shadows := true
var fx_enabled := true
var tier := 0
var tod := "night"
var weather := "clear"
var configured := false
var big_ground := true
var board: Label3D
var board2: Label3D

const T_GRASS := preload("res://assets/tex/grass.jpg")
const T_CROWD := preload("res://assets/tex/crowd.jpg")
const T_SKY := preload("res://assets/tex/sky_day.jpg")
const T_ADS := preload("res://assets/ads/atlas.png")

const PITCH_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform sampler2D grass : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform vec2 size = vec2(118.0, 82.0);
uniform float wet = 0.0;
uniform float snow = 0.0;
uniform float line_w = 0.13;
float ln(float d, float w) { return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.06, abs(d)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = hash(i), b = hash(i + vec2(1, 0)), c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 a = abs(p);
	// görsel: 1024 px = 8 biçme şeridi = 42 m; dikey yönde 1 doku = 21 m
	vec3 g = texture(grass, vec2((p.x + 52.5) / 42.0 + 0.012, p.y / 21.0)).rgb;
	// çapraz biçme izi
	float cross_s = mod(floor((p.y + 34.0) / 6.8), 2.0);
	vec3 col = g * tint * (0.95 + 0.06 * cross_s);
	float n = noise(p * 0.35) * 0.6 + noise(p * 2.3) * 0.4;
	col *= 0.9 + 0.18 * n;
	// yıpranmış alanlar (kale önü, orta saha, kenar çizgisi koşu yolu)
	float wear = exp(-pow(length(vec2(a.x - 49.0, p.y)) / 6.0, 2.0)) + 0.45 * exp(-pow(length(p) / 7.0, 2.0))
		+ 0.25 * exp(-pow((a.y - 33.0) / 1.2, 2.0)) * step(a.x, 50.0);
	float wn = smoothstep(0.35, 0.75, noise(p * 1.4) * 0.7 + noise(p * 6.0) * 0.3);
	vec3 mud = vec3(0.16, 0.11, 0.06) * (0.6 + 0.4 * n);
	col = mix(col, mud, clamp(wear * (0.25 + wet * 0.35) * (0.4 + wn), 0.0, 0.8));
	float w = line_w;
	float L = 0.0;
	L = max(L, ln(a.x - 52.5, w) * step(a.y, 34.0 + w));
	L = max(L, ln(a.y - 34.0, w) * step(a.x, 52.5 + w));
	L = max(L, ln(p.x, w) * step(a.y, 34.0));
	L = max(L, ln(length(p) - 9.15, w));
	L = max(L, 1.0 - smoothstep(0.2, 0.28, length(p)));
	float bx = 52.5 - 16.5;
	L = max(L, ln(a.x - bx, w) * step(a.y, 20.16));
	L = max(L, ln(a.y - 20.16, w) * step(bx, a.x) * step(a.x, 52.5));
	float gx = 52.5 - 5.5;
	L = max(L, ln(a.x - gx, w) * step(a.y, 9.16));
	L = max(L, ln(a.y - 9.16, w) * step(gx, a.x) * step(a.x, 52.5));
	vec2 ps = vec2(a.x - 41.5, p.y);
	L = max(L, 1.0 - smoothstep(0.14, 0.22, length(ps)));
	L = max(L, ln(length(ps) - 9.15, w) * step(a.x, bx));
	vec2 cn = vec2(a.x - 52.5, a.y - 34.0);
	L = max(L, ln(length(cn) - 1.0, w) * step(a.x, 52.5) * step(a.y, 34.0));
	// kar: çizgiler süpürülmüş, kenarlar daha beyaz
	float sn = snow * clamp(0.15 + 0.55 * noise(p * 1.6) * noise(p * 0.3) + 0.35 * smoothstep(30.0, 40.0, a.y) + 0.3 * smoothstep(50.0, 58.0, a.x) - wear * 0.6, 0.0, 1.0);
	col = mix(col, vec3(0.62, 0.64, 0.68), sn * (1.0 - L));
	col = mix(col, vec3(0.82), L * (0.85 + 0.15 * n));
	if (a.x > 52.6 || a.y > 34.1) { col *= 0.82; }
	col *= 1.0 - wet * 0.14;
	ALBEDO = col;
	ROUGHNESS = mix(0.82, 0.58, wet) - 0.08 * cross_s;
	SPECULAR = mix(0.25, 0.38, wet);
}
"""

const CROWD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D photo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 c1 = vec3(0.8, 0.6, 0.1);
uniform vec3 c2 = vec3(0.1, 0.1, 0.3);
uniform vec3 c3 = vec3(0.7, 0.1, 0.1);
uniform float excite = 0.0;
uniform float away_share = 0.0;
uniform float length_m = 100.0;
uniform float fill = 0.9;
uniform float light = 1.0;
uniform float flashes = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 recolor(vec3 c, vec3 team) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / max(mx, 0.001);
	float redness = smoothstep(0.32, 0.55, sat) * step(c.g, c.r * 0.72) * step(c.b, c.r * 0.8);
	return mix(c, team * (0.25 + mx * 1.25), redness);
}
void fragment() {
	float row = floor(UV2.y + 0.001);
	float xm = UV.x * length_m;
	// blok: 1.1 m genişlik, sıra başına
	vec2 cell = vec2(floor(xm / 1.1), row);
	float h = hash(cell);
	float h2 = hash(cell + 17.3);
	bool away = xm > length_m * (1.0 - away_share);
	vec3 team = away ? c3 : (h2 < 0.72 ? c1 : c2);
	float empty = step(fill, h);
	// heyecan: bloklar zıplar
	float hype = smoothstep(0.1 + h2 * 0.5, 0.3 + h2 * 0.5, excite);
	float bob = hype * abs(sin(TIME * (7.0 + h * 3.0) + h * 6.28)) * 0.045;
	float v = (row + (1.0 - UV.y)) / 14.0 + bob + floor(h2 * 3.0) * 0.21;
	vec2 puv = vec2(xm / 37.0 + floor(row * 0.5) * 0.37, v);
	vec3 c = texture(photo, puv).rgb;
	c = recolor(c, team);
	vec3 seat = mix(vec3(0.06, 0.065, 0.08), c2 * 0.6 + vec3(0.03), 0.5);
	seat *= 0.75 + 0.25 * step(0.25, fract(UV.y * 2.0));
	c = mix(c, seat, empty);
	float flash = step(0.9975, hash(cell + floor(TIME * 3.0))) * (1.0 - empty) * flashes;
	float depth_fade = 0.7 + 0.3 * clamp(row / 14.0, 0.0, 1.0);
	ALBEDO = clamp(c * light * depth_fade * (0.9 + 0.3 * excite) + vec3(flash * 1.6), vec3(0.0), vec3(1.6));
}
"""

const LED_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform sampler2D ads : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 c1 = vec3(0.9, 0.7, 0.1);
uniform float pulse = 0.0;
uniform float led = 1.0;
uniform float panels = 3.0;
uniform float bright = 1.6;
uniform float n_ads = 14.0;
uniform float seed = 0.0;
uniform vec3 bsize = vec3(96.0, 1.2, 0.15);
varying vec3 lp;
float pick(float k, float pi) { return mod(floor(k * 5.0 + pi * 3.0 + seed * 7.0), n_ads); }
void vertex() { lp = VERTEX; }
void fragment() {
	// kutu UV'si yerine yerel konum: tasarım panonun tamamına oturur
	float along = bsize.x >= bsize.z ? lp.x / bsize.x : -lp.z / bsize.z;
	vec2 buv = vec2(clamp(along + 0.5, 0.0, 0.9999), clamp(0.5 - lp.y / bsize.y, 0.0, 1.0));
	float pi = floor(buv.x * panels);
	vec2 lu = vec2(fract(buv.x * panels), buv.y);
	// her pano kendi temposunda: 6 sn'de bir sonraki tasarım aşağıdan yukarı kayarak gelir
	float t = led > 0.5 ? TIME / 6.0 + seed * 0.37 + pi * 0.11 : seed;
	float k = floor(t);
	float f = led > 0.5 ? smoothstep(0.86, 1.0, fract(t)) : 0.0;
	float y = lu.y + f;
	float d = y < 1.0 ? pick(k, pi) : pick(k + 1.0, pi);
	float yy = fract(y);
	vec3 col = texture(ads, vec2(lu.x, (d + clamp(yy, 0.004, 0.996)) / n_ads)).rgb;
	if (led > 0.5) {
		float px = step(0.18, fract(buv.x * panels * 260.0)) * step(0.18, fract(buv.y * 32.0));
		col *= 0.62 + 0.38 * px;
		col = mix(col, c1, pulse * step(0.5, fract(TIME * 4.0)));
	}
	ALBEDO = col * bright;
}
"""

const NET_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;
uniform float bulge = 0.0;
uniform vec3 hit = vec3(0.0);
void vertex() {
	float d = length(VERTEX.yz - hit.yz);
	VERTEX.x += bulge * exp(-d * d * 0.6) * 0.9;
}
void fragment() {
	vec2 g = fract(UV * vec2(40.0, 16.0));
	float line = 1.0 - step(0.12, g.x) * step(0.12, g.y);
	ALBEDO = vec3(0.95);
	ALPHA = line * 0.75;
}
"""

const FLAG_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 col = vec3(1.0, 0.8, 0.1);
void vertex() {
	float w = UV.x;
	VERTEX.z += sin(TIME * 6.0 + UV.x * 5.0) * 0.12 * w;
}
void fragment() { ALBEDO = col; ROUGHNESS = 0.8; }
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float strength = 0.05;
void fragment() {
	float fall = pow(1.0 - UV.y, 1.5);
	float edge = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = vec3(1.0, 0.95, 0.85) * strength * fall * (1.0 - edge * 0.85);
}
"""

## Projektör parlaması: kameraya dönük, merkez + yatay çizgi
const FLARE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float strength = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 q = UV - 0.5;
	float r = length(q);
	float core = exp(-r * r * 90.0);
	float halo = exp(-r * 7.0) * 0.35;
	float streak = exp(-abs(q.y) * 120.0) * exp(-abs(q.x) * 4.0) * 0.6;
	ALBEDO = vec3(1.0, 0.95, 0.85) * (core + halo + streak) * strength;
}
"""

## Gökyüzü kubbesi (Sky kaynağı yerine mesh: telefonda daha kararlı)
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never, fog_disabled;
uniform sampler2D sky : source_color, filter_linear, repeat_enable;
uniform int mode = 0;          // 0 gündüz dokusu, 1 gece prosedürel
uniform vec3 mul = vec3(1.0);
uniform vec3 add = vec3(0.0);
uniform float desat = 0.0;
uniform vec3 horizon = vec3(0.2, 0.25, 0.3);
varying vec3 dir;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { dir = normalize(VERTEX); }
void fragment() {
	vec3 d = normalize(dir);
	float el = asin(clamp(d.y, -1.0, 1.0)) / 1.5708;
	float az = atan(d.x, d.z) / 6.2832 + 0.5;
	vec3 c;
	if (mode == 0) {
		float u = abs(fract(az * 2.0) * 2.0 - 1.0);
		float v = 1.0 - clamp(el, 0.0, 1.0);
		c = texture(sky, vec2(u * 0.98 + 0.01, clamp(v * 0.97, 0.0, 0.985))).rgb;
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(c, vec3(l), desat) * mul + add;
		c = mix(c, horizon, smoothstep(0.02, -0.06, el));
	} else {
		vec3 top = vec3(0.004, 0.007, 0.018);
		vec3 low = vec3(0.04, 0.045, 0.07);
		c = mix(low, top, smoothstep(0.0, 0.5, el));
		vec2 sp = vec2(az * 900.0, el * 260.0);
		float st = step(0.9985, hash(floor(sp))) * smoothstep(0.08, 0.3, el);
		c += vec3(st) * 0.6 * (0.5 + 0.5 * sin(TIME * 2.0 + hash(floor(sp)) * 40.0));
		c = c * mul + add;
		c = mix(c, horizon, smoothstep(0.02, -0.06, el));
	}
	ALBEDO = c;
}
"""

const WINDOW_SHADER := """
shader_type spatial;
uniform vec3 wall = vec3(0.3, 0.28, 0.26);
uniform float night = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 g = UV * vec2(6.0, 4.0);
	vec2 f = fract(g);
	float win = step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.75);
	float lit = step(0.45, hash(floor(g) + floor(UV2 * 13.0)));
	ALBEDO = mix(wall, vec3(0.08, 0.1, 0.12), win);
	EMISSION = vec3(1.0, 0.78, 0.45) * win * lit * night * 1.6;
	ROUGHNESS = 0.9;
}
"""

# ================================================================ koşullar

## Maç koşullarını belirle (deterministik): lig seviyesi, ülke iklimi, ay
static func pick_cond(seed: int, lg_tier: int, week: int, zone: String, youth: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var t := "night"
	var r := rng.randf()
	if youth or lg_tier >= 3:
		t = "day" if r < 0.8 else "dusk"
	elif lg_tier == 2:
		t = "day" if r < 0.45 else ("dusk" if r < 0.7 else "night")
	else:
		t = "night" if r < 0.6 else ("dusk" if r < 0.8 else "day")
	var winter := week >= 13 and week <= 25
	var rain_p: float = {"brit": 0.32, "nordic": 0.28, "west": 0.24, "central": 0.2, "east": 0.18, "balkan": 0.16,
		"tr": 0.15, "south": 0.1, "sa": 0.15, "mena": 0.03, "africa": 0.08}.get(zone, 0.15)
	var snow_p := 0.0
	if winter and zone in ["nordic", "east", "central", "balkan"]:
		snow_p = 0.16
	elif winter and zone in ["tr", "brit"]:
		snow_p = 0.05
	if not winter:
		rain_p *= 0.7
	var w := "clear"
	var r2 := rng.randf()
	if r2 < snow_p:
		w = "snow"
	elif r2 < snow_p + rain_p:
		w = "rain"
	return {"tod": t, "weather": w, "stadium": clampi(lg_tier if not youth else 3, 0, 3)}

func configure(stadium_tier: int, time_of_day: String, w: String) -> void:
	tier = clampi(stadium_tier, 0, 3)
	tod = time_of_day
	weather = w
	configured = true

func is_night() -> bool:
	return tod != "day"

func post_preset() -> String:
	if weather == "rain":
		return "rain"
	return "day" if tod == "day" else "night"

# ================================================================ kurulum

func build(hc1: Color, hc2: Color, ac1: Color, night := true, with_shadows := true, with_env := true) -> void:
	home_c1 = hc1
	home_c2 = hc2
	away_c1 = ac1
	shadows = with_shadows
	if not configured:
		tod = "night" if night else "day"
	big_ground = with_env
	if with_env:
		_env()
		_sky()
	else:
		for pos in [Vector3(0, 45, 0), Vector3(-40, 35, 20), Vector3(40, 35, -20)]:
			var o := OmniLight3D.new()
			o.position = pos
			o.omni_range = 130.0
			o.light_energy = 1.7
			o.omni_attenuation = 0.35
			o.light_color = Color(1.0, 0.97, 0.9)
			add_child(o)
	_ground()
	_pitch()
	_goals()
	_make_led()
	match tier:
		0:
			_stands_arena()
		1:
			_stands_mid()
		2:
			_stands_small()
		_:
			_stands_ground()
	_lights()
	_led_boards()
	_flags()
	_dugouts()
	_surroundings()
	_effects()

func _mat(col: Color, emissive := 0.0, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emissive
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi

func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func _env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = not OS.has_feature("mobile")
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = shadows
	sun.shadow_opacity = 0.75
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.5
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-48, -152, 0)
	match tod:
		"day":
			env.background_color = Color(0.45, 0.6, 0.8)
			env.ambient_light_color = Color(0.62, 0.7, 0.85)
			env.ambient_light_energy = 0.55
			env.tonemap_exposure = 1.0
			sun.rotation_degrees = Vector3(-50, 35, 0)
			sun.light_energy = 1.55
			sun.light_color = Color(1.0, 0.95, 0.86)
			sun.shadow_opacity = 0.85
			fill.light_energy = 0.3
			fill.light_color = Color(0.7, 0.8, 1.0)
		"dusk":
			env.background_color = Color(0.25, 0.2, 0.25)
			env.ambient_light_color = Color(0.6, 0.55, 0.7)
			env.ambient_light_energy = 0.4
			env.tonemap_exposure = 0.98
			sun.rotation_degrees = Vector3(-55, 30, 0)
			sun.light_energy = 1.05
			sun.light_color = Color(1.0, 0.9, 0.78)
			fill.light_energy = 0.32
			fill.light_color = Color(1.0, 0.65, 0.45)
		_:
			env.background_color = Color(0.012, 0.016, 0.035)
			env.ambient_light_color = Color(0.5, 0.56, 0.7)
			env.ambient_light_energy = 0.34
			env.tonemap_exposure = 0.95
			sun.rotation_degrees = Vector3(-62, 28, 0)
			sun.light_energy = 1.0
			sun.light_color = Color(1.0, 0.97, 0.9)
			fill.light_energy = 0.28
			fill.light_color = Color(0.85, 0.9, 1.0)
	if weather == "rain":
		env.ambient_light_energy *= 0.85
		sun.light_energy *= 0.8 if tod != "day" else 0.55
		sun.shadow_opacity = 0.5 if tod == "day" else sun.shadow_opacity
	elif weather == "snow":
		env.ambient_light_energy *= 1.1
	# hafif sis: derinlik hissi (düşük kalitede kapalı)
	if Game.quality() != "low":
		env.fog_enabled = true
		env.fog_light_color = {"day": Color(0.7, 0.78, 0.88), "dusk": Color(0.55, 0.45, 0.45)}.get(tod, Color(0.08, 0.09, 0.12))
		if weather != "clear":
			env.fog_light_color = env.fog_light_color.lerp(Color(0.5, 0.52, 0.56) if tod == "day" else Color(0.12, 0.13, 0.15), 0.6)
		env.fog_density = {"clear": 0.0007, "rain": 0.0013, "snow": 0.0018}.get(weather, 0.001)
		env.fog_sky_affect = 0.25
	we.environment = env
	add_child(we)
	add_child(sun)
	add_child(fill)

func _sky() -> void:
	add_child(sky_dome(tod, weather))

static func sky_dome(time_of_day: String, w: String, radius := 420.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	mi.mesh = sm
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("sky", T_SKY)
	match time_of_day:
		"day":
			m.set_shader_parameter("mode", 0)
			m.set_shader_parameter("horizon", Vector3(0.42, 0.48, 0.5))
		"dusk":
			m.set_shader_parameter("mode", 0)
			m.set_shader_parameter("mul", Vector3(0.75, 0.5, 0.55))
			m.set_shader_parameter("add", Vector3(0.06, 0.02, 0.04))
			m.set_shader_parameter("horizon", Vector3(0.18, 0.12, 0.14))
		_:
			m.set_shader_parameter("mode", 1)
			m.set_shader_parameter("horizon", Vector3(0.05, 0.05, 0.07))
	if w != "clear":
		m.set_shader_parameter("desat", 0.85)
		if time_of_day == "day":
			m.set_shader_parameter("mul", Vector3(0.7, 0.72, 0.76))
			m.set_shader_parameter("add", Vector3(0.12, 0.12, 0.13))
		elif time_of_day == "dusk":
			m.set_shader_parameter("mul", Vector3(0.45, 0.42, 0.45))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1000.0
	return mi

func _ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900) if big_ground else Vector2(320, 260)
	mi.mesh = pm
	mi.position.y = -0.05
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = T_GRASS
	gm.uv1_scale = Vector3(60, 60, 1)
	gm.roughness = 0.95
	gm.albedo_color = Color(0.5, 0.52, 0.42) if tier >= 2 else Color(0.18, 0.2, 0.17)
	if weather == "snow":
		gm.albedo_color = Color(1.6, 1.6, 1.7)
		gm.albedo_texture = null
		gm.albedo_color = Color(0.5, 0.52, 0.55)
	mi.material_override = gm
	add_child(mi)
	# saha çevresi
	var apron := Color(0.06, 0.14, 0.07)
	if tier == 3:
		apron = Color(0.07, 0.16, 0.06)
	_box(Vector3(126, 0.04, 90), Vector3(0, -0.03, 0), _mat(apron, 0.0, 0.95))

func _pitch() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(118, 82)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	mi.mesh = pm
	pitch_mat = _shader_mat(PITCH_SHADER)
	pitch_mat.set_shader_parameter("grass", T_GRASS)
	var tint := Vector3(0.62, 0.68, 0.6)
	if tod == "day":
		tint = Vector3(0.6, 0.66, 0.56)
	elif tod == "dusk":
		tint = Vector3(0.6, 0.64, 0.56)
	if tier >= 2:
		tint *= Vector3(1.05, 0.97, 0.9)    # daha kuru, sarımsı çim
	pitch_mat.set_shader_parameter("tint", tint)
	pitch_mat.set_shader_parameter("wet", 1.0 if weather == "rain" else 0.0)
	pitch_mat.set_shader_parameter("snow", 1.0 if weather == "snow" else 0.0)
	mi.material_override = pitch_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _goals() -> void:
	var white := _mat(Color(0.97, 0.97, 0.97), 0.25, 0.25, 0.3)
	for sx in [-1.0, 1.0]:
		var g := Node3D.new()
		g.position = Vector3(52.5 * sx, 0, 0)
		add_child(g)
		var r := 0.06
		for z in [-3.66, 3.66]:
			var post := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = r
			cm.bottom_radius = r
			cm.height = 2.44
			post.mesh = cm
			post.material_override = white
			post.position = Vector3(0, 1.22, z)
			g.add_child(post)
			var back := MeshInstance3D.new()
			back.mesh = cm
			back.material_override = _mat(Color(0.8, 0.8, 0.82), 0.0, 0.4, 0.5)
			back.scale = Vector3(0.5, 1, 0.5)
			back.position = Vector3(1.9 * sx, 1.22, z)
			g.add_child(back)
		var bar := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = r
		bm.bottom_radius = r
		bm.height = 7.44
		bar.mesh = bm
		bar.material_override = white
		bar.rotation_degrees = Vector3(90, 0, 0)
		bar.position = Vector3(0, 2.44, 0)
		g.add_child(bar)
		var net := _shader_mat(NET_SHADER)
		net_mats.append(net)
		var back_q := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(7.32, 2.44)
		q.subdivide_width = 16
		q.subdivide_depth = 8
		back_q.mesh = q
		back_q.material_override = net
		back_q.rotation_degrees = Vector3(0, 90, 0)
		back_q.position = Vector3(1.95 * sx, 1.22, 0)
		g.add_child(back_q)
		var top_q := MeshInstance3D.new()
		var q2 := QuadMesh.new()
		q2.size = Vector2(1.95, 7.32)
		top_q.mesh = q2
		top_q.material_override = net
		top_q.rotation_degrees = Vector3(-90, 0, 0)
		top_q.position = Vector3(0.975 * sx, 2.44, 0)
		g.add_child(top_q)
		for z in [-3.66, 3.66]:
			var side_q := MeshInstance3D.new()
			var q3 := QuadMesh.new()
			q3.size = Vector2(1.95, 2.44)
			side_q.mesh = q3
			side_q.material_override = net
			side_q.position = Vector3(0.975 * sx, 1.22, z)
			g.add_child(side_q)

# ================================================================ tribünler

func _tier_mesh(length: float, rows: int, rise: float, depth: float) -> ArrayMesh:
	## Basamaklı tribün: dikey yüzlerde seyirci (UV2.y = sıra no), yatay yüzler beton.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl := length / 2.0
	for i in rows:
		var y0 := i * rise
		var z0 := i * depth
		var y1 := y0 + rise
		var n := Vector3(0, 0, -1)
		var verts := [Vector3(-hl, y0, z0), Vector3(hl, y0, z0), Vector3(hl, y1, z0), Vector3(-hl, y1, z0)]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(Vector2(uvs[idx].x, 1.0 - uvs[idx].y))
			st.set_uv2(Vector2(0, float(i)))
			st.add_vertex(verts[idx])
	var crowd := st.commit()
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rows:
		var y1 := (i + 1) * rise
		var z0 := i * depth
		var z1 := z0 + depth
		var verts := [Vector3(-hl, y1, z0), Vector3(hl, y1, z0), Vector3(hl, y1, z1), Vector3(-hl, y1, z1)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st2.set_normal(Vector3.UP)
			st2.add_vertex(verts[idx])
	st2.commit(crowd)
	return crowd

func _concrete() -> StandardMaterial3D:
	var c := Color(0.13, 0.14, 0.16) if tod != "day" else Color(0.42, 0.42, 0.44)
	if tier >= 2:
		c = c.lerp(Color(0.5, 0.47, 0.42), 0.25)
	return _mat(c, 0.0, 0.9)

func _dark() -> StandardMaterial3D:
	return _mat(Color(0.06, 0.065, 0.075) if tod != "day" else Color(0.18, 0.19, 0.21), 0.0, 0.7)

## opts: upper (2 kat), roof, away, back_wall
func _stand(length: float, rows: int, pos: Vector3, rot_y: float, opts := {}) -> void:
	var node := Node3D.new()
	node.position = pos
	node.rotation_degrees.y = rot_y
	add_child(node)
	var concrete := _concrete()
	var dark := _dark()
	var rise := 0.85
	var depth := 0.8
	var base_h: float = opts.get("base", 1.4)
	var lower := MeshInstance3D.new()
	lower.mesh = _tier_mesh(length, rows, rise, depth)
	var cm_low: ShaderMaterial = _crowd_for(length, opts.get("away", false))
	lower.set_surface_override_material(0, cm_low)
	lower.set_surface_override_material(1, concrete)
	lower.position = Vector3(0, base_h, 0)
	node.add_child(lower)
	_box(Vector3(length, base_h, 0.4), Vector3(0, base_h / 2.0, -0.2), dark, Vector3.ZERO, node)
	var top_y := base_h + rows * rise
	var back_z := rows * depth
	if opts.get("upper", false):
		var rows2 := rows - 3
		var bal_y := top_y + 2.2
		_box(Vector3(length, 2.2, 0.5), Vector3(0, top_y + 1.1, back_z - 0.2), dark, Vector3.ZERO, node)
		_box(Vector3(length, 0.5, 0.1), Vector3(0, top_y + 1.2, back_z - 0.5), led_mat, Vector3.ZERO, node)
		var up := MeshInstance3D.new()
		up.mesh = _tier_mesh(length, rows2, rise * 1.05, depth)
		up.set_surface_override_material(0, _crowd_for(length, opts.get("away", false)))
		up.set_surface_override_material(1, concrete)
		up.position = Vector3(0, bal_y, back_z - 0.3)
		node.add_child(up)
		top_y = bal_y + rows2 * rise * 1.05
		back_z = back_z - 0.3 + rows2 * depth
	if opts.get("back_wall", true):
		_box(Vector3(length + 1, top_y + 2.0, 1.0), Vector3(0, (top_y + 2.0) / 2.0, back_z + 0.5), concrete, Vector3.ZERO, node)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.6, top_y, back_z), Vector3(sx * length / 2.0, top_y / 2.0, back_z / 2.0), dark, Vector3.ZERO, node)
	if opts.get("roof", false):
		var ry := top_y + (6.0 if tier <= 1 else 3.2)
		var roof_m := _mat(Color(0.1, 0.11, 0.13) if tod != "day" else Color(0.55, 0.57, 0.6), 0.0, 0.5, 0.4)
		_box(Vector3(length + 2, 0.5, back_z + 6), Vector3(0, ry, back_z / 2.0 - 2.0), roof_m, Vector3(-4, 0, 0), node)
		if is_night():
			_box(Vector3(length - 4, 0.25, 0.6), Vector3(0, ry - 0.9, -3.5), _mat(Color(1.0, 0.97, 0.9), 5.0), Vector3.ZERO, node)
		var truss := _mat(Color(0.35, 0.36, 0.4), 0.0, 0.35, 0.7)
		var n := maxi(1, int(length / 12.0))
		for i in n + 1:
			var x := -length / 2.0 + i * (length / n)
			_box(Vector3(0.3, 0.3, back_z + 6), Vector3(x, ry + 0.6, back_z / 2.0 - 2.0), truss, Vector3(-4, 0, 0), node)
			_box(Vector3(0.35, ry, 0.35), Vector3(x, ry / 2.0, back_z + 0.2), truss, Vector3.ZERO, node)
	if opts.has("screen"):
		_screen(node, Vector3(0, top_y + 5.5, back_z + 0.2))

func _stand_at(length: float, rows: int, pos: Vector3, opts := {}) -> void:
	var d := Vector2(pos.x, pos.z).normalized()
	var rot := rad_to_deg(atan2(d.x, d.y))
	_stand(length, rows, pos, rot, opts)

func _stands_arena() -> void:
	_stand_at(112.0, 14, Vector3(0, 0, 40.5), {"upper": true, "roof": true})
	_stand_at(112.0, 14, Vector3(0, 0, -40.5), {"upper": true, "roof": true})
	_stand_at(70.0, 16, Vector3(61.5, 0, 0), {"roof": true, "screen": true})
	_stand_at(70.0, 16, Vector3(-61.5, 0, 0), {"roof": true, "away": true})
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_stand_at(24.0, 12, Vector3(sx * 58.5, 0, sz * 39.5), {})

func _stands_mid() -> void:
	_stand_at(100.0, 12, Vector3(0, 0, 40.5), {})   # yayın kamerası bu tribünün üstünde: çatı yok
	_stand_at(100.0, 11, Vector3(0, 0, -40.5), {"roof": true})
	_stand_at(62.0, 10, Vector3(61.5, 0, 0), {"screen": true})
	_stand_at(62.0, 10, Vector3(-61.5, 0, 0), {"away": true})

func _stands_small() -> void:
	_stand_at(64.0, 8, Vector3(0, 0, -40.0), {"roof": true, "base": 0.9})
	_stand_at(80.0, 5, Vector3(0, 0, 40.0), {"base": 0.6, "back_wall": false})
	_stand_at(26.0, 4, Vector3(-59.5, 0, 0), {"base": 0.5, "away": true, "back_wall": false})
	_fence(Vector2(124, 88))

func _stands_ground() -> void:
	_stand_at(18.0, 4, Vector3(-14, 0, -39.0), {"base": 0.4, "back_wall": false})
	_stand_at(18.0, 4, Vector3(14, 0, -39.0), {"base": 0.4, "back_wall": false})
	_fence(Vector2(120, 84))

func _fence(sz: Vector2) -> void:
	## Saha çevresi tel örgü
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.55, 0.5, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pole := _mat(Color(0.35, 0.37, 0.36), 0.0, 0.5, 0.5)
	for side in 4:
		var horiz := side < 2
		var L := sz.x if horiz else sz.y
		var pos := Vector3(0, 1.5, (sz.y / 2.0) * (1 if side == 0 else -1)) if horiz else Vector3((sz.x / 2.0) * (1 if side == 2 else -1), 1.5, 0)
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(L, 3.0)
		mi.mesh = q
		mi.material_override = mat
		mi.position = pos
		mi.rotation_degrees.y = 0 if horiz else 90
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var n := int(L / 6.0)
		for i in n + 1:
			var o := -L / 2.0 + i * L / n
			var pp := pos + (Vector3(o, 0, 0) if horiz else Vector3(0, 0, o))
			_box(Vector3(0.08, 3.0, 0.08), pp, pole)

func _screen(parent: Node3D, pos: Vector3) -> void:
	## Dev skor ekranı (Label3D: Compat'ta güvenli)
	_box(Vector3(18, 7.5, 0.6), pos, _mat(Color(0.03, 0.03, 0.035)), Vector3.ZERO, parent)
	_box(Vector3(17, 6.6, 0.1), pos + Vector3(0, 0, -0.33), _mat(Color(0.02, 0.04, 0.08), 0.6), Vector3.ZERO, parent)
	var l := Label3D.new()
	l.text = ""
	l.font = load("res://fonts/BarlowCondensed-ExtraBold.ttf")
	l.font_size = 220
	l.pixel_size = 0.012
	l.modulate = Color(1.0, 0.95, 0.8)
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.position = pos + Vector3(0, 0.4, -0.4)
	l.rotation_degrees.y = 180
	parent.add_child(l)
	var l2 := Label3D.new()
	l2.font = l.font
	l2.font_size = 110
	l2.pixel_size = 0.012
	l2.modulate = Color(home_c1.lightened(0.3))
	l2.position = pos + Vector3(0, -2.3, -0.4)
	l2.rotation_degrees.y = 180
	parent.add_child(l2)
	board = l
	board2 = l2

func set_board(score: String, sub: String) -> void:
	if board:
		board.text = score
		board2.text = sub

func _make_led() -> ShaderMaterial:
	led_mat = _shader_mat(LED_SHADER)
	led_mat.set_shader_parameter("ads", T_ADS)
	led_mat.set_shader_parameter("n_ads", float(T_ADS.get_height()) / 128.0)
	led_mat.set_shader_parameter("c1", Vector3(home_c1.r, home_c1.g, home_c1.b))
	led_mat.set_shader_parameter("led", 1.0 if tier <= 1 else 0.0)
	led_mat.set_shader_parameter("bright", 1.6 if is_night() else 1.1)
	return led_mat

var _crowd_cache := {}
func _crowd_for(length: float, away := false) -> ShaderMaterial:
	if crowd_mat == null:
		crowd_mat = _shader_mat(CROWD_SHADER)
		crowd_mat.set_shader_parameter("photo", T_CROWD)
	var key := "%d_%s" % [int(length), away]
	if _crowd_cache.has(key):
		return _crowd_cache[key]
	var m: ShaderMaterial = crowd_mat.duplicate()
	m.set_shader_parameter("c1", Vector3(home_c1.r, home_c1.g, home_c1.b))
	m.set_shader_parameter("c2", Vector3(home_c2.r, home_c2.g, home_c2.b))
	m.set_shader_parameter("c3", Vector3(away_c1.r, away_c1.g, away_c1.b))
	m.set_shader_parameter("length_m", length)
	m.set_shader_parameter("away_share", 0.55 if away else 0.0)
	m.set_shader_parameter("light", {"day": 0.95, "dusk": 0.8}.get(tod, 0.72))
	m.set_shader_parameter("flashes", 1.0 if is_night() else 0.0)
	_crowd_cache[key] = m
	return m

func _beam(parent: Node3D, from: Vector3, to: Vector3, strength := 0.05) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var length := from.distance_to(to)
	cm.top_radius = 0.6
	cm.bottom_radius = 9.0
	cm.height = length
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 16
	mi.mesh = cm
	var m := _shader_mat(BEAM_SHADER)
	m.set_shader_parameter("strength", strength)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = (from + to) / 2.0
	var dir := (to - from).normalized()
	var y := -dir
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length() < 0.1:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	mi.basis = Basis(x, y, z)

func _flare(pos: Vector3, size: float, strength: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := _shader_mat(FLARE_SHADER)
	m.set_shader_parameter("strength", strength)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	add_child(mi)
	lens.append(mi)

func _lights() -> void:
	var pole := _mat(Color(0.3, 0.31, 0.34), 0.0, 0.35, 0.6)
	var on := is_night()
	var lamp := _mat(Color(1.0, 0.98, 0.92), 7.0 if on else 0.4)
	var hq := Game.quality() != "low" and fx_enabled
	var spots: Array = []
	match tier:
		0:
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					spots.append([Vector3(sx * 70.0, 0, sz * 54.0), 46.0, 4])
		1:
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					spots.append([Vector3(sx * 66.0, 0, sz * 50.0), 38.0, 3])
		2:
			for x in [-40.0, 0.0, 40.0]:
				for sz in [-1.0, 1.0]:
					spots.append([Vector3(x, 0, sz * 50.0), 26.0, 2])
		_:
			for x in [-35.0, 35.0]:
				for sz in [-1.0, 1.0]:
					spots.append([Vector3(x, 0, sz * 46.0), 18.0, 1])
	for s in spots:
		var p: Vector3 = s[0]
		var h: float = s[1]
		var cols: int = s[2]
		var pole_mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18 + h * 0.007
		cm.bottom_radius = 0.3 + h * 0.012
		cm.height = h
		pole_mi.mesh = cm
		pole_mi.material_override = pole
		pole_mi.position = p + Vector3(0, h / 2.0, 0)
		add_child(pole_mi)
		var head := Node3D.new()
		head.position = p + Vector3(0, h + 0.5, 0)
		add_child(head)
		head.look_at(Vector3(p.x * 0.3, 0, 0), Vector3.UP)
		var hw := cols * 2.2 + 0.4
		_box(Vector3(hw, 3.8 if cols > 1 else 2.0, 0.5), Vector3.ZERO, pole, Vector3.ZERO, head)
		var rows := 3 if cols > 1 else 2
		for ix in cols:
			for iy in rows:
				_box(Vector3(1.6, 1.0, 0.2), Vector3(-(cols - 1) * 1.1 + ix * 2.2, -1.1 * (rows - 1) / 2.0 + iy * 1.1, -0.35), lamp, Vector3.ZERO, head)
		if on:
			var omni := OmniLight3D.new()
			omni.position = p * 0.75 + Vector3(0, h * 0.65, 0)
			omni.omni_range = 90.0
			omni.light_energy = 0.16 if tier <= 1 else 0.2
			omni.light_color = Color(1.0, 0.97, 0.9)
			# ıslak çimde köşede beyaz parlama yapmasın
			omni.light_specular = 0.0
			add_child(omni)
			if hq:
				_flare(head.position + (Vector3(-p.x, 0, -p.z).normalized() * 0.8), 8.0 + cols * 3.0, 0.9 if tod == "night" else 0.55)
				if Game.quality() == "high" or tier <= 1:
					_beam(self, head.position, Vector3(p.x * 0.35, 0, p.z * 0.2), 0.016 if weather == "clear" else 0.02)

func _led_boards() -> void:
	var back := _mat(Color(0.05, 0.05, 0.06))
	var L := 96.0 if tier <= 1 else 70.0
	var panels := L / 7.6
	for sz in [-1.0, 1.0]:
		var mi := _box(Vector3(L, 1.2, 0.15), Vector3(0, 0.6, sz * 37.2), led_mat)
		_board_uv(mi, L / 9.6, Vector3(L, 1.2, 0.15))
		_box(Vector3(L, 1.2, 0.3), Vector3(0, 0.6, sz * 37.45), back)
	if tier <= 2:
		for sx in [-1.0, 1.0]:
			for z in [-22.0, 22.0]:
				var mi2 := _box(Vector3(0.15, 1.2, 26), Vector3(sx * 56.0, 0.6, z), led_mat)
				_board_uv(mi2, 26.0 / 9.6, Vector3(0.15, 1.2, 26))

func _board_uv(mi: MeshInstance3D, panels: float, bsize := Vector3(96, 1.2, 0.15)) -> void:
	var m: ShaderMaterial = led_mat.duplicate()
	m.set_shader_parameter("panels", maxf(1.0, round(panels)))
	m.set_shader_parameter("bsize", bsize)
	m.set_shader_parameter("seed", float(led_mats.size()) * 1.7 + 0.3)
	mi.material_override = m
	led_mats.append(m)

func _flags() -> void:
	var flag_mat := _shader_mat(FLAG_SHADER)
	flag_mat.set_shader_parameter("col", Vector3(home_c1.r, home_c1.g, home_c1.b))
	var pole := _mat(Color(0.95, 0.95, 0.95))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * 52.5, 0, sz * 34.0)
			_box(Vector3(0.04, 1.5, 0.04), p + Vector3(0, 0.75, 0), pole)
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.45, 0.32)
			q.subdivide_width = 6
			mi.mesh = q
			mi.material_override = flag_mat
			mi.position = p + Vector3(0.24 * -sx, 1.33, 0)
			mi.rotation_degrees.y = 0 if sx < 0 else 180
			add_child(mi)

func _dugouts() -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.85, 1.0, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.5
	var seat := _mat(home_c1.darkened(0.2), 0.0, 0.5)
	var z := 38.4 if tier <= 1 else 36.4
	for x in [-9.0, 9.0]:
		var n := Node3D.new()
		n.position = Vector3(x, 0, z)
		add_child(n)
		_box(Vector3(7, 0.08, 1.8), Vector3(0, 2.2, 0), glass, Vector3(-10, 0, 0), n)
		_box(Vector3(7, 2.2, 0.08), Vector3(0, 1.1, 0.9), glass, Vector3.ZERO, n)
		for i in 8:
			_box(Vector3(0.5, 0.5, 0.5), Vector3(-3.0 + i * 0.85, 0.25, 0.4), seat, Vector3.ZERO, n)

func _surroundings() -> void:
	## Küçük stadyumlar: çevrede ağaçlar ve evler (çok örnekli tek çizim)
	if tier < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + tier
	var pts: Array = []
	for i in 160:
		var a := rng.randf() * TAU
		var r := rng.randf_range(78.0, 140.0)
		var p := Vector3(cos(a) * r * 1.25, 0, sin(a) * r)
		if absf(p.z) < 52.0 and absf(p.x) < 72.0:
			continue
		pts.append(p)
	var leaf := Color(0.09, 0.2, 0.07) if tod == "day" else Color(0.025, 0.06, 0.035)
	if tod == "dusk":
		leaf = Color(0.06, 0.12, 0.05)
	if weather == "snow":
		leaf = Color(0.55, 0.58, 0.6)
	# taç: düz gölgeli düşük çokgen, her ağaç farklı ton ve boy
	var crown := SphereMesh.new()
	crown.radius = 3.0
	crown.height = 6.4
	crown.radial_segments = 7
	crown.rings = 4
	var pine := CylinderMesh.new()
	pine.top_radius = 0.0
	pine.bottom_radius = 2.6
	pine.height = 9.0
	pine.radial_segments = 7
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = 3.0
	trunk.radial_segments = 5
	var mms := []
	for mesh in [crown, pine, trunk]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mms.append(mm)
	var lists := [[], [], []]
	for p in pts:
		var s2 := rng.randf_range(0.8, 1.6)
		var kind := 1 if rng.randf() < 0.35 else 0
		var tone := leaf * rng.randf_range(0.75, 1.25)
		tone.a = 1.0
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		if kind == 0:
			lists[0].append([Transform3D(yaw.scaled(Vector3(s2, s2 * rng.randf_range(0.9, 1.25), s2)), p + Vector3(0, 2.6 * s2 + 2.6, 0)), tone])
		else:
			lists[1].append([Transform3D(yaw.scaled(Vector3(s2, s2 * 1.1, s2)), p + Vector3(0, 4.9 * s2 + 1.2, 0)), tone.darkened(0.15)])
		lists[2].append([Transform3D(Basis().scaled(Vector3(s2, s2, s2)), p + Vector3(0, 1.5 * s2, 0)), Color(0.18, 0.12, 0.08) * (0.5 if tod != "day" else 1.0)])
	for k in 3:
		var mm: MultiMesh = mms[k]
		mm.instance_count = lists[k].size()
		for i in lists[k].size():
			mm.set_instance_transform(i, lists[k][i][0])
			mm.set_instance_color(i, lists[k][i][1])
		var tmi := MultiMeshInstance3D.new()
		tmi.multimesh = mm
		var tm := StandardMaterial3D.new()
		tm.vertex_color_use_as_albedo = true
		tm.roughness = 0.95
		tmi.material_override = tm
		tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tmi)
	# evler: tek çatılı kutular, gece pencereler yanar
	var wm := _shader_mat(WINDOW_SHADER)
	wm.set_shader_parameter("night", 1.0 if is_night() else 0.0)
	wm.set_shader_parameter("wall", Vector3(0.55, 0.5, 0.45) if tod == "day" else Vector3(0.12, 0.11, 0.1))
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(150.0, 210.0)
		var p := Vector3(cos(a) * r * 1.2, 0, sin(a) * r)
		var h := rng.randf_range(7.0, 22.0)
		var w := rng.randf_range(12.0, 22.0)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, 10.0)
		mi.mesh = bm
		mi.material_override = wm
		mi.position = p + Vector3(0, h / 2.0, 0)
		mi.rotation.y = -a + PI / 2.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

func _effects() -> void:
	if not fx_enabled:
		return
	# konfeti (CPU parçacıkları: tüm telefonlarda güvenli), yalnız büyük statlarda
	if tier > 1:
		return
	for sx in [-1.0, 1.0]:
		var p := CPUParticles3D.new()
		p.amount = 90
		p.lifetime = 3.5
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.85
		p.position = Vector3(sx * 30.0, 22.0, 46.0)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(22, 2, 6)
		p.direction = Vector3(0, 1, -0.6)
		p.spread = 50.0
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 9.0
		p.gravity = Vector3(0, -3.0, 0)
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
		grad.colors = PackedColorArray([home_c1, Color.WHITE, home_c2.lightened(0.3), home_c1])
		p.color_initial_ramp = grad
		var q := QuadMesh.new()
		q.size = Vector2(0.35, 0.22)
		var qm := StandardMaterial3D.new()
		qm.vertex_color_use_as_albedo = true
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = qm
		p.mesh = q
		add_child(p)
		confetti.append(p)

func disable_glow() -> void:
	for we in find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment.glow_enabled = false
		(we as WorldEnvironment).environment.fog_enabled = false

func set_fill(v: float) -> void:
	for k in _crowd_cache:
		_crowd_cache[k].set_shader_parameter("fill", v)

var _last_ex := -1.0
func set_excite(v: float) -> void:
	for k in _crowd_cache:
		_crowd_cache[k].set_shader_parameter("excite", v)
	if absf(v - _last_ex) < 0.02 and v > 0.0:
		return
	_last_ex = v
	for mm in led_mats + [led_mat]:
		if mm:
			mm.set_shader_parameter("pulse", clampf(v, 0.0, 1.0))

func goal_fx(side: float, home_scored: bool) -> void:
	for p in confetti:
		p.restart()
		p.emitting = true

func net_hit(goal_x: float, hit: Vector3) -> void:
	var idx := 0 if goal_x < 0 else 1
	if idx >= net_mats.size():
		return
	var m: ShaderMaterial = net_mats[idx]
	m.set_shader_parameter("hit", hit)
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("bulge", v), 0.0, 1.0, 0.12)
	tw.tween_method(func(v): m.set_shader_parameter("bulge", v), 1.0, 0.0, 1.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
