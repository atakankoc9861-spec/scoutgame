extends Node
## Analist Gözü (v0.24 5A) ekran görüntüsü: analist kamerası + işaretler, sonra karar ekranı.
## xvfb-run godot --rendering-driver opengl3 --path . tests/eye_shot.tscn  (EYE_SHOT_DIR=çıktı klasörü)
var out := "/tmp/eye_shots/"

func shot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", out + name + ".png")

func _ready() -> void:
	if OS.get_environment("EYE_SHOT_DIR") != "":
		out = OS.get_environment("EYE_SHOT_DIR").trim_suffix("/") + "/"
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
	host.size = get_viewport().get_visible_rect().size
	add_child(host)
	var mv = load("res://three/match_view.gd").new()
	var foc = [data.m.xi_h[5], data.m.xi_h[7], data.m.xi_h[9]]
	mv.setup(data, fh, fb, foc)
	host.add_child(mv)
	for i in 10: await get_tree().process_frame
	mv._end_intro()
	var n := 0
	var guard := 0
	while n < 2 and guard < 60000 and not mv.done:
		guard += 1
		await get_tree().process_frame
		if mv.eye_state == "choose" and mv.eye.t > 1.2:
			n += 1
			print("soru ", n, " ", mv.eye.pid, " dk ", int(mv.eng.clock / 60.0), " doğru ", mv.eye.opts[mv.eye.best].k, "/", mv.eye.opts[mv.eye.best].get("to", ""), " attr ", mv.eye.attr)
			await shot("eye%d_analist" % n)
			mv._eye_choose((mv.eye.best + 1) % mv.eye.opts.size() if n == 1 else mv.eye.best)
			while mv.eye_state == "wait":
				await get_tree().process_frame
			for i in 20: await get_tree().process_frame
			await shot("eye%d_karar" % n)
			print("karar: ", mv.eye_sub.text.replace("\n", " | "))
	mv.skip_now()
	print("reads ", mv.focus_events.get("_eye_reads", "yok"), " eye.reads ", mv.eye.reads)
	get_tree().quit()
