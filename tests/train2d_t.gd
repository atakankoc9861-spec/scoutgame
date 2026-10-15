extends Node
var main
var out := "/home/claude/tr2d/"
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
				if k % 90 == 0:
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
	Game.settings["drill_style"] = ""
	var pid = Game.search({"tier": Game.tier(Game.my_club().league)})[0]
	main._show("player", pid)
	await shot("p0", 10)
	main._do_action(pid, "train")
	await shot("modal", 20)
	main._choice_done.emit("board")
	await drive("board")
	Game.settings["drill_style"] = "cine"
	Game.s.scout.fatigue = 0
	main._do_action(pid, "train")
	await drive("cine")
	print("TR2D DONE ", Game.settings.drill_style)
	get_tree().quit()
