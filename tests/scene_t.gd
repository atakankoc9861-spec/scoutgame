extends Node
var main
var out := "/home/claude/scene/"
func shot(name: String, frames := 12) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)
func drive(prefix: String) -> void:
	var n := 0
	while main.dlg_layer != null and n < 16:
		if main.stage and main.stage.drill_on:
			var k := 0
			while main.stage and main.stage.drill_on:
				await get_tree().process_frame
				k += 1
				if main.stage.spark_live > 0.3:
					if main.stage.try_catch():
						main._spark_pop(true)
				if k % 30 == 0 and k <= 150:
					await shot("%s_drill%d" % [prefix, k], 1)
			continue
		await shot("%s_%02d" % [prefix, n], 30)
		n += 1
		if main.choice_box and main.choice_box.visible and main.dlg_choices.get_child_count() > 0:
			var b = main.dlg_choices.get_child(0)
			b.pressed.emit()
		else:
			if main._typing:
				main._typing.visible_ratio = 1.0
			main._dlg_waiting = false
			main.dlg_next.emit("")
	await shot(prefix + "_end", 20)
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.new_game("Atakan Koç", "tr")
	Game.take_job(Game.job_offers_start()[1])
	Game.finish_week()
	var pid = Game.search({"tier": Game.tier(Game.my_club().league)})[0]
	main._show("player", pid)
	await shot("p0", 20)
	main._do_action(pid, "train")
	await drive("train")
	main._do_action(pid, "meet")
	await drive("meet")
	main._do_action(pid, "journalist")
	await drive("journ")
	main._do_action(pid, "coach")
	await drive("coach")
	Game.s.scout.money += 500
	var pid2 = Game.search({"tier": 1})[2]
	main._do_action(pid2, "video")
	await drive("video")
	Game.s.week = 4
	main.sub.home = "board"
	main._goto_tab("home")
	await shot("board", 20)
	main._board_meeting()
	await drive("pres")
	# yatay maç (dikey ekranda döndürülmüş)
	var ms = Game.week_matches()
	var key = Game.match_key(ms[0].lg, ms[0].idx)
	var data = Game.watch_match_data(key)
	main._run_viewer(data, [])
	await shot("view_intro", 60)
	main.viewer._end_intro()
	await shot("view_live", 120)
	print("events ", data.eng.events.size())
	get_tree().quit()
