extends Node
var main
func mon() -> String:
	return "vmem %.1fMB tex %.1fMB obj %d nodes %d orphan %d static %.1fMB" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6]
func _ready() -> void:
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	Game.new_game("Atakan Koç", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.end_week_auto()
	main._goto_tab("week")
	for i in 10: await get_tree().process_frame
	print("start ", mon())
	for r in 60:
		var t0 := Time.get_ticks_msec()
		main.sub.week = "matches" if r % 2 == 0 else "this"
		main._refresh_soft()
		var dt := Time.get_ticks_msec() - t0
		for i in 3: await get_tree().process_frame
		if r % 10 == 0: print(r, " build ms ", dt, " ", mon())
	# oyuncu ekranı
	var pid = Game.search({"tier": 1})[0]
	for r in 20:
		main._show("player", pid)
		for i in 3: await get_tree().process_frame
		main._back()
		for i in 3: await get_tree().process_frame
	print("after player ", mon())
	get_tree().quit()
