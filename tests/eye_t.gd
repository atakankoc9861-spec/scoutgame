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
	var ms = Game.week_matches()
	var key = Game.match_key(ms[0].lg, ms[0].idx)
	Game.play_day(ms[0].m.day)
	var data = Game.watch_match_data(key)
	var fh = load("res://fonts/BarlowCondensed-Bold.ttf")
	var fb = load("res://fonts/Barlow-Medium.ttf")
	var host = Control.new()
	host.size = Vector2(1280, 720)
	add_child(host)
	var mv = load("res://three/match_view.gd").new()
	var foc = [data.m.xi_h[5], data.m.xi_h[7], data.m.xi_a[6]]
	mv.setup(data, fh, fb, foc)
	host.add_child(mv)
	for i in 10: await get_tree().process_frame
	mv._end_intro()
	mv.speed = 4.0
	var n := 0
	var guard := 0
	while n < 3 and guard < 20000 and not mv.done:
		guard += 1
		await get_tree().process_frame
		if mv.eye_state == "choose":
			n += 1
			print("eye start owner ", mv.eye_owner, " opts ", mv.eye_opts.map(func(o): return [o.k, o.get("to",""), snappedf(o.v, 0.0001), snappedf(o.risk, 0.01)]))
			await shot("eye%d_choose" % n)
			mv._eye_choose(1 if n == 1 else 0)
			while mv.eye_state == "wait":
				await get_tree().process_frame
			await shot("eye%d_verdict" % n)
			print("verdict: ", mv.eye_sub.text.replace("\n", " | "))
	print("eye log ", mv.eye_log, " hits ", mv.eye_hits, " clock ", int(mv.eng.clock/60))
	mv.skip_now()
	var fe = mv.focus_events
	fe["_eye"] = mv.eye_log
	fe["_eye_hits"] = mv.eye_hits
	Game.finish_live(data)
	var obs = Game.apply_watch(data, fe)
	for pid in obs.notes:
		print(pid, " ", obs.notes[pid].map(func(it): return T.t(it[0], it[1])))
	get_tree().quit()
