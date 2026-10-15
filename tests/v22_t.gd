extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	print("legends=", Game.s.legends.size())
	for lg in Game.s.legends:
		var p := Game.player(lg.pid)
		print("  ", Game.pname(p), " ", p.pos, " ", p.age, " pa=", p.pa, " ", Game.club(p.club).get("name"), " ", Game.club_country(p.club), " t", Game.club_tier(p.club))
	var rum := 0
	for w in 20:
		Game.s.events = []
		Game.finish_week()
		for e in Game.s.events:
			if e.kind == "rumor":
				rum += 1
				print("RUMOR w", Game.s.week, ": ", T.t(e.clue[0], e.clue[1]))
	print("rumors=", rum, " life=", Game.s.life.rel, " money=", Game.s.scout.money)
	Game.s.scout.money = 50000
	print("buy home ", Game.life_buy("home"), " car ", Game.life_buy("car"), " suit ", Game.life_buy("suit"))
	var lg0: Dictionary = Game.s.legends[0]
	Game.observe(lg0.pid, 0.2, ["tec"], 1.0)
	print("found? ", lg0.state, " pop=", Game.s.legend_pop)
	print("streak ", Game.eye_streak(true), Game.eye_streak(true), Game.eye_streak(false))
	print("kids feed ", Game.s.kids_feed.size())
	print("V22 DONE")
	get_tree().quit()
