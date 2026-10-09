extends Node
## Avrupa dünyası: yeni kariyer (farklı ülkeler), tam sezon, süre/boyut ölçümü
func _ready() -> void:
	for cc in ["PT", "SM"]:
		Game.delete_save()
		var t0 := Time.get_ticks_msec()
		Game.new_game("Test", "tr", cc)
		var t1 := Time.get_ticks_msec()
		var lazy := 0
		for cid in Game.s.clubs:
			if Game.is_lazy(cid):
				lazy += 1
		print("[EURO] ", cc, " yeni oyun ms=", t1 - t0, " kulüp=", Game.s.clubs.size(), " ayrıntısız=", lazy, " oyuncu=", Game.s.players.size(), " lig=", Game.s.fixtures.size())
		var offers := Game.job_offers_start()
		var names := []
		for o in offers:
			names.append("%s(%s,%d)" % [Game.club(o).name, Game.club(o).league, Game.club(o).prestige])
		print("[EURO] teklifler: ", names)
		Game.take_job(offers[0])
		var ws := Time.get_ticks_msec()
		var maxw := 0
		for w in 36:
			var a := Time.get_ticks_msec()
			# bir yabancı lig arama + plan
			if w == 3:
				Game.ensure_league("DE1")
			var ms := Game.week_matches([Game.my_club().league])
			if not ms.is_empty():
				Game.plan_match(ms[0].m.day, Game.match_key(ms[0].lg, ms[0].idx))
			var r := Game.end_week_auto()
			maxw = maxi(maxw, Time.get_ticks_msec() - a)
			if r.get("season_end", false):
				var sm: Dictionary = Game.s.season_summary
				print("[EURO] sezon sonu: şampiyon=", Game.club(sm.champ).name, " yükselen=", sm.promoted.map(func(c): return Game.club(c).name), " düşen=", sm.relegated.map(func(c): return Game.club(c).name))
				break
		var we := Time.get_ticks_msec()
		var lazy2 := 0
		for cid in Game.s.clubs:
			if Game.is_lazy(cid):
				lazy2 += 1
		var sz := FileAccess.get_file_as_bytes(Game.SAVE_PATH).size()
		print("[EURO] sezon ms=", we - ws, " en yavaş hafta=", maxw, " kayıt KB=", sz / 1024, " oyuncu=", Game.s.players.size(), " ayrıntısız=", lazy2, " teklif=", Game.s.offers.map(func(c): return Game.club(c).name + "/" + Game.club_country(c)))
		Game.save_game()
		var ok := Game.load_game()
		var lazy3 := 0
		for cid in Game.s.clubs:
			if Game.is_lazy(cid):
				lazy3 += 1
		print("[EURO] yükle=", ok, " ayrıntısız=", lazy3, " oyuncu=", Game.s.players.size())
		# lig isimleri / bölgeler
		print("[EURO] ", T.t("league_ES1"), " | ", T.t("country_DE"), " | ", T.t("zone_balkan"), " | ", Game.regions(), " | ", Game.tier_name(cc, 1))
	get_tree().quit()
