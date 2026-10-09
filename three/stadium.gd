extends Node3D
## Prosedürel gece stadyumu v2. Saha: X uzunluk (-52.5..52.5), Z genişlik (-34..34).

var home_c1 := Color("#d4a017")
var home_c2 := Color("#14213d")
var away_c1 := Color("#b5121b")
var crowd_mat: ShaderMaterial
var led_mat: ShaderMaterial
var net_mats := []
var flags := []
var confetti: Array = []
var flares: Array = []
var sun: DirectionalLight3D
var shadows := true
var fx_enabled := true

const PITCH_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 grass_a = vec3(0.022, 0.095, 0.026);
uniform vec3 grass_b = vec3(0.016, 0.072, 0.019);
uniform vec2 size = vec2(118.0, 82.0);
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
	float stripe = mod(floor((p.x + 52.5) / 5.25), 2.0);
	float cross_s = mod(floor((p.y + 34.0) / 6.8), 2.0);
	vec3 col = mix(grass_a, grass_b, stripe);
	col *= 0.96 + 0.05 * cross_s;
	float n = noise(p * 1.7) * 0.6 + noise(p * 9.0) * 0.4;
	col *= 0.86 + 0.24 * n;
	// yıpranmış alanlar (kale önü, orta saha)
	float wear = exp(-pow(length(vec2(a.x - 49.0, p.y)) / 6.0, 2.0)) + 0.5 * exp(-pow(length(p) / 7.0, 2.0));
	col = mix(col, vec3(0.05, 0.05, 0.02), wear * 0.35 * (0.6 + 0.4 * n));
	float w = 0.13;
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
	col = mix(col, vec3(0.8), L * (0.85 + 0.15 * n));
	if (a.x > 52.6 || a.y > 34.1) { col = mix(col, vec3(0.012, 0.04, 0.015), 0.4); }
	ALBEDO = col;
	ROUGHNESS = 0.82 - 0.2 * stripe;
	SPECULAR = 0.25;
}
"""

const CROWD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec3 c1 = vec3(0.8, 0.6, 0.1);
uniform vec3 c2 = vec3(0.1, 0.1, 0.3);
uniform vec3 c3 = vec3(0.7, 0.1, 0.1);
uniform float excite = 0.0;
uniform float away_share = 0.12;
uniform float seat_w = 0.55;
uniform float length_m = 100.0;
uniform float fill = 0.9;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float cols = length_m / seat_w;
	float row = floor(UV2.y + 0.001);
	vec2 g = vec2(UV.x * cols, UV.y);
	float ci = floor(g.x);
	float fx = fract(g.x);
	vec2 cell = vec2(ci, row);
	float h = hash(cell);
	float h2 = hash(cell + 17.3);
	float h3 = hash(cell + 41.7);
	vec3 seat = mix(vec3(0.05, 0.06, 0.08), c2 * 0.5, 0.35);
	vec3 col = seat * (0.8 + 0.2 * step(0.2, fract(UV.y * 3.0)));
	bool away = UV.x * length_m > length_m * (1.0 - away_share);
	vec3 shirt = away ? (h < 0.8 ? c3 : vec3(0.9)) : (h < 0.5 ? c1 : (h < 0.78 ? c2 : vec3(0.15 + h2 * 0.7)));
	float empty = step(fill, h3);
	// poz: sakin -> oturan/alkış, heyecan -> ayağa kalkan/kollar havada
	bool hype = excite > 0.15 + h2 * 0.6;
	float pose = floor(h * 4.0) + (hype ? 4.0 : 0.0);
	float rate = hype ? 3.5 : 1.2 + h3;
	float frame = floor(mod(TIME * rate + h * 4.0, 4.0));
	float variant = step(0.5, h2);
	float u = 0.5 + (fx - 0.5) * 0.62;
	float hgt = 0.62 + UV.y * 1.55 - (hype ? 0.0 : 0.05);
	float v = 1.0 - (hgt - 0.55) / 1.7;
	vec4 tx = vec4(0.0);
	if (u > 0.0 && u < 1.0 && v > 0.0 && v < 1.0) {
		tx = texture(atlas, vec2((variant * 4.0 + frame + u) / 8.0, (pose + v) / 8.0));
	}
	if (tx.a > 0.5 && empty < 0.5) {
		vec3 c = tx.rgb;
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
		if (sat < 0.12 && lum > 0.33) { c = shirt * (0.35 + lum * 0.85); }
		col = c;
	}
	float flash = step(0.997, hash(cell + floor(TIME * 3.0))) * (1.0 - empty);
	col += vec3(1.0) * flash * 1.5;
	float depth_fade = 0.6 + 0.4 * clamp(row / 14.0, 0.0, 1.0);
	ALBEDO = col * depth_fade * (0.85 + 0.35 * excite);
}
"""

const LED_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 c1 = vec3(0.9, 0.7, 0.1);
uniform vec3 c2 = vec3(0.1, 0.2, 0.6);
uniform float pulse = 0.0;
void fragment() {
	float x = UV.x * 20.0 - TIME * 0.9;
	float seg = mod(floor(x / 2.0), 3.0);
	vec3 col = seg < 1.0 ? c1 : (seg < 2.0 ? c2 : vec3(0.95));
	float fx = fract(x / 2.0);
	float chevron = step(0.5, fract(fx * 4.0 + UV.y * 1.5));
	col = mix(col * 0.5, col, chevron);
	float px = step(0.18, fract(UV.x * 600.0)) * step(0.18, fract(UV.y * 12.0));
	col *= 0.55 + 0.45 * px;
	col = mix(col, vec3(1.0, 0.85, 0.2), pulse * step(0.5, fract(TIME * 4.0)));
	ALBEDO = col * 1.8;
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
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float strength = 0.05;
void fragment() {
	float fall = pow(1.0 - UV.y, 1.5);
	float edge = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = vec3(1.0, 0.95, 0.85) * strength * fall * (1.0 - edge * 0.85);
}
"""

func build(hc1: Color, hc2: Color, ac1: Color, night := true, with_shadows := true, with_env := true) -> void:
	home_c1 = hc1
	home_c2 = hc2
	away_c1 = ac1
	shadows = with_shadows
	if with_env:
		_env(night)
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
	_stands()
	_lights()
	_led_boards()
	_flags()
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

func _env(night: bool) -> void:
	# Menüdeki (telefonda kararlı) ortamla aynı: düz renk arka plan, gökyüzü yok
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.56, 0.7)
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = shadows
	sun.shadow_opacity = 0.75
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.5
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-48, -152, 0)
	fill.light_energy = 0.28
	fill.light_color = Color(0.85, 0.9, 1.0)
	add_child(fill)

func _ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(320, 260)
	mi.mesh = pm
	mi.position.y = -0.05
	mi.material_override = _mat(Color(0.035, 0.045, 0.04))
	add_child(mi)
	# saha çevresi koşu bandı / beton
	_box(Vector3(126, 0.04, 90), Vector3(0, -0.03, 0), _mat(Color(0.06, 0.14, 0.07), 0.0, 0.95))

func _pitch() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(118, 82)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	mi.mesh = pm
	var pm_mat := _shader_mat(PITCH_SHADER)
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		pm_mat.set_shader_parameter("grass_a", Vector3(0.07, 0.24, 0.075))
		pm_mat.set_shader_parameter("grass_b", Vector3(0.055, 0.195, 0.06))
	mi.material_override = pm_mat
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
		# file: arka, üst, yanlar
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

func _tier_mesh(length: float, rows: int, rise: float, depth: float) -> ArrayMesh:
	## Basamaklı tribün: dikey yüzlerde seyirci (UV2.y = sıra no), yatay yüzler beton.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl := length / 2.0
	for i in rows:
		var y0 := i * rise
		var z0 := i * depth
		var y1 := y0 + rise
		# dikey (seyirci) yüz: z0'da, y0..y1
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

func _stand(length: float, rows: int, pos: Vector3, rot_y: float, upper: bool, roof: bool, away := false) -> void:
	var node := Node3D.new()
	node.position = pos
	node.rotation_degrees.y = rot_y
	add_child(node)
	var concrete := _mat(Color(0.13, 0.14, 0.16), 0.0, 0.9)
	var dark := _mat(Color(0.06, 0.065, 0.075), 0.0, 0.7)
	var rise := 0.85
	var depth := 0.8
	var lower := MeshInstance3D.new()
	lower.mesh = _tier_mesh(length, rows, rise, depth)
	var cm_low: ShaderMaterial = _crowd_for(length)
	if away:
		cm_low = cm_low.duplicate()
		cm_low.set_shader_parameter("away_share", 0.45)
		_crowd_cache[-int(length)] = cm_low
	lower.set_surface_override_material(0, cm_low)
	lower.set_surface_override_material(1, concrete)
	lower.position = Vector3(0, 1.4, 0)
	node.add_child(lower)
	_box(Vector3(length, 1.4, 0.4), Vector3(0, 0.7, -0.2), dark, Vector3.ZERO, node)
	var top_y := 1.4 + rows * rise
	var back_z := rows * depth
	if upper:
		var rows2 := rows - 3
		# balkon yüzü + LED şerit
		var bal_y := top_y + 2.2
		_box(Vector3(length, 2.2, 0.5), Vector3(0, top_y + 1.1, back_z - 0.2), dark, Vector3.ZERO, node)
		_box(Vector3(length, 0.5, 0.1), Vector3(0, top_y + 1.2, back_z - 0.5), led_ribbon(), Vector3.ZERO, node)
		var up := MeshInstance3D.new()
		up.mesh = _tier_mesh(length, rows2, rise * 1.05, depth)
		up.set_surface_override_material(0, _crowd_for(length))
		up.set_surface_override_material(1, concrete)
		up.position = Vector3(0, bal_y, back_z - 0.3)
		node.add_child(up)
		top_y = bal_y + rows2 * rise * 1.05
		back_z = back_z - 0.3 + rows2 * depth
	_box(Vector3(length + 1, top_y + 2.0, 1.0), Vector3(0, (top_y + 2.0) / 2.0, back_z + 0.5), concrete, Vector3.ZERO, node)
	for sx in [-1.0, 1.0]:
		var side := _box(Vector3(0.6, top_y, back_z), Vector3(sx * length / 2.0, top_y / 2.0, back_z / 2.0), dark, Vector3.ZERO, node)
	if roof:
		var ry := top_y + 6.0
		var roof_m := _mat(Color(0.1, 0.11, 0.13), 0.0, 0.5, 0.4)
		_box(Vector3(length + 2, 0.5, back_z + 6), Vector3(0, ry, back_z / 2.0 - 2.0), roof_m, Vector3(-4, 0, 0), node)
		# çatı altı ışık şeridi
		_box(Vector3(length - 4, 0.25, 0.6), Vector3(0, ry - 0.9, -3.5), _mat(Color(1.0, 0.97, 0.9), 5.0), Vector3.ZERO, node)
		# makas kirişler
		var truss := _mat(Color(0.35, 0.36, 0.4), 0.0, 0.35, 0.7)
		var n := int(length / 12.0)
		for i in n + 1:
			var x := -length / 2.0 + i * (length / n)
			_box(Vector3(0.3, 0.3, back_z + 6), Vector3(x, ry + 0.6, back_z / 2.0 - 2.0), truss, Vector3(-4, 0, 0), node)
			_box(Vector3(0.35, ry, 0.35), Vector3(x, ry / 2.0, back_z + 0.2), truss, Vector3.ZERO, node)
		# ışık huzmeleri
		for i in 5:
			var x := -length / 2.0 + (i + 0.5) * (length / 5.0)
			pass

func led_ribbon() -> ShaderMaterial:
	return led_mat if led_mat else _make_led()

func _make_led() -> ShaderMaterial:
	led_mat = _shader_mat(LED_SHADER)
	led_mat.set_shader_parameter("c1", Vector3(home_c1.r, home_c1.g, home_c1.b))
	led_mat.set_shader_parameter("c2", Vector3(home_c2.r, home_c2.g, home_c2.b) * 1.6 + Vector3(0.06, 0.06, 0.06))
	return led_mat

var _crowd_cache := {}
func _crowd_for(length: float) -> ShaderMaterial:
	if crowd_mat == null:
		crowd_mat = _shader_mat(CROWD_SHADER)
		crowd_mat.set_shader_parameter("atlas", preload("res://assets/crowd/atlas.png"))
	var key := int(length)
	if _crowd_cache.has(key):
		return _crowd_cache[key]
	var m: ShaderMaterial = crowd_mat.duplicate()
	m.set_shader_parameter("c1", Vector3(home_c1.r, home_c1.g, home_c1.b))
	m.set_shader_parameter("c2", Vector3(home_c2.r, home_c2.g, home_c2.b))
	m.set_shader_parameter("c3", Vector3(away_c1.r, away_c1.g, away_c1.b))
	m.set_shader_parameter("length_m", length)
	m.set_shader_parameter("away_share", 0.0)
	_crowd_cache[key] = m
	return m

func _beam(parent: Node3D, from: Vector3, to: Vector3) -> void:
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
	mi.material_override = _shader_mat(BEAM_SHADER)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var mid := (from + to) / 2.0
	mi.position = mid
	var dir := (to - from).normalized()
	var b := Basis()
	var y := -dir
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length() < 0.1:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	mi.basis = Basis(x, y, z)

func _stands() -> void:
	_make_led()
	_stand_at(112.0, 14, Vector3(0, 0, 40.5), true, true)
	_stand_at(112.0, 14, Vector3(0, 0, -40.5), true, true)
	_stand_at(70.0, 16, Vector3(61.5, 0, 0), false, true)
	_stand_at(70.0, 16, Vector3(-61.5, 0, 0), false, true, true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_stand_at(24.0, 12, Vector3(sx * 58.5, 0, sz * 39.5), false, false)

func _stand_at(length: float, rows: int, pos: Vector3, upper: bool, roof: bool, away := false) -> void:
	var d := Vector2(pos.x, pos.z).normalized()
	var rot := rad_to_deg(atan2(d.x, d.y))
	_stand(length, rows, pos, rot, upper, roof, away)

func _lights() -> void:
	var pole := _mat(Color(0.3, 0.31, 0.34), 0.0, 0.35, 0.6)
	var lamp := _mat(Color(1.0, 0.98, 0.92), 7.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * 70.0, 0, sz * 54.0)
			var pole_mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.9
			cm.height = 46.0
			pole_mi.mesh = cm
			pole_mi.material_override = pole
			pole_mi.position = p + Vector3(0, 23, 0)
			add_child(pole_mi)
			var head := Node3D.new()
			head.position = p + Vector3(0, 46.5, 0)
			add_child(head)
			head.look_at(Vector3(0, 0, 0), Vector3.UP)
			_box(Vector3(9, 5, 0.6), Vector3.ZERO, pole, Vector3.ZERO, head)
			for ix in 4:
				for iy in 3:
					_box(Vector3(1.6, 1.2, 0.2), Vector3(-3.3 + ix * 2.2, -1.5 + iy * 1.5, -0.4), lamp, Vector3.ZERO, head)
			var omni := OmniLight3D.new()
			omni.position = p * 0.75 + Vector3(0, 30.0, 0)
			omni.omni_range = 90.0
			omni.light_energy = 0.22
			omni.light_color = Color(1.0, 0.97, 0.9)
			omni.shadow_enabled = false
			add_child(omni)

func _led_boards() -> void:
	for sz in [-1.0, 1.0]:
		_box(Vector3(96, 0.95, 0.15), Vector3(0, 0.48, sz * 37.2), led_mat)
		_box(Vector3(96, 0.95, 0.3), Vector3(0, 0.48, sz * 37.45), _mat(Color(0.05, 0.05, 0.06)))
	for sx in [-1.0, 1.0]:
		for z in [-22.0, 22.0]:
			_box(Vector3(0.15, 0.95, 26), Vector3(sx * 56.0, 0.48, z), led_mat)

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
	for x in [-9.0, 9.0]:
		var n := Node3D.new()
		n.position = Vector3(x, 0, 41.2)
		add_child(n)
		_box(Vector3(7, 0.08, 1.8), Vector3(0, 2.2, 0), glass, Vector3(-10, 0, 0), n)
		_box(Vector3(7, 2.2, 0.08), Vector3(0, 1.1, 0.9), glass, Vector3.ZERO, n)
		for i in 8:
			_box(Vector3(0.5, 0.5, 0.5), Vector3(-3.0 + i * 0.85, 0.5, 0.4), seat, Vector3.ZERO, n)

func _effects() -> void:
	if true:
		return
	# konfeti (CPU parçacıkları: tüm telefonlarda güvenli)
	for sx in [-1.0, 1.0]:
		var p := CPUParticles3D.new()
		p.amount = 120
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

func set_fill(v: float) -> void:
	for k in _crowd_cache:
		_crowd_cache[k].set_shader_parameter("fill", v)

func set_excite(v: float) -> void:
	for k in _crowd_cache:
		_crowd_cache[k].set_shader_parameter("excite", v)
	if led_mat:
		led_mat.set_shader_parameter("pulse", clampf(v, 0.0, 1.0))

func goal_fx(side: float, home_scored: bool) -> void:
	for p in confetti:
		p.restart()
		p.emitting = true
	if home_scored and false:
		for f in flares:
			f.emitting = true
			var lamp: OmniLight3D = f.get_child(0)
			lamp.light_energy = 2.0
			var tw := create_tween()
			tw.tween_interval(5.0)
			tw.tween_property(lamp, "light_energy", 0.0, 2.0)
			tw.tween_callback(func(): f.emitting = false)

func net_hit(goal_x: float, hit: Vector3) -> void:
	var idx := 0 if goal_x < 0 else 1
	if idx >= net_mats.size():
		return
	var m: ShaderMaterial = net_mats[idx]
	m.set_shader_parameter("hit", hit)
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("bulge", v), 0.0, 1.0, 0.12)
	tw.tween_method(func(v): m.set_shader_parameter("bulge", v), 1.0, 0.0, 1.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
