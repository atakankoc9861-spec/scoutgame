extends Node3D
## Eklemli prosedürel futbolcu. Yüz +Z yönüne bakar, ayaklar y=0.
## Animasyonlar: koşu/bekleme (sürekli) + tek seferlik aksiyonlar (kick, header, dive, slide, tackle, celebrate).

const SKIN := [Color("#f1c9a5"), Color("#e0ac85"), Color("#c68863"), Color("#8d5a3b"), Color("#5a3825")]
const HAIR := [Color("#1b1410"), Color("#2c1d14"), Color("#4a3020"), Color("#0e0b0a"), Color("#8a5a2b"), Color("#c9a45c")]

var hips: Node3D
var spine: Node3D
var neck: Node3D
var sh_l: Node3D
var sh_r: Node3D
var el_l: Node3D
var el_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var kn_l: Node3D
var kn_r: Node3D
var number_lbl: Label3D

var phase := 0.0
var speed := 0.0          # m/s (yatay)
var action := ""
var action_t := 0.0
var action_dur := 0.5
var action_side := 1.0    # dalış yönü vb.
var mats := {}

static func make_mat(col: Color, rough := 0.65) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m

static func kit_mats(shirt: Color, shorts: Color, socks: Color) -> Dictionary:
	return {"shirt": make_mat(shirt, 0.55), "shorts": make_mat(shorts, 0.6), "socks": make_mat(socks, 0.7),
		"boot": make_mat(Color(0.06, 0.06, 0.07), 0.3)}

func build(kit: Dictionary, skin_i: int, hair_i: int, style: int, number: int, font: Font = null) -> void:
	var skin := make_mat(SKIN[clampi(skin_i, 0, 4)], 0.75)
	var hair := make_mat(HAIR[clampi(hair_i, 0, 5)], 0.9)
	hips = _pivot(self, Vector3(0, 0.95, 0))
	_mesh(hips, _cap(0.19, 0.36), kit.shorts, Vector3(0, -0.04, 0), Vector3(0, 0, 90), Vector3(1, 1.0, 0.75))
	spine = _pivot(hips, Vector3(0, 0.06, 0))
	_mesh(spine, _cap(0.17, 0.6), kit.shirt, Vector3(0, 0.26, 0), Vector3.ZERO, Vector3(1.28, 1, 0.78))
	neck = _pivot(spine, Vector3(0, 0.56, 0))
	_mesh(neck, _cyl(0.05, 0.1), skin, Vector3(0, 0.03, 0))
	_mesh(neck, _sph(0.112), skin, Vector3(0, 0.17, 0.0), Vector3.ZERO, Vector3(0.92, 1.05, 1.0))
	# saç stilleri
	match style % 4:
		0:
			_mesh(neck, _hemi(0.12, 0.09), hair, Vector3(0, 0.205, -0.008))
		1:
			_mesh(neck, _hemi(0.128, 0.13), hair, Vector3(0, 0.19, -0.01))
		2:
			_mesh(neck, _hemi(0.118, 0.05), hair, Vector3(0, 0.22, -0.005))
		_:
			_mesh(neck, _sph(0.13), hair, Vector3(0, 0.2, -0.03), Vector3.ZERO, Vector3(1, 0.9, 1.05))
	for side in [-1.0, 1.0]:
		var sh := _pivot(spine, Vector3(0.235 * side, 0.46, 0))
		_mesh(sh, _sph(0.075), kit.shirt, Vector3.ZERO)
		_mesh(sh, _cap(0.058, 0.3), kit.shirt, Vector3(0, -0.13, 0))
		var el := _pivot(sh, Vector3(0, -0.27, 0))
		_mesh(el, _cap(0.048, 0.27), skin, Vector3(0, -0.12, 0))
		_mesh(el, _sph(0.045), skin, Vector3(0, -0.27, 0))
		var hp := _pivot(hips, Vector3(0.1 * side, -0.08, 0))
		_mesh(hp, _cap(0.082, 0.36), kit.shorts, Vector3(0, -0.12, 0))
		_mesh(hp, _cap(0.07, 0.32), skin, Vector3(0, -0.3, 0))
		var kn := _pivot(hp, Vector3(0, -0.43, 0))
		_mesh(kn, _cap(0.058, 0.42), kit.socks, Vector3(0, -0.2, 0))
		_mesh(kn, _box(Vector3(0.1, 0.07, 0.24)), kit.boot, Vector3(0, -0.43, 0.05))
		if side < 0:
			sh_l = sh
			el_l = el
			hip_l = hp
			kn_l = kn
		else:
			sh_r = sh
			el_r = el
			hip_r = hp
			kn_r = kn
	# sırt numarası
	number_lbl = Label3D.new()
	number_lbl.text = str(number)
	number_lbl.font_size = 96
	number_lbl.pixel_size = 0.0028
	number_lbl.outline_size = 0
	number_lbl.modulate = Color(1, 1, 1) if kit.shirt.albedo_color.get_luminance() < 0.55 else Color(0.08, 0.08, 0.1)
	number_lbl.double_sided = false
	number_lbl.position = Vector3(0, 0.33, -0.142)
	number_lbl.rotation_degrees = Vector3(0, 180, 0)
	if font:
		number_lbl.font = font
	spine.add_child(number_lbl)

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

static var _cache := {}
func _cap(r: float, h: float) -> Mesh:
	var k := "c%.3f_%.3f" % [r, h]
	if not _cache.has(k):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 10
		m.rings = 4
		_cache[k] = m
	return _cache[k]

func _sph(r: float) -> Mesh:
	var k := "s%.3f" % r
	if not _cache.has(k):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 12
		m.rings = 6
		_cache[k] = m
	return _cache[k]

func _hemi(r: float, h: float) -> Mesh:
	var k := "h%.3f_%.3f" % [r, h]
	if not _cache.has(k):
		var m := SphereMesh.new()
		m.radius = r
		m.height = h * 2.0
		m.is_hemisphere = true
		m.radial_segments = 12
		m.rings = 4
		_cache[k] = m
	return _cache[k]

func _cyl(r: float, h: float) -> Mesh:
	var k := "y%.3f_%.3f" % [r, h]
	if not _cache.has(k):
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 8
		_cache[k] = m
	return _cache[k]

func _box(s: Vector3) -> Mesh:
	var k := "b%s" % s
	if not _cache.has(k):
		var m := BoxMesh.new()
		m.size = s
		_cache[k] = m
	return _cache[k]

# ================================================================ animasyon

func play(name: String, dur := 0.5, side := 1.0) -> void:
	action = name
	action_t = 0.0
	action_dur = dur
	action_side = side

func is_busy() -> bool:
	return action != "" and action_t < action_dur

func tick(delta: float, spd: float, anim_speed := 1.0) -> void:
	speed = spd
	var cad := 1.6 + spd * 0.55
	phase += delta * cad * TAU * 0.5 * anim_speed
	if action != "":
		action_t += delta * anim_speed
		if action_t >= action_dur:
			action = ""
	apply_pose()

func apply_pose() -> void:
	var run := clampf(speed / 7.0, 0.0, 1.0)
	var s := sin(phase)
	var c := cos(phase)
	# temel: koşu / bekleme
	var thigh := s * (0.15 + 0.85 * run)
	var hip_y := 0.95 + absf(sin(phase)) * 0.05 * run
	var lean := 0.04 + 0.2 * run
	var breathe := sin(Time.get_ticks_msec() / 700.0 + phase) * 0.02 * (1.0 - run)
	hip_l.rotation = Vector3(-thigh, 0, 0.02)
	hip_r.rotation = Vector3(thigh, 0, -0.02)
	kn_l.rotation.x = maxf(0.0, c) * (0.25 + 1.25 * run) + 0.08
	kn_r.rotation.x = maxf(0.0, -c) * (0.25 + 1.25 * run) + 0.08
	sh_l.rotation = Vector3(thigh * 0.9, 0, -0.12)
	sh_r.rotation = Vector3(-thigh * 0.9, 0, 0.12)
	el_l.rotation.x = -0.35 - 0.9 * run
	el_r.rotation.x = -0.35 - 0.9 * run
	spine.rotation = Vector3(lean + breathe, s * 0.12 * run, 0)
	neck.rotation = Vector3(-lean * 0.6, 0, 0)
	hips.position.y = hip_y
	hips.rotation = Vector3(0, -s * 0.1 * run, 0)
	hips.position.x = 0.0
	hips.position.z = 0.0
	rotation.z = 0.0
	if action == "":
		return
	var f := clampf(action_t / maxf(0.001, action_dur), 0.0, 1.0)
	match action:
		"kick":
			# sağ bacak: geri çek, sonra öne savur
			var swing := 0.0
			if f < 0.4:
				swing = lerpf(0.0, 0.9, f / 0.4)
			else:
				swing = lerpf(0.9, -1.5, minf(1.0, (f - 0.4) / 0.3))
			hip_r.rotation.x = swing
			kn_r.rotation.x = 1.3 if f < 0.45 else lerpf(1.3, 0.05, minf(1.0, (f - 0.45) / 0.2))
			hip_l.rotation.x = -0.15
			kn_l.rotation.x = 0.3
			spine.rotation.x = -0.12
			sh_l.rotation = Vector3(-0.4, 0, -0.9)
			sh_r.rotation = Vector3(0.3, 0, 0.7)
		"header":
			var jump := sin(f * PI)
			hips.position.y = 0.95 + jump * 0.55
			kn_l.rotation.x = 0.9 * jump + 0.1
			kn_r.rotation.x = 0.6 * jump + 0.1
			hip_l.rotation.x = 0.4 * jump
			hip_r.rotation.x = 0.1
			sh_l.rotation = Vector3(-1.2 * jump, 0, -0.8 * jump)
			sh_r.rotation = Vector3(-1.2 * jump, 0, 0.8 * jump)
			neck.rotation.x = 0.5 if f > 0.45 and f < 0.65 else -0.3
			spine.rotation.x = -0.2 + (0.5 if f > 0.45 and f < 0.7 else 0.0)
		"dive":
			var e := minf(1.0, f / 0.35)
			var down := 0.0 if f < 0.75 else (f - 0.75) / 0.25
			rotation.z = -action_side * 1.35 * e * (1.0 - down * 0.15)
			hips.position.x = action_side * 1.3 * e
			hips.position.y = 0.95 + sin(e * PI * 0.5) * 0.35 - e * 0.35
			sh_l.rotation = Vector3(-2.9, 0, -0.2)
			sh_r.rotation = Vector3(-2.9, 0, 0.2)
			el_l.rotation.x = -0.1
			el_r.rotation.x = -0.1
			hip_l.rotation.x = 0.2
			hip_r.rotation.x = -0.3
		"slide":
			var e := minf(1.0, f / 0.25)
			var up := maxf(0.0, (f - 0.7) / 0.3)
			var k := e * (1.0 - up)
			hips.position.y = 0.95 - 0.7 * k
			spine.rotation.x = -1.0 * k
			hip_r.rotation.x = -1.4 * k
			kn_r.rotation.x = 0.05
			hip_l.rotation.x = -0.5 * k
			kn_l.rotation.x = 1.6 * k
			sh_l.rotation = Vector3(0.6 * k, 0, -0.9 * k)
			sh_r.rotation = Vector3(0.6 * k, 0, 0.9 * k)
			hips.position.z = 0.8 * k
		"tackle":
			var k := sin(f * PI)
			hip_r.rotation.x = -1.1 * k
			kn_r.rotation.x = 0.2
			spine.rotation.x = 0.35 * k
			hips.position.y = 0.95 - 0.15 * k
		"celebrate":
			var hop := absf(sin(f * PI * 4.0))
			hips.position.y = 0.95 + hop * 0.18
			sh_l.rotation = Vector3(-2.8, 0, -0.35)
			sh_r.rotation = Vector3(-2.8, 0, 0.35)
			el_l.rotation.x = -0.2
			el_r.rotation.x = -0.2
			spine.rotation.x = -0.25
			neck.rotation.x = -0.4
		"knee_slide":
			var k := minf(1.0, f / 0.2)
			hips.position.y = 0.95 - 0.5 * k
			hip_l.rotation.x = -1.4 * k
			kn_l.rotation.x = 1.5 * k
			hip_r.rotation.x = 0.3 * k
			kn_r.rotation.x = 1.9 * k
			spine.rotation.x = -0.5 * k
			sh_l.rotation = Vector3(-1.6, 0, -1.2)
			sh_r.rotation = Vector3(-1.6, 0, 1.2)
			neck.rotation.x = -0.6
		"wave":
			sh_r.rotation = Vector3(-2.6, 0, 0.3 + sin(f * TAU * 3.0) * 0.3)
			el_r.rotation.x = -0.4

func pose_state() -> Array:
	return [phase, speed, action, action_t, action_dur, action_side]

func set_pose_state(st: Array) -> void:
	phase = st[0]
	speed = st[1]
	action = st[2]
	action_t = st[3]
	action_dur = st[4]
	action_side = st[5]
	apply_pose()
