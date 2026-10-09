extends Node
var main
func _ready() -> void:
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 20: await get_tree().process_frame
	Game.new_game("Atakan Koç", "tr")
	Game.take_job(Game.job_offers_start()[0])
	main._goto_tab("home")
	for i in 10: await get_tree().process_frame
	var pid: String = Game.s.players.keys()[40]
	var r := {"pid": pid, "fee": 450000}
	main._signing_scene(r)
	var k := 0
	for f in 900:
		await get_tree().process_frame
		if f % 60 == 30:
			get_viewport().get_texture().get_image().save_png("/home/claude/scene/sign_%02d.png" % k)
			k += 1
			main.dlg_next.emit()
		if main.dlg_layer == null:
			break
	# ev ziyareti
	var yp := ""
	for id in Game.s.players:
		var p = Game.player(id)
		if int(p.age) <= 18 and p.club != "" and not p.youth:
			yp = id; break
	if yp == "":
		for id in Game.s.players:
			if int(Game.player(id).age) <= 18: yp = id; break
	Game.player(yp)["youth"] = false
	print("home visit ", yp, " age ", Game.player(yp).age)
	main._do_action(yp, "meet")
	k = 0
	for f in 1500:
		await get_tree().process_frame
		if f % 50 == 25:
			get_viewport().get_texture().get_image().save_png("/home/claude/scene/home_%02d.png" % k)
			k += 1
			if main.choice_box and main.choice_box.visible:
				var bs = main.choice_box.find_children("*", "Button", true, false)
				if not bs.is_empty(): bs[0].pressed.emit()
			else:
				main.dlg_next.emit()
		if main.dlg_layer == null and f > 100:
			break
	print("done")
	get_tree().quit()
