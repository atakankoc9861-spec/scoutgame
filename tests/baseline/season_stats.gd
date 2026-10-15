extends Node
## Ölçüm temeli (v0.23 Dalga 1-D): Poisson tarafı (Game.sim_match) + hafta süresi.
## Bir tam sezonu Game.end_week_auto() ile oynatır; her haftanın süresini (ms) ölçer,
## sezon sonunda tüm lig maçlarının skorlarını toplar.
## Ortam değişkenleri:
##   SEED (varsayılan 2301)
##   PLAN=1  -> her hafta cumartesi oyuncunun liginden bir maç planlanır (canlı motor
##              ile izlenir, gerçek oyuncu akışına daha yakın). Varsayılan 0: plansız.
## Sonuç: "RESULT_JSON {...}" satırı.

func _env_int(k: String, d: int) -> int:
	var v := OS.get_environment(k)
	return int(v) if v != "" else d

func _blank() -> Dictionary:
	return {"n": 0, "goals": 0, "gh": 0, "ga": 0, "hw": 0, "dr": 0, "aw": 0, "nil": 0, "scores": {}}

func _add(a: Dictionary, gh: int, ga: int) -> void:
	a.n += 1
	a.goals += gh + ga
	a.gh += gh
	a.ga += ga
	if gh > ga:
		a.hw += 1
	elif gh == ga:
		a.dr += 1
	else:
		a.aw += 1
	if gh + ga == 0:
		a.nil += 1
	var sk := "%d-%d" % [gh, ga]
	a.scores[sk] = int(a.scores.get(sk, 0)) + 1

func _fin(a: Dictionary) -> Dictionary:
	var nn := maxf(1.0, float(a.n))
	return {"matches": a.n,
		"goals_per_match": snappedf(a.goals / nn, 0.01),
		"home_goals_per_match": snappedf(a.gh / nn, 0.01),
		"away_goals_per_match": snappedf(a.ga / nn, 0.01),
		"home_win_pct": snappedf(100.0 * a.hw / nn, 0.1),
		"draw_pct": snappedf(100.0 * a.dr / nn, 0.1),
		"away_win_pct": snappedf(100.0 * a.aw / nn, 0.1),
		"nil_nil_pct": snappedf(100.0 * a.nil / nn, 0.1),
		"score_dist": a.scores}

func _ready() -> void:
	var seed_v := _env_int("SEED", 2301)
	var plan := _env_int("PLAN", 0) == 1
	seed(seed_v)
	Game.rng.seed = seed_v
	var t0 := Time.get_ticks_msec()
	Game.new_game("T", "tr")
	var new_game_ms := Time.get_ticks_msec() - t0
	Game.take_job(Game.job_offers_start()[0])
	var my_lg: String = Game.club(Game.s.scout.club_id).league
	# maç türü (lazy = kulüp seviyesinden skor, detailed = ilk 11 gücünden skor), oynanmadan önce
	var seen := []
	var week_ms := []
	var live_watched := 0
	var s0: int = Game.s.season
	var guard := 0
	while Game.s.season == s0 and guard < 60:
		guard += 1
		for wm in Game.week_matches():
			# referans tutulur: sezon sonu fikstürler yenilense de sonuç bu sözlükte kalır
			seen.append({"lg": wm.lg, "m": wm.m, "kind": "lazy" if (Game.is_lazy(wm.m.h) or Game.is_lazy(wm.m.a)) else "detailed"})
		if plan:
			var ms: Array = Game.week_matches([my_lg])
			for wm in ms:
				if wm.m.day == "sat":
					if Game.plan_match("sat", Game.match_key(wm.lg, wm.idx)):
						live_watched += 1
					break
		var t1 := Time.get_ticks_msec()
		Game.end_week_auto()
		week_ms.append(Time.get_ticks_msec() - t1)
	# save maliyeti ayrıca
	var save_ms := []
	for i in 5:
		var t2 := Time.get_ticks_msec()
		Game.save_game()
		save_ms.append(Time.get_ticks_msec() - t2)
	save_ms.sort()
	# sonuçları topla
	var all := _blank()
	var by_kind := {"lazy": _blank(), "detailed": _blank()}
	var by_tier := {}
	var top5 := _blank()
	var tr_sl := _blank()
	var played := 0
	for it in seen:
		var m: Dictionary = it.m
		var lg: String = it.lg
		if int(m.gh) < 0:
			continue
		var t := Game.tier(lg)
		if not by_tier.has(t):
			by_tier[t] = _blank()
		played += 1
		var gh := int(m.gh)
		var ga := int(m.ga)
		_add(all, gh, ga)
		_add(by_tier[t], gh, ga)
		_add(by_kind[it.kind], gh, ga)
		if lg in ["EN1", "ES1", "IT1", "DE1", "FR1"]:
			_add(top5, gh, ga)
		if lg == "SL":
			_add(tr_sl, gh, ga)
	var sw: Array = week_ms.duplicate()
	sw.sort()
	var tiers_out := {}
	for t in by_tier:
		tiers_out[str(t)] = _fin(by_tier[t])
	var out := {
		"engine": "poisson", "seed": seed_v, "plan": plan, "live_watched": live_watched,
		"season_weeks_run": guard, "played_matches": played,
		"season_finished": Game.s.season != s0, "my_league": my_lg,
		"all": _fin(all), "lazy": _fin(by_kind.lazy), "detailed": _fin(by_kind.detailed),
		"top5_tier1": _fin(top5), "SL": _fin(tr_sl), "by_tier": tiers_out,
		"new_game_ms": new_game_ms,
		"week_ms": week_ms,
		"week_ms_median": sw[sw.size() / 2],
		"week_ms_p90": sw[int(sw.size() * 0.9)],
		"week_ms_max": sw[sw.size() - 1],
		"week_ms_min": sw[0],
		"save_ms_median": save_ms[2],
		"save_bytes": FileAccess.get_file_as_bytes(Game.SAVE_PATH).size(),
	}
	print("RESULT_JSON " + JSON.stringify(out))
	get_tree().quit(0)
