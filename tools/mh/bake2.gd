extends SceneTree
## Rohr (UE5 Manny) + Quaternius UAL animasyonlarını UAL mankenine retarget edip
## tek bir AnimationLibrary (.res) ve bölge renkli manken sahnesi üretir.
const CM = preload("res://tools/common.gd")
const OUT := "res://out/"
const FPS := 30.0

# hedef kemikler ve Rohr karşılıkları
const MAP := {
	"pelvis": "pelvis", "spine_01": "spine_02", "spine_02": "spine_04", "spine_03": "spine_05",
	"neck_01": "neck_01", "head": "head",
	"clavicle_l": "clavicle_l", "upperarm_l": "upperarm_l", "lowerarm_l": "lowerarm_l", "hand_l": "hand_l",
	"clavicle_r": "clavicle_r", "upperarm_r": "upperarm_r", "lowerarm_r": "lowerarm_r", "hand_r": "hand_r",
	"thigh_l": "thigh_l", "calf_l": "calf_l", "foot_l": "foot_l", "ball_l": "ball_l",
	"thigh_r": "thigh_r", "calf_r": "calf_r", "foot_r": "foot_r", "ball_r": "ball_r",
}
# yön hizalaması için çocuk kemik (hedef adıyla)
const CHILD := {
	"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "head",
	"clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
	"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l",
	"thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r",
}

var tsk: Skeleton3D          # hedef iskelet (UBC)
var usk: Skeleton3D          # UAL iskeleti (kaynak)
var urest := {}
var uK := {}
var trest := {}              # hedef kemik adı -> global rest Transform3D
var tnames: Array = []       # sırayla hedef kemikler (ebeveyn önce)
var lib := AnimationLibrary.new()
var report := []

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ual: Node3D = (load("res://src/ual.glb") as PackedScene).instantiate()
	usk = ual.get_node("Armature/Skeleton3D")
	var ubc: Node3D = (load("res://src/mh/player.glb") as PackedScene).instantiate()
	tsk = ubc.find_children("*", "Skeleton3D", true, false)[0]
	var urg := _rest_globals(usk)
	for b in usk.get_bone_count():
		urest[usk.get_bone_name(b)] = urg[b]
	var rg := _rest_globals(tsk)
	for b in tsk.get_bone_count():
		trest[tsk.get_bone_name(b)] = rg[b]
	for b in tsk.get_bone_count():
		var nm := tsk.get_bone_name(b)
		if MAP.has(nm):
			tnames.append(nm)
	for nm in tnames:
		uK[nm] = Basis()
		if CHILD.has(nm):
			var ds: Vector3 = ((urest[un(CHILD[nm])] as Transform3D).origin - (urest[un(nm)] as Transform3D).origin).normalized()
			var dt: Vector3 = ((trest[CHILD[nm]] as Transform3D).origin - (trest[nm] as Transform3D).origin).normalized()
			var ax := ds.cross(dt)
			if ax.length() > 1e-5:
				uK[nm] = Basis(ax.normalized(), ds.angle_to(dt))
	for sd in ["l", "r"]:
		for bn in ["lowerarm_" + sd, "hand_" + sd]:
			uK[bn] = _k2(func(n: String) -> Vector3: return (urest[un(n)] as Transform3D).origin, sd, bn)
	var uap: AnimationPlayer = ual.get_node("AnimationPlayer")
	# --- UAL (yerel) klipler
	_ual(uap, "Idle", "idle", true)
	_ual(uap, "Walk", "walk", true, true)
	_ual(uap, "Jog_Fwd", "jog", true, true)
	_ual(uap, "Sprint", "sprint", true, true)
	_ual(uap, "Idle_Talking", "talk", true)
	_ual(uap, "Sitting_Talking", "sit_talk", true)
	_ual(uap, "Sitting_Idle", "sit", true)
	_ual(uap, "Walk_Formal", "walk_formal", true, true)
	_ual(uap, "Crouch_Idle", "crouch", true)
	_ual(uap, "Dance", "dance", true)
	_ual(uap, "Interact", "interact", false)
	_ual(uap, "Death01", "fall", false, false, 0.0, 1.6)
	_ual(uap, "Jump_Start", "jump_a", false, false, 0.0, 0.7)
	_ual(uap, "Jump_Land", "jump_b", false, false, 0.0, 0.9)
	# --- Rohr futbol klipleri: [dosya, ad, pencere başı, pencere sonu (sn), mod]
	# mod: "contact:R/L" -> temas anı otomatik bulunur, pencere temas etrafında
	_rohr("08_Side_Foot_Kick_ue5.fbx", "pass", "contact", 0.55, 0.7)
	_rohr("09_Power_Kick_ue5.fbx", "shot_l", "contact", 0.55, 0.8)
	_rohr("11_Penalty_Kick_02_ue5.fbx", "shot", "contact", 0.55, 0.8)
	_rohr("15_Goalkeeper_Save_01_ue5.fbx", "dive", "dive", 0.35, 1.6)
	_rohr("17_Goalkeeper_Save_03_ue5.fbx", "save_low", "low", 0.55, 1.2)
	_rohr("18_Defending_01_ue5.fbx", "tackle", "low", 0.6, 0.7)
	_rohr("19_Defending_02_ue5.fbx", "jockey", "range", 0.6, 3.6)
	_rohr("12_Goal_Celebration_01_ue5.fbx", "knee_slide", "range", 0.1, 3.45)
	_rohr("13_Goal_Celebration_02_ue5.fbx", "celebrate", "range", 0.1, 3.5)
	_rohr("14_Goal_Celebration_03_ue5.fbx", "celebrate2", "range", 0.1, 3.15)
	_rohr("07_Throw_In_ue5.fbx", "throw", "range", 1.6, 4.4)
	_rohr("03_Dribble_03_ue5.fbx", "dribble", "range", 0.4, 3.4)
	_rohr("04_Juggling_01_ue5.fbx", "juggle", "range", 1.0, 9.0)
	_rohr("20_Yellow_Card_ue5.fbx", "card", "range", 0.1, 2.85)
	# sentetik
	_make_header()
	_make_slide()
	_make_pose("phone", {"upperarm_r": Vector3(-0.3, -0.25, 0.9), "lowerarm_r": Vector3(0.45, 0.7, -0.55)})
	_make_pose("notebook", {"upperarm_l": Vector3(0.25, -0.9, 0.3), "lowerarm_l": Vector3(-0.35, 0.15, 0.95), "upperarm_r": Vector3(-0.25, -0.9, 0.3), "lowerarm_r": Vector3(0.3, 0.25, 0.95)})
	_make_pose("arms_crossed", {"upperarm_l": Vector3(0.18, -0.9, 0.38), "lowerarm_l": Vector3(-0.95, 0.12, 0.2), "upperarm_r": Vector3(-0.18, -0.9, 0.34), "lowerarm_r": Vector3(0.95, 0.18, 0.28)})
	_make_pose("type", {"upperarm_l": Vector3(0.12, -0.8, 0.55), "lowerarm_l": Vector3(-0.2, -0.12, 1.0), "upperarm_r": Vector3(-0.12, -0.8, 0.55), "lowerarm_r": Vector3(0.2, -0.12, 1.0)})
	_make_pose("shake", {"upperarm_r": Vector3(-0.08, -0.75, 0.6), "lowerarm_r": Vector3(0.05, -0.05, 1.0)})
	_make_pose("scarf", {"upperarm_l": Vector3(0.35, 0.9, 0.15), "lowerarm_l": Vector3(-0.45, 0.85, 0.15), "upperarm_r": Vector3(-0.35, 0.9, 0.15), "lowerarm_r": Vector3(0.45, 0.85, 0.15)})
	_make_pose("point", {"upperarm_r": Vector3(-0.2, 0.15, 1.0), "lowerarm_r": Vector3(-0.1, 0.2, 1.0)})
	_mirror("shot_l", "shot_r2")
	_mirror("dive", "dive_m")
	_mirror("save_low", "save_low_m")
	_mirror("pass", "pass_m")
	_mirror("shot", "shot_m")
	var err := ResourceSaver.save(lib, OUT + "anims_mh.res", ResourceSaver.FLAG_COMPRESS)
	# seyirci klipleri (yalnız tribün atlası üretimi için, oyuna girmez)
	var main_lib := lib
	lib = AnimationLibrary.new()
	for cr in [["01_Sitting_Clapping_ue5.fbx", "cr_sit_clap"], ["02_Standing_Clapping_ue5.fbx", "cr_clap"], ["03_Clapping_Hands_Up_ue5.fbx", "cr_clap_up"], ["05_Fist_Up_Cheering_ue5.fbx", "cr_fist"], ["07_Hands_Up_Swaying_ue5.fbx", "cr_sway"], ["13_Sitting_Phone_Video_ue5.fbx", "cr_phone"], ["14_Head_Dancing_ue5.fbx", "cr_dance"], ["17_Pointing_Up_Cheering_ue5.fbx", "cr_point"]]:
		_rohr(cr[0], cr[1], "range", 0.6, 3.6, "crowd")
	ResourceSaver.save(lib, OUT + "crowd_anims_mh.res", ResourceSaver.FLAG_COMPRESS)
	lib = main_lib
	print("lib saved ", err, " clips ", lib.get_animation_list().size())
	var f := FileAccess.open(OUT + "report.txt", FileAccess.WRITE)
	f.store_string("\n".join(report))
	for r in report: print(r)
	quit()

# ---------------------------------------------------------------- yardımcılar

func _rest_globals(sk: Skeleton3D) -> Array:
	var out := []
	out.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		var par := sk.get_bone_parent(b)
		out[b] = sk.get_bone_rest(b) if par < 0 else (out[par] as Transform3D) * sk.get_bone_rest(b)
	return out

static func _frame(d: Vector3, a: Vector3) -> Basis:
	var x := d.normalized()
	var z := x.cross(a).normalized()
	var y := z.cross(x)
	return Basis(x, y, z)

## el ve ön kol için iki eksenli hizalama (kemik yönü + avuç ekseni): bilek burulmasını düzeltir
func _k2(src_pos: Callable, side: String, bone: String) -> Basis:
	var hn := "hand_" + side
	var child := "middle_01_" + side if bone == hn else hn
	var ds: Vector3 = src_pos.call(child) - src_pos.call(bone)
	var as_: Vector3 = src_pos.call("index_01_" + side) - src_pos.call("pinky_01_" + side)
	var dt: Vector3 = (trest[child] as Transform3D).origin - (trest[bone] as Transform3D).origin
	var at_: Vector3 = (trest["index_01_" + side] as Transform3D).origin - (trest["pinky_01_" + side] as Transform3D).origin
	return _frame(dt, at_) * _frame(ds, as_).inverse()

func un(nm: String) -> String:
	return "Head" if nm == "head" else nm

func _tbone(nm: String) -> int:
	return tsk.find_bone(nm)

## hedef global pozlarından (yalnız eşlenen kemikler) Animation üretir
## frames: Array of Dictionary {bone: Basis (global)}, pel: Array[Vector3] (global pelvis pos)
func _emit(name: String, frames: Array, pel: Array, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = maxf(1.0 / FPS, (frames.size() - 1) / FPS)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var root_g: Transform3D = trest["Root"]
	var tr := {}
	for nm in tnames:
		var ti := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(ti, NodePath("S:" + nm))
		tr[nm] = ti
	var pti := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pti, NodePath("S:pelvis"))
	for i in frames.size():
		var t := i / FPS
		var fr: Dictionary = frames[i]
		for nm in tnames:
			var b := _tbone(nm)
			var par := tsk.get_bone_parent(b)
			var pn := tsk.get_bone_name(par)
			var pg: Basis = fr[pn] if fr.has(pn) else (trest[pn] as Transform3D).basis
			var g: Basis = fr[nm]
			var lq := (pg.inverse() * g).orthonormalized().get_rotation_quaternion()
			a.rotation_track_insert_key(tr[nm], t, lq)
		var lp: Vector3 = root_g.affine_inverse() * (pel[i] as Vector3)
		a.position_track_insert_key(pti, t, lp)
	pass
	lib.add_animation(name, a)
	return a

## UAL klibi: hedef iskelet zaten aynı; global hesaplanıp aynı hatta verilir
func _ual(ap: AnimationPlayer, src: String, name: String, loop: bool, align_foot := false, t0 := 0.0, t1 := -1.0) -> void:
	var an := ap.get_animation(src)
	var tm := CM.track_map(an)
	if t1 < 0: t1 = an.length
	var n := int(round((t1 - t0) * FPS))
	var start := t0
	if align_foot:
		# döngüyü sol ayak en öndeyken başlat (klipler arası faz uyumu)
		var best := -9.0
		var k := 0
		while k < n:
			var g := CM.globals_at(usk, an, tm, t0 + k / FPS)
			var z: float = (g[usk.find_bone("ball_l")] as Transform3D).origin.z - (g[usk.find_bone("pelvis")] as Transform3D).origin.z
			if z > best:
				best = z
				start = t0 + k / FPS
			k += 1
	var frames := []
	var pel := []
	for i in n + 1:
		var t := start + i / FPS
		if loop:
			t = t0 + fposmod(t - t0, t1 - t0)
		var g := CM.globals_at(usk, an, tm, minf(t, an.length))
		var fr := {}
		for nm in tnames:
			var D: Basis = (g[usk.find_bone(un(nm))] as Transform3D).basis * (urest[un(nm)] as Transform3D).basis.inverse()
			fr[nm] = (D * (uK[nm] as Basis).inverse() * (trest[nm] as Transform3D).basis).orthonormalized()
		frames.append(fr)
		var up: Vector3 = (g[usk.find_bone("pelvis")] as Transform3D).origin
		var ur: Vector3 = (urest["pelvis"] as Transform3D).origin
		var tp: Vector3 = (trest["pelvis"] as Transform3D).origin
		pel.append(tp + (up - ur) * (tp.y / ur.y))
	_emit(name, frames, pel, loop)
	report.append("%s <- UAL %s len %.2f" % [name, src, n / FPS])

func _rohr(file: String, name: String, mode: String, pre: float, post: float, dir := "rohr") -> void:
	var sc: Node3D = (load("res://src/" + dir + "/" + file) as PackedScene).instantiate()
	var ssk: Skeleton3D = sc.get_node("Skeleton3D")
	var an := CM.clip_of(sc)
	var tm := CM.track_map(an)
	var sb := {}
	for k in MAP:
		sb[k] = ssk.find_bone(MAP[k])
	var rest := CM.globals_at(ssk, an, tm, 0.0)   # 0. kare T-poz
	# tüm kareleri örnekle
	var all := []
	var t := 1.0 / FPS
	while t <= an.length:
		all.append(CM.globals_at(ssk, an, tm, t))
		t += 1.0 / FPS
	var pel_i: int = sb["pelvis"]
	# referans kare (yön ve yer sıfırlama)
	var ref := 0
	var i0 := 0
	var i1 := all.size() - 1
	match mode:
		"contact":
			var best := 0.0
			for i in range(3, all.size()):
				for fb in ["ball_l", "ball_r"]:
					var v: float = ((all[i][sb[fb]] as Transform3D).origin - (all[i - 1][sb[fb]] as Transform3D).origin).length()
					if v > best:
						best = v
						ref = i
			i0 = maxi(0, ref - int(pre * FPS))
			i1 = mini(all.size() - 1, ref + int(post * FPS))
		"dive":
			var best := 0.0
			for i in range(3, all.size()):
				var v: float = absf((all[i][pel_i] as Transform3D).origin.x - (all[i - 1][pel_i] as Transform3D).origin.x)
				if v > best:
					best = v
					ref = i
			i0 = maxi(0, ref - int(pre * FPS))
			i1 = mini(all.size() - 1, ref + int(post * FPS))
		"low":
			var best := 9.0
			for i in range(3, all.size()):
				var y: float = (all[i][pel_i] as Transform3D).origin.y
				if y < best:
					best = y
					ref = i
			i0 = maxi(0, ref - int(pre * FPS))
			i1 = mini(all.size() - 1, ref + int(post * FPS))
		"range":
			i0 = int(pre * FPS)
			i1 = mini(all.size() - 1, int(post * FPS))
			ref = i0
	# yön: referans karede +Z'ye bakacak şekilde döndür
	var yaw := CM.facing(all[ref], ssk)
	var R := Basis(Vector3.UP, -yaw)
	var p_ref: Vector3 = (all[ref][pel_i] as Transform3D).origin
	var p0: Vector3 = (all[i0][pel_i] as Transform3D).origin
	var p1: Vector3 = (all[i1][pel_i] as Transform3D).origin
	var src_h: float = (rest[pel_i] as Transform3D).origin.y
	var dst_h: float = (trest["pelvis"] as Transform3D).origin.y
	var sc_h := dst_h / src_h
	var K := {}
	for nm in tnames:
		K[nm] = Basis()
		if CHILD.has(nm):
			var ds: Vector3 = ((rest[sb[CHILD[nm]]] as Transform3D).origin - (rest[sb[nm]] as Transform3D).origin).normalized()
			var dt: Vector3 = ((trest[CHILD[nm]] as Transform3D).origin - (trest[nm] as Transform3D).origin).normalized()
			var ax := ds.cross(dt)
			if ax.length() > 1e-5:
				K[nm] = Basis(ax.normalized(), ds.angle_to(dt))
	for sd in ["l", "r"]:
		for bn in ["lowerarm_" + sd, "hand_" + sd]:
			K[bn] = _k2(func(n: String) -> Vector3: return (rest[ssk.find_bone(n)] as Transform3D).origin, sd, bn)
	var frames := []
	var pel := []
	var travel := Vector3.ZERO
	for i in range(i0, i1 + 1):
		var g: Array = all[i]
		var fr := {}
		for nm in tnames:
			var D: Basis = (g[sb[nm]] as Transform3D).basis * (rest[sb[nm]] as Transform3D).basis.inverse()
			fr[nm] = (R * D * (K[nm] as Basis).inverse() * (trest[nm] as Transform3D).basis).orthonormalized()
		frames.append(fr)
		var p: Vector3 = (g[pel_i] as Transform3D).origin
		# yatay kayma: yerinde oynat (doğrusal sürüklenme çıkarılır)
		var f := float(i - i0) / maxf(1.0, float(i1 - i0))
		var drift := p0.lerp(p1, f)
		var rel := p - Vector3(drift.x, 0, drift.z)
		if mode == "dive":
			rel = p - Vector3(p0.x, 0, p0.z)    # dalışta yan hareket korunur
		var rp := R * Vector3(rel.x, 0, rel.z)
		var tp: Vector3 = (trest["pelvis"] as Transform3D).origin
		pel.append(Vector3(rp.x * sc_h + tp.x, p.y * sc_h, rp.z * sc_h + tp.z))
		travel = p1 - p0
	_emit(name, frames, pel, mode == "range" and name in ["jockey", "juggle", "dribble"])
	report.append("%s <- %s frames %d ref %.2fs (contact at %.2fs in clip) yaw %d travel %s" % [name, file, frames.size(), (ref - i0) / FPS, (ref + 1) / FPS, int(rad_to_deg(yaw)), str(travel.snappedf(0.01))])
	sc.free()

## kafa vuruşu: Jump_Start'ın yükseliş kısmı + Jump_Land, pelvise yükseklik eğrisi, başa öne sallanma
func _make_header() -> void:
	var a: Animation = lib.get_animation("jump_a")
	var b: Animation = lib.get_animation("jump_b")
	var out := Animation.new()
	var n := 24   # 0.8 sn
	out.length = (n - 1) / FPS
	for ti in a.get_track_count():
		var nt := out.add_track(a.track_get_type(ti))
		out.track_set_path(nt, a.track_get_path(ti))
		for i in n:
			var t := i / FPS
			var src: Animation = a if t < 0.35 else b
			var st := 0.08 + t if t < 0.35 else (t - 0.35) * 1.4
			var path := String(a.track_get_path(ti))
			if a.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
				var q := src.rotation_track_interpolate(ti, st)
				if path.ends_with(":neck_01") or path.ends_with(":head"):
					var nod := sin(clampf((t - 0.2) / 0.3, 0.0, 1.0) * PI) * 0.45
					q = q * Quaternion(Vector3.RIGHT, nod)
				out.rotation_track_insert_key(nt, t, q)
			else:
				var p := src.position_track_interpolate(ti, st)
				var up := sin(clampf(t / 0.62, 0.0, 1.0) * PI) * 0.38
				# pelvis yerel uzayı root'a göre: root -90X döndürülmüş, yukarı = yerel +Z
				var root_g: Transform3D = trest["Root"]
				p += root_g.basis.inverse() * Vector3(0, up, 0)
				out.position_track_insert_key(nt, t, p)
	lib.add_animation("header", out)
	report.append("header <- synth")

## kayarak müdahale: statik poz, yön vektörleriyle kurulur
func _make_slide() -> void:
	var dirs := {
		"pelvis": Vector3(0, 1, -0.75), "spine_01": Vector3(0, 1, -0.6), "spine_02": Vector3(0, 1, -0.45), "spine_03": Vector3(0, 1, -0.3),
		"neck_01": Vector3(0, 1, 0.2),
		"thigh_r": Vector3(0, -0.15, 1), "calf_r": Vector3(0, -0.1, 1), "foot_r": Vector3(0, 0.5, 1),
		"thigh_l": Vector3(0.25, -0.35, 0.6), "calf_l": Vector3(0.1, -0.2, -1), "foot_l": Vector3(0, -0.5, -1),
		"upperarm_l": Vector3(0.7, -0.5, -0.5), "lowerarm_l": Vector3(0.3, -1, -0.2),
		"upperarm_r": Vector3(-0.6, 0.2, 0.5), "lowerarm_r": Vector3(-0.3, 0.4, 0.8),
	}
	var fr := {}
	# ebeveyn önce: global yönleri hedefle
	for nm in tnames:
		var base: Basis = (trest[nm] as Transform3D).basis
		if dirs.has(nm) and CHILD.has(nm):
			var dt: Vector3 = ((trest[CHILD[nm]] as Transform3D).origin - (trest[nm] as Transform3D).origin).normalized()
			var want: Vector3 = (dirs[nm] as Vector3).normalized()
			var ax := dt.cross(want)
			if ax.length() > 1e-5:
				base = Basis(ax.normalized(), dt.angle_to(want)) * base
		else:
			# ebeveyninin döndürmesini miras al
			var par := tsk.get_bone_name(tsk.get_bone_parent(_tbone(nm)))
			if fr.has(par):
				base = (fr[par] as Basis) * (trest[par] as Transform3D).basis.inverse() * base
		fr[nm] = base.orthonormalized()
	var tp: Vector3 = (trest["pelvis"] as Transform3D).origin
	var frames := []
	var pel := []
	for i in 26:
		frames.append(fr)
		pel.append(Vector3(tp.x, 0.2, tp.z))
	_emit("slide", frames, pel, false)
	report.append("slide <- synth")

## kol kaplaması için statik poz (diğer kemikler dinlenme)
func _make_pose(name: String, dirs: Dictionary) -> void:
	var fr := {}
	for nm in tnames:
		var base: Basis = (trest[nm] as Transform3D).basis
		var par := tsk.get_bone_name(tsk.get_bone_parent(_tbone(nm)))
		if fr.has(par):
			base = (fr[par] as Basis) * (trest[par] as Transform3D).basis.inverse() * base
		if dirs.has(nm) and CHILD.has(nm):
			# ebeveyn dönüşünden sonra bu kemiğin yönünü hedefe çevir
			var cur_dir: Vector3 = (base * ((trest[nm] as Transform3D).basis.inverse() * ((trest[CHILD[nm]] as Transform3D).origin - (trest[nm] as Transform3D).origin))).normalized()
			var want: Vector3 = (dirs[nm] as Vector3).normalized()
			var ax := cur_dir.cross(want)
			if ax.length() > 1e-5:
				base = Basis(ax.normalized(), cur_dir.angle_to(want)) * base
		fr[nm] = base.orthonormalized()
	var tp: Vector3 = (trest["pelvis"] as Transform3D).origin
	_emit(name, [fr, fr, fr], [tp, tp, tp], true)
	report.append(name + " <- pose")

## X düzleminde ayna (sol/sağ yer değiştirir)
func _mirror(src: String, dst: String) -> void:
	var a: Animation = lib.get_animation(src)
	var out := Animation.new()
	out.length = a.length
	out.loop_mode = a.loop_mode
	var M := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	var idx := {}
	for ti in a.get_track_count():
		idx[String(a.track_get_path(ti)) + "/" + str(a.track_get_type(ti))] = ti
	var n := int(round(a.length * FPS)) + 1
	var root_g: Transform3D = trest["Root"]
	# global yeniden kur, aynala, yerel yaz
	var tracks := {}
	for nm in tnames:
		var ti := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(ti, NodePath("S:" + nm))
		tracks[nm] = ti
	var pti := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pti, NodePath("S:pelvis"))
	for i in n:
		var t := i / FPS
		var g := {}
		for nm in tnames:
			var b := _tbone(nm)
			var pn := tsk.get_bone_name(tsk.get_bone_parent(b))
			var pg: Basis = g[pn] if g.has(pn) else (trest[pn] as Transform3D).basis
			var q := a.rotation_track_interpolate(idx["S:" + nm + "/" + str(Animation.TYPE_ROTATION_3D)], t)
			g[nm] = pg * Basis(q)
		var mg := {}
		for nm in tnames:
			var sw: String = nm.replace("_l", "_X").replace("_r", "_l").replace("_X", "_r") if (nm.ends_with("_l") or nm.ends_with("_r")) else nm
			var D: Basis = (g[sw] as Basis) * (trest[sw] as Transform3D).basis.inverse()
			mg[nm] = (M * D * M) * (trest[nm] as Transform3D).basis
		for nm in tnames:
			var b := _tbone(nm)
			var pn := tsk.get_bone_name(tsk.get_bone_parent(b))
			var pg: Basis = mg[pn] if mg.has(pn) else (trest[pn] as Transform3D).basis
			out.rotation_track_insert_key(tracks[nm], t, (pg.inverse() * (mg[nm] as Basis)).orthonormalized().get_rotation_quaternion())
		var lp := a.position_track_interpolate(idx["S:pelvis/" + str(Animation.TYPE_POSITION_3D)], t)
		var gp := root_g * lp
		gp.x = -gp.x
		out.position_track_insert_key(pti, t, root_g.affine_inverse() * gp)
	pass
	lib.add_animation(dst, out)
	report.append("%s <- mirror %s" % [dst, src])

# ---------------------------------------------------------------- manken

func _save_man(ubc: Node3D) -> void:
	var rg := _rest_globals(tsk)
	var y_of := func(nm: String) -> float: return (rg[tsk.find_bone(nm)] as Transform3D).origin.y
	var x_of := func(nm: String) -> float: return absf((rg[tsk.find_bone(nm)] as Transform3D).origin.x)
	var knee: float = y_of.call("calf_l")
	var hip: float = y_of.call("thigh_l")
	var ankle: float = y_of.call("foot_l")
	var sh: float = x_of.call("upperarm_l")
	var el: float = x_of.call("lowerarm_l")
	var neck: float = y_of.call("neck_01")
	var head_y: float = y_of.call("Head")
	var root := Node3D.new()
	root.name = "Man"
	var sk := Skeleton3D.new()
	sk.name = "S"
	root.add_child(sk)
	sk.owner = root
	for b in tsk.get_bone_count():
		sk.add_bone(tsk.get_bone_name(b))
	for b in tsk.get_bone_count():
		sk.set_bone_parent(b, tsk.get_bone_parent(b))
		sk.set_bone_rest(b, tsk.get_bone_rest(b))
	sk.reset_bone_poses()
	for mi: MeshInstance3D in ubc.find_children("*", "MeshInstance3D", true, false):
		var src: ArrayMesh = mi.mesh
		var out := ArrayMesh.new()
		for s in src.get_surface_count():
			var arr := src.surface_get_arrays(s)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cols := PackedColorArray()
			cols.resize(V.size())
			for i in V.size():
				var v := V[i]
				cols[i] = Color((v.x + 1.0) * 0.5, v.y * 0.5, (v.z + 1.0) * 0.5, 1)
			arr[Mesh.ARRAY_COLOR] = cols
			arr[Mesh.ARRAY_TANGENT] = null
			var fmt := src.surface_get_format(s)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, (fmt | Mesh.ARRAY_FORMAT_COLOR) & ~Mesh.ARRAY_FORMAT_TEX_UV2 & ~Mesh.ARRAY_FORMAT_TANGENT)
		var m := MeshInstance3D.new()
		m.name = {"SuperHero_Male": "M", "Eyes": "Eyes", "Eyebrows": "Brows"}.get(String(mi.name), String(mi.name))
		m.mesh = out
		m.skin = mi.skin
		sk.add_child(m)
		m.owner = root
		m.skeleton = NodePath("..")
		report.append("mesh %s verts %d" % [m.name, src.surface_get_array_len(0)])
	# saç modelleri (Origin at 0): kafa kemiğine bağlı statik mesh, kendi sahnelerinde
	var hg: Transform3D = rg[tsk.find_bone("Head")]
	for hn in ["Hair_Buzzed", "Hair_SimpleParted", "Hair_Long", "Hair_Beard"]:
		var hs: Node = (load("res://src/ubc/" + hn + ".gltf") as PackedScene).instantiate()
		var hm: MeshInstance3D = hs.find_children("*", "MeshInstance3D", true, false)[0]
		var am: ArrayMesh = hm.mesh
		var out2 := ArrayMesh.new()
		for s in am.get_surface_count():
			var arr := am.surface_get_arrays(s)
			arr[Mesh.ARRAY_TANGENT] = null
			# kafa kemiği uzayına taşı
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var inv := hg.affine_inverse() * hm.global_transform if hm.is_inside_tree() else hg.affine_inverse() * hm.transform
			for i in V.size():
				V[i] = inv * V[i]
				N[i] = (inv.basis * N[i]).normalized()
			arr[Mesh.ARRAY_VERTEX] = V
			arr[Mesh.ARRAY_NORMAL] = N
			out2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, am.surface_get_format(s) & ~Mesh.ARRAY_FORMAT_TANGENT & ~Mesh.ARRAY_FORMAT_TEX_UV2)
		ResourceSaver.save(out2, OUT + hn.to_lower() + ".res", ResourceSaver.FLAG_COMPRESS)
		report.append("hair %s verts %d" % [hn, am.surface_get_array_len(0)])
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, OUT + "man.scn", ResourceSaver.FLAG_COMPRESS)
	report.append("man UBC: knee %.3f hip %.3f ankle %.3f sh %.3f el %.3f neck %.3f head %.3f" % [knee, hip, ankle, sh, el, neck, head_y])
