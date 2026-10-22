extends "res://tests/check/check_base.gd"
## Analist Gözü (v0.24 5A) kapısı.
## 1) Elle kurulmuş pozisyonlar: futbol mantığı doğru cevabı veriyor mu
##    (boş adam + açık yol doğru, kalabalığa ara pası yanlış, iyi açıdan boş şut > geri pas,
##    kapalı yol < açık yol), gerekçe TR ve EN üretiliyor mu, attr anahtarı geçerli mi.
## 2) 50 ekransız maç (izleyicinin Pacer + EyeLogic.Director akışı, tests/check/watch_sim.gd):
##    mod başına soru sayısı (Normal 4-5, Anlar 4, Özet 2), sayı ≥4 ise her yarıda ≥2,
##    sorular arası ≥8 oyun dakikası, soru sürerken oyun hızı hiç 0 değil,
##    _eye_reads [{pid, attr, ok}] geçerli Data.ATTRS anahtarlarıyla yazılıyor.
## 3) tests/i18n/eye.json TR/EN eşit, yer tutucu sayıları aynı.

const EyeLogic = preload("res://sim/eye_logic.gd")
const WatchSim = preload("res://tests/check/watch_sim.gd")

const N_MATCH: int = 50
const COUNT := {"full": [2, 3], "moments": [1, 2], "hl": [1, 1]}

var _tbl: Dictionary = {}

func watchdog_sec() -> float:
	return 1500.0

func run_check() -> void:
	_check_i18n()
	_check_positions()
	_check_matches()

# ---------------------------------------------------------------- i18n

func _check_i18n() -> void:
	var txt := FileAccess.get_file_as_string("res://tests/i18n/eye.json")
	var j := JSON.new()
	if not check(j.parse(txt) == OK and j.data is Dictionary, "tests/i18n/eye.json okunamadı"):
		return
	_tbl = j.data
	for k: String in _tbl:
		var v: Variant = _tbl[k]
		if not check(v is Array and (v as Array).size() == 2, "i18n biçim: " + k):
			continue
		var tr: String = v[0]
		var en: String = v[1]
		check(tr != "" and en != "", "i18n boş: " + k)
		check(tr.count("%s") == en.count("%s"), "i18n yer tutucu sayısı farklı: " + k)
	for k: String in EyeLogic.TEXT_KEYS:
		check(_tbl.has(k), "i18n eksik: " + k)

# ---------------------------------------------------------------- elle kurulmuş pozisyonlar

func _mate(id: String, x: float, y: float, role: String) -> Dictionary:
	return {"id": id, "pos": Vector2(x, y), "role": role, "name": id}

func _opp(x: float, y: float, gk := false) -> Dictionary:
	return {"pos": Vector2(x, y), "gk": gk}

func _find(opts: Array, k: String, to := "") -> int:
	for i: int in opts.size():
		if str(opts[i].k) == k and (to == "" or str(opts[i].get("to", "")) == to):
			return i
	return -1

func _render(parts: Array, lang: int) -> String:
	return EyeLogic.render(parts, func(key: String, args: Array) -> String:
		var row: Array = _tbl.get(key, [key, key])
		var s: String = row[lang]
		return s % args if not args.is_empty() else s)

func _check_positions() -> void:
	# A) Orta sahada top: sağ bek boş ve yol açık; forvete ara pası üç savunmacının arasına
	var sit_a := {"d": 1.0, "pos": Vector2(0, 0), "pid": "cm",
		"mates": [_mate("rb", -4, 26, "RB"), _mate("st", 30, 0, "ST"), _mate("lw", 6, -24, "LW")],
		"opps": [_opp(3, 0.5), _opp(28, 2.5), _opp(31, -2), _opp(29, -1.5), _opp(15, 0.6), _opp(10, -20), _opp(8, -26),
			_opp(-6, 6), _opp(20, 12), _opp(36, 0), _opp(50, 0, true)]}
	var oa: Array = EyeLogic.options(sit_a)
	var rb := _find(oa, "pass", "rb")
	var st := _find(oa, "pass", "st")
	var lw := _find(oa, "pass", "lw")
	if check(rb >= 0 and st >= 0, "A: seçenekler eksik %s" % str(oa.map(func(o): return [o.k, o.get("to", "")]))):
		var bi := EyeLogic.best_index(oa)
		log_info("A: en iyi %s/%s, rb=%.3f st=%.3f lw=%.3f" % [oa[bi].k, oa[bi].get("to", ""), float(oa[rb].score), float(oa[st].score), float(oa[lw].score) if lw >= 0 else -9.0])
		check(str(oa[rb].lane) == "open" and str(oa[rb].mark) == "free", "A: sağ bek boş/açık görünmüyor (%s/%s)" % [oa[rb].lane, oa[rb].mark])
		check(str(oa[st].lane) != "open" or str(oa[st].mark) == "tight", "A: kalabalığa ara pası açık görünüyor")
		check(EyeLogic.judge(oa, rb), "A: boş adam + açık yol doğru sayılmadı")
		check(not EyeLogic.judge(oa, st), "A: kalabalığa riskli ara pası doğru sayıldı")
		var parts := EyeLogic.reason(oa, st, false)
		var tr := _render(parts, 0)
		var en := _render(parts, 1)
		log_info("A gerekçe TR: " + tr)
		log_info("A gerekçe EN: " + en)
		check(tr != "" and en != "" and tr != en, "A: gerekçe TR/EN üretilmedi")
		check("%s" not in tr and "%s" not in en, "A: gerekçede doldurulmamış yer tutucu")
		check(tr.contains("rb") and en.contains("rb"), "A: gerekçe boş adamı (rb) anmıyor")
		check(tr.contains(str(_tbl.eye_rw_traffic[0]).left(12)) or tr.contains(str(_tbl.eye_rw_blocked[0]).left(10)), "A: gerekçe ara pasının neden kötü olduğunu söylemiyor: " + tr)
		var at := EyeLogic.attr_for(oa, EyeLogic.best_index(oa))
		check(at in Data.ATTRS, "A: attr geçersiz: " + at)
		log_info("A: attr " + at)
	# B) Ceza sahası içinde, iyi açı, önü boş: şut > geri pas
	var sit_b := {"d": 1.0, "pos": Vector2(40, 3), "pid": "st",
		"mates": [_mate("cm", 18, 0, "CM"), _mate("rw", 30, 22, "RW")],
		"opps": [_opp(44, 12), _opp(35, -10), _opp(25, 6), _opp(52, 0, true)]}
	var ob: Array = EyeLogic.options(sit_b)
	var sh := _find(ob, "shot")
	var cm := _find(ob, "pass", "cm")
	if check(sh >= 0 and cm >= 0, "B: şut/geri pas seçeneği yok"):
		check(EyeLogic.judge(ob, sh), "B: iyi açıdan boş şut doğru sayılmadı")
		check(not EyeLogic.judge(ob, cm), "B: boşken geri pas doğru sayıldı")
		var at := EyeLogic.attr_for(ob, sh)
		check(at == "finishing", "B: şut kararının attr'ı finishing değil: " + at)
		var en := _render(EyeLogic.reason(ob, cm, false), 1)
		log_info("B gerekçe EN: " + en)
		check(en != "", "B: gerekçe yok")
	# C) İki eşit boş adam: biri açık yolda, diğerinin yolunda rakip var -> açık yol doğru
	var sit_c := {"d": -1.0, "pos": Vector2(5, 0), "pid": "dm",
		"mates": [_mate("a", -5, 15, "LB"), _mate("b", -5, -15, "RB")],
		"opps": [_opp(2, -2.5), _opp(0, -7.6), _opp(-20, 2), _opp(15, 0), _opp(-30, 5), _opp(-31, -5), _opp(-52, 0, true)]}
	var oc: Array = EyeLogic.options(sit_c)
	var ia := _find(oc, "pass", "a")
	var ib := _find(oc, "pass", "b")
	if check(ia >= 0 and ib >= 0, "C: seçenekler eksik"):
		check(str(oc[ib].lane) == "blocked", "C: rakibin kestiği yol kapalı görünmüyor (%s)" % oc[ib].lane)
		check(EyeLogic.judge(oc, ia) and not EyeLogic.judge(oc, ib), "C: açık yol / kapalı yol ayrımı yanlış")
		check(_render(EyeLogic.reason(oc, ib, false), 0).contains("b"), "C: gerekçe kapalı yolu anmıyor")
	# D) Ofsayttaki adam seçenek değil
	var sit_d := {"d": 1.0, "pos": Vector2(10, 0), "pid": "am",
		"mates": [_mate("st", 40, 0, "ST"), _mate("cm", 0, 10, "CM")],
		"opps": [_opp(30, 5), _opp(31, -5), _opp(52, 0, true)]}
	check(_find(EyeLogic.options(sit_d), "pass", "st") < 0, "D: ofsayttaki adam seçenek olarak sunuldu")
	# E) Seçim seti: en çok 4, en iyisi içinde, attr her zaman geçerli
	var pick := EyeLogic.pick_set(oa)
	check(pick.size() >= 3 and pick.size() <= 4, "E: seçim seti boyutu %d" % pick.size())
	check(pick.has(oa[EyeLogic.best_index(oa)]), "E: en iyi seçenek sete girmedi")
	for k: String in EyeLogic.ATTR_KEYS:
		check(k in Data.ATTRS, "ATTR_KEYS geçersiz: " + k)

# ---------------------------------------------------------------- 50 ekransız maç

func _check_matches() -> void:
	Game.new_game("T", "tr")
	Game.take_job(str(Game.job_offers_start()[0]))
	var pool: Array = WatchSim.pool(Game, 5)
	check(pool.size() == 5, "maç havuzu eksik")
	var kinds := ["full", "moments", "hl"]
	var tot := {"full": [], "moments": [], "hl": []}
	var reads_n := 0
	var reads_ok := 0
	var min_rate := 99.0
	var attrs := {}
	var kinds_b := {}
	var noans := 0
	var gaps: Array = []
	var wall_eye := {"full": 0.0, "moments": 0.0, "hl": 0.0}
	var nm: int = N_MATCH
	if OS.get_environment("EYE_N").is_valid_int():
		nm = OS.get_environment("EYE_N").to_int()   # yalnız geliştirmede hızlı tur
	for i: int in nm:
		var kind: String = kinds[i % 3]
		var m: Dictionary = pool[i % pool.size()]
		var r: Dictionary = WatchSim.watch(Game, m, kind, 9100 + i * 7, true)
		var tag := "maç %d %s" % [i, kind]
		check(r.finished, tag + ": maç bitmedi")
		var asked: Array = r.eye_clock
		var n := asked.size()
		tot[kind].append(n)
		wall_eye[kind] = float(wall_eye[kind]) + float(r.eye_wall)
		var lo: int = COUNT[kind][0]
		var hi: int = COUNT[kind][1]
		check(n >= lo and n <= hi, "%s: %d soru (beklenen %d-%d)" % [tag, n, lo, hi])
		var per := [0, 0]
		for a: Array in asked:
			per[int(a[1])] += 1
		if n >= 4:
			check(per[0] >= 2 and per[1] >= 2, "%s: yarı dağılımı %s (her yarıda ≥2 olmalı)" % [tag, str(per)])
		for q: int in range(1, n):
			var gap: float = float(asked[q][0]) - float(asked[q - 1][0])
			check(gap >= EyeLogic.GAP, "%s: arka arkaya soru (%.0f sn oyun saati arayla)" % [tag, gap])
		min_rate = minf(min_rate, float(r.eye_min_rate))
		check(float(r.eye_min_rate) > 0.0, tag + ": soru sırasında oyun hızı 0")
		var fe: Dictionary = r.fe
		check(fe.has("_eye_reads"), tag + ": fe[_eye_reads] yazılmadı")
		var reads: Array = fe.get("_eye_reads", [])
		check(reads.size() == n, "%s: _eye_reads %d kayıt, soru %d" % [tag, reads.size(), n])
		for rd: Variant in reads:
			if not check(rd is Dictionary and rd.has("pid") and rd.has("attr") and rd.has("ok"), tag + ": _eye_reads biçimi " + str(rd)):
				continue
			check(str(rd.attr) in Data.ATTRS and str(rd.attr) in EyeLogic.ATTR_KEYS, tag + ": geçersiz attr " + str(rd.attr))
			check(str(rd.pid) in r.focus, tag + ": odak dışı oyuncuya soru " + str(rd.pid))
			check(typeof(rd.ok) == TYPE_BOOL, tag + ": ok bool değil")
			reads_n += 1
			attrs[str(rd.attr)] = int(attrs.get(str(rd.attr), 0)) + 1
			kinds_b[str(rd.get("k", ""))] = int(kinds_b.get(str(rd.get("k", "")), 0)) + 1
			gaps.append([float(rd.get("gap", 0.0)), bool(rd.get("blk", false))])
			if not bool(rd.get("ans", true)):
				noans += 1
			if bool(rd.ok):
				reads_ok += 1
	for kind: String in kinds:
		var arr: Array = tot[kind]
		var s := 0
		for x: int in arr:
			s += x
		log_info("%s: soru sayıları %s (ort %.2f), maç başı göz süresi %.0f sn" % [kind, str(arr), float(s) / maxf(1.0, arr.size()), float(wall_eye[kind]) / maxf(1.0, arr.size())])
	log_info("okumalar: %d, rastgele kullanıcı isabeti %d (%.0f%%), soru sırasında en düşük hız %.2f" % [reads_n, reads_ok, 100.0 * reads_ok / maxf(1.0, reads_n), min_rate])
	gaps.sort()
	log_info("attr dağılımı %s, doğru cevap türü %s, cevapsız %d" % [str(attrs), str(kinds_b), noans])
	check(min_rate >= EyeLogic.JUDGE_RATE - 0.001, "soru sırasında hız yargı hızının altına düştü: %.2f" % min_rate)
	# v2: gerçek notların dağılımı tek cevaba yığılmasın ("hep İyi" ezberi olmasın)
	var gtot := 0
	for g: String in EyeLogic.GRADES:
		gtot += int(kinds_b.get(g, 0))
	for g: String in EyeLogic.GRADES:
		var sh := float(kinds_b.get(g, 0)) / maxf(1.0, gtot)
		check(sh >= 0.15 and sh <= 0.55, "not dağılımı dengesiz: %s %%%d" % [g, int(sh * 100.0)])
