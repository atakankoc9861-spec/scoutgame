extends Node
func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	Game.new_game("T", "tr")
	print("players ", Game.s.players.size(), " clubs ", Game.s.clubs.size(), " ms ", Time.get_ticks_msec() - t0)
	for lg in ["EN1", "IT1", "BR1", "SL", "BAL1"]:
		var c0 = Game.league_clubs(lg)[0]
		print(lg, " ", Game.club(c0).name, " avg ", snappedf(Game.club_avg_ovr(c0), 0.1), " rounds ", Game.league_round_count(lg), " mgr ", Game.club(c0).manager.name)
	Game.take_job(Game.job_offers_start()[0])
	Game.refresh_staff_pool(true)
	Game.s.scout.rep = 60.0
	for i in 3:
		print(Game.hire_staff(Game.s.staff_pool[0].id))
	var rgs = ["en", "br", "tr_low"]
	for i in Game.s.staff.size():
		Game.assign_staff(Game.s.staff[i].id, rgs[i % 3])
	# yurtdışı maç planla
	Game.finish_week()
	var ms = Game.week_matches(["EN1"])
	var key = Game.match_key(ms[0].lg, ms[0].idx)
	print("abroad ", Game.match_abroad(key), " plan ", Game.plan_match(ms[0].m.day, key), " cal ", Game.s.cal, " travel ", Game.travel_info(Game.club(ms[0].m.h).city))
	for w in 6:
		t0 = Time.get_ticks_msec()
		Game.end_week_auto()
		print("week ", Game.s.week, " ms ", Time.get_ticks_msec() - t0, " staff reports ", Game.s.staff_reports.size(), " spent ", Game.s.scout.spent)
	var sz = FileAccess.get_file_as_bytes(Game.SAVE_PATH).size()
	print("save size ", sz, " load ", Game.load_game(), " players ", Game.s.players.size(), " attr type ", typeof(Game.player(Game.s.players.keys()[0]).attrs))
	for n in Game.s.news.slice(0, 8):
		print(T.t(n.key, n.args))
	get_tree().quit()
