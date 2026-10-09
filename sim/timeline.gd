extends RefCounted
## Olay bazlı maç zaman çizelgesi. Skor ve golcüler önceden belli (sim_match);
## bu dosya o skorla tutarlı, oyuncu özelliklerine dayalı pas/çalım/şut... olayları üretir.
## Olay: {t, ty, side, pid, tgt, ok, x, y, aa:[[özellik, p10, eğim]], ta:[[...]]}

const HALF := 2700
const FULL := 5400

const BASE := {
	"GK": Vector2(-49, 0), "CB": Vector2(-35, 0), "LB": Vector2(-31, -24), "RB": Vector2(-31, 24),
	"DM": Vector2(-20, 0), "CM": Vector2(-13, 0), "AM": Vector2(-3, 0),
	"LW": Vector2(5, -23), "RW": Vector2(5, 23), "ST": Vector2(11, 0),
}

static func slots(g, xi: Array) -> Dictionary:
	## pid -> taban pozisyon (kendi kalesi -x'te, hücum +x yönüne)
	var out := {}
	var count := {}
	var by_pos := {}
	for pid in xi:
		var p: Dictionary = g.player(pid)
		var pos: String = p.pos
		if not by_pos.has(pos):
			by_pos[pos] = []
		by_pos[pos].append(pid)
	for pos in by_pos:
		var arr: Array = by_pos[pos]
		var n := arr.size()
		for i in n:
			var b: Vector2 = BASE[pos]
			if n > 1:
				var spread := 18.0 if pos in ["CB", "CM", "DM", "ST", "AM"] else 10.0
				b.y += (float(i) - (n - 1) / 2.0) * spread
				if pos == "ST":
					b.x -= 2.0 * i
			out[arr[i]] = b
	return out

static func dyn_pos(base: Vector2, dir: float, ball: Vector2, has_ball: bool) -> Vector2:
	## Takım topa göre kayar
	var w := Vector2(base.x * dir, base.y * dir)
	var shift := clampf(ball.x * 0.42 + (7.0 if has_ball else -5.0) * dir, -20.0, 20.0)
	w.x += shift
	w.y += (ball.y - w.y) * 0.18
	w.x = clampf(w.x, -51.0, 51.0)
	w.y = clampf(w.y, -32.0, 32.0)
	return w

class Ctx:
	var g
	var rng: RandomNumberGenerator
	var m: Dictionary
	var xi := {"h": [], "a": []}
	var slot := {}
	var form := {}
	var ev := []
	var t := 0
	var ball := Vector2.ZERO
	var side := "h"
	var carrier := ""

	func dir(sd: String) -> float:
		return 1.0 if sd == "h" else -1.0

	func other(sd: String) -> String:
		return "a" if sd == "h" else "h"

	func pos_of(pid: String, sd: String) -> Vector2:
		return Timeline_dyn(slot[pid], dir(sd), ball, sd == side)

	func Timeline_dyn(b: Vector2, d: float, bl: Vector2, hb: bool) -> Vector2:
		var w := Vector2(b.x * d, b.y * d)
		var shift := clampf(bl.x * 0.42 + (7.0 if hb else -5.0) * d, -20.0, 20.0)
		w.x += shift
		w.y += (bl.y - w.y) * 0.18
		return Vector2(clampf(w.x, -51.0, 51.0), clampf(w.y, -32.0, 32.0))

	func attr(pid: String, a: String) -> float:
		var p: Dictionary = g.player(pid)
		var v := float(p.attrs[a]) + float(form.get(pid, 0.0))
		# geç dakikalarda dayanıklılık etkisi
		if t > 4200 and a != "stamina":
			v -= (10.0 - float(p.attrs.stamina)) * 0.12 * (float(t) - 4200.0) / 1200.0
		return v

	func nearest(sd: String, to: Vector2, exclude_gk := true) -> String:
		var best := ""
		var bd := 1e9
		for pid in xi[sd]:
			if exclude_gk and g.player(pid).pos == "GK":
				continue
			var d := pos_of(pid, sd).distance_to(to)
			if d < bd:
				bd = d
				best = pid
		return best

	func gk(sd: String) -> String:
		for pid in xi[sd]:
			if g.player(pid).pos == "GK":
				return pid
		return xi[sd][0]

	func emit(ty: String, sd: String, pid: String, tgt: String, ok: bool, aa: Array, ta: Array) -> void:
		ev.append({"t": t, "ty": ty, "side": sd, "pid": pid, "tgt": tgt, "ok": ok, "x": ball.x, "y": ball.y, "aa": aa, "ta": ta})

	func duel(att_pid: String, att: Array, def_pid: String, defs: Array, base: float, slope: float) -> Dictionary:
		## att/defs: [[özellik, ağırlık]]; başarı olasılığı ve kredi listeleri
		var ae := 0.0
		for x in att:
			ae += attr(att_pid, x[0]) * x[1]
		var de := 10.0
		if def_pid != "":
			de = 0.0
			for x in defs:
				de += attr(def_pid, x[0]) * x[1]
		var p := clampf(base + slope * (ae - de), 0.04, 0.96)
		var aa := []
		for x in att:
			var ae10: float = ae - (attr(att_pid, x[0]) - 10.0) * x[1]
			aa.append([x[0], clampf(base + slope * (ae10 - de), 0.04, 0.96), slope * x[1]])
		var ta := []
		if def_pid != "":
			for x in defs:
				var de10: float = de - (attr(def_pid, x[0]) - 10.0) * x[1]
				# savunmacı için "başarı" = saldırganın başarısız olması
				ta.append([x[0], 1.0 - clampf(base + slope * (ae - de10), 0.04, 0.96), slope * x[1]])
		return {"p": p, "aa": aa, "ta": ta}

static func generate(g, m: Dictionary) -> Array:
	var c := Ctx.new()
	c.g = g
	c.rng = g.rng
	c.m = m
	c.xi.h = m.xi_h
	c.xi.a = m.xi_a
	var sh := slots(g, m.xi_h)
	var sa := slots(g, m.xi_a)
	for k in sh:
		c.slot[k] = sh[k]
	for k in sa:
		c.slot[k] = sa[k]
	for pid in m.xi_h + m.xi_a:
		var p: Dictionary = g.player(pid)
		c.form[pid] = c.rng.randfn(0.0, 2.6 - float(p.hid.consistency) * 0.11) * 0.8
	# önceden belli goller
	var goals := []
	for e in m.ev:
		if e.t == "g":
			goals.append({"t": int(e.min) * 60 - c.rng.randi_range(5, 50), "side": e.side, "pid": e.pid, "as": e.get("as", "")})
	goals.sort_custom(func(a, b): return a.t < b.t)
	_kickoff(c, "h", 0)
	var half_done := false
	var gi := 0
	var guard := 0
	while c.t < FULL and guard < 3000:
		guard += 1
		if not half_done and c.t >= HALF:
			half_done = true
			c.emit("half", c.side, "", "", true, [], [])
			_kickoff(c, "a", HALF + 1)
			continue
		if gi < goals.size() and c.t >= goals[gi].t - 25:
			_goal_sequence(c, goals[gi])
			gi += 1
			continue
		_step(c)
	# kalan goller (zaman taşmışsa)
	while gi < goals.size():
		_goal_sequence(c, goals[gi])
		gi += 1
	c.t = maxi(c.t, FULL)
	c.emit("end", c.side, "", "", true, [], [])
	return c.ev

static func _kickoff(c: Ctx, sd: String, at: int) -> void:
	c.t = at
	c.side = sd
	c.ball = Vector2.ZERO
	var st := ""
	for pid in c.xi[sd]:
		if c.g.player(pid).pos in ["ST", "AM"]:
			st = pid
			break
	if st == "":
		st = c.xi[sd][c.xi[sd].size() - 1]
	c.carrier = st
	c.emit("kickoff", sd, st, "", true, [], [])
	c.t += 3

static func _advance(c: Ctx, lo: int, hi: int) -> void:
	c.t += c.rng.randi_range(lo, hi)

static func _step(c: Ctx) -> void:
	var sd := c.side
	var d := c.dir(sd)
	var prog := c.ball.x * d
	var opp := c.other(sd)
	# pres
	if c.rng.randf() < 0.12 and c.g.player(c.carrier).pos != "GK":
		var pr := c.nearest(opp, c.ball)
		var wts := [["work_rate", 0.7], ["stamina", 0.3]]
		var du := c.duel(pr, wts, c.carrier, [["composure", 0.6], ["first_touch", 0.4]], 0.2, 0.025)
		var won: bool = c.rng.randf() < du.p
		c.emit("press", opp, pr, c.carrier, won, du.aa, du.ta)
		_advance(c, 3, 6)
		if won:
			c.side = opp
			c.carrier = pr
			return
	var r := c.rng.randf()
	var cp: Dictionary = c.g.player(c.carrier)
	if cp.pos == "GK":
		_pass(c, false)
	elif prog > 28.0 and absf(c.ball.y) < 20.0:
		if r < 0.33:
			_shot(c, false, "")
		elif r < 0.8:
			_pass(c, false)
		else:
			_dribble(c)
	elif prog > 20.0 and absf(c.ball.y) >= 16.0:
		if r < 0.42:
			_cross(c)
		elif r < 0.75:
			_pass(c, false)
		else:
			_dribble(c)
	else:
		if r < 0.66:
			_pass(c, false)
		elif r < 0.9:
			_dribble(c)
		else:
			_pass(c, true)

static func _pick_target(c: Ctx, forward_bias: float, long := false) -> String:
	var sd := c.side
	var d := c.dir(sd)
	var cands := []
	var tot := 0.0
	for pid in c.xi[sd]:
		if pid == c.carrier:
			continue
		var p: Dictionary = c.g.player(pid)
		if p.pos == "GK" and c.rng.randf() < 0.85:
			continue
		var tp := c.pos_of(pid, sd)
		var dist := tp.distance_to(c.ball)
		var gain := (tp.x - c.ball.x) * d
		var w := 0.0
		if long:
			w = maxf(0.0, gain - 15.0) + 0.1
		else:
			w = exp(-dist / 18.0) * (1.0 + clampf(gain, -10.0, 25.0) * forward_bias)
		w = maxf(w, 0.01)
		cands.append([pid, w])
		tot += w
	var r := c.rng.randf() * tot
	for x in cands:
		r -= x[1]
		if r <= 0:
			return x[0]
	return cands[0][0] if not cands.is_empty() else c.carrier

static func _pass(c: Ctx, long: bool, forced_tgt := "") -> bool:
	var sd := c.side
	var opp := c.other(sd)
	var tgt := forced_tgt if forced_tgt != "" else _pick_target(c, 0.06, long)
	var tp := c.pos_of(tgt, sd)
	var dist := tp.distance_to(c.ball)
	var mid := (tp + c.ball) / 2.0
	var interceptor := c.nearest(opp, mid)
	var att := [["passing", 1.0]]
	if dist > 24.0:
		att = [["passing", 0.65], ["vision", 0.35]]
	var base := 0.88 - dist / 110.0
	if long:
		base = 0.62
	var du := c.duel(c.carrier, att, interceptor, [["positioning", 0.6], ["decisions", 0.4]], base, 0.024)
	var ok: bool = forced_tgt != "" or c.rng.randf() < du.p
	c.emit("pass", sd, c.carrier, tgt if ok else interceptor, ok, du.aa, du.ta if not ok else [])
	_advance(c, 3, 6 + int(dist / 10.0))
	if ok:
		c.ball = tp + Vector2(c.rng.randf_range(-2, 2), c.rng.randf_range(-2, 2))
		c.carrier = tgt
		if long:
			# uzun top: hız yarışı
			var defender := c.nearest(opp, c.ball)
			var race := c.duel(tgt, [["pace", 1.0]], defender, [["pace", 1.0]], 0.5, 0.04)
			var won: bool = c.rng.randf() < race.p
			c.emit("sprint", sd, tgt, defender, won, race.aa, race.ta)
			_advance(c, 3, 5)
			if not won:
				c.side = opp
				c.carrier = defender
				return false
	else:
		c.ball = mid
		c.side = opp
		c.carrier = interceptor
	return ok

static func _dribble(c: Ctx) -> void:
	var sd := c.side
	var d := c.dir(sd)
	var opp := c.other(sd)
	var defender := c.nearest(opp, c.ball + Vector2(4.0 * d, 0))
	var du := c.duel(c.carrier, [["dribbling", 0.55], ["agility", 0.25], ["pace", 0.2]], defender,
		[["tackling", 0.6], ["positioning", 0.4]], 0.5, 0.03)
	var ok: bool = c.rng.randf() < du.p
	c.emit("dribble", sd, c.carrier, defender, ok, du.aa, du.ta)
	_advance(c, 3, 6)
	if ok:
		c.ball.x = clampf(c.ball.x + d * c.rng.randf_range(6, 11), -50, 50)
		c.ball.y = clampf(c.ball.y + c.rng.randf_range(-4, 4), -32, 32)
	else:
		if c.rng.randf() < 0.12:
			c.emit("foul", opp, defender, c.carrier, true, [], [])
			_advance(c, 8, 15)
			return
		c.side = opp
		c.carrier = defender

static func _cross(c: Ctx) -> void:
	var sd := c.side
	var d := c.dir(sd)
	var opp := c.other(sd)
	var du := c.duel(c.carrier, [["crossing", 1.0]], "", [], 0.4, 0.03)
	var ok: bool = c.rng.randf() < du.p
	c.emit("cross", sd, c.carrier, "", ok, du.aa, [])
	_advance(c, 2, 4)
	var box := Vector2(44.0 * d, c.rng.randf_range(-6, 6))
	c.ball = box
	if not ok:
		var cb := c.nearest(opp, box)
		c.side = opp
		c.carrier = cb
		return
	# kafa düellosu
	var attacker := ""
	var best := -1.0
	for pid in c.xi[sd]:
		var p: Dictionary = c.g.player(pid)
		if p.pos in ["ST", "AM", "LW", "RW", "CB"] and pid != c.carrier:
			var v := float(p.attrs.heading) + (3.0 if p.pos == "ST" else 0.0) + c.rng.randf_range(0, 4)
			if v > best:
				best = v
				attacker = pid
	if attacker == "":
		attacker = c.xi[sd][c.xi[sd].size() - 1]
	var defender := c.nearest(opp, box)
	var hd := c.duel(attacker, [["heading", 0.7], ["strength", 0.3]], defender, [["heading", 0.6], ["strength", 0.4]], 0.45, 0.035)
	var won: bool = c.rng.randf() < hd.p
	c.emit("header", sd, attacker, defender, won, hd.aa, hd.ta)
	_advance(c, 1, 3)
	if won:
		c.carrier = attacker
		_shot(c, false, "", true)
	else:
		c.side = opp
		c.carrier = defender
		c.ball = Vector2(38.0 * d, c.ball.y)

static func _shot(c: Ctx, is_goal: bool, assister: String, header := false) -> void:
	var sd := c.side
	var d := c.dir(sd)
	var opp := c.other(sd)
	var goal := Vector2(52.5 * d, 0)
	var dist := c.ball.distance_to(goal)
	var att := [["finishing", 0.7], ["composure", 0.3]]
	if header:
		att = [["heading", 0.6], ["finishing", 0.2], ["composure", 0.2]]
	var du := c.duel(c.carrier, att, "", [], 0.42 - dist / 140.0, 0.03)
	var on: bool = is_goal or c.rng.randf() < du.p
	c.emit("shot", sd, c.carrier, assister, on, du.aa if not is_goal else _credit_ok(du.aa), [])
	_advance(c, 1, 2)
	var keeper := c.gk(opp)
	if is_goal:
		c.ball = goal
		c.emit("goal", sd, c.carrier, assister, true, [], [])
		return
	if on:
		var sv := c.duel(keeper, [["reflexes", 0.65], ["handling", 0.35]], "", [], 0.7, 0.025)
		var held: bool = c.rng.randf() < sv.p
		c.ball = goal * 0.97
		c.emit("save", opp, keeper, c.carrier, held, sv.aa, [])
		_advance(c, 4, 8)
		if not held:
			c.emit("corner", sd, c.carrier, "", true, [], [])
			_advance(c, 15, 25)
	else:
		c.ball = goal + Vector2(0, c.rng.randf_range(-12, 12))
		_advance(c, 10, 18)
	c.side = opp
	c.carrier = keeper
	c.ball = Vector2(47.0 * d, c.rng.randf_range(-6, 6))

static func _credit_ok(aa: Array) -> Array:
	return aa

static func _goal_sequence(c: Ctx, gl: Dictionary) -> void:
	var sd: String = gl.side
	var d := c.dir(sd)
	var opp := c.other(sd)
	c.t = maxi(c.t, int(gl.t) - 20)
	if c.side != sd:
		# top kazanımı
		var winner := c.nearest(sd, c.ball)
		var loser := c.carrier
		var du := c.duel(winner, [["tackling", 0.6], ["positioning", 0.4]], loser, [["dribbling", 0.6], ["composure", 0.4]], 0.5, 0.03)
		c.emit("tackle", sd, winner, loser, true, du.aa, du.ta)
		c.side = sd
		c.carrier = winner
		_advance(c, 2, 4)
	var scorer: String = gl.pid
	var asst: String = gl.get("as", "")
	# hücum hazırlığı
	for i in c.rng.randi_range(1, 3):
		var tgt := _pick_target(c, 0.12)
		if tgt == scorer or tgt == asst:
			continue
		_pass(c, false, tgt)
	if asst != "" and asst != c.carrier:
		_pass(c, false, asst)
	c.ball = Vector2(c.rng.randf_range(36, 44) * d, c.rng.randf_range(-12, 12))
	if asst != "":
		var tp := Vector2(c.rng.randf_range(40, 46) * d, c.rng.randf_range(-7, 7))
		c.emit("pass", sd, asst, scorer, true, [["passing", 0.75, 0.024], ["vision", 0.75, 0.012]], [])
		_advance(c, 2, 3)
		c.ball = tp
	else:
		c.emit("dribble", sd, scorer, c.nearest(opp, c.ball), true, [["dribbling", 0.5, 0.017]], [])
		_advance(c, 2, 4)
		c.ball = Vector2(c.rng.randf_range(38, 45) * d, c.rng.randf_range(-8, 8))
	c.carrier = scorer
	_shot(c, true, asst)
	c.t += c.rng.randi_range(40, 60)
	_kickoff(c, opp, c.t)

# ================================================================ toplama

static func aggregate(g, tl: Array, pids: Array) -> Dictionary:
	var out := {}
	for pid in pids:
		out[pid] = {"n_events": 0, "attr": {}, "st": {"pass": 0, "pass_ok": 0, "drib": 0, "drib_ok": 0, "tkl": 0, "tkl_ok": 0,
			"shots": 0, "on": 0, "goals": 0, "assists": 0, "saves": 0, "saves_ok": 0, "cross": 0, "cross_ok": 0,
			"air": 0, "air_ok": 0, "press": 0, "press_ok": 0, "sprint": 0, "sprint_ok": 0, "late_ok": 0, "late": 0}}
	for e in tl:
		var a: String = e.pid
		var b: String = e.tgt
		if out.has(a):
			out[a].n_events += 1
			_credit(out[a], e.aa, e.ok)
			_stat_actor(out[a].st, e)
			if e.t > 4200 and e.ty in ["pass", "dribble", "press", "sprint"]:
				out[a].st.late += 1
				if e.ok:
					out[a].st.late_ok += 1
		if b != "" and out.has(b) and b != a:
			out[b].n_events += 1
			if not e.ta.is_empty():
				_credit(out[b], e.ta, not e.ok)
			_stat_target(out[b].st, e)
	return out

static func _credit(ag: Dictionary, credits: Array, ok: bool) -> void:
	## Doğrusal model: başarı ~ p10 + eğim*(özellik-10). Bayesçi güncelleme için yeterli istatistikler.
	for cr in credits:
		var a: String = cr[0]
		if not ag.attr.has(a):
			ag.attr[a] = {"n": 0, "num": 0.0, "den": 0.0}
		var d: Dictionary = ag.attr[a]
		var p10 := float(cr[1])
		var sl := float(cr[2])
		var v := maxf(0.09, p10 * (1.0 - p10))
		d.n += 1
		d.num += sl * ((1.0 if ok else 0.0) - p10 + 10.0 * sl) / v
		d.den += sl * sl / v

static func _stat_actor(st: Dictionary, e: Dictionary) -> void:
	match e.ty:
		"pass":
			st.pass += 1
			if e.ok:
				st.pass_ok += 1
		"dribble":
			st.drib += 1
			if e.ok:
				st.drib_ok += 1
		"tackle":
			st.tkl += 1
			st.tkl_ok += 1
		"shot":
			st.shots += 1
			if e.ok:
				st.on += 1
		"goal":
			st.goals += 1
		"save":
			st.saves += 1
			if e.ok:
				st.saves_ok += 1
		"cross":
			st.cross += 1
			if e.ok:
				st.cross_ok += 1
		"header":
			st.air += 1
			if e.ok:
				st.air_ok += 1
		"press":
			st.press += 1
			if e.ok:
				st.press_ok += 1
		"sprint":
			st.sprint += 1
			if e.ok:
				st.sprint_ok += 1

static func _stat_target(st: Dictionary, e: Dictionary) -> void:
	match e.ty:
		"dribble":
			st.tkl += 1
			if not e.ok:
				st.tkl_ok += 1
		"pass":
			if not e.ok:
				st.tkl += 1
				st.tkl_ok += 1
		"header":
			st.air += 1
			if not e.ok:
				st.air_ok += 1
		"sprint":
			st.sprint += 1
			if not e.ok:
				st.sprint_ok += 1
		"goal":
			if e.tgt != "":
				st.assists += 1

static func implied(ag: Dictionary, a: String, prior := 10.0) -> float:
	## Bu maçın kanıtına göre (zayıf öncül ile) özellik tahmini
	if not ag.attr.has(a):
		return -1.0
	var d: Dictionary = ag.attr[a]
	var inv0 := 1.0 / 16.0
	return clampf((prior * inv0 + float(d.num)) / (inv0 + float(d.den)), 1.0, 20.0)

static func notes_for(g, pid: String, ag: Dictionary, m: Dictionary) -> Array:
	var p: Dictionary = g.player(pid)
	var scored := []
	for a in ag.attr:
		var n: int = ag.attr[a].n
		if n < 3:
			continue
		scored.append([implied(ag, a, 11.0), a, n])
	scored.sort_custom(func(x, y): return x[0] > y[0])
	var notes := []
	if scored.is_empty():
		notes.append(["nt_quiet", []])
	else:
		var top = scored[0]
		notes.append(["nt_%s_%s" % [top[1], "hi" if top[0] >= 13.5 else "mid"], []])
		if scored.size() > 2 and scored[1][0] >= 14.0:
			notes.append(["nt_%s_hi" % scored[1][1], []])
		var low = scored[scored.size() - 1]
		if scored.size() > 1 and low[0] <= 8.5:
			notes.append(["nt_%s_lo" % low[1], []])
	var st: Dictionary = ag.st
	if st.goals > 0:
		notes.append(["nt_goals", [st.goals]])
	if st.assists > 0:
		notes.append(["nt_assists", [st.assists]])
	if st.late >= 4:
		var rate := float(st.late_ok) / float(st.late)
		if rate < 0.4:
			notes.append(["nt_stamina_lo", []])
	for e in m.ev:
		if e.t == "inj" and e.pid == pid:
			notes.append(["nt_injured", [e.min]])
	var opp: Dictionary = g.club(m.a if pid in m.xi_h else m.h)
	if opp.prestige >= 80:
		var bm := float(p.hid.big_match)
		if bm >= 15 and g.rf() < 0.6:
			notes.append(["nt_bigmatch_hi", []])
		elif bm <= 6 and g.rf() < 0.6:
			notes.append(["nt_bigmatch_lo", []])
	if float(p.hid.professionalism) >= 16 and g.rf() < 0.25:
		notes.append(["nt_pro_hi", []])
	if float(p.hid.professionalism) <= 5 and g.rf() < 0.25:
		notes.append(["nt_pro_lo", []])
	return notes

static func stat_line(ag: Dictionary) -> Array:
	var st: Dictionary = ag.st
	if st.saves > 0 and st.pass < 15 and st.drib == 0:
		return ["line_gk", [st.saves_ok, st.saves, st.pass_ok, st.pass]]
	return ["line_out", [st.pass_ok, st.pass, st.drib_ok, st.drib, st.tkl_ok, st.tkl, st.on, st.shots]]
