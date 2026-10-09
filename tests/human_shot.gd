extends Node3D
const H = preload("res://three/human.gd")
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.3, 0.35)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.68)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40)
	g.mesh = pm
	g.material_override = H.make_mat(Color(0.15, 0.4, 0.15))
	add_child(g)
	var kit = H.kit_mats(Color("#b5121b"), Color("#f2f2f2"), Color("#b5121b"))
	var kit2 = H.kit_mats(Color("#d4a017"), Color("#14213d"), Color("#14213d"))
	var poses = [["", 0.0], ["", 7.0], ["kick", 0.62], ["header", 0.5], ["slide", 0.5], ["celebrate", 0.3], ["tackle", 0.5], ["dive", 0.5]]
	var font = load("res://fonts/BarlowCondensed-Bold.ttf")
	for i in poses.size():
		var f = H.new()
		add_child(f)
		f.build(kit if i % 2 == 0 else kit2, i % 5, i % 6, i, 7 + i, font)
		f.position = Vector3(-4.2 + (i % 4) * 2.8, 0, -float(i / 4) * 3.0)
		f.rotation.y = 0.5 if i != 1 else -1.2
		var p = poses[i]
		if p[0] != "":
			f.play(p[0], 1.0, 1.0)
			f.action_t = p[1]
		else:
			f.speed = p[1]
		f.phase = 1.2
		f.apply_pose()
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2.2, 6.5)
	cam.look_at(Vector3(0, 0.9, -1.5))
	cam.fov = 55
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/hum.png")
	cam.position = Vector3(-4.2+0.3, 1.65, 1.2)
	cam.look_at(Vector3(-4.2, 1.6, 0))
	cam.fov = 40
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/hum2.png")
	get_tree().quit()
