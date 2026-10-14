extends SubViewportContainer
## Menülerin arkasındaki kalıcı 3D dünya. İstasyonlar: ofis masası, dedektif panosu,
## harita masası, oyuncu kürsüsü, stadyum. goto(istasyon) ile kamera uçar.

const FB = preload("res://three/mocap_man.gd")
const Stadium = preload("res://three/stadium.gd")
const TrMap = preload("res://ui/map.gd")
const Europe = preload("res://ui/europe.gd")

var sv: SubViewport
var world: Node3D
var cam: Camera3D
var cam_look := Vector3.ZERO
var station := ""
var orbit := false
var orbit_t := 0.0
var tween: Tween
var font: Font

# dinamik parçalar
var board_root: Node3D
var map_root: Node3D
var map_dyn: Node3D
var ped_root: Node3D
var ped_player: Node3D
var ped_turn := 0.0
var ped_ball: MeshInstance3D
var pennant_mat: StandardMaterial3D
var pennant_mat2: StandardMaterial3D
var trophy_root: Node3D
var stadium_built := false
var stadium_node: Node3D
var stadium_men := []
var laptop_mat: ShaderMaterial
# --- yaşayan ofis
const MM = preload("res://three/mocap_man.gd")
var city_mat: ShaderMaterial
var me_man: Node3D
var phone_node: Node3D
var ring_t := -1.0
var tv_lines: Array = []
var tv_ticker: Label3D
var tv_t := 0.0
var tv_i := 0
var news_seen := -1
var clock_t := 0.0

const OFFICE := Vector3(0, 0, 0)
const MAP := Vector3(40, 0, 0)
const PED := Vector3(80, 0, 0)
const STAD := Vector3(400, 0, 0)

const STATIONS := {
	"office": [Vector3(1.25, 1.85, 1.3), Vector3(-0.15, 1.1, -2.6)],
	"desk": [Vector3(2.9, 1.75, -0.3), Vector3(1.6, 1.55, -3.6)],
	"board": [Vector3(0.4, 1.85, -1.2), Vector3(-4.9, 1.8, -1.2)],
	"map": [Vector3(40, 12.5, 3.4), Vector3(40, 0.9, 0.5)],
	"pedestal": [Vector3(80.0, 1.55, 5.2), Vector3(80, 1.25, 0)],
	"stadium": [Vector3(400 - 30, 22, 38), Vector3(400, 0, 0)],
}
var pitch_deg := 0.0
var active := true
## UI'nin üstünde görünen boş şerit (ekran koordinatı). Boşsa tam ekran.
var band := Rect2()
## şerit modunda istasyon başına yatay görüş açısı
const BAND_HFOV := {"office": 74.0, "desk": 66.0, "board": 34.0, "map": 36.0, "pedestal": 56.0, "stadium": 70.0}

func set_band(r: Rect2) -> void:
	band = r
	if band.size.y < 40.0:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		# yalnızca görünen şeridi (+ sekme boşlukları için biraz pay) çiz: hem tam kadraj hem daha az GPU
		set_anchors_preset(Control.PRESET_TOP_WIDE)
		offset_left = 0
		offset_right = 0
		offset_top = band.position.y
		offset_bottom = band.end.y + BAND_PAD
	_apply_proj(true)

const BAND_PAD := 70.0
var fov_target := 55.0

func _apply_proj(snap := false) -> void:
	if band.size.y < 40.0 or orbit:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		fov_target = 55.0
	else:
		var hf: float = BAND_HFOV.get(station, 70.0)
		var ar := size.x / maxf(band.size.y, 1.0)
		hf = clampf(hf * clampf(ar / 1.8, 0.8, 1.15), 30.0, 100.0)
		if cam.keep_aspect != Camera3D.KEEP_WIDTH:
			snap = true
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		fov_target = hf
	if snap:
		cam.fov = fov_target

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and cam:
		_apply_proj(true)

func set_pitch(deg: float) -> void:
	pitch_deg = deg

func set_active(on: bool) -> void:
	if on and not active:
		Watch.check_vp(sv, "hub-geri")
	active = on
	# v0.20: render hedefini artık küçültüp büyütmüyoruz (Adreno'da yeniden ayırma donmaya yol açabiliyordu);
	# hub zaten yalnızca üstteki şeridi çiziyor, kapalıyken sadece güncelleme durur.
	if on:
		_apply_proj.call_deferred()
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)
	visible = on

const WOOD_SHADER := """
shader_type spatial;
uniform vec3 c1 = vec3(0.18, 0.1, 0.05);
uniform vec3 c2 = vec3(0.26, 0.15, 0.08);
uniform float scale = 6.0;
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	vec2 p = UV * vec2(scale, scale * 0.25);
	float plank = floor(p.y * 4.0);
	float off = hash(plank) * 3.0;
	float grain = sin((p.x + off) * 40.0 + sin(p.y * 30.0) * 2.0) * 0.5 + 0.5;
	vec3 col = mix(c1, c2, grain * 0.6 + hash(plank + floor(p.x + off)) * 0.4);
	float seam = step(0.97, fract(p.y * 4.0));
	col *= 1.0 - seam * 0.5;
	ALBEDO = col;
	ROUGHNESS = 0.55;
}
"""

const WALL_SHADER := """
shader_type spatial;
uniform vec3 col = vec3(0.07, 0.14, 0.11);
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float n = hash(floor(UV * 300.0)) * 0.05;
	float panel = step(0.985, fract(UV.x * 6.0));
	ALBEDO = col * (0.95 + n) * (1.0 - panel * 0.3);
	ROUGHNESS = 0.9;
}
"""

const CITY_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float day = 0.0;      // 0 gece, 1 gündüz
uniform float dusk = 0.0;     // akşam/şafak kızıllığı
uniform float rain = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 night = mix(vec3(0.12, 0.08, 0.16), vec3(0.01, 0.015, 0.05), 1.0 - uv.y);
	vec3 dayc = mix(vec3(0.75, 0.85, 0.95), vec3(0.35, 0.55, 0.85), 1.0 - uv.y);
	vec3 duskc = mix(vec3(0.95, 0.55, 0.3), vec3(0.3, 0.2, 0.45), 1.0 - uv.y);
	vec3 sky = mix(night, dayc, day);
	sky = mix(sky, duskc, dusk);
	float star = step(0.996, hash(floor(uv * vec2(220.0, 140.0)))) * step(0.45, 1.0 - uv.y) * (1.0 - day) * (1.0 - rain);
	vec3 col = sky + vec3(star);
	float bx = floor(uv.x * 26.0);
	float bh = 0.25 + hash(vec2(bx, 3.0)) * 0.45;
	if (1.0 - uv.y < bh) {
		vec2 w = fract(uv * vec2(26.0 * 5.0, 60.0));
		float lit = step(0.55 + day * 0.35, hash(floor(uv * vec2(26.0 * 5.0, 60.0)) + floor(TIME * 0.05)));
		float win = step(0.25, w.x) * step(w.x, 0.75) * step(0.3, w.y) * step(w.y, 0.8);
		vec3 bld = mix(vec3(0.02, 0.025, 0.04), vec3(0.42, 0.45, 0.5) * (0.7 + 0.3 * hash(vec2(bx, 7.0))), day);
		col = bld + vec3(1.0, 0.8, 0.45) * win * lit * 0.8 * (1.0 - day * 0.8);
	}
	float glow = exp(-pow(length((uv - vec2(0.7, 0.62)) * vec2(1.0, 2.5)), 2.0) * 20.0);
	col += vec3(0.9, 0.95, 1.0) * glow * 0.6 * (1.0 - day);
	// yağmur: camda süzülen damlalar + gri perde
	if (rain > 0.0) {
		col = mix(col, vec3(0.35, 0.38, 0.42) * (0.4 + day * 0.6), rain * 0.45);
		vec2 r = uv * vec2(70.0, 9.0);
		float cx = floor(r.x);
		float sp = 0.6 + hash(vec2(cx, 1.0));
		float yy = fract(r.y - TIME * sp + hash(vec2(cx, 2.0)) * 10.0);
		float streak = step(0.85, hash(vec2(cx, 3.0))) * smoothstep(0.0, 0.08, yy) * (1.0 - smoothstep(0.08, 0.5, yy)) * step(abs(fract(r.x) - 0.5), 0.08);
		col += vec3(0.6, 0.65, 0.7) * streak * rain;
	}
	ALBEDO = col;
}
"""

const LAPTOP_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 accent = vec3(0.91, 0.77, 0.28);
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 col = vec3(0.03, 0.06, 0.05);
	// üst bar
	col = mix(col, vec3(0.06, 0.12, 0.09), step(0.88, uv.y));
	// sol: radar
	vec2 c = vec2(0.24, 0.45);
	vec2 d = (uv - c) * vec2(1.6, 1.0);
	float r = length(d);
	float ang = atan(d.y, d.x);
	float hex = 0.32 + 0.08 * sin(ang * 3.0 + TIME * 0.5);
	col = mix(col, accent * 0.7, step(r, hex) * 0.5);
	col += vec3(0.2) * (step(abs(r - 0.33), 0.004) + step(abs(r - 0.2), 0.004));
	// sağ: çubuk grafik
	if (uv.x > 0.5 && uv.x < 0.95 && uv.y > 0.15 && uv.y < 0.8) {
		float bar = floor((uv.x - 0.5) / 0.45 * 7.0);
		float h = 0.2 + hash(bar + floor(TIME * 0.3)) * 0.55;
		float on = step(uv.y, 0.15 + h * 0.65) * step(0.15, fract((uv.x - 0.5) / 0.45 * 7.0));
		col = mix(col, mix(vec3(0.36, 0.81, 0.48), accent, hash(bar)), on);
	}
	float scan = 0.94 + 0.06 * sin(uv.y * 400.0);
	ALBEDO = col * scan * 1.6;
}
"""

const CORK_SHADER := """
shader_type spatial;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float n = hash(floor(UV * vec2(320.0, 180.0)));
	vec3 col = mix(vec3(0.42, 0.28, 0.16), vec3(0.55, 0.38, 0.22), n);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
"""

const HOLO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec3 col = vec3(0.4, 0.8, 0.6);
void fragment() {
	vec2 g = fract(UV * vec2(40.0, 24.0));
	float line = (1.0 - step(0.04, g.x)) + (1.0 - step(0.04, g.y));
	float fade = 1.0 - length(UV - 0.5) * 1.6;
	ALBEDO = col * (0.04 + line * 0.12) * max(fade, 0.0);
}
"""

func _ready() -> void:
	stretch = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = Post.make("office")
	sv = SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_2X if Game.quality() == "high" and not Game.settings.get("safe3d", false) else Viewport.MSAA_DISABLED
	sv.scaling_3d_scale = Game.q_scale()
	sv.audio_listener_enable_3d = false
	add_child(sv)
	world = Node3D.new()
	sv.add_child(world)
	cam = Camera3D.new()
	cam.fov = 55
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 600
	world.add_child(cam)
	_env()
	_build_office(0)
	_build_map()
	_build_pedestal()
	Watch.check_vp(sv, "hub", func():
		for we in find_children("*", "WorldEnvironment", true, false):
			(we as WorldEnvironment).environment.glow_enabled = false)
	cam.position = STATIONS.office[0]
	cam_look = STATIONS.office[1]
	cam.look_at(cam_look)

func apply_quality() -> void:
	sv.msaa_3d = Viewport.MSAA_2X if Game.quality() == "high" and not Game.settings.get("safe3d", false) else Viewport.MSAA_DISABLED
	sv.scaling_3d_scale = Game.q_scale()

func setup_font(f: Font) -> void:
	font = f

# ================================================================ yardımcılar

func _shader(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func _mat(col: Color, rough := 0.7, metal := 0.0, emis := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emis > 0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emis
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, segs := 20) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _label(parent: Node3D, text: String, pos: Vector3, size := 0.004, col := Color.WHITE, billboard := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = size
	l.modulate = col
	l.outline_size = 8
	l.position = pos
	if font:
		l.font = font
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l

func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = not OS.has_feature("mobile")
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	we.environment = env
	world.add_child(we)

# ================================================================ ofis

## Ofis kariyerle büyür: 0 = dar bölge ofisi, 1 = kulüp scout odası, 2 = direktör ofisi
var office_node: Node3D
var office_level := -1
var clock_h: Node3D
var clock_m: Node3D

const PHOTO_WINDOW := """
shader_type spatial;
render_mode unshaded;
uniform sampler2D city : source_color, filter_linear;
uniform float day = 0.0;
uniform float dusk = 0.0;
uniform float rain = 0.0;
uniform vec2 crop_x = vec2(0.0, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = vec2(mix(crop_x.x, crop_x.y, UV.x), UV.y);
	if (rain > 0.0) {
		// camdaki damlalar görüntüyü kırar
		vec2 g = uv * vec2(38.0, 22.0);
		vec2 c = floor(g);
		float d = hash(c);
		vec2 f = fract(g) - 0.5;
		float drop = step(0.82, d) * (1.0 - smoothstep(0.12, 0.28, length(f * vec2(1.0, 0.7))));
		uv += f * drop * 0.02;
	}
	vec3 p = texture(city, uv).rgb;
	float lum = dot(p, vec3(0.3, 0.59, 0.11));
	float warm = clamp((p.r - p.b) * 2.0, 0.0, 1.0);
	float lights = smoothstep(0.42, 0.75, lum) * warm * smoothstep(0.42, 0.5, uv.y);
	float skyw = 1.0 - smoothstep(0.38, 0.55, uv.y);
	// gece: gökyüzü koyu lacivert, şehir ışıkları parlak
	vec3 night = p * vec3(0.28, 0.32, 0.5) * (1.0 - skyw * 0.4) + p * lights * 1.6;
	night += vec3(0.01, 0.015, 0.04) * skyw;
	// gündüz: mavi gök, ışıklar sönük, binalar aydınlık
	vec3 skyd = mix(vec3(0.62, 0.76, 0.92), vec3(0.32, 0.52, 0.86), 1.0 - uv.y * 1.8);
	vec3 bld = mix(vec3(lum), p, 0.45) * 1.7 * (1.0 - lights * 0.5);
	vec3 dayc = mix(bld, skyd, skyw);
	vec3 col = mix(night, dayc, day);
	col = mix(col, p * 1.15, dusk);
	if (rain > 0.0) {
		col = mix(col, vec3(0.32, 0.35, 0.4) * (0.35 + day * 0.65), rain * 0.4);
		vec2 r = UV * vec2(60.0, 7.0);
		float cx = floor(r.x);
		float yy = fract(r.y - TIME * (0.5 + hash(vec2(cx, 1.0))) + hash(vec2(cx, 2.0)) * 10.0);
		float streak = step(0.86, hash(vec2(cx, 3.0))) * smoothstep(0.0, 0.06, yy) * (1.0 - smoothstep(0.06, 0.45, yy)) * step(abs(fract(r.x) - 0.5), 0.07);
		col += vec3(0.55, 0.6, 0.66) * streak * rain;
	}
	ALBEDO = col;
}
"""

const AO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 0.55;
uniform vec2 shape = vec2(1.0, 1.0);
void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float d = length(q * shape);
	ALBEDO = vec3(0.0);
	ALPHA = (1.0 - smoothstep(0.2, 1.0, d)) * strength;
}
"""

const TILE_SHADER := """
shader_type spatial;
uniform vec3 a = vec3(0.32, 0.33, 0.31);
uniform vec3 b = vec3(0.27, 0.28, 0.27);
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 g = UV * vec2(24.0, 20.0);
	vec2 c = floor(g);
	float chk = mod(c.x + c.y, 2.0);
	vec3 col = mix(a, b, chk) * (0.92 + 0.12 * hash(c));
	float grout = step(0.96, fract(g.x)) + step(0.96, fract(g.y));
	col *= 1.0 - clamp(grout, 0.0, 1.0) * 0.35;
	// eski: lekeler
	col *= 0.9 + 0.1 * hash(floor(UV * 7.0));
	ALBEDO = col;
	ROUGHNESS = 0.45;
}
"""

const PAINT_SHADER := """
shader_type spatial;
uniform vec3 col = vec3(0.5, 0.55, 0.48);
uniform vec3 panel = vec3(0.22, 0.13, 0.07);
uniform float wainscot = 0.0;   // alt duvar ahşap kaplama yüksekliği (UV.y oranı)
uniform float stains = 0.0;
uniform float slats = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y); }
void fragment() {
	vec3 c = col * (0.94 + 0.08 * noise(UV * vec2(80.0, 30.0)));
	c *= 1.0 - stains * smoothstep(0.55, 0.85, noise(UV * vec2(6.0, 3.0))) * 0.25;
	if (slats > 0.0) {
		float s = fract(UV.x * 90.0);
		c *= 0.82 + 0.18 * smoothstep(0.0, 0.12, s) * (1.0 - smoothstep(0.88, 1.0, s));
	}
	float y = 1.0 - UV.y;
	if (y < wainscot) {
		float pv = fract(UV.x * 14.0);
		vec3 w = panel * (0.85 + 0.15 * noise(UV * vec2(4.0, 60.0)));
		w *= 1.0 - (step(pv, 0.03) + step(0.97, pv)) * 0.4;
		w *= 1.0 - step(wainscot - 0.015, y) * 0.3;
		c = w;
	}
	// köşelere doğru kararma (pişmiş ortam gölgesi taklidi)
	float edge = min(min(UV.x, 1.0 - UV.x) * 6.0, 1.0) * min(y * 5.0 + 0.4, 1.0) * min((1.0 - y) * 8.0 + 0.3, 1.0);
	c *= 0.6 + 0.4 * edge;
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
"""

func _tex_mat(path: String, tint := Color.WHITE, scale := Vector2.ONE, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.albedo_color = tint
	m.uv1_scale = Vector3(scale.x, scale.y, 1)
	m.roughness = rough
	return m

func _ao(parent: Node3D, pos: Vector3, size: Vector2, strength := 0.5, rot := Vector3(-90, 0, 0)) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := _shader(AO_SHADER)
	m.set_shader_parameter("strength", strength)
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func office_level_for(title_k: String) -> int:
	match title_k:
		"title_0", "title_1":
			return 0
		"title_2":
			return 1
		_:
			return 2

func set_office_level(lv: int) -> void:
	if lv == office_level:
		return
	if office_node:
		office_node.queue_free()
		office_node = null
	tv_lines.clear()
	_build_office(lv)
	set_club(_club_c1, _club_c2)
	set_trophies(_trophy_n)

var _club_c1 := Color("#e8c547")
var _club_c2 := Color("#123524")
var _trophy_n := 0

func _build_office(lv := 0) -> void:
	office_level = lv
	var o := Node3D.new()
	o.position = OFFICE
	world.add_child(o)
	office_node = o
	# ---------------- zemin
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 10)
	fl.mesh = pm
	if lv == 0:
		fl.material_override = _shader(TILE_SHADER)
	else:
		var wood := _shader(WOOD_SHADER)
		if lv == 2:
			wood.set_shader_parameter("c1", Vector3(0.1, 0.055, 0.03))
			wood.set_shader_parameter("c2", Vector3(0.17, 0.095, 0.05))
			wood.set_shader_parameter("scale", 9.0)
		fl.material_override = wood
	fl.position = Vector3(0, 0, -1)
	o.add_child(fl)
	# ---------------- duvarlar
	var wall := _shader(PAINT_SHADER)
	match lv:
		0:
			wall.set_shader_parameter("col", Vector3(0.42, 0.46, 0.4))
			wall.set_shader_parameter("stains", 1.0)
		1:
			wall.set_shader_parameter("col", Vector3(0.1, 0.2, 0.15))
			wall.set_shader_parameter("wainscot", 0.32)
		2:
			wall.set_shader_parameter("col", Vector3(0.1, 0.12, 0.17))
			wall.set_shader_parameter("panel", Vector3(0.16, 0.09, 0.05))
			wall.set_shader_parameter("wainscot", 0.24)
			wall.set_shader_parameter("slats", 1.0)
	_box(o, Vector3(12, 4.2, 0.2), Vector3(0, 2.1, -4.0), wall)
	_box(o, Vector3(0.2, 4.2, 10), Vector3(-5.1, 2.1, -1), wall, Vector3(0, 90, 0) * 0.0)
	_box(o, Vector3(0.2, 4.2, 10), Vector3(5.1, 2.1, -1), wall)
	var ceil_c := Color(0.5, 0.5, 0.48) if lv == 0 else Color(0.06, 0.065, 0.07)
	_box(o, Vector3(12, 0.2, 10), Vector3(0, 4.2, -1), _mat(ceil_c))
	_box(o, Vector3(12, 0.15, 0.05), Vector3(0, 0.075, -3.88), _mat(Color(0.12, 0.08, 0.05)))
	if lv == 0:
		# tavan karoları ve floresan
		for x in [-1.5, 1.5]:
			_box(o, Vector3(1.2, 0.04, 0.3), Vector3(x, 4.08, -1.6), _mat(Color(0.95, 0.97, 1.0), 0.3, 0.0, 3.0))
	# ---------------- pencere (gerçek şehir fotoğrafı)
	var ww: float = [1.6, 2.6, 3.4][lv]
	var wh: float = [1.2, 1.6, 2.4][lv]
	var wx: float = [2.6, 2.4, 2.6][lv]
	var wy: float = [2.3, 2.2, 2.0][lv]
	var win := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(ww, wh)
	win.mesh = q
	city_mat = _shader(PHOTO_WINDOW)
	city_mat.set_shader_parameter("city", load("res://assets/tex/city_night.jpg"))
	var span := clampf(ww / wh * 0.97 / 1.03, 0.3, 1.0)
	city_mat.set_shader_parameter("crop_x", Vector2(0.5 - span / 2.0, 0.5 + span / 2.0))
	win.material_override = city_mat
	win.position = Vector3(wx, wy, -3.88)
	o.add_child(win)
	var frame := _mat(Color(0.1, 0.1, 0.11), 0.4, 0.5)
	if lv == 0:
		frame = _mat(Color(0.75, 0.75, 0.72), 0.5, 0.1)
	var fx0: float = wx - ww / 2.0
	var fx1: float = wx + ww / 2.0
	_box(o, Vector3(ww + 0.2, 0.08, 0.1), Vector3(wx, wy + wh / 2.0 + 0.04, -3.86), frame)
	_box(o, Vector3(ww + 0.2, 0.12, 0.25), Vector3(wx, wy - wh / 2.0 - 0.05, -3.8), frame)
	_box(o, Vector3(0.08, wh + 0.1, 0.1), Vector3(fx0 - 0.04, wy, -3.86), frame)
	_box(o, Vector3(0.08, wh + 0.1, 0.1), Vector3(fx1 + 0.04, wy, -3.86), frame)
	var mull := 1 if lv < 2 else 2
	for i in mull:
		_box(o, Vector3(0.05, wh, 0.06), Vector3(fx0 + ww * (i + 1) / (mull + 1), wy, -3.86), frame)
	if lv == 1:
		# yarı açık jaluzi
		var slat := _mat(Color(0.82, 0.8, 0.74), 0.6)
		for i in 7:
			_box(o, Vector3(ww + 0.1, 0.02, 0.07), Vector3(wx, wy + wh / 2.0 - 0.06 - i * 0.07, -3.8), slat, Vector3(35, 0, 0))
		_box(o, Vector3(ww + 0.16, 0.06, 0.1), Vector3(wx, wy + wh / 2.0 + 0.02, -3.78), slat)
	var moon := OmniLight3D.new()
	moon.position = Vector3(wx, wy, -3.2)
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.5 + lv * 0.15
	moon.omni_range = 5.0
	o.add_child(moon)
	window_light = moon
	# ---------------- masa
	var desk_m: Material
	match lv:
		0:
			desk_m = _mat(Color(0.36, 0.37, 0.38), 0.4, 0.6)
		1:
			desk_m = _mat(Color(0.16, 0.09, 0.05), 0.35)
		_:
			desk_m = _mat(Color(0.09, 0.05, 0.03), 0.25)
	var dw: float = [2.0, 2.6, 3.0][lv]
	_box(o, Vector3(dw, 0.07, 1.2), Vector3(0, 0.78, -2.3), desk_m)
	for x in [-dw / 2.0 + 0.1, dw / 2.0 - 0.1]:
		_box(o, Vector3(0.07, 0.78, 1.1), Vector3(x, 0.39, -2.3), desk_m)
	_box(o, Vector3(dw - 0.2, 0.5, 0.04), Vector3(0, 0.5, -2.85), desk_m)
	if lv == 2:
		_box(o, Vector3(dw * 0.5, 0.012, 0.6), Vector3(0, 0.82, -2.3), _tex_mat("res://assets/tex/leather.jpg", Color(0.7, 0.6, 0.55), Vector2.ONE, 0.5))
	_ao(o, Vector3(0, 0.012, -2.35), Vector2(dw + 1.0, 1.9), 0.6)
	# laptop
	var metal := _mat(Color(0.55, 0.57, 0.6), 0.3, 0.8)
	_box(o, Vector3(0.62, 0.025, 0.42), Vector3(-0.15, 0.825, -2.5), metal)
	var screen := Node3D.new()
	screen.position = Vector3(-0.15, 0.84, -2.29)
	screen.rotation_degrees = Vector3(-14, 180, 0)
	o.add_child(screen)
	_box(screen, Vector3(0.62, 0.4, 0.018), Vector3(0, 0.2, 0), metal)
	laptop_mat = _shader(LAPTOP_SHADER)
	var sc := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.57, 0.35)
	sc.mesh = sq
	sc.material_override = laptop_mat
	sc.position = Vector3(0, 0.205, 0.011)
	screen.add_child(sc)
	var glow := OmniLight3D.new()
	glow.position = Vector3(-0.15, 1.05, -2.7)
	glow.light_color = Color(0.5, 0.9, 0.7)
	glow.light_energy = 0.35
	glow.omni_range = 1.4
	o.add_child(glow)
	# dosyalar, defter, kalem
	var manila := _tex_mat("res://assets/tex/manila.jpg", Color.WHITE, Vector2.ONE, 0.9)
	var paper := _tex_mat("res://assets/tex/paper.jpg", Color.WHITE, Vector2.ONE, 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + lv
	var stack_n: int = [5, 3, 2][lv]
	for i in stack_n:
		_box(o, Vector3(0.34, 0.012, 0.25), Vector3(0.62 + rng.randf_range(-0.03, 0.03), 0.82 + i * 0.013, -2.45), manila, Vector3(0, rng.randf_range(-14, 14), 0))
	_box(o, Vector3(0.32, 0.02, 0.23), Vector3(0.55, 0.825, -2.05), paper, Vector3(0, -12, 0))
	_box(o, Vector3(0.33, 0.012, 0.24), Vector3(0.55, 0.818, -2.05), _mat(Color(0.25, 0.1, 0.08)), Vector3(0, -12, 0))
	_cyl(o, 0.008, 0.008, 0.15, Vector3(0.62, 0.84, -2.0), _mat(Color(0.1, 0.2, 0.5), 0.3, 0.4), Vector3(0, 0, 90), 8)
	for i in [0, 1]:
		_box(o, Vector3(0.21, 0.004, 0.3), Vector3(-0.75 + i * 0.12, 0.818 + i * 0.002, -2.05), paper, Vector3(0, rng.randf_range(-25, 25), 0))
	# kupa (dumanı tüten)
	var mug := _mat(Color(0.92, 0.92, 0.9), 0.25)
	_cyl(o, 0.045, 0.04, 0.11, Vector3(0.95, 0.87, -2.35), mug)
	var handle := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.02
	tor.outer_radius = 0.035
	handle.mesh = tor
	handle.material_override = mug
	handle.position = Vector3(1.0, 0.87, -2.35)
	handle.rotation_degrees = Vector3(90, 0, 0)
	o.add_child(handle)
	_cyl(o, 0.04, 0.04, 0.005, Vector3(0.95, 0.92, -2.35), _mat(Color(0.18, 0.09, 0.04)))
	if Game.quality() != "low":
		var steam := CPUParticles3D.new()
		steam.amount = 10
		steam.lifetime = 2.2
		steam.position = Vector3(0.95, 0.93, -2.35)
		steam.direction = Vector3.UP
		steam.spread = 8.0
		steam.initial_velocity_min = 0.05
		steam.initial_velocity_max = 0.09
		steam.gravity = Vector3(0.01, 0.02, 0)
		steam.scale_amount_min = 0.5
		steam.scale_amount_max = 1.0
		var sqm := QuadMesh.new()
		sqm.size = Vector2(0.06, 0.06)
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		smat.vertex_color_use_as_albedo = true
		var gt := GradientTexture2D.new()
		var gg := Gradient.new()
		gg.set_color(0, Color(1, 1, 1, 0.25))
		gg.set_color(1, Color(1, 1, 1, 0.0))
		gt.gradient = gg
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		smat.albedo_texture = gt
		sqm.material = smat
		steam.mesh = sqm
		var cr := Gradient.new()
		cr.set_color(0, Color(1, 1, 1, 0.0))
		cr.add_point(0.2, Color(1, 1, 1, 0.5))
		cr.set_color(1, Color(1, 1, 1, 0.0))
		steam.color_ramp = cr
		o.add_child(steam)
	# masa lambası
	var lamp_m := _mat(Color(0.08, 0.08, 0.09), 0.35, 0.6)
	if lv == 2:
		lamp_m = _mat(Color(0.75, 0.6, 0.3), 0.25, 1.0)
	_cyl(o, 0.09, 0.1, 0.03, Vector3(-0.95, 0.83, -2.55), lamp_m)
	_box(o, Vector3(0.025, 0.5, 0.025), Vector3(-0.95, 1.07, -2.5), lamp_m, Vector3(15, 0, 0))
	_cyl(o, 0.03, 0.11, 0.14, Vector3(-0.85, 1.3, -2.38), lamp_m, Vector3(60, 0, -40))
	var spot := SpotLight3D.new()
	spot.position = Vector3(-0.82, 1.27, -2.36)
	spot.rotation_degrees = Vector3(-75, -20, 0)
	spot.light_color = Color(1.0, 0.82, 0.55)
	spot.light_energy = 3.0
	spot.spot_range = 3.0
	spot.spot_angle = 42.0
	spot.shadow_enabled = Game.quality() == "high"
	o.add_child(spot)
	_sphere(o, 0.03, Vector3(-0.83, 1.26, -2.37), _mat(Color(1.0, 0.85, 0.6), 0.2, 0.0, 6.0))
	# ---------------- tavan ışığı
	var ceil_l := OmniLight3D.new()
	ceil_l.position = Vector3(0, 3.8, -1.0)
	ceil_l.light_color = Color(0.95, 0.97, 1.0) if lv == 0 else Color(1.0, 0.9, 0.75)
	ceil_l.light_energy = [1.7, 1.7, 1.6][lv]
	ceil_l.omni_range = 10.0
	var fill_l := OmniLight3D.new()
	fill_l.position = Vector3(1.5, 2.2, 0.5)
	fill_l.light_color = Color(0.8, 0.85, 1.0)
	fill_l.light_energy = 0.7
	fill_l.omni_range = 7.0
	o.add_child(fill_l)
	o.add_child(ceil_l)
	if lv >= 1:
		# sarkıt lamba
		var pend := _mat(Color(0.1, 0.1, 0.1), 0.4, 0.7)
		_cyl(o, 0.006, 0.006, 0.9, Vector3(0.3, 3.65, -2.3), pend)
		_cyl(o, 0.06, 0.3, 0.22, Vector3(0.3, 3.1, -2.3), pend)
		_sphere(o, 0.06, Vector3(0.3, 3.0, -2.3), _mat(Color(1.0, 0.85, 0.6), 0.2, 0.0, 5.0))
	# ---------------- flama
	var pen := Node3D.new()
	pen.position = Vector3(-2.3, 3.0, -3.88)
	pen.scale = Vector3(0.6, 0.6, 0.6)
	o.add_child(pen)
	var tri := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.6, 0.25, 0), Vector3(0.6, 0.25, 0), Vector3(0, -0.75, 0)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	tri.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	pennant_mat = _mat(Color("#e8c547"), 0.8)
	pennant_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pmi := MeshInstance3D.new()
	pmi.mesh = tri
	pmi.material_override = pennant_mat
	pen.add_child(pmi)
	var stripe := ArrayMesh.new()
	var arr2 := []
	arr2.resize(Mesh.ARRAY_MAX)
	arr2[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.6, 0.25, 0.005), Vector3(0.6, 0.25, 0.005), Vector3(0.45, 0.0, 0.005), Vector3(-0.6, 0.25, 0.005), Vector3(0.45, 0.0, 0.005), Vector3(-0.45, 0.0, 0.005)])
	arr2[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	stripe.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
	pennant_mat2 = _mat(Color("#123524"), 0.8)
	pennant_mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
	var smi := MeshInstance3D.new()
	smi.mesh = stripe
	smi.material_override = pennant_mat2
	pen.add_child(smi)
	_box(o, Vector3(0.8, 0.02, 0.02), Vector3(-2.3, 3.16, -3.86), _mat(Color(0.4, 0.3, 0.15), 0.4, 0.5))
	# ---------------- raf ve kupalar
	var shelf_w: float = [1.0, 1.6, 2.2][lv]
	_box(o, Vector3(shelf_w, 0.05, 0.3), Vector3(-2.6, 1.9, -3.75), desk_m)
	if lv == 2:
		# camlı kupa dolabı
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.7, 0.85, 1.0, 0.12)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.05
		_box(o, Vector3(shelf_w + 0.1, 1.0, 0.04), Vector3(-2.6, 2.4, -3.58), glass)
		_box(o, Vector3(shelf_w, 0.05, 0.3), Vector3(-2.6, 2.9, -3.75), desk_m)
		var cab_l := OmniLight3D.new()
		cab_l.position = Vector3(-2.6, 2.8, -3.6)
		cab_l.light_color = Color(1.0, 0.9, 0.7)
		cab_l.light_energy = 0.6
		cab_l.omni_range = 1.4
		o.add_child(cab_l)
	trophy_root = Node3D.new()
	trophy_root.position = Vector3(-2.6, 1.925, -3.75)
	o.add_child(trophy_root)
	# ---------------- dolaplar, kitaplık, bitki
	_bookcase(o, Vector3(-4.15, 0, -3.72), lv, rng)
	_cabinet(o, Vector3(-1.45, 0, -3.62), lv)
	if lv >= 1:
		_plant(o, Vector3(4.35, 0, -3.35), 1.0 + lv * 0.2)
	if lv == 0:
		# karton kutular
		var card := _mat(Color(0.55, 0.4, 0.25), 0.95)
		_box(o, Vector3(0.6, 0.45, 0.45), Vector3(3.6, 0.225, -3.5), card, Vector3(0, 8, 0))
		_box(o, Vector3(0.5, 0.35, 0.4), Vector3(3.62, 0.62, -3.48), card, Vector3(0, -6, 0))
		_ao(o, Vector3(3.6, 0.012, -3.5), Vector2(1.2, 1.0), 0.5)
	if lv == 2:
		_sofa(o, Vector3(3.6, 0, 0.2))
		_framed_shirt(o, Vector3(5.0, 2.3, -1.6))
	# ---------------- duvar saati (gerçek saat)
	var ck := Node3D.new()
	ck.position = Vector3(0.0, 3.25, -3.87)
	o.add_child(ck)
	_cyl(ck, 0.24, 0.24, 0.04, Vector3.ZERO, _mat(Color(0.1, 0.1, 0.1), 0.4, 0.6), Vector3(90, 0, 0), 28)
	_cyl(ck, 0.21, 0.21, 0.045, Vector3(0, 0, 0.003), _mat(Color(0.93, 0.91, 0.85), 0.8), Vector3(90, 0, 0), 28)
	for i in 12:
		var a := i * TAU / 12.0
		_box(ck, Vector3(0.012, 0.035 if i % 3 else 0.05, 0.005), Vector3(sin(a) * 0.17, cos(a) * 0.17, 0.028), _mat(Color(0.1, 0.1, 0.1)), Vector3(0, 0, -rad_to_deg(a)))
	clock_h = Node3D.new()
	clock_h.position = Vector3(0, 0, 0.032)
	ck.add_child(clock_h)
	_box(clock_h, Vector3(0.016, 0.1, 0.005), Vector3(0, 0.045, 0), _mat(Color(0.08, 0.08, 0.08)))
	clock_m = Node3D.new()
	clock_m.position = Vector3(0, 0, 0.036)
	ck.add_child(clock_m)
	_box(clock_m, Vector3(0.01, 0.15, 0.005), Vector3(0, 0.07, 0), _mat(Color(0.08, 0.08, 0.08)))
	_update_clock()
	_update_sky()
	# ---------------- çerçeveler (sertifika, eski fotoğraf)
	var fr_m := _mat(Color(0.15, 0.1, 0.06), 0.5) if lv < 2 else _mat(Color(0.7, 0.55, 0.25), 0.3, 0.9)
	for i in [0, 1] if lv > 0 else [0]:
		var fp := Vector3(-3.6 + i * 0.6, 2.75 + (0.1 if i else 0.0), -3.88)
		_box(o, Vector3(0.42, 0.32, 0.03), fp, fr_m)
		_box(o, Vector3(0.36, 0.26, 0.032), fp + Vector3(0, 0, 0.002), paper)
	# ---------------- dedektif panosu (sol duvar) — gerçek mantar dokusu
	var cork := _tex_mat("res://assets/tex/cork.jpg", Color(0.95, 0.9, 0.85), Vector2(2.0, 1.0), 1.0)
	var bw: float = [2.6, 3.2, 3.6][lv]
	_box(o, Vector3(0.06, 1.7, bw), Vector3(-4.97, 1.75, -1.2), cork)
	_box(o, Vector3(0.08, 1.8, 0.08), Vector3(-4.95, 1.75, -1.2 + bw / 2.0 + 0.02), frame)
	_box(o, Vector3(0.08, 1.8, 0.08), Vector3(-4.95, 1.75, -1.2 - bw / 2.0 - 0.02), frame)
	_box(o, Vector3(0.08, 0.08, bw + 0.1), Vector3(-4.95, 2.62, -1.2), frame)
	_box(o, Vector3(0.08, 0.08, bw + 0.1), Vector3(-4.95, 0.88, -1.2), frame)
	board_root = Node3D.new()
	board_root.position = Vector3(-4.92, 1.75, -1.2)
	board_root.rotation_degrees.y = 90
	o.add_child(board_root)
	var bl := SpotLight3D.new()
	bl.position = Vector3(-3.6, 3.6, -1.2)
	bl.rotation_degrees = Vector3(-55, 90, 0)
	bl.light_color = Color(1.0, 0.92, 0.8)
	bl.light_energy = 2.2
	bl.spot_range = 5.0
	bl.spot_angle = 45
	o.add_child(bl)
	# ---------------- halı
	var rug_c: Color = [Color(0.2, 0.2, 0.22), Color(0.12, 0.05, 0.05), Color(0.08, 0.1, 0.14)][lv]
	_box(o, Vector3(3.2 + lv * 0.6, 0.01, 2.2 + lv * 0.4), Vector3(0, 0.005, -1.2), _mat(rug_c, 1.0))
	# köşe ve duvar dibi gölgeleri
	_ao(o, Vector3(0, 0.011, -3.75), Vector2(11.5, 0.8), 0.45)
	_ao(o, Vector3(-4.85, 0.011, -1.0), Vector2(0.8, 9.0), 0.4)
	_ao(o, Vector3(4.85, 0.011, -1.0), Vector2(0.8, 9.0), 0.4)
	_office_life(o, desk_m, frame)

func _update_clock() -> void:
	if clock_h == null:
		return
	var t := Time.get_time_dict_from_system()
	var h := float(t.hour % 12) + float(t.minute) / 60.0
	clock_h.rotation.z = -h / 12.0 * TAU
	clock_m.rotation.z = -float(t.minute) / 60.0 * TAU

func _bookcase(o: Node3D, pos: Vector3, lv: int, rng: RandomNumberGenerator) -> void:
	var wood := _mat(Color(0.14, 0.08, 0.045), 0.6) if lv > 0 else _mat(Color(0.4, 0.41, 0.42), 0.5, 0.5)
	var w := 1.0
	var h: float = [1.8, 2.2, 2.6][lv]
	var n := Node3D.new()
	n.position = pos
	o.add_child(n)
	_box(n, Vector3(w, h, 0.04), Vector3(0, h / 2.0, -0.17), wood)
	for sx in [-1.0, 1.0]:
		_box(n, Vector3(0.04, h, 0.36), Vector3(sx * w / 2.0, h / 2.0, 0), wood)
	var shelves := int(h / 0.42)
	var cols := [Color("#8a2a22"), Color("#24426a"), Color("#2f5a3a"), Color("#c9a24a"), Color("#3a3a3a"), Color("#d8d2c2"), Color("#5a3a6a")]
	for si in shelves + 1:
		var y := 0.05 + si * (h - 0.1) / shelves
		_box(n, Vector3(w, 0.03, 0.34), Vector3(0, y, 0), wood)
		if si == shelves:
			break
		var x := -w / 2.0 + 0.05
		while x < w / 2.0 - 0.1:
			var bwid := rng.randf_range(0.04, 0.09)
			var bh := rng.randf_range(0.22, 0.34)
			if rng.randf() < 0.12:
				x += 0.08
				continue
			_box(n, Vector3(bwid, bh, 0.24), Vector3(x + bwid / 2.0, y + 0.015 + bh / 2.0, 0.02), _mat(cols[rng.randi() % cols.size()] * rng.randf_range(0.7, 1.1), 0.8))
			x += bwid + 0.004
	_ao(o, pos + Vector3(0, 0.011, 0.1), Vector2(1.4, 0.9), 0.5)

func _cabinet(o: Node3D, pos: Vector3, lv: int) -> void:
	var m := _mat(Color(0.32, 0.34, 0.33), 0.45, 0.6) if lv < 2 else _mat(Color(0.12, 0.07, 0.04), 0.4)
	_box(o, Vector3(1.5, 0.7, 0.45), pos + Vector3(0, 0.35, 0), m)
	for i in 3:
		_box(o, Vector3(0.005, 0.62, 0.01), pos + Vector3(-0.75 + 0.375 * (i + 1), 0.35, 0.226), _mat(Color(0.08, 0.08, 0.08)))
	for i in 4:
		_box(o, Vector3(0.025, 0.12, 0.03), pos + Vector3(-0.6 + i * 0.4, 0.45, 0.235), _mat(Color(0.7, 0.7, 0.72), 0.3, 0.9))
	# üstünde dosya kutuları
	var bc := [Color("#24426a"), Color("#8a2a22"), Color("#c9a24a")]
	for i in 3:
		_box(o, Vector3(0.09, 0.3, 0.26), pos + Vector3(0.35 + i * 0.1, 0.85, 0), _mat(bc[i], 0.8))
	_ao(o, pos + Vector3(0, 0.011, 0.1), Vector2(2.0, 0.9), 0.5)

func _plant(o: Node3D, pos: Vector3, s: float) -> void:
	var pot := _mat(Color(0.55, 0.3, 0.18), 0.8)
	_cyl(o, 0.2 * s, 0.15 * s, 0.38 * s, pos + Vector3(0, 0.19 * s, 0), pot, Vector3.ZERO, 12)
	var leaf := _mat(Color(0.12, 0.3, 0.12), 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 9:
		var a := i * TAU / 9.0
		var lm := _sphere(o, 0.14 * s, pos + Vector3(cos(a) * 0.16 * s, (0.6 + rng.randf() * 0.5) * s, sin(a) * 0.16 * s), _mat(Color(0.1, 0.26 + rng.randf() * 0.1, 0.1), 0.7))
		lm.scale = Vector3(1.0, 1.9, 0.45)
		lm.rotation = Vector3(rng.randf_range(-0.5, 0.5), a, rng.randf_range(-0.4, 0.4))
	_ao(o, pos + Vector3(0, 0.011, 0), Vector2(0.8, 0.8), 0.5)

func _sofa(o: Node3D, pos: Vector3) -> void:
	var lth := _tex_mat("res://assets/tex/leather.jpg", Color(0.55, 0.32, 0.2), Vector2(2, 1), 0.45)
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = -90
	o.add_child(n)
	_box(n, Vector3(2.0, 0.42, 0.85), Vector3(0, 0.21, 0), lth)
	_box(n, Vector3(2.0, 0.55, 0.22), Vector3(0, 0.62, -0.32), lth)
	for sx in [-1.0, 1.0]:
		_box(n, Vector3(0.22, 0.58, 0.85), Vector3(sx * 0.95, 0.35, 0), lth)
	_ao(o, pos + Vector3(0, 0.011, 0), Vector2(1.3, 2.4), 0.55)

func _framed_shirt(o: Node3D, pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = -90
	o.add_child(n)
	_box(n, Vector3(0.9, 1.0, 0.04), Vector3.ZERO, _mat(Color(0.05, 0.05, 0.05), 0.4))
	_box(n, Vector3(0.82, 0.92, 0.042), Vector3(0, 0, 0.002), _mat(Color(0.85, 0.83, 0.78), 0.9))
	shirt_mat = _mat(_club_c1, 0.8)
	_box(n, Vector3(0.36, 0.5, 0.05), Vector3(0, -0.04, 0.004), shirt_mat)
	_box(n, Vector3(0.6, 0.14, 0.05), Vector3(0, 0.16, 0.004), shirt_mat)

var shirt_mat: StandardMaterial3D
var window_light: OmniLight3D

## Masada çalışan scout, duvarda TV, masada telefon; pencerede gerçek saate göre gün ışığı
func _office_life(o: Node3D, desk_m: Material, frame: Material) -> void:
	# sandalye (masanın arkasında, kameraya bakar)
	var ch := _mat(Color(0.08, 0.08, 0.09), 0.5)
	_box(o, Vector3(0.5, 0.06, 0.5), Vector3(0.0, 0.46, -3.2), ch)
	_box(o, Vector3(0.5, 0.7, 0.06), Vector3(0.0, 0.85, -3.47), ch)
	_cyl(o, 0.03, 0.03, 0.42, Vector3(0.0, 0.22, -3.2), ch)
	me_man = MM.new()
	o.add_child(me_man)
	me_man.build_outfit(Color("#2a3550"), Color("#3a3d44"), Color("#2a1a10"), 1, 0, 4, true)
	me_man.position = Vector3(0.0, 0.0, -3.2 + 0.33)
	me_man.rotation.y = 0.0
	me_man.set_base("sit")
	me_man.overlay = "type"
	# telefon
	phone_node = Node3D.new()
	phone_node.position = Vector3(0.35, 0.82, -2.0)
	o.add_child(phone_node)
	_box(phone_node, Vector3(0.075, 0.01, 0.15), Vector3.ZERO, _mat(Color(0.05, 0.05, 0.06), 0.25, 0.3))
	_box(phone_node, Vector3(0.068, 0.002, 0.14), Vector3(0, 0.006, 0), _mat(Color(0.1, 0.2, 0.3), 0.2, 0.0, 0.6))
	# TV (arka duvar, solda)
	var tv := Node3D.new()
	tv.position = Vector3(-1.45, 2.45, -3.86)
	o.add_child(tv)
	_box(tv, Vector3(1.3, 0.76, 0.05), Vector3.ZERO, _mat(Color(0.03, 0.03, 0.035), 0.3, 0.5))
	_box(tv, Vector3(1.22, 0.68, 0.01), Vector3(0, 0, 0.026), _mat(Color(0.03, 0.06, 0.09), 0.2, 0.0, 0.5))
	var hdr := _label(tv, "CANLI • SKORLAR", Vector3(-0.58, 0.27, 0.035), 0.0011, Color("#e8c547"))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hdr.font_size = 48
	for i in 3:
		var l := _label(tv, "", Vector3(-0.58, 0.12 - i * 0.13, 0.035), 0.0011, Color(0.92, 0.95, 0.97))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.font_size = 52
		tv_lines.append(l)
	_box(tv, Vector3(1.22, 0.1, 0.012), Vector3(0, -0.29, 0.03), _mat(Color(0.7, 0.1, 0.1), 0.4, 0.0, 0.4))
	tv_ticker = _label(tv, "", Vector3(-0.58, -0.29, 0.04), 0.0009, Color.WHITE)
	tv_ticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tv_ticker.font_size = 44
	var tvl := OmniLight3D.new()
	tvl.position = Vector3(-1.45, 2.4, -3.4)
	tvl.light_color = Color(0.5, 0.7, 1.0)
	tvl.light_energy = 0.25
	tvl.omni_range = 2.0
	o.add_child(tvl)
	_update_sky()
	_update_tv()

func _update_sky() -> void:
	if city_mat == null:
		return
	var h := float(Time.get_datetime_dict_from_system().hour) + float(Time.get_datetime_dict_from_system().minute) / 60.0
	var day := clampf(smoothstep(6.0, 8.5, h) - smoothstep(17.5, 19.5, h), 0.0, 1.0)
	var dusk := maxf(exp(-pow((h - 18.6) / 1.1, 2.0)), exp(-pow((h - 6.8) / 0.9, 2.0))) * 0.8
	var rain := 0.0
	if not Game.s.is_empty():
		var hs := hash(int(Game.s.get("season", 0)) * 53 + int(Game.s.get("week", 0)))
		rain = 1.0 if hs % 4 == 0 else 0.0
	city_mat.set_shader_parameter("day", day)
	city_mat.set_shader_parameter("dusk", dusk)
	city_mat.set_shader_parameter("rain", rain)
	if window_light:
		window_light.light_energy = 0.5 + day * 1.6 + dusk * 0.5
		window_light.light_color = Color(0.55, 0.65, 1.0).lerp(Color(1.0, 0.97, 0.92), day).lerp(Color(1.0, 0.7, 0.45), dusk * 0.6)
		window_light.omni_range = 5.0 + day * 2.0

func _update_tv() -> void:
	if tv_lines.is_empty() or Game.s.is_empty() or Game.s.scout.club_id == "":
		return
	var lg: String = Game.my_club().league
	var rows := []
	var rd := Game.round_for_week(lg, Game.s.week - 1)
	if Game.s.fixtures.has(lg) and rd >= 0:
		for m in Game.s.fixtures[lg][rd]:
			if int(m.gh) >= 0:
				rows.append("%s  %d - %d  %s" % [Game.club(m.h).short, int(m.gh), int(m.ga), Game.club(m.a).short])
	if rows.is_empty():
		rows = ["—"]
	for i in tv_lines.size():
		(tv_lines[i] as Label3D).text = rows[(tv_i * 3 + i) % rows.size()] if i < rows.size() else ""
	if not Game.s.news.is_empty():
		var n: Dictionary = Game.s.news[tv_i % mini(5, Game.s.news.size())]
		var txt := T.t(n.key, n.get("args", []))
		tv_ticker.text = txt.substr(0, 46) + ("…" if txt.length() > 46 else "")

## Yeni önemli haber: telefon titrer, scout açar
func notify_news() -> void:
	if Game.s.is_empty():
		return
	var n: int = Game.s.news.size()
	if news_seen >= 0 and n > news_seen:
		ring_t = 0.0
		Sfx.play("ring", -12.0)
	news_seen = n

func set_club(c1: Color, c2: Color) -> void:
	_club_c1 = c1
	_club_c2 = c2
	pennant_mat.albedo_color = c1
	pennant_mat2.albedo_color = c2
	if shirt_mat and office_level == 2:
		shirt_mat.albedo_color = c1

func set_trophies(n: int) -> void:
	_trophy_n = n
	for c in trophy_root.get_children():
		c.queue_free()
	var gold := _mat(Color(0.95, 0.75, 0.25), 0.25, 1.0)
	for i in mini(n, 7):
		var t := Node3D.new()
		t.position = Vector3(-0.65 + i * 0.21, 0, 0)
		trophy_root.add_child(t)
		_cyl(t, 0.03, 0.04, 0.03, Vector3(0, 0.015, 0), _mat(Color(0.1, 0.1, 0.1)))
		_cyl(t, 0.008, 0.008, 0.06, Vector3(0, 0.06, 0), gold)
		_cyl(t, 0.05, 0.02, 0.07, Vector3(0, 0.125, 0), gold)

func set_board(cards: Array) -> void:
	## cards: [{name, c1, c2, stars}] — panoya iğnelenmiş oyuncu kartları ve ipler
	for c in board_root.get_children():
		c.queue_free()
	var pin := _mat(Color(0.85, 0.1, 0.1), 0.3, 0.2)
	var string_m := _mat(Color(0.75, 0.08, 0.08), 0.8)
	var paper := _tex_mat("res://assets/tex/paper.jpg", Color(1, 1, 1), Vector2.ONE, 0.9)
	var pts := []
	var n := mini(cards.size(), 9)
	for i in n:
		var cd: Dictionary = cards[i]
		var col := i % 3
		var row := i / 3
		var p := Vector3(-1.05 + col * 1.05 + (0.08 if row % 2 else -0.04), 0.5 - row * 0.52, 0.04)
		var card := Node3D.new()
		card.position = p
		card.rotation_degrees.z = randf_range(-6, 6)
		board_root.add_child(card)
		_box(card, Vector3(0.62, 0.42, 0.01), Vector3.ZERO, paper)
		_box(card, Vector3(0.62, 0.1, 0.012), Vector3(0, 0.16, 0.001), _mat(Color(cd.c1), 0.8))
		_box(card, Vector3(0.12, 0.1, 0.013), Vector3(0.25, 0.16, 0.002), _mat(Color(cd.c2), 0.8))
		var ph_m := _mat(Color(0.3, 0.3, 0.32), 0.9)
		var phq := MeshInstance3D.new()
		var pq := QuadMesh.new()
		pq.size = Vector2(0.17, 0.2)
		phq.mesh = pq
		phq.material_override = ph_m
		phq.position = Vector3(-0.2, -0.04, 0.0075)
		card.add_child(phq)
		if cd.has("p"):
			Portrait.request(cd.p, func(t):
				ph_m.albedo_texture = t
				ph_m.albedo_color = Color.WHITE)
		var l := _label(card, cd.name, Vector3(0.07, -0.0, 0.01), 0.0016, Color(0.1, 0.1, 0.12))
		l.outline_size = 0
		l.width = 300
		var s := _label(card, cd.stars, Vector3(0.07, -0.12, 0.01), 0.0015, Color(0.7, 0.45, 0.05))
		s.outline_size = 0
		_sphere(card, 0.025, Vector3(0, 0.19, 0.03), pin)
		pts.append(card.position + Vector3(0, 0.19, 0.03))
	# ipler
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i] if i % 2 == 1 else pts[maxi(0, i - 2)]
		var mid := (a + b) / 2.0
		var len := a.distance_to(b)
		if len < 0.01:
			continue
		var s := _box(board_root, Vector3(len, 0.008, 0.008), mid, string_m)
		s.rotation.z = atan2(b.y - a.y, b.x - a.x)
	if n == 0:
		var l := _label(board_root, "?", Vector3(0, 0, 0.05), 0.012, Color(0.25, 0.15, 0.08))
		l.outline_size = 0

# ================================================================ harita masası

func _build_map() -> void:
	map_root = Node3D.new()
	map_root.position = MAP
	world.add_child(map_root)
	var dark := _mat(Color(0.05, 0.06, 0.07), 0.4, 0.3)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(16, 14)
	floor.mesh = pm
	floor.material_override = _mat(Color(0.03, 0.035, 0.04), 0.25, 0.5)
	map_root.add_child(floor)
	_box(map_root, Vector3(7.4, 0.12, 4.0), Vector3(0, 0.78, 0), _mat(Color(0.08, 0.09, 0.1), 0.3, 0.6))
	_box(map_root, Vector3(7.2, 0.78, 3.8), Vector3(0, 0.39, 0), dark)
	var rim := _mat(Color(0.91, 0.77, 0.28), 0.3, 0.0, 2.5)
	_box(map_root, Vector3(7.42, 0.02, 0.03), Vector3(0, 0.85, 2.0), rim)
	_box(map_root, Vector3(7.42, 0.02, 0.03), Vector3(0, 0.85, -2.0), rim)
	# holo ızgara
	var holo := MeshInstance3D.new()
	var hq := PlaneMesh.new()
	hq.size = Vector2(7.2, 3.8)
	holo.mesh = hq
	holo.material_override = _shader(HOLO_SHADER)
	holo.position = Vector3(0, 0.845, 0)
	map_root.add_child(holo)
	map_land = Node3D.new()
	map_root.add_child(map_land)
	_build_land("TR")
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 5.5, 1.5)
	spot.rotation_degrees = Vector3(-75, 0, 0)
	spot.light_energy = 4.0
	spot.spot_range = 9
	spot.spot_angle = 50
	spot.light_color = Color(0.9, 0.95, 1.0)
	spot.shadow_enabled = Game.quality() == "high"
	map_root.add_child(spot)
	var amb := OmniLight3D.new()
	amb.position = Vector3(0, 2.5, 3.5)
	amb.light_energy = 0.6
	amb.omni_range = 8
	map_root.add_child(amb)
	map_dyn = Node3D.new()
	map_root.add_child(map_dyn)

var map_land: Node3D
var map_cc := ""
var view_c := Vector2(35.3, 38.95)
var view_s := 0.438
var view_k := 0.777
const BOARD := Rect2(-3.55, -1.85, 7.1, 3.7)

func _geo(lon: float, lat: float) -> Vector2:
	return Vector2((lon - view_c.x) * view_k * view_s, -(lat - view_c.y) * view_s)

func _build_land(cc: String) -> void:
	## Seçili ülkeyi merkeze alan Avrupa haritası (kara + iç denizler), tahtaya kırpılmış
	map_cc = cc
	for ch in map_land.get_children():
		ch.queue_free()
	var vr := Europe.view_for(cc)
	view_c = vr.get_center()
	view_k = cos(deg_to_rad(view_c.y))
	view_s = minf(6.6 / (vr.size.x * view_k), 3.4 / vr.size.y)
	var rect := PackedVector2Array([BOARD.position, Vector2(BOARD.end.x, BOARD.position.y), BOARD.end, Vector2(BOARD.position.x, BOARD.end.y)])
	var land_polys := []
	for poly in Europe.LAND:
		var pp := PackedVector2Array()
		for q in poly:
			pp.append(_geo(q[0], q[1]))
		for part in Geometry2D.intersect_polygons(pp, rect):
			land_polys.append(part)
	var water_polys := []
	for poly in Europe.WATER:
		var pp := PackedVector2Array()
		for q in poly:
			pp.append(_geo(q[0], q[1]))
		for part in Geometry2D.intersect_polygons(pp, rect):
			water_polys.append(part)
	var top_y := 0.97
	var bot_y := 0.85
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for poly in land_polys:
		var tris := Geometry2D.triangulate_polygon(poly)
		var cw := Geometry2D.is_polygon_clockwise(poly)
		for i in range(0, tris.size(), 3):
			for k in ([0, 2, 1] if not cw else [0, 1, 2]):
				var v: Vector2 = poly[tris[i + k]]
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(v.x, top_y, v.y))
		for i in poly.size():
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % poly.size()]
			var n := Vector3(b.y - a.y, 0, -(b.x - a.x)).normalized()
			for v in [Vector3(a.x, top_y, a.y), Vector3(b.x, top_y, b.y), Vector3(b.x, bot_y, b.y), Vector3(a.x, top_y, a.y), Vector3(b.x, bot_y, b.y), Vector3(a.x, bot_y, a.y)]:
				st.set_normal(n)
				st.add_vertex(v)
	var land := MeshInstance3D.new()
	land.mesh = st.commit()
	var lm := _mat(Color(0.18, 0.42, 0.26), 0.55, 0.1, 0.25)
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	land.material_override = lm
	map_land.add_child(land)
	if not water_polys.is_empty():
		var sw := SurfaceTool.new()
		sw.begin(Mesh.PRIMITIVE_TRIANGLES)
		for poly in water_polys:
			var tris := Geometry2D.triangulate_polygon(poly)
			for i in range(0, tris.size(), 3):
				for k in [0, 2, 1]:
					var v: Vector2 = poly[tris[i + k]]
					sw.set_normal(Vector3.UP)
					sw.add_vertex(Vector3(v.x, top_y + 0.004, v.y))
		var wm := MeshInstance3D.new()
		wm.mesh = sw.commit()
		var wmat := _mat(Color(0.06, 0.08, 0.1), 0.3, 0.4)
		wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		wm.material_override = wmat
		map_land.add_child(wm)

func _map_cities(cc: String) -> Array:
	## Haritada gösterilecek şehirler: ülkenin şehirleri + tahtaya düşen komşular
	var out := []
	if cc == "TR":
		return Data.CITY_POS.keys()
	for city in Data.CITY_W:
		var c: Array = Data.CITY_W[city]
		if str(c[2]) == cc and BOARD.grow(-0.05).has_point(_geo(float(c[1]), float(c[0]))):
			out.append(city)
	return out

func set_map(home: String, match_cities: Array, planned: Array, labels: Dictionary) -> void:
	for c in map_dyn.get_children():
		c.queue_free()
	var pole := _mat(Color(0.8, 0.82, 0.85), 0.3, 0.8)
	var hcc := Data.city_country(home)
	if hcc != map_cc:
		_build_land(hcc)
	for city in _map_cities(hcc) + match_cities.filter(func(x): return Data.city_country(x) != hcc and BOARD.has_point(_geo(Data.city_pos(x)[1], Data.city_pos(x)[0]))):
		var p = Data.city_pos(city)
		var g := _geo(p[1], p[0])
		var other: bool = Data.city_country(city) != hcc
		var is_home: bool = city == home
		var is_match: bool = city in match_cities
		var is_plan: bool = city in planned
		var col := Color(0.55, 0.62, 0.58, 1) if not other else Color(0.35, 0.4, 0.38, 1)
		var h := 0.05
		var r := 0.028
		var emis := 0.0
		if is_home:
			col = Color("#e8c547")
			h = 0.42
			r = 0.07
			emis = 3.0
		elif is_plan:
			col = Color("#e8c547")
			h = 0.32
			r = 0.06
			emis = 2.5
		elif is_match:
			col = Color("#6fb3e8")
			h = 0.2
			r = 0.05
			emis = 2.0
		_cyl(map_dyn, 0.008, 0.008, h, Vector3(g.x, 0.97 + h / 2.0, g.y), pole, Vector3.ZERO, 6)
		var head := _sphere(map_dyn, r, Vector3(g.x, 0.97 + h, g.y), _mat(col, 0.3, 0.0, emis) if emis > 0 else _mat(col, 0.5))
		if is_home or is_plan:
			var tw := head.create_tween().set_loops()
			tw.tween_property(head, "scale", Vector3.ONE * 1.35, 0.6)
			tw.tween_property(head, "scale", Vector3.ONE, 0.6)
		if labels.has(city):
			var l := _label(map_dyn, labels[city], Vector3(g.x, 0.97 + h + 0.18, g.y), 0.0032, col, true)
	# rotalar: evden planlanan şehirlere ark
	var hp = Data.city_pos(home)
	var hg := _geo(hp[1], hp[0])
	var dot := _mat(Color("#e8c547"), 0.3, 0.0, 4.0)
	for city in planned:
		var cp = Data.city_pos(city)
		var cg := _geo(cp[1], cp[0])
		var a := Vector3(hg.x, 1.38, hg.y)
		var b := Vector3(cg.x, 1.28, cg.y)
		var mid := (a + b) / 2.0 + Vector3(0, a.distance_to(b) * 0.35 + 0.2, 0)
		var n := 18
		for i in n:
			var s := _sphere(map_dyn, 0.022, Vector3.ZERO, dot)
			var holder := {"i": i}
			var tw := s.create_tween().set_loops()
			tw.tween_method(func(t):
				var f := fmod(float(holder.i) / n + t, 1.0)
				s.position = a.lerp(mid, f).lerp(mid.lerp(b, f), f), 0.0, 1.0, 2.5)

# ================================================================ kürsü

func _build_pedestal() -> void:
	ped_root = Node3D.new()
	ped_root.position = PED
	world.add_child(ped_root)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor.mesh = pm
	floor.material_override = _mat(Color(0.02, 0.025, 0.03), 0.15, 0.6)
	ped_root.add_child(floor)
	var back := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 7.0
	cm.bottom_radius = 7.0
	cm.height = 8.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 48
	back.mesh = cm
	var bm := _mat(Color(0.03, 0.05, 0.04), 0.9)
	bm.cull_mode = BaseMaterial3D.CULL_FRONT
	back.material_override = bm
	back.position = Vector3(0, 4, 0)
	ped_root.add_child(back)
	_cyl(ped_root, 1.0, 1.1, 0.35, Vector3(0, 0.175, 0), _mat(Color(0.08, 0.09, 0.1), 0.25, 0.7), Vector3.ZERO, 48)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.04
	tm.outer_radius = 1.1
	tm.rings = 48
	ring.mesh = tm
	ring.material_override = _mat(Color("#e8c547"), 0.3, 0.0, 4.0)
	ring.position.y = 0.35
	ring.scale = Vector3(1, 0.3, 1)
	ped_root.add_child(ring)
	var key := SpotLight3D.new()
	key.position = Vector3(1.5, 5.0, 3.0)
	key.look_at_from_position(key.position, Vector3(0, 1.0, 0), Vector3.UP)
	key.position += PED * 0.0
	key.light_energy = 6.0
	key.spot_range = 9
	key.spot_angle = 30
	key.shadow_enabled = Game.quality() == "high"
	ped_root.add_child(key)
	key.look_at(PED + Vector3(0, 1.0, 0))
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 2.5, -2.0)
	rim.light_color = Color(0.9, 0.75, 0.3)
	rim.light_energy = 2.0
	rim.omni_range = 5.0
	ped_root.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 1.5, 3.0)
	fill.light_energy = 0.6
	fill.omni_range = 6
	ped_root.add_child(fill)

func set_pedestal(p: Dictionary, club: Dictionary) -> void:
	if ped_player:
		ped_player.queue_free()
	var c1 := Color(club.get("c1", "#cccccc"))
	var c2 := Color(club.get("c2", "#333333"))
	var kit := FB.kit_mats(c1, c2, c1.darkened(0.15))
	if p.get("pos", "") == "GK":
		kit = FB.kit_mats(Color("#2ec4b6"), Color("#111111"), Color("#1f8a80"))
	ped_player = FB.new()
	ped_root.add_child(ped_player)
	ped_player.apply_look(p)
	ped_player.build(kit, int(p.get("skin", 1)), int(p.get("hair", 0)), int(p.get("seed", 0)), (int(p.get("seed", 0)) % 30) + 1, font)
	ped_player.position = Vector3(0, 0.35, 0)
	# mevkiye göre duruş: hücumcu top sektirir, savunmacı/kaleci kollarını kavuşturur
	var pos: String = p.get("pos", "CM")
	if ped_ball == null:
		ped_ball = _sphere(ped_root, 0.11, Vector3(0, 0.5, 0), _mat(Color(0.96, 0.96, 0.96), 0.4))
	ped_ball.visible = pos in ["ST", "LW", "RW", "AM"]
	if ped_ball.visible:
		ped_player.set_base("juggle")
	elif pos in ["CB", "GK", "DM"]:
		ped_player.set_base("idle")
		ped_player.overlay = "arms_crossed"
	else:
		ped_player.set_base("talk")
	ped_player.rotation.y = 0.5
	ped_turn = 0.0

# ================================================================ stadyum

func _ensure_stadium() -> void:
	if stadium_built:
		return
	stadium_built = true
	stadium_node = Node3D.new()
	stadium_node.position = STAD
	world.add_child(stadium_node)
	var st = Stadium.new()
	st.fx_enabled = false
	stadium_node.add_child(st)
	st.build(Color("#e8c547"), Color("#123524"), Color("#b5121b"), true, false, false)
	st.set_excite(0.25)
	var kit := FB.kit_mats(Color("#e8c547"), Color("#123524"), Color("#e8c547"))
	var kit2 := FB.kit_mats(Color("#f2f2f2"), Color("#b5121b"), Color("#f2f2f2"))
	# menü arka planı: koşan oyuncu yok (ekran kartını ve pili yormasın)
	for i in 0:
		var f = FB.new()
		stadium_node.add_child(f)
		f.lod = true
		f.build(kit if i < 6 else kit2, i % 5, i % 6, i, i + 2, font)
		f.position = Vector3(randf_range(-30, 30), 0, randf_range(-20, 20))
		stadium_men.append({"n": f, "t": Vector3(randf_range(-40, 40), 0, randf_range(-26, 26))})

# ================================================================ kamera

func goto(name: String, instant := false) -> void:
	if name == "stadium" or name == "stadium_orbit":
		_ensure_stadium()
	orbit = name == "stadium_orbit"
	var key := "stadium" if orbit else name
	if not STATIONS.has(key):
		return
	var to_pos: Vector3 = STATIONS[key][0]
	var to_look: Vector3 = STATIONS[key][1]
	if station == name and not instant:
		return
	var far_jump := cam.position.distance_to(to_pos) > 60.0
	station = name
	_apply_proj(instant)
	if tween:
		tween.kill()
	if instant or orbit and far_jump:
		cam.position = to_pos
		cam_look = to_look
		cam.look_at(cam_look)
		return
	tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var dur := 1.1 if not far_jump else 0.9
	if far_jump:
		# uzak istasyon: hızlı "kesme" (önce yaklaş, sonra ışınlan)
		cam.position = to_pos + (cam.position - to_pos).normalized() * 6.0 if false else to_pos + Vector3(0, 2.0, 4.0)
		cam_look = to_look
	tween.tween_property(cam, "position", to_pos, dur)
	tween.tween_method(func(v):
		cam_look = v, cam_look, to_look, dur)

## Menüde 3D'yi seyrek çiz: kamera dururken saniyede ~20 kare yeter
var _thr_t := 0.0
func _throttle(delta: float) -> void:
	if not active:
		return
	var moving := (tween != null and tween.is_running()) or orbit or station == "pedestal" or absf(cam.fov - fov_target) > 0.2
	if moving or Game.quality() == "high":
		if sv.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	_thr_t += delta
	if _thr_t >= 0.05:
		_thr_t = 0.0
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	elif sv.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE

func _process(delta: float) -> void:
	_throttle(delta)
	if orbit:
		orbit_t += delta * 0.06
		cam.position = STAD + Vector3(sin(orbit_t) * 85.0, 32.0 + sin(orbit_t * 0.7) * 6.0, cos(orbit_t) * 85.0)
		cam_look = STAD
	cam.look_at(cam_look)
	var pd := pitch_deg
	if station == "pedestal" and pd > 0.0:
		pd = 9.0
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		pd = 0.0
	cam.fov = lerpf(cam.fov, fov_target, minf(1.0, delta * 4.0))
	if pd != 0.0:
		cam.rotate_object_local(Vector3.RIGHT, -deg_to_rad(pd))
	if me_man and station in ["office", "desk", "board"]:
		me_man.tick(delta, 0.0)
		tv_t += delta
		if tv_t > 4.0:
			tv_t = 0.0
			tv_i += 1
			_update_tv()
		clock_t += delta
		if clock_t > 30.0:
			clock_t = 0.0
			_update_sky()
			_update_clock()
		if ring_t >= 0.0:
			ring_t += delta
			if ring_t < 1.6:
				phone_node.rotation.y = sin(ring_t * 60.0) * 0.06
				phone_node.position.y = 0.82 + absf(sin(ring_t * 60.0)) * 0.004
			elif ring_t < 1.7:
				me_man.overlay = "phone"
				phone_node.visible = false
			elif ring_t > 5.0:
				me_man.overlay = "type"
				phone_node.visible = true
				phone_node.rotation.y = 0.0
				ring_t = -1.0
	if station == "pedestal" and ped_player:
		ped_turn += delta * 0.4
		ped_player.rotation.y = 0.5 + sin(ped_turn) * 0.7
		ped_player.tick(delta, 0.0)
		if ped_ball and ped_ball.visible:
			var sk: Skeleton3D = ped_player.skel
			var fl := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("ball_l"))).origin
			var fr := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("ball_r"))).origin
			var foot := fl if fl.y > fr.y else fr
			var hgt := 0.3 + absf(sin(ped_turn * 8.5)) * 0.6
			var tgt := ped_root.to_local(foot) + Vector3(0, hgt, 0)
			ped_ball.position = ped_ball.position.lerp(tgt, minf(1.0, delta * 12.0))
	if stadium_built and (station == "stadium" or orbit):
		for mm in stadium_men:
			var n = mm.n
			var to: Vector3 = mm.t - n.position
			if to.length() < 1.0:
				mm.t = Vector3(randf_range(-45, 45), 0, randf_range(-28, 28))
			var v := to.normalized() * 4.5
			n.position += v * delta
			n.rotation.y = atan2(v.x, v.z)
			n.tick(delta, 4.5)
