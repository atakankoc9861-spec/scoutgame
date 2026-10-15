extends Control
class_name Drill2D
## v0.22: 3B yerine 2D antrenman gözlemi. İki görünüm:
##  "board" — taktik tahtası: tebeşir çizgiler, mıknatıs pullar, kronometre, ölçülen değerler
##  "cine"  — sinematik çizim: tesis panoraması, perspektif çim, çizgi film oyuncular, ağır çekim
## Sonuçlar oyuncunun gerçek değerlerinden gelir (hızlı çocuk gerçekten önce varır).
## Stage3D ile aynı arayüz: start_drills / try_catch / drill_on / sparks_caught / kıvılcım sinyalleri.

signal spark_shown(idx: int)
signal spark_caught(idx: int)
signal spark_missed(idx: int)

const DRILL_SETS := {"tec": ["rondo", "slalom", "shoot", "longpass", "cross"], "phy": ["sprint", "duel", "slalom", "sprint", "duel"],
	"men": ["rondo", "longpass", "duel", "rondo", "cross"], "all": ["rondo", "shoot", "slalom", "cross", "sprint", "longpass", "duel"]}

const F_CHALK := preload("res://fonts/Caveat-Bold.ttf")
const F_COND := preload("res://fonts/BarlowCondensed-ExtraBold.ttf")
const F_MONO := preload("res://fonts/CourierPrime-Bold.ttf")

var style := "board"
var p: Dictionary = {}
var club: Dictionary = {}
var c1 := Color("#c8102e")
var c2 := Color("#ffffff")
var skin := Color("#c99a70")
var views: Array = []          # Stage3D uyumluluğu (perde kontrolü bunu boş görünce geçer)
var actors := {}
var follow := false
var drill_on := false
var sparks_caught := 0
var spark_times: Array = []
var spark_idx := 0
var spark_live := -1.0
var drill := {}
var ents := {}                 # ad -> {pos, prev, kind, col, ph, face}
var ball := {"pos": Vector2.ZERO, "h": 0.0, "on": false}
var cones: Array = []
var marks: Array = []          # [Vector2, yarıçap]
var goal := {}                 # {"x": float, "dir": 1}
var view := Rect2(-5, -10, 40, 20)
var trail: Array = []
var _trail_t := 0.0
var pops: Array = []           # {text, col, age, pos}
var results: Array = []
var cur_title := ""
var cur_result := ""
var watch_t := -1.0
var cam_x := 0.0
var rng := RandomNumberGenerator.new()
var tex_pano: Texture2D
var tex_turf: Texture2D
var _smudges: Array = []
var _idle_t := 0.0
var _slow := 1.0

func setup(st: String, pl: Dictionary, cl: Dictionary) -> void:
	style = st
	p = pl
	club = cl
	c1 = Color(cl.get("c1", "#c8102e"))
	c2 = Color(cl.get("c2", "#ffffff"))
	var skins := [Color("#f1c9a5"), Color("#d9a77c"), Color("#a9734a"), Color("#6b4428")]
	skin = skins[clampi(int(p.get("skin", 1)), 0, 3)]
	rng.seed = hash(str(p.get("id", "x")) + str(Time.get_ticks_msec()))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/tex/bg_training_panorama.jpg"):
		tex_pano = load("res://assets/tex/bg_training_panorama.jpg")
	if ResourceLoader.exists("res://assets/tex/tex_turf_worn.jpg"):
		tex_turf = load("res://assets/tex/tex_turf_worn.jpg")
	var r2 := RandomNumberGenerator.new()
	r2.seed = 77
	for i in 26:
		_smudges.append([Vector2(r2.randf(), r2.randf()), r2.randf_range(20, 90), r2.randf_range(0.02, 0.06)])
	_idle_layout()
	set_process(true)

# ---------------------------------------------------------------- Stage3D uyumluluk saplamaları
func wide() -> void:
	pass
func shot(_a = null, _b = null, _c = null, _d = null, _e = null) -> void:
	pass
func add_actor(_id = null, _i = null, _p = null, _r = null, _b = null):
	return null
func add_mates(_c = null, _n = null) -> void:
	pass
func focus_speaker(_a = null, _b = null, _c = null) -> void:
	pass
func say(_a = null, _b = null, _c = null) -> void:
	pass
func head_screen(_id = null, _vp = 0) -> Vector2:
	return size * 0.5

func _a(k: String) -> float:
	return float(p.get("attrs", {}).get(k, 10))

func _pname() -> String:
	var f := String(p.get("first", ""))
	var l := String(p.get("last", ""))
	if f == "":
		return l
	return (f.substr(0, 1) + ". " + l).to_upper()

# ---------------------------------------------------------------- akış
func start_drills(_id: String, duration := 34.0, n_sparks := 4, focus := "all") -> void:
	drill_on = true
	var dl: Array = DRILL_SETS.get(focus, DRILL_SETS.all).duplicate()
	dl.shuffle()
	if str(p.get("pos", "")) == "GK":
		dl = ["keeper", "rondo", "keeper", "longpass"]
	var n := clampi(int(round(duration / 7.0)), 3, dl.size())
	dl = dl.slice(0, n)
	drill = {"list": dl, "k": -1, "t": 0.0, "total": 0.0, "dur": duration, "L": duration / float(n), "st": {}}
	spark_times.clear()
	var slot := duration / float(n_sparks + 1)
	for k in n_sparks:
		spark_times.append(slot * (k + 1) + rng.randf_range(-0.8, 0.8))
	spark_idx = 0
	spark_live = -1.0
	sparks_caught = 0
	results.clear()
	_next_drill()

func try_catch() -> bool:
	if spark_live >= 0.0:
		sparks_caught += 1
		spark_caught.emit(spark_idx - 1)
		spark_live = -1.0
		_pop(T.t("d2_caught"), Color("#ffd23f"), _pp())
		return true
	return false

func _next_drill() -> void:
	if cur_result != "":
		results.append(cur_result)
	drill.k += 1
	if drill.k >= drill.list.size():
		drill.k = drill.list.size() - 1
		return
	drill.kind = drill.list[drill.k]
	drill.t = 0.0
	drill.st = {}
	ents.clear()
	cones.clear()
	marks.clear()
	goal = {}
	trail.clear()
	cur_result = ""
	watch_t = -1.0
	ball = {"pos": Vector2.ZERO, "h": 0.0, "on": false}
	cur_title = "%d. %s" % [drill.k + 1, T.t("d2_" + str(drill.kind))]
	call("_setup_" + str(drill.kind))
	for k in ents:
		ents[k].prev = ents[k].pos
	cam_x = _pp().x

func _ent(id: String, pos: Vector2, kind := "mate") -> void:
	var col := Color("#f1ead6")
	match kind:
		"p": col = c1
		"opp": col = Color("#2f5d9c")
		"gk": col = Color("#2ec4b6")
	ents[id] = {"pos": pos, "prev": pos, "kind": kind, "col": col, "ph": rng.randf() * TAU, "face": 1.0, "spd": 0.0}

func _pp() -> Vector2:
	return ents["p"].pos if ents.has("p") else Vector2.ZERO

func _pop(text: String, col: Color, pos: Vector2) -> void:
	pops.append({"text": text, "col": col, "age": 0.0, "pos": pos})

static func _ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

static func _lv(a: Vector2, b: Vector2, u: float) -> Vector2:
	return a.lerp(b, clampf(u, 0.0, 1.0))

func _process(delta: float) -> void:
	_idle_t += delta
	if drill_on:
		_slow = lerpf(_slow, 0.38 if (spark_live >= 0.0 and style == "cine") else 1.0, minf(1.0, delta * 8.0))
		var d := delta * _slow
		drill.t += d
		drill.total += d
		if spark_idx < spark_times.size() and drill.total >= spark_times[spark_idx]:
			spark_live = 0.0
			spark_idx += 1
			spark_shown.emit(spark_idx - 1)
		if spark_live >= 0.0:
			spark_live += delta
			if spark_live > 1.15:
				spark_live = -1.0
				spark_missed.emit(spark_idx - 1)
		call("_tick_" + str(drill.kind), drill.t, float(drill.L))
		for k in ents:
			var e: Dictionary = ents[k]
			var v: Vector2 = (e.pos - e.prev) / maxf(d, 0.0001)
			e.spd = lerpf(e.spd, v.length(), minf(1.0, delta * 10.0))
			if absf(v.x) > 0.3:
				e.face = signf(v.x)
			e.ph += e.spd * d * 2.4
			e.prev = e.pos
		_trail_t += d
		if _trail_t > 0.08 and ents.has("p"):
			_trail_t = 0.0
			trail.append(_pp())
			if trail.size() > 70:
				trail.pop_front()
		if drill.t >= float(drill.L):
			if drill.k >= drill.list.size() - 1:
				if drill.total >= drill.dur and spark_live < 0.0:
					if cur_result != "":
						results.append(cur_result)
						cur_result = ""
					drill_on = false
					_idle_layout()
			else:
				_next_drill()
	else:
		for k in ents:
			var e: Dictionary = ents[k]
			e.ph += delta * 1.5
	for pp in pops:
		pp.age += delta
	pops = pops.filter(func(x): return x.age < 1.6)
	if ents.has("p"):
		var tx: float = _pp().x
		if ball.on:
			tx = lerpf(tx, ball.pos.x, 0.35)
		if not goal.is_empty():
			tx = lerpf(tx, float(goal.x), 0.32)
		elif drill.get("kind", "") == "rondo" or not drill_on:
			tx = 0.0
		cam_x = lerpf(cam_x, tx, minf(1.0, delta * 3.0))
	queue_redraw()

func _idle_layout() -> void:
	ents.clear()
	cones.clear()
	marks.clear()
	goal = {}
	trail.clear()
	view = Rect2(-12, -9, 24, 18)
	_ent("p", Vector2(0, 0), "p")
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		_ent("m%d" % i, Vector2(cos(a), sin(a)) * 6.5, "mate")
	ball = {"pos": Vector2(0.6, 0.2), "h": 0.0, "on": true}
	cur_title = T.t("d2_idle", [club.get("name", "")])
	cam_x = 0.0

# ================================================================ antrenmanlar
# --- 30 m sprint: oyuncu ile bir takım arkadaşı yarışır
func _setup_sprint() -> void:
	view = Rect2(-4, -6, 40, 12)
	_ent("p", Vector2(0, -1.1), "p")
	_ent("m1", Vector2(0, 1.1), "mate")
	cones = [Vector2(0, -3), Vector2(0, 3), Vector2(30, -3), Vector2(30, 3)]
	var tp := clampf(5.55 - (_a("pace") - 10.0) * 0.1 - (_a("agility") - 10.0) * 0.03 + rng.randf_range(-0.12, 0.12), 3.75, 6.1)
	var tm := 4.6 + rng.randf_range(-0.18, 0.18)
	drill.st = {"tp": tp, "tm": tm, "done": false}

func _tick_sprint(t: float, L: float) -> void:
	var st: Dictionary = drill.st
	var t0 := 0.8
	var k := minf(1.0, (L - 1.8) / maxf(st.tp, st.tm))
	var f := func(u: float) -> float: return pow(clampf(u, 0.0, 1.0), 1.35)
	ents.p.pos = Vector2(30.0 * f.call((t - t0) / (st.tp * k)), -1.1)
	ents.m1.pos = Vector2(30.0 * f.call((t - t0) / (st.tm * k)), 1.1)
	if t > (t0 + st.tp * k):
		ents.p.pos.x = 30.0 + minf(3.0, (t - t0 - st.tp * k) * 3.0)
	if t > (t0 + st.tm * k):
		ents.m1.pos.x = 30.0 + minf(3.0, (t - t0 - st.tm * k) * 3.0)
	watch_t = clampf((t - t0) / k, 0.0, st.tp) if t > t0 else -1.0
	if t > t0 and t < t0 + 0.1:
		_pop(T.t("d2_go"), Color.WHITE, Vector2(2, -4))
	if not st.done and t > t0 + maxf(st.tp, st.tm) * k:
		st.done = true
		var first: bool = st.tp <= st.tm
		cur_result = T.t("d2r_sprint", ["%.2f" % st.tp, T.t("d2_first") if first else T.t("d2_second")])
		_pop("%.2f sn" % st.tp, Color("#ffd23f") if first else Color("#ff9f43"), Vector2(30, -4))

# --- huni slalomu
func _setup_slalom() -> void:
	view = Rect2(-3, -6, 30, 12)
	_ent("p", Vector2(0, 0), "p")
	_ent("c", Vector2(-2, 4), "mate")
	var pts := [Vector2(0, 0)]
	for k in 6:
		cones.append(Vector2(3.0 + k * 3.0, 0))
		pts.append(Vector2(3.0 + k * 3.0, 1.2 if k % 2 == 0 else -1.2))
	pts.append(Vector2(23, 0))
	var ts := clampf(9.8 - (_a("dribbling") + _a("agility") - 20.0) * 0.13 + rng.randf_range(-0.3, 0.3), 5.8, 12.5)
	var slip := _a("first_touch") < 9.5 and rng.randf() < 0.55
	if slip:
		ts += 0.9
	drill.st = {"pts": pts, "ts": ts, "slip": slip, "slip_k": rng.randi_range(2, 4), "done": false, "said": false}
	ball.on = true

func _tick_slalom(t: float, L: float) -> void:
	var st: Dictionary = drill.st
	var t0 := 0.6
	var k := minf(1.0, (L - 1.4) / st.ts)
	var u := clampf((t - t0) / (st.ts * k), 0.0, 1.0)
	var pts: Array = st.pts
	var seg := u * (pts.size() - 1)
	var i := mini(int(seg), pts.size() - 2)
	var fr := seg - i
	var pos: Vector2 = (pts[i] as Vector2).lerp(pts[i + 1], _ease(fr) * 0.6 + fr * 0.4)
	ents.p.pos = pos
	var dir: Vector2 = ((pts[i + 1] as Vector2) - (pts[i] as Vector2)).normalized()
	var bpos := pos + dir * 0.7
	if st.slip and i == st.slip_k and fr > 0.3 and fr < 0.8:
		bpos += Vector2(0, 1.6 * sin((fr - 0.3) / 0.5 * PI))
		if not st.said:
			st.said = true
			_pop(T.t("d2_slip"), Color("#ff6b6b"), pos + Vector2(0, -3))
	ball.pos = bpos
	watch_t = clampf((t - t0) / k, 0.0, st.ts) if t > t0 else -1.0
	if not st.done and u >= 1.0:
		st.done = true
		cur_result = T.t("d2r_slalom", ["%.1f" % st.ts])
		_pop("%.1f sn" % st.ts, Color("#ffd23f"), pos + Vector2(0, -3))

# --- bitiricilik: 4 şut
func _setup_shoot() -> void:
	view = Rect2(2, -8, 20, 16)
	goal = {"x": 18.0, "dir": 1}
	_ent("p", Vector2(5, 0), "p")
	_ent("gk", Vector2(17.6, 0), "gk")
	var pg := clampf(0.22 + (_a("finishing") - 10.0) * 0.045 + (_a("composure") - 10.0) * 0.02, 0.05, 0.85)
	var shots := []
	for s in 4:
		var y0 := rng.randf_range(-4.0, 4.0)
		var r := rng.randf()
		var out: String = "goal" if r < pg else ["save", "save", "save", "post", "wide", "wide"][rng.randi() % 6]
		var ty := rng.randf_range(1.2, 3.2) * (1.0 if rng.randf() < 0.5 else -1.0)
		if out == "post":
			ty = 3.66 * signf(ty)
		elif out == "wide":
			ty = rng.randf_range(4.3, 6.0) * signf(ty)
		shots.append({"y0": y0, "out": out, "ty": ty, "said": false})
	drill.st = {"shots": shots, "goals": 0}
	ball.on = true

func _tick_shoot(t: float, L: float) -> void:
	var st: Dictionary = drill.st
	var W := L / 4.0
	var si := mini(int(t / W), 3)
	var u := (t - si * W) / W
	var sh: Dictionary = st.shots[si]
	var spot := Vector2(7.0, sh.y0 * 0.5)
	ents.p.pos = _lv(Vector2(3.5, sh.y0), spot - Vector2(0.6, 0), u / 0.35)
	var gk_y := 0.0
	if u < 0.4:
		ball.pos = spot
		ball.h = 0.0
	else:
		var fu := clampf((u - 0.4) / 0.22, 0.0, 1.0)
		var tgt := Vector2(18.0, sh.ty)
		match sh.out:
			"goal":
				gk_y = -signf(sh.ty) * 1.8 * _ease(fu)
				if fu >= 1.0:
					tgt = Vector2(19.3, sh.ty)
			"save":
				gk_y = sh.ty * _ease(fu)
			"post", "wide":
				gk_y = signf(sh.ty) * 1.2 * _ease(fu)
		var bp := spot.lerp(tgt, fu)
		var after := clampf((u - 0.62) / 0.3, 0.0, 1.0)
		if fu >= 1.0:
			match sh.out:
				"save":
					bp = tgt.lerp(Vector2(14.5, sh.ty * 0.4), _ease(after))
				"post":
					bp = tgt.lerp(Vector2(15.0, sh.ty * 1.6), _ease(after))
				"wide":
					bp = tgt.lerp(Vector2(22.0, sh.ty * 1.3), after)
				"goal":
					bp = Vector2(19.3, sh.ty)
			if not sh.said:
				sh.said = true
				if sh.out == "goal":
					st.goals += 1
				var txt: String = {"goal": T.t("d2_goal"), "save": T.t("d2_save"), "post": T.t("d2_post"), "wide": T.t("d2_wide")}[sh.out]
				var col: Color = Color("#ffd23f") if sh.out == "goal" else Color("#e8e8e8")
				_pop(txt, col, Vector2(16.5, sh.ty - 2.5))
		ball.pos = bp
		ball.h = sin(fu * PI) * (0.9 if sh.out != "wide" else 1.6)
	ents.gk.pos = Vector2(17.6, gk_y)
	cur_result = T.t("d2r_shoot", [st.shots.slice(0, si + (1 if u > 0.62 else 0)).size(), st.goals])

# --- uzun pas: koşan arkadaşın önüne
func _setup_longpass() -> void:
	view = Rect2(-4, -12, 40, 22)
	_ent("p", Vector2(0, 4), "p")
	_ent("rn", Vector2(14, -8), "mate")
	var reps := []
	var errs := 0.0
	for r in 3:
		var e := clampf(8.5 - _a("passing") * 0.32 - _a("vision") * 0.12 + rng.randf_range(-1.0, 1.6), 0.4, 9.0)
		var ang := rng.randf() * TAU
		reps.append({"err": e, "ev": Vector2(cos(ang), sin(ang)) * e, "said": false})
		errs += e
	drill.st = {"reps": reps, "avg": errs / 3.0}
	ball.on = true

func _tick_longpass(t: float, L: float) -> void:
	var st: Dictionary = drill.st
	var W := L / 3.0
	var ri := mini(int(t / W), 2)
	var u := (t - ri * W) / W
	var rp: Dictionary = st.reps[ri]
	var tgt := Vector2(30, -6 + ri * 2.0)
	marks = [[tgt, 1.6]]
	ents.rn.pos = _lv(Vector2(14, -8 + ri * 2.0), tgt, (u - 0.1) / 0.62)
	ents.p.pos = _lv(Vector2(-2.0, 4.0), Vector2(0, 4), u / 0.25)
	if u < 0.27:
		ball.pos = Vector2(0.6, 4)
		ball.h = 0.0
	else:
		var fu := clampf((u - 0.27) / 0.45, 0.0, 1.0)
		ball.pos = Vector2(0.6, 4).lerp(tgt + rp.ev, fu)
		ball.h = sin(fu * PI) * 5.5
		if fu >= 1.0 and not rp.said:
			rp.said = true
			var good: bool = rp.err < 2.5
			_pop("%.1f m" % rp.err, Color("#ffd23f") if good else Color("#ff9f43"), tgt + Vector2(0, -3))
	var done := 0
	var sum := 0.0
	for k in st.reps.size():
		if st.reps[k].said:
			done += 1
			sum += st.reps[k].err
	if done > 0:
		cur_result = T.t("d2r_longpass", ["%.1f" % (sum / done), done])

# --- 1'e 1
func _setup_duel() -> void:
	view = Rect2(-3, -8, 24, 16)
	_ent("p", Vector2(0, 0), "p")
	_ent("df", Vector2(9, 0), "opp")
	var pw := clampf(0.45 + (_a("dribbling") - 10.0) * 0.035 + (_a("agility") - 10.0) * 0.02 + (_a("strength") - 10.0) * 0.012, 0.1, 0.9)
	var reps := []
	for r in 4:
		reps.append({"win": rng.randf() < pw, "side": 1.0 if rng.randf() < 0.5 else -1.0, "said": false})
	drill.st = {"reps": reps, "won": 0}
	cones = [Vector2(17, -3), Vector2(17, 3)]
	ball.on = true

func _tick_duel(t: float, L: float) -> void:
	var st: Dictionary = drill.st
	var W := L / 4.0
	var ri := mini(int(t / W), 3)
	var u := (t - ri * W) / W
	var rp: Dictionary = st.reps[ri]
	var s: float = rp.side
	var pp := _lv(Vector2(0, 0), Vector2(7, 0), u / 0.4)
	var dp := Vector2(9, 0)
	var bp := pp + Vector2(0.7, 0)
	if u > 0.4:
		var v := clampf((u - 0.4) / 0.4, 0.0, 1.0)
		if rp.win:
			pp = Vector2(7, 0).lerp(Vector2(11, 2.2 * s), _ease(minf(1.0, v * 1.6)))
			if v > 0.62:
				pp = Vector2(11, 2.2 * s).lerp(Vector2(17, 0), (v - 0.62) / 0.38)
			dp = Vector2(9, 0).lerp(Vector2(8.6, -1.2 * s), _ease(v))
			bp = pp + Vector2(0.7, 0)
		else:
			pp = Vector2(7, 0).lerp(Vector2(8.2, 0.6 * s), _ease(v))
			dp = Vector2(9, 0).lerp(Vector2(8.0, 0.2 * s), _ease(minf(1.0, v * 2.0)))
			bp = Vector2(7.7, 0).lerp(Vector2(11.5, 4.0 * s), _ease(v))
		if v > 0.55 and not rp.said:
			rp.said = true
			if rp.win:
				st.won += 1
			_pop(T.t("d2_beat") if rp.win else T.t("d2_lost"), Color("#ffd23f") if rp.win else Color("#ff6b6b"), Vector2(9, -3.5))
	ents.p.pos = pp
	ents.df.pos = dp
	ball.pos = bp
	var done := 0
	for r in st.reps:
		if r.said:
			done += 1
	cur_result = T.t("d2r_duel", [st.won, done])

# --- rondo: 5'e 2 top saklama
func _setup_rondo() -> void:
	view = Rect2(-9, -9, 18, 18)
	var R := 6.0
	for i in 5:
		var a := TAU * i / 5.0 - PI / 2.0
		_ent("p" if i == 0 else "m%d" % i, Vector2(cos(a), sin(a)) * R, "p" if i == 0 else "mate")
	_ent("o1", Vector2(-1, 0.5), "opp")
	_ent("o2", Vector2(1, -0.5), "opp")
	var pl := clampf(0.25 - (_a("first_touch") - 10.0) * 0.02 - (_a("passing") - 10.0) * 0.012 - (_a("decisions") - 10.0) * 0.01, 0.03, 0.4)
	drill.st = {"pl": pl, "seq": [], "touch": 0, "lost": 0, "built": false}
	ball.on = true

func _rondo_seq(L: float) -> Array:
	## top sırası: her 0.55 sn'de bir pas; oyuncu (0) sık sık topu alır
	var seq := []
	var holder := 1
	var t := 0.4
	while t < L - 0.3:
		var nxt := 0 if holder != 0 and rng.randf() < 0.5 else (rng.randi_range(1, 4))
		if nxt == holder:
			nxt = (holder + 2) % 5
		var lost := false
		if holder == 0 and rng.randf() < float(drill.st.pl):
			lost = true
		seq.append({"t": t, "from": holder, "to": nxt, "lost": lost, "said": false})
		holder = nxt if not lost else rng.randi_range(1, 4)
		t += 0.55 if not lost else 1.1
	return seq

func _tick_rondo(t: float, L: float) -> void:
	var st: Dictionary = drill.st
	if not st.built:
		st.built = true
		st.seq = _rondo_seq(L)
	var ids := ["p", "m1", "m2", "m3", "m4"]
	var cur: Dictionary = {}
	for s in st.seq:
		if s.t <= t:
			cur = s
	for i in 5:
		var e: Dictionary = ents[ids[i]]
		var a := TAU * i / 5.0 - PI / 2.0
		e.pos = Vector2(cos(a), sin(a)) * (6.0 + sin(t * 2.0 + i) * 0.25)
	if cur.is_empty():
		ball.pos = ents.m1.pos
		return
	var fp: Vector2 = ents[ids[cur.from]].pos
	var tp: Vector2 = ents[ids[cur.to]].pos
	var u := clampf((t - float(cur.t)) / 0.42, 0.0, 1.0)
	if cur.lost:
		var o: Vector2 = ents.o1.pos
		ball.pos = fp.lerp(o, u)
		if not cur.said and u > 0.6:
			cur.said = true
			st.lost += 1
			_pop(T.t("d2_lostball"), Color("#ff6b6b"), fp + Vector2(0, -2.5))
	else:
		ball.pos = fp.lerp(tp, u)
		if not cur.said and u > 0.9:
			cur.said = true
			if cur.to == 0:
				st.touch += 1
	# savunmacılar topa basar
	ents.o1.pos = ents.o1.pos.lerp(ball.pos * 0.8, 0.06)
	ents.o2.pos = ents.o2.pos.lerp((ball.pos + tp) * 0.35, 0.05)
	cur_result = T.t("d2r_rondo", [st.touch, st.lost])

# --- orta / kafa
func _setup_cross() -> void:
	view = Rect2(0, -17, 30, 25)
	goal = {"x": 27.0, "dir": 1}
	var wide := str(p.get("pos", "")) in ["LB", "RB", "LW", "RW"]
	_ent("p", Vector2(0, -14) if wide else Vector2(14, 1), "p")
	_ent("w", Vector2(14, 1) if wide else Vector2(0, -14), "mate")
	_ent("gk", Vector2(26.5, 0), "gk")
	_ent("df", Vector2(21, 1), "opp")
	var q := clampf((0.3 + (_a("crossing") - 10.0) * 0.05) if wide else (0.22 + (_a("heading") - 10.0) * 0.045 + (_a("positioning") - 10.0) * 0.015), 0.05, 0.85)
	var reps := []
	for r in 3:
		reps.append({"ok": rng.randf() < q, "said": false, "gy": rng.randf_range(-2.0, 2.0)})
	drill.st = {"wide": wide, "reps": reps, "n": 0}
	ball.on = true

func _tick_cross(t: float, L: float) -> void:
	var st: Dictionary = drill.st
	var W := L / 3.0
	var ri := mini(int(t / W), 2)
	var u := (t - ri * W) / W
	var rp: Dictionary = st.reps[ri]
	var winger: Dictionary = ents.p if st.wide else ents.w
	var target: Dictionary = ents.w if st.wide else ents.p
	winger.pos = _lv(Vector2(2, -14), Vector2(19, -14), u / 0.45)
	target.pos = _lv(Vector2(14, 1), Vector2(22.5, -0.5), (u - 0.25) / 0.4)
	ents.df.pos = _lv(Vector2(21, 2), Vector2(22, 0.3), (u - 0.3) / 0.4)
	var land := Vector2(23.0, -0.8) if rp.ok else Vector2(25.5, 3.5)
	if u < 0.47:
		ball.pos = winger.pos + Vector2(0.7, 0.3)
		ball.h = 0.0
	elif u < 0.72:
		var fu := (u - 0.47) / 0.25
		ball.pos = (winger.pos + Vector2(0.7, 0.3)).lerp(land, fu)
		ball.h = sin(fu * PI) * 3.2 + fu * 1.6
	else:
		var hu := clampf((u - 0.72) / 0.18, 0.0, 1.0)
		if rp.ok:
			ball.pos = land.lerp(Vector2(27.6, float(rp.gy)), hu)
			ball.h = lerpf(1.8, 1.0, hu)
		else:
			ball.pos = land.lerp(Vector2(30, 6), hu)
			ball.h = maxf(0.0, 1.6 - hu * 2.0)
		if not rp.said and hu > 0.5:
			rp.said = true
			if rp.ok:
				st.n += 1
			var txt := (T.t("d2_goodcross") if rp.ok else T.t("d2_badcross")) if st.wide else (T.t("d2_goal") if rp.ok else T.t("d2_wide"))
			_pop(txt, Color("#ffd23f") if rp.ok else Color("#e8e8e8"), Vector2(23, -4))
	var done := 0
	for r in st.reps:
		if r.said:
			done += 1
	cur_result = T.t("d2r_cross" if st.wide else "d2r_head", [st.n, done])

# --- kaleci
func _setup_keeper() -> void:
	view = Rect2(2, -9, 20, 18)
	goal = {"x": 18.0, "dir": 1}
	_ent("p", Vector2(17.6, 0), "p")
	for i in 3:
		_ent("s%d" % i, Vector2(6.5, -4.0 + i * 4.0), "mate")
	var ps := clampf(0.35 + (_a("reflexes") - 10.0) * 0.045 + (_a("handling") - 10.0) * 0.025 + (_a("positioning") - 10.0) * 0.01, 0.1, 0.92)
	var reps := []
	for r in 5:
		reps.append({"save": rng.randf() < ps, "ty": rng.randf_range(1.0, 3.3) * (1.0 if rng.randf() < 0.5 else -1.0), "from": r % 3, "said": false})
	drill.st = {"reps": reps, "n": 0}
	ball.on = true

func _tick_keeper(t: float, L: float) -> void:
	var st: Dictionary = drill.st
	var W := L / 5.0
	var ri := mini(int(t / W), 4)
	var u := (t - ri * W) / W
	var rp: Dictionary = st.reps[ri]
	var sh: Dictionary = ents["s%d" % rp.from]
	var from: Vector2 = sh.pos + Vector2(0.7, 0)
	var gy := 0.0
	if u < 0.35:
		ball.pos = from
		ball.h = 0.0
	else:
		var fu := clampf((u - 0.35) / 0.25, 0.0, 1.0)
		var tgt := Vector2(18.0, rp.ty)
		gy = (rp.ty if rp.save else rp.ty * 0.35) * _ease(fu)
		var bp := from.lerp(tgt, fu)
		if fu >= 1.0:
			var au := clampf((u - 0.6) / 0.3, 0.0, 1.0)
			bp = tgt.lerp(Vector2(14.0, rp.ty * 0.5), _ease(au)) if rp.save else Vector2(19.3, rp.ty)
			if not rp.said:
				rp.said = true
				if rp.save:
					st.n += 1
				_pop(T.t("d2_save") if rp.save else T.t("d2_goal"), Color("#ffd23f") if rp.save else Color("#ff6b6b"), Vector2(16, rp.ty - 2.5))
		ball.pos = bp
		ball.h = sin(fu * PI) * 0.8
	ents.p.pos = Vector2(17.6, gy)
	var done := 0
	for r in st.reps:
		if r.said:
			done += 1
	cur_result = T.t("d2r_keeper", [st.n, done])

# ================================================================ çizim
func _draw() -> void:
	if style == "cine":
		_draw_cine()
	else:
		_draw_board()

# ---------------------------------------------------------------- taktik tahtası
var _brect := Rect2()

func _f2s(v: Vector2) -> Vector2:
	## saha (m) -> tahta pikseli
	var inner := _brect.grow(-34)
	inner.position.y += 46
	inner.size.y -= 120
	var sc := minf(inner.size.x / view.size.x, inner.size.y / view.size.y)
	var off := inner.position + (inner.size - view.size * sc) * 0.5
	return off + (v - view.position) * sc

func _fsc() -> float:
	var inner := _brect.grow(-34)
	inner.size.y -= 120
	return minf(inner.size.x / view.size.x, inner.size.y / view.size.y)

func _chalk_line(a: Vector2, b: Vector2, w := 3.0, col := Color(0.95, 0.95, 0.9, 0.75), dashed := false) -> void:
	if dashed:
		var L := a.distance_to(b)
		var n := int(L / 14.0)
		for i in n:
			if i % 2 == 0:
				draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, w, true)
	else:
		draw_line(a, b, col, w, true)

func _draw_board() -> void:
	var W := size.x
	var H := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color("#14100c"))
	_brect = Rect2(18, 120, W - 36, H * 0.66 - 120)
	# ahşap çerçeve
	draw_rect(_brect.grow(14), Color("#6b4423"))
	draw_rect(_brect.grow(14), Color("#3b2414"), false, 3.0)
	for i in 6:
		draw_line(_brect.grow(14).position + Vector2(0, 4 + i * 4), _brect.grow(14).position + Vector2(_brect.size.x + 28, 4 + i * 4), Color(0, 0, 0, 0.08), 1.0)
	# keçe
	draw_rect(_brect, Color("#1f4433"))
	for s in _smudges:
		var c: Vector2 = _brect.position + s[0] * _brect.size
		draw_circle(c, s[1], Color(1, 1, 1, s[2] * 0.5))
	# başlık + kronometre
	draw_string(F_CHALK, _brect.position + Vector2(24, 48), cur_title, HORIZONTAL_ALIGNMENT_LEFT, W - 260, 40, Color(0.97, 0.96, 0.9, 0.95))
	_chalk_line(_brect.position + Vector2(22, 58), _brect.position + Vector2(minf(24.0 + cur_title.length() * 17.0, _brect.size.x - 200), 60), 2.5)
	var wc := Vector2(_brect.end.x - 74, _brect.position.y + 52)
	draw_circle(wc, 40, Color(0.96, 0.95, 0.9))
	draw_circle(wc, 40, Color(0.15, 0.15, 0.15), false, 3.0)
	draw_rect(Rect2(wc + Vector2(-7, -52), Vector2(14, 10)), Color(0.3, 0.3, 0.3))
	var wt := maxf(watch_t, 0.0)
	var ang := -PI / 2.0 + fmod(wt, 10.0) / 10.0 * TAU
	draw_line(wc, wc + Vector2(cos(ang), sin(ang)) * 30, Color("#c8102e"), 3.0, true)
	draw_string(F_MONO, wc + Vector2(-34, 22), "%05.2f" % wt, HORIZONTAL_ALIGNMENT_CENTER, 68, 17, Color(0.1, 0.1, 0.1))
	# saha işaretleri
	if not goal.is_empty():
		var gx: float = goal.x
		var a := _f2s(Vector2(gx, -3.66))
		var b := _f2s(Vector2(gx, 3.66))
		var dpt := _fsc() * 1.4
		draw_rect(Rect2(Vector2(a.x, a.y), Vector2(dpt, b.y - a.y)), Color(1, 1, 1, 0.08))
		_chalk_line(a, b, 5.0, Color(1, 1, 1, 0.9))
		_chalk_line(a, a + Vector2(dpt, 0), 3.0)
		_chalk_line(b, b + Vector2(dpt, 0), 3.0)
		_chalk_line(_f2s(Vector2(gx, -9)), _f2s(Vector2(gx - 5.5, -9)), 2.0)
		_chalk_line(_f2s(Vector2(gx - 5.5, -9)), _f2s(Vector2(gx - 5.5, 9)), 2.0)
		_chalk_line(_f2s(Vector2(gx - 5.5, 9)), _f2s(Vector2(gx, 9)), 2.0)
	for m in marks:
		var c := _f2s(m[0])
		var r: float = m[1] * _fsc()
		for i in 18:
			if i % 2 == 0:
				draw_arc(c, r, TAU * i / 18.0, TAU * (i + 1) / 18.0, 4, Color("#ffd23f", 0.85), 3.0, true)
	for cn in cones:
		var c := _f2s(cn)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -12), c + Vector2(9, 7), c + Vector2(-9, 7)]), Color("#ff7a1a"))
	# oyuncunun izi
	if trail.size() > 1:
		for i in range(1, trail.size()):
			if i % 2 == 0:
				draw_line(_f2s(trail[i - 1]), _f2s(trail[i]), Color(1, 0.95, 0.8, 0.35 + 0.4 * float(i) / trail.size()), 3.0, true)
	# pullar
	for id in ents:
		var e: Dictionary = ents[id]
		var c := _f2s(e.pos)
		var r := 17.0 if id == "p" else 14.0
		draw_circle(c + Vector2(2, 4), r, Color(0, 0, 0, 0.35))
		draw_circle(c, r, e.col)
		draw_circle(c, r, Color(0, 0, 0, 0.55), false, 2.5)
		draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.28, Color(1, 1, 1, 0.35))
		if id == "p":
			draw_circle(c, r + 5, Color(1, 1, 1, 0.8), false, 2.0)
			var nm := _pname()
			draw_string_outline(F_COND, c + Vector2(-80, r + 24), nm, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, 5, Color(0, 0, 0, 0.7))
			draw_string(F_COND, c + Vector2(-80, r + 24), nm, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, Color.WHITE)
			if spark_live >= 0.0:
				var pr := r + 12 + sin(spark_live * 14.0) * 5.0
				draw_circle(c, pr, Color("#ffd23f"), false, 5.0)
				draw_circle(c, pr + 9, Color("#ffd23f", 0.35), false, 3.0)
	# top (yüksekliği gölgeyle)
	if ball.on:
		var bc := _f2s(ball.pos)
		var hh: float = ball.h * _fsc() * 0.55
		draw_circle(bc + Vector2(2, 2), 6, Color(0, 0, 0, 0.35))
		draw_circle(bc - Vector2(0, hh), 7 + ball.h * 0.6, Color.WHITE)
		draw_circle(bc - Vector2(0, hh), 7 + ball.h * 0.6, Color(0.1, 0.1, 0.1), false, 2.0)
	# tebeşir yazıları
	for pp in pops:
		var c := _f2s(pp.pos)
		var a: float = clampf(1.6 - pp.age, 0.0, 1.0)
		draw_string(F_CHALK, c + Vector2(-120, -pp.age * 18.0), pp.text, HORIZONTAL_ALIGNMENT_CENTER, 240, 38, Color(pp.col, a))
	# alt şerit: bu antrenmanın sonucu + önceki sonuçlar
	var y := _brect.end.y - 62
	draw_line(Vector2(_brect.position.x + 20, y - 34), Vector2(_brect.end.x - 20, y - 34), Color(1, 1, 1, 0.18), 2.0)
	if cur_result != "":
		draw_string(F_CHALK, Vector2(_brect.position.x + 24, y), "→ " + cur_result, HORIZONTAL_ALIGNMENT_LEFT, _brect.size.x - 40, 32, Color("#ffd23f"))
	var ry := y + 34
	for i in range(results.size() - 1, maxi(-1, results.size() - 3), -1):
		draw_string(F_CHALK, Vector2(_brect.position.x + 24, ry), "✓ " + results[i], HORIZONTAL_ALIGNMENT_LEFT, _brect.size.x - 40, 24, Color(0.9, 0.95, 0.9, 0.6))
		ry += 26

# ---------------------------------------------------------------- sinematik çizim
var _hz := 0.0
const PX := 54.0

func _proj(v: Vector2, h := 0.0) -> Vector3:
	## saha (x ileri, y derinlik) -> ekran x, y, ölçek. Aksiyon bandı ekranın 0.36–0.64'ü.
	var W := size.x
	var H := size.y
	var d := clampf((v.y + 12.0) / 24.0, -0.2, 1.3)
	var s := lerpf(0.55, 1.2, d)
	var gy := _hz + (H * 0.64 - _hz) * (0.12 + 0.88 * d)
	var sx := W * 0.5 + (v.x - cam_x) * PX * s
	return Vector3(sx, gy - h * PX * s, s)

func _draw_cine() -> void:
	var W := size.x
	var H := size.y
	_hz = H * 0.30
	# gökyüzü + tesis panoraması (paralaks)
	draw_rect(Rect2(0, 0, W, _hz + 4), Color("#f2b880"))
	if tex_pano:
		var th := _hz * 1.25
		var tw := th * float(tex_pano.get_width()) / float(tex_pano.get_height())
		var ox := fposmod(-cam_x * 4.0, tw)
		for k in [-1, 0, 1]:
			draw_texture_rect(tex_pano, Rect2(ox + k * tw - tw * 0.3, _hz - th * 0.86, tw, th), false)
	else:
		draw_rect(Rect2(0, 0, W, _hz), Color("#9ec3e6"))
	# çim zemini: derinlik bantları
	var gnd_top := _hz
	var bands := 14
	for i in bands:
		var u0 := float(i) / bands
		var u1 := float(i + 1) / bands
		var y0 := gnd_top + (H - gnd_top) * u0 * u0
		var y1 := gnd_top + (H - gnd_top) * u1 * u1
		var col := Color("#3f8a3a") if i % 2 == 0 else Color("#4a9a42")
		col = col.darkened(0.25 * (1.0 - u0))
		draw_rect(Rect2(0, y0, W, y1 - y0 + 1), col)
	draw_rect(Rect2(0, gnd_top, W, 10), Color(0.9, 0.8, 0.6, 0.18))
	if tex_turf:
		var tw2 := 360.0
		var ox2 := fposmod(-cam_x * PX * 1.1, tw2)
		for k in range(-1, int(W / tw2) + 2):
			draw_texture_rect(tex_turf, Rect2(ox2 + k * tw2, H * 0.6, tw2, H * 0.4), false, Color(1, 1, 1, 0.16))
	# saha çizgileri (10 m'de bir dikey, perspektifle)
	var xs := int(floor((cam_x - 20.0) / 5.0)) * 5
	for x in range(xs, xs + 45, 5):
		var a := _proj(Vector2(x, -14))
		var b := _proj(Vector2(x, 16))
		draw_line(Vector2(a.x, a.y), Vector2(b.x, b.y), Color(1, 1, 1, 0.12), 2.0, true)
	# koniler, hedefler
	for m in marks:
		var c := _proj(m[0])
		draw_arc(Vector2(c.x, c.y), m[1] * PX * c.z, 0, TAU, 28, Color("#ffd23f", 0.7), 3.0, true)
	for cn in cones:
		var c := _proj(cn)
		var s := c.z
		draw_colored_polygon(PackedVector2Array([Vector2(c.x, c.y - 20 * s), Vector2(c.x + 9 * s, c.y), Vector2(c.x - 9 * s, c.y)]), Color("#ff7a1a"))
	# kale (derinlik ekseninde genişlik)
	var draw_list := []
	for id in ents:
		draw_list.append([ents[id].pos.y, "e", id])
	if ball.on:
		draw_list.append([ball.pos.y + 0.01, "b", ""])
	if not goal.is_empty():
		draw_list.append([-3.66, "g", ""])
	draw_list.sort_custom(func(x, y): return x[0] < y[0])
	for it in draw_list:
		match it[1]:
			"e": _cine_man(it[2])
			"b": _cine_ball()
			"g": _cine_goal()
	# hız çizgileri
	if ents.has("p") and float(ents.p.spd) > 5.5:
		var pc := _proj(ents.p.pos)
		for i in 7:
			var yy := pc.y - 20 - i * 9 * pc.z
			var ln := 60.0 + fmod(_idle_t * 400.0 + i * 37.0, 80.0)
			var fx := -float(ents.p.face)
			draw_line(Vector2(pc.x + fx * 30, yy), Vector2(pc.x + fx * (30 + ln), yy), Color(1, 1, 1, 0.35), 2.0, true)
	# ağır çekim (kıvılcım): yarım ton çerçeve + sarı halka
	if spark_live >= 0.0 and ents.has("p"):
		var pc := _proj(ents.p.pos)
		var rr := 46.0 * pc.z + sin(spark_live * 14.0) * 6.0
		draw_arc(Vector2(pc.x, pc.y), rr, 0, TAU, 40, Color("#ffd23f"), 6.0, true)
		for yy in range(0, int(H), 22):
			for xx in range(0, int(W), 22):
				var e := Vector2(xx, yy).distance_to(Vector2(W * 0.5, H * 0.45)) / (W * 0.9)
				if e > 0.55:
					draw_circle(Vector2(xx + (yy % 44) * 0.5, yy), (e - 0.55) * 18.0, Color(0, 0, 0, 0.35))
	# alt bölge: koyulaşan ön plan (not defteri burada açılır)
	for i in 12:
		var y0 := H * 0.62 + i * (H * 0.38 / 12.0)
		draw_rect(Rect2(0, y0, W, H * 0.38 / 12.0 + 1), Color(0.02, 0.04, 0.02, 0.06 + i * 0.045))
	# vinyet + sinema bantları
	for i in 8:
		var a := 0.06 * (8 - i)
		draw_rect(Rect2(0, 54 + i * 6, W, 6), Color(0, 0, 0, a * 0.5))
	# yorumcu bandı (alt üçte bir)
	var by := H * 0.665
	draw_rect(Rect2(0, by, W * 0.86, 58), Color(c1.darkened(0.35), 0.92))
	draw_rect(Rect2(0, by, 10, 58), c2)
	draw_rect(Rect2(W * 0.86, by, 26, 58), Color(c1.darkened(0.35), 0.6))
	draw_string(F_COND, Vector2(26, by + 41), cur_title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, W * 0.6, 32, Color.WHITE)
	if watch_t >= 0.0:
		draw_string(F_MONO, Vector2(W * 0.86 - 140, by + 38), "%05.2f" % watch_t, HORIZONTAL_ALIGNMENT_RIGHT, 120, 26, Color("#ffd23f"))
	if cur_result != "":
		draw_rect(Rect2(0, by + 58, W * 0.78, 40), Color(0.06, 0.05, 0.04, 0.88))
		draw_string(F_COND, Vector2(26, by + 88), cur_result, HORIZONTAL_ALIGNMENT_LEFT, W * 0.74, 25, Color("#ffd23f"))
	# çizgi roman ses efektleri
	for pp in pops:
		var c := _proj(pp.pos)
		var a: float = clampf(1.6 - pp.age, 0.0, 1.0)
		var sc := 1.0 + maxf(0.0, 0.25 - pp.age) * 2.0
		var fs := int(54 * sc)
		var pos := Vector2(c.x - 200, c.y - 40 - pp.age * 20.0)
		draw_string_outline(F_COND, pos + Vector2(4, 5), pp.text, HORIZONTAL_ALIGNMENT_CENTER, 400, fs, 14, Color(0, 0, 0, a * 0.6))
		draw_string_outline(F_COND, pos, pp.text, HORIZONTAL_ALIGNMENT_CENTER, 400, fs, 12, Color(0.08, 0.06, 0.05, a))
		draw_string(F_COND, pos, pp.text, HORIZONTAL_ALIGNMENT_CENTER, 400, fs, Color(pp.col, a))

func _cine_goal() -> void:
	var gx: float = goal.x
	var lp := _proj(Vector2(gx, -3.66))
	var rp := _proj(Vector2(gx, 3.66))
	var lt := _proj(Vector2(gx, -3.66), 2.44)
	var rt := _proj(Vector2(gx, 3.66), 2.44)
	var lb := _proj(Vector2(gx + 1.6, -3.66))
	var rb := _proj(Vector2(gx + 1.6, 3.66))
	var lbt := _proj(Vector2(gx + 1.6, -3.66), 1.6)
	var rbt := _proj(Vector2(gx + 1.6, 3.66), 1.6)
	var net := Color(1, 1, 1, 0.22)
	draw_colored_polygon(PackedVector2Array([Vector2(lt.x, lt.y), Vector2(rt.x, rt.y), Vector2(rbt.x, rbt.y), Vector2(lbt.x, lbt.y)]), Color(1, 1, 1, 0.06))
	for i in 9:
		var u := i / 8.0
		var a := Vector2(lt.x, lt.y).lerp(Vector2(rt.x, rt.y), u)
		var b := Vector2(lbt.x, lbt.y).lerp(Vector2(rbt.x, rbt.y), u)
		draw_line(a, b, net, 1.0)
		var c := Vector2(lb.x, lb.y).lerp(Vector2(rb.x, rb.y), u)
		draw_line(b, c, net, 1.0)
	for i in 5:
		var u := i / 4.0
		draw_line(Vector2(lt.x, lt.y).lerp(Vector2(lbt.x, lbt.y), u), Vector2(rt.x, rt.y).lerp(Vector2(rbt.x, rbt.y), u), net, 1.0)
	var pw := 5.0 * lp.z
	draw_line(Vector2(lp.x, lp.y), Vector2(lt.x, lt.y), Color.WHITE, pw, true)
	draw_line(Vector2(rp.x, rp.y), Vector2(rt.x, rt.y), Color.WHITE, 5.0 * rp.z, true)
	draw_line(Vector2(lt.x, lt.y), Vector2(rt.x, rt.y), Color.WHITE, pw, true)

func _cine_ball() -> void:
	var g := _proj(ball.pos)
	var c := _proj(ball.pos, ball.h)
	var r := 0.24 * PX * g.z
	draw_set_transform(Vector2(g.x, g.y), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, r * (1.2 - minf(ball.h, 4.0) * 0.08), Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	draw_circle(Vector2(c.x, c.y - r), r, Color.WHITE)
	draw_circle(Vector2(c.x, c.y - r), r, Color(0.1, 0.1, 0.1), false, 1.5)
	draw_circle(Vector2(c.x - r * 0.2, c.y - r * 1.1), r * 0.35, Color(0.15, 0.15, 0.15))

const OUTL := Color(0.08, 0.06, 0.05)

func _limb(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	draw_line(a, b, OUTL, w + 3.0, true)
	draw_circle(a, (w + 3.0) * 0.5, OUTL)
	draw_circle(b, (w + 3.0) * 0.5, OUTL)
	draw_line(a, b, col, w, true)
	draw_circle(a, w * 0.5, col)
	draw_circle(b, w * 0.5, col)

func _cine_man(id: String) -> void:
	var e: Dictionary = ents[id]
	var g := _proj(e.pos)
	var base := Vector2(g.x, g.y)
	var hgt := 1.8 * PX * g.z * 1.05
	var face: float = e.face
	var ph: float = e.ph
	var run := clampf(float(e.spd) / 6.0, 0.0, 1.0)
	var shirt: Color = e.col
	var shorts: Color = c2 if e.kind == "p" else (Color("#ffffff") if e.kind == "opp" else Color("#26282c"))
	if e.kind == "gk":
		shorts = Color("#111111")
	var socks: Color = shirt.darkened(0.1) if e.kind != "mate" else Color("#e6e6e6")
	var sk: Color = skin if e.kind == "p" else (Color("#d7a77e") if absi(hash(id)) % 3 == 0 else (Color("#a8754c") if absi(hash(id)) % 3 == 1 else Color("#6e4529")))
	var hair := Color("#2a1a10") if absi(hash(id + "h")) % 4 != 0 else Color("#6b4a2a")
	var lw := maxf(3.0, hgt * 0.07)
	var lean := run * 0.28 * face
	var bob := absf(sin(ph)) * hgt * 0.03 * run
	var hip := base + Vector2(0, -hgt * 0.5 - bob)
	var up := Vector2(sin(lean), -cos(lean))
	var sho := hip + up * hgt * 0.31
	var head := sho + up * hgt * 0.13
	# gölge
	draw_set_transform(base, 0, Vector2(1, 0.25))
	draw_circle(Vector2.ZERO, hgt * 0.2, Color(0, 0, 0, 0.32))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var sw := 0.85 * run + 0.06
	var legs := []
	for k in [-1.0, 1.0]:
		var a := sin(ph + (0.0 if k > 0 else PI)) * sw
		var knee := hip + Vector2(sin(a) * face, cos(a)) * hgt * 0.25
		var bend := maxf(0.0, -a) * 1.2 * run + 0.05
		var foot := knee + Vector2(sin(a - bend) * face, cos(a - bend)) * hgt * 0.26
		legs.append([k, knee, foot])
	var arms := []
	for k in [-1.0, 1.0]:
		var a := -sin(ph + (0.0 if k > 0 else PI)) * (0.95 * run + 0.08)
		var el := sho + Vector2(sin(a) * face, cos(a)) * hgt * 0.16
		var fa := a + (0.9 * run + 0.15) * 1.0
		var hd := el + Vector2(sin(fa) * face, cos(fa)) * hgt * 0.15
		arms.append([k, el, hd])
	# arka kol ve bacak (koyu)
	_limb(sho, arms[0][1], lw * 0.9, shirt.darkened(0.25))
	_limb(arms[0][1], arms[0][2], lw * 0.8, sk.darkened(0.2))
	_limb(hip, legs[0][1], lw * 1.15, sk.darkened(0.2))
	_limb(legs[0][1], legs[0][2], lw, socks.darkened(0.25))
	_limb(legs[0][2], legs[0][2] + Vector2(face * lw * 1.1, 0), lw * 0.9, Color("#151515"))
	# gövde: omuzda geniş, belde dar
	var side := Vector2(-up.y, up.x)
	var tw0 := hgt * 0.085
	var tw1 := hgt * 0.11
	var torso := PackedVector2Array([hip - side * tw0, hip + side * tw0, sho + side * tw1, sho - side * tw1])
	var outl := PackedVector2Array()
	for v in torso:
		outl.append(v)
	draw_colored_polygon(torso, shirt)
	outl.append(torso[0])
	draw_polyline(outl, OUTL, 2.5, true)
	draw_line(hip + side * tw0 * 0.3, sho + side * tw1 * 0.3, shirt.lightened(0.2), lw * 0.35, true)
	# şort
	_limb(hip + up * hgt * 0.02, hip - up * hgt * 0.06, tw0 * 2.0, shorts)
	# ön bacak
	_limb(hip, legs[1][1], lw * 1.15, sk)
	_limb(legs[1][1], legs[1][2], lw, socks)
	_limb(legs[1][2], legs[1][2] + Vector2(face * lw * 1.1, 0), lw * 0.9, Color("#151515"))
	# baş
	var hr := hgt * 0.075
	draw_circle(head, hr + 1.5, OUTL)
	draw_circle(head, hr, sk)
	draw_arc(head + Vector2(-face * hr * 0.1, -hr * 0.05), hr * 0.92, PI + (-0.2 if face > 0 else 0.2) - (PI * 0.5 if face < 0 else 0.0) * 0.0, TAU + (0.2 if face < 0 else -0.2), 14, hair, hr * 0.55, true)
	draw_circle(head + Vector2(face * hr * 0.42, -hr * 0.05), maxf(1.2, hr * 0.12), Color("#141414"))
	draw_circle(head + Vector2(-face * hr * 0.25, hr * 0.05), maxf(1.0, hr * 0.16), sk.darkened(0.15))
	# ön kol
	_limb(sho, arms[1][1], lw * 0.9, shirt)
	_limb(arms[1][1], arms[1][2], lw * 0.8, sk)
	if id == "p":
		var nm := _pname()
		var fs := int(16 + 8 * g.z)
		draw_string_outline(F_COND, head + Vector2(-100, -hr - 16), nm, HORIZONTAL_ALIGNMENT_CENTER, 200, fs, 6, Color(0, 0, 0, 0.75))
		draw_string(F_COND, head + Vector2(-100, -hr - 16), nm, HORIZONTAL_ALIGNMENT_CENTER, 200, fs, Color.WHITE)
		draw_colored_polygon(PackedVector2Array([head + Vector2(-8, -hr - 10), head + Vector2(8, -hr - 10), head + Vector2(0, -hr - 2)]), Color("#ffd23f"))
