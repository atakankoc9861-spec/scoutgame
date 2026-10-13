extends Node
func _ready() -> void:
	var out := "/home/claude/officeshots/"
	DirAccess.make_dir_recursive_absolute(out)
	Game.new_game("T", "tr")
	var hub = load("res://three/hub3d.gd").new()
	add_child(hub)
	await get_tree().process_frame
	var lvs := [0, 1, 2]
	if OS.get_cmdline_user_args().size() > 0:
		lvs = [int(OS.get_cmdline_user_args()[0])]
	for lv in lvs:
		hub.set_office_level(lv)
		hub.set_trophies(5)
		hub.set_board([{"name": "A. Yılmaz", "c1": "#c8102e", "c2": "#fff", "stars": "★★★"}, {"name": "B. Kaya", "c1": "#1d428a", "c2": "#fff", "stars": "★★"}, {"name": "C. Demir", "c1": "#f2c500", "c2": "#000", "stars": "★★★★"}, {"name": "D. Öz", "c1": "#006a44", "c2": "#fff", "stars": "★★"}])
		for st in ["office", "desk", "board"]:
			hub.goto(st, true)
			for i in 20:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out + "%d_%s.png" % [lv, st])
	print("OFFICE DONE")
	get_tree().quit()
