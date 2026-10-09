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
var big_goal := Vector3.ZERO
var crew := []            # idmana katılan arkadaşlar (mates öğeleri)

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
		cont.material = Watch.opaque_mat()
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
		if not m.get("busy", false):
			_mate_tick(m, delta)
	_walk_tick(delta)
	for sid in scarves:
		if actors.has(sid):
			var sk: Skeleton3D = actors[sid].skel
			var hl := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_l"))).origin
			var hr := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_r"))).origin
			var sc: Node3D = scarves[sid]
			sc.position = (hl + hr) * 0.5 + Vector3(0, 0.05, 0)
			var x := (hl - hr)
			if x.length() > 0.05:
				var xn := x.normalized()
				var fwd := Vector3(sin(actors[sid].rotation.y), 0, cos(actors[sid].rotation.y))
				var up := fwd.cross(xn).normalized()
				sc.basis = Basis(xn, up, xn.cross(up)).scaled(Vector3(clampf(x.length() / 0.55, 0.6, 1.4), 1, 1))
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
		m.apply_look(p)
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
	if info.get("kind", "npc") == "player":
		m.set_meta("p", info.p)
		m.set_meta("club", info.get("club", {}))
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
	var head := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("head"))).origin
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
	var hi := sk.find_bone("head")
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

## Konuşan: ağız replik süresince oynar, isteğe bağlı duygu; herkes konuşana bakar
func say(id: String, text: String, emo := "") -> void:
	if not actors.has(id):
		return
	var a = actors[id]
	if a.has_method("talk"):
		a.talk(clampf(text.length() / 15.0, 0.8, 5.0))
		if emo != "":
			a.emote(emo, 4.0)
			# beden dili: gerginlikte kollar kavuşur
			if emo in ["annoyed", "worried"] and a.overlay == "":
				a.overlay = "arms_crossed"
				get_tree().create_timer(4.0).timeout.connect(func():
					if is_instance_valid(a) and a.overlay == "arms_crossed":
						a.overlay = "")
	var sp := head_pos(id)
	for k in actors:
		var o = actors[k]
		if k == id:
			continue
		o.look_target = sp
	# konuşan dinleyene (ya da kameraya) bakar
	var other := ""
	for k in actors:
		if k != id:
			other = k
			break
	if other != "":
		a.look_target = head_pos(other)

func listener_react(id: String, good: bool) -> void:
	if not actors.has(id):
		return
	if actors[id].has_method("emote"):
		actors[id].emote("happy" if good else "worried", 3.0)
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
		"home": _set_home()
		"training", "video": _set_training()
	_extras(name)

## ---------------------------------------------------------------- figüranlar ve ortam sesi
var walkers: Array = []
var scarves := {}

func _extra(info: Dictionary, pos: Vector3, face: float, base := "idle") -> Node3D:
	var m = MM.new()
	world.add_child(m)
	m.lod = true
	m.build_outfit(info.get("top", Color("#555555")), info.get("pants", Color("#2a2a2a")), info.get("shoes", Color("#1a1a1a")), int(info.get("skin", 1)), int(info.get("hair", 0)), int(info.get("seed", 9)), true)
	m.position = pos
	m.rotation.y = face
	m.set_base(base)
	m.set_meta("move", true)
	m.set_meta("talker", false)
	return m

func _walker(info: Dictionary, pts: Array, spd := 1.2) -> void:
	var m := _extra(info, pts[0], 0.0, "")
	walkers.append({"n": m, "pts": pts, "i": 1, "spd": spd, "wait": randf_range(0.0, 2.0)})

func _extras(name: String) -> void:
	match name:
		"cafe":
			_chair(Vector3(2.6 + 0.6, 0, -1.5), -PI / 2.0, Color("#5a3a22"))
			var a := _extra({"top": Color("#6b4a3a"), "seed": 21, "skin": 2, "hair": 1}, Vector3(2.6 + 0.6 - 0.33, 0, -1.5), -PI / 2.0, "sit_talk")
			_chair(Vector3(-1.0 - 0.6, 0, -1.5), PI / 2.0, Color("#5a3a22"))
			_extra({"top": Color("#3d5566"), "seed": 33, "skin": 0, "hair": 4}, Vector3(-1.0 - 0.6 + 0.33, 0, -1.5), PI / 2.0, "sit")
			_extra({"top": Color("#f2f0ea"), "pants": Color("#151515"), "seed": 12, "skin": 1, "hair": 3}, Vector3(-2.3, 0, -2.05), 0.0, "idle")
			_walker({"top": Color("#1a1a1a"), "pants": Color("#1a1a1a"), "seed": 17, "skin": 3, "hair": 0}, [Vector3(-1.6, 0, -0.9), Vector3(1.8, 0, -0.9), Vector3(2.2, 0, -0.6), Vector3(-1.6, 0, -0.9)], 1.1)
			Sfx.amb_on("cafe", -14.0)
		"lobby":
			_box(Vector3(1.6, 1.05, 0.5), Vector3(4.2, 0.52, -2.2), Color("#3a2416"), 0.4)
			_extra({"top": Color("#22304a"), "seed": 27, "skin": 1, "hair": 2}, Vector3(4.2, 0, -2.65), 0.0, "idle")
			_walker({"top": Color("#7a2a2a"), "pants": Color("#2a2a33"), "seed": 44, "skin": 2, "hair": 1}, [Vector3(-5.0, 0, -1.8), Vector3(5.0, 0, -1.6), Vector3(-5.0, 0, -1.8)], 1.3)
			Sfx.amb_on("cafe", -22.0)
		"home":
			Sfx.amb_on("cafe", -30.0)
		"training", "video":
			Sfx.amb_on("field", -14.0)

func _walk_tick(delta: float) -> void:
	for w in walkers:
		var n: Node3D = w.n
		if w.wait > 0.0:
			w.wait -= delta
			n.tick(delta, 0.0)
			continue
		var tgt: Vector3 = w.pts[w.i]
		var d := tgt - n.position
		d.y = 0
		if d.length() < 0.1:
			w.i = (int(w.i) + 1) % (w.pts as Array).size()
			w.wait = randf_range(0.5, 2.5)
			continue
		n.position += d.normalized() * float(w.spd) * delta
		n.rotation.y = lerp_angle(n.rotation.y, atan2(d.x, d.z), minf(1.0, delta * 6.0))
		n.tick(delta, float(w.spd))

## Ev ziyareti: oturma odası (genç oyuncunun ailesi)
func _set_home() -> void:
	_env(Color("#120e0b"), Color("#8a7058"), 0.55)
	_box(Vector3(10, 0.1, 9), Vector3(0, -0.05, 0), Color("#6b4a30"), 0.7)
	_box(Vector3(10, 3.4, 0.2), Vector3(0, 1.7, -2.6), Color("#d9c9a8"))
	_box(Vector3(0.2, 3.4, 9), Vector3(-3.6, 1.7, 0), Color("#cbb995"))
	# halı, sehpa
	_box(Vector3(3.0, 0.02, 2.2), Vector3(0, 0.01, 0), Color("#7a2a2a"), 1.0)
	_box(Vector3(1.0, 0.06, 0.55), Vector3(0, 0.4, 0), Color("#3a2416"), 0.4)
	_cyl(0.05, 0.1, Vector3(-0.2, 0.48, 0.05), Color("#c84a2a"))
	_cyl(0.05, 0.1, Vector3(0.2, 0.48, -0.05), Color("#c84a2a"))
	_box(Vector3(0.5, 0.03, 0.35), Vector3(0.05, 0.445, 0.1), Color("#c9b98a"))
	# kanepe (aile) - oyuncunun yanında
	_box(Vector3(0.7, 0.42, 1.9), Vector3(1.55, 0.21, 0.0), Color("#5a6a3a"), 0.9)
	_box(Vector3(0.2, 0.55, 1.9), Vector3(1.95, 0.6, 0.0), Color("#4e5d32"), 0.9)
	# TV ünitesi, aile fotoğrafları, kupa/forma
	_box(Vector3(1.6, 0.5, 0.4), Vector3(-1.6, 0.25, -2.3), Color("#3a2416"))
	_box(Vector3(1.1, 0.62, 0.05), Vector3(-1.6, 0.85, -2.35), Color("#0a0a0a"), 0.2)
	for i in 4:
		_box(Vector3(0.28, 0.36, 0.03), Vector3(0.4 + i * 0.42, 1.9 + (0.12 if i % 2 == 0 else -0.06), -2.48), [Color("#e8dcc0"), Color("#c8b88a"), Color("#dcd0b4"), Color("#b8a87a")][i])
	_box(Vector3(0.6, 0.7, 0.02), Vector3(2.6, 1.8, -2.48), Color("#b5121b"))
	_lamp(Vector3(-0.5, 2.6, 0.8), Color("#ffd9a0"), 1.5, 6.0)
	_lamp(Vector3(2.4, 1.4, -1.6), Color("#ffcf8a"), 0.8, 3.0)
	_sun(Vector3(-35, -150, 0), Color("#ffe8c8"), 0.5)
	_chair(Vector3(-1.0, 0, 0.0), PI / 2.0, Color("#6b3a22"), true)
	cam_target["wide0"] = {"pos": Vector3(0.3, 1.7, 3.6), "look": Vector3(0.3, 0.85, -0.2)}

## İmza anı: atkı iki elin arasında
func attach_scarf(id: String, c1: Color, c2: Color) -> void:
	if not actors.has(id):
		return
	var n := Node3D.new()
	world.add_child(n)
	for k in 5:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.2, 0.012)
		mi.mesh = bm
		mi.material_override = _mat(c1 if k % 2 == 0 else c2, 0.9)
		mi.position = Vector3(-0.24 + k * 0.12, 0, 0)
		n.add_child(mi)
	scarves[id] = n

func flash() -> void:
	## basın flaşı: sahneyi bir an beyazlat
	var cr := ColorRect.new()
	cr.color = Color(1, 1, 1, 0.85)
	cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cr)
	var tw := create_tween()
	tw.tween_property(cr, "color:a", 0.0, 0.25)
	tw.tween_callback(cr.queue_free)
	Sfx.play("blip", -6.0)

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
	# büyük kale (şut idmanı): x=17, kaleci karşısında
	big_goal = Vector3(17.0, 0, 2.0)
	for zz in [-3.66, 3.66]:
		_box(Vector3(0.12, 2.44, 0.12), big_goal + Vector3(0, 1.22, zz), white, 0.4)
	_box(Vector3(0.12, 0.12, 7.44), big_goal + Vector3(0, 2.44, 0), white, 0.4)
	var bnet := _box(Vector3(1.6, 2.4, 7.3), big_goal + Vector3(0.85, 1.2, 0), Color(1, 1, 1, 1))
	bnet.material_override = nm
	# sprint kulvarı konileri
	for xx in [-12.0, 12.0]:
		for zz in [-11.4, -13.8]:
			_cyl(0.16, 0.32, Vector3(xx, 0.16, zz), Color("#ffd21a"), 0.02)
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
		m.lod = true
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

## Gerçek idmanlar: odak seçimine göre rondo, kaleci karşısında şut, sprint testi, 1'e 1.
## İzlenen oyuncu her idmanda rol alır; sonuçlar özelliklerine göre belirlenir.
const DRILL_SETS := {"tec": ["rondo", "slalom", "shoot", "longpass", "cross"], "phy": ["sprint", "duel", "slalom", "sprint", "duel"],
	"men": ["rondo", "longpass", "duel", "rondo", "cross"], "all": ["rondo", "shoot", "slalom", "cross", "sprint", "longpass", "duel"]}
const DRILL_LEN := {"rondo": 8.0, "shoot": 8.5, "sprint": 6.0, "duel": 7.0, "slalom": 7.5, "cross": 8.0, "longpass": 7.0, "keeper": 9.0}
var drill_nodes: Array = []

func start_drills(id: String, duration := 14.0, n_sparks := 3, focus := "all") -> void:
	drill_on = true
	drill_actor = id
	var a = actors[id]
	a.set_meta("move", true)
	a.set_meta("talker", false)
	a.set_base("")
	if mates.size() < 6:
		add_mates(a.get_meta("club", {}), 6 - mates.size())
	crew = mates.slice(0, 6)
	if not actors.has("coach"):
		var co = add_actor("coach", {"kind": "npc", "top": Color("#1f2a3a"), "pants": Color("#1f2a3a"), "shoes": Color("#e8e8e8"), "seed": 41, "skin": 2, "hair": 3}, Vector3(4.0, 0, -4.5), -0.6, "talk")
		co.set_meta("talker", false)
	for m in crew:
		m.busy = true
		(m.n as Node3D).set_meta("move", true)
	var dl: Array = DRILL_SETS.get(focus, DRILL_SETS.all).duplicate()
	dl.shuffle()
	if str(a.get_meta("p", {}).get("pos", "")) == "GK":
		dl = ["keeper", "rondo", "keeper", "longpass"]
	drill = {"list": dl, "k": -1, "t": 0.0, "total": 0.0, "dur": duration, "st": {}}
	spark_times.clear()
	var slot := duration / float(n_sparks + 1)
	for k in n_sparks:
		spark_times.append(slot * (k + 1) + randf_range(-0.8, 0.8))
	spark_idx = 0
	spark_live = -1.0
	sparks_caught = 0
	ball_free = false
	_next_drill()

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

func _attr(k: String) -> float:
	var a = actors[drill_actor]
	return float(a.get_meta("p", {}).get("attrs", {}).get(k, 10))

func _pop(pos: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0007
	l.font_size = 56
	l.outline_size = 14
	l.text = text
	l.modulate = col
	world.add_child(l)
	l.position = pos + Vector3(0, 2.3, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.8, 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)

func _next_drill() -> void:
	drill.k += 1
	drill.t = 0.0
	var list: Array = drill.list
	drill.kind = list[drill.k % list.size()]
	drill.st = {}
	for dn in drill_nodes:
		if is_instance_valid(dn):
			dn.queue_free()
	drill_nodes = []
	ball_free = false
	Sfx.play("whistle", -14.0)
	var a = actors[drill_actor]
	var c: Array = crew.map(func(m): return m.n)
	# bu idmanda görevi olmayanlar kenarda dinlenir (kalabalık olmasın)
	for k in c.size():
		(c[k] as Node3D).position = Vector3(-4.0 - k * 1.3, 0, -15.5)
		(c[k] as Node3D).rotation.y = 0.0
	match drill.kind:
		"rondo":
			# 5'e 2: çemberde 5 hücumcu (izlenen dahil), ortada 2 savunmacı
			var C := Vector3(-3.0, 0, 2.0)
			var ring := [a, c[0], c[1], c[2], c[3]]
			for i in ring.size():
				var ang := TAU * i / ring.size()
				ring[i].position = C + Vector3(cos(ang), 0, sin(ang)) * 5.5
			c[4].position = C + Vector3(0.8, 0, 0.3)
			c[5].position = C + Vector3(-0.8, 0, -0.4)
			drill.st = {"C": C, "ring": ring, "def": [c[4], c[5]], "hold": 0, "wait": 0.8, "fl": {}}
			ball.position = a.position + Vector3(0, 0.11, 0)
			shot(0, C + Vector3(0.0, 11.0, 11.5), C + Vector3(0, 0, 0.8), 2.0, true)
		"shoot":
			# servis arkadaştan, izlenen ceza sahası önünde kontrol edip vurur; kaleci kalede
			var gk = c[0]
			gk.position = big_goal - Vector3(0.6, 0, 0)
			gk.rotation.y = -PI / 2.0
			var server = c[1]
			server.position = big_goal + Vector3(-14.0, 0, -9.0)
			for k in range(2, 6):
				c[k].position = Vector3(-6.0 - k * 1.2, 0, -6.0 - k * 0.5)
			drill.st = {"gk": gk, "server": server, "ph": "serve", "pt": 0.0, "reps": 0}
			a.position = big_goal + Vector3(-17.0, 0, 1.5)
			ball.position = server.position + Vector3(0.6, 0.11, 0.3)
			shot(0, big_goal + Vector3(-23.0, 2.2, 2.6), big_goal + Vector3(0, 1.0, 0), 2.0, true)
		"sprint":
			var mate = c[1]
			a.position = Vector3(-13.0, 0, -12.0)
			mate.position = Vector3(-13.0, 0, -13.2)
			a.rotation.y = PI / 2.0
			mate.rotation.y = PI / 2.0
			drill.st = {"mate": mate, "ph": "ready", "va": 6.4 + (_attr("pace") - 10.0) * 0.16 + (_attr("agility") - 10.0) * 0.03, "vm": randf_range(6.6, 7.3), "done": false}
			ball.position = Vector3(-14.5, 0.11, -10.5)
			shot(0, Vector3(17.0, 1.5, -10.8), Vector3(-10.0, 1.0, -12.6), 2.0, true)
		"duel":
			var df = c[2]
			a.position = Vector3(-6.0, 0, -1.0)
			df.position = Vector3(1.0, 0, -1.0)
			a.rotation.y = PI / 2.0
			df.rotation.y = -PI / 2.0
			drill.st = {"df": df, "ph": "approach", "pt": 0.0, "reps": 0}
			ball.position = a.position + Vector3(0.6, 0.11, 0)
			shot(0, Vector3(-10.5, 1.7, 0.2), Vector3(0.0, 0.9, -1.0), 2.0, true)
		"slalom":
			# huni slalomu: çalım + çeviklik + ilk dokunuş, süre tutulur
			var pts := []
			for k in 6:
				var cp := Vector3(-11.0 + k * 2.2, 0, -6.0)
				var cn := _cyl(0.16, 0.42, cp + Vector3(0, 0.21, 0), Color("#ff7a1a"), 0.02)
				drill_nodes.append(cn)
				pts.append(cp + Vector3(0, 0, 0.95 if k % 2 == 0 else -0.95))
			pts.append(Vector3(3.0, 0, -6.0))
			a.position = Vector3(-14.0, 0, -6.0)
			a.rotation.y = PI / 2.0
			var spd := 3.4 + (_attr("dribbling") + _attr("agility") - 20.0) * 0.11
			drill.st = {"pts": pts, "i": 0, "spd": clampf(spd, 2.2, 5.6), "time": 0.0, "slip": false, "said": false}
			ball.position = a.position + Vector3(0.6, 0.11, 0)
			shot(0, Vector3(-5.0, 4.2, 3.5), Vector3(-5.0, 0.6, -6.0), 2.0, true)
		"cross":
			# kanattan orta + kafa: kanat oyuncusuysa ortayı o yapar, değilse kafayı o vurur
			var pos_s := str(a.get_meta("p", {}).get("pos", ""))
			var wide := pos_s in ["LB", "RB", "LW", "RW"]
			var gk2 = c[0]
			gk2.position = big_goal - Vector3(0.6, 0, 0)
			gk2.rotation.y = -PI / 2.0
			var winger: Node3D = a if wide else c[1]
			var target: Node3D = c[2] if wide else a
			winger.position = big_goal + Vector3(-20.0, 0, 13.0)
			target.position = big_goal + Vector3(-15.0, 0, -2.0)
			var df2 = c[3]
			df2.position = big_goal + Vector3(-7.0, 0, 0.5)
			drill.st = {"w": winger, "tg": target, "gk": gk2, "df": df2, "ph": "run", "pt": 0.0, "wide": wide}
			ball.position = winger.position + Vector3(0.6, 0.11, 0)
			shot(0, big_goal + Vector3(-22.0, 6.0, -10.0), big_goal + Vector3(-8.0, 0.8, 4.0), 2.0, true)
		"longpass":
			# uzun top: koşan arkadaşın önüne, isabet pas + vizyondan
			var rn = c[1]
			a.position = Vector3(-10.0, 0, 6.0)
			rn.position = Vector3(2.0, 0, -9.0)
			rn.rotation.y = PI / 2.0
			var tgt_z := Vector3(13.0, 0, -9.0)
			var mk := _cyl(1.6, 0.02, tgt_z + Vector3(0, 0.01, 0), Color("#e8c547"))
			mk.transparency = 0.6
			drill_nodes.append(mk)
			drill.st = {"rn": rn, "tgt": tgt_z, "ph": "set", "pt": 0.0, "reps": 0}
			ball.position = a.position + Vector3(0.6, 0.11, 0)
			shot(0, Vector3(-16.0, 5.5, 12.0), Vector3(3.0, 0.5, -3.0), 2.0, true)
		"keeper":
			# kaleci idmanı: arkadaşlar sırayla vurur, refleks + elle kontrol
			a.position = big_goal - Vector3(0.6, 0, 0)
			a.rotation.y = -PI / 2.0
			var sh_list := [c[1], c[2], c[3]]
			for k in sh_list.size():
				(sh_list[k] as Node3D).position = big_goal + Vector3(-13.0, 0, -4.0 + k * 4.0)
				(sh_list[k] as Node3D).rotation.y = PI / 2.0
			drill.st = {"sh": sh_list, "k": 0, "ph": "aim", "pt": 0.0}
			ball.position = (sh_list[0] as Node3D).position + Vector3(0.6, 0.11, 0)
			shot(0, big_goal + Vector3(-19.0, 2.4, 5.5), big_goal + Vector3(0, 1.0, 0), 2.0, true)

func _face_to(n: Node3D, p: Vector3, delta: float, k := 8.0) -> void:
	var d := p - n.position
	if Vector2(d.x, d.z).length() > 0.05:
		n.rotation.y = lerp_angle(n.rotation.y, atan2(d.x, d.z), minf(1.0, delta * k))

func _move(n: Node3D, p: Vector3, spd: float, delta: float) -> float:
	var d := p - n.position
	d.y = 0
	var L := d.length()
	if L < 0.05:
		return 0.0
	var step := minf(L, spd * delta)
	n.position += d / L * step
	_face_to(n, p, delta)
	return step / maxf(delta, 0.001)

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
	var speeds := {}
	match drill.kind:
		"rondo":
			_rondo(delta, speeds)
		"shoot":
			_shoot(delta, speeds)
		"sprint":
			_sprint(delta, speeds)
		"duel":
			_duel(delta, speeds)
		"slalom":
			_slalom(delta, speeds)
		"cross":
			_cross(delta, speeds)
		"longpass":
			_longpass(delta, speeds)
		"keeper":
			_keeper(delta, speeds)
	a.tick(delta, float(speeds.get(a, 0.0)))
	for m in crew:
		var n: Node3D = m.n
		n.tick(delta, float(speeds.get(n, 0.0)))
	if drill.t >= float(DRILL_LEN[drill.kind]) and not ball_free:
		_next_drill()
	if drill.total >= drill.dur and spark_live < 0.0:
		drill_on = false
		for dn in drill_nodes:
			if is_instance_valid(dn):
				dn.queue_free()
		drill_nodes = []
		for m in crew:
			m.busy = false

## --- rondo
func _rondo(delta: float, speeds: Dictionary) -> void:
	var st: Dictionary = drill.st
	var ring: Array = st.ring
	var C: Vector3 = st.C
	var fl: Dictionary = st.fl
	# savunmacılar: top sahibine ve pas yoluna baskı
	var holder: Node3D = ring[st.hold] if fl.is_empty() else null
	var bp := ball.position
	for i in 2:
		var d: Node3D = st.def[i]
		var tgt: Vector3 = bp.lerp(C, 0.35 + 0.3 * i) + Vector3(0.6 * (i * 2 - 1), 0, 0.4)
		speeds[d] = _move(d, Vector3(tgt.x, 0, tgt.z), 3.6, delta)
		_face_to(d, bp, delta)
	for n in ring:
		_face_to(n, bp, delta, 5.0)
	if not fl.is_empty():
		fl.t += delta
		var f := clampf(fl.t / fl.dur, 0.0, 1.0)
		ball.position = (fl.from as Vector3).lerp(fl.to, f) + Vector3(0, 0.11, 0)
		ball.rotate_x(delta * 14.0)
		if f >= 1.0:
			if fl.cut:
				var dn: Node3D = fl.cut_by
				_pop(dn.position, "✗", Color("#ff6a5a"))
				st.hold = -1
				st.def_hold = dn
				st.wait = 0.7
			else:
				st.hold = fl.recv
				st.wait = randf_range(0.45, 0.9)
				if ring[fl.recv] == actors[drill_actor] and _attr("first_touch") < 8.0 and randf() < 0.3:
					_pop(ring[fl.recv].position, T.t("tr_poor_touch"), Color("#ffb04a"))
			st.fl = {}
		return
	st.wait -= delta
	if st.hold < 0:
		# savunmacı topu kaptı: dışarı geri verir
		var dn2: Node3D = st.def_hold
		ball.position = ball.position.lerp(dn2.position + Vector3(0.4, 0.11, 0), minf(1.0, delta * 6.0))
		if st.wait <= 0.0:
			var r := randi() % ring.size()
			dn2.play("kick")
			st.fl = {"from": dn2.position, "to": (ring[r] as Node3D).position, "t": 0.0, "dur": 0.7, "recv": r, "cut": false}
		return
	var h: Node3D = ring[st.hold]
	var fwd := Vector3(sin(h.rotation.y), 0, cos(h.rotation.y))
	ball.position = ball.position.lerp(h.position + fwd * 0.45 + Vector3(0, 0.11, 0), minf(1.0, delta * 8.0))
	if st.wait <= 0.0:
		var me: bool = h == actors[drill_actor]
		var r2: int = (int(st.hold) + 1 + randi() % (ring.size() - 1)) % ring.size()
		var to: Vector3 = (ring[r2] as Node3D).position
		# kesilme: pas yoluna en yakın savunmacı
		var cut := false
		var cut_by: Node3D = null
		for d2 in st.def:
			var seg: Vector3 = to - h.position
			var tt := clampf(((d2 as Node3D).position - h.position).dot(seg) / maxf(0.01, seg.length_squared()), 0.0, 1.0)
			var dist := ((h.position + seg * tt) - (d2 as Node3D).position).length()
			if dist < 1.1:
				var pass_q := (_attr("passing") + _attr("vision")) * 0.5 if me else 11.0
				if randf() > 0.55 + (pass_q - 10.0) * 0.05:
					cut = true
					cut_by = d2
		h.play("kick")
		st.fl = {"from": h.position, "to": cut_by.position if cut else to, "t": 0.0, "dur": 0.55 if cut else h.position.distance_to(to) / 11.0, "recv": r2, "cut": cut, "cut_by": cut_by}
		if me:
			_pop(h.position, "✗ " + T.t("ev_pass") if cut else "✓ " + T.t("ev_pass"), Color("#ff6a5a") if cut else Color("#5ccf7a"))

## --- kaleci karşısında şut
func _shoot(delta: float, speeds: Dictionary) -> void:
	var st: Dictionary = drill.st
	var a = actors[drill_actor]
	var gk: Node3D = st.gk
	var sv: Node3D = st.server
	_face_to(gk, ball.position, delta, 4.0)
	st.pt += delta
	if st.ph in ["serve", "fly", "touch"]:
		shot(0, a.position + Vector3(-5.5, 2.0, 1.2), big_goal + Vector3(0, 1.0, 0), 2.5)
	elif st.ph == "shot" and st.pt > 0.2:
		shot(0, big_goal + Vector3(-10.0, 1.7, 6.5), big_goal + Vector3(-1.0, 1.0, 0), 5.0)
	match st.ph:
		"serve":
			var spot: Vector3 = big_goal + Vector3(-17.0, 0, randf_range(-0.5, 1.5)) if not st.has("spot") else st.spot
			st.spot = spot
			speeds[a] = _move(a, spot, 3.0, delta)
			_face_to(sv, a.position, delta)
			if st.pt > 0.8:
				sv.play("kick")
				st.ph = "fly"
				st.pt = 0.0
				st.from = ball.position
		"fly":
			var f := clampf(st.pt / 0.9, 0.0, 1.0)
			ball.position = (st.from as Vector3).lerp(a.position + Vector3(0.5, 0.11, 0), f)
			_face_to(a, ball.position, delta)
			if f >= 1.0:
				st.ph = "touch"
				st.pt = 0.0
		"touch":
			var tgt: Vector3 = st.spot + Vector3(3.0, 0, 0)
			speeds[a] = _move(a, tgt, 4.0, delta)
			ball.position = ball.position.lerp(a.position + Vector3(0.7, 0.11, 0), minf(1.0, delta * 8.0))
			if st.pt > 0.75:
				a.rotation.y = atan2(big_goal.x - a.position.x, big_goal.z - a.position.z)
				a.play("shot")
				st.ph = "shot"
				st.pt = 0.0
		"shot":
			if st.pt > 0.14 and not st.has("aim"):
				var fin := _attr("finishing")
				var side := randf_range(-3.2, 3.2)
				st.aim = big_goal + Vector3(0, randf_range(0.2, 2.1), side)
				var on_target := randf() < 0.6 + (fin - 10.0) * 0.04
				if not on_target:
					st.aim = big_goal + Vector3(0, randf_range(0.5, 3.0), signf(side) * randf_range(3.9, 5.0))
				st.goal = on_target and randf() < 0.45 + (fin - 10.0) * 0.045
				st.from = ball.position
				st.ft = 0.0
				# kaleci tahmin edip uçar
				var dive_dir := signf((st.aim as Vector3).z - gk.position.z)
				if absf((st.aim as Vector3).z - gk.position.z) > 1.0:
					gk.play("dive", 0.8, dive_dir)
				else:
					gk.play("save_low")
			if st.has("aim"):
				st.ft += delta
				var f2 := clampf(st.ft / 0.55, 0.0, 1.0)
				var pos := (st.from as Vector3).lerp(st.aim, f2)
				pos.y += sin(f2 * PI) * 0.4
				if not st.goal and f2 > 0.85 and (st.aim as Vector3).z > -3.7 and (st.aim as Vector3).z < 3.7:
					# kurtarış: top geri seker
					pos = (st.from as Vector3).lerp(st.aim, 0.85) + Vector3(-(f2 - 0.85) * 12.0, 0, 0)
				ball.position = pos
				if f2 >= 1.0 and not st.has("said"):
					st.said = true
					var on_frame: bool = (st.aim as Vector3).z > -3.7 and (st.aim as Vector3).z < 3.7
					if st.goal:
						_pop(a.position, T.t("tr_goal"), Color("#e8c547"))
						Sfx.play("net", -10.0)
					elif on_frame:
						_pop(a.position, T.t("tr_saved"), Color("#ffb04a"))
					else:
						_pop(a.position, T.t("tr_wide"), Color("#ff6a5a"))
			if st.pt > 2.2:
				st.erase("aim")
				st.erase("said")
				st.erase("spot")
				st.ph = "back"
				st.pt = 0.0
		"back":
			speeds[a] = _move(a, big_goal + Vector3(-17.0, 0, 1.0), 4.5, delta)
			ball.position = ball.position.lerp(sv.position + Vector3(0.6, 0.11, 0.3), minf(1.0, delta * 3.0))
			if st.pt > 1.0:
				st.ph = "serve"
				st.pt = 0.0

## --- huni slalomu
func _slalom(delta: float, speeds: Dictionary) -> void:
	var st: Dictionary = drill.st
	var a = actors[drill_actor]
	var pts: Array = st.pts
	if st.i >= pts.size():
		if not st.said:
			st.said = true
			var tt: float = st.time
			_pop(a.position, "%.1f sn" % tt, Color("#5ccf7a") if tt < 4.6 else (Color("#e8c547") if tt < 5.6 else Color("#ffb04a")))
		return
	st.time += delta
	var spd: float = st.spd
	if st.slip:
		spd *= 0.35
		st.slip_t -= delta
		if st.slip_t <= 0.0:
			st.slip = false
	speeds[a] = _move(a, pts[st.i], spd, delta)
	var fwd := Vector3(sin(a.rotation.y), 0, cos(a.rotation.y))
	ball.position = ball.position.lerp(a.position + fwd * 0.5 + Vector3(0, 0.11, 0), minf(1.0, delta * 9.0))
	shot(0, a.position + Vector3(-1.5, 3.2, 5.5), a.position + Vector3(1.0, 0.6, 0), 3.0)
	if a.position.distance_to(pts[st.i]) < 0.25:
		st.i += 1
		# zayıf ilk dokunuş: top açılır, yavaşlar
		if not st.slip and randf() < 0.18 - (_attr("first_touch") - 10.0) * 0.02:
			st.slip = true
			st.slip_t = 0.6
			_pop(a.position, T.t("tr_poor_touch"), Color("#ffb04a"))

## --- orta + kafa
func _cross(delta: float, speeds: Dictionary) -> void:
	var st: Dictionary = drill.st
	var w: Node3D = st.w
	var tg: Node3D = st.tg
	var gk: Node3D = st.gk
	st.pt += delta
	_face_to(gk, ball.position, delta, 4.0)
	_face_to(st.df, ball.position, delta, 4.0)
	if st.ph == "run":
		shot(0, w.position + Vector3(-6.0, 3.2, 6.0), w.position + Vector3(2.0, 0.8, -2.0), 3.0)
	match st.ph:
		"run":
			speeds[w] = _move(w, big_goal + Vector3(-7.0, 0, 12.0), 6.0, delta)
			speeds[tg] = _move(tg, big_goal + Vector3(-11.0, 0, 1.0), 3.5, delta)
			ball.position = ball.position.lerp(w.position + Vector3(0.7, 0.11, -0.2), minf(1.0, delta * 9.0))
			if w.position.distance_to(big_goal + Vector3(-7.0, 0, 12.0)) < 0.4:
				w.rotation.y = atan2(tg.position.x - w.position.x, tg.position.z - w.position.z)
				w.play("kick")
				var cq := _attr("crossing") if st.wide else 12.0
				var err := clampf((16.0 - cq) * 0.35, 0.3, 4.0) * randf()
				st.land = big_goal + Vector3(-7.0, 0, 0.5) + Vector3(randf_range(-err, err), 0, randf_range(-err, err))
				st.good_cross = err < 1.6
				st.from = ball.position
				st.ph = "fly"
				st.pt = 0.0
		"fly":
			var f := clampf(st.pt / 1.1, 0.0, 1.0)
			var pos: Vector3 = (st.from as Vector3).lerp(st.land + Vector3(0, 0.0, 0), f)
			pos.y = 0.11 + sin(f * PI) * 4.2 + f * 1.6
			ball.position = pos
			speeds[tg] = _move(tg, st.land, 6.5, delta)
			speeds[st.df] = _move(st.df, (st.land as Vector3) + Vector3(0.8, 0, 0.4), 5.0, delta)
			shot(0, big_goal + Vector3(-17.0, 5.0, 9.0), (st.land as Vector3) + Vector3(0, 1.4, 0), 3.0)
			if f >= 1.0:
				var hq := _attr("heading") if not st.wide else 12.0
				var won: bool = st.good_cross and randf() < 0.45 + (hq - 10.0) * 0.05
				if won:
					tg.play("header")
				if won:
					st.goal = randf() < 0.5 + (hq - 10.0) * 0.03
					st.aim = big_goal + Vector3(0, randf_range(0.3, 2.0), randf_range(-3.0, 3.0))
					if not st.goal:
						gk.play("dive", 0.8, signf((st.aim as Vector3).z - gk.position.z))
				st.won = won
				st.from = ball.position
				st.ph = "end"
				st.pt = 0.0
				var who: Node3D = w if st.wide else tg
				if not st.good_cross:
					_pop(who.position, T.t("tr_bad_cross") if st.wide else T.t("tr_no_ball"), Color("#ff6a5a"))
				elif not won:
					_pop(tg.position, T.t("tr_lost_air"), Color("#ffb04a"))
		"end":
			if st.get("won", false):
				var f2 := clampf(st.pt / 0.5, 0.0, 1.0)
				ball.position = (st.from as Vector3).lerp(st.aim, f2)
				if f2 >= 1.0 and not st.has("said"):
					st.said = true
					if st.goal:
						_pop(tg.position, T.t("tr_goal"), Color("#e8c547"))
						Sfx.play("net", -10.0)
					else:
						_pop(tg.position, T.t("tr_saved"), Color("#ffb04a"))
			else:
				ball.position = ball.position.lerp(st.df.position + Vector3(0.5, 0.11, 0), minf(1.0, delta * 5.0))

## --- uzun pas
func _longpass(delta: float, speeds: Dictionary) -> void:
	var st: Dictionary = drill.st
	var a = actors[drill_actor]
	var rn: Node3D = st.rn
	st.pt += delta
	match st.ph:
		"set":
			_face_to(a, st.tgt, delta)
			if st.pt > 0.7:
				speeds[rn] = 0.0
				a.play("kick")
				st.ph = "fly"
				st.pt = 0.0
				var q := (_attr("passing") * 0.6 + _attr("vision") * 0.4)
				var err := clampf((17.0 - q) * 0.45, 0.2, 6.0) * randf()
				st.land = (st.tgt as Vector3) + Vector3(randf_range(-err, err), 0, randf_range(-err, err))
				st.good = (st.land as Vector3).distance_to(st.tgt) < 2.0
				st.from = ball.position
		"fly":
			var f := clampf(st.pt / 1.5, 0.0, 1.0)
			var pos: Vector3 = (st.from as Vector3).lerp(st.land, f)
			pos.y = 0.11 + sin(f * PI) * 7.0
			ball.position = pos
			speeds[rn] = _move(rn, st.land, 6.8, delta)
			shot(0, Vector3(pos.x - 8.0, 6.0, pos.z + 12.0), pos, 3.0)
			if f >= 1.0:
				var ok: bool = st.good and rn.position.distance_to(st.land) < 1.6
				_pop(rn.position, T.t("tr_long_ok") if ok else T.t("tr_long_bad"), Color("#5ccf7a") if ok else Color("#ff6a5a"))
				st.ph = "after"
				st.pt = 0.0
		"after":
			ball.position = ball.position.lerp(rn.position + Vector3(0.5, 0.11, 0), minf(1.0, delta * 6.0))
			if st.pt > 1.4 and st.reps < 1:
				st.reps += 1
				rn.position = Vector3(2.0, 0, -9.0)
				ball.position = a.position + Vector3(0.6, 0.11, 0)
				st.ph = "set"
				st.pt = 0.0

## --- kaleci
func _keeper(delta: float, speeds: Dictionary) -> void:
	var st: Dictionary = drill.st
	var a = actors[drill_actor]
	var shooters: Array = st.sh
	var sh: Node3D = shooters[st.k % shooters.size()]
	st.pt += delta
	_face_to(a, ball.position, delta, 6.0)
	shot(0, big_goal + Vector3(-12.0, 2.2, 8.5), big_goal + Vector3(-1.0, 1.1, -0.5), 3.0)
	match st.ph:
		"aim":
			ball.position = ball.position.lerp(sh.position + Vector3(0.6, 0.11, 0), minf(1.0, delta * 6.0))
			if st.pt > 0.9:
				sh.play("shot")
				st.aim = big_goal + Vector3(0, randf_range(0.2, 2.1), randf_range(-3.2, 3.2))
				st.from = ball.position
				var refl := _attr("reflexes") * 0.6 + _attr("handling") * 0.4
				st.save = randf() < 0.45 + (refl - 10.0) * 0.05
				st.held = st.save and randf() < 0.5 + (_attr("handling") - 10.0) * 0.05
				var dd: float = (st.aim as Vector3).z - a.position.z
				if absf(dd) > 0.9:
					a.play("dive", 0.8, signf(dd))
				else:
					a.play("save_low")
				st.ph = "fly"
				st.pt = 0.0
		"fly":
			var f := clampf(st.pt / 0.5, 0.0, 1.0)
			var pos := (st.from as Vector3).lerp(st.aim, f)
			if st.save and f > 0.85:
				pos = (st.from as Vector3).lerp(st.aim, 0.85) + Vector3(-(f - 0.85) * (2.0 if st.held else 10.0), 0, 0)
			ball.position = pos
			if f >= 1.0:
				if st.save:
					_pop(a.position, T.t("tr_held") if st.held else T.t("tr_parried"), Color("#5ccf7a") if st.held else Color("#e8c547"))
				else:
					_pop(a.position, T.t("tr_conceded"), Color("#ff6a5a"))
					Sfx.play("net", -12.0)
				st.ph = "reset"
				st.pt = 0.0
		"reset":
			if st.pt > 1.2:
				st.k += 1
				st.ph = "aim"
				st.pt = 0.0
				a.position = big_goal - Vector3(0.6, 0, 0)
				ball.position = (shooters[st.k % shooters.size()] as Node3D).position + Vector3(0.6, 0.11, 0)

## --- sprint testi
func _sprint(delta: float, speeds: Dictionary) -> void:
	var st: Dictionary = drill.st
	var a = actors[drill_actor]
	var mt: Node3D = st.mate
	match st.ph:
		"ready":
			if drill.t > 0.9:
				st.ph = "run"
				Sfx.play("whistle", -10.0)
		"run":
			var va: float = st.va * minf(1.0, (drill.t - 0.9) * 1.6 + 0.3)
			var vm: float = st.vm * minf(1.0, (drill.t - 0.9) * 1.5 + 0.3)
			speeds[a] = _move(a, Vector3(13.0, 0, -12.0), va, delta)
			speeds[mt] = _move(mt, Vector3(13.0, 0, -13.2), vm, delta)
			shot(0, Vector3(minf(a.position.x + 6.5, 16.0), 1.4, -10.9), Vector3(a.position.x - 1.0, 1.0, -12.6), 3.5)
			if not st.done and (a.position.x > 12.0 or mt.position.x > 12.0):
				st.done = true
				var won: bool = a.position.x >= mt.position.x
				_pop(a.position, T.t("tr_first") if won else T.t("tr_second"), Color("#5ccf7a") if won else Color("#ffb04a"))
			if a.position.x > 12.9 and mt.position.x > 12.9:
				st.ph = "rest"
		"rest":
			pass

## --- 1'e 1
func _duel(delta: float, speeds: Dictionary) -> void:
	var st: Dictionary = drill.st
	var a = actors[drill_actor]
	var df: Node3D = st.df
	st.pt += delta
	match st.ph:
		"approach":
			speeds[a] = _move(a, df.position + Vector3(-1.4, 0, 0), 3.2, delta)
			speeds[df] = _move(df, a.position + Vector3(2.2, 0, 0), 1.2, delta)
			var fwd := Vector3(sin(a.rotation.y), 0, cos(a.rotation.y))
			ball.position = ball.position.lerp(a.position + fwd * 0.55 + Vector3(0, 0.11, 0), minf(1.0, delta * 10.0))
			if a.position.distance_to(df.position) < 1.8:
				var drib := _attr("dribbling") * 0.6 + _attr("agility") * 0.25 + _attr("pace") * 0.15
				st.win = randf() < 0.5 + (drib - 11.0) * 0.05
				st.ph = "beat" if st.win else "lose"
				st.pt = 0.0
				st.side = 1.0 if randf() < 0.5 else -1.0
				if st.win:
					a.play("kick", 0.4)
					_pop(a.position, "✓ " + T.t("ev_dribble"), Color("#5ccf7a"))
				else:
					df.play("tackle")
					_pop(a.position, "✗ " + T.t("ev_dribble"), Color("#ff6a5a"))
		"beat":
			var tgt: Vector3 = df.position + Vector3(3.0, 0, st.side * 1.4)
			speeds[a] = _move(a, tgt, 5.5, delta)
			ball.position = ball.position.lerp(a.position + Vector3(0.7, 0.11, 0), minf(1.0, delta * 9.0))
			_face_to(df, a.position, delta)
			if st.pt > 1.3:
				st.ph = "reset"
				st.pt = 0.0
		"lose":
			ball.position += Vector3(2.5, 0, st.side * 2.0) * delta * maxf(0.0, 1.0 - st.pt)
			speeds[df] = _move(df, ball.position, 2.0, delta)
			if st.pt > 1.3:
				st.ph = "reset"
				st.pt = 0.0
		"reset":
			speeds[a] = _move(a, Vector3(-6.0, 0, -1.0), 4.5, delta)
			speeds[df] = _move(df, Vector3(1.0, 0, -1.0), 4.0, delta)
			ball.position = ball.position.lerp(a.position + Vector3(0.6, 0.11, 0), minf(1.0, delta * 3.0))
			if st.pt > 1.4:
				a.rotation.y = PI / 2.0
				st.ph = "approach"
				st.pt = 0.0

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
