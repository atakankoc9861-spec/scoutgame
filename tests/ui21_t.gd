extends Node
var main
var out := "/home/claude/ui21/"
func shot(n: String, frames := 30) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + n + ".png")
	print("shot ", n)
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.delete_save()
	if FileAccess.file_exists(Game.CRASH_FLAG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.CRASH_FLAG))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.new_game("Atakan Koç", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.finish_week()
	var sl = Game.search({"lg": Game.my_club().league})
	for i in 14:
		Game.toggle_shortlist(sl[i])
		Game.log_discovery(sl[i], "match")
	Game.s.scout.disc_log[0].season = 2023
	Game._headline("transfer", sl[0], ["Galatasaray SK", "€4.5M"])
	Game.s.events = [{"kind": "dilemma", "type": "bribe", "pid": sl[2], "money": 4000, "week": Game.s.week}]
	main._goto_tab("home")
	await shot("01_tut_home", 40)
	await shot("02_headline", 40)
	main._choice_done.emit(true)
	await shot("03_dilemma", 40)
	main._choice_done.emit(false)
	await shot("04_dilemma_res", 20)
	main._choice_done.emit(true)
	await shot("05_after", 30)
	# son gün
	var dl = Game._make_deadline()
	main._run_event(dl)
	await shot("06_deadline", 30)
	main._choice_done.emit(true)
	await shot("07_deadline_res", 20)
	for i in 4:
		await get_tree().create_timer(1.6).timeout
		main._choice_done.emit(false)
	await shot("08_deadline_sum", 30)
	main._choice_done.emit(true)
	# turnuva
	Game.s.scout.money = 50000
	main._run_event({"kind": "tournament", "cc": "NL", "summer": true})
	await shot("09_tour_inv", 30)
	main._choice_done.emit(true)
	await shot("10_tour_m1", 30)
	for i in 4:
		var m = Game.s.players.keys()[-1]
		main._choice_done.emit(m)
		await get_tree().process_frame
	await shot("11_tour_done", 30)
	main._choice_done.emit(true)
	await get_tree().process_frame
	main.sub.home = "archive"
	main._goto_tab("home")
	await shot("12_finds", 40)
	main.scroll.scroll_vertical = 700
	await shot("13_finds2", 20)
	main.sub.home = "career"
	main._goto_tab("home")
	await shot("14_career", 40)
	print("UI21 DONE")
	get_tree().quit()
