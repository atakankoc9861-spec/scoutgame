extends Node
func _ready() -> void:
	Game.delete_save()
	if FileAccess.file_exists(Game.CRASH_FLAG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.CRASH_FLAG))
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.tut_skip()
	var sl = Game.search({"lg": Game.my_club().league})
	main._goto_tab("players")
	main._show("report", sl[0])
	for i in 40: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/rep21.png")
	print("REP OK fee=", Game.est_fee(sl[0]))
	get_tree().quit()
