extends "res://tests/check/check_base.gd"
## v0.24 Dalga 5B "Bu maçta öğrendiklerin" + Analist Gözü bilgi kazancı:
## - senaryolu izleme: obs.learned kartlarındaki önce/sonra aralıklar ve bilgi % elle alınan fotoğraflarla birebir
## - fe["_eye_reads"]: yalnız ok=true + odak oyuncu + geçerli özellik işlenir; maç başı tavan (EYE_READ_CAP),
##   özellik başı tavan (EYE_READ_PER_ATTR), bilgi göz bonusuyla EYE_READ_K_MAX'ı aşmaz; yanlış okuma 0 etki
## - _eye_reads yok / bozuk → çökme yok, kartlar yine üretilir
## - finish_video da kart döndürür
## - kayıt turu temiz (obs.learned last_obs içinde kayda girer)
## - tests/i18n/ogrendiklerin.json TR/EN eşit
## - OGREN_SHOT=<klasör> verilirse (görüntülü sürücüyle) ekranın görüntüsü alınır

func watchdog_sec() -> float:
	return 600.0

var _main: Node = null

func run_check() -> void:
	Game.new_game("T", "tr")
	var offers: Array = Game.job_offers_start()
	if not check(not offers.is_empty(), "başlangıç teklifi yok"):
		return
	Game.take_job(str(offers[0]))
	Game.finish_week()
	_check_i18n()
	var w := _watch_setup()
	if w.is_empty():
		return
	_check_deltas(w)
	_check_eye(w)
	_check_eye_direct(w)
	_check_video()
	check_save_roundtrip("öğrendiklerin")
	check_scout_state("son")
	var shot := OS.get_environment("OGREN_SHOT")
	if shot != "":
		await _shot(shot)

func _check_i18n() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/i18n/ogrendiklerin.json"))
	if not check(d is Dictionary, "ogrendiklerin.json okunamadı"):
		return
	for k: String in ["learn_title", "learn_title_vid", "learn_know", "learn_new", "learn_pa", "learn_eye_n", "learn_none", "learn_cont"]:
		if not check(d.has(k) and d[k] is Array and d[k].size() == 2, "i18n eksik: " + k):
			continue
		check(str(d[k][0]) != "" and str(d[k][1]) != "", "i18n boş: " + k)
		check(str(d[k][0]).count("%s") == str(d[k][1]).count("%s"), "i18n yer tutucu sayısı farklı: " + k)
	for k2: String in ["h_big_match", "h_consistency", "lvl_0", "lvl_2"]:
		check(T.has_key(k2), "mevcut metin yok: " + k2)

## Bir lig maçını oynatır; durum + rng fotoğrafı ile iki kez apply_watch denenebilsin
func _watch_setup() -> Dictionary:
	var key := ""
	for wm in Game.week_matches():
		if int(wm.m.gh) < 0:
			key = Game.match_key(wm.lg, wm.idx)
			break
	if not check(key != "", "izlenecek maç yok"):
		return {}
	var data := Game.watch_match_data(key)
	Game.finish_live(data)
	var m: Dictionary = data.m
	var fa: String = str(m.xi_h[3])
	var fb: String = str(m.xi_a[7])
	var outsider: String = str(m.xi_h[8])
	var fe := {fa: [0, 1, 2, 3, 4], fb: [5, 6, 7, 8], "_sparks": {}, "_eye": {}, "_eye_hits": {}, "_eye_def": {}}
	return {"data": data, "fe": fe, "fa": fa, "fb": fb, "out": outsider,
		"s": Game.s.duplicate(true), "rng": Game.rng.state}

func _restore(w: Dictionary) -> void:
	Game.s = (w.s as Dictionary).duplicate(true)
	Game.rng.state = int(w.rng)

func _k(pid: String) -> Dictionary:
	return (Game.s.scout.knowledge.get(pid, {}).get("k", {}) as Dictionary).duplicate()

## (1) önce/sonra farkı elle alınan fotoğraflarla aynı mı (_eye_reads yok)
func _check_deltas(w: Dictionary) -> void:
	_restore(w)
	var pre := {}
	for pid: String in [w.fa, w.fb]:
		pre[pid] = Game.know_snap(pid)
	var obs: Dictionary = Game.apply_watch(w.data, (w.fe as Dictionary).duplicate(true))
	var cards: Array = obs.get("learned", [])
	if not check(cards.size() == 2, "iki odak oyuncu için kart yok: %d" % cards.size()):
		return
	var tot_rows := 0
	for c: Dictionary in cards:
		var pid := str(c.pid)
		var b: Dictionary = pre[pid]
		var post := Game.know_snap(pid)
		check(int(c.k0) == int(round(float(b.pct) * 100.0)) and int(c.k1) == int(round(float(post.pct) * 100.0)), "%s bilgi %% yanlış" % pid)
		check(int(c.k1) >= int(c.k0), "%s bilgi azaldı %d → %d" % [pid, int(c.k0), int(c.k1)])
		check((c.rows as Array).size() <= Game.LEARN_ROWS_MAX, "satır tavanı aşıldı")
		check(int(c.eye) == 0, "okuma yokken göz bonusu var")
		var last_n := 999
		for r: Dictionary in c.rows:
			var a := str(r.a)
			var r0: Array = b.rng[a]
			var r1: Array = post.rng[a]
			check(not r1.is_empty() and int(r.lo1) == int(r1[0]) and int(r.hi1) == int(r1[1]), "%s %s yeni aralık yanlış" % [pid, a])
			if r0.is_empty():
				check(int(r.lo0) == -1, "%s %s eski aralık bilinmiyordu" % [pid, a])
			else:
				check(int(r.lo0) == int(r0[0]) and int(r.hi0) == int(r0[1]), "%s %s eski aralık yanlış" % [pid, a])
			var w0 := 19 if r0.is_empty() else int(r0[1]) - int(r0[0])
			check(int(r.n) == w0 - (int(r1[1]) - int(r1[0])) and int(r.n) > 0, "%s %s daralma yanlış" % [pid, a])
			check(int(r.n) <= last_n, "satırlar daralmaya göre sıralı değil")
			last_n = int(r.n)
			tot_rows += 1
		check(Game.learn_has(c), "%s ilk izlemede kart boş" % pid)
		if not (c.rows as Array).is_empty():
			var r0d: Dictionary = c.rows[0]
			log_info("%s: bilgi %%%d → %%%d, %d satır, örn. %s %s → %d–%d" % [pid, int(c.k0), int(c.k1), (c.rows as Array).size(), r0d.a,
				"?" if int(r0d.lo0) < 0 else "%d–%d" % [int(r0d.lo0), int(r0d.hi0)], int(r0d.lo1), int(r0d.hi1)])
	check(tot_rows > 0, "hiç daralan özellik yok")

## (2) göz okumaları: aynı maç, aynı rng; okumalı ve okumasız sonuç karşılaştırılır
func _check_eye(w: Dictionary) -> void:
	var fa: String = w.fa
	var fb: String = w.fb
	_restore(w)
	Game.apply_watch(w.data, (w.fe as Dictionary).duplicate(true))
	var ka0 := _k(fa)
	var kb0 := _k(fb)
	var ko0 := _k(w.out)
	var xp0 := int(Game.s.scout.xp_eye) + int(Game.s.scout.eye) * 1000
	_restore(w)
	var fe: Dictionary = (w.fe as Dictionary).duplicate(true)
	fe["_eye_reads"] = [
		{"pid": fa, "attr": "passing", "ok": true},
		{"pid": fa, "attr": "passing", "ok": true},
		{"pid": fa, "attr": "passing", "ok": true},     # özellik başı 2 → sayılmaz
		{"pid": fa, "attr": "vision", "ok": false},     # yanlış → 0 etki
		{"pid": w.out, "attr": "pace", "ok": true},     # odak değil → sayılmaz
		{"pid": fa, "attr": "bogus", "ok": true},       # geçersiz özellik
		{"pid": fb, "attr": "dribbling", "ok": true},   # 3. işlenen → tavan
		{"pid": fb, "attr": "pace", "ok": true},        # tavan doldu → sayılmaz
	]
	var obs: Dictionary = Game.apply_watch(w.data, fe)
	var ka1 := _k(fa)
	var kb1 := _k(fb)
	var ko1 := _k(w.out)
	var xp1 := int(Game.s.scout.xp_eye) + int(Game.s.scout.eye) * 1000
	var gain_pass := float(ka1.passing) - float(ka0.passing)
	log_info("göz bonusu: %s pas k %.3f → %.3f (+%.3f), %s çalım k %.3f → %.3f; göz XP +%d" % [fa, float(ka0.passing), float(ka1.passing), gain_pass,
		fb, float(kb0.dribbling), float(kb1.dribbling), xp1 - xp0])
	if float(ka0.passing) < Game.EYE_READ_K_MAX:
		var k1 := minf(Game.EYE_READ_K_MAX, float(ka0.passing) + Game.EYE_READ_GAIN * (1.0 - float(ka0.passing)))
		var k2 := minf(Game.EYE_READ_K_MAX, k1 + Game.EYE_READ_GAIN * (1.0 - k1))
		check(absf(float(ka1.passing) - k2) < 0.002, "pas: iki okuma bekleniyordu (%.3f ≠ %.3f)" % [float(ka1.passing), k2])
	check(float(ka1.passing) <= maxf(Game.EYE_READ_K_MAX, float(ka0.passing)) + 0.0005, "göz bonusu tavanı aştı")
	check(is_equal_approx(float(ka1.vision), float(ka0.vision)), "yanlış okuma bilgi verdi (vision)")
	check(is_equal_approx(float(ko1.get("pace", 0.0)), float(ko0.get("pace", 0.0))), "odak dışı oyuncuya göz bonusu")
	if float(kb0.dribbling) < Game.EYE_READ_K_MAX:
		check(float(kb1.dribbling) > float(kb0.dribbling), "3. doğru okuma işlenmedi")
	check(is_equal_approx(float(kb1.pace), float(kb0.pace)), "maç tavanı aşıldı (4. doğru okuma işlendi)")
	for a in Data.ATTRS:
		if a != "passing":
			check(is_equal_approx(float(ka1[a]), float(ka0[a])), "%s %s okumasız değişti" % [fa, a])
		if a != "dribbling":
			check(is_equal_approx(float(kb1[a]), float(kb0[a])), "%s %s okumasız değişti" % [fb, a])
	check(xp1 - xp0 == 2 * Game.EYE_READ_CAP or xp1 - xp0 > 500, "göz XP'si %d (beklenen %d)" % [xp1 - xp0, 2 * Game.EYE_READ_CAP])
	for c: Dictionary in obs.learned:
		if str(c.pid) == fa:
			check(int(c.eye) == 1 and not (c.rows as Array).is_empty() and bool(c.rows[0].eye) and str(c.rows[0].a) == "passing", "göz satırı en üstte değil")
		elif str(c.pid) == fb:
			check(int(c.eye) == 1, "fb göz sayısı yanlış")

## (3) apply_eye_reads doğrudan: bozuk girdi, tavanlar
func _check_eye_direct(w: Dictionary) -> void:
	_restore(w)
	var fa: String = w.fa
	var foc := [fa]
	for bad: Variant in [{}, {"_eye_reads": "x"}, {"_eye_reads": null}, {"_eye_reads": [null, 5, {}, {"pid": fa}, {"ok": true}]}]:
		check((Game.apply_eye_reads(bad, foc) as Dictionary).is_empty(), "bozuk _eye_reads işlendi: " + str(bad))
	var many := []
	for a in Data.ATTRS:
		many.append({"pid": fa, "attr": a, "ok": true})
	var got: Dictionary = Game.apply_eye_reads({"_eye_reads": many}, foc)
	check((got.get(fa, []) as Array).size() == Game.EYE_READ_CAP, "maç tavanı: %d özellik işlendi" % (got.get(fa, []) as Array).size())
	var kn := Game.know(fa)
	kn.k["stamina"] = 0.79
	for i in 2:
		Game.apply_eye_reads({"_eye_reads": [{"pid": fa, "attr": "stamina", "ok": true}]}, foc)
	check(float(kn.k.stamina) <= Game.EYE_READ_K_MAX + 0.0005, "K_MAX aşıldı: %.3f" % float(kn.k.stamina))
	# okuma listesi hiç yokken apply_watch çökmez
	_restore(w)
	var fe: Dictionary = {w.fa: [0, 1]}
	var obs: Dictionary = Game.apply_watch(w.data, fe)
	check(obs.has("learned") and (obs.learned as Array).size() == 1, "_eye_reads'siz izlemede kart yok")
	_restore(w)

## (4) video analizi de kart döndürür
func _check_video() -> void:
	var pid := ""
	for cid in Game.s.clubs:
		var c: Dictionary = Game.club(cid)
		if Game.club_country(cid) == Game.my_country() and not (c.get("squad", []) as Array).is_empty():
			for p2 in c.squad:
				if not Game.player(p2).get("youth", false) and int(Game.player(p2).st.apps) > 0:
					pid = p2
					break
		if pid != "":
			break
	if not check(pid != "", "video için oyuncu yok"):
		return
	var data := Game.video_match_data(pid)
	var eng = data.eng
	if not eng.finished:
		eng.run_to_end()
	data.tl = eng.events
	data.erase("eng")
	var idx := []
	for i in mini(8, (data.tl as Array).size()):
		idx.append(i)
	var res: Dictionary = Game.finish_video(pid, data, {pid: idx, "_eye_reads": [{"pid": pid, "attr": "first_touch", "ok": true}]}, "tec")
	check(res.ok and res.has("learned"), "finish_video kart döndürmedi")
	if res.ok:
		var c: Dictionary = res.learned
		check(str(c.pid) == pid and int(c.eye) == 1, "video kartı yanlış: " + str(c.get("eye")))
		check(Game.learn_has(c), "video kartı boş")
		log_info("video: bilgi %%%d → %%%d, %d satır" % [int(c.k0), int(c.k1), (c.rows as Array).size()])

## Ekran görüntüsü (yalnız OGREN_SHOT verilince; headless dummy sürücüde görüntü boş olur)
func _shot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	for i in 20:
		await get_tree().process_frame
	# son izlenen maçın kartlarıyla sahte hafta sonucu
	var key := ""
	for wm in Game.week_matches():
		if int(wm.m.gh) < 0:
			key = Game.match_key(wm.lg, wm.idx)
			break
	if key == "":
		log_info("görüntü: maç yok")
		return
	var data := Game.watch_match_data(key)
	Game.finish_live(data)
	var m: Dictionary = data.m
	var fe := {str(m.xi_h[9]): [0, 1, 2, 3], str(m.xi_a[6]): [4, 5, 6],
		"_sparks": {str(m.xi_h[9]): 1},
		"_eye_reads": [{"pid": str(m.xi_h[9]), "attr": "passing", "ok": true}, {"pid": str(m.xi_a[6]), "attr": "vision", "ok": false}]}
	Game.apply_watch(data, fe)
	_main.pending_result = {"obs": Game.s.last_obs}
	_main._learn_ack = false
	_main._show("result", null, false)
	for i in 120:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("ogrendiklerin_%s.png" % T.lang))
	log_info("görüntü: " + dir.path_join("ogrendiklerin_%s.png" % T.lang))
	Game.settings["calm"] = true
	_main._show("result", null, false)   # _learn_ack hâlâ false: aynı ekran sakin modda
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir.path_join("ogrendiklerin_calm.png"))
	Game.settings["calm"] = false
