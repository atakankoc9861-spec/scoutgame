extends "res://tests/check/check_base.gd"
## quick.gd + v22_t.gd senaryolarının assert'li hâli (oyuncu isimlerine bakmaz):
## - Dünya üretimi: oyuncu/kulüp var, simüle edilen her ligde fikstür ve tablo var
##   (eski quick.gd, world.json'da olmayan "BAL1" ligine [0] ile eriştiği için SCRIPT ERROR
##   verip quit()'e hiç ulaşmıyordu → headless'ta sonsuza kadar asılı kalıyordu.)
## - İşe gir, ekip kur, bölge ata
## - Her hafta: bir maç planla (canlı motor yolu), 3 oyuncuya odaklan, end_week_auto
## - Yurtdışı maç planı/yolculuk
## - v0.22: efsaneler, söylentiler, hayat satın alımları, gözlem → efsane bulma, seri
## - Her adımda para/itibar NaN değil, eksi değil; sonunda kaydet→yükle→kaydet aynı
## - İkinci başlangıç ülkesi (EN) ile kısa tur

const WEEKS_TO_PLAY: int = 8

func run_check() -> void:
	_career_tr()
	_start_other_country("EN", "en")

func _career_tr() -> void:
	var t0: int = Time.get_ticks_msec()
	Game.new_game("T", "tr")
	log_info("new_game TR: %d oyuncu, %d kulüp, %d ms" % [Game.s.players.size(), Game.s.clubs.size(), Time.get_ticks_msec() - t0])
	check(Game.s.players.size() > 500, "oyuncu sayısı çok az: %d" % Game.s.players.size())
	check(Game.s.clubs.size() > 100, "kulüp sayısı çok az: %d" % Game.s.clubs.size())
	var no_fx: PackedStringArray = []
	for lg: Variant in Game.LEAGUES:
		var n: int = Game.league_clubs(str(lg)).size()
		# make_fixtures: çift devreli, devre başına n-1 tur
		if n >= 2 and (Game.league_round_count(str(lg)) != 2 * (n - 1) or not Game.s.table.has(lg)):
			no_fx.append(str(lg))
	check(no_fx.is_empty(), "fikstür/tur sayısı hatalı ligler: %s" % ", ".join(no_fx))
	check_scout_state("yeni oyun")
	var offers: Array = Game.job_offers_start()
	if not check(not offers.is_empty(), "başlangıç teklifi yok"):
		return
	Game.take_job(str(offers[0]))
	check_scout_state("işe giriş")
	check(Game.s.assign.size() > 0, "işe girişte görev verilmedi")
	check(Game.s.legends.size() > 0, "efsane tohumlanmadı")

	# ekip
	Game.refresh_staff_pool(true)
	check(Game.s.staff_pool.size() == 6, "ekip havuzu 6 değil: %d" % Game.s.staff_pool.size())
	Game.s.scout.rep = 60.0
	var hired: int = 0
	for i: int in 3:
		if Game.s.staff_pool.is_empty():
			break
		if Game.hire_staff(str(Game.s.staff_pool[0].id)) == "staff_hired":
			hired += 1
	check(hired >= 1, "hiç ekip üyesi işe alınamadı")
	var regs: Array = Game.regions()
	for i: int in Game.s.staff.size():
		Game.assign_staff(str(Game.s.staff[i].id), str(regs[i % regs.size()]))
	for m: Dictionary in Game.s.staff:
		check_num(m.get("salary"), "ekip maaşı", 1.0)

	# hafta 0 -> 1
	Game.finish_week()
	check(int(Game.s.week) == 1, "finish_week hafta 1'e geçmedi")
	check_scout_state("hafta 1")

	# yurtdışı maç planı (sadece planla; plan geri alınır, hata vermemeli)
	var abroad_key: String = _find_abroad_match()
	if abroad_key != "":
		var ok: bool = Game.plan_match("sat", abroad_key)
		log_info("yurtdışı plan %s -> %s" % [abroad_key, str(ok)])
		if ok:
			check(str(Game.s.plan.get("travel_sat", "")) != "", "yurtdışı planda yolculuk günü ayrılmadı")
		Game.plan_match("sat", "")
		check(str(Game.s.plan.get("travel_sat", "")) == "", "plan geri alınınca yolculuk günü kalktı mı")

	var rumors: int = 0
	var watched0: int = int(Game.s.scout.stats.watched)
	var know0: int = Game.s.scout.knowledge.size()
	var weeks_ms: Array[int] = []
	for w: int in WEEKS_TO_PLAY:
		Game.s.events = []
		var planned: String = _plan_home_match()
		var wt: int = Time.get_ticks_msec()
		var res: Dictionary = Game.end_week_auto()
		weeks_ms.append(Time.get_ticks_msec() - wt)
		check(res.has("obs"), "end_week_auto sonucu 'obs' yok")
		if planned != "":
			_check_played(planned, int(Game.s.week) - 1)
		for e: Dictionary in Game.s.events:
			if str(e.get("kind", "")) == "rumor":
				rumors += 1
		check_scout_state("hafta %d" % int(Game.s.week))
	log_info("%d hafta: ms %s, söylenti %d, izlenen +%d, bilgi +%d" % [WEEKS_TO_PLAY, str(weeks_ms), rumors, int(Game.s.scout.stats.watched) - watched0, Game.s.scout.knowledge.size() - know0])
	check(rumors >= 1, "%d haftada hiç söylenti yok" % WEEKS_TO_PLAY)
	check(Game.s.scout.knowledge.size() > know0, "maç izleyip hiç bilgi edinilmedi")
	check_num(Game.s.scout.spent, "harcama", 0.0)

	# hayat satın alımları
	Game.s.scout.money = 50000
	for kind: String in ["home", "car", "suit"]:
		var m0: int = int(Game.s.scout.money)
		var price: int = Game.life_price(kind, int(Game.s.life.get(kind, 0)) + 1)
		check(Game.life_buy(kind), "life_buy(%s) başarısız" % kind)
		check(int(Game.s.scout.money) == m0 - price, "life_buy(%s) parayı doğru düşmedi" % kind)
	Game.s.scout.money = 10
	check(not Game.life_buy("car"), "para yetmezken life_buy başarılı oldu")
	check(int(Game.s.scout.money) == 10, "başarısız life_buy parayı değiştirdi")
	check_scout_state("hayat")

	# efsane bulma
	var hidden: Array = Game.s.legends.filter(func(l: Dictionary) -> bool: return str(l.state) == "hidden")
	if check(not hidden.is_empty(), "gizli efsane kalmadı"):
		var lg0: Dictionary = hidden[0]
		var rep0: float = float(Game.s.scout.rep)
		Game.observe(str(lg0.pid), 0.2, ["tec"], 1.0)
		check(str(lg0.state) == "found", "gözlem efsaneyi bulmadı (state=%s)" % str(lg0.state))
		check(str(lg0.pid) in Game.s.legend_pop, "bulunan efsane legend_pop'ta yok")
		check(float(Game.s.scout.rep) >= rep0, "efsane bulmak itibarı düşürdü")
	check(Game.eye_streak(true) == 1 and Game.eye_streak(true) == 2 and Game.eye_streak(false) == 0, "eye_streak sayacı yanlış")
	check_scout_state("efsane")

	# birkaç hafta daha (kira, hayat haftası) ve kayıt turu
	Game.s.scout.money = 0
	for i: int in 2:
		Game.end_week_auto()
		check_scout_state("parasız hafta %d" % i)
	check_save_roundtrip("kariyer TR")
	Game.end_week_auto()
	check_scout_state("yüklemeden sonra hafta")

func _start_other_country(cc: String, lang: String) -> void:
	if not Data.COUNTRIES.has(cc) or Data.is_scout_cc(cc):
		log_info("başlangıç ülkesi %s yok, atlandı" % cc)
		return
	var t0: int = Time.get_ticks_msec()
	Game.new_game("T", lang, cc)
	check(str(Game.s.start_cc) == cc, "start_cc %s değil" % cc)
	var offers: Array = Game.job_offers_start()
	if not check(not offers.is_empty(), "%s başlangıç teklifi yok" % cc):
		return
	Game.take_job(str(offers[0]))
	check(Game.club_country(str(Game.s.scout.club_id)) == cc, "%s teklifi başka ülkeden" % cc)
	for i: int in 3:
		_plan_home_match()
		Game.end_week_auto()
		check_scout_state("%s hafta %d" % [cc, int(Game.s.week)])
	check_save_roundtrip("kariyer " + cc)
	log_info("%s başlangıcı: %d ms" % [cc, Time.get_ticks_msec() - t0])

## Bu haftanın, kendi ülkendeki bir maçını cumartesi/pazar için planla, 3 oyuncuya odaklan
func _plan_home_match() -> String:
	var mc: String = Game.my_country()
	for wm: Dictionary in Game.week_matches():
		if Game.league_country(str(wm.lg)) != mc or int(wm.m.gh) >= 0:
			continue
		var day: String = str(wm.m.day)
		var key: String = Game.match_key(str(wm.lg), int(wm.idx))
		if Game.match_abroad(key) or not Game.plan_match(day, key):
			continue
		var sq: Array = Game.club(str(wm.m.h)).squad + Game.club(str(wm.m.a)).squad
		for i: int in mini(3, sq.size()):
			Game.toggle_focus(day, str(sq[i * 5 % sq.size()]))
		return "%s|%s|%d" % [day, wm.lg, int(wm.idx)]
	return ""

func _check_played(planned: String, week: int) -> void:
	var parts: PackedStringArray = planned.split("|")
	var lg: String = parts[1]
	var r: int = Game.round_for_week(lg, week)
	if not check(r >= 0, "planlı maçın turu bulunamadı"):
		return
	var m: Dictionary = Game.s.fixtures[lg][r][int(parts[2])]
	check(int(m.gh) >= 0 and int(m.ga) >= 0, "planlı (canlı motor) maç oynanmadı: %s" % planned)
	check(int(m.gh) <= 15 and int(m.ga) <= 15, "planlı maç skoru anormal: %d-%d" % [int(m.gh), int(m.ga)])

func _find_abroad_match() -> String:
	for wm: Dictionary in Game.week_matches():
		var key: String = Game.match_key(str(wm.lg), int(wm.idx))
		if Game.match_abroad(key):
			return key
	return ""
