extends Node
## Render ölçümü (tech-art Faz 0): maç görünümü (gece tier0 + gündüz tier2) ve bir sahne (stage3d)
## kurar, sabit kare sayısı sonra çizim sayaçlarını okur ve ekran görüntüsü kaydeder.
## GPU gerekir; headless'ta sayaçlar 0 gelir. Çalıştırma:
##   xvfb-run -s "-screen 0 720x1280x24" $GODOT --rendering-driver opengl3 --path . res://tests/baseline/render_probe.tscn
## Ortam: PROBE_OUT=klasör (png), PROBE_TAG=etiket. Çıktı satırları "PROBE {json}".

var out := ""
var tag := "run"

func _info() -> Dictionary:
	var rs := RenderingServer
	return {
		"draw_calls": rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"texture_mem_mb": snappedf(rs.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.01),
		"video_mem_mb": snappedf(rs.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.01),
	}

func _measure(name: String, frames := 90) -> void:
	for i in frames:
		await get_tree().process_frame
	# birkaç karenin en büyüğü (sayaçlar kareye göre oynar)
	var best := {}
	for i in 8:
		await RenderingServer.frame_post_draw
		var inf := _info()
		for k in inf:
			best[k] = maxf(float(best.get(k, 0.0)), float(inf[k]))
	best["scene"] = name
	best["tag"] = tag
	if out != "":
		get_viewport().get_texture().get_image().save_png(out.path_join("%s_%s.png" % [name, tag]))
	print("PROBE ", JSON.stringify(best))

func _match(cond: Dictionary, cam: String, name: String, cam2 := "") -> void:
	var ms = Game.week_matches()
	var key = Game.match_key(ms[0].lg, ms[0].idx)
	var data: Dictionary = Game.watch_match_data(key)
	data["cond"] = cond
	var host := Control.new()
	host.size = Vector2(720, 1280)
	add_child(host)
	var mv = load("res://three/match_view.gd").new()
	mv.setup(data, load("res://fonts/BarlowCondensed-Bold.ttf"), load("res://fonts/Barlow-Medium.ttf"), [data.m.xi_h[6], data.m.xi_a[9]])
	host.add_child(mv)
	for i in 30:
		await get_tree().process_frame
	mv._end_intro()
	# sabit durum: maç akışı durdurulur (yalnız kamera oturur) -> öncesi/sonrası karşılaştırılabilir
	for i in 20:
		await get_tree().process_frame
	mv.paused = true
	mv.cam_mode = cam
	await _measure(name)
	if cam2 != "":
		mv.cam_mode = cam2
		await _measure(name + "_" + cam2, 60)
	host.queue_free()
	for i in 5:
		await get_tree().process_frame

func _ready() -> void:
	out = OS.get_environment("PROBE_OUT")
	if OS.get_environment("PROBE_TAG") != "":
		tag = OS.get_environment("PROBE_TAG")
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	Game.rng.seed = 20231015
	seed(20231015)
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.finish_week()
	var ms = Game.week_matches()
	Game.play_day(ms[0].m.day)
	await _measure("empty", 10)
	await _match({"stadium": 0, "tod": "night", "weather": "clear"}, "wide", "match_night_t0", "stand")
	await _match({"stadium": 2, "tod": "day", "weather": "clear"}, "stand", "match_day_t2")
	# yalnız stadyum, sabit kamera (deterministik; projektör kuleleri kadrajda)
	for t in [0, 2]:
		var sv := SubViewport.new()
		sv.size = Vector2i(720, 1280)
		sv.own_world_3d = true
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var svc := SubViewportContainer.new()
		svc.size = Vector2(720, 1280)
		svc.add_child(sv)
		add_child(svc)
		var sd = load("res://three/stadium.gd").new()
		sv.add_child(sd)
		sd.configure(t, "night", "clear")
		sd.build(Color(0.8, 0.1, 0.1), Color.WHITE, Color(0.1, 0.2, 0.8), true, false, true)
		var cam := Camera3D.new()
		cam.fov = 60
		sv.add_child(cam)
		cam.position = Vector3(-95, 45, 80)
		cam.look_at(Vector3(0, 8, 0))
		await _measure("stadium_night_t%d" % t, 30)
		svc.queue_free()
		for i in 3:
			await get_tree().process_frame
	var st = load("res://three/stage3d.gd").new()
	add_child(st)
	st.setup("training")
	st.wide()
	await _measure("stage_training")
	print("PROBE_DONE")
	get_tree().quit()
