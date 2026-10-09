extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	print("budget ", Game.s.scout.budget, " rep ", Game.s.scout.rep)
	var t0 := Time.get_ticks_msec()
	for season in 2:
		var guard := 0
		var s0: int = Game.s.season
		while Game.s.season == s0 and guard < 60:
			Game.end_week_auto()
			guard += 1
		var sm: Dictionary = Game.s.season_summary
		var mins := {}
		for cid in Game.s.clubs:
			var c = Game.s.clubs[cid]
			var t := Game.tier(c.league)
			mins[t] = mini(int(mins.get(t, 99)), c.squad.size())
		print("season end ", s0, " weeks ", guard, " rep ", snappedf(Game.s.scout.rep, 0.1), " fired ", sm.get("fired", false), " offers ", Game.s.offers.size(), " min squads ", mins, " money ", Game.s.scout.money)
		if sm.get("fired", false) and not Game.s.offers.is_empty():
			Game.take_job(Game.s.offers[0])
	print("ms ", Time.get_ticks_msec() - t0)
	get_tree().quit()
