extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.finish_week()
	var ms = Game.week_matches()
	var key = Game.match_key(ms[0].lg, ms[0].idx)
	Game.play_day(ms[0].m.day)
	var data = Game.watch_match_data(key)
	var fh = load("res://fonts/BarlowCondensed-Bold.ttf")
	var mv = load("res://three/match_view.gd").new()
	mv.setup(data, fh, fh, [])
	add_child(mv)
	mv._end_intro()
	var real := 0.0
	var t0 := Time.get_ticks_msec()
	var maxsteps := int(OS.get_environment("STEPS")) if OS.get_environment("STEPS") != "" else 30 * 60 * 4
	var steps := 0
	var hl := OS.get_environment("HL") == "1"
	if hl:
		mv._cycle_speed()
		mv._cycle_speed()
	while not mv.done and steps < maxsteps:
		if mv.mode == "replay":
			mv._after_replay()
		mv._process(1.0 / 30.0)
		real += 1.0 / 30.0
		steps += 1
	var d = mv.dbg
	print("EVENTS ", mv.idx, "/", mv.tl.size(), " real_s=", snappedf(real, 0.1), " game_s=", snappedf(mv.game_t, 0.1), " cpu_ms=", Time.get_ticks_msec() - t0)
	print("KICK avg=", snappedf(d.kick_far / max(1, d.kick), 0.01), " n=", d.kick, "  RECV avg=", snappedf(d.recv_far / max(1, d.recv), 0.01), " bad=", d.recv_bad, "/", d.recv)
	get_tree().quit()
