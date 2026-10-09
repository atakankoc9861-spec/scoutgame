extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	var ids: Array = Game.s.players.keys()
	ids.shuffle()
	var n := 0
	for pid in ids:
		var p = Game.player(pid)
		if p.club == "" or p.club == Game.s.scout.club_id or p.youth:
			continue
		if Data.POS_GROUP[p.pos] != "GK" and n % 3 != 0:
			pass
		var acc := n < 9
		var cur: float = Game.stars(float(p.ovr)) if acc else 5.0
		var pot: float = Game.stars(float(p.pa)) if acc else 5.0
		Game.submit_report(pid, "", cur, pot, "watch", [])
		n += 1
		if n >= 14: break
	for i in 4:
		Game.area_gain("TR1", 5.0)
	var sh_p = ""
	for pid in Game.s.players:
		var pp = Game.player(pid)
		if pp.club != "" and pp.club != Game.s.scout.club_id and pp.pos == "CB":
			sh_p = pid; break
	print("shadow add ", Game.shadow_add(sh_p, "CB"), Game.shadow_of("CB"))
	var guard := 0
	var s0: int = Game.s.season
	while Game.s.season == s0 and guard < 60:
		Game.end_week_auto(); guard += 1
	var whys := []
	for nn in Game.s.news:
		if str(nn.key).begins_with("n_req"): whys.append(nn.key)
	print("req news ", whys)
	print("acc ", Game.s.scout.acc, " spec ", Game.s.scout.spec, " badges ", Game.scout_badges(), " arep ", Game.s.scout.arep, " rel ", Game.reliability())
	for k in 2:
		if Game.s.season_summary.get("fired", false) and not Game.s.offers.is_empty():
			Game.take_job(Game.s.offers[0])
		var s1: int = Game.s.season
		var g2 := 0
		while Game.s.season == s1 and g2 < 60:
			Game.end_week_auto(); g2 += 1
	print("disc ", Game.s.scout.disc_log.size(), " museum ", Game.s.museum)
	for nn in Game.s.news.slice(0, 40):
		if str(nn).find("n_badge") >= 0: print(nn)
	get_tree().quit()
