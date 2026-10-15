extends Node
## Teşhis: quick.tscn neden yavaş? Her adımı ayrı zamanlar (stdout'a hemen yazar).
func _p(s: String) -> void:
	print("[%d ms] %s" % [Time.get_ticks_msec(), s])

func _ready() -> void:
	_p("ready")
	var t0 := Time.get_ticks_msec()
	Game.new_game("T", "tr")
	_p("new_game %d ms players %d clubs %d" % [Time.get_ticks_msec() - t0, Game.s.players.size(), Game.s.clubs.size()])
	t0 = Time.get_ticks_msec()
	Game.take_job(Game.job_offers_start()[0])
	_p("take_job %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	Game.save_game()
	_p("save_game %d ms size %d" % [Time.get_ticks_msec() - t0, FileAccess.get_file_as_bytes(Game.SAVE_PATH).size()])
	for w in 3:
		t0 = Time.get_ticks_msec()
		Game.end_week_auto()
		_p("week %d %d ms" % [Game.s.week, Time.get_ticks_msec() - t0])
	get_tree().quit()
