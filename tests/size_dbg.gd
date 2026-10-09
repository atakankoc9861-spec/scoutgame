extends Node
func walk(n: Node, depth: int) -> void:
	if n is Control and depth <= 4:
		print("  ".repeat(depth), n.get_class(), " ", n.name, " min=", n.get_combined_minimum_size(), " size=", n.size)
	for c in n.get_children():
		walk(c, depth + 1)
func _ready() -> void:
	Game.delete_save()
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.new_game("Atakan Koç", "tr")
	Game.s.offers = []
	Game.take_job(Game.job_offers_start()[1])
	main._goto_tab("home")
	for i in 10:
		await get_tree().process_frame
	print("main ", main.size, " root ", main.root.size, " topbar ", main.topbar.size, " page ", main.page.size, " scroll ", main.scroll.size)
	walk(main, 0)
	get_tree().quit()
