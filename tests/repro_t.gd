extends Node
var main
func _ready() -> void:
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 30: await get_tree().process_frame
	Game.new_game("Atakan Koç", "tr")
	var cid := ""
	for id in Game.s.clubs:
		if Game.s.clubs[id].name == "Hatay Defne SK": cid = id
	print("club ", cid, " league ", Game.s.clubs[cid].league)
	Game.take_job(cid)
	Game.end_week_auto()
	Game.end_week_auto()
	main._goto_tab("week")
	for i in 5: await get_tree().process_frame
	print("--- matches tab")
	main.sub.week = "matches"
	main._refresh_soft()
	for i in 5: await get_tree().process_frame
	print("page children ", main.page.get_child_count())
	print("--- u19")
	var data = Game.watch_u19_data(0)
	var mv = load("res://three/match_view.gd").new()
	Game.finish_live(data)
	main.pending_obs = Game.apply_watch(data, {})
	main._show("obs", null, true)
	for i in 5: await get_tree().process_frame
	var pids = main.pending_obs.get("players", main.pending_obs.keys())
	print("obs keys ", main.pending_obs.keys())
	# ilk detay butonu: oyuncu ekranı
	for k in main.pending_obs.keys():
		var v = main.pending_obs[k]
		if v is Array and v.size() > 0:
			var first = v[0]
			var pid = first.get("pid", first.get("id", "")) if first is Dictionary else str(first)
			print("open player ", pid)
			main._show("player", pid)
			for i in 5: await get_tree().process_frame
			break
	print("done")
	get_tree().quit()
