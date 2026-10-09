extends Node3D
## Gerçekçi oranlı, iskeletli, tek parça prosedürel futbolcu.
## Gövde lofting ile üretilir, vertex renkleri forma bölgelerini taşır, kemik pozlarıyla canlanır.
## API eski footballer.gd ile aynı: build/play/tick/apply_pose/pose_state.

const SKIN := [Color("#f1c9a5"), Color("#e0ac85"), Color("#c68863"), Color("#8d5a3b"), Color("#5a3825")]
const HAIR := [Color("#1b1410"), Color("#2c1d14"), Color("#4a3020"), Color("#0e0b0a"), Color("#8a5a2b"), Color("#c9a45c")]

enum B { HIPS, SPINE, CHEST, NECK, HEAD, SH_L, EL_L, HA_L, SH_R, EL_R, HA_R, HIP_L, KN_L, AN_L, HIP_R, KN_R, AN_R }
const PARENT := [-1, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9, 0, 11, 12, 0, 14, 15]
const REST := [
	Vector3(0, 0.95, 0), Vector3(0, 0.1, 0), Vector3(0, 0.2, 0), Vector3(0, 0.25, 0), Vector3(0, 0.1, 0),
	Vector3(0.175, 0.18, 0), Vector3(0, -0.28, 0), Vector3(0, -0.25, 0),
	Vector3(-0.175, 0.18, 0), Vector3(0, -0.28, 0), Vector3(0, -0.25, 0),
	Vector3(0.095, -0.06, 0), Vector3(0, -0.43, 0), Vector3(0, -0.42, 0),
	Vector3(-0.095, -0.06, 0), Vector3(0, -0.43, 0), Vector3(0, -0.42, 0),
]

static func make_mat(col: Color, rough := 0.65) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m

static func kit_mats(shirt: Color, shorts: Color, socks: Color) -> Dictionary:
	return {"shirt": make_mat(shirt), "shorts": make_mat(shorts), "socks": make_mat(socks), "boot": make_mat(Color(0.06, 0.06, 0.07))}

static var _mesh_cache := {}
static var _mat_shared: StandardMaterial3D

var skel: Skeleton3D
var mesh_inst: MeshInstance3D
var number_lbl: Label3D
var gpos := []     # kemiklerin global dinlenme konumları

var phase := 0.0
var speed := 0.0
var action := ""
var action_t := 0.0
var action_dur := 0.5
var action_side := 1.0
var _qcache := {}

func build(kit: Dictionary, skin_i: int, hair_i: int, style: int, number: int, font: Font = null) -> void:
	var shirt: Color = kit.shirt.albedo_color
	var shorts: Color = kit.shorts.albedo_color
	var socks: Color = kit.socks.albedo_color
	var skin: Color = SKIN[clampi(skin_i, 0, 4)]
	var hair: Color = HAIR[clampi(hair_i, 0, 5)]
	skel = Skeleton3D.new()
	add_child(skel)
	gpos.resize(REST.size())
	for i in REST.size():
		skel.add_bone(B.keys()[i])
		if PARENT[i] >= 0:
			skel.set_bone_parent(i, PARENT[i])
		skel.set_bone_rest(i, Transform3D(Basis(), REST[i]))
		gpos[i] = REST[i] if PARENT[i] < 0 else gpos[PARENT[i]] + REST[i]
	skel.reset_bone_poses()
	var key := "%s|%s|%s|%d|%d|%d" % [shirt.to_html(), shorts.to_html(), socks.to_html(), skin_i, hair_i, style % 4]
	if not _mesh_cache.has(key):
		_mesh_cache[key] = _build_mesh(shirt, shorts, socks, skin, hair, style % 4)
	mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = _mesh_cache[key]
	if _mat_shared == null:
		_mat_shared = StandardMaterial3D.new()
		_mat_shared.vertex_color_use_as_albedo = true
		_mat_shared.roughness = 0.62
	mesh_inst.material_override = _mat_shared
	skel.add_child(mesh_inst)
	mesh_inst.skeleton = NodePath("..")
	mesh_inst.skin = skel.create_skin_from_rest_transforms()
	# sırt numarası
	var att := BoneAttachment3D.new()
	att.bone_name = "CHEST"
	skel.add_child(att)
	number_lbl = Label3D.new()
	number_lbl.text = str(number)
	number_lbl.font_size = 96
	number_lbl.pixel_size = 0.0026
	number_lbl.modulate = Color(1, 1, 1) if shirt.get_luminance() < 0.55 else Color(0.08, 0.08, 0.1)
	number_lbl.position = Vector3(0, 0.05, -0.128)
	number_lbl.rotation_degrees = Vector3(0, 180, 0)
	number_lbl.double_sided = false
	if font:
		number_lbl.font = font
	att.add_child(number_lbl)

# ================================================================ mesh üretimi

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _bo := PackedInt32Array()
var _we := PackedFloat32Array()
var _idx := PackedInt32Array()

func _add_vert(p: Vector3, n: Vector3, c: Color, bones: Array, weights: Array) -> int:
	_v.append(p)
	_n.append(n.normalized())
	_c.append(c)
	for i in 4:
		_bo.append(bones[i] if i < bones.size() else 0)
		_we.append(weights[i] if i < weights.size() else 0.0)
	return _v.size() - 1

func _tube(p0: Vector3, p1: Vector3, radii: Array, color_fn: Callable, weight_fn: Callable, segs := 12, flat_z := 1.0) -> void:
	## radii: [[t, rx, rz], ...] profil. Eksen p0->p1.
	var axis := (p1 - p0)
	var len := axis.length()
	var d := axis / len
	var side := Vector3(1, 0, 0)
	if absf(d.dot(side)) > 0.9:
		side = Vector3(0, 0, 1)
	var u := (side - d * d.dot(side)).normalized()
	var w := d.cross(u).normalized()
	# renk sınırlarında keskin geçiş için ek halkalar
	var rr: Array = radii.duplicate(true)
	var prev: Color = color_fn.call(0.0)
	for k in range(1, 81):
		var tt := k / 80.0
		var cc: Color = color_fn.call(tt)
		if cc != prev:
			for e in [tt - 0.0124, tt]:
				var j := 0
				while j < rr.size() - 1 and rr[j + 1][0] < e:
					j += 1
				var a0: Array = rr[j]
				var a1: Array = rr[mini(j + 1, rr.size() - 1)]
				var f := 0.0 if a1[0] == a0[0] else clampf((e - a0[0]) / (a1[0] - a0[0]), 0.0, 1.0)
				rr.insert(j + 1, [e, lerpf(a0[1], a1[1], f), lerpf(a0[2], a1[2], f)])
		prev = cc
	radii = rr
	var rings := radii.size()
	var base := _v.size()
	for ri in rings:
		var t: float = radii[ri][0]
		var rx: float = radii[ri][1]
		var rz: float = radii[ri][2] * flat_z
		var center := p0 + axis * t
		var col: Color = color_fn.call(t)
		var bw: Array = weight_fn.call(t)
		for si in segs:
			var a := float(si) / segs * TAU
			var off := u * cos(a) * rx + w * sin(a) * rz
			var nrm := u * cos(a) / maxf(rx, 0.001) + w * sin(a) / maxf(rz, 0.001)
			_add_vert(center + off, nrm, col, bw[0], bw[1])
	for ri in rings - 1:
		for si in segs:
			var a0 := base + ri * segs + si
			var a1 := base + ri * segs + (si + 1) % segs
			var b0 := a0 + segs
			var b1 := a1 + segs
			_idx.append_array([a0, b0, a1, a1, b0, b1])
	# kapaklar
	for end: int in [0, rings - 1]:
		var t: float = radii[end][0]
		var center := p0 + axis * t
		var ci := _add_vert(center, d * (1.0 if end > 0 else -1.0), color_fn.call(t), weight_fn.call(t)[0], weight_fn.call(t)[1])
		for si in segs:
			var a0 := base + end * segs + si
			var a1 := base + end * segs + (si + 1) % segs
			if end == 0:
				_idx.append_array([ci, a1, a0])
			else:
				_idx.append_array([ci, a0, a1])

func _ellipsoid(c: Vector3, r: Vector3, col_fn: Callable, bone: int, rings := 10, segs := 14, y_min := -2.0) -> void:
	var base := _v.size()
	for ri in rings + 1:
		var th := float(ri) / rings * PI
		for si in segs + 1:
			var ph := float(si) / segs * TAU
			var n := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var p := c + Vector3(n.x * r.x, n.y * r.y, n.z * r.z)
			_add_vert(p, Vector3(n.x / r.x, n.y / r.y, n.z / r.z), col_fn.call(n), [bone], [1.0])
	for ri in rings:
		for si in segs:
			var a0 := base + ri * (segs + 1) + si
			var a1 := a0 + 1
			var b0 := a0 + segs + 1
			var b1 := b0 + 1
			var ny := cos((float(ri) + 0.5) / rings * PI)
			if ny < y_min:
				continue
			_idx.append_array([a0, b0, a1, a1, b0, b1])

func _build_mesh(shirt: Color, shorts: Color, socks: Color, skin: Color, hair: Color, style: int) -> ArrayMesh:
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_c = PackedColorArray()
	_bo = PackedInt32Array()
	_we = PackedFloat32Array()
	_idx = PackedInt32Array()
	var boot := Color(0.07, 0.07, 0.08)
	var g := gpos
	# gövde (pelvis -> omuz)
	var torso_p0 := Vector3(0, 0.82, 0)
	var torso_p1 := Vector3(0, 1.5, 0)
	var prof := [[0.0, 0.15, 0.1], [0.12, 0.172, 0.115], [0.24, 0.165, 0.11], [0.36, 0.148, 0.1], [0.5, 0.155, 0.105],
		[0.66, 0.178, 0.12], [0.8, 0.188, 0.116], [0.88, 0.178, 0.105], [0.95, 0.15, 0.09], [1.0, 0.075, 0.065]]
	_tube(torso_p0, torso_p1, prof,
		func(t: float): return shorts if t < 0.25 else shirt,
		func(t: float):
			var y := 0.82 + 0.68 * t
			if y < 0.98:
				return [[B.HIPS], [1.0]]
			if y < 1.1:
				var k := (y - 0.98) / 0.12
				return [[B.HIPS, B.SPINE], [1.0 - k, k]]
			if y < 1.24:
				var k := (y - 1.1) / 0.14
				return [[B.SPINE, B.CHEST], [1.0 - k, k]]
			return [[B.CHEST], [1.0]], 14)
	# boyun
	_tube(Vector3(0, 1.44, -0.005), Vector3(0, 1.6, 0.01), [[0.0, 0.07, 0.065], [0.5, 0.058, 0.056], [1.0, 0.055, 0.055]],
		func(t: float): return skin,
		func(t: float): return [[B.CHEST, B.NECK], [0.5, 0.5]] if t < 0.3 else [[B.NECK], [1.0]], 10)
	# baş
	var hc := Vector3(0, 1.665, 0.012)
	_ellipsoid(hc, Vector3(0.088, 0.112, 0.1), func(n: Vector3): return skin, B.HEAD)
	# çene
	_ellipsoid(hc + Vector3(0, -0.06, 0.03), Vector3(0.06, 0.05, 0.06), func(n: Vector3): return skin.darkened(0.03), B.HEAD, 6, 10)
	# burun
	_ellipsoid(hc + Vector3(0, -0.01, 0.098), Vector3(0.016, 0.026, 0.02), func(n: Vector3): return skin.darkened(0.05), B.HEAD, 5, 8)
	# kulaklar
	for sx in [-1.0, 1.0]:
		_ellipsoid(hc + Vector3(0.088 * sx, 0.0, -0.005), Vector3(0.014, 0.03, 0.022), func(n: Vector3): return skin.darkened(0.08), B.HEAD, 5, 8)
	# gözler ve kaşlar
	for sx in [-1.0, 1.0]:
		_ellipsoid(hc + Vector3(0.033 * sx, 0.022, 0.088), Vector3(0.013, 0.008, 0.006), func(n: Vector3): return Color(0.95, 0.95, 0.95), B.HEAD, 4, 6)
		_ellipsoid(hc + Vector3(0.033 * sx, 0.022, 0.093), Vector3(0.006, 0.007, 0.003), func(n: Vector3): return Color(0.08, 0.05, 0.03), B.HEAD, 4, 6)
		_ellipsoid(hc + Vector3(0.034 * sx, 0.045, 0.09), Vector3(0.02, 0.005, 0.006), func(n: Vector3): return hair.darkened(0.1), B.HEAD, 3, 6)
	# ağız
	_ellipsoid(hc + Vector3(0, -0.045, 0.085), Vector3(0.022, 0.004, 0.005), func(n: Vector3): return skin.darkened(0.3), B.HEAD, 3, 6)
	# saç
	match style:
		0:
			_ellipsoid(hc + Vector3(0, 0.03, -0.012), Vector3(0.093, 0.1, 0.104), func(n: Vector3): return hair, B.HEAD, 10, 14, 0.2)
		1:
			_ellipsoid(hc + Vector3(0, 0.03, -0.01), Vector3(0.1, 0.11, 0.112), func(n: Vector3): return hair, B.HEAD, 10, 14, 0.0)
		2:
			_ellipsoid(hc + Vector3(0, 0.015, -0.004), Vector3(0.091, 0.103, 0.103), func(n: Vector3): return hair.lerp(skin, 0.35), B.HEAD, 10, 14, 0.35)
		_:
			_ellipsoid(hc + Vector3(0, 0.02, -0.02), Vector3(0.106, 0.118, 0.115), func(n: Vector3): return hair, B.HEAD, 10, 14, -0.25)
	# kollar
	for sx in [1.0, -1.0]:
		var sh: int = B.SH_L if sx > 0 else B.SH_R
		var el: int = B.EL_L if sx > 0 else B.EL_R
		var ha: int = B.HA_L if sx > 0 else B.HA_R
		var ps: Vector3 = g[sh]
		var pe: Vector3 = g[el]
		var ph: Vector3 = g[ha]
		_ellipsoid(ps + Vector3(-0.01 * sx, 0.005, 0), Vector3(0.06, 0.055, 0.058), func(n: Vector3): return shirt, sh, 6, 10)
		_tube(ps, pe, [[0.0, 0.056, 0.054], [0.4, 0.05, 0.048], [0.55, 0.046, 0.044], [1.0, 0.04, 0.038]],
			func(t: float): return shirt if t < 0.5 else skin,
			func(t: float): return [[sh, el], [1.0 - maxf(0.0, (t - 0.8) / 0.2) * 0.5, maxf(0.0, (t - 0.8) / 0.2) * 0.5]], 10)
		_tube(pe, ph, [[0.0, 0.04, 0.038], [0.4, 0.036, 0.032], [1.0, 0.028, 0.024]],
			func(t: float): return skin,
			func(t: float): return [[el, sh], [1.0 - maxf(0.0, (0.2 - t) / 0.2) * 0.5, maxf(0.0, (0.2 - t) / 0.2) * 0.5]], 10)
		_ellipsoid(ph + Vector3(0, -0.045, 0.005), Vector3(0.026, 0.05, 0.034), func(n: Vector3): return skin, ha, 5, 8)
	# bacaklar
	for sx in [1.0, -1.0]:
		var hp: int = B.HIP_L if sx > 0 else B.HIP_R
		var kn: int = B.KN_L if sx > 0 else B.KN_R
		var an: int = B.AN_L if sx > 0 else B.AN_R
		var p_h: Vector3 = g[hp]
		var p_k: Vector3 = g[kn]
		var p_a: Vector3 = g[an]
		_tube(p_h + Vector3(0, 0.04, 0), p_k, [[0.0, 0.088, 0.09], [0.3, 0.082, 0.082], [0.38, 0.075, 0.075], [0.7, 0.06, 0.062], [1.0, 0.05, 0.052]],
			func(t: float): return shorts if t < 0.36 else skin,
			func(t: float):
				if t < 0.12:
					return [[hp, B.HIPS], [0.6 + t * 3.3, 0.4 - t * 3.3]]
				var k := maxf(0.0, (t - 0.85) / 0.15) * 0.5
				return [[hp, kn], [1.0 - k, k]], 12)
		_tube(p_k, p_a, [[0.0, 0.05, 0.052], [0.15, 0.052, 0.056], [0.35, 0.048, 0.055], [0.75, 0.034, 0.036], [1.0, 0.03, 0.03]],
			func(t: float): return skin if t < 0.12 else socks,
			func(t: float):
				var k := maxf(0.0, (0.15 - t) / 0.15) * 0.5
				return [[kn, hp], [1.0 - k, k]], 12)
		# krampon
		_tube(p_a + Vector3(0, -0.035, -0.06), p_a + Vector3(0, -0.04, 0.17), [[0.0, 0.042, 0.035], [0.3, 0.05, 0.04], [0.8, 0.044, 0.03], [1.0, 0.03, 0.02]],
			func(t: float): return boot,
			func(t: float): return [[an], [1.0]], 10)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_BONES] = _bo
	arr[Mesh.ARRAY_WEIGHTS] = _we
	arr[Mesh.ARRAY_INDEX] = _idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

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
	var cad := 1.7 + spd * 0.5
	phase += delta * cad * PI * anim_speed
	if action != "":
		action_t += delta * anim_speed
		if action_t >= action_dur:
			action = ""
	apply_pose()

func _rot(b: int, x: float, y := 0.0, z := 0.0) -> void:
	skel.set_bone_pose_rotation(b, Quaternion.from_euler(Vector3(x, y, z)))

func _hips_pos(off: Vector3) -> void:
	skel.set_bone_pose_position(B.HIPS, REST[B.HIPS] + off)

func apply_pose() -> void:
	if skel == null:
		return
	var run := clampf(speed / 7.0, 0.0, 1.0)
	var s := sin(phase)
	var c := cos(phase)
	var thigh := s * (0.12 + 0.75 * run)
	var lean := 0.03 + 0.18 * run
	var breathe := sin(Time.get_ticks_msec() / 800.0 + phase) * 0.015 * (1.0 - run)
	# not: kemik -Y'ye sarkar; X ekseninde negatif = öne
	var hl := Vector3(-thigh - 0.05 * run, 0, 0.03)
	var hr := Vector3(thigh - 0.05 * run, 0, -0.03)
	var kl := maxf(0.0, c) * (0.2 + 1.3 * run) + 0.06
	var kr := maxf(0.0, -c) * (0.2 + 1.3 * run) + 0.06
	var al := thigh * 0.9
	var ar := -thigh * 0.9
	var el := -0.3 - 1.0 * run
	var sp := Vector3(lean * 0.5 + breathe, s * 0.1 * run, 0)
	var ch := Vector3(lean * 0.5, s * 0.08 * run, 0)
	var nk := Vector3(-lean * 0.6, 0, 0)
	var hips_off := Vector3(0, absf(sin(phase)) * 0.045 * run - 0.02 * run, 0)
	var hips_rot := Vector3(0, -s * 0.12 * run, 0)
	var sh_z := 0.1
	rotation.z = 0.0
	if action != "":
		var f := clampf(action_t / maxf(0.001, action_dur), 0.0, 1.0)
		match action:
			"kick":
				var sw := lerpf(0.0, 0.9, f / 0.4) if f < 0.4 else lerpf(0.9, -1.45, minf(1.0, (f - 0.4) / 0.3))
				hr = Vector3(sw, 0, -0.05)
				kr = 1.35 if f < 0.45 else lerpf(1.35, 0.05, minf(1.0, (f - 0.45) / 0.2))
				hl = Vector3(-0.12, 0, 0.05)
				kl = 0.35
				sp = Vector3(-0.1, 0.25 * sin(f * PI), 0)
				al = -0.35
				ar = 0.35
				sh_z = 0.6
			"header":
				var j := sin(f * PI)
				hips_off = Vector3(0, j * 0.5, 0)
				kl = 0.9 * j + 0.1
				kr = 0.6 * j + 0.1
				hl = Vector3(-0.4 * j, 0, 0.05)
				hr = Vector3(-0.1, 0, -0.05)
				al = -1.3 * j
				ar = -1.3 * j
				sh_z = 0.5 * j + 0.1
				nk = Vector3(0.5 if f > 0.45 and f < 0.65 else -0.25, 0, 0)
				sp = Vector3(-0.15 + (0.45 if f > 0.45 and f < 0.7 else 0.0), 0, 0)
			"dive":
				var e := minf(1.0, f / 0.35)
				rotation.z = -action_side * 1.3 * e
				hips_off = Vector3(action_side * 1.25 * e, sin(e * PI * 0.5) * 0.3 - e * 0.35, 0)
				al = -2.9
				ar = -2.9
				el = -0.1
				hl = Vector3(-0.2, 0, 0.1)
				hr = Vector3(0.3, 0, -0.1)
			"slide":
				var e := minf(1.0, f / 0.25)
				var k := e * (1.0 - maxf(0.0, (f - 0.7) / 0.3))
				hips_off = Vector3(0, -0.68 * k, 0.75 * k)
				sp = Vector3(-0.95 * k, 0, 0)
				hr = Vector3(-1.4 * k, 0, 0)
				kr = 0.05
				hl = Vector3(-0.5 * k, 0, 0)
				kl = 1.6 * k
				al = 0.6 * k
				ar = 0.6 * k
				sh_z = 0.9 * k
			"tackle":
				var k := sin(f * PI)
				hr = Vector3(-1.05 * k, 0, 0)
				kr = 0.2
				sp = Vector3(0.35 * k, 0, 0)
				hips_off = Vector3(0, -0.14 * k, 0)
			"celebrate":
				var hop := absf(sin(f * PI * 4.0))
				hips_off = Vector3(0, hop * 0.16, 0)
				al = -2.8
				ar = -2.8
				el = -0.2
				sh_z = 0.35
				sp = Vector3(-0.22, 0, 0)
				nk = Vector3(-0.35, 0, 0)
			"knee_slide":
				var k := minf(1.0, f / 0.2)
				hips_off = Vector3(0, -0.5 * k, 0)
				hl = Vector3(-1.4 * k, 0, 0)
				kl = 1.5 * k
				hr = Vector3(0.3 * k, 0, 0)
				kr = 1.9 * k
				sp = Vector3(-0.45 * k, 0, 0)
				al = -1.6
				ar = -1.6
				sh_z = 1.2
				nk = Vector3(-0.55, 0, 0)
			"wave":
				ar = -2.6
				el = -0.4
	_hips_pos(hips_off)
	_rot(B.HIPS, hips_rot.x, hips_rot.y, hips_rot.z)
	_rot(B.SPINE, sp.x, sp.y, sp.z)
	_rot(B.CHEST, ch.x, ch.y, ch.z)
	_rot(B.NECK, nk.x * 0.5, 0, 0)
	_rot(B.HEAD, nk.x * 0.5, 0, 0)
	_rot(B.HIP_L, hl.x, hl.y, hl.z)
	_rot(B.HIP_R, hr.x, hr.y, hr.z)
	_rot(B.KN_L, kl)
	_rot(B.KN_R, kr)
	_rot(B.AN_L, -kl * 0.3)
	_rot(B.AN_R, -kr * 0.3)
	_rot(B.SH_L, al, 0, sh_z)
	_rot(B.SH_R, ar, 0, -sh_z)
	_rot(B.EL_L, el)
	_rot(B.EL_R, el)

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
