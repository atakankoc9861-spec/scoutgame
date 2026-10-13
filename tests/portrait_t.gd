extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	var sl = Game.search({"lg": "SL"})
	var done := [0]
	var imgs := []
	for i in 6:
		var p = Game.player(sl[i * 3])
		print(p.club, " ", Game.club(p.club).get("c1"))
		Portrait.request(p, func(t):
			imgs.append(t.get_image())
			done[0] += 1)
	while done[0] < 6:
		await get_tree().process_frame
	var W := Image.create(192 * 6, 192, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		var im: Image = imgs[i]
		im.convert(Image.FORMAT_RGB8)
		W.blit_rect(im, Rect2i(0, 0, 192, 192), Vector2i(i * 192, 0))
	W.save_png("/home/claude/portraits.png")
	print("PORTRAIT DONE")
	get_tree().quit()
