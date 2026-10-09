extends Node
var out := "/home/claude/shots3d/"
func shot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.finish_week()
	var sl = Game.search({"lg": "SL"})
	var pid: String = ""
	for c in sl:
		var p = Game.player(c)
		if p.pos in ["CM", "AM", "LW", "ST"]:
			pid = c
			break
	var data = Game.video_match_data(pid)
	print("[V] video ", Game.pname(Game.player(pid)), " vs ", Game.club(data.vs).name, " moments=", data.moments)
	var fh = load("res://fonts/BarlowCondensed-Bold.ttf")
	var fb = load("res://fonts/Barlow-Medium.ttf")
	var host = Control.new()
	host.size = Vector2(1280, 720)
	add_child(host)
	var mv = load("res://three/match_view.gd").new()
	mv.setup(data, fh, fb, [pid])
	host.add_child(mv)
	for i in 10: await get_tree().process_frame
	mv._end_intro()
	var guard := 0
	var eyes := 0
	var shots := 0
	var last_m := 0
	while guard < 9000 and not mv.done:
		guard += 1
		await get_tree().process_frame
		if mv.moments_seen != last_m and not mv.seeking:
			last_m = mv.moments_seen
			print("[V] an ", last_m, " dk ", int(mv.eng.clock / 60.0), " frame ", guard)
			if shots < 2:
				shots += 1
				await shot("vid_moment%d" % last_m)
		if mv.seeking and guard % 60 == 0 and shots < 3:
			shots += 1
			await shot("vid_seek")
		if mv.eye_state == "choose":
			eyes += 1
			print("[V] eye opts ", mv.eye_opts.map(func(o): return [o.k, o.get("to",""), snappedf(o.v, 0.0001), snappedf(o.risk, 0.01)]), " best ", mv.eye_best)
			if eyes == 1:
				await shot("vid_eye_choose")
			mv._eye_choose(randi() % mv.eye_opts.size())
			while mv.eye_state == "wait":
				await get_tree().process_frame
			if eyes == 1:
				await shot("vid_eye_verdict")
			print("[V] verdict: ", mv.eye_sub.text.replace("\n", " | "))
	print("[V] bitti done=", mv.done, " anlar=", mv.moments_seen, " göz=", eyes, " dk=", int(mv.eng.clock / 60.0), " frames=", guard, " fe=", mv.focus_events.get(pid, []).size())
	var fe = mv.focus_events
	fe["_eye"] = mv.eye_log
	fe["_eye_hits"] = mv.eye_hits
	fe["_sparks"] = mv.spark_caught
	var r = Game.finish_video(pid, data, fe, "tec")
	print("[V] sonuç ", r.ok, " notlar ", r.notes.map(func(it): return T.t(it[0], it[1])), " satır ", r.lines.map(func(it): return T.t(it[0], it[1])))
	get_tree().quit()
