extends Node
func _ready() -> void:
	Game.settings["quality"] = "high"
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.finish_week()
	var ms = Game.week_matches()
	var key = Game.match_key(ms[0].lg, ms[0].idx)
	Game.play_day(ms[0].m.day)
	var data = Game.watch_match_data(key)
	var host = Control.new()
	host.size = Vector2(1459, 720)
	add_child(host)
	var mv = load("res://three/match_view.gd").new()
	mv.setup(data, load("res://fonts/BarlowCondensed-Bold.ttf"), load("res://fonts/Barlow-Medium.ttf"), [data.m.xi_h[5]])
	host.add_child(mv)
	var t0 := Time.get_ticks_msec()
	for i in 400:
		await get_tree().process_frame
		if i % 40 == 0:
			print("f", i, " ", mv.mode, " ", Watch._mon())
		if i == 120:
			mv._end_intro()
	get_tree().quit()
