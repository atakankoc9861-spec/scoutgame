extends RefCounted
## Canlı maç motoru: 22 bağımsız karar veren oyuncu.
## Topa sahip oyuncu seçeneklerini (pas, çalım, şut, orta, top saklama) özelliklerine göre
## değerlendirir; görüş (vision) hangi arkadaşlarını gördüğünü, karar (decisions) seçimin
## isabetini belirler. Sonuçlar ikili düellolarla çözülür ve zaman çizelgesi biçiminde olay
## üretir (bilgi modeli bu olaylardan öğrenir). İzleyici aynı simülasyonu canlı oynatır.
## Koordinatlar: x boy (-52.5..52.5, ev sahibi +x'e hücum eder), y en (-34..34).

const DT := 0.1
const CLOCK_K := 4.0           # 1 sim saniyesi = 4 maç saniyesi (90 dk ≈ 22.5 dk sim)
const HALF := 2700.0
const FULL := 5400.0
const L := 52.5
const W := 34.0
const BASE := {
	"GK": Vector2(-49, 0), "CB": Vector2(-35, 0), "LB": Vector2(-31, -24), "RB": Vector2(-31, 24),
	"DM": Vector2(-20, 0), "CM": Vector2(-13, 0), "AM": Vector2(-3, 0),
	"LW": Vector2(5, -23), "RW": Vector2(5, 23), "ST": Vector2(11, 0),
}

class Pl:
	var id := ""
	var side := "h"
	var d := 1.0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var face := Vector2.RIGHT
	var base := Vector2.ZERO
	var role := "CM"
	var gk := false
	var a := {}
	var vmax := 7.5
	var acc := 6.0
	var fx := 0.5
	var stun := 0.0
	var decide_t := 0.0
	var tackle_cd := 0.0
	var think_t := 0.0
	var spot := Vector2.INF
	var run_to := Vector2.INF
	var run_t := 0.0
	var seed := 0.0
	var st := {}
	var yel := 0
	var off := false

var g
var m: Dictionary
var youth := false
var rng := RandomNumberGenerator.new()
var pl := {}
var team := {"h": [], "a": []}
var t := 0.0
var clock := 0.0
var score := [0, 0]
var ball := Vector2.ZERO
var ball_h := 0.0
var bvel := Vector2.ZERO
var owner: Pl = null
var flight := {}
var last: Pl = null
var last_pass := {}             # asist takibi: {pid, t}
var poss := "h"
var phase := "dead"
var dead_t := 0.0
var restart := {}
var events: Array = []
var anims: Array = []
var shots := {"h": 0, "a": 0}
var half_done := false
var finished := false
var stoppage := 0.0
var celebrate_t := 0.0
var scorer := ""
var form := {}
var dbg := {"dec": 0, "dec_f3": 0, "shot_opt": 0, "pick": {}, "lx_sum": 0.0}

# ================================================================ kurulum

func setup(game, match_d: Dictionary, is_youth: bool, seed_v := 0) -> void:
	g = game
	m = match_d
	youth = is_youth
	if seed_v != 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	if not m.has("xi_h") or m.xi_h.is_empty():
		m.xi_h = g.best_xi(m.h, true, youth)
		m.xi_a = g.best_xi(m.a, true, youth)
	for sd in ["h", "a"]:
		var xi: Array = m["xi_" + sd]
		var slots := _slots(xi)
		for pid in xi:
			var p: Dictionary = g.player(pid)
			var q := Pl.new()
			q.id = pid
			q.side = sd
			q.d = 1.0 if sd == "h" else -1.0
			q.role = p.pos
			q.gk = p.pos == "GK"
			q.base = slots[pid]
			q.fx = clampf((q.base.x + 35.0) / 46.0, 0.0, 1.0)
			var fm := rng.randfn(0.0, 2.6 - float(p.hid.consistency) * 0.11) * 0.8
			if sd == "h" and not youth:
				fm += 0.3   # ev sahibi avantajı
			if not youth and g.club(m.h if sd == "a" else m.a).get("prestige", 0) >= 80:
				fm += (float(p.hid.big_match) - 10.0) * 0.06
			form[pid] = fm
			for k in p.attrs:
				q.a[k] = clampf(float(p.attrs[k]) + fm, 1.0, 20.0)
			q.vmax = 6.3 + q.a.pace * 0.14
			q.acc = 4.6 + q.a.agility * 0.13
			q.seed = rng.randf() * TAU
			q.st = {"p": 0, "po": 0, "kp": 0, "d": 0, "do": 0, "t": 0, "s": 0, "so": 0, "g": 0, "as": 0, "sv": 0, "err": 0, "air": 0, "air_ok": 0}
			pl[pid] = q
			team[sd].append(q)
	# hız/çeviklik de maç seviyesine göre (alt ligler yavaş çekim gibi oynamasın)
	for q: Pl in pl.values():
		q.vmax = 6.3 + at(q, "pace") * 0.14
		q.acc = 4.6 + at(q, "agility") * 0.13
	_kickoff("h")

func _slots(xi: Array) -> Dictionary:
	var out := {}
	var by_pos := {}
	for pid in xi:
		var pos: String = g.player(pid).pos
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

# ================================================================ yardımcılar

func other(sd: String) -> String:
	return "a" if sd == "h" else "h"

func at(q: Pl, k: String) -> float:
	## Maçın kendi seviyesine göre ölçeklenmiş özellik: 10 + (değer - bu maçtaki ortalama).
	## Böylece BAL ligi ile Süper Lig aynı oyun temposunda oynar; farkı oyuncular arası fark belirler.
	var v: float = 10.0 + (float(q.a[k]) - _raw_avg(k)) * float(_raw_cache.get(k + "#f", 1.0))
	if clock > 4200.0 and k != "stamina":
		v -= (10.0 - at(q, "stamina")) * 0.12 * (clock - 4200.0) / 1200.0
	return v

func duel(att: Pl, aw: Array, def: Pl, dw: Array, base: float, slope: float) -> Dictionary:
	## timeline.gd ile aynı biçim: p ve özellik kredileri [özellik, p10, eğim]
	var ae := 0.0
	for x in aw:
		ae += at(att, x[0]) * x[1]
	var de := 0.0
	if def == null:
		# rakipsiz düello: sabit 10 yerine bu maçtaki oyuncuların ortalaması (lig seviyesinden bağımsız)
		for x in aw:
			de += _avg_attr(x[0]) * x[1]
	else:
		de = 0.0
		for x in dw:
			de += at(def, x[0]) * x[1]
	slope *= 1.2   # oyuncu kalitesinin etkisini belirginleştir
	var p := clampf(base + slope * (ae - de), 0.04, 0.96)
	var aa := []
	for x in aw:
		var ae10: float = ae - (at(att, x[0]) - 10.0) * x[1]
		aa.append([x[0], clampf(base + slope * (ae10 - de), 0.04, 0.96), slope * x[1]])
	var ta := []
	if def != null:
		for x in dw:
			var de10: float = de - (at(def, x[0]) - 10.0) * x[1]
			ta.append([x[0], 1.0 - clampf(base + slope * (ae - de10), 0.04, 0.96), slope * x[1]])
	return {"p": p, "aa": aa, "ta": ta}

var _raw_cache := {}

func _raw_avg(k: String) -> float:
	if not _raw_cache.has(k):
		var tot := 0.0
		var n := 0
		for q: Pl in pl.values():
			var gk_attr: bool = k in ["reflexes", "handling"]
			if q.gk != gk_attr and not (k == "stamina"):
				continue
			tot += float(q.a[k])
			n += 1
		var avg := tot / float(n) if n > 0 else 10.0
		var var_sum := 0.0
		for q: Pl in pl.values():
			var gk2: bool = k in ["reflexes", "handling"]
			if q.gk != gk2 and not (k == "stamina"):
				continue
			var_sum += pow(float(q.a[k]) - avg, 2.0)
		var sd := sqrt(var_sum / float(maxi(1, n)))
		# çok geniş yetenek farkı olan maçlarda (dev - küçük) farkı biraz sıkıştır
		_raw_cache[k + "#f"] = clampf(2.6 / maxf(0.1, sd), 0.6, 1.0)
		_raw_cache[k] = avg
	return _raw_cache[k]

var _avg_cache := {}

func _avg_attr(k: String) -> float:
	if not _avg_cache.has(k):
		var tot := 0.0
		var n := 0
		for q: Pl in pl.values():
			if q.gk and k != "reflexes" and k != "handling":
				continue
			tot += at(q, k)
			n += 1
		_avg_cache[k] = tot / maxf(1.0, float(n)) if n > 0 else 10.0
	return _avg_cache[k]

func emit(ty: String, sd: String, pid: String, tgt: String, ok: bool, aa: Array, ta: Array) -> void:
	events.append({"t": int(clock), "ty": ty, "side": sd, "pid": pid, "tgt": tgt, "ok": ok,
		"x": ball.x, "y": ball.y, "aa": aa, "ta": ta, "st": t})

func anim(q: Pl, name: String, dur := 0.5, side := 1.0) -> void:
	anims.append([q.id, name, dur, side])

func value(p: Vector2, d: float) -> float:
	## Konum değeri (beklenen tehdit benzeri): kaleye yakın ve merkezde yüksek
	## ~ bu konumdan sonraki birkaç hamlede gol olasılığı (xT benzeri)
	var lx := p.x * d
	var prog := clampf((lx + L) / (2.0 * L), 0.0, 1.0)
	var central := 1.0 - clampf(absf(p.y) / W, 0.0, 1.0) * 0.5
	var v := pow(prog, 3.0) * central * 0.16
	if lx > 30.0:
		v += xg(p, d) * 0.7
	return v

func xg(p: Vector2, d: float) -> float:
	var goal := Vector2(L * d, 0)
	var dist := p.distance_to(goal)
	var ang := absf(atan2(absf(p.y), maxf(0.5, L - p.x * d)))
	var q := 0.55 * exp(-dist / 9.5) * (1.0 - clampf(ang / 1.25, 0.0, 0.85))
	return clampf(q, 0.005, 0.6)

func nearest_opp(q: Pl, p: Vector2) -> Pl:
	var best: Pl = null
	var bd := 1e9
	for o: Pl in team[other(q.side)]:
		var dd := o.pos.distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = o
	return best

func pressure_on(q: Pl) -> float:
	var o := nearest_opp(q, q.pos)
	if o == null:
		return 0.0
	return clampf(1.0 - (o.pos.distance_to(q.pos) - 1.0) / 6.0, 0.0, 1.0)

func keeper(sd: String) -> Pl:
	for q: Pl in team[sd]:
		if q.gk:
			return q
	return team[sd][0]

func intense() -> bool:
	## İzleyici için: bu an gerçek hızda mı gösterilmeli
	if celebrate_t > 0.0 or phase == "dead" and restart.get("k", "") in ["corner", "free"]:
		return true
	if not flight.is_empty() and flight.k in ["shot", "cross"]:
		return true
	var d := 1.0 if poss == "h" else -1.0
	return ball.x * d > 20.0

# ================================================================ ana adım

func step(dt := DT) -> void:
	if finished:
		return
	t += dt
	if phase != "dead" or restart.get("k", "") != "goal":
		clock += dt * CLOCK_K
	if celebrate_t > 0.0:
		celebrate_t -= dt
	for q: Pl in pl.values():
		q.stun = maxf(0.0, q.stun - dt)
		q.tackle_cd = maxf(0.0, q.tackle_cd - dt)
	# devre ve bitiş
	if not half_done and clock >= HALF + stoppage and phase != "dead":
		half_done = true
		emit("half", poss, "", "", true, [], [])
		_kickoff("a")
		stoppage = rng.randf_range(60.0, 240.0)
		return
	if half_done and clock >= FULL + stoppage and phase != "dead":
		finished = true
		emit("end", poss, "", "", true, [], [])
		return
	if phase == "dead":
		dead_t -= dt
		_move_all(dt)
		if dead_t <= 0.0:
			_do_restart()
		return
	_update_ball(dt)
	if owner != null and phase == "play":
		owner.decide_t -= dt
		if owner.decide_t > 0.25 and pressure_on(owner) > 0.65:
			owner.decide_t = 0.25
		_defend_owner(dt)
		if owner != null and owner.decide_t <= 0.0 and owner.stun <= 0.0:
			_decide(owner)
	_move_all(dt)

# ================================================================ top fiziği

func _update_ball(dt: float) -> void:
	if owner != null:
		# top ayağın önünde, dokunuşlarla yumuşakça takip eder
		var sp := owner.vel.length()
		var lead := owner.face * (0.45 + clampf(sp / 8.0, 0.0, 1.0) * (0.3 + 0.25 * absf(sin(t * 5.5))))
		var want := owner.pos + lead
		ball = ball.lerp(want, minf(1.0, dt * 9.0)) if ball.distance_to(want) < 3.0 else want
		ball_h = 0.0
		last = owner
		poss = owner.side
		return
	if not flight.is_empty():
		flight.e += dt
		var f := clampf(flight.e / flight.dur, 0.0, 1.0)
		var ef := f if flight.k != "ground" else 1.0 - pow(1.0 - f, 1.5)
		ball = (flight.from as Vector2).lerp(flight.to, ef)
		ball_h = sin(f * PI) * float(flight.h)
		if flight.k == "shot":
			ball_h = lerpf(0.2, float(flight.z), f) + sin(f * PI) * 0.4
		if f >= 1.0:
			_arrive()
		return
	# serbest top
	ball += bvel * dt
	var sp := bvel.length()
	if sp > 0.01:
		bvel = bvel.normalized() * maxf(0.0, sp - 4.0 * dt)
	ball_h = 0.0
	if absf(ball.x) > L or absf(ball.y) > W:
		_out_of_play()
		return
	# en yakın oyuncu topu alır
	var best: Pl = null
	var bd := 1.3
	for q: Pl in pl.values():
		if q.stun > 0.0 or q.off:
			continue
		var dd := q.pos.distance_to(ball)
		if dd < bd:
			bd = dd
			best = q
	if best != null:
		_gain(best, false)

func _gain(q: Pl, controlled: bool) -> void:
	owner = q
	flight = {}
	bvel = Vector2.ZERO
	poss = q.side
	last = q
	q.decide_t = _think_time(q) * (0.6 if controlled else 1.0)

func _think_time(q: Pl) -> float:
	## Karar hızı: iyi karar verenler daha hızlı ve baskı altında daha net
	return clampf(0.9 - at(q, "decisions") * 0.025 + rng.randf_range(-0.1, 0.25), 0.3, 1.1)

func _arrive() -> void:
	var fl := flight
	flight = {}
	ball = fl.to
	match fl.k:
		"ground", "loft":
			var r: Pl = pl.get(fl.recv, null)
			if r != null and r.pos.distance_to(ball) < 3.5:
				# ilk dokunuş: baskı altında kontrol
				var pr := pressure_on(r)
				if pr > 0.45 and rng.randf() > 0.55 + at(r, "first_touch") * 0.022 + at(r, "composure") * 0.01:
					bvel = Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
					r.st.err += 1
					last = r
					return
				_gain(r, true)
				return
			# hedefte kimse yok: serbest top
			bvel = (fl.to - fl.from).normalized() * 3.0
		"cross":
			_aerial(fl)
		"shot":
			_shot_arrive(fl)
		"clear":
			bvel = (fl.to - fl.from).normalized() * 4.0

func _out_of_play() -> void:
	var lt: Pl = last if last != null else team.h[0]
	if absf(ball.y) > W:
		# taç
		var sd := other(lt.side)
		_set_restart("throw", sd, Vector2(clampf(ball.x, -L + 1, L - 1), signf(ball.y) * (W - 0.3)))
		return
	# kale çizgisi
	var end_d := signf(ball.x)
	var def_side := "h" if end_d < 0 else "a"
	if lt.side == def_side:
		_set_restart("corner", other(def_side), Vector2(end_d * (L - 0.4), signf(ball.y if ball.y != 0 else 1.0) * (W - 0.4)))
		g_emit_corner(other(def_side))
	else:
		_set_restart("goalkick", def_side, Vector2(end_d * (L - 5.5), rng.randf_range(-6, 6)))

func g_emit_corner(sd: String) -> void:
	var tk := _best(team[sd], "crossing")
	emit("corner", sd, tk.id, "", true, [], [])

# ================================================================ karar verme

func _gk_decide(o: Pl) -> void:
	## Kaleci topla: güvenli kısa pas ya da uzun degaj; asla riskli pas yok
	var d := o.d
	o.face = Vector2(d, 0)
	var near_opp := nearest_opp(o, o.pos)
	var danger := near_opp != null and near_opp.pos.distance_to(o.pos) < 14.0
	var best: Pl = null
	var bv := -1e9
	if not danger:
		for mt: Pl in team[o.side]:
			if mt == o:
				continue
			var dist := mt.pos.distance_to(o.pos)
			if dist < 8.0 or dist > 40.0:
				continue
			var speed := clampf(10.0 + dist * 0.35, 12.0, 24.0)
			var risk := _lane_risk(o, mt.pos, speed)
			var mp := pressure_on(mt)
			if risk > 0.2 or mp > 0.5:
				continue
			var v := value(mt.pos, d) - risk * 0.3 + rng.randf() * 0.02
			if v > bv:
				bv = v
				best = mt
	if best != null:
		var dist2 := best.pos.distance_to(o.pos)
		_do_pass(o, {"to": best, "tp": best.pos, "p": 0.95, "v": bv, "long": dist2 > 30.0, "speed": clampf(10.0 + dist2 * 0.35, 12.0, 24.0), "risk": 0.05})
		return
	# uzun degaj: kanatlara/forvete doğru
	var to := Vector2(d * rng.randf_range(5.0, 25.0), rng.randf_range(-22.0, 22.0))
	var fw := _forward(o.side)
	if fw != null and rng.randf() < 0.6:
		to = fw.pos + Vector2(d * 3.0, rng.randf_range(-4.0, 4.0))
	to = Vector2(clampf(to.x, -L + 1, L - 1), clampf(to.y, -W + 1, W - 1))
	_kick(o, to, 24.0, "loft", minf(o.pos.distance_to(to) * 0.18, 13.0), "")
	emit("pass", o.side, o.id, "", true, [], [])
	o.st.p += 1

func _decide(o: Pl) -> void:
	if o.gk:
		_gk_decide(o)
		return
	var d := o.d
	var opts := []
	var press := pressure_on(o)
	var lx := o.pos.x * d
	var cur_v := value(o.pos, d)
	var loss := 0.012 + value(o.pos, -d) * 0.7
	# şut
	if lx > 15.0 and absf(o.pos.y) < 26.0:
		var q := xg(o.pos, d) * (0.6 + at(o, "finishing") * 0.03) * (1.0 - press * 0.3)
		# karşı karşıya: kaleyle arasında savunmacı yoksa şut çok daha cazip
		var goal_p := Vector2(L * d, 0)
		var blockers := 0
		for op: Pl in team[other(o.side)]:
			if op.gk:
				continue
			var seg := goal_p - o.pos
			var tp2 := clampf((op.pos - o.pos).dot(seg) / maxf(0.01, seg.length_squared()), 0.0, 1.0)
			if (o.pos + seg * tp2).distance_to(op.pos) < 2.5:
				blockers += 1
		var mult := 1.05
		if blockers == 0 and lx > 30.0:
			mult = 2.0
		elif blockers == 0:
			mult = 1.5
		opts.append({"k": "shot", "v": q * mult})
	# paslar
	var vis := at(o, "vision")
	var off_line := _offside_line(o.side)
	for mt: Pl in team[o.side]:
		if mt == o or mt.stun > 0.0:
			continue
		var dist := mt.pos.distance_to(o.pos)
		if dist < 4.0 or dist > 55.0:
			continue
		var fwd := (mt.pos.x - o.pos.x) * d
		var see_p := 0.92 - maxf(0.0, dist - 18.0) / 60.0 + (vis - 10.0) * 0.03 - (0.25 if fwd > 15.0 else 0.0)
		if mt.gk:
			see_p -= 0.5
		if rng.randf() > see_p:
			continue
		var speed := clampf(10.0 + dist * 0.35, 12.0, 24.0)
		var tf := dist / speed
		var tp: Vector2 = mt.pos + mt.vel * tf * 0.85
		# ara pas: koşan arkadaşın önüne (görüş yüksekse)
		if fwd > 0.0 and mt.vel.x * d > 3.0 and vis > 11.0:
			tp += Vector2(d * (vis - 9.0) * 0.5, 0)
		tp = Vector2(clampf(tp.x, -L + 1, L - 1), clampf(tp.y, -W + 1, W - 1))
		var offs := false
		if tp.x * d > off_line and mt.pos.x * d > off_line - 0.5:
			# çoğunlukla görülür; bazen pasör/koşucu zamanlamayı kaçırır
			if rng.randf() > 0.06 + (10.0 - minf(at(o, "decisions"), 10.0)) * 0.01:
				continue
			offs = mt.pos.x * d > off_line + 0.3
		var risk := _lane_risk(o, tp, speed)
		var long := dist > 30.0
		var acc_q := (at(o, "passing") * (0.65 if long else 1.0) + (at(o, "vision") * 0.35 if long else 0.0) - 10.0) * 0.022
		var ps := clampf(0.97 - dist / 150.0 - risk * 0.6 + acc_q - press * 0.1, 0.05, 0.98)
		var mp := pressure_on(mt)
		var v := ps * (value(tp, d) * (1.0 - mp * 0.3) + 0.004) - (1.0 - ps) * loss
		opts.append({"k": "pass", "to": mt, "tp": tp, "p": ps, "v": v, "long": long, "speed": speed, "risk": risk, "offside": offs})
	# çalım / top sürme
	var opp := nearest_opp(o, o.pos + Vector2(4.0 * d, 0))
	var dir := Vector2(d, 0)
	if opp != null:
		var away := (o.pos - opp.pos).normalized()
		dir = (dir * 1.0 + away * 0.6).normalized()
		if absf(o.pos.y) > W - 6:
			dir.y = -signf(o.pos.y) * absf(dir.y)
	var carry_to := o.pos + dir * 8.0
	carry_to = Vector2(clampf(carry_to.x, -L + 2, L - 2), clampf(carry_to.y, -W + 2, W - 2))
	var near := opp != null and opp.pos.distance_to(o.pos) < 6.0
	var pd := 0.93 if not near else clampf(0.5 + (at(o, "dribbling") * 0.55 + at(o, "agility") * 0.25 + at(o, "pace") * 0.2 - (at(opp, "tackling") * 0.6 + at(opp, "positioning") * 0.4)) * 0.03, 0.1, 0.9)
	var dv := pd * value(carry_to, d) - (1.0 - pd) * loss
	if near:
		dv -= 0.006 - (at(o, "dribbling") - 10.0) * 0.0006
	else:
		dv += 0.002
	opts.append({"k": "dribble", "to": carry_to, "p": pd, "near": near, "opp": opp, "v": dv})
	# orta
	if lx > 22.0 and absf(o.pos.y) > 11.0:
		var targets := 0.0
		for mt: Pl in team[o.side]:
			if mt.pos.x * d > 36.0 and absf(mt.pos.y) < 14.0:
				targets += 0.5 + at(mt, "heading") * 0.03
		var pc := 0.3 + at(o, "crossing") * 0.025
		opts.append({"k": "cross", "v": pc * minf(targets, 2.5) * 0.085})
	# kaleci/defans: tehlikede uzaklaştır
	if lx < -30.0 and press > 0.6:
		opts.append({"k": "clear", "v": 0.0})
	# seçim: softmax, sıcaklık karar özelliğine bağlı
	var temp := clampf(0.008 - (at(o, "decisions") - 10.0) * 0.0005, 0.003, 0.016)
	var mx := -1e9
	for op in opts:
		mx = maxf(mx, op.v)
	var tot := 0.0
	for op in opts:
		op.w = exp((op.v - mx) / temp)
		tot += op.w
	var r := rng.randf() * tot
	var pick: Dictionary = opts[0]
	for op in opts:
		r -= op.w
		if r <= 0.0:
			pick = op
			break
	dbg.dec += 1
	dbg.lx_sum += lx
	if lx > 17.5:
		dbg.dec_f3 += 1
	for op in opts:
		if op.k == "shot":
			dbg.shot_opt += 1
	dbg.pick[pick.k] = dbg.pick.get(pick.k, 0) + 1
	match pick.k:
		"shot":
			_do_shot(o, false)
		"pass":
			_do_pass(o, pick)
		"dribble":
			_do_dribble(o, pick)
		"cross":
			_do_cross(o)
		"clear":
			_do_clear(o)

func _offside_line(sd: String) -> float:
	## Hücum eden takımın yerel koordinatında ofsayt çizgisi (sondan ikinci savunmacı)
	var d := 1.0 if sd == "h" else -1.0
	var xs := []
	for q: Pl in team[other(sd)]:
		xs.append(q.pos.x * d)
	xs.sort()
	var line: float = xs[xs.size() - 2] if xs.size() >= 2 else L
	return maxf(line, ball.x * d)

func _lane_risk(o: Pl, tp: Vector2, speed: float) -> float:
	## Pas hattına yetişebilecek en tehlikeli rakip (0..1)
	var a := o.pos
	var ab := tp - a
	var len := ab.length()
	if len < 0.1:
		return 0.0
	var worst := 0.0
	for q: Pl in team[other(o.side)]:
		var tproj := clampf((q.pos - a).dot(ab) / (len * len), 0.05, 1.0)
		var cp := a + ab * tproj
		var reach := q.pos.distance_to(cp)
		var tb := len * tproj / speed
		var tq := maxf(0.0, reach - 1.0) / (q.vmax * 0.85) + 0.25
		var r := clampf((tb - tq + 0.15) / 0.8, 0.0, 1.0)
		if q.gk:
			r *= 0.7
		worst = maxf(worst, r)
	return worst

func _interceptor(o: Pl, tp: Vector2, speed: float) -> Array:
	## En erken yetişebilecek rakip ve yakalama noktası
	var a := o.pos
	var ab := tp - a
	var len := maxf(0.1, ab.length())
	var best: Pl = null
	var bp := tp
	var bt := 1e9
	for q: Pl in team[other(o.side)]:
		var tproj := clampf((q.pos - a).dot(ab) / (len * len), 0.1, 1.0)
		var cp := a + ab * tproj
		var tq := q.pos.distance_to(cp) / q.vmax
		if tq < bt:
			bt = tq
			best = q
			bp = cp
	return [best, bp]

# ================================================================ eylemler

func _kick(o: Pl, to: Vector2, speed: float, kind: String, h := 0.0, recv := "") -> void:
	var dist := o.pos.distance_to(to)
	flight = {"from": ball, "to": to, "dur": maxf(0.2, dist / speed), "e": 0.0, "k": kind, "h": h, "recv": recv, "by": o.id, "side": o.side}
	owner = null
	last = o
	o.face = (to - o.pos).normalized() if dist > 0.1 else o.face
	anim(o, "shot" if kind in ["shot", "clear"] or speed > 24.0 else "kick", 0.42)

func _do_pass(o: Pl, op: Dictionary) -> void:
	var mt: Pl = op.to
	var tp: Vector2 = op.tp
	var long: bool = op.long
	var ic := _interceptor(o, tp, op.speed)
	var icp: Pl = ic[0]
	var att := [["passing", 1.0]] if not long else [["passing", 0.65], ["vision", 0.35]]
	var base := clampf(0.97 - o.pos.distance_to(tp) / 150.0 - float(op.risk) * 0.42 - pressure_on(o) * 0.08, 0.2, 0.96)
	var du := duel(o, att, icp, [["positioning", 0.6], ["decisions", 0.4]], base, 0.024)
	var ok: bool = rng.randf() < du.p
	o.st.p += 1
	var kind := "loft" if long else "ground"
	var h := minf(o.pos.distance_to(tp) * 0.16, 11.0) if long else 0.0
	if ok and op.get("offside", false):
		emit("offside", o.side, mt.id, o.id, true, [], [])
		_kick(o, tp, op.speed, kind, h, mt.id)
		_set_restart("free", other(o.side), mt.pos)
		return
	if ok:
		o.st.po += 1
		if value(tp, o.d) > 0.35 and value(tp, o.d) - value(o.pos, o.d) > 0.08:
			o.st.kp += 1
		emit("pass", o.side, o.id, mt.id, true, du.aa, [])
		last_pass = {"pid": o.id, "t": t}
		_kick(o, tp, op.speed, kind, h, mt.id)
		mt.run_to = tp
		mt.run_t = 3.0
		# uzun topta hız yarışı
		if long and icp != null and icp.pos.distance_to(tp) < 9.0:
			var race := duel(mt, [["pace", 1.0]], icp, [["pace", 1.0]], 0.5, 0.04)
			var won: bool = rng.randf() < race.p
			emit("sprint", mt.side, mt.id, icp.id, won, race.aa, race.ta)
			if not won:
				flight.recv = icp.id
				icp.run_to = tp
				icp.run_t = 3.0
	else:
		emit("pass", o.side, o.id, icp.id if icp else "", false, du.aa, du.ta)
		var ip: Vector2 = ic[1]
		_kick(o, ip, op.speed, kind, h * 0.6, icp.id if icp else "")
		if icp:
			icp.run_to = ip
			icp.run_t = 3.0
			icp.st.t += 1

func _do_dribble(o: Pl, op: Dictionary) -> void:
	var to: Vector2 = op.to
	if op.near and op.opp != null:
		var df: Pl = op.opp
		var du := duel(o, [["dribbling", 0.55], ["agility", 0.25], ["pace", 0.2]], df, [["tackling", 0.6], ["positioning", 0.4]], 0.5, 0.03)
		var ok: bool = rng.randf() < du.p
		o.st.d += 1
		emit("dribble", o.side, o.id, df.id, ok, du.aa, du.ta)
		if ok:
			o.st.do += 1
			df.stun = 1.1
			df.tackle_cd = 1.5
			anim(df, "slide" if rng.randf() < 0.3 else "tackle", 0.7)
			o.run_to = to
			o.run_t = 1.4
			o.decide_t = 1.2
		else:
			df.st.t += 1
			anim(df, "slide" if rng.randf() < 0.35 else "tackle", 0.7)
			if rng.randf() < 0.2 - at(df, "tackling") * 0.005:
				_foul(df, o)
				return
			o.stun = 0.8
			_gain(df, false)
	else:
		# boş alanda top sürme
		o.run_to = to
		o.run_t = 1.2
		o.decide_t = 0.6 + rng.randf() * 0.5

func _do_shot(o: Pl, header: bool, pen := false) -> void:
	var d := o.d
	var goal := Vector2(L * d, 0)
	var dist := o.pos.distance_to(goal)
	var att := [["finishing", 0.7], ["composure", 0.3]] if not header else [["heading", 0.6], ["finishing", 0.2], ["composure", 0.2]]
	var press := pressure_on(o) if not pen else 0.0
	var du := duel(o, att, null, [], (0.76 - dist / 55.0 - press * 0.1) if not pen else 0.86, 0.03)
	var on: bool = rng.randf() < du.p
	o.st.s += 1
	shots[o.side] += 1
	emit("shot", o.side, o.id, last_pass.pid if last_pass.get("t", -99.0) > t - 6.0 and last_pass.get("pid", "") != o.id else "", on, du.aa, [])
	var target := Vector2(L * d + 0.5 * d, rng.randf_range(-3.3, 3.3))
	var z := rng.randf_range(0.2, 2.1)
	if not on:
		var over := rng.randf() < 0.4
		target = Vector2(L * d + 2.0 * d, rng.randf_range(-3, 3) if over else rng.randf_range(4.3, 9.0) * (1.0 if rng.randf() < 0.5 else -1.0))
		z = 3.2 if over else rng.randf_range(0.2, 1.2)
	var power := 22.0 + at(o, "finishing") * 0.4 + (at(o, "strength") * 0.2 if not header else -8.0)
	_kick(o, target, power, "shot", 0.0)
	flight.z = z
	flight.on = on
	flight.header = header
	flight.dist = dist
	flight.pen = pen
	if header:
		anims.pop_back()
		anim(o, "header", 0.62)
	# kaleci tepkisi
	var k := keeper(other(o.side))
	if absf(target.y - k.pos.y) > 1.0 and z < 2.6:
		anim(k, "dive", 0.95, signf(target.y - k.pos.y) * k.d)

func _shot_arrive(fl: Dictionary) -> void:
	var sh: Pl = pl[fl.by]
	var k := keeper(other(sh.side))
	if not fl.on:
		if rng.randf() < 0.3:
			# savunmaya çarpıp kornere
			_set_restart("corner", sh.side, Vector2(signf(ball.x) * (L - 0.4), signf(ball.y if ball.y != 0 else 1.0) * (W - 0.4)))
			g_emit_corner(sh.side)
		else:
			_set_restart("goalkick", k.side, Vector2(L * signf(ball.x) - 5.5 * signf(ball.x), rng.randf_range(-6, 6)))
		return
	var sv := duel(k, [["reflexes", 0.65], ["handling", 0.35]], sh, [["finishing", 0.6], ["composure", 0.4]] if not fl.header else [["heading", 1.0]],
		clampf(0.41 + float(fl.dist) / 90.0, 0.36, 0.84) if not fl.get("pen", false) else 0.2, 0.025)
	var saved: bool = rng.randf() < sv.p
	if saved:
		var held: bool = rng.randf() < 0.35 + at(k, "handling") * 0.025
		k.st.sv += 1
		emit("save", k.side, k.id, sh.id, held, sv.aa, sv.ta)
		if held:
			ball = k.pos
			_gain(k, true)
			k.decide_t = 1.6
		else:
			if rng.randf() < 0.55:
				_set_restart("corner", sh.side, Vector2(signf(ball.x) * (L - 0.4), signf(ball.y if ball.y != 0 else 1.0) * (W - 0.4)))
				g_emit_corner(sh.side)
			else:
				bvel = Vector2(-signf(ball.x) * rng.randf_range(5, 9), rng.randf_range(-6, 6))
				last = k
		return
	# gol
	var sd: String = sh.side
	score[0 if sd == "h" else 1] += 1
	sh.st.g += 1
	var asst := ""
	if last_pass.get("t", -99.0) > t - 8.0 and last_pass.get("pid", "") != sh.id and pl.has(last_pass.get("pid", "")) and pl[last_pass.pid].side == sd:
		asst = last_pass.pid
		pl[asst].st["as"] += 1
	emit("goal", sd, sh.id, asst, true, [], [])
	scorer = sh.id
	celebrate_t = 7.0
	anim(sh, "knee_slide" if rng.randf() < 0.4 else "celebrate", 3.0)
	_set_restart("goal", other(sd), Vector2.ZERO)
	dead_t = 9.0

func _do_cross(o: Pl) -> void:
	var d := o.d
	var du := duel(o, [["crossing", 1.0]], null, [], 0.42, 0.03)
	var ok: bool = rng.randf() < du.p
	emit("cross", o.side, o.id, "", ok, du.aa, [])
	var spot := Vector2(L * d - rng.randf_range(5.0, 11.0) * d, rng.randf_range(-6.0, 6.0))
	if not ok:
		spot += Vector2(-d * rng.randf_range(0, 4), rng.randf_range(-8, 8))
	_kick(o, spot, 19.0, "cross", 6.5)
	flight.ok = ok
	# ceza sahasına koşular
	var n := 0
	for mt: Pl in team[o.side]:
		if mt == o or mt.gk or mt.fx < 0.3:
			continue
		mt.run_to = spot + Vector2(-d * rng.randf_range(0, 3), rng.randf_range(-3, 3))
		mt.run_t = 2.5
		n += 1
		if n >= 3:
			break

func _aerial(fl: Dictionary) -> void:
	var by: Pl = pl[fl.by]
	var sd := by.side
	var att: Pl = null
	var ba := -1.0
	for q: Pl in team[sd]:
		if q.gk:
			continue
		var dd := q.pos.distance_to(ball)
		if dd < 6.5:
			var v := at(q, "heading") + at(q, "strength") * 0.3 - dd * 1.2
			if v > ba:
				ba = v
				att = q
	var df: Pl = null
	var bd := -1.0
	for q: Pl in team[other(sd)]:
		var dd := q.pos.distance_to(ball)
		if dd < 6.5:
			var v := at(q, "heading") + at(q, "strength") * 0.3 - dd * 1.2 + (4.0 if q.gk and dd < 3.0 else 0.0)
			if v > bd:
				bd = v
				df = q
	if att == null or not fl.get("ok", true):
		if df != null:
			_clear_header(df)
		else:
			bvel = Vector2.ZERO
		return
	if df == null:
		ball = att.pos
		_do_shot(att, true)
		return
	var hd := duel(att, [["heading", 0.7], ["strength", 0.3]], df, [["heading", 0.6], ["strength", 0.4]], 0.45, 0.035)
	var won: bool = rng.randf() < hd.p
	att.st.air += 1
	df.st.air += 1
	emit("header", sd, att.id, df.id, won, hd.aa, hd.ta)
	if won:
		att.st.air_ok += 1
		anim(df, "header", 0.62)
		ball = att.pos
		_do_shot(att, true)
	else:
		df.st.air_ok += 1
		_clear_header(df)

func _clear_header(df: Pl) -> void:
	anim(df, "header", 0.62)
	last = df
	var to := df.pos + Vector2(df.d * rng.randf_range(15, 28), rng.randf_range(-15, 15))
	to = Vector2(clampf(to.x, -L + 1, L - 1), clampf(to.y, -W + 1, W - 1))
	flight = {"from": ball, "to": to, "dur": df.pos.distance_to(to) / 16.0, "e": 0.0, "k": "clear", "h": 5.0, "recv": "", "by": df.id, "side": df.side}

func _do_clear(o: Pl) -> void:
	var to := o.pos + Vector2(o.d * rng.randf_range(25, 40), rng.randf_range(-20, 20))
	to = Vector2(clampf(to.x, -L + 1, L - 1), clampf(to.y, -W + 1, W - 1))
	_kick(o, to, 20.0, "clear", 8.0)

func _defend_owner(dt: float) -> void:
	## Topa yakın savunmacı top kapmayı dener
	var o := owner
	for q: Pl in team[other(o.side)]:
		if q.stun > 0.0 or q.tackle_cd > 0.0:
			continue
		if q.pos.distance_to(o.pos) < 1.2:
			q.tackle_cd = 1.2
			var du := duel(q, [["tackling", 0.6], ["positioning", 0.25], ["work_rate", 0.15]], o, [["dribbling", 0.5], ["composure", 0.3], ["strength", 0.2]], 0.24, 0.03)
			var won: bool = rng.randf() < du.p
			if won:
				emit("press", q.side, q.id, o.id, true, du.aa, du.ta)
				q.st.t += 1
				anim(q, "tackle", 0.5)
				if rng.randf() < 0.13:
					_foul(q, o)
					return
				o.stun = 0.7
				_gain(q, false)
				return
			elif rng.randf() < 0.15:
				emit("press", q.side, q.id, o.id, false, du.aa, du.ta)

# ================================================================ hakem: faul, kart, penaltı, ofsayt

func _foul(df: Pl, vic: Pl) -> void:
	var lx := vic.pos.x * vic.d
	var in_box := lx > L - 16.5 and absf(vic.pos.y) < 20.16
	# ceza sahasında hakem çoğu teması "devam" der
	if in_box and rng.randf() < 0.45:
		return
	emit("foul", df.side, df.id, vic.id, true, [], [])
	# kart: tehlikeli bölge ve son adam faulü daha ağır
	var pc := 0.14 + (0.12 if lx > 20.0 else 0.0) + (0.1 if in_box else 0.0) - at(df, "composure") * 0.004
	var pr := 0.006 + (0.03 if in_box and _last_man(df) else 0.0)
	if not df.gk and rng.randf() < pr:
		_send_off(df, false)
	elif rng.randf() < pc:
		df.yel += 1
		df.st["yc"] = int(df.st.get("yc", 0)) + 1
		if df.yel >= 2 and not df.gk:
			emit("yellow", df.side, df.id, vic.id, true, [], [])
			_send_off(df, true)
		else:
			emit("yellow", df.side, df.id, vic.id, true, [], [])
	if in_box:
		emit("penalty", vic.side, vic.id, df.id, true, [], [])
		_set_restart("penalty", vic.side, Vector2((L - 11.0) * vic.d, 0))
	else:
		_set_restart("free", vic.side, vic.pos)

func _last_man(df: Pl) -> bool:
	var behind := 0
	for q: Pl in team[df.side]:
		if q != df and not q.gk and q.pos.x * df.d < df.pos.x * df.d:
			behind += 1
	return behind == 0

func _send_off(q: Pl, second: bool) -> void:
	emit("red", q.side, q.id, "2y" if second else "", true, [], [])
	q.off = true
	q.st["rc"] = 1
	team[q.side].erase(q)
	q.pos = Vector2(0, (W + 3.0) * (1.0 if q.side == "h" else 1.0))
	q.vel = Vector2.ZERO
	if owner == q:
		owner = null

# ================================================================ duran toplar

func _set_restart(k: String, sd: String, at_p: Vector2) -> void:
	phase = "dead"
	owner = null
	flight = {}
	bvel = Vector2.ZERO
	poss = sd
	ball = at_p
	var tk: Pl = null
	match k:
		"goalkick":
			tk = keeper(sd)
		"corner":
			tk = _best(team[sd], "crossing")
		"goal", "kick":
			tk = _forward(sd)
		_:
			var bd := 1e9
			for q: Pl in team[sd]:
				if q.gk:
					continue
				var dd := q.pos.distance_to(at_p)
				if dd < bd:
					bd = dd
					tk = q
	restart = {"k": k, "side": sd, "pos": at_p, "taker": tk.id}
	if k == "penalty":
		tk = _best(team[sd], "finishing")
		restart.taker = tk.id
	dead_t = {"goalkick": 2.5, "corner": 3.2, "throw": 1.6, "free": 2.6, "goal": 9.0, "kick": 2.0, "penalty": 5.0}.get(k, 2.0)

func _best(arr: Array, attr: String) -> Pl:
	var best: Pl = null
	var bv := -1.0
	for q: Pl in arr:
		if q.gk:
			continue
		if q.a[attr] > bv:
			bv = q.a[attr]
			best = q
	return best

func _forward(sd: String) -> Pl:
	for q: Pl in team[sd]:
		if q.role in ["ST", "AM"]:
			return q
	return team[sd][team[sd].size() - 1]

func _kickoff(sd: String) -> void:
	for q: Pl in pl.values():
		var lp := Vector2(minf(q.base.x * 0.72, -1.2), q.base.y * 0.9)
		if q.gk:
			lp = Vector2(-50.5, 0)
		q.pos = Vector2(lp.x * q.d, lp.y * q.d)
		q.vel = Vector2.ZERO
		q.face = Vector2(q.d, 0)
	_set_restart("kick", sd, Vector2.ZERO)
	var tk: Pl = pl[restart.taker]
	tk.pos = Vector2(-0.6 * tk.d, 0)
	emit("kickoff", sd, tk.id, "", true, [], [])

func _do_restart() -> void:
	var k: String = restart.k
	var tk: Pl = pl[restart.taker]
	if k == "goal":
		_kickoff(restart.side)
		return
	phase = "play"
	tk.pos = restart.pos - Vector2(tk.d * 0.6, 0) if k != "throw" else restart.pos
	ball = restart.pos
	_gain(tk, true)
	if k == "throw":
		anim(tk, "throw", 1.0)
	match k:
		"penalty":
			tk.pos = restart.pos - Vector2(tk.d * 0.8, 0)
			var kp := keeper(other(tk.side))
			kp.pos = Vector2(L * tk.d - 0.3 * tk.d, 0)
			_do_shot(tk, false, true)
		"corner":
			_do_cross(tk)
		"kick", "throw":
			tk.decide_t = 0.05
		"goalkick":
			tk.decide_t = 0.3
		"free":
			tk.decide_t = 0.4

# ================================================================ hareket (takım yapay zekâsı)

func _move_all(dt: float) -> void:
	var dead := phase == "dead"
	var focus := ball
	if not flight.is_empty():
		focus = (flight.from as Vector2).lerp(flight.to, 0.6)
	var line := {"h": _deep("h"), "a": _deep("a")}
	var defside := other(poss)
	var pressers := _nearest_two(defside, focus)
	for q: Pl in pl.values():
		if q.off:
			q.vel = Vector2.ZERO
			continue
		var tw := _target_for(q, focus, line, pressers, dead)
		var cap: float = tw[1]
		_steer(q, tw[0], cap, tw[2], dt)
	_separate(dt)

func _deep(sd: String) -> float:
	var d := 1.0 if sd == "h" else -1.0
	var mn := 99.0
	for q: Pl in team[sd]:
		if not q.gk:
			mn = minf(mn, q.pos.x * d)
	return mn

func _nearest_two(sd: String, p: Vector2) -> Array:
	var a: Pl = null
	var b: Pl = null
	var da := 1e9
	var db := 1e9
	for q: Pl in team[sd]:
		if q.gk:
			continue
		var dd := q.pos.distance_squared_to(p)
		if dd < da:
			b = a
			db = da
			a = q
			da = dd
		elif dd < db:
			b = q
			db = dd
	return [a, b]

func _shape(q: Pl, lb: Vector2, attacking: bool) -> Vector2:
	var base := q.base
	var line := 0.0
	var length := 0.0
	var wscale := 1.0
	var shift := 0.0
	if attacking:
		line = clampf(lb.x * 0.62 - 13.0, -37.0, 12.0)
		length = 40.0
		wscale = 1.12
		shift = 0.18
	else:
		line = clampf(lb.x * 0.55 - 17.0, -39.0, -6.0)
		length = 27.0
		wscale = 0.72
		shift = 0.42
	var x := line + q.fx * length
	var y := base.y * wscale + (lb.y - base.y * wscale) * shift
	if attacking and q.role in ["LB", "RB"] and signf(base.y) == signf(lb.y) and lb.x > 0.0:
		x += 16.0
		y = base.y * 1.25
	if attacking and q.role in ["LW", "RW"]:
		y = base.y * 1.32
	var sway := sin(t * 0.35 + q.seed) * 1.2
	return Vector2(clampf(x + sway, -50.0, 50.0), clampf(y + cos(t * 0.29 + q.seed), -32.5, 32.5))

func _target_for(q: Pl, focus: Vector2, line: Dictionary, pressers: Array, dead: bool) -> Array:
	## [hedef (dünya), hız sınırı, acil mi]
	var d := q.d
	var attacking := q.side == poss
	var lb := Vector2(focus.x * d, focus.y * d)
	var tgt := _shape(q, lb, attacking)
	var cap := q.vmax * 0.62
	var urgent := false
	# duran toplar
	if dead:
		var k: String = restart.get("k", "")
		if restart.get("taker", "") == q.id:
			return [restart.pos - Vector2(q.d * 0.6, 0), q.vmax * 0.8, true]
		if k == "corner" and not q.gk:
			var cd := 1.0 if restart.side == "h" else -1.0
			var hsh := fmod(q.seed, 1.0)
			if q.side == restart.side and q.fx > 0.25:
				return [Vector2((43.0 + hsh * 7.0) * cd, (hsh - 0.5) * 16.0), q.vmax * 0.8, false]
			elif q.side != restart.side:
				return [Vector2((46.5 + hsh * 4.0) * cd, (hsh - 0.5) * 14.0), q.vmax * 0.8, false]
		if k == "goal":
			if q.id == scorer:
				return [Vector2(46.0 * q.d, 30.0 * signf(q.pos.y + 0.01)), 7.5, false]
			if pl.has(scorer) and pl[scorer].side == q.side and not q.gk:
				return [pl[scorer].pos + Vector2(cos(q.seed), sin(q.seed)) * 2.0, 6.5, false]
			return [Vector2(tgt.x * d, tgt.y * d), 1.6, false]
		cap = minf(cap, 3.5)
	if q.gk:
		var gx := -L + clampf(1.4 + (lb.x + L) * 0.045, 1.2, 5.5)
		if attacking:
			gx = -L + clampf(4.0 + (lb.x + L) * 0.12, 4.0, 16.0)
		var gp := Vector2(gx * d, clampf(lb.y * 0.14, -3.2, 3.2) * d)
		if not flight.is_empty() and flight.k == "shot" and flight.side != q.side:
			gp = Vector2(gp.x, clampf(flight.to.y, -3.4, 3.4))
			return [gp, 7.0, true]
		return [gp, 5.0, false]
	if owner == q:
		if q.run_t > 0.0 and q.run_to != Vector2.INF:
			q.run_t -= DT
			return [q.run_to, q.vmax * 0.85, true]
		return [q.pos + q.face * 1.5, 3.0, false]
	# pas alıcısı / topa koşan
	if q.run_t > 0.0 and q.run_to != Vector2.INF:
		q.run_t -= DT
		var need := q.pos.distance_to(q.run_to) / maxf(0.2, float(flight.get("dur", 1.0)) - float(flight.get("e", 0.0)))
		return [q.run_to, clampf(need * 1.15, 2.5, q.vmax), true]
	# serbest topa en yakınlar koşar
	if owner == null and flight.is_empty():
		var close := _nearest_two(q.side, ball)
		if q == close[0]:
			return [ball, q.vmax, true]
	# savunma: pres, kapatma, markaj
	if not attacking:
		if q == pressers[0]:
			var own_goal := Vector2(-L * d, 0)
			return [focus + (own_goal - focus).normalized() * 1.0, q.vmax * (0.85 + at(q, "work_rate") * 0.008), true]
		if q == pressers[1]:
			var own_goal2 := Vector2(-L * d, 0)
			return [focus + (own_goal2 - focus).normalized() * 7.0, q.vmax * 0.8, false]
		var mk := _mark(q, tgt)
		if mk != Vector2.INF:
			tgt = tgt.lerp(mk, 0.35 + at(q, "positioning") * 0.02)
	else:
		# hücum: ofsayt çizgisi, boş alan arama, derin koşular
		var ol: float = -float(line[other(q.side)])
		var lim := maxf(ol, lb.x)
		if q.fx > 0.8 and owner != null and owner.side == q.side and owner != q and lb.x > -10.0:
			# forvet: çizgide bekle, uygun anda arkaya koş
			if q.think_t <= 0.0:
				q.think_t = 1.5 + rng.randf()
				var dart := rng.randf() < 0.25 + (at(q, "pace") + at(q, "decisions")) * 0.012
				q.spot = Vector2(lim + (8.0 if dart else -1.0), tgt.y) if dart else Vector2(INF, 0)
			q.think_t -= DT
			if q.spot.x != INF:
				tgt = q.spot
				cap = q.vmax
				urgent = true
		elif owner != null and owner.side == q.side and owner != q:
			# destek: boş alan ara
			if q.think_t <= 0.0:
				q.think_t = 1.0 + rng.randf() * 0.8
				q.spot = _open_spot(q, tgt)
			q.think_t -= DT
			if q.spot != Vector2.INF:
				tgt = q.spot
		if tgt.x > lim - 0.4 and not urgent:
			tgt.x = lim - 0.4
	return [Vector2(tgt.x * d, tgt.y * d), cap, urgent]

func _open_spot(q: Pl, local_tgt: Vector2) -> Vector2:
	## Rakiplerden uzak, ileri bir destek noktası (yerel koordinat)
	var best := local_tgt
	var bv := -1e9
	for i in 6:
		var ang := q.seed + i * TAU / 6.0
		var cand := local_tgt + Vector2(cos(ang), sin(ang)) * 6.0
		cand = Vector2(clampf(cand.x, -50, 50), clampf(cand.y, -32, 32))
		var wp := Vector2(cand.x * q.d, cand.y * q.d)
		var nd := 99.0
		for o: Pl in team[other(q.side)]:
			nd = minf(nd, o.pos.distance_to(wp))
		var v := minf(nd, 9.0) + cand.x * 0.08 * (at(q, "decisions") / 10.0)
		if v > bv:
			bv = v
			best = cand
	return best

func _mark(q: Pl, local_tgt: Vector2) -> Vector2:
	var d := q.d
	var sw := Vector2(local_tgt.x * d, local_tgt.y * d)
	var best := Vector2.INF
	var bd := 11.0
	for o: Pl in team[other(q.side)]:
		if o.gk:
			continue
		var dd := o.pos.distance_to(sw)
		if dd < bd:
			bd = dd
			var gs := o.pos + (Vector2(-L * d, 0) - o.pos).normalized() * 1.6
			best = Vector2(gs.x * d, gs.y * d)
	return best

func _steer(q: Pl, tw: Vector2, cap: float, urgent: bool, dt: float) -> void:
	if q.stun > 0.0:
		q.vel *= maxf(0.0, 1.0 - dt * 3.0)
		q.pos += q.vel * dt
		return
	var to := Vector2(clampf(tw.x, -56, 56), clampf(tw.y, -37, 37)) - q.pos
	var dist := to.length()
	var want := minf(cap, dist * (2.2 if urgent else 1.1))
	if not urgent and dist < 1.2:
		want = 0.0
	if owner == q:
		want = minf(want, q.vmax * (0.78 + at(q, "dribbling") * 0.006))
	var dv := (to.normalized() * want if dist > 0.01 else Vector2.ZERO) - q.vel
	var accv := q.acc * (1.35 if dv.dot(q.vel) < 0 else 1.0)
	if dv.length() > accv * dt:
		dv = dv.normalized() * accv * dt
	q.vel += dv
	q.pos += q.vel * dt
	if q.vel.length() > 1.0:
		q.face = q.face.lerp(q.vel.normalized(), minf(1.0, dt * 8.0)).normalized()
	elif owner != q:
		var tb := (ball - q.pos)
		if tb.length() > 0.5:
			q.face = q.face.lerp(tb.normalized(), minf(1.0, dt * 5.0)).normalized()

func _separate(dt: float) -> void:
	var arr := pl.values()
	var n := arr.size()
	for i in n:
		var a: Pl = arr[i]
		for j in range(i + 1, n):
			var b: Pl = arr[j]
			var dx := b.pos.x - a.pos.x
			var dz := b.pos.y - a.pos.y
			var d2 := dx * dx + dz * dz
			var minr := 0.9 if a.side != b.side else 2.4
			if d2 < minr * minr and d2 > 0.0001:
				var dd := sqrt(d2)
				var push := (minr - dd) * 0.5 * minf(1.0, dt * 6.0)
				var nv := Vector2(dx, dz) / dd
				a.pos -= nv * push
				b.pos += nv * push

# ================================================================ hızlı koşu ve sonuç

func run_to_end(max_steps := 200000, dt := 0.2) -> void:
	var n := 0
	while not finished and n < max_steps:
		step(dt)
		anims.clear()
		n += 1

func ratings(live := false) -> Dictionary:
	var out := {}
	var gd: int = score[0] - score[1]
	for q: Pl in pl.values():
		var s: Dictionary = q.st
		var r := 6.1
		r += s.po * 0.025 - (s.p - s.po) * 0.06 + s.kp * 0.12
		r += s.do * 0.12 - (s.d - s.do) * 0.05 + s.t * 0.09
		r += s.so * 0.25 + s.g * 0.9 + s["as"] * 0.5 + s.sv * 0.3 - s.err * 0.15
		r += s.air_ok * 0.05
		var team_gd := gd if q.side == "h" else -gd
		r += clampf(float(team_gd), -3.0, 3.0) * 0.15
		if q.gk:
			var conc: int = score[1] if q.side == "h" else score[0]
			r += 0.4 - conc * 0.3
		r -= float(s.get("yc", 0)) * 0.3 + float(s.get("rc", 0)) * 1.5
		out[q.id] = snappedf(clampf(r + (0.0 if live else rng.randfn(0.0, 0.2)), 3.5, 9.8), 0.1)
	return out

func goal_events() -> Array:
	var out := []
	for e in events:
		if e.ty == "goal":
			out.append({"t": "g", "pid": e.pid, "as": e.tgt, "side": e.side, "min": mini(90, int(e.t / 60.0) + 1)})
	return out
