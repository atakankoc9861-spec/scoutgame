extends Node
var main
var out := "/home/claude/ui8/"
func shot(name: String, frames := 20) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)
func scroll_to(px: int) -> void:
	main.scroll.scroll_vertical = px
	await get_tree().process_frame
func subtab(screen: String, key: String, val: String, name: String, arg = null, sc := 0) -> void:
	main.sub[key] = val
	if arg == null:
		main._goto_tab(screen)
	else:
		main._show(screen, arg)
	await get_tree().process_frame
	if sc > 0:
		await scroll_to(sc)
	await shot(name)
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await shot("01_title", 60)
	main._show("newgame")
	await shot("02_newgame")
	Game.new_game("Atakan Koç", "tr")
	main._show("offers", null, false)
	await shot("03_offers")
	Game.s.offers = []
	Game.take_job(Game.job_offers_start()[2])
	# birkaç hafta oynat ki veri olsun
	for i in 3:
		var wm = Game.week_matches(Game.TIER_GROUPS[Game.tier(Game.my_club().league)])
		if wm.size() > 0:
			var mm = wm[0]
			Game.plan_match(mm.m.day, Game.match_key(mm.lg, mm.idx))
			var sq = Game.best_xi(mm.m.h)
			Game.toggle_focus(mm.m.day, sq[9])
			Game.toggle_focus(mm.m.day, sq[6])
		Game.end_week_auto()
	var all = Game.search({"tier": Game.tier(Game.my_club().league)})
	for pid in all.slice(0, 4):
		Game.toggle_shortlist(pid)
	if all.size() > 0:
		Game.do_video(all[0])
		Game.do_source(all[0], "coach")
		Game.submit_report(all[0], Game.s.assign[0].id, 3.0, 3.5, "sign", [])
	await subtab("home", "home", "summary", "04_home")
	await subtab("home", "home", "career", "04b_career")
	await subtab("home", "home", "club", "04c_myclub")
	await subtab("week", "week", "this", "05_week")
	await subtab("week", "week", "matches", "05b_matches")
	await subtab("week", "week", "u19", "05c_u19")
	var ms = Game.week_matches(Game.TIER_GROUPS[Game.tier(Game.my_club().league)])
	var key = Game.match_key(ms[0].lg, ms[0].idx)
	Game.plan_match(ms[0].m.day, key)
	main._show("match", key)
	await shot("06_match_plan")
	await subtab("tasks", "tasks", "requests", "07_tasks")
	await subtab("tasks", "tasks", "reports", "07b_reports")
	await subtab("tasks", "tasks", "transfers", "07c_transfers")
	await subtab("players", "players", "shortlist", "08_shortlist")
	await subtab("players", "players", "search", "08b_search")
	await subtab("players", "players", "youth", "08c_youth")
	main.compare = Game.s.scout.shortlist.slice(0, 2)
	await subtab("players", "players", "compare", "08d_compare", null, 500)
	var pid = all[0]
	await subtab("player", "player", "file", "09_player", pid)
	await subtab("player", "player", "file", "09b_player_mid", pid, 900)
	await subtab("player", "player", "attrs", "09c_attrs", pid, 500)
	await subtab("player", "player", "notes", "09d_notes", pid)
	await subtab("player", "player", "career", "09e_pcareer", pid)
	main._show("report", pid)
	await shot("10_report")
	await scroll_to(1200)
	await shot("10b_report_low")
	await subtab("news", "news", "news", "11_news")
	await subtab("news", "news", "table", "11b_table")
	await subtab("news", "news", "fixtures", "11c_fixtures")
	await subtab("club", "club", "squad", "12_club", Game.my_club().id)
	await subtab("club", "club", "info", "12b_clubinfo", Game.my_club().id)
	Game.refresh_staff_pool(true)
	Game.s.scout.rep = 45.0
	Game.hire_staff(Game.s.staff_pool[0].id)
	Game.hire_staff(Game.s.staff_pool[0].id)
	Game.assign_staff(Game.s.staff[0].id, "en")
	Game.finish_week()
	Game.finish_week()
	await subtab("team", "team", "staff", "14_team")
	await subtab("team", "team", "pool", "14b_pool")
	await subtab("team", "team", "reports", "14c_sreports")
	main.week_lg = "EN1"
	await subtab("week", "week", "matches", "15_week_en")
	main.table_lg = "BR1"
	await subtab("news", "news", "table", "15b_table_br")
	main.pending_result = Game.finish_week()
	main._show("result", null, false)
	await shot("13_result")
	get_tree().quit()
