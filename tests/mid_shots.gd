extends Node
var out := "/home/claude/midshots/"
func shot(name: String, frames := 4) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.finish_week()
	var ms = Game.week_matches()
	Game.play_day(ms[0].m.day)
	var data = Game.watch_match_data(Game.match_key(ms[0].lg, ms[0].idx))
	var host = Control.new()
	host.size = Vector2(720, 1280)
	add_child(host)
	var mv = load("res://three/match_view.gd").new()
	mv.setup(data, load("res://fonts/BarlowCondensed-Bold.ttf"), load("res://fonts/Barlow-Medium.ttf"), [])
	host.add_child(mv)
	await shot("m0", 10)
	mv._end_intro()
	await shot("m1_kickoff", 20)
	mv._set_cam("wide")
	await shot("m2_wide", 40)
	mv._set_cam("tv")
	mv._enter_event(200)
	await shot("m3_tv", 50)
	mv.cam.position = Vector3(0, 30, 40)
	mv.cam_mode = "none"
	mv.set_process(false)
	mv.cam.look_at(Vector3(0, 0, 0))
	await shot("m4_overview", 6)
	get_tree().quit()
