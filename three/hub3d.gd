extends SubViewportContainer
## Menülerin arkasındaki kalıcı 3D dünya. İstasyonlar: ofis masası, dedektif panosu,
## harita masası, oyuncu kürsüsü, stadyum. goto(istasyon) ile kamera uçar.

const FB = preload("res://three/mocap_man.gd")
const Stadium = preload("res://three/stadium.gd")
const TrMap = preload("res://ui/map.gd")

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
var pennant_mat: StandardMaterial3D
var pennant_mat2: StandardMaterial3D
var trophy_root: Node3D
var stadium_built := false
var stadium_node: Node3D
var stadium_men := []
var laptop_mat: ShaderMaterial

const OFFICE := Vector3(0, 0, 0)
const MAP := Vector3(40, 0, 0)
const PED := Vector3(80, 0, 0)
const STAD := Vector3(400, 0, 0)

const STATIONS := {
	"office": [Vector3(1.0, 1.75, 0.6), Vector3(-0.2, 1.05, -2.5)],
	"desk": [Vector3(2.9, 1.75, -0.3), Vector3(1.6, 1.55, -3.6)],
	"board": [Vector3(0.4, 1.85, -1.2), Vector3(-4.9, 1.8, -1.2)],
	"map": [Vector3(40, 12.5, 3.4), Vector3(40, 0.9, 0.5)],
	"pedestal": [Vector3(80.0, 1.55, 5.2), Vector3(80, 1.25, 0)],
	"stadium": [Vector3(400 - 30, 22, 38), Vector3(400, 0, 0)],
}
var pitch_deg := 0.0
var active := true

func set_pitch(deg: float) -> void:
	pitch_deg = deg

func set_active(on: bool) -> void:
	active = on
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
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 sky = mix(vec3(0.05, 0.06, 0.14), vec3(0.01, 0.01, 0.04), uv.y * -1.0 + 1.0);
	sky = mix(vec3(0.12, 0.08, 0.16), vec3(0.01, 0.015, 0.05), 1.0 - uv.y);
	float star = step(0.996, hash(floor(uv * vec2(220.0, 140.0)))) * step(0.45, 1.0 - uv.y);
	vec3 col = sky + vec3(star);
	float bx = floor(uv.x * 26.0);
	float bh = 0.25 + hash(vec2(bx, 3.0)) * 0.45;
	if (1.0 - uv.y < bh) {
		vec2 w = fract(uv * vec2(26.0 * 5.0, 60.0));
		float lit = step(0.55, hash(floor(uv * vec2(26.0 * 5.0, 60.0)) + floor(TIME * 0.05)));
		float win = step(0.25, w.x) * step(w.x, 0.75) * step(0.3, w.y) * step(w.y, 0.8);
		col = vec3(0.02, 0.025, 0.04) + vec3(1.0, 0.8, 0.45) * win * lit * 0.8;
	}
	// uzakta stadyum ışıkları
	float glow = exp(-pow(length((uv - vec2(0.7, 0.62)) * vec2(1.0, 2.5)), 2.0) * 20.0);
	col += vec3(0.9, 0.95, 1.0) * glow * 0.6;
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
	sv = SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_2X if Game.quality() == "high" else Viewport.MSAA_DISABLED
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
	_build_office()
	_build_map()
	_build_pedestal()
	cam.position = STATIONS.office[0]
	cam_look = STATIONS.office[1]
	cam.look_at(cam_look)

func apply_quality() -> void:
	sv.msaa_3d = Viewport.MSAA_2X if Game.quality() == "high" else Viewport.MSAA_DISABLED
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
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	we.environment = env
	world.add_child(we)

# ================================================================ ofis

func _build_office() -> void:
	var o := Node3D.new()
	o.position = OFFICE
	world.add_child(o)
	var floor_m := _shader(WOOD_SHADER)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 10)
	fl.mesh = pm
	fl.material_override = floor_m
	fl.position = Vector3(0, 0, -1)
	o.add_child(fl)
	var wall := _shader(WALL_SHADER)
	_box(o, Vector3(12, 4.2, 0.2), Vector3(0, 2.1, -4.0), wall)
	_box(o, Vector3(0.2, 4.2, 10), Vector3(-5.1, 2.1, -1), wall)
	_box(o, Vector3(0.2, 4.2, 10), Vector3(5.1, 2.1, -1), wall)
	_box(o, Vector3(12, 0.2, 10), Vector3(0, 4.2, -1), _mat(Color(0.05, 0.06, 0.06)))
	# süpürgelik
	_box(o, Vector3(12, 0.15, 0.05), Vector3(0, 0.075, -3.88), _mat(Color(0.12, 0.08, 0.05)))
	# pencere (gece şehir manzarası)
	var win := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 1.6)
	win.mesh = q
	win.material_override = _shader(CITY_SHADER)
	win.position = Vector3(2.4, 2.2, -3.88)
	o.add_child(win)
	var frame := _mat(Color(0.1, 0.1, 0.11), 0.4, 0.5)
	_box(o, Vector3(2.8, 0.08, 0.1), Vector3(2.4, 3.04, -3.86), frame)
	_box(o, Vector3(2.8, 0.08, 0.1), Vector3(2.4, 1.36, -3.86), frame)
	_box(o, Vector3(0.08, 1.7, 0.1), Vector3(1.06, 2.2, -3.86), frame)
	_box(o, Vector3(0.08, 1.7, 0.1), Vector3(3.74, 2.2, -3.86), frame)
	_box(o, Vector3(0.05, 1.6, 0.06), Vector3(2.4, 2.2, -3.86), frame)
	var moon := OmniLight3D.new()
	moon.position = Vector3(2.4, 2.2, -3.3)
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.5
	moon.omni_range = 5.0
	o.add_child(moon)
	# masa
	var desk_m := _mat(Color(0.16, 0.09, 0.05), 0.35)
	_box(o, Vector3(2.6, 0.07, 1.2), Vector3(0, 0.78, -2.3), desk_m)
	for x in [-1.2, 1.2]:
		_box(o, Vector3(0.07, 0.78, 1.1), Vector3(x, 0.39, -2.3), desk_m)
	_box(o, Vector3(2.4, 0.5, 0.04), Vector3(0, 0.5, -2.85), desk_m)
	# laptop
	var metal := _mat(Color(0.55, 0.57, 0.6), 0.3, 0.8)
	_box(o, Vector3(0.62, 0.025, 0.42), Vector3(-0.15, 0.825, -2.15), metal)
	var screen := Node3D.new()
	screen.position = Vector3(-0.15, 0.84, -2.36)
	screen.rotation_degrees = Vector3(-14, 0, 0)
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
	glow.position = Vector3(-0.15, 1.05, -2.0)
	glow.light_color = Color(0.5, 0.9, 0.7)
	glow.light_energy = 0.35
	glow.omni_range = 1.4
	o.add_child(glow)
	# defter ve kalem
	var paper := _mat(Color(0.93, 0.9, 0.82), 0.9)
	_box(o, Vector3(0.32, 0.02, 0.23), Vector3(0.55, 0.825, -2.05), paper, Vector3(0, -12, 0))
	_box(o, Vector3(0.33, 0.012, 0.24), Vector3(0.55, 0.818, -2.05), _mat(Color(0.25, 0.1, 0.08)), Vector3(0, -12, 0))
	_cyl(o, 0.008, 0.008, 0.15, Vector3(0.62, 0.84, -2.0), _mat(Color(0.1, 0.2, 0.5), 0.3, 0.4), Vector3(0, 0, 90), 8)
	# kupa
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
	# masa lambası
	var lamp_m := _mat(Color(0.08, 0.08, 0.09), 0.35, 0.6)
	_cyl(o, 0.09, 0.1, 0.03, Vector3(-0.95, 0.83, -2.55), lamp_m)
	_box(o, Vector3(0.025, 0.5, 0.025), Vector3(-0.95, 1.07, -2.5), lamp_m, Vector3(15, 0, 0))
	var head := _cyl(o, 0.03, 0.11, 0.14, Vector3(-0.85, 1.3, -2.38), lamp_m, Vector3(60, 0, -40))
	var spot := SpotLight3D.new()
	spot.position = Vector3(-0.82, 1.27, -2.36)
	spot.rotation_degrees = Vector3(-75, -20, 0)
	spot.light_color = Color(1.0, 0.82, 0.55)
	spot.light_energy = 3.0
	spot.spot_range = 3.0
	spot.spot_angle = 42.0
	spot.shadow_enabled = Game.quality() == "high"
	o.add_child(spot)
	var bulb := _sphere(o, 0.03, Vector3(-0.83, 1.26, -2.37), _mat(Color(1.0, 0.85, 0.6), 0.2, 0.0, 6.0))
	# tavan lambası (loş)
	var ceil_l := OmniLight3D.new()
	ceil_l.position = Vector3(0, 3.8, -1.0)
	ceil_l.light_color = Color(1.0, 0.9, 0.75)
	ceil_l.light_energy = 1.4
	ceil_l.omni_range = 10.0
	var fill_l := OmniLight3D.new()
	fill_l.position = Vector3(1.5, 2.2, 0.5)
	fill_l.light_color = Color(0.8, 0.85, 1.0)
	fill_l.light_energy = 0.7
	fill_l.omni_range = 7.0
	o.add_child(fill_l)
	o.add_child(ceil_l)
	# flama
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
	# raf ve kupalar
	_box(o, Vector3(1.6, 0.05, 0.3), Vector3(-2.6, 1.9, -3.75), desk_m)
	trophy_root = Node3D.new()
	trophy_root.position = Vector3(-2.6, 1.925, -3.75)
	o.add_child(trophy_root)
	# dedektif panosu (sol duvar)
	_box(o, Vector3(0.06, 1.7, 3.2), Vector3(-4.97, 1.75, -1.2), _shader(CORK_SHADER))
	_box(o, Vector3(0.08, 1.8, 0.08), Vector3(-4.95, 1.75, 0.42), frame)
	_box(o, Vector3(0.08, 1.8, 0.08), Vector3(-4.95, 1.75, -2.82), frame)
	_box(o, Vector3(0.08, 0.08, 3.3), Vector3(-4.95, 2.62, -1.2), frame)
	_box(o, Vector3(0.08, 0.08, 3.3), Vector3(-4.95, 0.88, -1.2), frame)
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
	# halı
	_box(o, Vector3(3.2, 0.01, 2.2), Vector3(0, 0.005, -1.2), _mat(Color(0.12, 0.05, 0.05), 1.0))

func set_club(c1: Color, c2: Color) -> void:
	pennant_mat.albedo_color = c1
	pennant_mat2.albedo_color = c2

func set_trophies(n: int) -> void:
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
	var paper := _mat(Color(0.95, 0.93, 0.88), 0.9)
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
		_box(card, Vector3(0.16, 0.2, 0.012), Vector3(-0.2, -0.04, 0.002), _mat(Color(0.3, 0.3, 0.32), 0.9))
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
	# Türkiye: ekstrüde poligon
	var poly := PackedVector2Array()
	for p in TrMap.OUTLINE:
		poly.append(_geo(p[0], p[1]))
	var tris := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_y := 0.97
	var bot_y := 0.85
	for i in range(0, tris.size(), 3):
		for k in [0, 2, 1]:
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
	map_root.add_child(land)
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

func _geo(lon: float, lat: float) -> Vector2:
	var w := 6.6
	var x := (lon - 35.3) / 19.4 * w
	var y := -(lat - 38.95) / 19.4 * w * 1.28
	return Vector2(x, y)

func set_map(home: String, match_cities: Array, planned: Array, labels: Dictionary) -> void:
	for c in map_dyn.get_children():
		c.queue_free()
	var pole := _mat(Color(0.8, 0.82, 0.85), 0.3, 0.8)
	for city in Data.CITY_POS:
		var p = Data.CITY_POS[city]
		var g := _geo(p[1], p[0])
		var is_home: bool = city == home
		var is_match: bool = city in match_cities
		var is_plan: bool = city in planned
		var col := Color(0.55, 0.62, 0.58, 1)
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
	var hp = Data.CITY_POS.get(home, [39.0, 35.0])
	var hg := _geo(hp[1], hp[0])
	var dot := _mat(Color("#e8c547"), 0.3, 0.0, 4.0)
	for city in planned:
		var cp = Data.CITY_POS.get(city, [39.0, 35.0])
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
	ped_player.build(kit, int(p.get("skin", 1)), int(p.get("hair", 0)), int(p.get("seed", 0)), (int(p.get("seed", 0)) % 30) + 1, font)
	ped_player.position = Vector3(0, 0.35, 0)
	if ped_player.has_method("set_base"):
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
	for i in 12:
		var f = FB.new()
		stadium_node.add_child(f)
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

func _process(delta: float) -> void:
	if orbit:
		orbit_t += delta * 0.06
		cam.position = STAD + Vector3(sin(orbit_t) * 85.0, 32.0 + sin(orbit_t * 0.7) * 6.0, cos(orbit_t) * 85.0)
		cam_look = STAD
	cam.look_at(cam_look)
	var pd := pitch_deg
	if station == "pedestal" and pd > 0.0:
		pd = 9.0
	if pd != 0.0:
		cam.rotate_object_local(Vector3.RIGHT, -deg_to_rad(pd))
	if station == "pedestal" and ped_player:
		ped_turn += delta * 0.4
		ped_player.rotation.y = 0.5 + sin(ped_turn) * 0.7
		ped_player.tick(delta, 0.0)
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
