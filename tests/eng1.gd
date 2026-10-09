extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	var c = Game.league_clubs("SL")
	var m = {"h": c[0], "a": c[1], "day": "sat", "gh": -1, "ga": -1, "ev": []}
	print("before setup")
	var eng = Game.LiveEngine.new()
	eng.setup(Game, m, false, 7)
	print("after setup")
	var t0 := Time.get_ticks_msec()
	for i in 3000:
		eng.step(0.2)
		eng.anims.clear()
		if i % 300 == 0:
			print(i, " clock ", int(eng.clock), " phase ", eng.phase, " owner ", eng.owner.id if eng.owner else "-", " flight ", eng.flight.get("k", "-"), " ev ", eng.events.size(), " score ", eng.score, " ball ", eng.ball, " ms ", Time.get_ticks_msec() - t0)
		if eng.finished:
			print("finished at ", i)
			break
	get_tree().quit()
