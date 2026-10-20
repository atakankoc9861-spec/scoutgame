extends Node
## v0.23 Dalga 3a — Poisson yolunu hızlı motora (sim/quick_engine.gd) kalibre eder -> data/sim_calib.json
##
## Çalıştırma (geliştirici aracı, APK'ya girmez):
##   XDG_DATA_HOME=<boş klasör> <godot> --headless --path . res://tools/dev/calibrate.tscn
## Ortam: CAL_SEEDS ("2301 4711 9001 1234 5678"), CAL_N (seed başına maç, 2000),
##        CAL_OUT (çıktı yolu, varsayılan res://data/sim_calib.json), CAL_DRY=1 (yazma).
##
## Örnek: her seed için yeni oyun; ayrıntılı (lazy olmayan) kulüpler arasındaki fikstür eşleşmeleri,
## ilk 11 Game.best_xi(noise) ile, maç quick_engine ile. Poisson yolunun bugünkü biçimi korunur
## (λ = taban · exp(±(d + ev) / bölen), d = team_str farkı), sabitler motor sonuçlarından çıkarılır:
##   - taban / ev sahibi bonusu / bölen: iki taraflı Poisson log-olabilirlik (Newton), 8 d kovasında kontrol
##     ("poisson.mle"); sonra skor durumu (lead_k / trail_k, 6 dilim) + ev bonusu ızgarası, taban gol/maç'a
##     ölçeklenir. Bağımsız Poisson motorun beraberlik (%29) ve 4+ fark (%1) oranlarını tutturamıyor.
##   - golcü mevki ağırlıkları (Game._pick_scorer: w = grup · (bitiricilik/10)^2): motorun grup paylarına
##   - asistsiz gol oranı, gol dakikası histogramı (15'erlik 6 kova, son kova 76-89 + 90)
##   - reyting: gol farkı kovası (-3..3) başına ortalama + artık sd, ovr farkı / gol / asist / mevki etkisi
## Sonunda aynı maçlar Poisson modeliyle (kendi RNG'si) yeniden oynatılır; motor ↔ model karşılaştırması
## json'un "check" alanına ve çıktıya yazılır.

const QE = preload("res://sim/quick_engine.gd")
const GROUPS := ["GK", "DEF", "MID", "ATT"]
const D_EDGES := [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0]   # 8 kova
const MIN_EDGES := [15, 30, 45, 60, 75, 89, 90]            # 7 kova: 1-15 … 76-89, 90(+)
const NP := 13   # reyting regresyonu: 7 gol farkı kesişimi + ovr farkı + gol + asist + GK/DEF/MID

# maç düzeyi
var m_d := PackedFloat32Array()
var m_gh := PackedInt32Array()
var m_ga := PackedInt32Array()
var m_xi: Array = []          # [[ [grp, fin, ovr, cons, bm] x11 ], [...]] ev, dep
var m_big: Array = []         # [big_h, big_a]
# gol düzeyi
var g_grp := [0, 0, 0, 0]
var g_noas := 0
var g_n := 0
var g_min := [0, 0, 0, 0, 0, 0, 0]
var g_side_xi: Array = []     # her gol için atan tarafın [grp, fin] listesi
# reyting satırları
var r_y := PackedFloat32Array()
var r_x: Array = []           # PackedFloat32Array(NP)
var r_b := PackedInt32Array() # gol farkı kovası 0..6
var r_cons := PackedFloat32Array()
var r_grp := PackedInt32Array()
var ms_list := PackedFloat32Array()

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ready() -> void:
	var seeds := []
	for x in _env("CAL_SEEDS", "2301 4711 9001 1234 5678").split(" ", false):
		seeds.append(int(x))
	var n: int = int(_env("CAL_N", "2000"))
	var t0 := Time.get_ticks_msec()
	for sd: int in seeds:
		_collect(sd, n)
		print("seed %d: %d maç toplandı (%d ms)" % [sd, m_d.size(), Time.get_ticks_msec() - t0])
	if _env("CAL_DUMP", "") != "":
		var fd := FileAccess.open(_env("CAL_DUMP", ""), FileAccess.WRITE)
		for i in m_d.size():
			fd.store_line("%f,%d,%d" % [m_d[i], m_gh[i], m_ga[i]])
		fd.close()
	var out := _fit()
	out.seeds = seeds
	out.n = m_d.size()
	out.date = Time.get_date_string_from_system()
	_fit_state(out)
	out.check = _validate(out)
	_print(out)
	if _env("CAL_DRY", "0") != "1":
		var path := _env("CAL_OUT", ProjectSettings.globalize_path("res://data/sim_calib.json"))
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  ", false) + "\n")
		f.close()
		print("yazıldı: ", path)
	print("CALIBRATE_DONE %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit(0)

# ================================================================ örnek toplama

func _pinfo(pid: String) -> Array:
	var p: Dictionary = Game.player(pid)
	return [GROUPS.find(Data.POS_GROUP[p.pos]), float(p.attrs.finishing), float(p.ovr), float(p.hid.consistency), float(p.hid.big_match)]

func _collect(sd: int, n: int) -> void:
	Game.rng.seed = sd
	seed(sd)
	Game.new_game("T", "tr")
	var pairs := []
	var leagues: Array = Game.s.fixtures.keys()
	leagues.sort()
	for lg: String in leagues:
		for rnd: Array in Game.s.fixtures[lg]:
			for fm: Dictionary in rnd:
				if not Game.is_lazy(str(fm.h)) and not Game.is_lazy(str(fm.a)):
					pairs.append([str(fm.h), str(fm.a)])
	var lr := RandomNumberGenerator.new()
	lr.seed = sd * 31 + 7
	for i in range(pairs.size() - 1, 0, -1):
		var j := lr.randi_range(0, i)
		var t = pairs[i]
		pairs[i] = pairs[j]
		pairs[j] = t
	for i in n:
		var pr: Array = pairs[i % pairs.size()]
		var xh: Array = Game.best_xi(pr[0], true)
		var xa: Array = Game.best_xi(pr[1], true)
		var big_h: bool = Game.club(pr[1]).prestige >= 80
		var big_a: bool = Game.club(pr[0]).prestige >= 80
		var d: float = Game.team_str(xh, big_h) - Game.team_str(xa, big_a)
		var m := {"h": pr[0], "a": pr[1], "day": "sat", "gh": -1, "ga": -1, "ev": [], "xi_h": xh, "xi_a": xa}
		var tq := Time.get_ticks_usec()
		var r: Dictionary = QE.simulate(Game, m, false, sd * 100003 + i)
		ms_list.append((Time.get_ticks_usec() - tq) / 1000.0)
		m_d.append(d)
		m_gh.append(int(r.gh))
		m_ga.append(int(r.ga))
		var info := [[], []]
		for pid in xh:
			info[0].append(_pinfo(pid))
		for pid in xa:
			info[1].append(_pinfo(pid))
		m_xi.append(info)
		m_big.append([big_h, big_a])
		for e: Dictionary in r.ev:
			if str(e.t) != "g":
				continue
			var p: Dictionary = Game.player(str(e.pid))
			g_grp[GROUPS.find(Data.POS_GROUP[p.pos])] += 1
			g_n += 1
			if str(e["as"]) == "":
				g_noas += 1
			var mn: int = int(e["min"])
			for k in MIN_EDGES.size():
				if mn <= MIN_EDGES[k]:
					g_min[k] += 1
					break
			g_side_xi.append(info[0] if str(e.side) == "h" else info[1])
		# reyting satırları
		var goals := {}
		var assists := {}
		for e: Dictionary in r.ev:
			goals[e.pid] = int(goals.get(e.pid, 0)) + 1
			if str(e["as"]) != "":
				assists[e["as"]] = int(assists.get(e["as"], 0)) + 1
		for si in 2:
			var xi: Array = xh if si == 0 else xa
			var gd: int = (int(r.gh) - int(r.ga)) * (1 if si == 0 else -1)
			var b: int = clampi(gd, -3, 3) + 3
			var avg := 0.0
			for pid in xi:
				avg += float(Game.player(pid).ovr)
			avg /= maxf(1.0, float(xi.size()))
			for pid in xi:
				if not r.rt.has(pid):
					continue
				var p: Dictionary = Game.player(pid)
				var x := PackedFloat32Array()
				x.resize(NP)
				x.fill(0.0)
				x[b] = 1.0
				x[7] = float(p.ovr) - avg
				x[8] = float(goals.get(pid, 0))
				x[9] = float(assists.get(pid, 0))
				var gi: int = GROUPS.find(Data.POS_GROUP[p.pos])
				if gi < 3:
					x[10 + gi] = 1.0
				r_x.append(x)
				r_y.append(float(r.rt[pid]))
				r_b.append(b)
				r_cons.append(float(p.hid.consistency))
				r_grp.append(gi)

# ================================================================ uydurma

func _bucket(d: float) -> int:
	for k in D_EDGES.size():
		if d <= D_EDGES[k]:
			return k
	return D_EDGES.size()

func _fit() -> Dictionary:
	var out := {"version": 1, "source": "tools/dev/calibrate.gd (quick_engine)"}
	# --- iki taraflı Poisson: log λh = ah + k d, log λa = aa − k d
	var ah := log(1.4)
	var aa := log(1.15)
	var k := 0.09
	for _it in 40:
		var g := [0.0, 0.0, 0.0]
		var H := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
		for i in m_d.size():
			var d: float = m_d[i]
			var lh := exp(ah + k * d)
			var la := exp(aa - k * d)
			g[0] += m_gh[i] - lh
			g[1] += m_ga[i] - la
			g[2] += (m_gh[i] - lh) * d - (m_ga[i] - la) * d
			H[0][0] -= lh
			H[1][1] -= la
			H[0][2] -= lh * d
			H[1][2] += la * d
			H[2][2] -= (lh + la) * d * d
		H[2][0] = H[0][2]
		H[2][1] = H[1][2]
		var st: Array = _solve(H, g)
		ah -= st[0]
		aa -= st[1]
		k -= st[2]
		if absf(st[0]) + absf(st[1]) + absf(st[2]) < 1e-9:
			break
	var base := exp((ah + aa) / 2.0)
	var home := (ah - aa) / (2.0 * k)
	out.poisson = {"base_h": snappedf(base, 0.0001), "base_a": snappedf(base, 0.0001),
		"home": snappedf(home, 0.001), "div": snappedf(1.0 / k, 0.001)}
	# kova kontrolü
	var bk := []
	for b in D_EDGES.size() + 1:
		bk.append({"n": 0, "gh": 0.0, "ga": 0.0, "lh": 0.0, "la": 0.0})
	for i in m_d.size():
		var row: Dictionary = bk[_bucket(m_d[i])]
		row.n += 1
		row.gh += m_gh[i]
		row.ga += m_ga[i]
		row.lh += exp(ah + k * m_d[i])
		row.la += exp(aa - k * m_d[i])
	var buckets := []
	for b in bk.size():
		var row: Dictionary = bk[b]
		var nn := maxf(1.0, float(row.n))
		var lo: String = "-inf" if b == 0 else str(D_EDGES[b - 1])
		var hi: String = "+inf" if b == D_EDGES.size() else str(D_EDGES[b])
		buckets.append({"d": "(%s,%s]" % [lo, hi], "n": row.n, "motor_gh": snappedf(row.gh / nn, 0.001), "motor_ga": snappedf(row.ga / nn, 0.001),
			"model_gh": snappedf(row.lh / nn, 0.001), "model_ga": snappedf(row.la / nn, 0.001)})
	out.buckets = buckets
	# --- golcü mevki ağırlıkları
	var tgt := []
	for gi in 4:
		tgt.append(float(g_grp[gi]) / maxf(1.0, float(g_n)))
	var w := [0.0, 0.25, 0.9, 2.6]
	if g_grp[0] > 0:
		w[0] = 0.02
	for _it in 60:
		var pred := _scorer_shares(w)
		for gi in 4:
			if pred[gi] > 0.0 and tgt[gi] > 0.0:
				w[gi] *= tgt[gi] / pred[gi]
			elif tgt[gi] == 0.0:
				w[gi] = 0.0
		var sc: float = 2.6 / maxf(1e-6, w[3])
		for gi in 4:
			w[gi] *= sc
	out.scorer_w = {}
	for gi in 4:
		out.scorer_w[GROUPS[gi]] = snappedf(w[gi], 0.0001)
	out.scorer_share_motor = {}
	for gi in 4:
		out.scorer_share_motor[GROUPS[gi]] = snappedf(100.0 * tgt[gi], 0.01)
	out.no_assist = snappedf(float(g_noas) / maxf(1.0, float(g_n)), 0.0001)
	var mins := []
	for kk in g_min.size():
		mins.append(snappedf(float(g_min[kk]) / maxf(1.0, float(g_n)), 0.0001))
	out.minutes = mins
	out.minute_edges = MIN_EDGES
	# --- reyting regresyonu (en küçük kareler, normal denklemler)
	var XtX := []
	for i in NP:
		var rr := []
		rr.resize(NP)
		rr.fill(0.0)
		XtX.append(rr)
	var Xty := []
	Xty.resize(NP)
	Xty.fill(0.0)
	for j in r_y.size():
		var x: PackedFloat32Array = r_x[j]
		for a in NP:
			if x[a] == 0.0:
				continue
			Xty[a] += x[a] * r_y[j]
			for b in NP:
				XtX[a][b] += x[a] * x[b]
	var beta: Array = _solve(XtX, Xty)
	var ss := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var cn := [0, 0, 0, 0, 0, 0, 0]
	var csq := 0.0
	for j in r_y.size():
		var x: PackedFloat32Array = r_x[j]
		var yh := 0.0
		for a in NP:
			yh += x[a] * beta[a]
		var e := r_y[j] - yh
		ss[r_b[j]] += e * e
		cn[r_b[j]] += 1
		var cm := 0.95 - 0.03 * r_cons[j]
		csq += cm * cm
	var mu := []
	var sdv := []
	for b in 7:
		mu.append(snappedf(beta[b], 0.0001))
		sdv.append(snappedf(sqrt(ss[b] / maxf(1.0, float(cn[b]))), 0.0001))
	out.rating = {"mu": mu, "sd": sdv, "k_ovr": snappedf(beta[7], 0.0001), "goal": snappedf(beta[8], 0.0001),
		"assist": snappedf(beta[9], 0.0001), "grp": {"GK": snappedf(beta[10], 0.0001), "DEF": snappedf(beta[11], 0.0001), "MID": snappedf(beta[12], 0.0001), "ATT": 0.0},
		"cons_norm": snappedf(sqrt(csq / maxf(1.0, float(r_y.size()))), 0.0001), "lo": 3.5, "hi": 9.8}
	return out

func _scorer_shares(w: Array) -> Array:
	var sh := [0.0, 0.0, 0.0, 0.0]
	for xi: Array in g_side_xi:
		var tot := 0.0
		var part := [0.0, 0.0, 0.0, 0.0]
		for pi: Array in xi:
			var v: float = w[pi[0]] * pow(float(pi[1]) / 10.0, 2.0)
			part[pi[0]] += v
			tot += v
		if tot <= 0.0:
			continue
		for gi in 4:
			sh[gi] += part[gi] / tot
	for gi in 4:
		sh[gi] /= maxf(1.0, float(g_side_xi.size()))
	return sh

## Gauss eleme (kısmi pivot). A: Array[Array], b: Array -> x
func _solve(A0: Array, b0: Array) -> Array:
	var nn := b0.size()
	var A := []
	for i in nn:
		A.append((A0[i] as Array).duplicate())
	var b := b0.duplicate()
	for col in nn:
		var piv := col
		for r in range(col + 1, nn):
			if absf(A[r][col]) > absf(A[piv][col]):
				piv = r
		var t = A[col]
		A[col] = A[piv]
		A[piv] = t
		var tb = b[col]
		b[col] = b[piv]
		b[piv] = tb
		var dv: float = A[col][col]
		if absf(dv) < 1e-12:
			continue
		for r in range(col + 1, nn):
			var f: float = A[r][col] / dv
			if f == 0.0:
				continue
			for c in range(col, nn):
				A[r][c] -= f * A[col][c]
			b[r] -= f * b[col]
	var x := []
	x.resize(nn)
	x.fill(0.0)
	for i in range(nn - 1, -1, -1):
		var sacc: float = b[i]
		for c in range(i + 1, nn):
			sacc -= A[i][c] * x[c]
		x[i] = sacc / A[i][i] if absf(A[i][i]) > 1e-12 else 0.0
	return x

# ================================================================ doğrulama: aynı maçlar Poisson modeliyle

## Skor modeli (Game._sim_goals ile aynı): maç 15'erlik 6 dilim; her dilimde taraf başına
## Poisson(λ · dilim payı · durum çarpanı). Durum: önde olan yavaşlar exp(-lead_k·fark),
## geride olan bastırır exp(trail_k·fark). Motorun skor durumu davranışını (beraberlik çok,
## 4+ fark az) bağımsız Poisson'dan daha iyi taşır. λ = taban · scale · exp(±(d + home) / div).
static func score(r: RandomNumberGenerator, d: float, P: Dictionary, sw: Array) -> Array:
	var dd: float = d + float(P.home)
	var lh: float = float(P.base_h) * exp(dd / float(P.div))
	var la: float = float(P.base_a) * exp(-dd / float(P.div))
	var gh := 0
	var ga := 0
	for si in sw.size():
		var lead := gh - ga
		var fh := 1.0
		var fa := 1.0
		if lead > 0:
			fh = exp(-float(P.lead_k) * lead)
			fa = exp(float(P.trail_k) * lead)
		elif lead < 0:
			fh = exp(float(P.trail_k) * -lead)
			fa = exp(-float(P.lead_k) * -lead)
		gh += _pois_s(r, lh * float(sw[si]) * fh)
		ga += _pois_s(r, la * float(sw[si]) * fa)
	return [gh, ga]

static func _pois_s(r: RandomNumberGenerator, lam: float) -> int:
	if lam <= 0.0:
		return 0
	var l := exp(-minf(lam, 30.0))
	var kk := 0
	var p := 1.0
	while kk < 200:
		p *= r.randf()
		if p <= l:
			break
		kk += 1
	return kk

func _sim_stats(P: Dictionary, sw: Array, reps: int, sd: int) -> Dictionary:
	var acc := {"hw": 0.0, "dr": 0.0, "aw": 0.0, "big": 0.0, "nil": 0.0, "gpm": 0.0, "ha": 0.0}
	for rep in reps:
		var r := RandomNumberGenerator.new()
		r.seed = sd + rep * 7919
		var ph := PackedInt32Array()
		var pa := PackedInt32Array()
		for i in m_d.size():
			var sc: Array = score(r, m_d[i], P, sw)
			ph.append(sc[0])
			pa.append(sc[1])
		var st := _res_stats(ph, pa)
		for k in acc:
			acc[k] += float(st[k]) / float(reps)
	return acc

## Skor durumu parametreleri: ızgara (home, lead_k, trail_k); her noktada taban, gol/maç motora
## eşit olacak şekilde ölçeklenir. Hata: ev/beraberlik/dep/4+ (puan²) + gol/maç + ev/dep oranı.
func _fit_state(out: Dictionary) -> void:
	var mins: Array = out.minutes
	var sw := [mins[0], mins[1], mins[2], mins[3], mins[4], float(mins[5]) + float(mins[6])]
	var tot := 0.0
	for x in sw:
		tot += float(x)
	for i in sw.size():
		sw[i] = float(sw[i]) / tot
	out.slices = sw
	var mo := _res_stats(m_gh, m_ga)
	var P0: Dictionary = out.poisson
	var best := {}
	var best_e := 1e18
	for hm in [float(P0.home), float(P0.home) + 0.4, float(P0.home) + 0.8]:
		for lk in [0.15, 0.2, 0.25, 0.3, 0.35]:
			for tk in [0.1, 0.15, 0.2, 0.25, 0.3]:
				var P := {"base_h": P0.base_h, "base_a": P0.base_a, "div": P0.div, "home": hm, "lead_k": lk, "trail_k": tk}
				var st := _sim_stats(P, sw, 1, 4242)
				var scale: float = float(mo.gpm) / maxf(0.01, float(st.gpm))
				P.base_h = float(P0.base_h) * scale
				P.base_a = float(P0.base_a) * scale
				st = _sim_stats(P, sw, 2, 777)
				var e := 0.0
				for k in ["hw", "dr", "aw", "big"]:
					e += pow(float(st[k]) - float(mo[k]), 2.0)
				e += 25.0 * pow(float(st.gpm) - float(mo.gpm), 2.0) + 400.0 * pow(float(st.ha) - float(mo.ha), 2.0)
				if e < best_e:
					best_e = e
					best = P
					best.err = e
					best.st = st
	print("motor: ev %.1f ber %.1f dep %.1f 4+ %.1f 0-0 %.1f gol %.2f ev/dep %.3f" % [mo.hw, mo.dr, mo.aw, mo.big, mo.nil, mo.gpm, mo.ha])
	print("model: ", JSON.stringify(best.st), " hata %.2f" % best.err)
	out.poisson = {"base_h": snappedf(float(best.base_h), 0.0001), "base_a": snappedf(float(best.base_a), 0.0001),
		"home": snappedf(float(best.home), 0.001), "div": P0.div, "lead_k": best.lead_k, "trail_k": best.trail_k,
		"mle": P0}

func _res_stats(gh: PackedInt32Array, ga: PackedInt32Array) -> Dictionary:
	var nn := gh.size()
	var o := {"n": nn, "gpm": 0.0, "hw": 0.0, "dr": 0.0, "aw": 0.0, "big": 0.0, "ha": 0.0, "nil": 0.0}
	var sh := 0
	var sa := 0
	for i in nn:
		sh += gh[i]
		sa += ga[i]
		if gh[i] > ga[i]:
			o.hw += 1
		elif gh[i] == ga[i]:
			o.dr += 1
			if gh[i] == 0:
				o.nil += 1
		else:
			o.aw += 1
		if absi(gh[i] - ga[i]) >= 4:
			o.big += 1
	for k in ["hw", "dr", "aw", "big", "nil"]:
		o[k] = snappedf(100.0 * o[k] / maxf(1.0, float(nn)), 0.01)
	o.gpm = snappedf(float(sh + sa) / maxf(1.0, float(nn)), 0.001)
	o.ha = snappedf(float(sh) / maxf(1.0, float(sa)), 0.001)
	return o

func _validate(cal: Dictionary) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = 99173
	var P: Dictionary = cal.poisson
	var R: Dictionary = cal.rating
	var W := []
	for gname in GROUPS:
		W.append(float(cal.scorer_w[gname]))
	var ph := PackedInt32Array()
	var pa := PackedInt32Array()
	var grp := [0, 0, 0, 0]
	var gn := 0
	var rt_n := 0
	var rt_s := 0.0
	var rt_q := 0.0
	var by_g_s := [0.0, 0.0, 0.0, 0.0]
	var by_g_n := [0, 0, 0, 0]
	for i in m_d.size():
		var scr: Array = score(r, m_d[i], P, cal.slices)
		var gh: int = scr[0]
		var ga: int = scr[1]
		ph.append(gh)
		pa.append(ga)
		for si in 2:
			var xi: Array = m_xi[i][si]
			var ng: int = gh if si == 0 else ga
			var goals := []
			goals.resize(xi.size())
			goals.fill(0)
			var asts := goals.duplicate()
			for _g in ng:
				var tot := 0.0
				for pi: Array in xi:
					tot += W[pi[0]] * pow(float(pi[1]) / 10.0, 2.0)
				var u := r.randf() * tot
				var sc := xi.size() - 1
				for j in xi.size():
					u -= W[xi[j][0]] * pow(float(xi[j][1]) / 10.0, 2.0)
					if u <= 0.0:
						sc = j
						break
				goals[sc] += 1
				grp[xi[sc][0]] += 1
				gn += 1
				if r.randf() >= float(cal.no_assist):
					var aj := (sc + 1 + r.randi_range(0, xi.size() - 2)) % xi.size()
					asts[aj] += 1
			var gd: int = (gh - ga) * (1 if si == 0 else -1)
			var b: int = clampi(gd, -3, 3) + 3
			var avg := 0.0
			for pi: Array in xi:
				avg += float(pi[2])
			avg /= maxf(1.0, float(xi.size()))
			for j in xi.size():
				var pi: Array = xi[j]
				var gi: int = pi[0]
				var v: float = float(R.mu[b]) + float(R.k_ovr) * (float(pi[2]) - avg) + float(R.goal) * goals[j] + float(R.assist) * asts[j] + float(R.grp[GROUPS[gi]])
				v += r.randfn(0.0, float(R.sd[b]) * (0.95 - 0.03 * float(pi[3])) / float(R.cons_norm))
				if m_big[i][si]:
					v += (float(pi[4]) - 10.0) * 0.04
				v = snappedf(clampf(v, 3.5, 9.8), 0.1)
				rt_n += 1
				rt_s += v
				rt_q += v * v
				by_g_s[gi] += v
				by_g_n[gi] += 1
	var mo := _res_stats(m_gh, m_ga)
	var po := _res_stats(ph, pa)
	# motor reyting
	var ms := 0.0
	var mq := 0.0
	var mg_s := [0.0, 0.0, 0.0, 0.0]
	var mg_n := [0, 0, 0, 0]
	for j in r_y.size():
		ms += r_y[j]
		mq += r_y[j] * r_y[j]
		mg_s[r_grp[j]] += r_y[j]
		mg_n[r_grp[j]] += 1
	var mmu := ms / maxf(1.0, float(r_y.size()))
	var pmu := rt_s / maxf(1.0, float(rt_n))
	mo.rt_mean = snappedf(mmu, 0.001)
	mo.rt_sd = snappedf(sqrt(maxf(0.0, mq / maxf(1.0, float(r_y.size())) - mmu * mmu)), 0.001)
	po.rt_mean = snappedf(pmu, 0.001)
	po.rt_sd = snappedf(sqrt(maxf(0.0, rt_q / maxf(1.0, float(rt_n)) - pmu * pmu)), 0.001)
	mo.rt_grp = {}
	po.rt_grp = {}
	mo.scorer = {}
	po.scorer = {}
	for gi in 4:
		mo.rt_grp[GROUPS[gi]] = snappedf(mg_s[gi] / maxf(1.0, float(mg_n[gi])), 0.001)
		po.rt_grp[GROUPS[gi]] = snappedf(by_g_s[gi] / maxf(1.0, float(by_g_n[gi])), 0.001)
		mo.scorer[GROUPS[gi]] = snappedf(100.0 * g_grp[gi] / maxf(1.0, float(g_n)), 0.01)
		po.scorer[GROUPS[gi]] = snappedf(100.0 * grp[gi] / maxf(1.0, float(gn)), 0.01)
	ms_list.sort()
	mo.ms_median = snappedf(ms_list[ms_list.size() / 2], 0.01)
	mo.ms_max = snappedf(ms_list[ms_list.size() - 1], 0.01)
	return {"motor": mo, "poisson_model": po}

func _print(out: Dictionary) -> void:
	print("poisson: ", JSON.stringify(out.poisson))
	for b: Dictionary in out.buckets:
		print("  d %-12s n=%5d motor %.2f-%.2f model %.2f-%.2f" % [b.d, b.n, b.motor_gh, b.motor_ga, b.model_gh, b.model_ga])
	print("golcü ağırlık: ", JSON.stringify(out.scorer_w), " motor pay: ", JSON.stringify(out.scorer_share_motor))
	print("asistsiz: ", out.no_assist, "  dakika: ", JSON.stringify(out.minutes))
	print("reyting: ", JSON.stringify(out.rating))
	print("motor : ", JSON.stringify(out.check.motor))
	print("model : ", JSON.stringify(out.check.poisson_model))
