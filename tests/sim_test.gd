extends Node

func _ready() -> void:
	var t0 = Time.get_ticks_msec()
	Game.new_game("Test", "tr")
	print("players: ", Game.s.players.size(), " clubs ", Game.s.clubs.size(), " gen ms ", Time.get_ticks_msec() - t0)
	var szs := {}
	for cid in Game.s.clubs:
		var lg: String = Game.s.clubs[cid].league
		szs[lg] = szs.get(lg, 0) + 1
	print("leagues ", szs)
	for lg in ["SL","L1","L2A","L3A","BAL1"]:
		var c0 = Game.league_clubs(lg)[0]
		print(lg, " ", Game.club(c0).name, " avg xi ", snappedf(Game.club_avg_ovr(c0), 0.1), " squad ", Game.club(c0).squad.size(), " u19 ", Game.club(c0).u19.size(), " rounds ", Game.league_round_count(lg))
	var offers = Game.job_offers_start()
	Game.take_job(offers[0])
	# zaman çizelgesi testi
	Game.end_week_auto()
	var ms = Game.week_matches()
	var m = ms[0]
	var key = Game.match_key(m.lg, m.idx)
	Game.play_day("sat")
	Game.play_day("sun")
	var t1 = Time.get_ticks_msec()
	var data = Game.watch_match_data(key)
	print("timeline events: ", data.tl.size(), " ms ", Time.get_ticks_msec() - t1, " score ", data.m.gh, "-", data.m.ga)
	var goals = 0
	var types = {}
	for e in data.tl:
		types[e.ty] = types.get(e.ty, 0) + 1
		if e.ty == "goal": goals += 1
	print("goal events ", goals, " types ", types)
	print("last t ", data.tl[-1].t)
	# tahmin doğruluğu: aynı maçı 6 kez izlenmiş gibi biriktir
	var agg = Game.Timeline.aggregate(Game, data.tl, data.m.xi_h + data.m.xi_a)
	var err_sum = 0.0
	var n = 0
	for pid in data.m.xi_h:
		var p = Game.player(pid)
		for a in agg[pid].attr:
			if agg[pid].attr[a].n >= 8:
				var imp = Game.Timeline.implied(agg[pid], a)
				err_sum += abs(imp - p.attrs[a])
				n += 1
				if n <= 8:
					print(p.pos, " ", a, " n=", agg[pid].attr[a].n, " true=", p.attrs[a], " implied=", snappedf(imp, 0.1))
	print("mean abs err single match: ", err_sum / max(1, n), " over ", n)
	# 6 maç birikimli tahmin
	var pid_t = data.m.xi_h[6]
	var fe0 = {}
	fe0[pid_t] = range(data.tl.size())
	for k in 6:
		var mm2 = data.m.duplicate()
		var tl2 = Game.Timeline.generate(Game, mm2)
		var ag2 = Game.Timeline.aggregate(Game, tl2, [pid_t])
		Game._learn_from_agg(pid_t, ag2[pid_t], 1.0)
		var errs = 0.0
		var cnt = 0
		for a in Data.POS_WEIGHTS[Game.player(pid_t).pos]:
			var r = Game.attr_range(pid_t, a)
			if r.size() > 0:
				var mid = (r[0] + r[1]) / 2.0
				errs += abs(mid - Game.player(pid_t).attrs[a])
				cnt += 1
		if k == 5:
			var knx = Game.know(pid_t)
			for a in knx.ev:
				print("   ", a, " ev=", knx.ev[a], " k=", snappedf(knx.k[a],0.01), " n=", ag2[pid_t].attr[a].n if ag2[pid_t].attr.has(a) else 0)
		print("after ", k + 1, " matches: mean err key attrs ", snappedf(errs / max(1, cnt), 0.01), " ovr range ", Game.ovr_range(pid_t), " true ovr ", Game.player(pid_t).ovr, " known ", snappedf(Game.known_fraction(pid_t), 0.01))
	var fe = {}
	fe[data.m.xi_h[5]] = range(data.tl.size())
	var obs = Game.apply_watch(data, fe)
	print("notes: ", obs.notes)
	for k in obs.notes:
		for item in obs.notes[k]:
			print("  ", T.t(item[0], item[1]))
		print("  line: ", T.t(obs.lines[k][0], obs.lines[k][1]))
	# U19
	var u = Game.watch_u19_data(0)
	print("u19 events ", u.tl.size(), " xi ", u.m.xi_h.size(), "/", u.m.xi_a.size())
	var o2 = Game.apply_watch(u, {})
	print("discovered ", o2.new_disc.size())
	Game.finish_week()
	for season in 2:
		while true:
			var wm = Game.week_matches()
			if wm.size() > 0:
				var mm = wm[Game.ri(0, wm.size()-1)]
				Game.plan_match(mm.m.day, Game.match_key(mm.lg, mm.idx))
				var sq = Game.best_xi(mm.m.h)
				for i in 3:
					Game.toggle_focus(mm.m.day, sq[Game.ri(0, sq.size()-1)])
			if Game.wed_free() and Game.s.u19fx.size() > 0:
				var ud = Game.watch_u19_data(Game.ri(0, Game.s.u19fx.size()-1))
				Game.apply_watch(ud, {})
			var sl = Game.search({"lg": "SL"})
			if sl.size() > 3:
				Game.do_video(sl[0])
				Game.do_training(sl[1])
				Game.do_meet(sl[2])
				Game.do_source(sl[3], "coach")
			for a in Game.s.assign:
				if a.status == "open" and Game.rf() < 0.3:
					var cands = Game.search({"grp": Data.POS_GROUP[a.pos], "max_age": a.max_age})
					if cands.size() > 0:
						var pid: String = cands[Game.ri(0, min(5, cands.size()-1))]
						Game.submit_report(pid, a.id, Game.stars(Game.player(pid).ovr), Game.stars(Game.player(pid).pa), "sign")
			var res = Game.end_week_auto()
			if res.get("season_end", false):
				var sm: Dictionary = Game.s.season_summary
				for t in [2,3,4,5]:
					print("  up from tier ", t, ": ", sm.moves.up[t].map(func(c): return Game.club(c).name))
				for t in [1,2,3,4]:
					print("  down from tier ", t, ": ", sm.moves.down[t].map(func(c): return Game.club(c).name))
				var cnt := {}
				for cid in Game.s.clubs:
					var lg: String = Game.s.clubs[cid].league
					cnt[lg] = cnt.get(lg, 0) + 1
				print("  league sizes ", cnt)
				print("SEASON END ", sm.season, " champ ", Game.club(sm.champ).name, " rep ", snappedf(sm.rep_before,0.1), "->", snappedf(sm.rep_after,0.1), " evals ", sm.evals.size(), " promoted youth tracked ", sm.promoted_youth.size())
				Game.dismiss_summary()
				break
	print("stats ", Game.s.scout.stats, " youth disc ", Game.discovered_youth().size())
	var ts := Time.get_ticks_msec()
	Game.save_game()
	print("save ms ", Time.get_ticks_msec() - ts, " size ", FileAccess.get_file_as_bytes(Game.SAVE_PATH).size())
	ts = Time.get_ticks_msec()
	print("load ok: ", Game.load_game(), " ms ", Time.get_ticks_msec() - ts)
	for nn in Game.s.news.slice(0, 6):
		print(T.t(nn.key, nn.args))
	print("total ms ", Time.get_ticks_msec() - t0)
	get_tree().quit()
