extends Node
## Stadyum varyasyonları: her seviye/zaman/hava için ekran görüntüsü
var out := "/home/claude/stadshots/"
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.new_game("T", "tr")
	var combos := [[0, "night", "clear"], [0, "day", "clear"], [1, "dusk", "rain"], [2, "day", "clear"], [2, "night", "snow"], [3, "day", "clear"]]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		combos = [combos[int(args[0])]]
	for c in combos:
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.size = Vector2(720, 1280)
		add_child(svc)
		var sv := SubViewport.new()
		sv.own_world_3d = true
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		svc.add_child(sv)
		var st = load("res://three/stadium.gd").new()
		sv.add_child(st)
		st.configure(c[0], c[1], c[2])
		st.build(Color("#c8102e"), Color("#ffffff"), Color("#1d428a"), true, true)
		st.set_fill(0.85)
		st.set_board("IST  1 - 0  ANK", "İSTANBUL SPOR")
		var pm := Post.make(st.post_preset())
		Post.weather(pm, c[2])
		svc.material = pm
		var cam := Camera3D.new()
		cam.fov = 40
		cam.far = 900
		sv.add_child(cam)
		var tag := "%d_%s_%s" % c
		for v in [["tv", Vector3(0, 30, 39), Vector3(0, 0, 4), 28.0], ["wide", Vector3(-26, 30, 39), Vector3(-34, 0, -2), 40.0], ["low", Vector3(25, 6.5, 39), Vector3(35, 0.6, 0), 40.0], ["orbit", Vector3(95, 42, 95), Vector3(0, 0, 0), 50.0], ["board", Vector3(0, 1.4, 31.5), Vector3(12, 0.6, 37.2), 50.0]]:
			cam.fov = v[3]
			cam.position = v[1]
			cam.look_at(v[2])
			for i in 8:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out + tag + "_" + v[0] + ".png")
		svc.queue_free()
		await get_tree().process_frame
	print("STAD DONE")
	get_tree().quit()
