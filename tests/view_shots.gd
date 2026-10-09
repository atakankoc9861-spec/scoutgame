extends Node

var out := "/home/claude/shots3d/"

func shot(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.finish_week()
	var ms = Game.week_matches()
	var key = Game.match_key(ms[0].lg, ms[0].idx)
	Game.play_day(ms[0].m.day)
	var data = Game.watch_match_data(key)
	var fh = load("res://fonts/BarlowCondensed-Bold.ttf")
	var fb = load("res://fonts/Barlow-Medium.ttf")
	var host = Control.new()
	host.size = Vector2(720, 1280)
	add_child(host)
	var mv = load("res://three/match_view.gd").new()
	mv.setup(data, fh, fb, [data.m.xi_h[6], data.m.xi_a[9]])
	host.add_child(mv)
	await shot("v0_intro")
	for i in 100:
		await get_tree().process_frame
	await shot("v0b_intro")
	mv._end_intro()
	await shot("v1_start")
	mv.speed = 4.0
	for i in 120:
		await get_tree().process_frame
	await shot("v2_play")
	mv.cam_mode = "wide"
	for i in 60:
		await get_tree().process_frame
	await shot("v3_wide")
	mv.cam_mode = "close"
	for i in 60:
		await get_tree().process_frame
	await shot("v4_close")
	mv._open_list()
	await shot("v5_list")
	mv.list_panel.visible = false
	mv._skip_to_end()
	await shot("v6_end")
	get_tree().quit()
