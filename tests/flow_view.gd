extends Node
var out := "/home/claude/flowshots/"
func shot(name: String, frames := 4) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.delete_save()
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.new_game("T", "tr")
	Game.s.offers = []
	Game.take_job(Game.job_offers_start()[0])
	main._goto_tab("home")
	await shot("f0_home", 30)
	Game.finish_week()
	main._watch_u19(0)
	await shot("f1_u19_intro", 20)
	main.viewer._end_intro()
	await shot("f2_u19_kickoff", 30)
	main.viewer._skip_to_end()
	main.viewer.finished.emit(main.viewer.focus_events)
	await shot("f3_obs", 40)
	main._goto_tab("home")
	await shot("f4_home_back", 30)
	get_tree().quit()
