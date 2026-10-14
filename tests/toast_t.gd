extends Node
func shot(n):
	for i in 25: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/home/claude/toast_%s.png" % n)
func _ready() -> void:
	Game.delete_save()
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await shot("0")
	for i in 60: await get_tree().process_frame
	main._toast("Hata kaydı kopyalandı")
	print("toast ", main.toast.visible, " ", main.toast.get_global_rect(), " ", main.toast.modulate)
	await shot("1")
	print("toast2 ", main.toast.visible, " ", main.toast.get_global_rect(), " ", main.toast.modulate, " z", main.toast.get_index(), "/", main.get_child_count(), " ", main.get_children().map(func(c): return c.get_class()))
	Game.new_game("T", "tr")
	Game.take_job(Game.job_offers_start()[0])
	Game.tut_skip()
	Game.s.events = []
	main._goto_tab("week")
	for i in 20: await get_tree().process_frame
	main._toast("Fazla mesai: bu hafta bir iş günün daha var.")
	await shot("2")
	main._toast("Grafik sürücüsü takıldı. 3B görüntü gelmezse oyunu kapatıp yeniden aç; ilerlemen kayıtlı.")
	await shot("3")
	get_tree().quit()
