extends Node3D
## Mocap animasyonlu futbolcu (Quaternius manken + Rohr/UAL hareketleri).
## API human.gd ile aynı: build / play / tick / is_busy / pose_state / set_pose_state.

const SKIN := [Color("#f1c9a5"), Color("#e0ac85"), Color("#c68863"), Color("#8d5a3b"), Color("#5a3825")]
const HAIR := [Color("#1b1410"), Color("#2c1d14"), Color("#4a3020"), Color("#0e0b0a"), Color("#8a5a2b"), Color("#c9a45c")]
const BONES := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
# yürüyüş karışımı: klip, doğal hız (m/s)
const LOCO := [["idle", 0.0], ["walk", 1.5], ["jog", 3.6], ["sprint", 6.6]]
# motor eylem adı -> [klip, başlangıç (sn), yumuşak giriş, yumuşak çıkış]
const ACT := {
	"kick": [["pass", 0.36], ["pass_m", 0.36]],
	"shot": [["shot", 0.38], ["shot_r2", 0.38], ["shot_m", 0.38]],
	"header": [["header", 0.05]],
	"tackle": [["tackle", 0.35]],
	"slide": [["slide", 0.0]],
	"dive": [["dive", 0.12]],
	"dive_m": [["dive_m", 0.12]],
	"save_low": [["save_low", 0.3], ["save_low_m", 0.3]],
	"celebrate": [["celebrate", 0.0], ["celebrate2", 0.0], ["dance", 0.0]],
	"knee_slide": [["knee_slide", 0.0]],
	"throw": [["throw", 1.75]],
	"fall": [["fall", 0.0]],
	"card": [["card", 0.0]],
}

static var LIB: AnimationLibrary
static var SCN: PackedScene
static var CL := {}         # klip adı -> {"a": Animation, "r": PackedInt32Array, "p": int, "len": float}
static var _mats := {}

static func _load() -> void:
	if LIB != null:
		return
	LIB = load("res://assets/man/anims.res")
	SCN = load("res://assets/man/man.scn")
	for nm in LIB.get_animation_list():
		var a: Animation = LIB.get_animation(nm)
		var r := PackedInt32Array()
		for b in BONES:
			r.append(a.find_track(NodePath("S:" + b), Animation.TYPE_ROTATION_3D))
		CL[nm] = {"a": a, "r": r, "p": a.find_track(NodePath("S:pelvis"), Animation.TYPE_POSITION_3D), "len": a.length, "loop": a.loop_mode != Animation.LOOP_NONE}

static func make_mat(col: Color, rough := 0.65) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m

static func kit_mats(shirt: Color, shorts: Color, socks: Color) -> Dictionary:
	return {"shirt": make_mat(shirt), "shorts": make_mat(shorts), "socks": make_mat(socks), "boot": make_mat(Color(0.06, 0.06, 0.07))}

static func _mat(shirt: Color, shorts: Color, socks: Color, skin: Color, hair: Color, hs := 1) -> ShaderMaterial:
	var key := "%s%s%s%s%s%d" % [shirt.to_html(), shorts.to_html(), socks.to_html(), skin.to_html(), hair.to_html(), hs]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://assets/man/kit.gdshader")
		m.set_shader_parameter("c_shirt", shirt)
		m.set_shader_parameter("c_shorts", shorts)
		m.set_shader_parameter("c_socks", socks)
		m.set_shader_parameter("c_skin", skin)
		m.set_shader_parameter("c_hair", hair)
		m.set_shader_parameter("c_boots", Color(0.07, 0.07, 0.08))
		# saç stili: 0 kısa, 1 normal, 2 uzun
		m.set_shader_parameter("hair_top", [1.745, 1.715, 1.705][hs])
		m.set_shader_parameter("hair_back", [1.64, 1.585, 1.53][hs])
		_mats[key] = m
	return _mats[key]

var skel: Skeleton3D
var mesh_inst: MeshInstance3D
var number_lbl: Label3D
var bid := PackedInt32Array()
var pel_rest := Vector3.ZERO

var phase := 0.0          # yürüyüş döngüsü (0..1)
var idle_t := 0.0
var speed := 0.0
var action := ""          # motor adı (dive kontrolü için)
var act_clip := ""
var action_t := 0.0
var action_dur := 0.5
var act_start := 0.0
var action_side := 1.0
var base := ""            # sabit döngü (sahneler: talk, juggle, crouch...)
var mirror_seed := 0
var gk := false

func build(kit: Dictionary, skin_i: int, hair_i: int, style: int, number: int, font: Font = null) -> void:
	_load()
	var shirt: Color = kit.shirt.albedo_color
	var shorts: Color = kit.shorts.albedo_color
	var socks: Color = kit.socks.albedo_color
	var inst: Node3D = SCN.instantiate()
	add_child(inst)
	skel = inst.get_node("S")
	mesh_inst = skel.get_node("M")
	mesh_inst.material_override = _mat(shirt, shorts, socks, SKIN[clampi(skin_i, 0, 4)], HAIR[clampi(hair_i, 0, 5)], posmod(style, 3))
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for b in BONES:
		bid.append(skel.find_bone(b))
	pel_rest = skel.get_bone_rest(skel.find_bone("pelvis")).origin
	mirror_seed = style
	idle_t = float(style % 17) * 0.13
	phase = float(style % 7) / 7.0
	var att := BoneAttachment3D.new()
	att.bone_name = "spine_03"
	skel.add_child(att)
	number_lbl = Label3D.new()
	number_lbl.text = str(number)
	number_lbl.font_size = 96
	number_lbl.pixel_size = 0.0024
	number_lbl.modulate = Color(1, 1, 1) if shirt.get_luminance() < 0.55 else Color(0.08, 0.08, 0.1)
	number_lbl.double_sided = false
	if font:
		number_lbl.font = font
	att.add_child(number_lbl)
	# kemik ekseninden bağımsız: sırt yönüne yerleştir (global)
	number_lbl.top_level = false
	_place_number(att)
	tick(0.0, 0.0)

func _place_number(att: BoneAttachment3D) -> void:
	# spine_03 global rest -> sırt (-Z) tarafına, dışa bakan etiket
	var g := skel.get_bone_global_rest(skel.find_bone("spine_03"))
	var want := Transform3D(Basis(Vector3.UP, PI), Vector3(0, g.origin.y - 0.06, g.origin.z - 0.13))
	number_lbl.transform = g.affine_inverse() * want

func set_base(clip: String) -> void:
	base = clip if CL.has(clip) else ""
	idle_t = 0.0

func play(name: String, dur := 0.5, side := 1.0) -> void:
	var key := name
	if name == "dive":
		key = "dive_m" if side > 0.0 else "dive"
	if not ACT.has(key):
		return
	if action == "throw" and action_t < 0.9 and name in ["kick", "shot"]:
		return
	var opts: Array = ACT[key]
	var pick: Array = opts[(mirror_seed + int(Time.get_ticks_msec() / 997)) % opts.size()] if name in ["celebrate"] else opts[mirror_seed % opts.size()]
	if not CL.has(pick[0]):
		return
	action = name
	act_clip = pick[0]
	act_start = pick[1]
	action_t = 0.0
	action_side = side
	action_dur = CL[act_clip].len - act_start
	if name in ["celebrate", "knee_slide"]:
		action_dur = maxf(action_dur, dur)

func is_busy() -> bool:
	return action != "" and action_t < action_dur

func tick(delta: float, spd: float, anim_speed := 1.0) -> void:
	speed = spd
	idle_t += delta * anim_speed
	# yürüyüş fazı: iki komşu klibin döngü sürelerinin karışımıyla ilerler
	var i := 0
	while i < LOCO.size() - 2 and spd > LOCO[i + 1][1]:
		i += 1
	var lo: Array = LOCO[i]
	var hi: Array = LOCO[i + 1]
	var w := clampf((spd - lo[1]) / (hi[1] - lo[1]), 0.0, 1.0)
	var la: float = CL[lo[0]].len
	var lb: float = CL[hi[0]].len
	var cyc := lerpf(la if i > 0 else lb, lb, w)
	var over := maxf(1.0, spd / LOCO[-1][1])
	phase = fposmod(phase + delta * anim_speed * over / maxf(0.3, cyc), 1.0)
	if action != "":
		action_t += delta * anim_speed
		if action_t >= action_dur + 0.25:
			action = ""
	_apply(lo[0], hi[0], w)

func _sample_loop(c: Dictionary, t: float, k: int) -> Quaternion:
	var a: Animation = c.a
	return a.rotation_track_interpolate(c.r[k], t)

func _apply(ca: String, cb: String, w: float) -> void:
	if skel == null:
		return
	var A: Dictionary = CL[ca]
	var Bc: Dictionary = CL[cb]
	var ta: float = idle_t if ca == "idle" else phase * float(A.len)
	var tb: float = phase * float(Bc.len)
	if ca == "idle":
		ta = fposmod(idle_t, float(A.len))
	var bs: Dictionary = CL[base] if base != "" else {}
	var tbase: float = fposmod(idle_t, float(bs.len)) if base != "" else 0.0
	var X: Dictionary = CL[act_clip] if action != "" and act_clip != "" else {}
	var tx := 0.0
	var wx := 0.0
	if not X.is_empty():
		tx = minf(act_start + action_t, X.len)
		wx = clampf(action_t / 0.1, 0.0, 1.0) * clampf((action_dur + 0.25 - action_t) / 0.25, 0.0, 1.0)
	var aA: Animation = A.a
	var aB: Animation = Bc.a
	for k in BONES.size():
		var q: Quaternion
		if base != "":
			q = (bs.a as Animation).rotation_track_interpolate(bs.r[k], tbase)
		else:
			q = aA.rotation_track_interpolate(A.r[k], ta)
			if w > 0.001:
				q = q.slerp(aB.rotation_track_interpolate(Bc.r[k], tb), w)
		if wx > 0.001:
			q = q.slerp((X.a as Animation).rotation_track_interpolate(X.r[k], tx), wx)
		skel.set_bone_pose_rotation(bid[k], q)
	var p: Vector3
	if base != "":
		p = (bs.a as Animation).position_track_interpolate(bs.p, tbase)
	else:
		p = aA.position_track_interpolate(A.p, ta)
		if w > 0.001:
			p = p.lerp(aB.position_track_interpolate(Bc.p, tb), w)
	if wx > 0.001:
		p = p.lerp((X.a as Animation).position_track_interpolate(X.p, tx), wx)
	skel.set_bone_pose_position(bid[0], p)
	# dalışta gövdeyi yana yatır (klip yana sıçrama; yatay uçuş hissi)
	var roll := 0.0
	if wx > 0.001 and action == "dive":
		var f := clampf((action_t - 0.08) / 0.75, 0.0, 1.0)
		roll = sin(f * PI) * 1.05 * wx * (-1.0 if act_clip == "dive" else 1.0)
	var inst := skel.get_parent() as Node3D
	if absf(roll) > 0.001 or inst.transform != Transform3D.IDENTITY:
		var pv := Vector3(p.x, 0.0, 0.0)
		var rest_root := skel.get_bone_global_rest(0)
		pv = rest_root * p
		pv.y = 0.85
		inst.transform = Transform3D(Basis(), pv) * Transform3D(Basis(Vector3.BACK, roll), Vector3.ZERO) * Transform3D(Basis(), -pv)

func pose_state() -> Array:
	return [phase, speed, action, action_t, action_dur, action_side, act_clip, act_start, idle_t]

func set_pose_state(st: Array) -> void:
	phase = st[0]
	speed = st[1]
	action = st[2]
	action_t = st[3]
	action_dur = st[4]
	action_side = st[5]
	act_clip = st[6]
	act_start = st[7]
	idle_t = st[8]
	tick(0.0, speed)
