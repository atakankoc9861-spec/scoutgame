extends "res://tests/check/check_base.gd"
## v0.24 Dalga 4B talep tavanı + izin kuralı + bölge seçici:
## - üç kaynak (sezon brifingi, 4 haftalık ek talep, organik) toplamda hiçbir hafta >3 açık talep açmaz
## - "Şimdi yapamam": açık talep kapanır, başkan morali -3, sezonda en fazla 2; yeni sezonda hak yenilenir
## - izinsiz ülkede do_training / do_meet "need_board_abroad" döner ve gün harcamaz; do_video çalışır
## - arama "sadece video" bayrağı izinle birebir; izin verilince kalkar
## - ZONES: her ülke tam bir bölgede, adlar TR/EN, haritada her bölgenin noktası var
## - eski kayıt: PL/SI/MD eski bölge izni ülke bazında korunur (board.abroad_cc)
## - tests/i18n/talep_izin.json TR/EN eşit, yer tutucu sayıları aynı

func watchdog_sec() -> float:
	return 600.0

func run_check() -> void:
	Game.new_game("T", "tr")
	var offers: Array = Game.job_offers_start()
	if not check(not offers.is_empty(), "başlangıç teklifi yok"):
		return
	Game.take_job(str(offers[0]))
	Game.finish_week()
	_check_zones()
	_check_i18n()
	_check_cap_season()
	_check_cap_stress()
	_check_decline()
	_check_permit()
	_check_migrate()
	check_scout_state("son")

func _check_zones() -> void:
	var seen := {}
	for z: String in Data.ZONES:
		for cc: String in Data.ZONES[z]:
			check(not seen.has(cc), "%s iki bölgede: %s, %s" % [cc, seen.get(cc, ""), z])
			seen[cc] = z
		check(Data.ZONE_NAMES.has(z) and Data.ZONE_NAMES[z].size() == 2, "bölge adı eksik: " + z)
		if z != "tr":
			check(not Europe.zone_points(z).is_empty(), "haritada bölge noktası yok: " + z)
	for cc: String in Data.COUNTRIES:
		check(seen.has(cc), "ülke hiçbir bölgede değil: " + cc)
	check(Data.zone_of("SE") == "nordic" and Data.zone_of("PL") == "east" and Data.zone_of("SI") == "balkan", "yeni gruplama yanlış")
	for cc: String in Data.ZONE_MOVED:
		check(Data.zone_of(cc) != str(Data.ZONE_MOVED[cc]), "ZONE_MOVED güncel değil: " + cc)

const Europe = preload("res://ui/europe.gd")

func _check_i18n() -> void:
	var txt := FileAccess.get_file_as_string("res://tests/i18n/talep_izin.json")
	var d: Variant = JSON.parse_string(txt)
	if not check(d is Dictionary, "talep_izin.json okunamadı"):
		return
	for k: String in ["status_declined", "n_assign_declined", "req_decline", "req_decline_q", "req_decline_yes", "decline_ok",
			"decline_limit", "decline_not_open", "video_only", "video_only_note", "zp_title", "zp_hint", "zp_ask"]:
		if not check(d.has(k) and d[k] is Array and d[k].size() == 2, "i18n eksik: " + k):
			continue
		var tr: String = d[k][0]
		var en: String = d[k][1]
		check(tr != "" and en != "", "i18n boş: " + k)
		check(tr.count("%s") == en.count("%s"), "i18n yer tutucu sayısı farklı: " + k)
	check(T.has_key("need_board_abroad"), "need_board_abroad metni yok")

func _check_cap_season() -> void:
	var s0 := int(Game.s.season)
	var mx := Game.req_open_count()
	var weeks := 0
	var made := 0
	var last_aid := int(Game.s.next_aid)
	while int(Game.s.season) == s0 and weeks < Game.WEEKS + 5:
		Game.end_week_auto()
		weeks += 1
		if int(Game.s.season) != s0:
			break
		made += int(Game.s.next_aid) - last_aid
		last_aid = int(Game.s.next_aid)
		var n := Game.req_open_count()
		mx = maxi(mx, n)
		check(n <= Game.REQ_OPEN_MAX, "hafta %d: açık talep %d > %d" % [int(Game.s.week), n, Game.REQ_OPEN_MAX])
	log_info("tam sezon: %d hafta, %d yeni talep, en çok açık %d" % [weeks, made, mx])
	check(int(Game.s.season) == s0 + 1, "sezon bitmedi")
	if not Game.s.season_summary.is_empty():
		Game.dismiss_summary()
	Game.finish_week()

func _check_cap_stress() -> void:
	## Her kaynağı zorla: sezon brifingi ×5, organik ×10 (sakatlık tetikli), 4. hafta ek talep
	Game.s.week = 4
	Game.make_assignments(5)
	check(Game.req_open_count() <= Game.REQ_OPEN_MAX, "make_assignments tavanı aştı: %d" % Game.req_open_count())
	var me := Game.my_club()
	for pid: String in me.squad.slice(0, 6):
		Game.player(pid)["inj"] = 9
	for i in 10:
		Game._organic_requests()
	check(Game.req_open_count() <= Game.REQ_OPEN_MAX, "organik talepler tavanı aştı: %d" % Game.req_open_count())
	for pid: String in me.squad.slice(0, 6):
		Game.player(pid)["inj"] = 0

func _first_open() -> Dictionary:
	for a: Dictionary in Game.s.assign:
		if a.status == "open":
			return a
	return {}

func _check_decline() -> void:
	Game.s.assign = []
	Game.s.erase("req_decl")
	Game.make_assignments(3)
	check(Game.req_open_count() == 3, "3 talep açılamadı: %d" % Game.req_open_count())
	check(Game.declines_left() == Game.DECLINE_MAX, "başlangıç geri çevirme hakkı %d" % Game.declines_left())
	var b := Game.board()
	var mood0 := int(b.mood)
	var a1 := _first_open()
	var r1 := Game.assign_decline(str(a1.id))
	check(bool(r1.ok) and a1.status == "declined", "geri çevirme çalışmadı: %s" % str(r1))
	check(int(b.mood) == mood0 - Game.DECLINE_MOOD, "başkan morali %d -> %d (beklenen -%d)" % [mood0, int(b.mood), Game.DECLINE_MOOD])
	check(Game.req_open_count() == 2, "geri çevrilen talep hâlâ açık sayılıyor")
	check(Game.req_room(), "geri çevirince yer açılmadı")
	var r_again := Game.assign_decline(str(a1.id))
	check(not bool(r_again.ok) and r_again.msg == "decline_not_open", "kapalı talep yeniden geri çevrildi")
	var a2 := _first_open()
	a2.status = "submitted"
	check(Game.assign_decline(str(a2.id)).msg == "decline_not_open", "yönetimdeki talep geri çevrildi")
	a2.status = "open"
	check(bool(Game.assign_decline(str(a2.id)).ok), "ikinci geri çevirme olmadı")
	check(Game.declines_left() == 0, "hak 0 olmalı: %d" % Game.declines_left())
	var a3 := _first_open()
	var r3 := Game.assign_decline(str(a3.id))
	check(not bool(r3.ok) and r3.msg == "decline_limit" and a3.status == "open", "sezonda 3. geri çevirme kabul edildi")
	# kayıt turu: req_decl ve declined durumu korunur
	check_save_roundtrip("geri çevirme")
	check(Game.declines_left() == 0, "kayıttan sonra hak sıfırlandı")
	Game.s.season = int(Game.s.season) + 1
	check(Game.declines_left() == Game.DECLINE_MAX, "yeni sezonda hak yenilenmedi")
	Game.s.season = int(Game.s.season) - 1

func _foreign_pid(want_cc := "") -> String:
	var mc := Game.my_country()
	for pid: String in Game.search({"country": want_cc} if want_cc != "" else {}):
		var p := Game.player(pid)
		var cc := Game.club_country(p.club)
		if cc != mc and not p.youth and (want_cc == "" or cc == want_cc):
			return pid
	return ""

func _check_permit() -> void:
	var b := Game.board()
	b.abroad = []
	b.abroad_cc = []
	var fcc := "SE" if Game.my_country() != "SE" else "DK"
	Game.ensure_country(fcc)
	var res: Array = Game.search({}).slice(0, 30) + Game.search({"country": fcc}).slice(0, 30)
	var n_vo := 0
	var n_ok := 0
	for pid: String in res:
		var cc := Game.club_country(Game.player(pid).club)
		var vo := Game.video_only(pid)
		check(vo == (cc != Game.my_country()), "arama bayrağı yanlış: %s (%s) video_only=%s" % [pid, cc, str(vo)])
		if vo:
			n_vo += 1
		else:
			n_ok += 1
	log_info("arama: %d sonuç, %d sadece video" % [res.size(), n_vo])
	check(n_vo > 0 and n_ok > 0, "aramada hem izinli hem izinsiz oyuncu olmalı (%d/%d)" % [n_ok, n_vo])
	var pid := _foreign_pid(fcc)
	if not check(pid != "", "yabancı oyuncu bulunamadı"):
		return
	var cc := Game.club_country(Game.player(pid).club)
	Game.s.cal = {}
	var fd := Game.free_days()
	var money := int(Game.s.scout.money)
	var rt := Game.do_training(pid, "phy", 0)
	check(not bool(rt.ok) and rt.msg == "need_board_abroad", "izinsiz ülkede antrenman: %s" % str(rt))
	var rm := Game.do_meet(pid, [])
	check(not bool(rm.ok) and rm.msg == "need_board_abroad", "izinsiz ülkede görüşme: %s" % str(rm))
	check(Game.free_days() == fd and int(Game.s.scout.money) == money, "reddedilen eylem gün/para harcadı")
	check(Game.onsite_block(pid) == "need_board_abroad", "onsite_block yanlış")
	var rv := Game.do_video(pid, "tec", 0)
	check(bool(rv.ok), "izinsiz ülkede video çalışmalı: %s" % str(rv))
	# yurtiçi oyuncu: antrenman açık
	var home := ""
	for p2: String in res:
		if not Game.video_only(p2):
			home = p2
			break
	Game.s.cal = {}
	check(bool(Game.do_training(home, "phy", 0).ok), "yurtiçi antrenman kapandı")
	# izin verilince bayrak kalkar, antrenman açılır
	b.abroad.append(Data.zone_of(cc))
	check(not Game.video_only(pid), "izin sonrası hâlâ sadece video")
	Game.s.cal = {}
	check(bool(Game.do_training(pid, "phy", 0).ok), "izin sonrası antrenman olmadı")
	check(not (Game.my_country() == "TR" and "tr" in Game.board_zone_opts()), "ev bölgesi (TR) seçenekte")
	check(not (Data.zone_of(cc) in Game.board_zone_opts()), "verilmiş izin yine seçenekte")
	b.abroad = []
	Game.s.cal = {}

func _check_migrate() -> void:
	## v0.23 kaydı: başkan "central" izni vermişti (o zaman PL ve SI içindeydi), abroad_cc yok
	var b := Game.board()
	b.abroad = ["central", "balkan"]
	b.erase("abroad_cc")
	Game.save_game()
	check(Game.load_game(), "load_game false")
	var b2 := Game.board()
	var keep: Array = b2.get("abroad_cc", [])
	check("PL" in keep, "PL eski izni korunmadı: %s" % str(keep))
	check(not ("SI" in keep), "SI zaten balkan izniyle açık, abroad_cc'ye girmemeli: %s" % str(keep))
	check("MD" in keep, "MD eski balkan izni korunmadı: %s" % str(keep))
	check(Game.board_abroad_ok("PL") and Game.board_abroad_ok("SI") and Game.board_abroad_ok("DE"), "eski izinler çalışmıyor")
	check(not Game.board_abroad_ok("UA"), "PL taşındı diye tüm doğu açıldı")
	b2.abroad = []
	b2.abroad_cc = []
