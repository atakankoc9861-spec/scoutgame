extends Node
## Tribün seyirci atlası: 8 poz × (2 tip × 4 kare), her hücre 64×96
const MM = preload("res://three/mocap_man.gd")
const POSES := ["cr_sit_clap", "cr_phone", "cr_clap", "cr_dance", "cr_clap_up", "cr_fist", "cr_sway", "cr_point"]
const CW := 64
const CH := 96
func _ready() -> void:
	var lib: AnimationLibrary = load("res://tests/data/crowd_anims.res")
	MM._load()
	for nm in lib.get_animation_list():
		var a: Animation = lib.get_animation(nm)
		var r := PackedInt32Array()
		for b in MM.BONES:
			r.append(a.find_track(NodePath("S:" + b), Animation.TYPE_ROTATION_3D))
		MM.CL[nm] = {"a": a, "r": r, "p": a.find_track(NodePath("S:pelvis"), Animation.TYPE_POSITION_3D), "len": a.length, "loop": true}
	var vp := SubViewport.new()
	vp.size = Vector2i(CW * 4, CH * 4)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var w := Node3D.new()
	vp.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_energy = 0.9
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.light_energy = 0.9
	w.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.7
	cam.position = Vector3(0, 1.4, 4)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	w.add_child(cam)
	var men := []
	for v in 2:
		var m = MM.new()
		w.add_child(m)
		if v == 0:
			m.build_outfit(Color(1, 1, 1), Color("#1d2235"), Color("#151515"), 1, 0, 1, false)
		else:
			m.build_outfit(Color(1, 1, 1), Color("#2a2a2a"), Color("#151515"), 3, 3, 2, true)
		men.append(m)
	var atlas := Image.create(CW * 8, CH * POSES.size(), false, Image.FORMAT_RGBA8)
	for pi in POSES.size():
		for v in 2:
			for m in men: m.visible = false
			var man = men[v]
			man.visible = true
			for f in 4:
				man.base = POSES[pi]
				man.idle_t = MM.CL[POSES[pi]].len * (f / 4.0) + v * 0.37
				man._apply("idle", "walk", 0.0)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img := vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				img.resize(CW, CH, Image.INTERPOLATE_LANCZOS)
				atlas.blit_rect(img, Rect2i(0, 0, CW, CH), Vector2i((v * 4 + f) * CW, pi * CH))
	atlas.save_png("res://assets/crowd/atlas.png")
	atlas.save_png("/tmp/claude-0/atlas.png")
	print("atlas ok")
	get_tree().quit()
