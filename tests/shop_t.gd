extends Node
func shot(n):
	for i in 30: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/shop_%s.png" % n)
func _ready() -> void:
	Game.delete_save()
	if FileAccess.file_exists(Game.CRASH_FLAG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.CRASH_FLAG))
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await shot("0")
	main._shop()
	await shot("1")
	main._choice_done.emit("close")
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.tut_skip()
	Game.s.events = []
	Game.finish_week()
	Game.s.events = []
	Game.s.scout.fatigue = 60
	for i in 5: Game._take_day("rest", "")
	main._goto_tab("week")
	await shot("2")
	main._rewarded("day")
	await shot("3")
	print("SHOP DONE free=", Game.free_days())
	get_tree().quit()
