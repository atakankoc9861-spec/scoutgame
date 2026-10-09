extends Node
var main
func drag(from: Vector2, to: Vector2, touch: bool) -> void:
	if touch:
		var t := InputEventScreenTouch.new(); t.position = from; t.pressed = true; t.index = 0
		Input.parse_input_event(t)
		await get_tree().process_frame
		for i in 12:
			var d := InputEventScreenDrag.new(); d.index = 0
			d.position = from.lerp(to, (i + 1) / 12.0); d.relative = (to - from) / 12.0
			Input.parse_input_event(d)
			await get_tree().process_frame
		var r := InputEventScreenTouch.new(); r.position = to; r.pressed = false; r.index = 0
		Input.parse_input_event(r)
	else:
		var b := InputEventMouseButton.new(); b.position = from; b.button_index = MOUSE_BUTTON_LEFT; b.pressed = true
		Input.parse_input_event(b)
		await get_tree().process_frame
		for i in 12:
			var m := InputEventMouseMotion.new(); m.position = from.lerp(to, (i + 1) / 12.0); m.relative = (to - from) / 12.0; m.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(m)
			await get_tree().process_frame
		var r := InputEventMouseButton.new(); r.position = to; r.button_index = MOUSE_BUTTON_LEFT; r.pressed = false
		Input.parse_input_event(r)
	for i in 5:
		await get_tree().process_frame
func _ready() -> void:
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.finish_week()
	main.sub.players = "search"
	main.sub.week = "matches"
	for scr in ["players", "week", "news"]:
		main._goto_tab(scr)
		for i in 30:
			await get_tree().process_frame
		var y0 = main.scroll.scroll_vertical
		for pt in [Vector2(360, 900), Vector2(100, 700), Vector2(600, 1000)]:
			main.scroll.scroll_vertical = 0
			await get_tree().process_frame
			await drag(pt, pt - Vector2(0, 400), true)
			print("  dbg active=", main._sd_active, " moved=", main._sd_moved, " holder=", main.holder.get_global_rect(), " vel=", main._sd_vel)
			var mm := InputEventMouseMotion.new(); mm.position = pt
			Input.parse_input_event(mm)
			await get_tree().process_frame
			var hov = get_viewport().gui_get_hovered_control()
			var chain := []
			var n = hov
			while n != null and chain.size() < 12:
				chain.append("%s(%s,%d)" % [n.get_class(), n.name, n.mouse_filter if n is Control else -1])
				n = n.get_parent()
			print(chain)
			print(scr, " touch at ", pt, " -> scroll ", main.scroll.scroll_vertical, " max ", main.scroll.get_v_scroll_bar().max_value, " ctrl ", get_viewport().gui_find_control(pt) if false else "")
	get_tree().quit()
