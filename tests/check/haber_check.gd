extends "res://tests/check/check_base.gd"
## v0.24 Dalga 3A haber özeti + kayıt v7:
## - teklif/görev haberleri (NEWS_PIN_KEYS) 8 hafta akışta kalır, tavan dolsa da düşmez; sonra düşer
## - diğer kulüplerin hoca kovulmaları haftada tek satır (alt satırlar items'ta)
## - evlat haberleri yalnız senin keşiflerinden (is_my_find), haftalık tek özet
## - aynı genç yıldız haberi sezonda bir kez
## - kayıt v7: knowledge/hist dizi olarak yazılır, kaydet->yükle kararlı, dosya küçülür
## - v6 -> v7 göçü: v6 biçimli kayıt açılır, para/itibar/sezon aynı, evlat/keşif kayıtları budanır,
##   senin keşiflerin kalır

func watchdog_sec() -> float:
	return 600.0

func run_check() -> void:
	Game.new_game("T", "tr")
	var offers: Array = Game.job_offers_start()
	if not check(not offers.is_empty(), "başlangıç teklifi yok"):
		return
	Game.take_job(str(offers[0]))
	Game.finish_week()
	for i: int in 3:
		Game.end_week_auto()
	_check_pinned()
	_check_sackings()
	_check_kids()
	_check_young_star()
	_check_save_v7()
	_check_migrate_v6()

func _news_since(head: Variant) -> Array:
	var out: Array = []
	for n: Dictionary in Game.s.news:
		if head != null and is_same(n, head):
			break
		out.append(n)
	return out

func _head() -> Variant:
	return Game.s.news[0] if not Game.s.news.is_empty() else null

# ---------------------------------------------------------------- sabit haberler
func _check_pinned() -> void:
	var w0: int = int(Game.s.week)
	Game.add_news("n_staff_poach", ["Test Kişi"], true, "bad")
	var pin: Dictionary = Game.s.news[0]
	Game.add_news("n_new_assign", [], true, "career")
	var pin2: Dictionary = Game.s.news[0]
	# 8 hafta boyunca her hafta 40 sıradan haber: tavan (160) defalarca dolar
	for wk: int in Game.NEWS_PIN_WEEKS:
		Game.s.week = w0 + wk + 1
		for i: int in 40:
			Game.add_news("n_young_star", ["Dolgu %d" % i, "-", "7.00"], false, "press")
		check(Game.s.news.size() <= Game.NEWS_CAP, "haber tavanı aşıldı: %d" % Game.s.news.size())
		check(Game.s.news.has(pin) and Game.s.news.has(pin2), "teklif/görev haberi %d. haftada akıştan düştü" % (wk + 1))
		check(Game.pinned_news().has(pin), "teklif haberi %d. haftada sabitlerde yok" % (wk + 1))
	# 9. hafta: artık sabit değil, sıradan haber gibi düşer
	Game.s.week = w0 + Game.NEWS_PIN_WEEKS + 1
	check(not Game.news_pinned(pin), "teklif haberi 9. haftada hâlâ sabit")
	for i: int in Game.NEWS_CAP:
		Game.add_news("n_young_star", ["Dolgu2 %d" % i, "-", "7.00"], false, "press")
	check(not Game.s.news.has(pin), "süresi dolan sabit haber düşmedi")
	Game.s.week = w0
	Game.s.news = []

# ---------------------------------------------------------------- kovulmalar
func _check_sackings() -> void:
	# tabloyu prestijin tersine çevir: çok kulüp kovulma eşiğine girer
	for lg: Variant in Game.s.table:
		var order: Array = Game.sorted_table(str(lg))
		var n: int = order.size()
		for i: int in n:
			var cid: String = order[i]
			var tb: Dictionary = Game.s.table[lg][cid]
			tb.pts = int(Game.club(cid).prestige) * -1 + 200
	var head: Variant = _head()
	var before: Dictionary = {}
	for cid: Variant in Game.s.clubs:
		before[cid] = str(Game.s.clubs[cid].get("manager", {}).get("name", ""))
	Game._manager_sackings()
	var sacked: int = 0
	var mine_sacked: bool = false
	for cid: Variant in Game.s.clubs:
		if str(Game.s.clubs[cid].get("manager", {}).get("name", "")) != before[cid]:
			sacked += 1
			if cid == Game.s.scout.club_id:
				mine_sacked = true
	var added: Array = _news_since(head)
	log_info("kovulma: %d kulüp, %d haber" % [sacked, added.size()])
	check(sacked >= 2, "test kurgusu: kovulma olmadı (%d)" % sacked)
	check(added.size() <= (2 if mine_sacked else 1), "kovulmalar tek satıra inmedi: %d haber" % added.size())
	var dig: Array = added.filter(func(n: Dictionary) -> bool: return n.key == "n_sacked_week")
	if sacked - int(mine_sacked) >= 2:
		check(dig.size() == 1, "n_sacked_week özeti yok")
		if not dig.is_empty():
			check(int(dig[0].n_items) == sacked - int(mine_sacked), "özet kovulma sayısı yanlış")
			check(int(dig[0].args[0]) == sacked - int(mine_sacked), "özet argümanı yanlış")
			check((dig[0].items as Array).size() <= Game.NEWS_ITEMS_MAX, "özet alt satırları tavanı aştı")

# ---------------------------------------------------------------- evlatlar
func _pick_players(n: int, exclude: Dictionary) -> Array:
	var out: Array = []
	for pid: Variant in Game.s.players:
		var p: Dictionary = Game.s.players[pid]
		if p.club == "" or p.club == Game.s.scout.club_id or bool(p.youth) or exclude.has(pid) or Game.is_my_find(str(pid)):
			continue
		if Game.discovery(str(pid)).is_empty():
			out.append(str(pid))
			if out.size() >= n:
				break
	return out

func _check_kids() -> void:
	var mine: Array = _pick_players(2, {})
	var ex: Dictionary = {}
	for pid: String in mine:
		ex[pid] = true
	var other: Array = _pick_players(3, ex)
	if not check(mine.size() == 2 and other.size() == 3, "test kurgusu: oyuncu yok"):
		return
	for pid: String in mine:
		Game.log_discovery(pid, "trip")
	for pid: String in other:
		Game.log_discovery(pid, "match")
	for pid: String in mine + other:
		Game.s.players[pid].st.g = 0
	Game.s.kids_feed = []
	Game._kids_week()   # ilk görüş: durum kaydı
	for pid: String in other:
		check(not Game.s.kids_state.has(pid), "maçta görülen oyuncu evlat sayıldı: %s" % pid)
	# hepsi gol atsın
	for pid: String in mine + other:
		Game.s.players[pid].st.g = 1
	var head: Variant = _head()
	Game._kids_week()
	var added: Array = _news_since(head).filter(func(n: Dictionary) -> bool: return n.kind == "kids")
	check(added.size() == 1, "evlat haberleri haftalık teke inmedi: %d" % added.size())
	if not added.is_empty():
		var n: Dictionary = added[0]
		var names: Array = []
		for it: Variant in n.get("items", []):
			if not (str(it[1][0]) in names):
				names.append(str(it[1][0]))
		check(n.key == "n_kids_week" and names.size() == 2 and int(n.n_items) >= 2, "özet 2 evlat içermiyor: %s" % str(n))
		for pid: String in other:
			check(not (Game.pname(Game.player(pid)) in names), "özette senin keşfin olmayan oyuncu var")
	for it: Dictionary in Game.s.kids_feed:
		check(str(it.pid) in mine, "kids_feed'de senin keşfin olmayan oyuncu: %s" % str(it.pid))
	# tek olay: tekil haber (eski anahtar)
	Game.s.players[mine[0]].st.g = 10
	head = _head()
	Game._kids_week()
	added = _news_since(head)
	check(added.size() == 1 and added[0].key == "kf_ten_goals", "tek evlat olayı tekil haber değil: %s" % str(added.map(func(x: Dictionary) -> String: return x.key)))

func _check_young_star() -> void:
	var head: Variant = _head()
	for i: int in 6:
		Game._flavor_news()
	var names: Dictionary = {}
	for n: Dictionary in _news_since(head):
		if n.key == "n_young_star":
			check(not names.has(n.args[0]), "aynı genç yıldız haberi tekrarlandı: %s" % str(n.args[0]))
			names[n.args[0]] = true

# ---------------------------------------------------------------- kayıt v7
func _check_save_v7() -> void:
	check(Game.SAVE_VERSION == 7, "SAVE_VERSION 7 değil")
	Game.save_game()
	var txt: String = FileAccess.get_file_as_string(Game.SAVE_PATH)
	var raw: Variant = _parse_json(txt)
	if not check(raw is Dictionary, "v7 kayıt JSON değil"):
		return
	# biten haftaların maçlarında ilk 11/reyting tutulmuyor; fikstür dizi olarak yazılıyor
	var heavy: int = 0
	var played: int = 0
	for lg: Variant in Game.s.fixtures:
		for rnd: Array in Game.s.fixtures[lg]:
			for m: Dictionary in rnd:
				if int(m.gh) >= 0:
					played += 1
					if m.has("xi_h") or m.has("rt"):
						heavy += 1
	check(played > 0 and heavy == 0, "biten maçlarda xi/rt kaldı: %d/%d" % [heavy, played])
	var fx_lg: String = str(raw.fixtures.keys()[0])
	check(raw.fixtures[fx_lg][0][0] is Array, "fikstür dizi olarak yazılmadı")
	var kn: Dictionary = raw.scout.knowledge
	var packed_ok: bool = not kn.is_empty()
	for pid: Variant in kn:
		if not (kn[pid].e is Array and kn[pid].k is Array):
			packed_ok = false
			break
	check(packed_ok, "knowledge e/k dizi olarak yazılmadı")
	var mem_kn: Dictionary = Game.s.scout.knowledge
	var any_pid: String = str(mem_kn.keys()[0]) if not mem_kn.is_empty() else ""
	var e0: Dictionary = mem_kn[any_pid].e.duplicate() if any_pid != "" else {}
	check(Game.load_game(), "v7 kayıt açılmadı")
	if any_pid != "":
		var e1: Dictionary = Game.s.scout.knowledge[any_pid].e
		check(e1 is Dictionary and e1.size() == Data.ATTRS.size(), "knowledge.e sözlüğe açılmadı")
		var same: bool = true
		for a: String in Data.ATTRS:
			if not is_equal_approx(float(e0[a]), float(e1[a])):
				same = false
		check(same, "knowledge.e yükleme sonrası farklı")
	for pid: Variant in Game.s.players:
		for h: Variant in Game.s.players[pid].get("hist", []):
			if not (h is Dictionary):
				check(false, "hist sözlüğe açılmadı: %s" % str(pid))
				return
	check_save_roundtrip("v7")

# ---------------------------------------------------------------- v6 -> v7 göçü
func _to_v6(txt: String) -> Dictionary:
	## v7 kaydı v6 biçimine çevir (eski sözlük biçimi + eski şişkin evlat kayıtları)
	var d: Dictionary = _parse_json(txt)
	d.version = 6
	for pid: Variant in d.players:
		var p: Dictionary = d.players[pid]
		if p.get("hist") is Array:
			Game._unpack_hist(p.hist)
	for pid: Variant in d.scout.knowledge:
		Game._unpack_kn(d.scout.knowledge[pid])
	for lg: Variant in d.fixtures:
		for rnd: Array in d.fixtures[lg]:
			for i: int in rnd.size():
				var m: Variant = rnd[i]
				if m is Array:
					rnd[i] = {"h": m[0], "a": m[1], "day": m[2], "gh": m[3], "ga": m[4], "ev": m[5],
						"xi_h": [], "xi_a": [], "rt": {}} if int(m[3]) >= 0 else {"h": m[0], "a": m[1], "day": m[2], "gh": m[3], "ga": m[4], "ev": m[5]}
	return d

func _check_migrate_v6() -> void:
	# her şeyi evlat sayan eski davranış: maçta görülen oyuncular için kids_state/kids_feed/haberler
	var other: Array = _pick_players(30, {})
	for pid: String in other:
		Game.log_discovery(pid, "match")
		Game.s.kids_state[pid] = {"apps": 0, "g": 0, "club": Game.player(pid).club, "ovr": 50, "youth": false}
		Game.s.kids_state[pid + "_vs"] = true
		Game.s.kids_feed.push_front({"season": Game.s.season, "week": Game.s.week, "pid": pid, "key": "kf_first_goal", "args": [Game.pname(Game.player(pid))]})
		Game.s.news.push_front({"season": Game.s.season, "week": Game.s.week, "key": "kf_first_goal", "args": [Game.pname(Game.player(pid))], "imp": false, "kind": "kids"})
	var my_pids: Array = Game._my_find_pids()
	check(not my_pids.is_empty(), "test kurgusu: senin keşfin yok")
	Game.save_game()
	var v6: Dictionary = _to_v6(FileAccess.get_file_as_string(Game.SAVE_PATH))
	var v6_txt: String = JSON.stringify(v6)
	var f: FileAccess = FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string(v6_txt)
	f.close()
	Game.s = {}
	if not check(Game.load_game(), "v6 kayıt açılmadı"):
		return
	check(int(Game.s.version) == 7, "göç sonrası sürüm %d" % int(Game.s.version))
	check(Game.s.scout.money == int(v6.scout.money), "göçte para değişti")
	check(is_equal_approx(float(Game.s.scout.rep), float(v6.scout.rep)), "göçte itibar değişti")
	check(int(Game.s.season) == int(v6.season) and int(Game.s.week) == int(v6.week), "göçte sezon/hafta değişti")
	check(Game.s.players.size() == v6.players.size(), "göçte oyuncu sayısı değişti")
	check(Game.s.scout.knowledge.size() == v6.scout.knowledge.size(), "göçte bilgi kaydı kayboldu")
	var heavy: int = 0
	for lg: Variant in Game.s.fixtures:
		for rnd: Array in Game.s.fixtures[lg]:
			for m: Dictionary in rnd:
				if m.has("xi_h") or m.has("rt"):
					heavy += 1
	check(heavy == 0, "göç geçmiş maçların xi/rt'sini silmedi: %d" % heavy)
	for pid: String in other:
		check(not Game.s.kids_state.has(pid) and not Game.s.kids_state.has(pid + "_vs"), "göç kids_state'i budamadı: %s" % pid)
	for it: Dictionary in Game.s.kids_feed:
		check(Game.is_my_find(str(it.pid)), "göç kids_feed'i budamadı")
	var bad_news: int = 0
	for n: Dictionary in Game.s.news:
		if n.kind == "kids" and n.key == "kf_first_goal":
			var e: Dictionary = Game.find_entity(str(n.args[0]))
			if not Game.is_my_find(str(e.get("player", ""))):
				bad_news += 1
	check(bad_news == 0, "göç sonrası %d yabancı evlat haberi kaldı" % bad_news)
	for pid: String in my_pids:
		check(not Game.discovery(pid).is_empty() or Game.is_my_find(pid), "göçte senin keşfin kayboldu: %s" % pid)
	check(Game._my_find_pids().size() == my_pids.size(), "göçte keşif sayısı değişti")
	Game.save_game()
	var v7_len: int = FileAccess.get_file_as_string(Game.SAVE_PATH).length()
	log_info("kayıt boyutu v6 %d KB -> v7 %d KB" % [v6_txt.length() / 1024, v7_len / 1024])
	check(v7_len < v6_txt.length(), "v7 kayıt v6'dan küçük değil")
	check_save_roundtrip("v6->v7")
	# bir hafta oyna
	var w: int = int(Game.s.week)
	Game.end_week_auto()
	check(int(Game.s.week) == w + 1, "göç sonrası hafta ilerlemedi")
	check_scout_state("göç sonrası 1 hafta")
