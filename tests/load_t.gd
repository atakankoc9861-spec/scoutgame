extends Node
var main
func _ready() -> void:
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 20: await get_tree().process_frame
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.finish_week()
	main._goto_tab("home")
	for i in 10: await get_tree().process_frame
	var ms = Game.week_matches()
	var key = Game.match_key(ms[0].lg, ms[0].idx)
	Game.play_day(ms[0].m.day)
	var data = Game.watch_match_data(key)
	main._run_viewer(data, [])
	for i in 20: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots15/10_loading.png")
	print("loading shot ", Watch._mon())
	for i in 120: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shots15/11_after.png")
	print("after ", Watch._mon(), " hold ", main.viewer.hold)
	get_tree().quit()
