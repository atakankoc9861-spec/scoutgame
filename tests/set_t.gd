extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	var names := ["office", "cafe", "lobby", "home", "video", "training"]
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		names = [a[0]]
	for n in names:
		var host := Control.new()
		host.size = Vector2(720, 1280)
		add_child(host)
		var st = load("res://three/stage3d.gd").new()
		host.add_child(st)
		st.setup(n, false)
		if n in ["office"]:
			st.add_actor("a", {"top": Color("#1f2a44"), "seed": 7}, Vector3(1.75 - 0.33, 0, 0), -PI / 2.0, "sit")
			st.add_actor("b", {"top": Color("#55402a"), "seed": 3}, Vector3(-0.85 + 0.33, 0, 0), PI / 2.0, "sit")
		elif n in ["cafe", "lobby"]:
			st.add_actor("a", {"top": Color("#1f2a44"), "seed": 7}, Vector3(1.0 - 0.33, 0, 0), -PI / 2.0, "sit")
			st.add_actor("b", {"top": Color("#55402a"), "seed": 3}, Vector3(-1.0 + 0.33, 0, 0), PI / 2.0, "sit")
		elif n == "home":
			st.add_actor("a", {"top": Color("#1f2a44"), "seed": 7}, Vector3(1.17, 0, -0.45), -PI / 2.0, "sit")
			st.add_actor("b", {"top": Color("#55402a"), "seed": 3}, Vector3(-1.0 + 0.33, 0, 0), PI / 2.0, "sit")
		st.wide()
		for i in 40:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/home/claude/set_%s.png" % n)
		host.queue_free()
		await get_tree().process_frame
	print("SET DONE")
	get_tree().quit()
