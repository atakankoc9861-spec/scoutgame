extends Node
const MM = preload("res://three/mocap_man.gd")
func _ready() -> void:
	var vp := get_viewport()
	var w := Node3D.new(); add_child(w)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.28, 0.32)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	w.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-30, 25, 0); w.add_child(sun)
	var cam := Camera3D.new(); cam.fov = 22; w.add_child(cam)
	var man = MM.new(); w.add_child(man)
	man.build(MM.kit_mats(Color("#1d4ed8"), Color("#ffffff"), Color("#1d4ed8")), 1, 1, 7, 9)
	man.set_base("idle")
	print("fx ", man._fx.size(), " face ", man.face_on)
	for i in 5: await get_tree().process_frame
	var hp: Vector3 = man.skel.global_transform * man.skel.get_bone_global_pose(man.skel.find_bone("head")).origin
	cam.position = hp + Vector3(0, -0.02, 0.95)
	cam.look_at(hp + Vector3(0, -0.02, 0))
	var out := []
	for e in ["neutral", "happy", "sad", "angry", "surprised", "worried"]:
		man.emote(e)
		man._blink_t = 99.0
		for i in 40: await fr(man)
		out.append(vp.get_texture().get_image())
	man.emote("neutral")
	man.talk(3.0)
	for k in 3:
		for i in 7: await fr(man)
		out.append(vp.get_texture().get_image())
	man.stop_talk()
	man.look_target = hp + Vector3(1.0, 0.1, 0.6)
	for i in 30: await fr(man)
	out.append(vp.get_texture().get_image())
	man.look_target = hp + Vector3(-1.0, 0.0, 0.6)
	for i in 30: await fr(man)
	out.append(vp.get_texture().get_image())
	man._blink_t = 0.0
	for i in 4: await fr(man)
	out.append(vp.get_texture().get_image())
	var W := 300
	var sheet := Image.create(W * 4, W * 3, false, Image.FORMAT_RGBA8)
	for i in out.size():
		var im: Image = out[i]
		im.convert(Image.FORMAT_RGBA8)
		var s := im.get_size()
		var c := im.get_region(Rect2i(s.x / 2 - 150, s.y / 2 - 60, 300, 300))
		sheet.blit_rect(c, Rect2i(0, 0, 300, 300), Vector2i((i % 4) * W, (i / 4) * W))
	sheet.save_png("/home/claude/shots15/face_sheet.png")
	get_tree().quit()

func fr(man) -> void:
	man.tick(0.03, 0.0)
	await get_tree().process_frame
