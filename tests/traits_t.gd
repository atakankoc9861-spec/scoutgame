extends Node3D
## Tech-art Faz 2 görsel kontrol: 6 profil yan yana (kısa-çevik kanat, uzun stoper, kilolu forvet,
## 17 yaş, 34 yaş, 88. dk yorgun düşük kondisyon), tam model.
## xvfb-run -s "-screen 0 1280x720x24" $GODOT --rendering-driver opengl3 --path . res://tests/traits_t.tscn
## Ortam: TRAITS=0 bayrak kapalı (önce), PROBE_OUT=klasör, PROBE_TAG=etiket.

const FB = preload("res://three/mocap_man.gd")

const PROFILES := [
	["kısa kanat", {"seed": 41, "pos": "LW", "age": 21, "skin": 1, "hair": 0, "foot": "L", "attrs": {"strength": 6, "pace": 18, "agility": 18, "stamina": 14}}],
	["stoper", {"seed": 12, "pos": "CB", "age": 27, "skin": 3, "hair": 3, "foot": "R", "attrs": {"strength": 18, "pace": 9, "agility": 7, "stamina": 13}}],
	["kilolu ST", {"seed": 77, "pos": "ST", "age": 29, "skin": 0, "hair": 1, "foot": "R", "attrs": {"strength": 17, "pace": 6, "agility": 8, "stamina": 8}}],
	["17 yaş", {"seed": 33, "pos": "CM", "age": 17, "skin": 1, "hair": 2, "foot": "R", "attrs": {"strength": 7, "pace": 12, "agility": 13, "stamina": 12}}],
	["34 yaş", {"seed": 58, "pos": "CM", "age": 34, "skin": 0, "hair": 0, "foot": "R", "attrs": {"strength": 11, "pace": 8, "agility": 9, "stamina": 9}}],
	["yorgun 88'", {"seed": 64, "pos": "DM", "age": 30, "skin": 2, "hair": 1, "foot": "R", "attrs": {"strength": 12, "pace": 10, "agility": 9, "stamina": 5}}],
]

func _ready() -> void:
	var on := OS.get_environment("TRAITS") != "0"
	Game.settings["traits3d"] = on
	var out := OS.get_environment("PROBE_OUT")
	var tag := OS.get_environment("PROBE_TAG") if OS.get_environment("PROBE_TAG") != "" else ("after" if on else "before")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 10)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.42, 0.18)
	floor_mi.material_override = fm
	add_child(floor_mi)
	# 1.80 m ölçü çubuğu
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 1.8, 0.05)
	bar.mesh = bm
	bar.position = Vector3(-6.6, 0.9, 0)
	add_child(bar)
	for i in PROFILES.size():
		var p: Dictionary = PROFILES[i][1]
		var m: Node3D = FB.new()
		m.lod = false
		add_child(m)
		m.apply_look(p)
		m.build(FB.kit_mats(Color(0.75, 0.1, 0.12), Color.WHITE, Color(0.75, 0.1, 0.12)), p.skin, p.hair, p.seed, 4 + i)
		m.position = Vector3(-5.0 + i * 2.0, 0, 0)
		m.rotation.y = 0.35
		m.tick(0.0, 0.0)
		if i == 5:
			# yorgun duruşu göster (maçta motor saatinden gelir)
			m.lod = true
			m.tired_w = 1.0 if on else 0.0
			m.tick(0.0, 0.0)
		var l := Label3D.new()
		l.text = "%s\n%s" % [PROFILES[i][0], ("%.0f cm" % float(m.traits.h_cm)) if not m.traits.is_empty() else "-"]
		l.font_size = 40
		l.pixel_size = 0.006
		l.position = m.position + Vector3(0, 2.35, 0)
		add_child(l)
	var cam := Camera3D.new()
	cam.fov = 38
	cam.position = Vector3(0, 1.4, 11.5)
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.make_current()
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if out != "":
		get_viewport().get_texture().get_image().save_png(out.path_join("traits_%s.png" % tag))
	print("TRAITS_DONE ", tag)
	get_tree().quit()
