extends Control
const Stage3D = preload("res://three/stage3d.gd")
func _ready() -> void:
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	var pid: String = Game.my_club().squad[3]
	var p := Game.player(pid)
	var cl := Game.club(p.club)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st = Stage3D.new()
	add_child(st)
	st.setup("training")
	st.add_actor("p", {"kind": "player", "p": p, "club": cl, "training": true}, Vector3(-10, 0, 4), PI / 2.0, "idle")
	st.add_mates(cl, 6)
	var me = st.add_actor("me", {"kind": "npc", "top": Color("#334455"), "seed": 5}, Vector3(-3.0, 0, 9.5), PI, "idle")
	for i in 10: await get_tree().process_frame
	st.start_drills("p", 32.0, 3, "all")
	var marks := [2.0, 5.5, 10.0, 13.5, 17.0, 19.5, 26.0, 29.0]
	var t0 := Time.get_ticks_msec()
	var k := 0
	var dt_acc := 0.0
	while st.drill_on and k < marks.size():
		await get_tree().process_frame
		if float(st.drill.total) >= marks[k]:
			get_viewport().get_texture().get_image().save_png("/home/claude/scene/drill_%d.png" % k)
			print("mark ", k, " ", st.drill.kind)
			k += 1
	get_tree().quit()
