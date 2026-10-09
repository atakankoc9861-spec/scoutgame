extends Node
## Mocap klip kontak sayfası: her klip için 6 kare, yandan ve önden
const MM = preload("res://three/mocap_man.gd")
var vp: SubViewport
var cam: Camera3D
var man
var out := "/home/claude/mocap/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	vp = SubViewport.new()
	vp.size = Vector2i(220, 300)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var w := Node3D.new()
	vp.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.75, 0.8, 0.85)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	w.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(10, 10)
	fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.3, 0.55, 0.3)
	fl.material_override = fm
	w.add_child(fl)
	cam = Camera3D.new()
	cam.fov = 40
	w.add_child(cam)
	man = MM.new()
	w.add_child(man)
	man.build(MM.kit_mats(Color("#c8102e"), Color("#ffffff"), Color("#c8102e")), 1, 0, 0, 9)
	await get_tree().process_frame
	var clips := ["idle", "walk", "jog", "sprint", "pass", "shot", "shot_r2", "header", "tackle", "slide", "dive", "dive_m", "save_low", "celebrate", "celebrate2", "knee_slide", "throw", "jockey", "dribble", "juggle", "talk", "crouch", "fall", "card"]
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		clips = args
	if "face" in clips:
		man.base = "idle"
		man.idle_t = 0.0
		man._apply("idle", "walk", 0.0)
		cam.fov = 20
		var ims := []
		for pos in [Vector3(0, 1.68, 1.2), Vector3(0.8, 1.68, 0.9), Vector3(1.2, 1.68, 0.0)]:
			cam.position = pos
			cam.look_at(Vector3(0, 1.66, 0))
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			ims.append(vp.get_texture().get_image())
		var sh := Image.create(660, 300, false, Image.FORMAT_RGBA8)
		for i in 3:
			ims[i].convert(Image.FORMAT_RGBA8)
			sh.blit_rect(ims[i], Rect2i(0, 0, 220, 300), Vector2i(i * 220, 0))
		sh.save_png(out + "face.png")
		get_tree().quit()
		return
	for c in clips:
		var imgs := []
		for view in [0, 1]:
			for k in 6:
				var C: Dictionary = MM.CL[c]
				var t: float = C.len * k / 5.0
				man.action = ""
				man.base = c
				man.idle_t = t
				man._apply("idle", "walk", 0.0)
				if view == 0:
					cam.position = Vector3(3.6, 1.0, 0.3)
				else:
					cam.position = Vector3(0.0, 1.0, 3.8)
				cam.look_at(Vector3(0, 0.85, 0))
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				imgs.append(vp.get_texture().get_image())
		var sheet := Image.create(220 * 6, 600, false, Image.FORMAT_RGBA8)
		for i in imgs.size():
			var im: Image = imgs[i]
			im.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(im, Rect2i(0, 0, 220, 300), Vector2i((i % 6) * 220, (i / 6) * 300))
		sheet.save_png(out + c + ".png")
		print("sheet ", c)
	get_tree().quit()
