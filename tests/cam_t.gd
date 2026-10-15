extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size = Vector2(1459, 720)
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	var st = load("res://three/stadium.gd").new()
	sv.add_child(st)
	st.configure(2, "dusk", "clear")
	st.build(Color("#c8102e"), Color("#ffffff"), Color("#1d428a"), true, true)
	var cam := Camera3D.new()
	sv.add_child(cam)
	var args := OS.get_cmdline_user_args()
	for v in [["old", 24.5, 1.0], ["new", 27.0, -3.0], ["far", 27.0, -19.0]]:
		cam.fov = v[1]
		cam.position = Vector3(0, 21, 47)
		cam.look_at(Vector3(0, 0, v[2]))
		for i in 10: await get_tree().process_frame
		var img := sv.get_texture().get_image()
		img.save_png("/home/claude/cam_%s.png" % v[0])
	get_tree().quit()
