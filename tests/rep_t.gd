extends Node
var main
func _ready() -> void:
	Game.delete_save()
	Game.settings.sound = false
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	Game.new_game("Atakan Koç", "tr")
	Game.s.offers = []
	var offers = Game.job_offers_start()
	var pick = offers[0]
	for cid in Game.s.clubs:
		if "Defne" in Game.club(cid).get("name", ""): pick = cid
	Game.take_job(pick)
	print("club ", Game.my_club().name, " ", Game.my_club().league)
	for i in 2:
		Game.end_week_auto()
	var t0 := Time.get_ticks_msec()
	main.sub["week"] = "matches"
	for lg in Game.LEAGUES.keys():
		main.week_lg = lg
		var t1 := Time.get_ticks_msec()
		main._goto_tab("week")
		await get_tree().process_frame
		print("week matches ", lg, " ms ", Time.get_ticks_msec() - t1)
	main.sub["week"] = "u19"
	main._goto_tab("week")
	await get_tree().process_frame
	# U19 izle -> obs ekranı
	var data = Game.watch_u19_data(0)
	var eng = load("res://sim/live_engine.gd").new()
	data.eng = eng
	eng.setup(Game, data.m, true, 7)
	eng.run_to_end()
	Game.finish_live(data)
	var obs = Game.apply_watch(data, {})
	main.pending_obs = obs
	main._show("obs", null, true)
	await get_tree().process_frame
	print("obs ok, keys ", obs.keys())
	var cnt := 0
	for pid in obs.get("new_ids", obs.get("found", [])):
		var t2 := Time.get_ticks_msec()
		main._show("player", pid)
		await get_tree().process_frame
		cnt += 1
		print("player ", pid, " ms ", Time.get_ticks_msec() - t2)
		if cnt > 6: break
	for pid in data.m.xi_h.slice(0, 5):
		var t3 := Time.get_ticks_msec()
		main._show("player", pid)
		await get_tree().process_frame
		print("player xi ", pid, " ms ", Time.get_ticks_msec() - t3)
	print("DONE ", Time.get_ticks_msec() - t0)
	get_tree().quit()
