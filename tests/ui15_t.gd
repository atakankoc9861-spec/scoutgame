extends Node
var main
var out := "/home/claude/shots15/"
func shot(name: String, frames := 25) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Game.delete_save()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 20: await get_tree().process_frame
	Game.new_game("Atakan Koç", "tr")
	Game.take_job(Game.job_offers_start()[0])
	for i in 2:
		Game.end_week_auto()
	# veri hazırla
	Game.area_gain("TR1", 30.0); Game.area_gain("TR3", 12.0); Game.area_gain("EN", 4.0)
	Game.s.scout.spec.ATT = 4.0; Game.s.scout.spec.gem = 5.0
	Game.s.scout.acc = {"n": 6, "good": 4, "infl": 1}
	Game.s.scout.badges = Game.scout_badges()
	var n := 0
	for pid in Game.s.players:
		var p = Game.player(pid)
		if p.club != "" and p.club != Game.s.scout.club_id and not p.youth and p.pos in ["ST", "CB", "LB", "CM"]:
			if Game.shadow_of(p.pos).size() < 2:
				Game.know(pid); Game.shadow_add(pid, p.pos); n += 1
		if n >= 6: break
	Game._organic_assign("first11", "ST", "inj", Game.my_club().squad[0], true, 6)
	var e := {"pid": Game.s.scout.shortlist[0], "name": "Rodrigo Souza", "pos": "LW", "seen_season": 2026, "seen_age": 16, "ovr0": 44, "ovr": 68, "club": "c3", "why": "rejected", "season": 2027, "value": 2500000, "how": "tip"}
	Game.s.museum.append(e)
	main._goto_tab("home")
	main.sub.home = "career"; main._refresh_soft()
	await shot("01_career")
	main.scroll.scroll_vertical = 700
	await shot("02_career_rep")
	main.scroll.scroll_vertical = 1400
	await shot("03_career_badges")
	main.sub.home = "archive"; main._refresh_soft()
	main.scroll.scroll_vertical = 0
	await shot("04_archive")
	main.scroll.scroll_vertical = 900
	await shot("05_archive2")
	main._goto_tab("players")
	main.sub.players = "shadow"; main._refresh_soft()
	await shot("06_shadow")
	main.scroll.scroll_vertical = 600
	await shot("07_shadow2")
	main._goto_tab("tasks")
	await shot("08_tasks")
	main._show("player", Game.s.scout.shortlist[0])
	await shot("09_player")
	get_tree().quit()
