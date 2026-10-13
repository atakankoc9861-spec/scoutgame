extends Node
func m(tag):
	print("MEM ", tag, " ram=", int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6), "MB vmem=", int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6), "MB tex=", int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6), "MB")
func _ready() -> void:
	Game.delete_save()
	if FileAccess.file_exists(Game.CRASH_FLAG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.CRASH_FLAG))
	m("start")
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	m("title")
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	m("newgame")
	main._goto_tab("home")
	for i in 30: await get_tree().process_frame
	m("home")
	for t in ["week", "players", "tasks", "team", "news"]:
		main._goto_tab(t)
		for i in 20: await get_tree().process_frame
	m("tabs")
	get_tree().quit()
