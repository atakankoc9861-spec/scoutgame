extends "res://tests/check/check_base.gd"
## season_t.gd senaryosunun assert'li hâli:
## - Tam bir sezon end_week_auto ile tamamlanıyor, sezon devri (season+1, week 0) oluyor
## - Her hafta: para/itibar/bütçe NaN değil, eksi değil
## - Hafta 17 ve 34'te: oynanan maçlar ile puan tablosu tutarlı (P, G/B/M, puan, gol dengesi)
## - Ayrıntılı kulüplerde kadro asgarisi, oyuncu sayılarında NaN yok
## - Sezon özeti dolu, kovulduysa teklif var; ikinci sezona 3 hafta devam ediliyor
## - Sezon sonunda kaydet→yükle→kaydet aynı

const EXTRA_WEEKS: int = 3

func run_check() -> void:
	Game.new_game("T", "tr")
	var offers: Array = Game.job_offers_start()
	if not check(not offers.is_empty(), "başlangıç teklifi yok"):
		return
	Game.take_job(str(offers[0]))
	check(str(Game.s.scout.club_id) != "", "take_job sonrası kulüp yok")
	check_num(Game.s.scout.budget, "başlangıç bütçe", 1.0)
	check_scout_state("başlangıç")
	var s0: int = int(Game.s.season)
	var weeks: int = 0
	var t0: int = Time.get_ticks_msec()
	var max_week_ms: int = 0
	while int(Game.s.season) == s0 and weeks < Game.WEEKS + 5:
		var wt: int = Time.get_ticks_msec()
		var w_before: int = int(Game.s.week)
		Game.end_week_auto()
		weeks += 1
		max_week_ms = maxi(max_week_ms, Time.get_ticks_msec() - wt)
		var tag: String = "s%d w%d" % [s0, w_before]
		check_scout_state(tag)
		if int(Game.s.season) == s0:
			check(int(Game.s.week) == w_before + 1, "%s hafta ilerlemedi (%d)" % [tag, int(Game.s.week)])
			if int(Game.s.week) == 17 or int(Game.s.week) == Game.WEEKS:
				# s.week = W iken 1..W-1 turları oynanmış olmalı
				check_tables(tag, int(Game.s.week) - 1)
				check_world(tag)
	var ms: int = Time.get_ticks_msec() - t0
	log_info("sezon %d: %d hafta, %d ms (hafta ort %d ms, en uzun %d ms)" % [s0, weeks, ms, ms / maxi(1, weeks), max_week_ms])
	check(int(Game.s.season) == s0 + 1, "sezon bitmedi: season=%d (%d hafta oynandı)" % [int(Game.s.season), weeks])
	check(weeks == Game.WEEKS + 1, "sezon %d haftada bitti, beklenen %d" % [weeks, Game.WEEKS + 1])
	check(int(Game.s.week) == 0, "yeni sezon week=0 değil")
	var sm: Dictionary = Game.s.season_summary
	check(int(sm.get("season", -1)) == s0, "sezon özeti yanlış sezon")
	check(Game.s.clubs.has(str(sm.get("champ", ""))), "şampiyon geçerli kulüp değil")
	check(sm.has("rep_after") and sm.has("fired"), "sezon özeti eksik alan")
	check(not Game.s.fixtures.is_empty() and Game.s.fixtures.size() == Game.s.table.size(), "yeni sezon fikstürü yok")
	for lg: Variant in Game.s.table:
		for cid: Variant in Game.s.table[lg]:
			if int(Game.s.table[lg][cid].p) != 0:
				check(false, "yeni sezon tablosu sıfırlanmadı: %s" % str(lg))
				break
	check_scout_state("sezon sonu")
	log_info("sezon sonu: rep %.1f money %s fired %s offers %d" % [float(Game.s.scout.rep), str(Game.s.scout.money), str(sm.get("fired")), Game.s.offers.size()])
	if bool(sm.get("fired", false)):
		check(not Game.s.offers.is_empty(), "kovuldu ama teklif yok")
		if not Game.s.offers.is_empty():
			Game.take_job(str(Game.s.offers[0]))
	check_save_roundtrip("sezon sonu")
	for i: int in EXTRA_WEEKS:
		Game.end_week_auto()
		check_scout_state("s%d w%d" % [s0 + 1, i])
	check(int(Game.s.season) == s0 + 1 and int(Game.s.week) == EXTRA_WEEKS, "ikinci sezon ilerlemedi")
	check_world("ikinci sezon")

## Tablo tutarlılığı: ilk `upto` haftanın tüm maçları oynanmış, tablo bunlarla birebir uyumlu
func check_tables(tag: String, upto: int) -> void:
	var bad_leagues: int = 0
	for lg: Variant in Game.s.fixtures:
		var exp: Dictionary = {}
		var unplayed: int = 0
		for w: int in range(1, upto + 1):
			var r: int = Game.round_for_week(str(lg), w)
			if r < 0:
				continue
			for m: Dictionary in Game.s.fixtures[lg][r]:
				var gh: int = int(m.gh)
				var ga: int = int(m.ga)
				if gh < 0 or ga < 0:
					unplayed += 1
					continue
				for side: Array in [[m.h, gh, ga], [m.a, ga, gh]]:
					var e: Dictionary = exp.get(side[0], {"p": 0, "pts": 0, "gf": 0, "ga": 0})
					e.p += 1
					e.gf += int(side[1])
					e.ga += int(side[2])
					e.pts += 3 if int(side[1]) > int(side[2]) else (1 if side[1] == side[2] else 0)
					exp[side[0]] = e
		var ok: bool = check(unplayed == 0, "%s %s: %d maç oynanmadı" % [tag, str(lg), unplayed])
		var tb: Dictionary = Game.s.table.get(lg, {})
		for cid: Variant in tb:
			var t: Dictionary = tb[cid]
			var e: Dictionary = exp.get(cid, {"p": 0, "pts": 0, "gf": 0, "ga": 0})
			if int(t.p) != int(e.p) or int(t.pts) != int(e.pts) or int(t.gf) != int(e.gf) or int(t.ga) != int(e.ga) \
					or int(t.w) + int(t.d) + int(t.l) != int(t.p) or int(t.pts) != 3 * int(t.w) + int(t.d):
				ok = check(false, "%s %s tablo/fikstür uyumsuz: %s tablo=%s beklenen=%s" % [tag, str(lg), str(cid), str(t), str(e)])
				break
		if not ok:
			bad_leagues += 1
	check(bad_leagues == 0, "%s %d ligde tablo hatası" % [tag, bad_leagues])

## Ayrıntılı kulüplerin kadroları ve oyuncu sayıları
func check_world(tag: String) -> void:
	var small: int = 0
	var missing: int = 0
	for cid: Variant in Game.s.clubs:
		if Game.is_lazy(str(cid)) or Game.is_scout_club(str(cid)):
			continue
		var sq: Array = Game.club(str(cid)).squad
		if sq.size() < 16:
			small += 1
		for pid: Variant in sq:
			if Game.player(str(pid)).is_empty():
				missing += 1
	check(small == 0, "%s %d kulübün kadrosu 16'dan az" % [tag, small])
	check(missing == 0, "%s kadrolarda %d kayıp oyuncu kimliği" % [tag, missing])
	var badnum: int = 0
	for pid: Variant in Game.s.players:
		var p: Dictionary = Game.s.players[pid]
		for k: String in ["ovr", "pa", "value", "age"]:
			var v: float = float(p.get(k, NAN))
			if not is_finite(v) or v < 0.0:
				badnum += 1
				if badnum <= 3:
					check(false, "%s oyuncu %s %s=%s" % [tag, str(pid), k, str(p.get(k))])
	check(badnum == 0, "%s %d oyuncu alanında NaN/eksi" % [tag, badnum])
