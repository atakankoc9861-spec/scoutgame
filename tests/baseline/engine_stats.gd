extends Node
## v0.23 Dalga 2-F ölçümü: canlı motor (sim/live_engine.gd) ve hızlı motor (sim/quick_engine.gd)
## aynı maç havuzunda, aynı ilk 11'lerle. Puan tablosuna ve oyuncu istatistiklerine YAZMAZ.
## Ortam değişkenleri:
##   MODE  live | quick (varsayılan quick)
##   N     maç sayısı (varsayılan 2000 quick, 300 live)
##   SEED  dünya + maç tohumu (varsayılan 2301)
##   LGS   virgüllü lig listesi (varsayılan SL,EN1,ES1,IT1,DE1,FR1; tur tur sırayla)
## Sonuç: "RESULT_JSON {...}" satırı. tests/baseline/engine_agg.py birleştirir.
const LiveEngine = preload("res://sim/live_engine.gd")

func _env_int(k: String, d: int) -> int:
	var v: String = OS.get_environment(k)
	return int(v) if v.is_valid_int() else d

func _ready() -> void:
	var mode: String = OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "quick"
	var n: int = _env_int("N", 2000 if mode == "quick" else 300)
	var seed_v: int = _env_int("SEED", 2301)
	var lgs_s: String = OS.get_environment("LGS") if OS.get_environment("LGS") != "" else "SL,EN1,ES1,IT1,DE1,FR1"
	var lgs: PackedStringArray = lgs_s.split(",")
	seed(seed_v)
	Game.rng.seed = seed_v
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	var qe: GDScript = null
	if mode == "quick":
		qe = load("res://sim/quick_engine.gd")
	# fikstürden maç havuzu (ligler sırayla, tur tur); havuz yetmezse baştan tekrar (farklı ilk 11 gürültüsü)
	var pool: Array = []
	var r: int = 0
	while pool.size() < n:
		var any: bool = false
		for lg: String in lgs:
			if not Game.s.fixtures.has(lg):
				continue
			var fx: Array = Game.s.fixtures[lg]
			if fx.is_empty():
				continue
			any = true
			var rr: int = r % fx.size()
			for fm: Dictionary in fx[rr]:
				if pool.size() < n:
					pool.append({"lg": lg, "h": fm.h, "a": fm.a})
		if not any:
			break
		r += 1
	for p: Dictionary in pool:
		Game.ensure_squad(p.h)
		Game.ensure_squad(p.a)
	var res: Dictionary = {"n": 0, "goals": 0, "gh": 0, "ga": 0, "hw": 0, "dr": 0, "aw": 0, "nil": 0, "big": 0,
		"shots": 0, "sot": 0, "passes": 0, "pass_ok": 0, "fouls": 0, "corners": 0, "yellow": 0, "red": 0,
		"stronger_w": 0, "stronger_n": 0, "rt_sum": 0.0, "rt_sq": 0.0, "rt_n": 0, "gmin": [0, 0, 0, 0, 0, 0],
		"scorer_att": 0, "scorer_n": 0, "assist_n": 0, "scores": {}, "ms": [], "margin": {}}
	var t_all: int = Time.get_ticks_msec()
	for i: int in pool.size():
		var p: Dictionary = pool[i]
		var m: Dictionary = {"h": p.h, "a": p.a, "day": "sat", "gh": -1, "ga": -1, "ev": []}
		m.xi_h = Game.best_xi(p.h, true)
		m.xi_a = Game.best_xi(p.a, true)
		var ms_seed: int = seed_v * 100000 + i + 1
		var gh: int = 0
		var ga: int = 0
		var ev: Array = []
		var rt: Dictionary = {}
		var tm: Dictionary = {}
		var cards: Dictionary = {}
		var t0: int = Time.get_ticks_usec()
		if mode == "quick":
			var out: Dictionary = qe.simulate(Game, m, false, ms_seed)
			res.ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
			gh = out.gh
			ga = out.ga
			ev = out.ev
			rt = out.rt
			tm = out.team
			cards = out.cards
		else:
			var eng = LiveEngine.new()
			eng.setup(Game, m, false, ms_seed)
			eng.run_to_end()
			res.ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
			gh = eng.score[0]
			ga = eng.score[1]
			ev = eng.goal_events()
			rt = eng.ratings()
			tm = {"h": {"sh": int(eng.shots.h), "sot": 0, "fouls": 0, "corners": 0, "p": 0, "po": 0},
				"a": {"sh": int(eng.shots.a), "sot": 0, "fouls": 0, "corners": 0, "p": 0, "po": 0}}
			for e: Dictionary in eng.events:
				match e.ty:
					"shot":
						if e.ok:
							tm[e.side].sot += 1
					"foul":
						tm[e.side].fouls += 1
					"corner":
						tm[e.side].corners += 1
					"yellow":
						res.yellow += 1
					"red":
						res.red += 1
			for q in eng.pl.values():
				tm[q.side].p += int(q.st.p)
				tm[q.side].po += int(q.st.po)
		for pid: String in cards:
			res.yellow += int(cards[pid].get("yc", 0))
			res.red += int(cards[pid].get("rc", 0))
		res.n += 1
		res.goals += gh + ga
		res.gh += gh
		res.ga += ga
		if gh > ga:
			res.hw += 1
		elif gh == ga:
			res.dr += 1
		else:
			res.aw += 1
		if gh + ga == 0:
			res.nil += 1
		if absi(gh - ga) >= 4:
			res.big += 1
		var mk: String = str(mini(absi(gh - ga), 5))
		res.margin[mk] = int(res.margin.get(mk, 0)) + 1
		var sk: String = "%d-%d" % [gh, ga]
		res.scores[sk] = int(res.scores.get(sk, 0)) + 1
		for sd: String in ["h", "a"]:
			res.shots += int(tm[sd].sh)
			res.sot += int(tm[sd].sot)
			res.fouls += int(tm[sd].fouls)
			res.corners += int(tm[sd].corners)
			res.passes += int(tm[sd].get("p", 0))
			res.pass_ok += int(tm[sd].get("po", 0))
		# güçlü takım (ilk 11 ovr ortalaması 1.5+ fazla) kazanıyor mu
		var sh_: float = _str(m.xi_h)
		var sa_: float = _str(m.xi_a)
		if absf(sh_ - sa_) >= 1.5:
			res.stronger_n += 1
			if (sh_ > sa_ and gh > ga) or (sa_ > sh_ and ga > gh):
				res.stronger_w += 1
		for pid: String in rt:
			var v: float = float(rt[pid])
			res.rt_sum += v
			res.rt_sq += v * v
			res.rt_n += 1
		for e: Dictionary in ev:
			var mn: int = int(e["min"])
			res.gmin[clampi((mn - 1) / 15, 0, 5)] += 1
			res.scorer_n += 1
			if Data.POS_GROUP[Game.player(e.pid).pos] == "ATT":
				res.scorer_att += 1
			if str(e["as"]) != "":
				res.assist_n += 1
		if (i + 1) % 100 == 0 and mode == "live":
			print("ilerleme %d/%d  %d ms" % [i + 1, pool.size(), Time.get_ticks_msec() - t_all])
	var ms: Array = res.ms.duplicate()
	ms.sort()
	var nn: float = maxf(1.0, float(res.n))
	var rn: float = maxf(1.0, float(res.rt_n))
	var rmean: float = res.rt_sum / rn
	var out2: Dictionary = {
		"engine": mode, "seed": seed_v, "leagues": lgs_s, "matches": res.n,
		"goals": res.goals, "gh": res.gh, "ga": res.ga, "hw": res.hw, "dr": res.dr, "aw": res.aw,
		"nil": res.nil, "big": res.big, "stronger_w": res.stronger_w, "stronger_n": res.stronger_n,
		"goals_per_match": snappedf(res.goals / nn, 0.01),
		"home_away_goal_ratio": snappedf(float(res.gh) / maxf(1.0, float(res.ga)), 0.01),
		"home_win_pct": snappedf(100.0 * res.hw / nn, 0.1),
		"draw_pct": snappedf(100.0 * res.dr / nn, 0.1),
		"away_win_pct": snappedf(100.0 * res.aw / nn, 0.1),
		"nil_nil_pct": snappedf(100.0 * res.nil / nn, 0.1),
		"big_margin_pct": snappedf(100.0 * res.big / nn, 0.1),
		"stronger_win_pct": snappedf(100.0 * res.stronger_w / maxf(1.0, float(res.stronger_n)), 0.1),
		"shots_per_match": snappedf(res.shots / nn, 0.1),
		"sot_per_match": snappedf(res.sot / nn, 0.1),
		"pass_attempts_per_match": snappedf(res.passes / nn, 1.0),
		"pass_accuracy_pct": snappedf(100.0 * res.pass_ok / maxf(1.0, float(res.passes)), 0.1),
		"fouls_per_match": snappedf(res.fouls / nn, 0.1),
		"corners_per_match": snappedf(res.corners / nn, 0.1),
		"yellow_per_match": snappedf(res.yellow / nn, 0.01),
		"red_per_match": snappedf(res.red / nn, 0.01),
		"rating_mean": snappedf(rmean, 0.01),
		"rating_sd": snappedf(sqrt(maxf(0.0, res.rt_sq / rn - rmean * rmean)), 0.01),
		"goal_min_buckets_15": res.gmin,
		"scorer_att_pct": snappedf(100.0 * res.scorer_att / maxf(1.0, float(res.scorer_n)), 0.1),
		"assisted_pct": snappedf(100.0 * res.assist_n / maxf(1.0, float(res.scorer_n)), 0.1),
		"margin": res.margin,
		"score_dist": res.scores,
		"ms_median": snappedf(ms[ms.size() / 2], 0.01) if not ms.is_empty() else 0.0,
		"ms_p99": snappedf(ms[int(ms.size() * 0.99)], 0.01) if not ms.is_empty() else 0.0,
		"ms_max": snappedf(ms[ms.size() - 1], 0.01) if not ms.is_empty() else 0.0,
		"ms_first": snappedf(res.ms[0], 0.01) if not ms.is_empty() else 0.0,
		"ms_max_after_first": snappedf(_max_after_first(res.ms), 0.01),
		"cpu_ms_total": Time.get_ticks_msec() - t_all,
	}
	print("RESULT_JSON " + JSON.stringify(out2))
	get_tree().quit(0)

func _str(xi: Array) -> float:
	var t: float = 0.0
	for pid: String in xi:
		t += float(Game.player(pid).ovr)
	return t / maxf(1.0, float(xi.size()))

func _max_after_first(a: Array) -> float:
	var mx: float = 0.0
	for i: int in range(1, a.size()):
		mx = maxf(mx, float(a[i]))
	return mx
