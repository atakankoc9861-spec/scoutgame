extends Node
var out := "/home/claude/v4/"
var mv
func shot(name: String, frames := 4) -> void:
	for i in frames:
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
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cl = CanvasLayer.new()
	add_child(cl)
	cl.add_child(host)
	mv = load("res://three/match_view.gd").new()
	mv.setup(data, fh, fb, [data.m.xi_h[6], data.m.xi_a[9]])
	host.add_child(mv)
	await shot("a_intro", 60)
	mv._end_intro()
	await shot("b_kick", 20)
	var cams = ["tv", "wide", "stand", "goal", "player"]
	for c in cams:
		mv._set_cam(c)
		for i in 40:
			await get_tree().process_frame
		await shot("c_" + c)
	mv._set_cam("tv")
	for i in 30:
		await get_tree().process_frame
	await shot("d_tv2")
	print("events ", mv.eng.events.size(), " clock ", mv.eng.clock)
	# gole kadar hızlı ilerle
	mv.speed = 4.0
	for i in 6000:
		await get_tree().process_frame
		if mv.eng.celebrate_t > 5.0:
			break
	await shot("e_goal", 2)
	for i in 600:
		await get_tree().process_frame
		if mv.mode == "replay":
			break
	for i in 60:
		await get_tree().process_frame
	await shot("f_replay", 2)
	mv._open_list()
	await shot("g_list")
	mv.list_panel.visible = false
	mv.skip_now()
	await shot("h_end", 10)
	get_tree().quit()
