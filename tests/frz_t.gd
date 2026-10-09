extends Node
var main
func _ready() -> void:
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.end_week_auto()
	main._goto_tab("home")
	for i in 10: await get_tree().process_frame
	# planla
	var wm = Game.week_matches()[0]
	var key: String = Game.match_key(wm.lg, wm.idx)
	Game.plan_match(wm.m.day, key)
	var m := Game.get_match(key)
	var t0 := Time.get_ticks_msec()
	Game.play_day("sat"); Game.play_day("sun")
	var data := Game.watch_match_data(key)
	print("xi ", m.get("xi_h", []).size())
	var focus := [data.m.xi_h[3], data.m.xi_a[8]] if data.m.has("xi_h") else []
	Game.finish_live(data)
	var fe := {}
	Game.apply_watch(data, fe)
	main.pending_result = Game.finish_week()
	var tr := Time.get_ticks_msec()
	main._show("result", null, false)
	print("result sync ", Time.get_ticks_msec() - tr)
	for i in 30: await get_tree().process_frame
	print("result shown ", Time.get_ticks_msec() - t0)
	var obs = main.pending_result.get("obs", [])
	print("obs n ", obs.size())
	for o in obs:
		for pid in o.notes.keys() + o.standouts:
			var t1 := Time.get_ticks_msec()
			main._show("player", pid)
			print("  sync ms ", Time.get_ticks_msec() - t1)
			for i in 20: await get_tree().process_frame
			print("player ", pid, " ms ", Time.get_ticks_msec() - t1, " fps ", Engine.get_frames_per_second())
			main._back()
			for i in 10: await get_tree().process_frame
			print("back ms ", Time.get_ticks_msec() - t1)
	print("done")
	get_tree().quit()
