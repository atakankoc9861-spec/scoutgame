extends Node
func _ready() -> void:
	Game.new_game("T", "tr")
	for lg in ["SL", "BAL1"]:
		var cnt := {}
		var attrs := {}
		var n := 0
		for cid in Game.league_clubs(lg):
			var xi = Game.best_xi(cid)
			for pid in xi:
				var p = Game.player(pid)
				cnt[p.pos] = cnt.get(p.pos, 0) + 1
				for k in ["finishing", "pace", "passing", "tackling", "reflexes", "dribbling"]:
					attrs[k] = attrs.get(k, 0.0) + float(p.attrs[k])
				n += 1
		for k in attrs: attrs[k] = snappedf(attrs[k] / n, 0.1)
		print(lg, " ", cnt, " ", attrs)
	get_tree().quit()
