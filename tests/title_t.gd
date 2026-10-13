extends Node
func _ready() -> void:
	Game.delete_save()
	if FileAccess.file_exists(Game.CRASH_FLAG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.CRASH_FLAG))
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/title.png")
	print("TITLE OK vid=", main.title_vid != null, " playing=", main.title_vid.is_playing() if main.title_vid else false)
	get_tree().quit()
