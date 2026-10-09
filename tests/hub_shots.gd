extends Node
var main
var out := "/home/claude/hubshots/"
func shot(name: String, frames := 50) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.new_game("Atakan Koç", "tr")
	Game.s.offers = []
	Game.take_job(Game.job_offers_start()[1])
	Game.finish_week()
	var sl = Game.search({"lg": "SL"})
	for i in 6:
		Game.toggle_shortlist(sl[i])
	var ms = Game.week_matches()
	Game.plan_match(ms[3].m.day, Game.match_key(ms[3].lg, ms[3].idx))
	Game.do_video(sl[0])
	main._goto_tab("home")
	await shot("h1_home", 80)
	print("BAND ", main.hub.band, " pos ", main.hub.position, main.hub.size, " fov ", main.hub.cam.fov)
	main._goto_tab("week")
	await shot("h2_week")
	print("BAND ", main.hub.band, " pos ", main.hub.position, main.hub.size, " fov ", main.hub.cam.fov)

	main._goto_tab("players")
	await shot("h3_players")
	main._show("player", sl[0])
	await shot("h4_player")
	main._goto_tab("news")
	await shot("h5_news")
	main._show("table")
	await shot("h6_table", 60)
	main.hub.set_active(false)
	await shot("h8_off", 10)
	main.hub.set_active(true)
	main._goto_tab("week")
	await shot("h9_week_back", 40)
	print("BACK sv ", main.hub.sv.size, " hub ", main.hub.size)
	main._show("title", null, false)
	await shot("h7_title", 40)
	print("TITLE ", main.hub.size, main.hub.band, main.hub.cam.fov)
	get_tree().quit()
