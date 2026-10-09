extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.finish_week()
	var tot := {"g": 0, "shots": 0, "on": 0, "pass": 0, "pass_ok": 0, "drib": 0, "press": 0, "cross": 0, "head": 0, "save": 0, "corner": 0, "foul": 0, "yellow": 0, "red": 0, "penalty": 0, "offside": 0, "home_w": 0, "away_w": 0, "draw": 0}
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 20
	var t0 := Time.get_ticks_msec()
	var lgs = OS.get_environment("LG").split(",") if OS.get_environment("LG") != "" else ["SL"]
	var ms = Game.week_matches(lgs)
	var stronger := 0
	for i in n:
		var wm = ms[i % ms.size()]
		var m = {"h": wm.m.h, "a": wm.m.a, "day": "sat", "gh": -1, "ga": -1, "ev": []}
		var eng = Game.LiveEngine.new()
		eng.setup(Game, m, false, 1000 + i)
		eng.run_to_end()
		tot.g += eng.score[0] + eng.score[1]
		if eng.score[0] > eng.score[1]: tot.home_w += 1
		elif eng.score[0] < eng.score[1]: tot.away_w += 1
		else: tot.draw += 1
		var sh = Game.club_avg_ovr(m.h) - Game.club_avg_ovr(m.a)
		if (sh > 0 and eng.score[0] > eng.score[1]) or (sh < 0 and eng.score[0] < eng.score[1]): stronger += 1
		for e in eng.events:
			match e.ty:
				"shot":
					tot.shots += 1
					if e.ok: tot.on += 1
				"pass":
					tot.pass += 1
					if e.ok: tot.pass_ok += 1
				"dribble": tot.drib += 1
				"press": tot.press += 1
				"cross": tot.cross += 1
				"header": tot.head += 1
				"save": tot.save += 1
				"corner": tot.corner += 1
				"foul": tot.foul += 1
				"yellow": tot.yellow += 1
				"red": tot.red += 1
				"penalty": tot.penalty += 1
				"offside": tot.offside += 1
		if i < 3:
			print("  dbg ", eng.dbg, " avg lx ", eng.dbg.lx_sum / max(1, eng.dbg.dec))
		if i < 5:
			print("match ", i, " ", Game.club(m.h).short, " ", eng.score[0], "-", eng.score[1], " ", Game.club(m.a).short, " events ", eng.events.size(), " t ", snappedf(eng.t, 1), " shots ", eng.shots)
	var ms_per = (Time.get_ticks_msec() - t0) / float(n)
	print("PER MATCH: goals ", snappedf(tot.g / float(n), 0.01), " shots ", tot.shots / n, " on ", tot.on / n, " passes ", tot.pass / n, " pass% ", snappedf(100.0 * tot.pass_ok / max(1, tot.pass), 0.1), " drib ", tot.drib / n, " press ", tot.press / n, " cross ", tot.cross / n, " head ", tot.head / n, " saves ", tot.save / n, " corners ", tot.corner / n, " fouls ", tot.foul / n)
	print("cards Y/R %.2f/%.2f pens %.2f offs %.2f fouls %.1f" % [tot.yellow / float(n), tot.red / float(n), tot.penalty / float(n), tot.offside / float(n), tot.foul / float(n)])
	print("results H/D/A ", tot.home_w, "/", tot.draw, "/", tot.away_w, " stronger won ", stronger, "/", n, " ms/match ", ms_per)
	get_tree().quit()
