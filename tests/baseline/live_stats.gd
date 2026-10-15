extends Node
## Ölçüm temeli (v0.23 Dalga 1-D): canlı motor (sim/live_engine.gd) istatistikleri.
## Gerçek fikstürden N maç alır, LiveEngine.run_to_end() ile oynatır; puan tablosuna
## ve oyuncu istatistiklerine YAZMAZ. Sonuç: "RESULT_JSON {...}" satırı.
## Ortam değişkenleri: N (maç sayısı, varsayılan 200), LGS (virgüllü lig listesi,
## varsayılan "SL"), SEED (varsayılan 2301).
const LiveEngine = preload("res://sim/live_engine.gd")

func _env_int(k: String, d: int) -> int:
	var v := OS.get_environment(k)
	return int(v) if v != "" else d

func _ready() -> void:
	var n := _env_int("N", 200)
	var seed_v := _env_int("SEED", 2301)
	var lgs: Array = (OS.get_environment("LGS") if OS.get_environment("LGS") != "" else "SL").split(",")
	seed(seed_v)
	Game.rng.seed = seed_v
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	# fikstürden maç listesi (ligler sırayla, tur tur)
	var pool := []
	var r := 0
	while pool.size() < n and r < 60:
		var any := false
		for lg in lgs:
			if not Game.s.fixtures.has(lg) or r >= Game.s.fixtures[lg].size():
				continue
			any = true
			for m in Game.s.fixtures[lg][r]:
				if pool.size() < n:
					pool.append({"lg": lg, "h": m.h, "a": m.a})
		if not any:
			break
		r += 1
	var res := {"n": 0, "goals": 0, "gh": 0, "ga": 0, "hw": 0, "dr": 0, "aw": 0, "nil": 0,
		"shots": 0, "sot": 0, "passes": 0, "pass_ok": 0, "fouls": 0, "corners": 0, "yellow": 0, "red": 0,
		"scores": {}, "ms": []}
	var t_all := Time.get_ticks_msec()
	for i in pool.size():
		var p: Dictionary = pool[i]
		Game.ensure_squad(p.h)
		Game.ensure_squad(p.a)
		var m := {"h": p.h, "a": p.a, "day": "sat", "gh": -1, "ga": -1, "ev": []}
		var eng = LiveEngine.new()
		var t0 := Time.get_ticks_msec()
		eng.setup(Game, m, false, seed_v * 1000 + i + 1)
		eng.run_to_end()
		res.ms.append(Time.get_ticks_msec() - t0)
		var gh: int = eng.score[0]
		var ga: int = eng.score[1]
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
		var sk := "%d-%d" % [gh, ga]
		res.scores[sk] = int(res.scores.get(sk, 0)) + 1
		res.shots += int(eng.shots.h) + int(eng.shots.a)
		for e in eng.events:
			match e.ty:
				"shot":
					if e.ok:
						res.sot += 1
				"foul":
					res.fouls += 1
				"corner":
					res.corners += 1
				"yellow":
					res.yellow += 1
				"red":
					res.red += 1
		for q in eng.pl.values():
			res.passes += int(q.st.p)
			res.pass_ok += int(q.st.po)
		if (i + 1) % 25 == 0:
			print("ilerleme %d/%d  %d ms" % [i + 1, pool.size(), Time.get_ticks_msec() - t_all])
	var ms: Array = res.ms.duplicate()
	ms.sort()
	var nn := maxf(1.0, float(res.n))
	var out := {
		"engine": "live", "seed": seed_v, "leagues": lgs, "matches": res.n,
		"goals_per_match": snappedf(res.goals / nn, 0.01),
		"home_goals_per_match": snappedf(res.gh / nn, 0.01),
		"away_goals_per_match": snappedf(res.ga / nn, 0.01),
		"home_win_pct": snappedf(100.0 * res.hw / nn, 0.1),
		"draw_pct": snappedf(100.0 * res.dr / nn, 0.1),
		"away_win_pct": snappedf(100.0 * res.aw / nn, 0.1),
		"nil_nil_pct": snappedf(100.0 * res.nil / nn, 0.1),
		"shots_per_match": snappedf(res.shots / nn, 0.1),
		"shots_on_target_per_match": snappedf(res.sot / nn, 0.1),
		"pass_attempts_per_match": snappedf(res.passes / nn, 1.0),
		"pass_accuracy_pct": snappedf(100.0 * res.pass_ok / maxf(1.0, float(res.passes)), 0.1),
		"fouls_per_match": snappedf(res.fouls / nn, 0.1),
		"corners_per_match": snappedf(res.corners / nn, 0.1),
		"yellow_per_match": snappedf(res.yellow / nn, 0.01),
		"red_per_match": snappedf(res.red / nn, 0.01),
		"score_dist": res.scores,
		"cpu_ms_per_match_median": ms[ms.size() / 2] if not ms.is_empty() else 0,
		"cpu_ms_per_match_max": ms[ms.size() - 1] if not ms.is_empty() else 0,
		"cpu_ms_total": Time.get_ticks_msec() - t_all,
	}
	print("RESULT_JSON " + JSON.stringify(out))
	get_tree().quit(0)
