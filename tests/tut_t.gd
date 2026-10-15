extends Node
var main
var n := 0
func shot(name: String, frames := 14) -> void:
	for i in frames:
		await get_tree().process_frame
	main._coach_tick(1.0)
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/tut/%02d_%s.png" % [n, name])
	n += 1
	print("shot ", name, " step=", Game.tut_step(), " target=", main.coach.target.get_meta("tut", main.coach.target.get_meta("tab", "?")) if main.coach and main.coach.target else "-")
func press(k: String) -> void:
	var f: Dictionary = main._coach_find()
	if f.has(k):
		(f[k] as Button).pressed.emit()
	else:
		print("YOK ", k)
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("/home/claude/tut")
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.new_game("Atakan Koç", "tr")
	Game.take_job(Game.job_offers_start()[1])
	Game.finish_week()
	Game.s.events = []
	main._goto_tab("home")
	for i in 30: await get_tree().process_frame
	main._choice_done.emit(true)
	for i in 6:
		await shot("intro%d" % i)
		main._coach_tapped()
	await shot("week_nav")
	press("nav_week")
	await shot("pick")
	var im1 := get_viewport().get_texture().get_image()
	main.coach.visible = false
	main.coach.set_process(false)
	for i in 3: await get_tree().process_frame
	var im2 := get_viewport().get_texture().get_image()
	main.coach.set_process(true)
	main.coach.visible = true
	print("PIX with=", im1.get_pixel(360, 300), " without=", im2.get_pixel(360, 300), " top with=", im1.get_pixel(100,100), " without=", im2.get_pixel(100,100))
	print("COACH ", main.coach.size, " ", main.coach.get_global_rect(), " hole=", main.coach.hole, " idx=", main.coach.get_index(), "/", main.get_child_count(), " vis=", main.coach.is_visible_in_tree(), " mod=", main.coach.modulate)
	press("pick_match")
	await shot("ticket")
	press("ticket")
	await shot("go_match")
	press("go_match")
	await shot("focus")
	press("focus_btn")
	await shot("weekend")
	Game.tut_event("watched")
	main._goto_tab("home")
	await shot("players_nav")
	press("nav_players")
	await shot("player_row")
	var f: Dictionary = main._coach_find()
	if f.has("player_row"):
		f.player_row.pressed.emit()
	await shot("report")
	Game.tut_event("report")
	main._goto_tab("home")
	await shot("done")
	main._coach_tapped()
	await shot("after")
	print("TUT DONE on=", Game.tut_on())
	get_tree().quit()
