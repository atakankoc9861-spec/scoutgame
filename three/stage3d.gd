extends Control
## Diyalog/aksiyon sahneleri için 3D sahne: kafe, lobi, başkan odası, telefon (bölünmüş ekran),
## antrenman sahası ve video odası. Mocap karakterler, kamera kesmeleri, kıvılcım anları.

const MM = preload("res://three/mocap_man.gd")

signal spark_shown(idx: int)
signal spark_caught(idx: int)
signal spark_missed(idx: int)

var set_name := ""
var views: Array = []          # [{sv, cam, cont}]
var world: Node3D
var actors := {}              # id -> mocap man
var cam_target := {}          # vp idx -> {pos, look}
var cam_cur := {}
var cut_t := 0.0
var t := 0.0
var speaking := ""
var talk_t := 0.0
var shadows := true

# antrenman
var drill_on := false
var drill_actor := ""
var drill := {}
var ball: MeshInstance3D
var ball_vel := Vector3.ZERO
var ball_free := false
var cones: Array = []
var goal_pos := Vector3.ZERO
var mates: Array = []
var spark_times: Array = []
var spark_idx := 0
var spark_live := -1.0
var spark_ring: MeshInstance3D
var sparks_caught := 0
var follow := true

func setup(name: String, split := false) -> void:
	set_name = name
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadows = Game.quality() == "high"
	world = Node3D.new()
	var n := 2 if split else 1
	var w3 := World3D.new()
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 4)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)
	for i in n:
		var cont := SubViewportContainer.new()
		cont.stretch = true
		cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(cont)
		var sv := SubViewport.new()
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.msaa_3d = Viewport.MSAA_2X if shadows and not Game.settings.get("safe3d", false) else Viewport.MSAA_DISABLED
		sv.world_3d = w3
		cont.add_child(sv)
		var cam := Camera3D.new()
		cam.fov = 48
		sv.add_child(cam)
		views.append({"sv": sv, "cam": cam, "cont": cont})
	views[0].sv.add_child(world)
	Watch.check_vp(views[0].sv, "sahne " + name)
	_build(name)

func _process(delta: float) -> void:
	t += delta
	# kameralar yumuşak takip
	for i in views.size():
		if not cam_target.has(i):
			continue
		var tg: Dictionary = cam_target[i]
		if not cam_cur.has(i):
			cam_cur[i] = tg.duplicate()
		var c: Dictionary = cam_cur[i]
		var k := minf(1.0, delta * float(tg.get("speed", 3.0)))
		c.pos = (c.pos as Vector3).lerp(tg.pos, k)
		c.look = (c.look as Vector3).lerp(tg.look, k)
		var cam: Camera3D = views[i].cam
		# hafif el kamerası salınımı
		var sway := Vector3(sin(t * 0.7 + i) * 0.015, sin(t * 0.9 + i * 2.0) * 0.01, 0.0)
		cam.position = c.pos + sway
		if cam.position.distance_to(c.look) > 0.01:
			cam.look_at(c.look)
	for id in actors:
		var a = actors[id]
		if not a.get_meta("move", false):
			a.tick(delta, 0.0)
		_props(a)
	# konuşan karakter
	if speaking != "" and actors.has(speaking):
		talk_t += delta
	if drill_on:
		_drill_tick(delta)
	for m in mates:
		_mate_tick(m, delta)
	if ball_free:
		_ball_tick(delta)

# ================================================================ yardımcılar

func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _box(sz: Vector3, pos: Vector3, c: Color, rough := 0.8, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(c, rough)
	(parent if parent else world).add_child(mi)
	return mi

func _cyl(r: float, h: float, pos: Vector3, c: Color, r2 := -1.0, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if r2 < 0 else r2
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 20
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(c)
	(parent if parent else world).add_child(mi)
	return mi

func _sphere(r: float, pos: Vector3, c: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(c, 0.6)
	(parent if parent else world).add_child(mi)
	return mi

func _glow_quad(sz: Vector2, pos: Vector3, rot_y: float, c: Color, energy := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	mi.position = pos
	mi.rotation.y = rot_y
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * energy
	mi.material_override = m
	world.add_child(mi)
	return mi

func _env(bg: Color, amb: Color, amb_e := 0.6, sky := false) -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	if sky:
		e.background_mode = Environment.BG_SKY
		var s := Sky.new()
		var pm := ProceduralSkyMaterial.new()
		pm.sky_top_color = Color("#5d8fc9")
		pm.sky_horizon_color = Color("#c9dbe8")
		pm.ground_horizon_color = Color("#9fb3a0")
		pm.ground_bottom_color = Color("#4b5e48")
		s.sky_material = pm
		e.sky = s
		e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		e.background_mode = Environment.BG_COLOR
		e.background_color = bg
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = amb
	e.ambient_light_energy = amb_e
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	we.environment = e
	world.add_child(we)

func _sun(rot: Vector3, c: Color, e: float, shadow := true) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot
	l.light_color = c
	l.light_energy = e
	l.shadow_enabled = shadow and shadows
	l.directional_shadow_max_distance = 25.0
	world.add_child(l)
	return l

func _lamp(pos: Vector3, c: Color, e: float, rng := 4.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = c
	l.light_energy = e
	l.omni_range = rng
	world.add_child(l)
	return l

func _chair(pos: Vector3, face: float, c: Color, arm := false) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = face
	world.add_child(n)
	_box(Vector3(0.5, 0.08, 0.48), Vector3(0, 0.43, 0), c, 0.7, n)
	_box(Vector3(0.5, 0.6, 0.07), Vector3(0, 0.75, -0.24), c, 0.7, n)
	if arm:
		_box(Vector3(0.08, 0.25, 0.46), Vector3(0.27, 0.55, 0), c.darkened(0.1), 0.7, n)
		_box(Vector3(0.08, 0.25, 0.46), Vector3(-0.27, 0.55, 0), c.darkened(0.1), 0.7, n)
		_box(Vector3(0.62, 0.4, 0.5), Vector3(0, 0.2, 0), c.darkened(0.15), 0.7, n)
	else:
		for sx in [-0.21, 0.21]:
			for sz in [-0.2, 0.2]:
				_box(Vector3(0.04, 0.42, 0.04), Vector3(sx, 0.21, sz), c.darkened(0.3), 0.7, n)

## Oyuncu/NPC ekle. info: {kind: "player"|"npc", p: oyuncu sözlüğü, club, top, pants, shoes, skin, hair, seed}
func add_actor(id: String, info: Dictionary, pos: Vector3, face: float, base := "idle") -> Node3D:
	var m = MM.new()
	world.add_child(m)
	if info.get("kind", "npc") == "player":
		var p: Dictionary = info.p
		var cl: Dictionary = info.get("club", {})
		var c1 := Color(cl.get("c1", "#cccccc"))
		var c2 := Color(cl.get("c2", "#333333"))
		if info.get("training", false):
			# antrenman kıyafeti: forma rengi üst, koyu şort
			m.build(MM.kit_mats(c1, c2.darkened(0.3), c1), int(p.get("skin", 1)), int(p.get("hair", 0)), int(p.get("seed", 0)), int(p.get("seed", 0)) % 30 + 1)
		elif info.get("casual", false):
			m.build_outfit(info.get("top", Color("#2b3a55")), Color("#2d3440"), Color("#1c1c20"), int(p.get("skin", 1)), int(p.get("hair", 0)), int(p.get("seed", 0)), false)
		else:
			m.build(MM.kit_mats(c1, c2, c1), int(p.get("skin", 1)), int(p.get("hair", 0)), int(p.get("seed", 0)), int(p.get("seed", 0)) % 30 + 1)
	else:
		m.build_outfit(info.get("top", Color("#3b3f47")), info.get("pants", Color("#22262e")), info.get("shoes", Color("#1a1410")), int(info.get("skin", 1)), int(info.get("hair", 0)), int(info.get("seed", 3)), info.get("sleeves", true))
	m.position = pos
	m.rotation.y = face
	m.set_base(base)
	actors[id] = m
	return m

## eldeki eşyalar: not defteri ve kalem, telefon
func _props(a) -> void:
	var ov: String = a.overlay
	if ov != "notebook" and ov != "phone":
		return
	var sk: Skeleton3D = a.skel
	var hl := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_l"))).origin
	var hr := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_r"))).origin
	var head := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin
	if not a.has_meta("prop"):
		var pr := Node3D.new()
		world.add_child(pr)
		if ov == "notebook":
			_box(Vector3(0.16, 0.012, 0.22), Vector3.ZERO, Color("#c9a55a"), 0.8, pr)
			_box(Vector3(0.15, 0.014, 0.205), Vector3(0, 0.002, 0), Color("#f4efe2"), 0.9, pr)
			var pen := _cyl(0.006, 0.14, Vector3.ZERO, Color("#1b3d8a"), -1.0, pr)
			pen.name = "Pen"
		else:
			_box(Vector3(0.035, 0.14, 0.07), Vector3.ZERO, Color("#151515"), 0.3, pr)
		a.set_meta("prop", pr)
	var pr2: Node3D = a.get_meta("prop")
	if ov == "notebook":
		var mid := hl.lerp(hr, 0.35) + Vector3(0, 0.02, 0)
		var to_head := (head - mid).normalized()
		var right := (hr - hl).normalized()
		var up := to_head.lerp(Vector3.UP, 0.4).normalized()
		var fwd := right.cross(up).normalized()
		pr2.global_transform = Transform3D(Basis(right, up, fwd).orthonormalized(), mid)
		var pen: Node3D = pr2.get_node("Pen")
		pen.global_position = hr + Vector3(0, 0.03, 0)
		pen.rotation = Vector3(0.6, 0, 0.4)
	else:
		var dir := (head - hr).normalized()
		pr2.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), hr + dir * 0.06)

func head_pos(id: String) -> Vector3:
	if not actors.has(id):
		return Vector3.ZERO
	var m = actors[id]
	var sk: Skeleton3D = m.skel
	var hi := sk.find_bone("Head")
	return (sk.global_transform * sk.get_bone_global_pose(hi)).origin + Vector3(0, 0.12, 0)

## 3D baş konumunun ekran koordinatı (bu Control'e göre)
func head_screen(id: String, vp := 0) -> Vector2:
	if views.is_empty():
		return Vector2.ZERO
	var v: Dictionary = views[mini(vp, views.size() - 1)]
	var cam: Camera3D = v.cam
	var hp := head_pos(id)
	if cam.is_position_behind(hp):
		return Vector2(-1, -1)
	var sp := cam.unproject_position(hp)
	var cont: Control = v.cont
	var svs: Vector2 = Vector2((v.sv as SubViewport).size)
	var scale_f := cont.size / svs if svs.x > 0 else Vector2.ONE
	return cont.position + sp * scale_f

func shot(vp: int, pos: Vector3, look: Vector3, speed := 3.0, cut := false) -> void:
	cam_target[vp] = {"pos": pos, "look": look, "speed": speed}
	if cut:
		cam_cur[vp] = {"pos": pos, "look": look}

## konuşana kes: dinleyenin omzunun üstünden
func focus_speaker(id: String, listener: String, vp := 0) -> void:
	speaking = id
	talk_t = 0.0
	for k in actors:
		var a = actors[k]
		if a.get_meta("seated", false):
			a.set_base("sit_talk" if k == id else "sit")
		elif not a.get_meta("move", false) and a.get_meta("talker", true):
			a.set_base("talk" if k == id else "idle")
	if actors.has(listener) and actors.has(id):
		var sp := head_pos(id)
		var lp := head_pos(listener)
		var d := (sp - lp)
		d.y = 0.0
		d = d.normalized()
		var side := d.cross(Vector3.UP).normalized()
		var cpos := lp - d * 0.75 + side * 0.42 + Vector3(0, 0.12, 0)
		shot(vp, cpos, sp - Vector3(0, 0.12, 0) + side * 0.12, 6.0, true)
		# dinleyen konuşana baksın, ara ara başını sallasın
		actors[listener].head_yaw = 0.0
	elif actors.has(id):
		var sp2 := head_pos(id)
		var a2 = actors[id]
		var fwd := Vector3(sin(a2.rotation.y), 0, cos(a2.rotation.y))
		shot(vp, sp2 + fwd * 1.15 + fwd.cross(Vector3.UP) * 0.3, sp2 - Vector3(0, 0.08, 0), 6.0, true)

func listener_react(id: String, good: bool) -> void:
	if not actors.has(id):
		return
	if good:
		actors[id].nod()
	else:
		actors[id].head_yaw = 0.35
		get_tree().create_timer(0.7).timeout.connect(func():
			if actors.has(id):
				actors[id].head_yaw = 0.0)

func wide(vp := 0) -> void:
	if cam_target.has("wide%d" % vp):
		var w: Dictionary = cam_target["wide%d" % vp]
		shot(vp, w.pos, w.look, 2.5, true)

# ================================================================ setler

func _build(name: String) -> void:
	match name:
		"cafe": _set_cafe()
		"lobby": _set_lobby()
		"office": _set_office()
		"phone": _set_phone()
		"training", "video": _set_training()

func _set_cafe() -> void:
	_env(Color("#1b120c"), Color("#7a5a40"), 0.55)
	_box(Vector3(10, 0.1, 8), Vector3(0, -0.05, 0), Color("#4a3020"), 0.6)
	_box(Vector3(10, 4, 0.2), Vector3(0, 2, -2.6), Color("#cdb48f"))
	_box(Vector3(0.2, 4, 8), Vector3(-3.4, 2, 0), Color("#b89c76"))
	_box(Vector3(10, 1.0, 0.25), Vector3(0, 0.5, -2.45), Color("#5e3b24"))
	# pencere
	_glow_quad(Vector2(3.4, 1.7), Vector3(0.6, 1.95, -2.48), 0.0, Color("#dfe9f2"), 1.3)
	for x in [-1.1, 0.0, 1.1, 2.3]:
		_box(Vector3(0.06, 1.75, 0.08), Vector3(x + 0.0, 1.95, -2.44), Color("#3a2416"))
	_box(Vector3(3.5, 0.08, 0.1), Vector3(0.6, 1.95, -2.44), Color("#3a2416"))
	# tezgâh ve şişeler
	_box(Vector3(2.2, 1.05, 0.6), Vector3(-2.2, 0.52, -1.6), Color("#6b4428"), 0.5)
	_box(Vector3(2.2, 0.06, 0.66), Vector3(-2.2, 1.07, -1.6), Color("#2a1a10"), 0.3)
	var cols := [Color("#7d1d1d"), Color("#1d5c3a"), Color("#c49a2c"), Color("#2e4d7d"), Color("#a8c8d0")]
	for i in 9:
		_cyl(0.035, 0.26, Vector3(-3.1 + i * 0.2, 1.23, -2.3), cols[i % cols.size()])
	_box(Vector3(2.4, 0.04, 0.25), Vector3(-2.2, 1.1, -2.35), Color("#3a2416"))
	# masa
	_cyl(0.48, 0.04, Vector3(0, 0.74, 0), Color("#2b1b10"), -1.0)
	_cyl(0.05, 0.72, Vector3(0, 0.36, 0), Color("#1a1a1a"))
	_cyl(0.25, 0.03, Vector3(0, 0.015, 0), Color("#1a1a1a"))
	_cyl(0.045, 0.08, Vector3(-0.18, 0.8, 0.08), Color("#f2efe6"))
	_cyl(0.045, 0.08, Vector3(0.2, 0.8, -0.06), Color("#f2efe6"))
	_cyl(0.07, 0.01, Vector3(0.2, 0.765, -0.06), Color("#e8e2d4"))
	_box(Vector3(0.16, 0.012, 0.22), Vector3(-0.05, 0.765, 0.18), Color("#e9dfc6"))
	# lambalar
	for lx in [-1.6, 0.0, 1.6]:
		_cyl(0.18, 0.16, Vector3(lx, 2.55, 0.0), Color("#2a2a2a"), 0.06)
		_sphere(0.06, Vector3(lx, 2.45, 0.0), Color("#fff2c8"))
		_lamp(Vector3(lx, 2.35, 0.0), Color("#ffcf8a"), 1.6, 4.0)
	_sun(Vector3(-35, -150, 0), Color("#dfe9ff"), 0.6)
	# arka masalar
	for bx in [2.6, -1.0]:
		_cyl(0.42, 0.04, Vector3(bx, 0.74, -1.5), Color("#2b1b10"))
		_cyl(0.05, 0.72, Vector3(bx, 0.36, -1.5), Color("#1a1a1a"))
	_chair(Vector3(-0.98, 0, 0.0), PI / 2.0, Color("#5a3a22"))
	_chair(Vector3(0.98, 0, 0.0), -PI / 2.0, Color("#5a3a22"))
	cam_target["wide0"] = {"pos": Vector3(0.2, 1.5, 2.7), "look": Vector3(0, 0.95, -0.2)}

func _set_lobby() -> void:
	_env(Color("#140f0c"), Color("#806650"), 0.55)
	_box(Vector3(12, 0.1, 10), Vector3(0, -0.05, 0), Color("#5c2424"), 0.9)
	_box(Vector3(12, 4.5, 0.2), Vector3(0, 2.25, -3.0), Color("#e6d8bd"))
	_box(Vector3(12, 1.1, 0.24), Vector3(0, 0.55, -2.88), Color("#4a2c1a"), 0.5)
	_glow_quad(Vector2(2.2, 2.6), Vector3(-2.3, 2.1, -2.88), 0.0, Color("#e8eef5"), 1.25)
	_glow_quad(Vector2(2.2, 2.6), Vector3(2.3, 2.1, -2.88), 0.0, Color("#e8eef5"), 1.25)
	# halı, sehpa, saksı, lamba
	_box(Vector3(3.2, 0.02, 2.4), Vector3(0, 0.01, 0), Color("#8a6a3a"), 1.0)
	_box(Vector3(0.9, 0.06, 0.55), Vector3(0, 0.42, 0), Color("#2a1a10"), 0.3)
	_box(Vector3(0.06, 0.4, 0.06), Vector3(0, 0.2, 0), Color("#d4af37"), 0.3)
	_cyl(0.2, 0.45, Vector3(-1.9, 0.22, -2.2), Color("#3a2a20"), 0.16)
	_sphere(0.5, Vector3(-1.9, 1.0, -2.2), Color("#2e5a2e"))
	_sphere(0.35, Vector3(-1.75, 1.4, -2.1), Color("#386b36"))
	_cyl(0.02, 1.5, Vector3(1.9, 0.75, -2.3), Color("#c8a040"))
	_cyl(0.22, 0.3, Vector3(1.9, 1.6, -2.3), Color("#f5e6c0"), 0.14)
	_lamp(Vector3(1.9, 1.55, -2.1), Color("#ffd9a0"), 1.4, 4.0)
	_lamp(Vector3(0, 3.2, 0.5), Color("#ffe8c8"), 1.1, 6.0)
	_sun(Vector3(-40, -160, 0), Color("#f0f4ff"), 0.55)
	_chair(Vector3(-1.0, 0, 0.0), PI / 2.0, Color("#6b3a22"), true)
	_chair(Vector3(1.0, 0, 0.0), -PI / 2.0, Color("#6b3a22"), true)
	cam_target["wide0"] = {"pos": Vector3(0.2, 1.75, 3.7), "look": Vector3(0, 0.85, -0.2)}

func _set_office() -> void:
	_env(Color("#120d09"), Color("#6e5642"), 0.5)
	_box(Vector3(10, 0.1, 9), Vector3(0, -0.05, 0), Color("#3b2416"), 0.5)
	_box(Vector3(10, 4.2, 0.2), Vector3(0, 2.1, -2.4), Color("#5a3a24"), 0.6)
	# kitaplık
	for row in 4:
		_box(Vector3(3.0, 0.04, 0.35), Vector3(-2.4, 0.5 + row * 0.5, -2.2), Color("#2a1a10"))
		for b in 14:
			var bc: Color = [Color("#7d1d1d"), Color("#1d3c5c"), Color("#c49a2c"), Color("#2e5a3a"), Color("#d8cbb0")][(b * 3 + row) % 5]
			_box(Vector3(0.16, 0.38, 0.26), Vector3(-3.7 + b * 0.19, 0.71 + row * 0.5, -2.2), bc)
	# kulüp bayrağı
	var cl := Game.my_club()
	var c1 := Color(cl.get("c1", "#b5121b"))
	var c2 := Color(cl.get("c2", "#ffffff"))
	_box(Vector3(1.2, 0.7, 0.02), Vector3(1.4, 2.2, -2.28), c1, 0.9)
	_box(Vector3(1.2, 0.23, 0.025), Vector3(1.4, 2.2, -2.27), c2, 0.9)
	# kupa
	_cyl(0.12, 0.08, Vector3(2.6, 1.09, -2.0), Color("#d4af37"), -1.0)
	_cyl(0.04, 0.2, Vector3(2.6, 1.23, -2.0), Color("#d4af37"))
	_cyl(0.07, 0.18, Vector3(2.6, 1.42, -2.0), Color("#e8c547"), 0.13)
	_box(Vector3(0.8, 1.05, 0.5), Vector3(2.6, 0.52, -2.0), Color("#2a1a10"))
	# masa
	_box(Vector3(0.95, 0.07, 1.9), Vector3(0.5, 0.76, 0), Color("#4a2a16"), 0.35)
	_box(Vector3(0.06, 0.72, 1.85), Vector3(0.05, 0.38, 0), Color("#3a2010"), 0.5)
	_box(Vector3(0.22, 0.02, 0.3), Vector3(0.35, 0.8, -0.3), Color("#f0e8d8"))
	_box(Vector3(0.22, 0.02, 0.3), Vector3(0.37, 0.81, -0.27), Color("#e8dcc0"))
	_cyl(0.03, 0.12, Vector3(0.75, 0.86, 0.55), Color("#1a1a1a"))
	_cyl(0.1, 0.02, Vector3(0.7, 0.8, -0.6), Color("#d4af37"))
	_lamp(Vector3(0.3, 2.6, 0.6), Color("#ffd9a0"), 1.6, 5.0)
	_glow_quad(Vector2(1.6, 2.0), Vector3(-0.3, 2.1, -2.28), 0.0, Color("#cfdcea"), 0.9)
	_sun(Vector3(-40, 30, 0), Color("#ffe8c8"), 0.5)
	_chair(Vector3(1.75, 0, 0.0), -PI / 2.0, Color("#2a1810"), true)
	_chair(Vector3(-0.85, 0, 0.0), PI / 2.0, Color("#5a3a22"))
	cam_target["wide0"] = {"pos": Vector3(0.4, 1.6, 2.9), "look": Vector3(0.4, 1.0, -0.3)}

func _set_phone() -> void:
	# sol (0): scout ofiste; sağ (1): arayan kişinin yeri (x=40)
	_env(Color("#141414"), Color("#6a6a70"), 0.6, true)
	_box(Vector3(6, 0.1, 6), Vector3(0, -0.05, 0), Color("#3b2a1e"), 0.6)
	_box(Vector3(6, 3.5, 0.2), Vector3(0, 1.75, -1.8), Color("#a89880"))
	_box(Vector3(1.4, 0.06, 0.7), Vector3(0, 0.75, -0.6), Color("#4a2a16"), 0.35)
	_box(Vector3(1.35, 0.7, 0.05), Vector3(0, 0.37, -0.92), Color("#3a2010"))
	_box(Vector3(0.5, 0.32, 0.03), Vector3(-0.3, 1.0, -0.85), Color("#111111"), 0.2)
	_glow_quad(Vector2(0.46, 0.28), Vector3(-0.3, 1.0, -0.83), 0.0, Color("#6fa0c8"), 1.0)
	_box(Vector3(0.25, 0.02, 0.32), Vector3(0.3, 0.79, -0.5), Color("#efe6cf"))
	_lamp(Vector3(0.4, 2.2, 0.3), Color("#ffd9a0"), 1.3, 4.0)
	_chair(Vector3(0, 0, 0.05), PI, Color("#3a2416"))
	# arayan: antrenman sahası kenarı
	_box(Vector3(30, 0.1, 30), Vector3(40, -0.05, 0), Color("#2f6b2f"), 0.95)
	for i in 6:
		_box(Vector3(30, 0.012, 2.4), Vector3(40, 0.002, -12 + i * 4.8), Color("#367a35"), 0.95)
	_box(Vector3(30, 1.2, 0.06), Vector3(40, 0.6, -4), Color("#2a3a2a"), 0.5)
	for i in 8:
		_cyl(0.04, 1.3, Vector3(33 + i * 2, 0.65, -4), Color("#777777"))
	_box(Vector3(2.4, 0.9, 0.6), Vector3(37.5, 0.45, -3.2), Color("#d0d0d0"), 0.4)
	_sun(Vector3(-50, -30, 0), Color("#fff4e0"), 1.1)
	cam_target["wide0"] = {"pos": Vector3(0.55, 1.4, -1.45), "look": Vector3(0, 1.15, -0.25)}
	cam_target["wide1"] = {"pos": Vector3(41.0, 1.6, 2.2), "look": Vector3(40, 1.3, 0)}

func _set_training() -> void:
	_env(Color("#000000"), Color("#ffffff"), 0.7, true)
	var pm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform vec3 a : source_color = vec3(0.17, 0.42, 0.16);
uniform vec3 b : source_color = vec3(0.2, 0.48, 0.19);
varying vec3 wp;
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment(){ float s = step(0.5, fract(wp.x / 6.0)); ALBEDO = mix(a, b, s); ROUGHNESS = 0.95; }"""
	pm.shader = sh
	var pl := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(90, 70)
	pl.mesh = pmesh
	pl.material_override = pm
	world.add_child(pl)
	var white := Color("#f2f2ee")
	for z in [-20.0, 20.0]:
		_box(Vector3(60, 0.01, 0.1), Vector3(0, 0.006, z), white)
	for x in [-30.0, 0.0, 30.0]:
		_box(Vector3(0.1, 0.01, 40), Vector3(x, 0.006, 0), white)
	# çit, bank, binalar
	_box(Vector3(90, 1.6, 0.08), Vector3(0, 0.8, -26), Color("#2c3a2c"), 0.6)
	_box(Vector3(14, 6, 6), Vector3(-18, 3, -32), Color("#d8d2c2"))
	_box(Vector3(14, 0.5, 6.5), Vector3(-18, 6.2, -32), Color("#8a2a22"))
	_box(Vector3(5, 0.5, 0.6), Vector3(4, 0.45, -22.5), Color("#3a5a8a"), 0.4)
	_box(Vector3(5, 1.2, 0.1), Vector3(4, 0.8, -22.85), Color("#cfd8e0"), 0.2)
	# koniler
	cones.clear()
	for i in 6:
		var cp := Vector3(-8.0 + i * 2.2, 0, 4.0 + (0.9 if i % 2 == 0 else -0.9))
		var cn := _cyl(0.16, 0.32, cp + Vector3(0, 0.16, 0), Color("#ff7a1a"), 0.02)
		cones.append(cp)
	# mini kale
	goal_pos = Vector3(10.0, 0, 4.0)
	for zz in [-1.6, 1.6]:
		_box(Vector3(0.08, 1.4, 0.08), goal_pos + Vector3(0.0, 0.7, zz), white, 0.4)
	_box(Vector3(0.08, 0.08, 3.28), goal_pos + Vector3(0, 1.4, 0), white, 0.4)
	var net := _box(Vector3(0.9, 1.35, 3.2), goal_pos + Vector3(0.5, 0.68, 0), Color(1, 1, 1, 1))
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(1, 1, 1, 0.18)
	nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net.material_override = nm
	ball = _sphere(0.11, Vector3(-9, 0.11, 4), Color("#f5f5f5"))
	_sun(Vector3(-48, -35, 0), Color("#fff4e0"), 1.2)
	# kıvılcım halkası
	spark_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.7
	tm.outer_radius = 0.85
	spark_ring.mesh = tm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.82, 0.2, 0.9)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_ring.material_override = sm
	spark_ring.scale = Vector3(1, 0.15, 1)
	spark_ring.visible = false
	world.add_child(spark_ring)
	cam_target["wide0"] = {"pos": Vector3(-2, 4.5, 16), "look": Vector3(0, 0.5, 3)}

## antrenmanda arka planda koşan takım arkadaşları
func add_mates(club: Dictionary, n := 6) -> void:
	var c1 := Color(club.get("c1", "#cccccc"))
	var c2 := Color(club.get("c2", "#333333"))
	for i in n:
		var m = MM.new()
		world.add_child(m)
		m.build(MM.kit_mats(c1, c2.darkened(0.3), c1), i % 5, (i * 2) % 6, i + 11, i + 2)
		var a := -8.0 + i * 3.0
		m.position = Vector3(a, 0, -8.0 - (i % 3) * 2.0)
		m.set_meta("move", true)
		m.set_base("")
		mates.append({"n": m, "ang": float(i) / n * TAU, "r": 7.0 + (i % 2) * 1.5, "c": Vector3(-2, 0, -10), "spd": 3.2 + (i % 3) * 0.5})

func _mate_tick(m: Dictionary, delta: float) -> void:
	var n = m.n
	m.ang += delta * m.spd / m.r
	var target: Vector3 = m.c + Vector3(cos(m.ang) * m.r, 0, sin(m.ang) * m.r * 0.6)
	var d: Vector3 = target - n.position
	var v := d / maxf(delta, 0.001)
	n.position = target
	if d.length() > 0.001:
		n.rotation.y = atan2(d.x, d.z)
	n.tick(delta, minf(v.length(), 7.0))

# ================================================================ antrenman / video: drill + kıvılcım

## Oyuncu cones, şut, top sektirme döngüsü yapar. Süre boyunca n kıvılcım anı belirir.
func start_drills(id: String, duration := 14.0, n_sparks := 3) -> void:
	drill_on = true
	drill_actor = id
	var a = actors[id]
	a.set_meta("move", true)
	a.set_meta("talker", false)
	a.set_base("")
	a.position = cones[0] - Vector3(2.0, 0, 0)
	drill = {"phase": "slalom", "i": 0, "t": 0.0, "total": 0.0, "dur": duration}
	spark_times.clear()
	var slot := duration / float(n_sparks + 1)
	for k in n_sparks:
		spark_times.append(slot * (k + 1) + randf_range(-0.8, 0.8))
	spark_idx = 0
	spark_live = -1.0
	sparks_caught = 0
	ball.position = a.position + Vector3(0.5, 0.11, 0)
	ball_free = false

func drill_done() -> bool:
	return not drill_on

func try_catch() -> bool:
	## ekrana dokunuldu: canlı kıvılcım varsa yakala
	if spark_live >= 0.0:
		sparks_caught += 1
		spark_caught.emit(spark_idx - 1)
		spark_live = -1.0
		spark_ring.visible = false
		return true
	return false

func _drill_tick(delta: float) -> void:
	var a = actors[drill_actor]
	drill.t += delta
	drill.total += delta
	# kıvılcımlar
	if spark_idx < spark_times.size() and drill.total >= spark_times[spark_idx]:
		spark_live = 0.0
		spark_idx += 1
		spark_ring.visible = true
		spark_shown.emit(spark_idx - 1)
	if spark_live >= 0.0:
		spark_live += delta
		spark_ring.position = a.position + Vector3(0, 0.05, 0)
		var pulse := 1.0 + sin(spark_live * 14.0) * 0.12
		spark_ring.scale = Vector3(pulse, 0.15, pulse)
		if spark_live > 1.15:
			spark_live = -1.0
			spark_ring.visible = false
			spark_missed.emit(spark_idx - 1)
	var spd := 0.0
	match drill.phase:
		"slalom":
			var tgt: Vector3 = cones[drill.i] + Vector3(0, 0, -0.55 if drill.i % 2 == 0 else 0.55)
			spd = 4.2
			var d: Vector3 = tgt - a.position
			d.y = 0
			if d.length() < 0.35:
				drill.i += 1
				if drill.i >= cones.size():
					drill.phase = "shoot_run"
					drill.t = 0.0
			else:
				var step: Vector3 = d.normalized() * spd * delta
				a.position += step
				a.rotation.y = lerp_angle(a.rotation.y, atan2(d.x, d.z), minf(1.0, delta * 10.0))
			# top ayakta, önde
			var fwd := Vector3(sin(a.rotation.y), 0, cos(a.rotation.y))
			ball.position = ball.position.lerp(a.position + fwd * (0.55 + absf(sin(drill.total * 6.0)) * 0.25) + Vector3(0, 0.11, 0), minf(1.0, delta * 10.0))
			ball.rotate_x(delta * 9.0)
		"shoot_run":
			var tgt2 := goal_pos - Vector3(6.5, 0, 0)
			var d2: Vector3 = tgt2 - a.position
			d2.y = 0
			spd = 3.0
			if d2.length() < 0.3:
				drill.phase = "shoot"
				drill.t = 0.0
				a.rotation.y = atan2(goal_pos.x - a.position.x, goal_pos.z - a.position.z)
				a.play("shot")
				spd = 0.0
			else:
				a.position += d2.normalized() * spd * delta
				a.rotation.y = lerp_angle(a.rotation.y, atan2(d2.x, d2.z), minf(1.0, delta * 8.0))
				var fwd2 := Vector3(sin(a.rotation.y), 0, cos(a.rotation.y))
				ball.position = ball.position.lerp(a.position + fwd2 * 0.6 + Vector3(0, 0.11, 0), minf(1.0, delta * 10.0))
		"shoot":
			if drill.t > 0.14 and not ball_free:
				ball_free = true
				var aim := goal_pos + Vector3(0, randf_range(0.3, 1.1), randf_range(-1.2, 1.2))
				ball_vel = (aim - ball.position).normalized() * 19.0 + Vector3(0, 1.5, 0)
			if drill.t > 1.6:
				drill.phase = "juggle"
				drill.t = 0.0
				ball_free = false
				a.set_base("juggle")
				a.rotation.y = atan2(-1.0, 0.6)
		"juggle":
			# top sektirme: top, yüksekteki ayağın üstünde zıplar
			var sk: Skeleton3D = a.skel
			var fl := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("ball_l"))).origin
			var fr := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("ball_r"))).origin
			var foot := fl if fl.y > fr.y else fr
			var hgt := 0.35 + absf(sin(drill.t * 3.4)) * 0.75
			ball.position = ball.position.lerp(Vector3(foot.x, foot.y + hgt, foot.z) + Vector3(sin(a.rotation.y), 0, cos(a.rotation.y)) * 0.15, minf(1.0, delta * 12.0))
			if drill.t > 4.5:
				a.set_base("")
				drill.phase = "back"
				drill.t = 0.0
		"back":
			var tgt3: Vector3 = cones[0] - Vector3(2.0, 0, 0)
			var d3: Vector3 = tgt3 - a.position
			d3.y = 0
			spd = 5.5
			if d3.length() < 0.4:
				drill.phase = "slalom"
				drill.i = 0
				ball.position = a.position + Vector3(0.5, 0.11, 0)
			else:
				a.position += d3.normalized() * spd * delta
				a.rotation.y = lerp_angle(a.rotation.y, atan2(d3.x, d3.z), minf(1.0, delta * 8.0))
				if drill.t > 0.3 and ball.position.distance_to(a.position) > 1.2:
					ball.position = ball.position.lerp(tgt3 + Vector3(0.5, 0.11, 0), minf(1.0, delta * 2.0))
	a.tick(delta, spd)
	# kamera: oyuncuyu takip
	if follow:
		var fwd3 := Vector3(sin(a.rotation.y), 0, cos(a.rotation.y))
		var cp: Vector3 = a.position + Vector3(-1.5, 2.2, 5.2) - fwd3 * 0.6
		shot(0, cp, a.position + Vector3(0, 0.9, 0), 2.2)
	if drill.total >= drill.dur and spark_live < 0.0:
		drill_on = false

func _ball_tick(delta: float) -> void:
	ball_vel.y -= 9.8 * delta
	ball.position += ball_vel * delta
	if ball.position.y < 0.11:
		ball.position.y = 0.11
		ball_vel.y = absf(ball_vel.y) * 0.45
		ball_vel.x *= 0.8
		ball_vel.z *= 0.8
	if ball.position.x > goal_pos.x + 0.8:
		ball.position.x = goal_pos.x + 0.8
		ball_vel.x = -ball_vel.x * 0.15
