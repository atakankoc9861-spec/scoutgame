extends Node
func _ready() -> void:
	Game.delete_save()
	Game.new_game("Test", "tr", "TR")
	Game.take_job(Game.job_offers_start()[0])
	for w in 4:
		var a := Time.get_ticks_msec()
		Game.play_day("sat"); Game.play_day("sun")
		var b := Time.get_ticks_msec()
		for wm in Game.week_matches():
			if int(wm.m.gh) < 0:
				Game.sim_match(wm.m, wm.lg)
		var c := Time.get_ticks_msec()
		Game._staff_week()
		Game._week_events()
		var d := Time.get_ticks_msec()
		Game.make_u19_fixtures()
		var e := Time.get_ticks_msec()
		Game.s.week += 1
		Game.save_game()
		var f := Time.get_ticks_msec()
		print("[P] play=", b - a, " sim=", c - b, " events=", d - c, " u19=", e - d, " save=", f - e)
	get_tree().quit()
