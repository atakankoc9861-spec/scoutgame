extends Node
func _ready() -> void:
	Game.delete_save()
	if FileAccess.file_exists(Game.CRASH_FLAG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.CRASH_FLAG))
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	main._goto_tab("home")
	for i in 30: await get_tree().process_frame
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	Watch._notification(NOTIFICATION_APPLICATION_PAUSED)
	for i in 10: await get_tree().process_frame
	Watch._notification(NOTIFICATION_APPLICATION_RESUMED)
	main._notification(NOTIFICATION_APPLICATION_RESUMED)
	for i in 30: await get_tree().process_frame
	print(FileAccess.get_file_as_string("user://watch_bc.txt").split("\n").slice(-6))
	print("BG DONE upd=", main.hub.sv.render_target_update_mode)
	get_tree().quit()
