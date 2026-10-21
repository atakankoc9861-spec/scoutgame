extends "res://tests/check/check_base.gd"
## v0.24 Dalga 1A — alt lig gol/beraberlik (canlı motor, kalecinin mutlak seviyesi).
## - LiveEngine.gk_abs_pen(): üst lig kalecisinde ~0, zayıf kalecide pozitif, monoton
## - LiveEngine.team_day_sd(): ilk 11 ovr ortalaması düştükçe artan takım günü oynaklığı, üst ligde 0
## - Gerçek ilk 11 kalecileri: TFF 2. Lig cezası üst liglerden belirgin büyük, üst liglerde küçük
## - Kısa canlı örnek (alt lig): skor = gol olayları, deterministik
## Asıl dağılım ölçümü: tests/baseline/engine_stats.tscn (MODE=live LGS=L1,L2A,L2B N=300).

const LiveEngine = preload("res://sim/live_engine.gd")

func watchdog_sec() -> float:
	return 280.0

func run_check() -> void:
	Game.new_game("T", "tr")
	Game.take_job(str(Game.job_offers_start()[0]))
	# formül
	check(is_zero_approx(LiveEngine.gk_abs_pen(15.0, 14.0)), "üst seviye kaleciye ceza var")
	check(LiveEngine.gk_abs_pen(9.0, 9.0) > 0.03, "zayıf kaleci cezası çok küçük: %.3f" % LiveEngine.gk_abs_pen(9.0, 9.0))
	check(LiveEngine.gk_abs_pen(9.0, 9.0) < 0.12, "zayıf kaleci cezası çok büyük")
	var prev: float = 1.0
	var mono: bool = true
	for v: int in range(4, 18):
		var p: float = LiveEngine.gk_abs_pen(float(v), float(v))
		mono = mono and p <= prev + 1e-6
		prev = p
	check(mono, "gk_abs_pen monoton değil")
	# takım günü oynaklığı: üst lig seviyesinde 0, alt seviyede pozitif ve sınırlı
	check(is_zero_approx(LiveEngine.team_day_sd(73.0)), "üst lig seviyesinde takım günü oynaklığı var")
	check(LiveEngine.team_day_sd(50.0) > LiveEngine.team_day_sd(57.0), "takım günü oynaklığı seviyeyle artmıyor")
	check(LiveEngine.team_day_sd(57.0) > 0.0, "L1 seviyesinde takım günü oynaklığı yok")
	check(LiveEngine.team_day_sd(30.0) <= LiveEngine.TEAM_DAY_SD + 1e-6, "takım günü oynaklığı sınırsız")
	# gerçek kaleciler
	var low: float = _mean_pen(["L2A", "L2B"])
	var top: float = _mean_pen(["SL", "EN1", "ES1", "IT1", "DE1", "FR1"])
	log_info("ortalama kaleci cezası: alt lig %.4f, üst lig %.4f" % [low, top])
	check_num(top, "üst lig kaleci cezası", 0.0, 0.01)
	check(low > top + 0.02, "alt lig kaleci cezası üst ligden belirgin büyük değil (%.4f / %.4f)" % [low, top])
	# kısa canlı örnek
	var fx: Array = Game.s.fixtures.get("L2A", [])
	check(not fx.is_empty(), "L2A fikstürü yok")
	if fx.is_empty():
		return
	for i: int in 3:
		var fm: Dictionary = fx[0][i]
		Game.ensure_squad(fm.h)
		Game.ensure_squad(fm.a)
		var sc: Array = []
		var xh: Array = Game.best_xi(fm.h, true)
		var xa: Array = Game.best_xi(fm.a, true)
		for rep: int in 2:
			var m: Dictionary = {"h": fm.h, "a": fm.a, "day": "sat", "gh": -1, "ga": -1, "ev": []}
			m.xi_h = xh.duplicate()
			m.xi_a = xa.duplicate()
			var eng = LiveEngine.new()
			eng.setup(Game, m, false, 9100 + i)
			eng.run_to_end()
			check(eng.goal_events().size() == eng.score[0] + eng.score[1], "gol olayı ≠ skor")
			sc.append("%d-%d" % [eng.score[0], eng.score[1]])
		check(sc[0] == sc[1], "canlı motor deterministik değil: %s" % str(sc))
		log_info("L2A örnek %d: %s" % [i, sc[0]])

func _mean_pen(lgs: Array) -> float:
	var tot: float = 0.0
	var n: int = 0
	for lg: String in lgs:
		if not Game.s.fixtures.has(lg):
			continue
		for fm: Dictionary in Game.s.fixtures[lg][0]:
			for cid: String in [fm.h, fm.a]:
				Game.ensure_squad(cid)
				for pid: String in Game.best_xi(cid, false):
					var p: Dictionary = Game.player(pid)
					if p.pos == "GK":
						tot += LiveEngine.gk_abs_pen(float(p.attrs.reflexes), float(p.attrs.handling))
						n += 1
	return tot / maxf(1.0, float(n))
