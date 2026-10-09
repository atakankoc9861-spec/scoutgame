extends Node3D
## Mocap animasyonlu futbolcu (Quaternius manken + Rohr/UAL hareketleri).
## API human.gd ile aynı: build / play / tick / is_busy / pose_state / set_pose_state.

const SKIN := [Color(0.84, 0.66, 0.56), Color(0.76, 0.56, 0.44), Color(0.62, 0.44, 0.32), Color(0.44, 0.3, 0.21), Color(0.3, 0.2, 0.14)]
const HAIR := [Color("#16110d"), Color("#2a1b12"), Color("#4a3020"), Color("#0b0908"), Color("#7a5230"), Color("#b8945a")]
const BONES := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
# yürüyüş karışımı: klip, doğal hız (m/s)
const LOCO := [["idle", 0.0], ["walk", 1.5], ["jog", 3.6], ["sprint", 6.6]]
# motor eylem adı -> [klip, başlangıç (sn)]
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
## Saç modelleri (Blender üretimi, MakeHuman CC0); "" = kazınmış (sadece cilt dokusu)
const HAIRS := ["HairCrop", "HairFade", "HairQuiff", "HairCurly", "HairAfro", ""]
const MORPHS := ["muscle", "lean", "heavy", "thin", "young", "old", "african", "asian",
	"nose_wide", "nose_long", "chin", "jaw", "oval", "cheeks", "mouth", "brow"]

const T_DET := preload("res://assets/mh/skin_detail.png")
const T_DET2 := preload("res://assets/mh/skin_detail2.png")
const SH_SKIN := preload("res://assets/mh/skin.gdshader")
const SH_EYE := preload("res://assets/mh/eye.gdshader")
const SH_HAIR := preload("res://assets/mh/hair.gdshader")
const SH_CLOTH := preload("res://assets/mh/cloth.gdshader")

static var LIB: AnimationLibrary
static var SCN: PackedScene
static var CL := {}         # klip adı -> {"a": Animation, "r": PackedInt32Array, "p": int, "len": float}
static var _mats := {}

static func _load() -> void:
	if LIB != null:
		return
	LIB = load("res://assets/mh/anims.res")
	SCN = load("res://assets/mh/player.glb")
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

static func _cloth(c1: Color, c2 := Color.WHITE, pattern := 0, rough := 0.82) -> ShaderMaterial:
	var key := "c%s%s%d%.2f" % [c1.to_html(), c2.to_html(), pattern, rough]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SH_CLOTH
		m.set_shader_parameter("c1", c1)
		m.set_shader_parameter("c2", c2)
		m.set_shader_parameter("pattern", pattern)
		m.set_shader_parameter("rough", rough)
		_mats[key] = m
	return _mats[key]

static func _skin(skin: Color, hair: Color, beard: float, scalp: float) -> ShaderMaterial:
	var key := "s%s%s%.2f%.2f" % [skin.to_html(), hair.to_html(), beard, scalp]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SH_SKIN
		m.set_shader_parameter("detail", T_DET)
		m.set_shader_parameter("detail2", T_DET2)
		m.set_shader_parameter("skin", skin)
		m.set_shader_parameter("hair_col", hair)
		m.set_shader_parameter("beard", beard)
		m.set_shader_parameter("scalp_amt", scalp)
		_mats[key] = m
	return _mats[key]

static func _hairmat(hair: Color) -> ShaderMaterial:
	var key := "h" + hair.to_html()
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SH_HAIR
		m.set_shader_parameter("hair_col", hair)
		m.set_shader_parameter("detail", T_DET)
		_mats[key] = m
	return _mats[key]

static func _eyemat(iris: Color) -> ShaderMaterial:
	var key := "e" + iris.to_html()
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SH_EYE
		m.set_shader_parameter("iris", iris)
		_mats[key] = m
	return _mats[key]

var skel: Skeleton3D
var mesh_inst: MeshInstance3D      # gövde (eski API uyumu)
var parts := {}                    # parça adı -> MeshInstance3D
var number_lbl: Label3D
var bid := PackedInt32Array()
var pel_rest := Vector3.ZERO
var lod := false                   # maçta hafif modeller (kurulumdan önce ayarlanır)
var look := {}                     # morph ağırlıkları (apply_look ile özelliklerden)

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
var overlay := ""          # kol kaplaması: phone / notebook / arms_crossed
var overlay_w := 0.0
var _last_overlay := ""
var nod_t := -1.0          # baş sallama zamanlayıcı
var head_yaw := 0.0        # başı sağa-sola çevir (rad)
var _head_yaw_cur := 0.0
var _inst: Node3D
const ARM_R := [11, 12, 13]
const ARM_L := [7, 8, 9]

## Kişiye özel görünüm: tohumdan (yüz) + isteğe bağlı oyuncu verisinden (yaş, güç, hız)
static func look_for(style: int, skin_i: int, p: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(style * 7919 + 13)
	var L := {}
	for f in ["nose_wide", "nose_long", "chin", "jaw", "oval", "cheeks", "mouth", "brow"]:
		L[f] = clampf(rng.randfn(0.0, 0.45), -0.6, 1.0)
	var sk := clampi(skin_i, 0, 4)
	if sk >= 3:
		L["african"] = rng.randf_range(0.6, 1.0)
	elif sk == 2:
		L["african"] = rng.randf_range(0.0, 0.35)
		L["asian"] = rng.randf_range(0.0, 0.3) if rng.randf() < 0.4 else 0.0
	L["muscle"] = rng.randf_range(0.0, 0.6)
	L["thin"] = rng.randf_range(0.0, 0.4)
	var hs := rng.randf_range(0.96, 1.04)
	if not p.is_empty():
		var a: Dictionary = p.get("attrs", {})
		var stg := float(a.get("strength", 10))
		var pac := float(a.get("pace", 10))
		L["muscle"] = clampf((stg - 9.0) / 8.0, 0.0, 1.0)
		L["lean"] = clampf((9.0 - stg) / 7.0, 0.0, 0.8)
		L["thin"] = clampf((pac - 11.0) / 8.0, 0.0, 0.7)
		L["heavy"] = clampf((stg - pac - 3.0) / 10.0, 0.0, 0.6)
		var age := float(p.get("age", 24))
		L["young"] = clampf((22.0 - age) / 5.0, 0.0, 1.0)
		L["old"] = clampf((age - 29.0) / 7.0, 0.0, 1.0)
		var pos: String = p.get("pos", "CM")
		if pos in ["GK", "CB"]:
			hs += 0.035
		elif pos in ["LW", "RW", "AM"]:
			hs -= 0.025
		hs += (stg - 10.0) * 0.004
	L["_h"] = clampf(hs, 0.9, 1.1)
	return L

func build(kit: Dictionary, skin_i: int, hair_i: int, style: int, number: int, font: Font = null) -> void:
	_build(kit, skin_i, hair_i, style, number, font, false, {})

func _build(kit: Dictionary, skin_i: int, hair_i: int, style: int, number: int, font: Font, outfit: bool, ofit: Dictionary) -> void:
	_load()
	var shirt: Color = kit.shirt.albedo_color
	var shorts: Color = kit.shorts.albedo_color
	var socks: Color = kit.socks.albedo_color
	_inst = SCN.instantiate()
	add_child(_inst)
	skel = _inst.find_children("*", "Skeleton3D", true, false)[0]
	var skin: Color = SKIN[clampi(skin_i, 0, 4)]
	var hair: Color = HAIR[clampi(hair_i, 0, 5)]
	if look.is_empty():
		look = look_for(style, skin_i)
	# saç: koyu tenlilerde kısa/kazınmış/kıvırcık ağırlıklı
	var hidx := posmod(style * 3 + hair_i, HAIRS.size())
	if skin_i >= 3 and HAIRS[hidx] in ["HairCrop", "HairQuiff"]:
		hidx = [1, 3, 4, 5][posmod(style, 4)]
	var hname: String = HAIRS[hidx]
	var beard: float = [0.0, 0.0, 0.35, 0.8, 0.15][posmod(style, 5)]
	if float(look.get("young", 0.0)) > 0.6:
		beard *= 0.3
	var want := ["Body", "Eyes", "Boots"]
	if outfit:
		want += ["ShirtLong" if ofit.get("sleeves", true) else "Shirt", "Pants"]
	else:
		want += ["Shirt", "Shorts", "Socks"]
	if hname != "":
		want.append(hname)
	parts = {}
	for mi: MeshInstance3D in _inst.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		var baseName := nm.trim_suffix("_lod")
		var is_lod := nm.ends_with("_lod")
		var has_lod := _inst.find_child(baseName + "_lod", true, false) != null
		var keep: bool = baseName in want and (not has_lod or is_lod == lod)
		if not keep:
			mi.get_parent().remove_child(mi)
			mi.free()
			continue
		parts[baseName] = mi
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# materyaller
	var pat := int(kit.get("pattern", 0))
	var c2: Color = kit.get("c2", Color.WHITE)
	for nm in parts:
		var mi: MeshInstance3D = parts[nm]
		match nm:
			"Body":
				mi.material_override = _skin(skin, hair, beard, 0.95 if hname == "" else 0.55)
				mesh_inst = mi
			"Eyes":
				mi.material_override = _eyemat([Color(0.3, 0.19, 0.09), Color(0.18, 0.12, 0.07), Color(0.25, 0.35, 0.3), Color(0.2, 0.3, 0.45)][posmod(style * 5 + skin_i, 4) if skin_i < 2 else posmod(style, 2)])
			"Shirt", "ShirtLong":
				mi.material_override = _cloth(shirt, c2, pat if not outfit else 0, 0.8 if not outfit else 0.7)
			"Shorts", "Pants":
				mi.material_override = _cloth(shorts, Color.WHITE, 0, 0.75)
			"Socks":
				mi.material_override = _cloth(socks, Color.WHITE, 0, 0.85)
			"Boots":
				mi.material_override = _cloth(ofit.get("shoes", Color(0.06, 0.06, 0.07)), Color.WHITE, 0, 0.35)
			_:
				mi.material_override = _hairmat(hair)
	_apply_morphs()
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
	number_lbl.pixel_size = 0.0022
	number_lbl.modulate = Color(1, 1, 1) if shirt.get_luminance() < 0.55 else Color(0.08, 0.08, 0.1)
	number_lbl.double_sided = false
	if font:
		number_lbl.font = font
	att.add_child(number_lbl)
	_place_number(att)
	number_lbl.visible = not outfit and number > 0
	tick(0.0, 0.0)

func _apply_morphs() -> void:
	for nm in parts:
		var mi: MeshInstance3D = parts[nm]
		for k in MORPHS:
			var w := float(look.get(k, 0.0))
			if absf(w) < 0.01:
				continue
			var bi := mi.find_blend_shape_by_name(k)
			if bi >= 0:
				mi.set_blend_shape_value(bi, w)
	_inst.scale = Vector3.ONE * float(look.get("_h", 1.0))

## Oyuncu verisinden vücut tipi (build'den önce ya da sonra çağrılabilir)
func apply_look(p: Dictionary) -> void:
	look = look_for(int(p.get("seed", 0)), int(p.get("skin", 1)), p)
	if _inst != null:
		_apply_morphs()

func _place_number(att: BoneAttachment3D) -> void:
	# spine_03 global rest -> sırt (-Z) tarafına, dışa bakan etiket
	var g := skel.get_bone_global_rest(skel.find_bone("spine_03"))
	var want := Transform3D(Basis(Vector3.UP, PI), Vector3(0, g.origin.y + 0.06, -0.135))
	number_lbl.transform = g.affine_inverse() * want

## Sahne kıyafeti: forma yerine günlük/takım elbise
func build_outfit(top: Color, pants: Color, shoes: Color, skin_i: int, hair_i: int, style: int, sleeves := true) -> void:
	_build(kit_mats(top, pants, pants), skin_i, hair_i, style, 0, null, true, {"sleeves": sleeves, "shoes": shoes})

func nod() -> void:
	nod_t = 0.0

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
	overlay_w = move_toward(overlay_w, 1.0 if overlay != "" else 0.0, delta * 4.0)
	if nod_t >= 0.0:
		nod_t += delta
		if nod_t > 0.9:
			nod_t = -1.0
	_head_yaw_cur = lerpf(_head_yaw_cur, head_yaw, minf(1.0, delta * 5.0))
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
	# kol kaplaması
	if overlay_w > 0.001 and CL.has(overlay if overlay != "" else _last_overlay):
		var oc: Dictionary = CL[overlay if overlay != "" else _last_overlay]
		var bones: Array = ARM_R if (overlay if overlay != "" else _last_overlay) == "phone" else ARM_R + ARM_L
		for k in bones:
			var cur := skel.get_bone_pose_rotation(bid[k])
			var oq := (oc.a as Animation).rotation_track_interpolate(oc.r[k], 0.0)
			skel.set_bone_pose_rotation(bid[k], cur.slerp(oq, overlay_w))
	if overlay != "":
		_last_overlay = overlay
	# baş: sallama + çevirme
	if nod_t >= 0.0 or absf(_head_yaw_cur) > 0.01:
		var nodv := sin(clampf(nod_t / 0.9, 0.0, 1.0) * TAU * 1.5) * 0.22 if nod_t >= 0.0 else 0.0
		var hq := skel.get_bone_pose_rotation(bid[5])
		skel.set_bone_pose_rotation(bid[5], hq * Quaternion(Vector3.RIGHT, nodv))
		var nq := skel.get_bone_pose_rotation(bid[4])
		# boyun kemiğinin yerel ekseni bilinmiyor: global Y etrafında döndür
		var ng := skel.get_bone_global_pose(skel.get_bone_parent(bid[4])).basis
		var axis := (ng.inverse() * Vector3.UP).normalized()
		skel.set_bone_pose_rotation(bid[4], Quaternion(axis, _head_yaw_cur) * nq)
	# dalışta gövdeyi yana yatır (klip yana sıçrama; yatay uçuş hissi)
	var roll := 0.0
	if wx > 0.001 and action == "dive":
		var f := clampf((action_t - 0.08) / 0.75, 0.0, 1.0)
		roll = sin(f * PI) * 1.05 * wx * (-1.0 if act_clip == "dive" else 1.0)
	var sc := float(look.get("_h", 1.0))
	if absf(roll) > 0.001 or _inst.transform.basis != Basis().scaled(Vector3.ONE * sc):
		var rest_root := skel.get_bone_global_rest(0)
		var pv := rest_root * p
		pv.y = 0.85
		_inst.transform = Transform3D(Basis(), pv * sc) * Transform3D(Basis(Vector3.BACK, roll), Vector3.ZERO) * Transform3D(Basis().scaled(Vector3.ONE * sc), -pv * sc)

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
