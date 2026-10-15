extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	var cl := Game.my_club()
	var p: Dictionary = Game.player(cl.squad[3]) if cl.has("squad") else {}
	if p.is_empty():
		for k in Game.s.players:
			p = Game.s.players[k]
			break
	var args := OS.get_cmdline_user_args()
	var styles := ["cine"] if args.size() > 0 else ["board", "cine"]
	for st in styles:
		var d := Drill2D.new()
		add_child(d)
		d.setup(st, p, cl)
		d.size = Vector2(720, 1280)
		for i in 10: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/home/claude/d2_%s_idle.png" % st)
		var order := ["sprint", "slalom", "shoot", "longpass", "duel", "rondo", "cross", "keeper"]
		for kind in order:
			d.drill_on = true
			d.drill = {"list": [kind], "k": -1, "t": 0.0, "total": 0.0, "dur": 7.0, "L": 7.0, "st": {}}
			d.spark_times = [3.0]
			d.spark_idx = 0
			d._next_drill()
			# hızlı ileri sar
			var t := 0.0
			while t < 4.2:
				d._process(0.05)
				t += 0.05
			for i in 3: await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("/home/claude/d2_%s_%s.png" % [st, kind])
		d.queue_free()
		await get_tree().process_frame
	print("D2 DONE")
	get_tree().quit()
