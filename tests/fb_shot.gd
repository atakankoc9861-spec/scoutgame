extends Node3D
const FB = preload("res://three/human.gd")
const Stadium = preload("res://three/stadium.gd")
func _ready() -> void:
	var st = Stadium.new()
	add_child(st)
	st.build(Color("#d4a017"), Color("#14213d"), Color("#b5121b"))
	var kit = FB.kit_mats(Color("#b5121b"), Color("#f2f2f2"), Color("#b5121b"))
	var kit2 = FB.kit_mats(Color("#d4a017"), Color("#14213d"), Color("#14213d"))
	var poses = [["", 0.0], ["", 7.0], ["kick", 0.0], ["header", 0.0], ["dive", 0.0], ["celebrate", 0.0], ["slide", 0.0], ["knee_slide", 0.0]]
	var font = load("res://fonts/BarlowCondensed-Bold.ttf")
	var men = []
	for i in poses.size():
		var f = FB.new()
		add_child(f)
		f.build(kit if i % 2 == 0 else kit2, i % 5, i % 6, i, 7 + i, font)
		f.position = Vector3(-7 + i * 2.0, 0, 0)
		f.rotation.y = 0.6 if i != 1 else -0.9
		men.append([f, poses[i]])
	for m in men:
		var f = m[0]
		var p = m[1]
		if p[0] != "":
			f.play(p[0], 1.0, 1.0)
			f.action_t = {"kick": 0.62, "header": 0.5, "dive": 0.5, "celebrate": 0.3, "slide": 0.5, "knee_slide": 0.5}[p[0]]
		f.speed = p[1]
		f.phase = 1.2
		f.apply_pose()
	var cam = Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 2.6, 9)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.fov = 60
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/fb.png")
	cam.position = Vector3(-20, 14, 30)
	cam.look_at(Vector3(10, 2, 0))
	st.goal_fx(1.0, true)
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/fb2.png")
	cam.position = Vector3(0, 60, 95)
	cam.look_at(Vector3(0, 0, 0))
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/fb3.png")
	get_tree().quit()
