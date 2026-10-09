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
	host.size = Vector2(1280, 720)
	add_child(host)
	var mv = load("res://three/match_view.gd").new()
	mv.setup(data, load("res://fonts/BarlowCondensed-Bold.ttf"), load("res://fonts/Barlow-Medium.ttf"), [data.m.xi_h[6]])
	host.add_child(mv)
	for i in 60: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots15/c0_intro.png")
	mv._end_intro()
	mv.cam_mode = "player"
	for i in 200: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots15/c1_player.png")
	mv.cam_mode = "tv"
	for i in 60: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots15/c2_tv.png")
	print("ok ", Watch._mon(), " fps ", Engine.get_frames_per_second())
	get_tree().quit()
