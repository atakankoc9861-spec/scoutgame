extends "res://tests/check/check_base.gd"
## v0.24 Dalga 2A ilerleme dengesi:
## - is_my_find: yalnız rapor yazılan / ilk keşfi sana ait oyuncu (match/staff/tip/agent sayılmaz,
##   u19 yalnız odakla izlendiyse)
## - manşet itibarı sezonda en fazla Game.HL_REP_CAP, yeni sezonda sıfırlanır
## - görevler: süre >= ASSIGN_WEEKS[0] (sezon başında), ülke içinde ulaşılabilir aday var
##   (ya da çıta prestije göre izin verilen tabana inmiş)
## - kovulma: itibar 0 ve rep_start 0 iken kovulur (eski kural imkânsızdı); iyi itibarda kovulmaz
## - sezon sonu teklifleri en fazla OFFER_STEP_MAX prestij yukarı

func watchdog_sec() -> float:
	return 600.0

func run_check() -> void:
	Game.new_game("T", "tr")
	var offers: Array = Game.job_offers_start()
	if not check(not offers.is_empty(), "başlangıç teklifi yok"):
		return
	# en prestijli yerli kulübe gir: görevlerin ulaşılabilirliği en zor burada
	var top := ""
	for cid: String in Game.s.clubs:
		if Game.club_country(cid) == "TR" and not Game.is_scout_club(cid) and (top == "" or int(Game.club(cid).prestige) > int(Game.club(top).prestige)):
			top = cid
	Game.take_job(top)
	log_info("kulüp %s prestij %d" % [Game.my_club().short, int(Game.my_club().prestige)])
	_check_assignments()
	_check_my_find()
	_check_hl_cap()
	_check_fire_and_offers()

func _cands(a: Dictionary) -> int:
	var me := Game.my_club()
	var extra := 20 if a.kind == "prospect" else (34 if a.kind == "wonderkid" else 0)
	var n := 0
	for pid: String in Game.s.players:
		var p: Dictionary = Game.s.players[pid]
		if p.club == "" or p.club == me.id or Game.is_lazy(p.club) or (not Game.visible(p) and a.kind != "wonderkid"):
			continue
		if Data.POS_GROUP[p.pos] != Data.POS_GROUP[a.pos] or int(p.age) > int(a.max_age):
			continue
		if Game.club_country(p.club) != Game.club_country(me.id):
			continue
		var fee := Game.est_fee(pid)
		if fee > int(float(a.max_value) * 1.15) or fee > int(me.budget):
			continue
		if (int(p.pa) - extra if extra > 0 else int(p.ovr)) >= int(a.min_ovr):
			n += 1
	return n

func _check_assignments() -> void:
	Game.s.assign = []
	Game.make_assignments(12)
	var ok := 0
	for a: Dictionary in Game.s.assign:
		check(int(a.deadline) - int(Game.s.week) >= int(Game.ASSIGN_WEEKS[0]), "görev süresi kısa: %s" % str(a))
		var n := _cands(a)
		if n >= Game.ASSIGN_MIN_CANDS:
			ok += 1
		log_info("görev %s %s min_ovr %d aday %d" % [a.kind, a.pos, int(a.min_ovr), n])
	# esneme tabanı bazı görevleri hâlâ zor bırakabilir; çoğu ulaşılabilir olmalı
	check(ok >= int(Game.s.assign.size() * 0.75), "ulaşılabilir görev az: %d/%d" % [ok, Game.s.assign.size()])
	Game.s.assign = []
	Game.make_assignments(3)
	_check_extend()

func _check_extend() -> void:
	## süre dolarken izlenen uygun aday varsa bir kez uzar; yoksa düşer
	var a: Dictionary = Game.s.assign[0]
	a.max_value = 900000000
	a.max_age = 40
	var saved_know: Dictionary = Game.s.scout.knowledge.duplicate(true)
	Game.s.scout.knowledge = {}
	Game.s.week = 10
	a.deadline = 9
	check(not Game._assign_extend(a), "aday yokken görev uzadı")
	var cand := ""
	for pid: String in Game.s.players:
		var p: Dictionary = Game.s.players[pid]
		if p.club != "" and p.club != Game.s.scout.club_id and Data.POS_GROUP[p.pos] == Data.POS_GROUP[a.pos] and Game.fee_ok(pid, a.id) == "":
			cand = pid
			break
	if check(cand != "", "uzatma testi için aday yok"):
		Game.know(cand).seen = 1
		check(Game._assign_extend(a), "izlenen aday varken görev uzamadı")
		check(int(a.deadline) == 10 + Game.ASSIGN_EXTEND, "uzatma süresi yanlış")
		check(not Game._assign_extend(a), "görev ikinci kez uzadı")
	Game.s.scout.knowledge = saved_know
	Game.s.week = 0
	Game.s.assign = []
	Game.make_assignments(3)

func _pick_free(n: int) -> Array:
	var out := []
	for pid: String in Game.s.players:
		var p: Dictionary = Game.s.players[pid]
		if p.club != "" and p.club != Game.s.scout.club_id and not p.get("youth", false) and Game.discovery(pid).is_empty():
			out.append(pid)
			if out.size() >= n:
				break
	return out

func _check_my_find() -> void:
	var ps := _pick_free(7)
	Game.log_discovery(ps[0], "match")
	Game.log_discovery(ps[1], "staff", "X")
	Game.log_discovery(ps[2], "tip")
	Game.log_discovery(ps[3], "agent")
	Game.log_discovery(ps[4], "trip", "TR")
	check(not Game.is_my_find(ps[0]), "odaklı izleme keşif sayıldı")
	check(not Game.is_my_find(ps[1]), "ekip keşfi senin keşfin sayıldı")
	check(not Game.is_my_find(ps[2]), "ihbar senin keşfin sayıldı")
	check(not Game.is_my_find(ps[3]), "menajer ipucu senin keşfin sayıldı")
	check(Game.is_my_find(ps[4]), "gezi keşfi sayılmadı")
	# maçta görülüp sonra raporlanan: rapor sayılır
	Game.submit_report(ps[0], "", 2.5, 3.0, "monitor", [])
	check(Game.is_my_find(ps[0]), "rapor yazılan oyuncu keşif sayılmadı")
	# u19: yalnız odakla izlendiyse
	Game.log_discovery(ps[5], "u19")
	Game.s.scout.knowledge.erase(ps[5])
	check(not Game.is_my_find(ps[5]), "odaksız U19 oyuncusu keşif sayıldı")
	Game.know(ps[5]).seen = 1
	check(Game.is_my_find(ps[5]), "odakla izlenen U19 keşif sayılmadı")
	var pids: Array = Game._my_find_pids()
	check(ps[0] in pids and ps[4] in pids and ps[5] in pids, "_my_find_pids eksik")
	check(not (ps[1] in pids) and not (ps[2] in pids) and not (ps[3] in pids), "_my_find_pids fazla")

func _check_hl_cap() -> void:
	var ps := _pick_free(20)
	Game.s.scout.rep = 30.0
	var r0 := float(Game.s.scout.rep)
	for pid: String in ps:
		Game._headline("star", pid, ["X", "8.0"])
	var gain := float(Game.s.scout.rep) - r0
	check(gain <= Game.HL_REP_CAP + 0.001, "manşet itibarı tavanı aştı: +%.2f" % gain)
	check(gain >= Game.HL_REP_CAP - 0.001, "20 manşet tavanı doldurmadı: +%.2f" % gain)
	check(absf(Game.hl_rep_season() - gain) < 0.001, "hl_rep_season tutarsız")
	check_num(Game.s.scout.hl_rep, "hl_rep", 0.0, Game.HL_REP_CAP)
	# yeni sezon: tavan sıfırlanır
	Game.s.season = int(Game.s.season) + 1
	var r1 := float(Game.s.scout.rep)
	Game._headline("star", ps[0], ["X", "8.0"])
	check(float(Game.s.scout.rep) > r1, "yeni sezonda manşet itibarı gelmedi")
	Game.s.season = int(Game.s.season) - 1
	Game.s.scout["hl_rep_season"] = -1

func _check_fire_and_offers() -> void:
	Game.save_game()
	var snap := FileAccess.get_file_as_string(Game.SAVE_PATH)
	# 1) itibar 0, rep_start 0, çalışkan (rapor var): kovulmalı
	Game.s.scout.rep = 0.0
	Game.s.scout["rep_start"] = 0.0
	Game.s.scout["season_reports"] = 3
	Game.s.scout["season_watched"] = 20
	Game._season_end()
	check(bool(Game.s.season_summary.get("fired", false)), "itibar 0'da kovulmadı (rep_start 0)")
	check_scout_state("kovulma sonrası")
	# 2) yeniden yükle, iyi itibar: kovulmaz; teklifler en fazla OFFER_STEP_MAX yukarı
	Game.load_game()
	var mine_p := int(Game.my_club().prestige)
	Game.s.scout.rep = 70.0
	Game.s.scout["rep_start"] = 60.0
	Game.s.scout["season_reports"] = 3
	Game.s.scout["season_watched"] = 20
	# daha düşük prestijli kulübe geçip teklif aralığını test et
	var low := ""
	for cid: String in Game.s.clubs:
		if Game.club_country(cid) == "TR" and not Game.is_scout_club(cid) and int(Game.club(cid).prestige) <= 45 and not Game.is_lazy(cid):
			low = cid
			break
	if low != "":
		Game.s.scout.club_id = low
		mine_p = int(Game.club(low).prestige)
	Game._season_end()
	check(not bool(Game.s.season_summary.get("fired", false)), "iyi itibarda kovuldu")
	for cid: Variant in Game.s.offers:
		check(int(Game.club(str(cid)).prestige) <= mine_p + Game.OFFER_STEP_MAX, "teklif prestij basamağı büyük: %d -> %d" % [mine_p, int(Game.club(str(cid)).prestige)])
	log_info("teklifler (%d'den): %s" % [mine_p, str(Game.s.offers.map(func(c): return int(Game.club(str(c)).prestige)))])
	check(snap.length() > 0, "kayıt boş")
	check_save_roundtrip("ilerleme sonu")
