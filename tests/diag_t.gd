extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size = Vector2(720, 400)
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	var st = load("res://three/stadium.gd").new()
	sv.add_child(st)
	st.configure(3, "dusk", "clear")
	st.build(Color("#c8102e"), Color("#ffffff"), Color("#1d428a"), true, true)
	var cam := Camera3D.new()
	cam.fov = 40
	sv.add_child(cam)
	cam.position = Vector3(0, 30, 39)
	cam.look_at(Vector3(0, 0, 4))
	for i in 10:
		await get_tree().process_frame
	await Watch.diagnose(sv, "t", false)
	print("\n".join(Watch.diag_lines))
	print("DIAG DONE")
	get_tree().quit()
