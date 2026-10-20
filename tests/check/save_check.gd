extends "res://tests/check/check_base.gd"
## v0.23 Dalga 2-E: kayıt göçü ve kayıt sağlamlığı.
## - tests/fixtures/ altındaki eski sürüm kayıtları (v4: v0.18, v5: v0.19 ve v0.22-b4) açılıyor;
##   para/itibar/sezon/hafta aynı, hiçbir oyuncu kaybolmuyor, 1 hafta hatasız ilerliyor,
##   sonra kaydet→yükle→kaydet birebir aynı.
## - Yeni oyun: kaydet→yükle→kaydet ilk turda da birebir aynı (load_game artık kadro doldurmuyor).
## - s.sim_seed: yeni oyunda üretiliyor, rng akışını değiştirmiyor, eski kayıtta göçle ekleniyor.
## - NaN/inf: kaydetmeden önce güvenli değere çekiliyor, bozuk (nan/inf yazılmış) kayıt onarılarak açılıyor.
## - v3 ve öncesi: "eski kayıt" (old_save), daha yeni sürüm: reddedilir.
## Fixture'lar gzip'li JSON; oyuncu/hoca adları nötrleştirilmiştir (gerçek isim yok).

const FIXTURES: Array[String] = ["save_v4_v018", "save_v5_v019", "save_v5_v022"]

func watchdog_sec() -> float:
	return 600.0

func run_check() -> void:
	_check_new_game_strict()
	_check_sim_seed()
	_check_nan_on_save()
	_check_nan_in_file()
	_check_versions()
	for fx: String in FIXTURES:
		_check_fixture(fx)

# ---------------------------------------------------------------- yardımcılar

func _fixture_text(fx: String) -> String:
	var raw: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/%s.json.gz" % fx)
	if raw.is_empty():
		return ""
	var bytes: PackedByteArray = raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	return bytes.get_string_from_utf8()

func _write_save(txt: String) -> void:
	var f: FileAccess = FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string(txt)
	f.close()

## fill_squad'ın ekleyeceği oyuncu sayısı (durumu değiştirmeden; Game.SQUAD_MIN/POS_MIN kuralı)
func _squad_deficit() -> Dictionary:
	var clubs: int = 0
	var players: int = 0
	for cid: Variant in Game.s.clubs:
		if Game.is_lazy(str(cid)):
			continue
		var c: Dictionary = Game.s.clubs[cid]
		var cnt: Dictionary = {}
		for pid: Variant in c.squad:
			var p: Dictionary = Game.player(str(pid))
			if not p.is_empty():
				cnt[p.pos] = int(cnt.get(p.pos, 0)) + 1
		var need: int = 0
		for pos: Variant in Game.POS_MIN:
			need += maxi(0, int(Game.POS_MIN[pos]) - int(cnt.get(pos, 0)))
		need = maxi(need, int(Game.SQUAD_MIN.get(Game.tier(str(c.league)), 20)) - c.squad.size())
		if need > 0:
			clubs += 1
			players += need
	return {"clubs": clubs, "players": players}

# ---------------------------------------------------------------- yeni oyun

func _check_new_game_strict() -> void:
	Game.new_game("T", "tr")
	var offers: Array = Game.job_offers_start()
	if not check(not offers.is_empty(), "başlangıç teklifi yok"):
		return
	Game.take_job(str(offers[0]))
	Game.finish_week()
	for i: int in 4:
		Game.end_week_auto()
	var def: Dictionary = _squad_deficit()
	log_info("yeni oyun hafta %d: asgari kadronun altında %d kulüp (%d eksik oyuncu) — yükleme bunları artık değiştirmemeli" % [int(Game.s.week), int(def.clubs), int(def.players)])
	var added: int = check_save_roundtrip("yeni oyun")
	check(added == 0, "load_game() ilk yüklemede %d oyuncu ekledi (kayıt değişti)" % added)
	Game.end_week_auto()
	check_scout_state("yeni oyun yüklendikten sonra hafta")

func _check_sim_seed() -> void:
	Game.rng.seed = 777
	Game.new_game("S", "tr")
	var a: Variant = Game.s.get("sim_seed")
	var st_a: int = Game.rng.state
	Game.rng.seed = 777
	Game.new_game("S", "tr")
	var b: Variant = Game.s.get("sim_seed")
	check(typeof(a) == TYPE_INT and int(a) != 0, "new_game sim_seed üretmedi: %s" % str(a))
	check(a == b, "aynı tohumla sim_seed farklı: %s vs %s" % [str(a), str(b)])
	check(Game.rng.state == st_a, "aynı tohumla new_game sonrası rng durumu farklı")
	var st0: int = Game.rng.state
	Game._new_sim_seed()
	check(Game.rng.state == st0, "_new_sim_seed rng akışını ilerletti (dünya üretimi değişir)")
	Game.rng.seed = 778
	Game.new_game("S", "tr")
	check(Game.s.sim_seed != a, "farklı tohumla aynı sim_seed")
	Game.save_game()
	var seed_before: int = int(Game.s.sim_seed)
	check(Game.load_game(), "sim_seed: load_game false")
	check(typeof(Game.s.sim_seed) == TYPE_INT and int(Game.s.sim_seed) == seed_before, "sim_seed yükleme sonrası int/aynı değil")
	# alanı olmayan kayıt: has() ile üretilir, deterministik
	Game.s.erase("sim_seed")
	Game.save_game()
	check(Game.load_game(), "sim_seed'siz kayıt yüklenmedi")
	var m1: Variant = Game.s.get("sim_seed")
	Game.s.erase("sim_seed")
	Game.save_game()
	Game.load_game()
	check(typeof(m1) == TYPE_INT and int(m1) != 0 and m1 == Game.s.get("sim_seed"), "eksik sim_seed deterministik üretilmedi: %s / %s" % [str(m1), str(Game.s.get("sim_seed"))])
	Game.rng.randomize()

# ---------------------------------------------------------------- NaN / inf

func _check_nan_on_save() -> void:
	Game.new_game("N", "tr")
	var offers: Array = Game.job_offers_start()
	Game.take_job(str(offers[0]))
	var sc: Dictionary = Game.s.scout
	var rep_start: float = float(sc.rep_start)
	var cid: String = str(sc.club_id)
	var some_pid: String = str(Game.club(cid).squad[0])
	sc.money = NAN
	sc.rep = INF
	sc.budget = -INF
	sc.spent = NAN
	sc.arep["west"] = NAN
	Game.s.life.rel.press = NAN
	Game.club(cid).budget = NAN
	Game.player(some_pid).st.rs = NAN   # bilinmeyen alan: ikinci kat koruma 0 yazmalı
	Game.save_game()
	var txt: String = FileAccess.get_file_as_string(Game.SAVE_PATH)
	check(_parse_json(txt) is Dictionary, "NaN'lı durum kaydedilince geçersiz JSON yazıldı")
	check(int(sc.money) == 0 and typeof(sc.money) == TYPE_INT, "NaN para 0'a çekilmedi: %s" % str(sc.money))
	check(is_equal_approx(float(sc.rep), rep_start), "inf itibar rep_start'a çekilmedi: %s" % str(sc.rep))
	check(int(sc.budget) == 0 and int(sc.spent) == 0, "bütçe/harcama onarılmadı: %s / %s" % [str(sc.budget), str(sc.spent)])
	check(float(sc.arep.west) == 0.0, "arep NaN onarılmadı")
	check(float(Game.s.life.rel.press) == 50.0, "life.rel NaN onarılmadı")
	check_num(Game.club(cid).budget, "kulüp bütçesi (kayıttan sonra)", 1.0)
	check(Game.load_game(), "NaN onarımlı kayıt yüklenmedi")
	check_scout_state("NaN kayıt sonrası")
	check_num(Game.player(some_pid).st.rs, "oyuncu st.rs (ikinci kat)", 0.0, 0.0)

func _check_nan_in_file() -> void:
	## Eski sürümün yazdığı bozuk kayıt: "money":nan, "rep":inf -> yükleme reddetmez, onarır
	Game.new_game("B", "tr")
	var offers: Array = Game.job_offers_start()
	Game.take_job(str(offers[0]))
	Game.finish_week()
	var rep_start: float = float(Game.s.scout.rep_start)
	var week: int = int(Game.s.week)
	# işaret değerleri: kayıt metninde tam olarak bulunup nan/inf ile değiştirilir
	Game.s.scout.money = 987654321
	Game.s.scout.rep = 12.375
	var pid0: String = str(Game.my_club().squad[0])
	Game.player(pid0).st.rs = 4.625
	Game.save_game()
	var txt: String = FileAccess.get_file_as_string(Game.SAVE_PATH)
	check(txt.count("\"money\":987654321") == 1 and txt.count("\"rep\":12.375") == 1 and txt.count("\"rs\":4.625") == 1, "işaret değerleri kayıtta bulunamadı (test hatası)")
	var bad: String = txt.replace("\"money\":987654321", "\"money\":nan").replace("\"rep\":12.375", "\"rep\":inf").replace("\"rs\":4.625", "\"rs\":-inf")
	check(bad != txt and _parse_json(bad) == null, "bozuk kayıt metni hazırlanamadı (test hatası)")
	_write_save(bad)
	check(Game.load_game(), "nan/inf içeren kayıt reddedildi (onarılmalıydı)")
	check(int(Game.s.week) == week, "onarılan kayıtta hafta değişti")
	check(int(Game.s.scout.money) == 0, "onarılan kayıtta para 0 değil: %s" % str(Game.s.scout.money))
	check(is_equal_approx(float(Game.s.scout.rep), rep_start), "onarılan kayıtta itibar rep_start değil: %s" % str(Game.s.scout.rep))
	check_scout_state("bozuk kayıt onarıldı")
	Game.end_week_auto()
	check_scout_state("bozuk kayıttan sonra hafta")
	Game.save_game()
	check(_parse_json(FileAccess.get_file_as_string(Game.SAVE_PATH)) is Dictionary, "onarımdan sonraki kayıt geçersiz JSON")

func _check_versions() -> void:
	_write_save(JSON.stringify({"version": 3, "scout": {}}))
	Game.old_save = false
	check(not Game.load_game(), "v3 kayıt yüklendi (reddedilmeliydi)")
	check(Game.old_save, "v3 kayıtta old_save işareti yok")
	Game.old_save = false
	_write_save(JSON.stringify({"version": Game.SAVE_VERSION + 1, "scout": {}}))
	check(not Game.load_game(), "gelecek sürüm kayıt yüklendi")
	check(not Game.old_save, "gelecek sürüm kayıt old_save sayıldı")
	_write_save("{bozuk")
	check(not Game.load_game(), "çözülemeyen kayıt true döndü")

# ---------------------------------------------------------------- eski sürüm kayıtları

func _check_fixture(fx: String) -> void:
	var t0: int = Time.get_ticks_msec()
	var txt: String = _fixture_text(fx)
	if not check(txt.length() > 1000, "%s fixture okunamadı" % fx):
		return
	var raw: Variant = _parse_json(txt)
	if not check(raw is Dictionary, "%s fixture JSON değil" % fx):
		return
	var r: Dictionary = raw
	var v0: int = int(r.version)
	_write_save(txt)
	Game.old_save = false
	Game.s = {}
	if not check(Game.load_game(), "%s (v%d) yüklenmedi" % [fx, v0]):
		return
	var tag: String = "%s v%d" % [fx, v0]
	check(int(Game.s.version) == Game.SAVE_VERSION, tag + " göç sonrası sürüm %d" % int(Game.s.version))
	check(not Game.old_save, tag + " old_save işaretlendi")
	check(Game.s.scout.money == int(r.scout.money), "%s para değişti: %s -> %s" % [tag, str(r.scout.money), str(Game.s.scout.money)])
	check(is_equal_approx(float(Game.s.scout.rep), float(r.scout.rep)), "%s itibar değişti" % tag)
	check(int(Game.s.season) == int(r.season) and int(Game.s.week) == int(r.week), tag + " sezon/hafta değişti")
	check(str(Game.s.scout.club_id) == str(r.scout.club_id), tag + " kulüp değişti")
	var lost: Array = []
	var changed: int = 0
	for pid: Variant in r.players:
		if not Game.s.players.has(pid):
			lost.append(pid)
		elif str(Game.s.players[pid].club) != str(r.players[pid].club) or int(Game.s.players[pid].ovr) != int(r.players[pid].ovr):
			changed += 1
	check(lost.is_empty(), "%s yüklemede %d oyuncu kayboldu" % [tag, lost.size()])
	check(changed == 0, "%s yüklemede %d oyuncunun kulübü/ovr'si değişti" % [tag, changed])
	var n0: int = r.players.size()
	var n1: int = Game.s.players.size()
	if v0 == Game.SAVE_VERSION - 1 and r.has("legends_seeded"):
		# güncel biçimdeki v5 (0.22): göç dünyaya hiçbir şey eklememeli
		check(n1 == n0, "%s oyuncu sayısı yüklemede değişti: %d -> %d" % [tag, n0, n1])
	log_info("%s: oyuncu %d -> %d (eski kayıtta efsane tohumlama/onarım eklemeleri), kulüp %d -> %d" % [tag, n0, n1, r.clubs.size(), Game.s.clubs.size()])
	check(typeof(Game.s.get("sim_seed")) == TYPE_INT and int(Game.s.sim_seed) != 0, tag + " sim_seed yok")
	check_scout_state(tag + " yüklendi")
	# dünya yapısı güncel sürümle uyumlu: her simüle ligin fikstürü/tablosu var, fazlası yok
	var bad_lg: PackedStringArray = []
	for lg: Variant in Game.LEAGUES:
		if Game.league_clubs(str(lg)).size() >= 2 and (not Game.s.fixtures.has(lg) or not Game.s.table.has(lg)):
			bad_lg.append(str(lg))
	for lg: Variant in Game.s.fixtures:
		if not Game.LEAGUES.has(lg):
			bad_lg.append("+" + str(lg))
	check(bad_lg.is_empty(), "%s fikstür/tablo uyumsuz ligler: %s" % [tag, ", ".join(bad_lg)])
	var no_lg: int = 0
	for cid: Variant in Game.s.clubs:
		if not Data.LG.has(str(Game.s.clubs[cid].league)):
			no_lg += 1
	check(no_lg == 0, "%s ligi artık olmayan %d kulüp" % [tag, no_lg])
	# 1 hafta
	var w: int = int(Game.s.week)
	Game.end_week_auto()
	check(int(Game.s.week) == w + 1, "%s hafta ilerlemedi" % tag)
	check_scout_state(tag + " +1 hafta")
	check_save_roundtrip(tag)
	log_info("%s: %d ms" % [tag, Time.get_ticks_msec() - t0])
