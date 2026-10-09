extends Node
var out := "/home/claude/goalshots/"
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
	var data = {}
	for tries in 30:
		var ms = Game.week_matches()
		var mm = ms[tries % ms.size()]
		Game.play_day(mm.m.day)
		if int(mm.m.gh) + int(mm.m.ga) > 0:
			data = Game.watch_match_data(Game.match_key(mm.lg, mm.idx))
			break
	var host = Control.new()
	host.size = Vector2(720, 1280)
	add_child(host)
	var mv = load("res://three/match_view.gd").new()
	mv.setup(data, load("res://fonts/BarlowCondensed-Bold.ttf"), load("res://fonts/Barlow-Medium.ttf"), [])
	host.add_child(mv)
	await shot("g0_intro", 30)
	mv._end_intro()
	var gi = 0
	for i in data.tl.size():
		if data.tl[i].ty == "goal":
			gi = i
			break
	mv._enter_event(max(0, gi - 6))
	mv.speed = 1.0
	await shot("g1_buildup", 40)
	while mv.idx < gi:
		await get_tree().process_frame
	await shot("g2_goal", 25)
	await shot("g3_celebrate", 60)
	while mv.mode != "replay":
		await get_tree().process_frame
	await shot("g4_replay", 50)
	get_tree().quit()
