extends Node
var main
var out := "/home/claude/euroshots/"
func shot(name: String, frames := 40) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await shot("e0_title", 30)
	main.ng_country = "ES"
	main._show("newgame")
	await shot("e1_newgame", 30)
	Game.new_game("Atakan Koç", "tr", "ES")
	main._show("offers", null, false)
	await shot("e2_offers", 30)
	Game.take_job(Game.s.offers[0])
	Game.s.offers = []
	Game.finish_week()
	main._goto_tab("week")
	await shot("e3_week", 60)
	main._show("table")
	await shot("e4_table", 30)
	main.search_f.country = "DE"
	main.search_f.tier = 1
	main._goto_tab("players")
	main.sub.players = "search"
	main.players_mode = "search"
	main._refresh()
	await shot("e5_search", 30)
	main._goto_tab("home")
	main.sub.home = "career"
	main._refresh()
	await shot("e6_career", 30)
	main.ng_country = "TR"
	Game.new_game("Atakan Koç", "tr", "DE")
	Game.take_job(Game.job_offers_start()[0])
	main._goto_tab("week")
	await shot("e7_week_de", 60)
	Game.new_game("Atakan Koç", "tr", "NO")
	Game.take_job(Game.job_offers_start()[0])
	main._goto_tab("week")
	await shot("e8_week_no", 60)
	Game.new_game("Atakan Koç", "tr", "EN")
	Game.take_job(Game.job_offers_start()[0])
	main._goto_tab("week")
	await shot("e9_week_en", 60)
	Game.new_game("Atakan Koç", "tr", "TR")
	Game.take_job(Game.job_offers_start()[0])
	Game.refresh_staff_pool(true)
	Game.board().slots = 2
	Game.s.staff_pool[0].role = "scout"
	Game.hire_staff(Game.s.staff_pool[0].id)
	main._goto_tab("team")
	await shot("e10_team", 40)
	main._goto_tab("week")
	await shot("e11_week_tr", 60)
	get_tree().quit()
