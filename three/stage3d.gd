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
		cont.material = Post.make("training" if name == "training" else ("video" if name == "video" else "office"))
		hb.add_child(cont)
		var sv := SubViewport.new()
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# match_view ile aynı kural: mobilde MSAA hiç açılmaz (v0.21 Adreno boş görünüm geçmişi)
		sv.msaa_3d = Viewport.MSAA_2X if shadows and not Game.settings.get("safe3d", false) and not OS.has_feature("mobile") else Viewport.MSAA_DISABLED
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
		# Sky kaynağı bazı Adreno sürücülerinde siyah ekran veriyordu: mesh kubbe
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color("#9fb7cc")
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color("#c6d4e6")
		world.add_child(load("res://three/stadium.gd").sky_dome("day", "clear", 300.0))
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
		"training": _set_training()
		"video": _set_video()
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

func _set_training() -> void:
	# tesis sahası: stadyum sisteminin küçük sahası (çit, ağaçlar, direkler, gökyüzü, hava)
	var cond := StadS.pick_cond(hash(str(Game.s.get("season", 0)) + str(Game.s.get("week", 0)) + set_name), 3, int(Game.s.get("week", 1)), "tr", true)
	var st = StadS.new()
	world.add_child(st)
	st.configure(3, cond.tod, cond.weather if cond.weather != "snow" else "clear")
	var cl := Game.my_club()
	st.build(Color(cl.get("c1", "#2f6b3a")), Color(cl.get("c2", "#ffffff")), Color("#888888"), false, shadows)
	train_stadium = st
	_training_panorama(cond)
	var white := Color("#f2f2ee")
	# yıpranmış çim lekeleri: kale ağzı ve koni slalomu
	_worn_patch(Vector3(10.6, 0, 4.0), Vector2(5.0, 6.5))
	_worn_patch(Vector3(-2.5, 0, 4.0), Vector2(14.0, 4.0))
	# tesis binası: iki katlı, camlı, kulüp renginde şerit
	var win_m = st._shader_mat(StadS.WINDOW_SHADER)
	win_m.set_shader_parameter("night", 0.0 if cond.tod == "day" else 1.0)
	win_m.set_shader_parameter("wall", Vector3(0.78, 0.76, 0.72))
	_mbox(Vector3(22, 7, 9), Vector3(-14, 3.5, -50), win_m)
	_mbox(Vector3(22.4, 0.5, 9.4), Vector3(-14, 7.2, -50), _mat(Color(cl.get("c1", "#8a2a22")), 0.6))
	_mbox(Vector3(4, 3, 0.2), Vector3(-14, 1.5, -45.4), _mat(Color(0.15, 0.17, 0.2), 0.2, 0.4))
	# yedek kulübesi bankları, top torbası, su şişeleri, duvar mankenleri
	for bx in [-6.0, 2.0]:
		_mbox(Vector3(4.5, 0.08, 0.45), Vector3(bx, 0.45, -37.0), _mat(Color(cl.get("c1", "#2a4a8a")), 0.5))
		_mbox(Vector3(4.5, 0.5, 0.06), Vector3(bx, 0.72, -37.25), _mat(Color(cl.get("c1", "#2a4a8a")).darkened(0.2), 0.5))
		for lx in [-2.0, 2.0]:
			_box(Vector3(0.06, 0.45, 0.4), Vector3(bx + lx, 0.22, -37.0), Color(0.3, 0.3, 0.32))
		_ao(Vector3(bx, 0, -37.0), Vector2(5.2, 1.2), 0.45)
	var bag := _mat(Color(0.1, 0.1, 0.12), 0.9)
	_mbox(Vector3(0.7, 0.5, 0.5), Vector3(-1.5, 0.25, -35.5), bag)
	for i in 6:
		_sphere(0.11, Vector3(-1.75 + (i % 3) * 0.22, 0.55, -35.4 + (i / 3) * 0.2), white)
	for i in 8:
		_cyl(0.04, 0.24, Vector3(0.0 + i * 0.12, 0.12, -35.8), Color(0.2, 0.55, 0.9) if i % 2 == 0 else Color(0.95, 0.95, 0.95), 0.03)
	for i in 4:
		var mx := 6.0 + i * 0.7
		_mbox(Vector3(0.5, 1.75, 0.12), Vector3(mx, 0.9, -6.0), _mat(Color(0.95, 0.75, 0.1), 0.6))
		_sphere(0.14, Vector3(mx, 1.9, -6.0), Color(0.95, 0.75, 0.1))
	# taktik tahtası
	_mbox(Vector3(1.4, 0.95, 0.05), Vector3(4.6, 1.3, -5.2), _mat(Color(0.95, 0.95, 0.93), 0.3))
	_box(Vector3(0.05, 1.3, 0.05), Vector3(4.0, 0.65, -5.2), Color(0.3, 0.3, 0.3))
	_box(Vector3(0.05, 1.3, 0.05), Vector3(5.2, 0.65, -5.2), Color(0.3, 0.3, 0.3))
	for i in 5:
		_sphere(0.04, Vector3(4.2 + i * 0.2, 1.3 + sin(i) * 0.2, -5.17), Color(0.85, 0.1, 0.1) if i % 2 else Color(0.1, 0.2, 0.8))
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
	var nm := _shm("""shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
void fragment() {
	vec2 g = fract(UV * vec2(36.0, 24.0));
	float line = 1.0 - step(0.08, g.x) * step(0.08, g.y);
	ALBEDO = vec3(0.95);
	ALPHA = line * 0.32;
}""")
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
var train_stadium: Node3D

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

# ================================================================ v0.21 set kiti: dokular, pencereler, gölgeler
const HubS = preload("res://three/hub3d.gd")
const StadS = preload("res://three/stadium.gd")

func _has(path: String) -> bool:
	return ResourceLoader.exists(path)

## Doku varsa doku (Gemini), yoksa renk
func _tmat(path: String, fallback: Color, scale := Vector2.ONE, tint := Color.WHITE, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = rough
	if _has(path):
		m.albedo_texture = load(path)
		m.albedo_color = tint
		m.uv1_scale = Vector3(scale.x, scale.y, 1)
	else:
		m.albedo_color = fallback
	return m

func _shm(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func _paint(col: Color, wainscot := 0.0, panel := Color(0.22, 0.13, 0.07), stains := 0.0, slats := 0.0) -> ShaderMaterial:
	var m := _shm(HubS.PAINT_SHADER)
	m.set_shader_parameter("col", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("panel", Vector3(panel.r, panel.g, panel.b))
	m.set_shader_parameter("wainscot", wainscot)
	m.set_shader_parameter("stains", stains)
	m.set_shader_parameter("slats", slats)
	return m

func _wood(dark := false) -> Material:
	if _has("res://assets/tex/tex_wood_dark.jpg"):
		return _tmat("res://assets/tex/tex_wood_dark.jpg", Color.BLACK, Vector2(4, 4), Color(1, 1, 1) if dark else Color(1.35, 1.2, 1.05), 0.55)
	var m := _shm(HubS.WOOD_SHADER)
	if dark:
		m.set_shader_parameter("c1", Vector3(0.1, 0.055, 0.03))
		m.set_shader_parameter("c2", Vector3(0.17, 0.095, 0.05))
	return m

func _mbox(sz: Vector3, pos: Vector3, mat: Material, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	(parent if parent else world).add_child(mi)
	return mi

func _quad(sz: Vector2, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	return mi

func _ao(pos: Vector3, size: Vector2, strength := 0.5) -> void:
	var m := _shm(HubS.AO_SHADER)
	m.set_shader_parameter("strength", strength)
	_quad(size, pos + Vector3(0, 0.012, 0), m, Vector3(-90, 0, 0))

## Pencere: özel görsel varsa onu, yoksa gece şehri fotoğrafını saate göre boyar
func _window(pos: Vector3, size: Vector2, img: String, frame: Color, mode := "day", rot_y := 0.0) -> void:
	var mat: Material
	if _has(img):
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_texture = load(img)
		sm.albedo_color = Color(1.05, 1.05, 1.05)
		mat = sm
	else:
		var pm := _shm(HubS.PHOTO_WINDOW)
		pm.set_shader_parameter("city", load("res://assets/tex/city_night.jpg"))
		pm.set_shader_parameter("day", 1.0 if mode == "day" else 0.0)
		pm.set_shader_parameter("dusk", 1.0 if mode == "dusk" else 0.0)
		var span := clampf(size.x / size.y * 0.97, 0.3, 1.0)
		pm.set_shader_parameter("crop_x", Vector2(0.5 - span / 2.0, 0.5 + span / 2.0))
		mat = pm
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = rot_y
	world.add_child(holder)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	q.mesh = qm
	q.material_override = mat
	holder.add_child(q)
	var fm := _mat(frame, 0.5, 0.3)
	_mbox(Vector3(size.x + 0.14, 0.07, 0.08), Vector3(0, size.y / 2.0 + 0.035, 0.02), fm, holder)
	_mbox(Vector3(size.x + 0.14, 0.1, 0.22), Vector3(0, -size.y / 2.0 - 0.05, 0.08), fm, holder)
	for sx in [-1.0, 1.0]:
		_mbox(Vector3(0.07, size.y, 0.08), Vector3(sx * (size.x / 2.0 + 0.035), 0, 0.02), fm, holder)
	_mbox(Vector3(0.04, size.y, 0.05), Vector3(0, 0, 0.02), fm, holder)

func _frames(base: Vector3, n: int, rng: RandomNumberGenerator, gold := false) -> void:
	## duvarda çerçeveli fotoğraflar (kâğıt dokulu içerik, futbol temalı küçük renkler)
	var fr := _mat(Color(0.72, 0.56, 0.24) if gold else Color(0.12, 0.08, 0.05), 0.4, 0.8 if gold else 0.0)
	var paper := _tmat("res://assets/tex/paper.jpg", Color(0.9, 0.86, 0.78))
	for i in n:
		var w := rng.randf_range(0.28, 0.42)
		var h := rng.randf_range(0.32, 0.46)
		var p := base + Vector3(i * 0.55, rng.randf_range(-0.12, 0.12), 0)
		_mbox(Vector3(w, h, 0.03), p, fr)
		_mbox(Vector3(w - 0.06, h - 0.06, 0.032), p + Vector3(0, 0, 0.002), paper)
		# fotoğrafın içindeki takım (küçük renk bloğu)
		_mbox(Vector3(w - 0.12, (h - 0.06) * 0.45, 0.034), p + Vector3(0, -0.02, 0.003), _mat(Color.from_hsv(rng.randf(), 0.35, 0.35), 0.9))

func _books(pos: Vector3, w: float, h: float, rng: RandomNumberGenerator, dark := true) -> void:
	var wood := _wood(dark)
	_mbox(Vector3(w, h, 0.04), pos + Vector3(0, h / 2.0, -0.17), wood)
	for sx in [-1.0, 1.0]:
		_mbox(Vector3(0.04, h, 0.36), pos + Vector3(sx * w / 2.0, h / 2.0, 0), wood)
	var shelves := int(h / 0.42)
	var cols := [Color("#7d1d1d"), Color("#1d3c5c"), Color("#c49a2c"), Color("#2e5a3a"), Color("#d8cbb0"), Color("#3a3a3a"), Color("#5a3a6a")]
	for si in shelves + 1:
		var y := 0.05 + si * (h - 0.1) / shelves
		_mbox(Vector3(w, 0.03, 0.34), pos + Vector3(0, y, 0), wood)
		if si == shelves:
			break
		var x := -w / 2.0 + 0.05
		while x < w / 2.0 - 0.1:
			var bw := rng.randf_range(0.04, 0.09)
			var bh := rng.randf_range(0.22, 0.34)
			if rng.randf() < 0.1:
				x += 0.1
				continue
			_box(Vector3(bw, bh, 0.24), pos + Vector3(x + bw / 2.0, y + 0.015 + bh / 2.0, 0.02), cols[rng.randi() % cols.size()] * rng.randf_range(0.7, 1.1))
			x += bw + 0.004
	_ao(pos + Vector3(0, 0, 0.1), Vector2(w + 0.4, 0.8), 0.45)

func _plant(pos: Vector3, s := 1.0) -> void:
	_cyl(0.2 * s, 0.38 * s, pos + Vector3(0, 0.19 * s, 0), Color("#8a4a2a"), 0.16 * s)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 100.0 + pos.z * 7.0)
	for i in 9:
		var a := i * TAU / 9.0
		var lm := _sphere(0.14 * s, pos + Vector3(cos(a) * 0.16 * s, (0.6 + rng.randf() * 0.5) * s, sin(a) * 0.16 * s), Color(0.1, 0.26 + rng.randf() * 0.1, 0.1))
		lm.scale = Vector3(1.0, 1.9, 0.45)
		lm.rotation = Vector3(rng.randf_range(-0.5, 0.5), a, rng.randf_range(-0.4, 0.4))
	_ao(pos, Vector2(0.8, 0.8) * s, 0.45)

func _leather_chair(pos: Vector3, face: float, col := Color(0.42, 0.22, 0.12)) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = face
	world.add_child(n)
	var lm := _tmat("res://assets/tex/leather.jpg", col, Vector2.ONE, col.lightened(0.6), 0.45)
	_mbox(Vector3(0.62, 0.4, 0.55), Vector3(0, 0.2, 0), lm, n)
	_mbox(Vector3(0.58, 0.12, 0.5), Vector3(0, 0.44, 0.02), lm, n)
	_mbox(Vector3(0.62, 0.62, 0.12), Vector3(0, 0.75, -0.24), lm, n)
	for sx in [-1.0, 1.0]:
		_mbox(Vector3(0.1, 0.24, 0.55), Vector3(sx * 0.31, 0.56, 0), lm, n)
	_ao(pos, Vector2(1.0, 1.0), 0.5)

func _rug(pos: Vector3, size: Vector2, col: Color) -> void:
	_mbox(Vector3(size.x, 0.012, size.y), pos + Vector3(0, 0.006, 0), _tmat("res://assets/tex/tex_carpet.jpg", col, size / 1.5, col.lightened(0.5), 1.0))

# ================================================================ setler (v0.21)

## Başkan / kulüp ofisi: imza ve yönetim toplantısı
func _set_office() -> void:
	_env(Color("#120d09"), Color("#7a6250"), 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_mbox(Vector3(10, 0.1, 9), Vector3(0, -0.05, 0), _wood(true))
	_mbox(Vector3(10, 4.2, 0.2), Vector3(0, 2.1, -2.4), _paint(Color(0.1, 0.12, 0.17), 0.26, Color(0.16, 0.09, 0.05), 0.0, 1.0))
	_mbox(Vector3(0.2, 4.2, 9), Vector3(-4.2, 2.1, 0), _paint(Color(0.1, 0.12, 0.17), 0.26, Color(0.16, 0.09, 0.05)))
	_mbox(Vector3(10, 0.2, 9), Vector3(0, 4.2, 0), _mat(Color(0.06, 0.06, 0.07)))
	# büyük pencere (stadyum manzarası)
	_window(Vector3(-0.3, 2.15, -2.28), Vector2(2.6, 1.9), "res://assets/tex/win_president.jpg", Color(0.08, 0.08, 0.09), "day")
	# kitaplık + kupa dolabı
	_books(Vector3(-3.0, 0, -2.08), 1.6, 2.6, rng)
	var cl := Game.my_club()
	var c1 := Color(cl.get("c1", "#b5121b"))
	var c2 := Color(cl.get("c2", "#ffffff"))
	var cab := _wood(true)
	_mbox(Vector3(1.2, 2.2, 0.45), Vector3(2.7, 1.1, -2.05), cab)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.85, 1.0, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	_mbox(Vector3(1.1, 1.2, 0.02), Vector3(2.7, 1.55, -1.81), glass)
	var gold := _mat(Color(0.95, 0.75, 0.25), 0.25, 1.0)
	for i in 3:
		var tp := Vector3(2.35 + i * 0.35, 1.0 + (i % 2) * 0.55, -2.0)
		_mbox(Vector3(1.0, 0.03, 0.38), Vector3(2.7, tp.y - 0.04, -2.0), cab)
		var cup := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.04
		cm.height = 0.2
		cup.mesh = cm
		cup.material_override = gold
		cup.position = tp + Vector3(0, 0.14, 0)
		world.add_child(cup)
		_cyl(0.025, 0.08, tp + Vector3(0, 0.03, 0), Color(0.95, 0.75, 0.25))
	_lamp(Vector3(2.7, 2.0, -1.6), Color("#ffe2a8"), 0.7, 1.8)
	# çerçeveli kulüp forması ve eski fotoğraflar
	_mbox(Vector3(0.9, 1.0, 0.04), Vector3(1.25, 2.35, -2.27), _mat(Color(0.05, 0.05, 0.05), 0.4))
	_mbox(Vector3(0.82, 0.92, 0.042), Vector3(1.25, 2.35, -2.268), _mat(Color(0.85, 0.83, 0.78), 0.9))
	_mbox(Vector3(0.36, 0.5, 0.05), Vector3(1.25, 2.31, -2.262), _mat(c1, 0.8))
	_mbox(Vector3(0.6, 0.14, 0.05), Vector3(1.25, 2.51, -2.262), _mat(c1, 0.8))
	_mbox(Vector3(0.36, 0.1, 0.052), Vector3(1.25, 2.3, -2.26), _mat(c2, 0.8))
	_frames(Vector3(-4.08, 2.4, -1.4), 3, rng, true)
	for f in world.get_children().slice(-9):
		pass
	# masa: maun, deri kaplama, isimlik, lamba
	var desk := _wood(true)
	_mbox(Vector3(0.95, 0.07, 1.9), Vector3(0.5, 0.76, 0), desk)
	_mbox(Vector3(0.06, 0.72, 1.85), Vector3(0.05, 0.38, 0), desk)
	_mbox(Vector3(0.85, 0.7, 0.06), Vector3(0.5, 0.38, -0.9), desk)
	_mbox(Vector3(0.85, 0.7, 0.06), Vector3(0.5, 0.38, 0.9), desk)
	_mbox(Vector3(0.6, 0.012, 1.1), Vector3(0.55, 0.8, 0), _tmat("res://assets/tex/leather.jpg", Color(0.3, 0.12, 0.08), Vector2.ONE, Color(0.85, 0.7, 0.62), 0.5))
	_mbox(Vector3(0.22, 0.02, 0.3), Vector3(0.35, 0.81, -0.3), _tmat("res://assets/tex/paper.jpg", Color(0.94, 0.9, 0.82)))
	_mbox(Vector3(0.22, 0.02, 0.3), Vector3(0.37, 0.82, -0.27), _tmat("res://assets/tex/manila.jpg", Color(0.86, 0.76, 0.52)))
	_mbox(Vector3(0.05, 0.06, 0.26), Vector3(0.12, 0.83, 0.45), gold)
	_cyl(0.06, 0.03, Vector3(0.75, 0.81, -0.62), Color(0.75, 0.6, 0.3))
	_box(Vector3(0.02, 0.38, 0.02), Vector3(0.75, 1.0, -0.62), Color(0.75, 0.6, 0.3))
	_cyl(0.05, 0.12, Vector3(0.68, 1.2, -0.62), Color(0.1, 0.3, 0.18), 0.12)
	_lamp(Vector3(0.6, 1.1, -0.55), Color("#ffd9a0"), 1.2, 2.5)
	_cyl(0.03, 0.12, Vector3(0.75, 0.86, 0.55), Color("#1a1a1a"))
	_ao(Vector3(0.5, 0, 0), Vector2(1.6, 2.6), 0.6)
	_rug(Vector3(0.4, 0, 0.2), Vector2(4.2, 3.2), Color(0.32, 0.08, 0.08))
	_plant(Vector3(-1.9, 0, -1.9), 1.2)
	_lamp(Vector3(0.3, 3.4, 0.6), Color("#ffe2b8"), 1.4, 6.0)
	_lamp(Vector3(-0.3, 2.0, -1.4), Color("#dfe9ff"), 0.9, 4.5)
	_sun(Vector3(-40, 30, 0), Color("#ffe8c8"), 0.5)
	_leather_chair(Vector3(1.75, 0, 0.0), -PI / 2.0, Color(0.18, 0.1, 0.07))
	_leather_chair(Vector3(-0.85, 0, 0.0), PI / 2.0)
	_ao(Vector3(0, 0, -2.25), Vector2(9.5, 0.7), 0.45)
	_ao(Vector3(-4.05, 0, 0), Vector2(0.7, 8.5), 0.45)
	cam_target["wide0"] = {"pos": Vector3(0.4, 1.6, 2.9), "look": Vector3(0.4, 1.0, -0.3)}

## Kahvehane / kafe
func _set_cafe() -> void:
	_env(Color("#1b120c"), Color("#806048"), 0.55)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	if _has("res://assets/tex/tex_cafe_tiles.jpg"):
		_mbox(Vector3(10, 0.1, 8), Vector3(0, -0.05, 0), _tmat("res://assets/tex/tex_cafe_tiles.jpg", Color.WHITE, Vector2(8, 6.5), Color(0.9, 0.88, 0.84), 0.5))
	else:
		var tm := _shm(HubS.TILE_SHADER)
		tm.set_shader_parameter("a", Vector3(0.62, 0.6, 0.55))
		tm.set_shader_parameter("b", Vector3(0.12, 0.11, 0.1))
		_mbox(Vector3(10, 0.1, 8), Vector3(0, -0.05, 0), tm)
	var wall_m: Material = _tmat("res://assets/tex/tex_brick.jpg", Color.WHITE, Vector2(5, 2), Color(0.95, 0.9, 0.85), 0.9) if _has("res://assets/tex/tex_brick.jpg") else _paint(Color(0.7, 0.55, 0.38), 0.25, Color(0.3, 0.18, 0.1), 0.6)
	_mbox(Vector3(10, 4, 0.2), Vector3(0, 2, -2.6), wall_m)
	_mbox(Vector3(0.2, 4, 8), Vector3(-3.4, 2, 0), _paint(Color(0.66, 0.52, 0.36), 0.28, Color(0.3, 0.18, 0.1), 0.5))
	_mbox(Vector3(10, 0.2, 8), Vector3(0, 4.0, 0), _mat(Color(0.2, 0.14, 0.1)))
	# vitrin penceresi: sokak
	_window(Vector3(0.9, 1.95, -2.48), Vector2(3.4, 1.7), "res://assets/tex/win_cafe.jpg", Color("#3a2416"), "dusk")
	# tezgâh, çay ocağı, ince belli bardaklar
	var wood := _wood(false)
	_mbox(Vector3(2.2, 1.05, 0.6), Vector3(-2.2, 0.52, -1.6), wood)
	_mbox(Vector3(2.3, 0.06, 0.68), Vector3(-2.2, 1.07, -1.6), _mat(Color(0.08, 0.07, 0.06), 0.25))
	var steel := _mat(Color(0.75, 0.75, 0.78), 0.25, 0.9)
	_cyl(0.16, 0.42, Vector3(-2.9, 1.31, -1.7), Color(0.75, 0.75, 0.78), 0.12)
	_cyl(0.13, 0.22, Vector3(-2.9, 1.63, -1.7), Color(0.78, 0.78, 0.8), 0.08)
	_mbox(Vector3(0.45, 0.4, 0.35), Vector3(-1.6, 1.3, -1.75), steel)
	var tea := StandardMaterial3D.new()
	tea.albedo_color = Color(0.55, 0.15, 0.05, 0.75)
	tea.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tea.roughness = 0.1
	for i in 7:
		var gm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.032
		cm.bottom_radius = 0.026
		cm.height = 0.09
		gm.mesh = cm
		gm.material_override = tea
		gm.position = Vector3(-2.6 + i * 0.12, 1.15, -1.45)
		world.add_child(gm)
	# raf: şişeler, kavanozlar
	_mbox(Vector3(2.4, 0.04, 0.25), Vector3(-2.2, 1.6, -2.38), wood)
	_mbox(Vector3(2.4, 0.04, 0.25), Vector3(-2.2, 2.1, -2.38), wood)
	var cols := [Color("#7d1d1d"), Color("#1d5c3a"), Color("#c49a2c"), Color("#2e4d7d"), Color("#a8c8d0")]
	for i in 9:
		_cyl(0.035, 0.24, Vector3(-3.1 + i * 0.2, 1.74, -2.38), cols[i % cols.size()])
		_cyl(0.05, 0.14, Vector3(-3.05 + i * 0.2, 2.19, -2.38), Color(0.85, 0.75, 0.55))
	# karatahta menü
	_mbox(Vector3(1.0, 0.7, 0.04), Vector3(-2.2, 2.8, -2.48), _mat(Color(0.08, 0.1, 0.09), 0.9))
	for i in 5:
		_box(Vector3(0.6 - (i % 2) * 0.15, 0.025, 0.01), Vector3(-2.25, 3.0 - i * 0.1, -2.455), Color(0.85, 0.85, 0.8))
	# eski futbol fotoğrafları
	_frames(Vector3(-3.28, 2.3, 0.6), 3, rng)
	# masa ve çay takımı
	_cyl(0.48, 0.04, Vector3(0, 0.74, 0), Color("#2b1b10"), -1.0)
	_cyl(0.05, 0.72, Vector3(0, 0.36, 0), Color("#1a1a1a"))
	_cyl(0.25, 0.03, Vector3(0, 0.015, 0), Color("#1a1a1a"))
	for pp in [Vector3(-0.18, 0.8, 0.08), Vector3(0.2, 0.8, -0.06)]:
		var gm2 := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.034
		cm2.bottom_radius = 0.026
		cm2.height = 0.1
		gm2.mesh = cm2
		gm2.material_override = tea
		gm2.position = pp
		world.add_child(gm2)
		_cyl(0.06, 0.008, pp - Vector3(0, 0.05, 0), Color("#e8e2d4"))
	_mbox(Vector3(0.16, 0.012, 0.22), Vector3(-0.05, 0.765, 0.18), _tmat("res://assets/tex/paper.jpg", Color(0.92, 0.88, 0.78)))
	_ao(Vector3(0, 0, 0), Vector2(1.6, 1.6), 0.55)
	# sarkıt lambalar
	for lx in [-1.6, 0.0, 1.6]:
		_cyl(0.18, 0.16, Vector3(lx, 2.55, 0.0), Color("#2a2a2a"), 0.06)
		_sphere(0.06, Vector3(lx, 2.45, 0.0), Color("#fff2c8"))
		_box(Vector3(0.01, 1.4, 0.01), Vector3(lx, 3.3, 0.0), Color("#111111"))
		_lamp(Vector3(lx, 2.35, 0.0), Color("#ffcf8a"), 1.6, 4.0)
	_lamp(Vector3(0.9, 1.9, -1.9), Color("#a8c0e8"), 0.6, 3.5)
	_sun(Vector3(-35, -150, 0), Color("#dfe9ff"), 0.5)
	for bx in [2.6, -1.0]:
		_cyl(0.42, 0.04, Vector3(bx, 0.74, -1.5), Color("#2b1b10"))
		_cyl(0.05, 0.72, Vector3(bx, 0.36, -1.5), Color("#1a1a1a"))
		_ao(Vector3(bx, 0, -1.5), Vector2(1.3, 1.3), 0.5)
	_plant(Vector3(3.6, 0, -2.2), 1.0)
	_chair(Vector3(-0.98, 0, 0.0), PI / 2.0, Color("#5a3a22"))
	_chair(Vector3(0.98, 0, 0.0), -PI / 2.0, Color("#5a3a22"))
	_ao(Vector3(0, 0, -2.45), Vector2(9.5, 0.7), 0.45)
	cam_target["wide0"] = {"pos": Vector3(0.2, 1.5, 2.7), "look": Vector3(0, 0.95, -0.2)}

## Otel / kulüp lobisi
func _set_lobby() -> void:
	_env(Color("#140f0c"), Color("#8a7058"), 0.55)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	if _has("res://assets/tex/tex_marble.jpg"):
		_mbox(Vector3(12, 0.1, 10), Vector3(0, -0.05, 0), _tmat("res://assets/tex/tex_marble.jpg", Color.WHITE, Vector2(6, 5), Color.WHITE, 0.2))
	else:
		var tm := _shm(HubS.TILE_SHADER)
		tm.set_shader_parameter("a", Vector3(0.78, 0.74, 0.66))
		tm.set_shader_parameter("b", Vector3(0.7, 0.66, 0.58))
		_mbox(Vector3(12, 0.1, 10), Vector3(0, -0.05, 0), tm)
	_mbox(Vector3(12, 4.5, 0.2), Vector3(0, 2.25, -3.0), _paint(Color(0.82, 0.76, 0.64), 0.3, Color(0.25, 0.14, 0.08)))
	_mbox(Vector3(12, 0.2, 10), Vector3(0, 4.5, 0), _mat(Color(0.85, 0.82, 0.75)))
	# kulüp tarihi duvarı (görsel varsa)
	if _has("res://assets/tex/wall_club_history.jpg"):
		var hm := StandardMaterial3D.new()
		hm.albedo_texture = load("res://assets/tex/wall_club_history.jpg")
		_quad(Vector2(3.6, 1.8), Vector3(0, 2.4, -2.88), hm)
	else:
		_frames(Vector3(-1.1, 2.4, -2.88), 5, rng, true)
	# iki yüksek pencere
	_window(Vector3(-3.8, 2.1, -2.88), Vector2(1.6, 2.6), "res://assets/tex/win_president.jpg", Color(0.15, 0.1, 0.06), "day")
	_window(Vector3(3.8, 2.1, -2.88), Vector2(1.6, 2.6), "res://assets/tex/win_president.jpg", Color(0.15, 0.1, 0.06), "day")
	# resepsiyon, avize ışıkları
	var wood := _wood(true)
	_mbox(Vector3(1.8, 1.05, 0.55), Vector3(4.2, 0.52, -2.1), wood)
	_mbox(Vector3(1.9, 0.05, 0.6), Vector3(4.2, 1.07, -2.1), _mat(Color(0.85, 0.82, 0.76), 0.2))
	_rug(Vector3(0, 0, 0), Vector2(3.6, 2.6), Color(0.45, 0.3, 0.15))
	_mbox(Vector3(0.9, 0.06, 0.55), Vector3(0, 0.42, 0), _mat(Color(0.08, 0.06, 0.05), 0.2))
	_mbox(Vector3(0.06, 0.4, 0.06), Vector3(0, 0.2, 0), _mat(Color(0.83, 0.68, 0.22), 0.3, 1.0))
	_cyl(0.06, 0.1, Vector3(0.2, 0.5, 0.1), Color(0.95, 0.95, 0.92))
	_plant(Vector3(-2.2, 0, -2.4), 1.3)
	_plant(Vector3(2.4, 0, -2.5), 1.1)
	for cx in [-1.5, 1.5]:
		_cyl(0.3, 0.05, Vector3(cx, 3.6, 0.3), Color(0.83, 0.68, 0.22))
		_sphere(0.1, Vector3(cx, 3.5, 0.3), Color(1.0, 0.92, 0.75))
		_lamp(Vector3(cx, 3.3, 0.3), Color("#ffe2b8"), 1.1, 5.5)
	_lamp(Vector3(0, 2.3, -2.2), Color("#ffd9a0"), 0.7, 3.5)
	_sun(Vector3(-40, -160, 0), Color("#f0f4ff"), 0.55)
	_leather_chair(Vector3(-1.0, 0, 0.0), PI / 2.0, Color(0.45, 0.25, 0.12))
	_leather_chair(Vector3(1.0, 0, 0.0), -PI / 2.0, Color(0.45, 0.25, 0.12))
	_ao(Vector3(0, 0, -2.85), Vector2(11.5, 0.7), 0.4)
	cam_target["wide0"] = {"pos": Vector3(0.2, 1.75, 3.7), "look": Vector3(0, 0.85, -0.2)}

## Ev ziyareti: oturma odası (genç oyuncunun ailesi), akşam
func _set_home() -> void:
	_env(Color("#120e0b"), Color("#8a7058"), 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	_mbox(Vector3(10, 0.1, 9), Vector3(0, -0.05, 0), _wood(false))
	_mbox(Vector3(10, 3.4, 0.2), Vector3(0, 1.7, -2.6), _paint(Color(0.78, 0.68, 0.5), 0.0, Color.BLACK, 0.4))
	_mbox(Vector3(0.2, 3.4, 9), Vector3(-3.6, 1.7, 0), _paint(Color(0.72, 0.62, 0.46), 0.0, Color.BLACK, 0.4))
	_mbox(Vector3(10, 0.2, 9), Vector3(0, 3.4, 0), _mat(Color(0.82, 0.78, 0.7)))
	# pencere + perdeler (gece mahalle)
	_window(Vector3(-0.6, 1.8, -2.48), Vector2(1.6, 1.3), "res://assets/tex/win_home.jpg", Color(0.9, 0.88, 0.84), "night")
	var curtain := _mat(Color(0.55, 0.18, 0.12), 0.95)
	for sx in [-1.0, 1.0]:
		var c := _mbox(Vector3(0.45, 2.0, 0.06), Vector3(-0.6 + sx * 1.05, 1.6, -2.4), curtain)
		c.rotation_degrees.y = sx * 4.0
	_box(Vector3(2.8, 0.04, 0.04), Vector3(-0.6, 2.62, -2.38), Color(0.6, 0.5, 0.3))
	_rug(Vector3(0, 0, 0), Vector2(3.0, 2.2), Color(0.5, 0.15, 0.12))
	_mbox(Vector3(1.0, 0.06, 0.55), Vector3(0, 0.4, 0), _wood(true))
	_ao(Vector3(0, 0, 0), Vector2(1.4, 0.9), 0.45)
	# çay takımı ve tabak
	_cyl(0.05, 0.1, Vector3(-0.2, 0.48, 0.05), Color("#c84a2a"))
	_cyl(0.05, 0.1, Vector3(0.2, 0.48, -0.05), Color("#c84a2a"))
	_cyl(0.16, 0.02, Vector3(0.0, 0.44, 0.12), Color(0.92, 0.9, 0.84))
	for i in 5:
		_sphere(0.025, Vector3(-0.05 + (i % 3) * 0.04, 0.47, 0.1 + (i / 3) * 0.04), Color(0.7, 0.45, 0.2))
	# kanepe (kumaş)
	var sofa := _mat(Color(0.35, 0.42, 0.25), 0.95)
	_mbox(Vector3(0.75, 0.42, 1.9), Vector3(1.55, 0.21, 0.0), sofa)
	_mbox(Vector3(0.22, 0.6, 1.9), Vector3(1.95, 0.6, 0.0), sofa)
	for sz in [-1.0, 1.0]:
		_mbox(Vector3(0.75, 0.55, 0.18), Vector3(1.55, 0.35, sz * 0.95), sofa)
	_box(Vector3(0.35, 0.3, 0.12), Vector3(1.75, 0.6, -0.6), Color(0.85, 0.7, 0.35))
	_ao(Vector3(1.6, 0, 0), Vector2(1.2, 2.4), 0.5)
	# TV ünitesi
	_mbox(Vector3(1.6, 0.5, 0.4), Vector3(-2.3, 0.25, -2.3), _wood(true))
	_box(Vector3(1.1, 0.62, 0.05), Vector3(-2.3, 0.85, -2.35), Color("#0a0a0a"), 0.2)
	var tvm := StandardMaterial3D.new()
	tvm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tvm.albedo_texture = load("res://assets/tex/grass.jpg")
	tvm.albedo_color = Color(0.7, 0.8, 0.7)
	_quad(Vector2(1.02, 0.56), Vector3(-2.3, 0.85, -2.32), tvm)
	_lamp(Vector3(-2.3, 0.9, -1.8), Color("#7fb0ff"), 0.5, 2.5)
	# duvarda aile fotoğrafları, çocukluk forması, madalyalar
	_frames(Vector3(0.6, 2.0, -2.48), 4, rng)
	var cl := Game.my_club()
	_mbox(Vector3(0.6, 0.7, 0.02), Vector3(3.0, 1.8, -2.48), _mat(Color("#b5121b"), 0.9))
	_mbox(Vector3(0.66, 0.76, 0.015), Vector3(3.0, 1.8, -2.49), _mat(Color(0.1, 0.07, 0.05)))
	# köşede eski top ve krampon
	_sphere(0.11, Vector3(-3.2, 0.11, -1.8), Color(0.93, 0.92, 0.88))
	_box(Vector3(0.12, 0.08, 0.28), Vector3(-3.0, 0.04, -2.1), Color(0.1, 0.1, 0.1))
	_plant(Vector3(-3.1, 0, 0.8), 0.9)
	# abajur
	_cyl(0.02, 1.4, Vector3(2.6, 0.7, -1.9), Color(0.5, 0.4, 0.25))
	_cyl(0.25, 0.3, Vector3(2.6, 1.5, -1.9), Color(0.95, 0.85, 0.65), 0.15)
	_lamp(Vector3(2.6, 1.4, -1.7), Color("#ffcf8a"), 1.0, 3.5)
	_lamp(Vector3(-0.5, 2.6, 0.8), Color("#ffd9a0"), 1.3, 6.0)
	_sun(Vector3(-35, -150, 0), Color("#a8b8e0"), 0.3)
	_chair(Vector3(-1.0, 0, 0.0), PI / 2.0, Color("#6b3a22"), true)
	_ao(Vector3(0, 0, -2.45), Vector2(9.5, 0.7), 0.45)
	cam_target["wide0"] = {"pos": Vector3(0.3, 1.7, 3.6), "look": Vector3(0.3, 0.85, -0.2)}

## Telefon: solda scout ofisi, sağda arayan kişi (antrenman sahası kenarı)
func _set_phone() -> void:
	# sağ taraf: gerçek tesis sahası (stadyum sistemi, küçük ölçek)
	var st = StadS.new()
	st.position = Vector3(40, 0, 0)
	world.add_child(st)
	st.configure(3, "day", "clear")
	st.build(Color("#2f6b3a"), Color("#ffffff"), Color("#b5121b"), false, shadows)
	# sol: scout ofisi
	_mbox(Vector3(6, 0.1, 6), Vector3(0, -0.05, 0), _wood(false))
	_mbox(Vector3(6, 3.5, 0.2), Vector3(0, 1.75, -1.8), _paint(Color(0.1, 0.2, 0.15), 0.3))
	_window(Vector3(1.6, 1.75, -1.68), Vector2(1.2, 1.0), "", Color(0.1, 0.1, 0.11), "night")
	var desk := _wood(false)
	_mbox(Vector3(1.4, 0.06, 0.7), Vector3(0, 0.75, -0.6), desk)
	_mbox(Vector3(1.35, 0.7, 0.05), Vector3(0, 0.37, -0.92), desk)
	_box(Vector3(0.5, 0.32, 0.03), Vector3(-0.3, 1.0, -0.85), Color("#111111"), 0.2)
	_glow_quad(Vector2(0.46, 0.28), Vector3(-0.3, 1.0, -0.83), 0.0, Color("#6fa0c8"), 1.0)
	_mbox(Vector3(0.25, 0.02, 0.32), Vector3(0.3, 0.79, -0.5), _tmat("res://assets/tex/manila.jpg", Color(0.86, 0.76, 0.52)))
	_mbox(Vector3(1.2, 0.7, 0.04), Vector3(-1.4, 1.9, -1.68), _tmat("res://assets/tex/cork.jpg", Color(0.6, 0.45, 0.3)))
	_ao(Vector3(0, 0, -0.6), Vector2(1.8, 1.2), 0.5)
	_lamp(Vector3(0.4, 2.2, 0.3), Color("#ffd9a0"), 1.3, 4.0)
	_chair(Vector3(0, 0, 0.05), PI, Color("#3a2416"))
	cam_target["wide0"] = {"pos": Vector3(0.55, 1.4, -1.45), "look": Vector3(0, 1.15, -0.25)}
	cam_target["wide1"] = {"pos": Vector3(41.0, 1.6, 2.2), "look": Vector3(40, 1.3, 0)}

## Video odası: karanlık analiz odası, büyük ekran
func _set_video() -> void:
	_env(Color("#07090c"), Color("#4a5a70"), 0.4)
	_mbox(Vector3(8, 0.1, 8), Vector3(0, -0.05, 0), _tmat("res://assets/tex/tex_carpet.jpg", Color(0.14, 0.15, 0.18), Vector2(4, 4), Color(0.4, 0.42, 0.5), 1.0))
	_mbox(Vector3(8, 3.4, 0.2), Vector3(0, 1.7, -2.4), _paint(Color(0.08, 0.09, 0.11), 0.0, Color.BLACK, 0.0, 1.0))
	_mbox(Vector3(0.2, 3.4, 8), Vector3(-3.0, 1.7, 0), _paint(Color(0.08, 0.09, 0.11)))
	# büyük ekran: maç görüntüsü (çim + oyuncu noktaları)
	var scr := _shm("""shader_type spatial;
render_mode unshaded;
uniform sampler2D grass : source_color, filter_linear_mipmap, repeat_enable;
float h(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 c = texture(grass, vec2(uv.x * 2.5, uv.y * 1.2)).rgb * 0.75;
	float line = step(abs(uv.x - 0.5), 0.003) + step(abs(length((uv - 0.5) * vec2(1.6, 1.0)) - 0.12), 0.004);
	c = mix(c, vec3(0.9), clamp(line, 0.0, 1.0) * 0.8);
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		vec2 p = vec2(0.5 + 0.38 * sin(TIME * (0.15 + h(fi) * 0.2) + fi * 1.7), 0.5 + 0.35 * cos(TIME * (0.12 + h(fi + 3.0) * 0.2) + fi));
		float d = length((uv - p) * vec2(1.6, 1.0));
		vec3 tc = i < 7 ? vec3(0.9, 0.2, 0.15) : vec3(0.95);
		c = mix(c, tc, 1.0 - smoothstep(0.008, 0.012, d));
	}
	float scan = 0.92 + 0.08 * sin(uv.y * 500.0);
	ALBEDO = c * scan * 1.3;
}""")
	scr.set_shader_parameter("grass", load("res://assets/tex/grass.jpg"))
	_mbox(Vector3(3.3, 1.9, 0.08), Vector3(0, 1.75, -2.26), _mat(Color(0.02, 0.02, 0.02), 0.3))
	_quad(Vector2(3.1, 1.74), Vector3(0, 1.75, -2.21), scr)
	_lamp(Vector3(0, 1.6, -1.5), Color("#9fd0a8"), 0.9, 4.0)
	# masa, iki monitör, not defteri
	var desk := _mat(Color(0.12, 0.12, 0.13), 0.4, 0.3)
	_mbox(Vector3(2.4, 0.06, 0.8), Vector3(0, 0.75, -0.9), desk)
	for sx in [-1.0, 1.0]:
		_mbox(Vector3(0.06, 0.72, 0.75), Vector3(sx * 1.15, 0.37, -0.9), desk)
		_box(Vector3(0.6, 0.36, 0.03), Vector3(sx * 0.45, 1.05, -1.15), Color("#0b0b0b"), 0.2)
		_glow_quad(Vector2(0.56, 0.32), Vector3(sx * 0.45, 1.05, -1.13), 0.0, Color("#3a7a5a") if sx < 0 else Color("#5a6a9a"), 0.9)
	_mbox(Vector3(0.22, 0.02, 0.3), Vector3(0.1, 0.79, -0.7), _tmat("res://assets/tex/paper.jpg", Color(0.94, 0.9, 0.82)))
	_ao(Vector3(0, 0, -0.9), Vector2(2.8, 1.3), 0.5)
	# jaluzili yan pencere: dışarıdan ince ışık
	_window(Vector3(-2.88, 1.8, 0.4), Vector2(1.4, 1.1), "", Color(0.2, 0.2, 0.22), "night", PI / 2.0)
	var slat := _mat(Color(0.75, 0.74, 0.7), 0.6)
	for i in 8:
		_mbox(Vector3(0.07, 0.02, 1.5), Vector3(-2.8, 2.3 - i * 0.12, 0.4), slat, null, Vector3(0, 0, 35))
	_lamp(Vector3(1.2, 2.8, 0.8), Color("#ffd9a0"), 0.6, 4.0)
	_sun(Vector3(-40, 30, 0), Color("#a8b8e0"), 0.25)
	_chair(Vector3(0, 0, 0.1), PI, Color("#222222"))
	cam_target["wide0"] = {"pos": Vector3(0.9, 1.5, 2.4), "look": Vector3(0, 1.3, -1.6)}

# ---- tesis panoraması (Gemini) ve yıpranmış çim ----
func _training_panorama(cond: Dictionary) -> void:
	if not _has("res://assets/tex/bg_training_panorama.jpg"):
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 230.0
	cm.bottom_radius = 230.0
	cm.height = 120.0
	cm.radial_segments = 48
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	mi.position = Vector3(0, 57.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := _shm("""shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
uniform sampler2D pano : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0);
uniform vec3 haze = vec3(0.7, 0.78, 0.88);
uniform float haze_k = 0.25;
uniform float sat = 1.0;
void fragment() {
	float t = UV.x * 3.0;
	float u = 1.0 - abs(mod(t, 2.0) - 1.0);
	vec3 c = texture(pano, vec2(u, UV.y)).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat) * tint;
	// ufka yakın kısım sisle karışsın, sahne ile uyumlu dursun
	float h = smoothstep(0.35, 1.0, UV.y);
	c = mix(c, haze, haze_k * (0.4 + 0.6 * h));
	ALBEDO = c;
}""")
	m.set_shader_parameter("pano", load("res://assets/tex/bg_training_panorama.jpg"))
	var tod: String = cond.get("tod", "day")
	var w: String = cond.get("weather", "clear")
	var tint: Vector3 = {"day": Vector3(1.0, 1.0, 1.0), "dusk": Vector3(0.95, 0.78, 0.7), "night": Vector3(0.1, 0.12, 0.18)}.get(tod, Vector3.ONE)
	var haze: Vector3 = {"day": Vector3(0.7, 0.78, 0.88), "dusk": Vector3(0.55, 0.45, 0.45), "night": Vector3(0.05, 0.06, 0.09)}.get(tod, Vector3(0.7, 0.78, 0.88))
	var hk := 0.22
	var sat := 1.0
	if w == "rain":
		tint *= 0.75
		hk = 0.5
		sat = 0.55
		haze = haze.lerp(Vector3(0.5, 0.52, 0.56) if tod == "day" else Vector3(0.12, 0.13, 0.15), 0.6)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("haze", haze)
	m.set_shader_parameter("haze_k", hk)
	m.set_shader_parameter("sat", sat)
	mi.material_override = m
	world.add_child(mi)

func _worn_patch(pos: Vector3, size: Vector2) -> void:
	if not _has("res://assets/tex/tex_turf_worn.jpg"):
		return
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = size
	mi.mesh = q
	mi.position = pos + Vector3(0, 0.015, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := _shm("""shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D turf : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 rep = vec2(1.0);
void fragment() {
	vec3 c = texture(turf, UV * rep).rgb;
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(0.45, 1.0, max(d.x * d.x + d.y * d.y, 0.0));
	float n = texture(turf, UV * rep * 0.37 + 0.21).g;
	ALBEDO = c * 0.95;
	ROUGHNESS = 0.95;
	ALPHA = clamp(edge * (0.55 + n * 0.6), 0.0, 0.85);
}""")
	m.set_shader_parameter("turf", load("res://assets/tex/tex_turf_worn.jpg"))
	m.set_shader_parameter("rep", size / 6.0)
	mi.material_override = m
	world.add_child(mi)
