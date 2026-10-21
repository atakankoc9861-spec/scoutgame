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
const TR := preload("res://three/traits3d.gd")

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

## Klibin vuruş ayağı: başlangıç anı çevresinde hangi uyluk daha çok savruluyor ("L"/"R")
static var _clip_foot := {}
static func clip_foot(clip: String) -> String:
	_load()
	if _clip_foot.has(clip):
		return _clip_foot[clip]
	var res := ""
	if CL.has(clip):
		var c: Dictionary = CL[clip]
		var a: Animation = c.a
		var t0 := 0.0
		for k in ACT:
			for o in ACT[k]:
				if o[0] == clip:
					t0 = o[1]
		var sw := [0.0, 0.0]
		for side in 2:
			var tk: int = c.r[BONES.find("thigh_l" if side == 0 else "thigh_r")]
			if tk < 0:
				continue
			var q0 := a.rotation_track_interpolate(tk, maxf(0.0, t0 - 0.25))
			for i in 10:
				var q := a.rotation_track_interpolate(tk, clampf(t0 - 0.25 + i * 0.07, 0.0, a.length))
				sw[side] = maxf(sw[side], q0.angle_to(q))
		res = "L" if sw[0] > sw[1] else "R"
	_clip_foot[clip] = res
	return res

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
var traits := {}                   # tech-art Faz 2: traits3d.for_player (boş = kapalı, eski davranış)
var _yaw_prev := 0.0
var _yaw_ok := false
var _mv: Object = null             # maç görünümü (yorgunluk için motor saati; salt okunur)
var _mv_tried := false
var tired_w := 0.0                 # 0..1 yorgun duruş ağırlığı (ölçüm/test)

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
# --- yüz animasyonu (sahne/menü; maçta kapalı)
const EXPR := ["x_blink", "x_wide_eyes", "x_squint", "x_brow_up", "x_brow_worry", "x_brow_down", "x_jaw", "x_smile", "x_wide", "x_round", "x_sad"]
const EMO := {
	"neutral": {},
	"happy": {"x_smile": 0.75, "x_squint": 0.25, "x_brow_up": 0.15},
	"smirk": {"x_smile": 0.4, "x_squint": 0.15},
	"sad": {"x_sad": 0.6, "x_brow_worry": 0.7},
	"worried": {"x_brow_worry": 0.65, "x_sad": 0.25},
	"angry": {"x_brow_down": 0.85, "x_squint": 0.35, "x_sad": 0.2},
	"annoyed": {"x_brow_down": 0.45, "x_sad": 0.3, "x_squint": 0.2},
	"surprised": {"x_wide_eyes": 0.8, "x_brow_up": 0.8, "x_jaw": 0.18},
	"thinking": {"x_brow_down": 0.25, "x_squint": 0.3, "x_round": 0.15},
}
var face_on := false
var _fx := {}             # morph adı -> index (gövde)
var _fw := {}             # şu anki ağırlıklar
var _emo := "neutral"
var _emo_t := -1.0
var _talk_left := 0.0
var _talk_ph := 0.0
var _blink_t := 2.0
var _blink := 0.0
var _eye_mat: ShaderMaterial
var look_target := Vector3.INF
var _eye_off := Vector2.ZERO
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
	if float(traits.get("grey", 0.0)) > 0.0:
		hair = hair.lerp(TR.GREY, float(traits.grey))
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
	_face_init(style)
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
	if skel != null and traits.has("head"):
		var hb := skel.find_bone("head")
		if hb >= 0:
			skel.set_bone_pose_scale(hb, Vector3.ONE * float(traits.head))

## Oyuncu verisinden vücut tipi (build'den önce ya da sonra çağrılabilir)
func apply_look(p: Dictionary) -> void:
	look = look_for(int(p.get("seed", 0)), int(p.get("skin", 1)), p)
	traits = TR.for_player(p)
	if not traits.is_empty():
		TR.body_morphs(look, traits, p)
		look["_h"] = float(traits.scale)
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
	if traits.has("foot") and name in ["kick", "shot"]:
		pick = pick_for_foot(opts, str(traits.foot), mirror_seed)
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

## Tercih edilen ayağa uyan seçenek (birden çok varsa tohumla seçilir; uyan yoksa ilk seçenek)
static func pick_for_foot(opts: Array, foot: String, seed_i: int) -> Array:
	var ok: Array = []
	for o in opts:
		if clip_foot(o[0]) == foot:
			ok.append(o)
	if ok.is_empty():
		return opts[posmod(seed_i, opts.size())]
	return ok[posmod(seed_i, ok.size())]

func is_busy() -> bool:
	return action != "" and action_t < action_dur

func tick(delta: float, spd: float, anim_speed := 1.0) -> void:
	speed = spd
	idle_t += delta * anim_speed
	if not traits.is_empty():
		_turn(delta)
		# adım: ölçekli model klibin doğal hızına s kat daha hızlı ulaşır -> karışım/döngü spd/s ile
		spd /= float(traits.scale)
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
	# tech-art Faz 1: maçta (lod) kameradan uzak oyuncunun kemik yazımı 2 karede 1.
	# Zaman/faz her karede ilerler (senkron bozulmaz), yalnız poz örneklemesi seyrelir.
	if lod and _thin_skip():
		return
	_apply(lo[0], hi[0], w)
	if not traits.is_empty() and lod:
		_tired(delta)
	if face_on and delta > 0.0:
		_face(delta)

## Çeviklik: maç görünümünün bu karedeki dönüş adımını (lerp) kazançla büyütür/küçültür.
## Kazanç, hedefi aşmayacak şekilde 1/f ile sınırlı (f = match_view lerp oranı). delta=0 (tekrar,
## başlangıç yerleşimi) ya da ışınlanma benzeri büyük sıçrama referansı sıfırlar.
func _turn(delta: float) -> void:
	var g := float(traits.get("turn", 1.0))
	if delta <= 0.0 or not lod or not is_inside_tree() or not visible:
		_yaw_ok = false
		return
	var cur := rotation.y
	if _yaw_ok and absf(g - 1.0) > 0.001 and not (action == "dive" and is_busy()):
		var d := wrapf(cur - _yaw_prev, -PI, PI)
		if absf(d) < 2.0:
			var f := minf(1.0, 0.2 + delta * 8.0)
			rotation.y = _yaw_prev + d * minf(g, 1.0 / f)
	_yaw_prev = rotation.y
	_yaw_ok = true

## Maç saati (motor clock, sn); maç görünümü yoksa -1
func _clock() -> float:
	if not _mv_tried:
		_mv_tried = true
		var n := get_parent()
		while n != null:
			if "eng" in n and n.get("eng") != null:
				_mv = n
				break
			n = n.get_parent()
	if _mv == null or not is_instance_valid(_mv):
		return -1.0
	var e = _mv.get("eng")
	if e == null or not ("clock" in e):
		return -1.0
	return float(e.clock)

## Yorgun duruş: 70'ten sonra düşük kondisyonlu oyuncu yavaşken öne eğilir, başı düşer
func _tired(delta: float) -> void:
	var want := 0.0
	var clk := _clock()
	if clk > 0.0:
		want = TR.tired(float(traits.get("stamina", 10.0)), clk)
	if delta > 0.0:
		tired_w = move_toward(tired_w, want, delta * 0.5)
	var amt := tired_w * clampf(1.0 - speed / 3.0, 0.25, 1.0)
	if action != "":
		amt *= 1.0 - clampf(action_t / 0.1, 0.0, 1.0)
	if amt < 0.01 or skel == null:
		return
	# omurga ve baş: karakterin sağ ekseni etrafında öne eğil (iskelet uzayı -> kemik yerel)
	for k in [1, 2, 5]:
		var par := skel.get_bone_parent(bid[k])
		var pb := skel.get_bone_global_pose(par).basis if par >= 0 else Basis()
		var axis := (pb.inverse() * _skel_right()).normalized()
		var ang := amt * (0.16 if k != 5 else 0.22)
		skel.set_bone_pose_rotation(bid[k], Quaternion(axis, ang) * skel.get_bone_pose_rotation(bid[k]))

var _sk_right := Vector3.ZERO
func _skel_right() -> Vector3:
	if _sk_right == Vector3.ZERO:
		# kök (bu düğüm) +X ekseninin iskelet uzayındaki karşılığı; ölçek dışı dönüşler
		var b := Basis()
		var n: Node = skel
		while n != null and n != _inst:
			if n is Node3D:
				b = (n as Node3D).transform.basis.orthonormalized() * b
			n = n.get_parent()
		_sk_right = (b.inverse() * Vector3.RIGHT).normalized()
	return _sk_right

const THIN_DIST := 35.0            # m; bunun ötesindeki oyuncular seyreltilir
static var thin_skipped := 0       # ölçüm/test sayacı (atlanan _apply)
var _thin_slot := -1

## Bu kare poz yazımı atlanacak mı? Bayrak: Game.settings.ta_anim_thin (varsayılan açık).
## Aksiyon (şut/dalış) sırasında ve kamera yokken asla atlanmaz.
func _thin_skip() -> bool:
	if not bool(Game.settings.get("ta_anim_thin", true)):
		return false
	if action != "" or not is_inside_tree():
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	if global_position.distance_squared_to(cam.global_position) < THIN_DIST * THIN_DIST:
		return false
	if _thin_slot < 0:
		_thin_slot = get_instance_id() & 1   # oyuncuları iki kareye dağıt (yük dengesi)
	if (Engine.get_process_frames() & 1) == _thin_slot:
		return false
	thin_skipped += 1
	return true

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

## ---------------------------------------------------------------- yüz
func _face_init(style: int) -> void:
	face_on = not lod and parts.has("Body")
	if not face_on:
		return
	var b: MeshInstance3D = parts["Body"]
	for k in EXPR:
		var i := b.find_blend_shape_by_name(k)
		if i >= 0:
			_fx[k] = i
			_fw[k] = 0.0
	if _fx.is_empty():
		face_on = false
		return
	_blink_t = 1.0 + float(style % 23) * 0.13
	if parts.has("Eyes"):
		var em: ShaderMaterial = (parts["Eyes"] as MeshInstance3D).material_override
		_eye_mat = em.duplicate()
		parts["Eyes"].material_override = _eye_mat

## Konuşma: süre boyunca ağız hece hecesi oynar
func talk(seconds: float) -> void:
	_talk_left = maxf(_talk_left, seconds)

func stop_talk() -> void:
	_talk_left = 0.0

## Duygu: ad (EMO) ve süre (-1 = kalıcı)
func emote(name: String, dur := -1.0) -> void:
	_emo = name if EMO.has(name) else "neutral"
	_emo_t = dur

func _face(delta: float) -> void:
	var want := {}
	for k in _fw:
		want[k] = 0.0
	var e: Dictionary = EMO.get(_emo, {})
	for k in e:
		want[k] = e[k]
	if _emo_t > 0.0:
		_emo_t -= delta
		if _emo_t <= 0.0:
			_emo = "neutral"
			_emo_t = -1.0
	# konuşma: hece ritmi (~7 Hz), sesli harf şekli heceye göre değişir
	if _talk_left > 0.0:
		_talk_left -= delta
		_talk_ph += delta * 7.0
		var syl := absf(sin(_talk_ph * PI))
		var h := hash(int(_talk_ph)) % 3
		var env := clampf(_talk_left * 3.0, 0.0, 1.0)
		want["x_jaw"] = float(want.get("x_jaw", 0.0)) + (0.12 + 0.38 * syl) * env
		if h == 1:
			want["x_wide"] = 0.35 * syl * env
		elif h == 2:
			want["x_round"] = 0.45 * syl * env
	# göz kırpma
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 0.16
		_blink_t = randf_range(2.2, 5.5)
	if _blink > 0.0:
		_blink -= delta
		want["x_blink"] = sin(clampf(1.0 - _blink / 0.16, 0.0, 1.0) * PI)
	var b: MeshInstance3D = parts["Body"]
	for k in _fw:
		var spd := 30.0 if k in ["x_jaw", "x_blink", "x_wide", "x_round"] else 5.0
		var nv := lerpf(float(_fw[k]), float(want[k]), minf(1.0, delta * spd))
		if absf(nv - float(_fw[k])) > 0.002 or (nv == 0.0 and float(_fw[k]) != 0.0):
			_fw[k] = nv
			b.set_blend_shape_value(_fx[k], nv)
	# gözler hedefe bakar (iris UV kaydırma)
	if _eye_mat and look_target != Vector3.INF and skel:
		var hi := skel.find_bone("head")
		var hg := skel.global_transform * skel.get_bone_global_pose(hi)
		var eye_w := hg * Vector3(0, 0.04, 0.09)
		var d := (look_target - eye_w)
		var loc := (global_transform.basis.inverse() * d).normalized()
		var yaw := clampf(atan2(loc.x, loc.z), -0.6, 0.6)
		var pitch := clampf(asin(clampf(loc.y, -1.0, 1.0)), -0.35, 0.35)
		var tgt := Vector2(-yaw, -pitch) * 0.0035
		_eye_off = _eye_off.lerp(tgt, minf(1.0, delta * 8.0))
		_eye_mat.set_shader_parameter("look", _eye_off)

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
