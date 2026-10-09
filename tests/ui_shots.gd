extends Node

var main
var out := "/home/claude/shots/"

func shot(name: String, frames := 30) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)

func scroll_to(px: int) -> void:
	main.scroll.scroll_vertical = px
	await get_tree().process_frame

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
	Game.take_job(Game.job_offers_start()[1])
	main._goto_tab("home")
	await shot("04_home")
	Game.finish_week()
	main._goto_tab("week")
	await shot("05_week")
	await scroll_to(700)
	await shot("05b_week_scrolled")
	var ms = Game.week_matches()
	var m = ms[0]
	var key = Game.match_key(m.lg, m.idx)
	Game.plan_match(m.m.day, key)
	var sq = Game.best_xi(m.m.h)
	Game.toggle_focus(m.m.day, sq[9])
	Game.toggle_focus(m.m.day, sq[5])
	main._show("match", key)
	await shot("06_match_plan")
	# U19 izleme
	main._watch_u19(0)
	await shot("07_u19_viewer", 50)
	main.viewer._skip_to_end()
	await shot("07b_u19_end", 20)
	main.viewer.finished.emit(main.viewer.focus_events)
	await shot("08_u19_obs", 40)
	# hafta sonu
	main._play_weekend()
	await shot("09_viewer", 60)
	main.viewer.speed = 4.0
	await shot("09b_viewer_play", 90)
	main.viewer._open_list()
	await shot("09d_viewer_list", 10)
	main.viewer.list_panel.visible = false
	main.viewer._set_cam("close")
	await shot("09e_viewer_close", 60)
	main.viewer._skip_to_end()
	main.viewer.finished.emit(main.viewer.focus_events)
	await shot("09c_between", 40)
	if main.viewer != null:
		main.viewer._skip_to_end()
		main.viewer.finished.emit(main.viewer.focus_events)
	await shot("10_result", 40)
	var pid = sq[9]
	Game.do_video(pid)
	Game.do_source(pid, "coach")
	Game.toggle_shortlist(pid)
	main._show("player", pid)
	await shot("11_player", 50)
	await scroll_to(900)
	await shot("11b_player_mid")
	await scroll_to(1900)
	await shot("11c_player_attrs")
	main._show("report", pid)
	await shot("12_report")
	main._goto_tab("tasks")
	await shot("13_tasks")
	main.players_mode = "search"
	main._goto_tab("players")
	await shot("14_search")
	main.players_mode = "youth"
	main._goto_tab("players")
	await shot("15_youth")
	main._goto_tab("news")
	await shot("16_news")
	main._show("table")
	await shot("17_table")
	main._goto_tab("home")
	await shot("18_home_after", 40)
	get_tree().quit()
