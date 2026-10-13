extends Node
## v0.21 oynanış sistemleri: olaylar, manşetler, keşif 11'i, turnuva, son gün
func _ready() -> void:
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	var sl = Game.search({"lg": Game.my_club().league})
	for i in 5:
		Game.toggle_shortlist(sl[i])
		Game.log_discovery(sl[i], "match")
	var seen := {}
	var hl := 0
	for w in 40:
		Game.end_week_auto()
		for e in Game.s.events.duplicate():
			seen[e.kind] = int(seen.get(e.kind, 0)) + 1
			match e.kind:
				"deadline":
					for c in e.calls:
						var r = Game.resolve_deadline_call(c, randf() < 0.6)
						print("DL ", c.type, " -> ", r.key)
					Game.s.events.erase(e)
				"tournament":
					var ms = Game.tournament_accept(e.cc)
					var all := []
					var picked := []
					for m in ms:
						all += m.kids
						picked.append(m.kids[0])
						Game.tournament_pick(m.kids[0])
					Game.tournament_cleanup(all, picked)
					print("TOURN ", e.cc, " matches ", ms.size(), " picked ", picked.size())
					Game.s.events.erase(e)
				"dilemma":
					var r2 = Game.resolve_dilemma(e, randf() < 0.5)
					print("DIL ", e.type, " -> ", r2.key)
		while not Game.pop_headline().is_empty():
			hl += 1
	print("EVENTS ", seen, " headlines ", hl, " hl_log ", Game.s.hl_log.size(), " integrity ", Game.s.scout.integrity)
	var xi = Game.finds_xi()
	var filled := 0
	for x in xi:
		if x.pid != "":
			filled += 1
	print("XI filled ", filled, "/11 value ", Game.money_str(Game.finds_value()), " title ", Game.title_key(), " perk1a ", Game.has_perk("perk_1a"))
	print("V21 DONE")
	get_tree().quit()
