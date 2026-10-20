extends RefCounted
## SADECE test kodunun doğrulaması için sahte hızlı motor (HYBRID_QE=res://tests/baseline/hybrid_mock_qe.gd).
## sim/quick_engine.gd arayüzüne uyar: static simulate(g, m, youth, seed_v) -> Dictionary, saf, deterministik.
## Kalibre DEĞİLDİR; oyunda kullanılmaz.

static func simulate(g, m: Dictionary, _youth: bool, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var sides := {"h": m.xi_h, "a": m.xi_a}
	var str_ := {}
	for sd: String in sides:
		var t := 0.0
		for pid in sides[sd]:
			t += float(g.player(str(pid)).ovr)
		str_[sd] = t / maxf(1.0, float((sides[sd] as Array).size()))
	var lam := {"h": 1.45 * exp((str_.h - str_.a) / 14.0), "a": 1.15 * exp((str_.a - str_.h) / 14.0)}
	var goals := {"h": _poisson(rng, lam.h), "a": _poisson(rng, lam.a)}
	var ev := []
	var gcount := {}
	for sd: String in ["h", "a"]:
		var xi: Array = sides[sd]
		for i in int(goals[sd]):
			var tot := 0.0
			var ws := []
			for pid in xi:
				var p: Dictionary = g.player(str(pid))
				var w: float = {"GK": 0.0, "DEF": 0.25, "MID": 0.9, "ATT": 2.6}[Data.POS_GROUP[p.pos]]
				ws.append(w)
				tot += w
			var r := rng.randf() * tot
			var sc: String = str(xi[xi.size() - 1])
			for k in xi.size():
				r -= ws[k]
				if r <= 0.0:
					sc = str(xi[k])
					break
			gcount[sc] = int(gcount.get(sc, 0)) + 1
			ev.append({"t": "g", "pid": sc, "as": "", "side": sd, "min": rng.randi_range(1, 90)})
	ev.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.min) < int(y.min))
	var rt := {}
	for sd: String in ["h", "a"]:
		var gd: int = int(goals[sd]) - int(goals["a" if sd == "h" else "h"])
		for pid in sides[sd]:
			var v := 6.4 + clampf(float(gd), -3.0, 3.0) * 0.18 + rng.randfn(0.0, 0.6) + int(gcount.get(str(pid), 0)) * 0.7
			rt[pid] = snappedf(clampf(v, 4.5, 9.8), 0.1)
	return {"gh": goals.h, "ga": goals.a, "ev": ev, "rt": rt, "cards": {},
		"team": {"h": {"sh": 0, "sot": 0, "fouls": 0, "corners": 0, "poss": 50}, "a": {"sh": 0, "sot": 0, "fouls": 0, "corners": 0, "poss": 50}}}

static func _poisson(rng: RandomNumberGenerator, lam: float) -> int:
	var l := exp(-lam)
	var k := 0
	var p := 1.0
	while k < 20:
		p *= rng.randf()
		if p <= l:
			break
		k += 1
	return k
