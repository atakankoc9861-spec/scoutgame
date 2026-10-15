extends Node
var main
func shot(n: String, frames := 25) -> void:
	for i in frames: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/v22ui/%s.png" % n)
	print("shot ", n)
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("/home/claude/v22ui")
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.new_game("Atakan Koç", "tr")
	Game.take_job(Game.job_offers_start()[1])
	Game.tut_skip()
	Game.s["story_seen"] = {"first_job": true, "promoted": true, "first_headline": true, "first_signing": true}
	for w in 8:
		Game.s.events = []
		Game.finish_week()
	Game.s.events = []
	var lg: Dictionary = Game.s.legends[0]
	main._goto_tab("home")
	await shot("home")
	main._ev_rumor({"kind": "rumor", "clue": Game.legend_clue_text(Game.s.legends.filter(func(l): return int(l.clues) > 0)[0])[-1]})
	await shot("rumor")
	main._choice_done.emit("ok")
	await get_tree().process_frame
	Game.observe(lg.pid, 0.2, ["tec"], 1.0)
	main._legend_celebrate(Game.s.legend_pop.pop_front())
	await shot("celebrate", 50)
	main._choice_done.emit("close")
	# evlat akışı örneği
	var some := []
	for pid in Game.s.players:
		if Game.s.players[pid].club != "" and some.size() < 3:
			some.append(pid)
	Game._kid_feed(some[0], "kf_debut", [Game.pname(Game.player(some[0])), "Kartal FK"])
	Game._kid_feed(some[1], "kf_thanks", [Game.pname(Game.player(some[1]))])
	Game._kid_feed(some[2], "kf_first_goal", [Game.pname(Game.player(some[2]))])
	main.sub.home = "archive"
	main._goto_tab("home")
	await shot("archive")
	main.scroll.scroll_vertical = 700
	await shot("archive2")
	main.sub.home = "career"
	Game.s.scout.money = 8000
	main._goto_tab("home")
	await shot("career")
	main._ev_life({"kind": "life", "type": "family"})
	await shot("life_ev")
	main._choice_done.emit(true)
	await shot("life_ev2")
	main._choice_done.emit(true)
	print("V22UI DONE")
	get_tree().quit()
