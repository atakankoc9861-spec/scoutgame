extends "res://tests/check/check_base.gd"
## v0.23 3b — Hibrit maç yolu testleri (Dalga 3 kapısı, Müdür planı §4).
## Küçük örnek (1 sezon); eşiklere örnekleme payı eklenir (z=HYBRID_Z, varsayılan 3.5).
## Kesin eşikli büyük ölçüm: tests/baseline/hybrid_run.sh (≥5 seed × 2000 maç/yol).
##
## Kademeler (çalışma anında kendiliğinden açılır):
##   0) sim/quick_engine.gd yok           -> "SKIP: quick_engine yok", PASS (runner yeşil kalır)
##   1) quick_engine var, Game yönlendirmesi (_use_fast) yok
##                                         -> yalnız motor düzeyi denetimler (sözleşme, saflık,
##                                            determinizm, çağrı sırası, tutarlılık, dağılım bandı)
##      Game kaynağında quick_engine geçiyor ama _use_fast yoksa FAIL (adlar planla uyuşmuyor;
##      HYBRID_FAST_FN=<ad> ile verilebilir).
##   2) ikisi de var                       -> tam hibrit denetim:
##      (1) determinizm hash'i  (2) yol başına dağılım + iki yol farkı  (3) reyting ort/sd, golcü grubu
##      (4) 15 dk gol kovaları  (5) gol olayı=skor, Σst.g=tablo gf, golcü ilk 11'de
##      (6) sakatlık oranı üç yolda  (7) kayıtta tl/cards yok, kayıt boyutu ≤%105
## Ortam: HYBRID_QE (motor yolu), HYBRID_FAST_FN, HYBRID_WATCH (izlenen maç sayısı, varsayılan 30),
##        HYBRID_ENGINE_N (motor düzeyi maç, varsayılan 2000), HYBRID_Z, HYBRID_FAKE_ROUTE=1 (yalnız
##        test kodunun kendisini doğrulamak için; gerçek kapı sonucu sayılmaz).

const Lib = preload("res://tests/baseline/hybrid_lib.gd")

func watchdog_sec() -> float:
	return 840.0

func _apply(results: Array) -> void:
	for r: Dictionary in results:
		if check(bool(r.ok), str(r.msg)):
			log_info("ok  " + str(r.msg))

func run_check() -> void:
	var qe: Script = Lib.load_qe()
	if qe == null:
		print("SKIP: quick_engine yok (%s bulunamadı) — hibrit testler hızlı motor gelince kendiliğinden devreye girer" % Lib.qe_path())
		return
	var prob: String = Lib.qe_contract_problem(qe)
	if not check(prob == "", "quick_engine sözleşmesi (%s): %s" % [Lib.qe_path(), prob]):
		return
	var z: float = float(OS.get_environment("HYBRID_Z")) if OS.get_environment("HYBRID_Z").is_valid_float() else 3.5
	Lib.setup_game()
	var info: Dictionary = Lib.routing_info()
	log_info("yönlendirme: " + Lib.routing_text(info))
	if bool(info.fake):
		log_info("UYARI: HYBRID_FAKE_ROUTE=1 — bu koşu kapı sonucu değildir")
	if Lib.routing_ready(info):
		_hybrid(info, z)
	elif bool(info.mentions_qe):
		check(false, "Game.gd quick_engine'i kullanıyor ama %s() yok — planlı ad değişmiş olabilir (HYBRID_FAST_FN=<ad> ile verin). %s" % [info.fast_fn, Lib.routing_text(info)])
	else:
		print("SKIP: Game yönlendirmesi yok (%s) — yalnız motor düzeyi denetimler" % info.fast_fn)
	_engine(qe, z)

## Motor düzeyi: quick_engine doğrudan
func _engine(qe: Script, z: float) -> void:
	var n: int = Lib.env_int("HYBRID_ENGINE_N", 2000)
	var r: Dictionary = Lib.engine_checks(qe, n, 4242)
	_apply(r.results)
	var mt: Dictionary = Lib.metrics(r.acc)
	_log_metrics("motor", mt)
	_apply(Lib.eval_bands("motor", mt, z))
	log_info("motor hız: medyan %.2f ms, p99 %.2f ms, en kötü %.2f ms (hedef ≤3 / ≤10; kesin ölçüm hybrid_run.sh)" % [r.ms_median, r.ms_p99, r.ms_max])
	# hız kapısı burada gevşek (makine gürültüsü); kesin eşik ölçüm betiğinde
	check(float(r.ms_median) <= 6.0, "motor medyan süre %.2f ms > 6 ms (hedef 3 ms)" % r.ms_median)

## Tam hibrit: 1 sezon play_day/finish_week, kayıt, determinizm, izlenen yol
func _hybrid(info: Dictionary, z: float) -> void:
	var t0 := Time.get_ticks_msec()
	var st: Dictionary = Lib.run_season(info)
	log_info("sezon: %d hafta, %d ms (en uzun hafta %d ms)" % [int(st.weeks), Time.get_ticks_msec() - t0, int(st.week_ms_max)])
	var accs: Dictionary = st.accs
	var mts := {}
	for p: String in Lib.PATHS:
		mts[p] = Lib.metrics(accs[p])
	mts["poisson"] = Lib.metrics(Lib.poisson_all(accs))
	for p: String in ["fast", "poisson_d", "poisson_l", "poisson"]:
		_log_metrics(p, mts[p])
	# yönlendirme
	check(int(mts.fast.n) > 0, "hızlı yola hiç maç gitmedi (%s hep false)" % info.fast_fn)
	check(int(mts.poisson.n) > 0, "Poisson yoluna hiç maç gitmedi")
	check(int(st.get("unplayed", 0)) == 0, "%d maç play_day sonrası oynanmamış kaldı" % int(st.get("unplayed", 0)))
	check(int(st.get("max_fast_other", 0)) <= Lib.FAST_SHORTLIST_CAP, "bir haftada oyuncunun ligi dışında %d maç hızlı yola gitti (sınır %d)" % [int(st.get("max_fast_other", 0)), Lib.FAST_SHORTLIST_CAP])
	log_info("hafta başına lig dışı en çok hızlı maç: %d (shortlist %d oyuncu)" % [int(st.get("max_fast_other", 0)), (Game.s.scout.shortlist as Array).size()])
	if st.has("fast_fn_pure") and not bool(st.fast_fn_pure):
		log_info("UYARI: %s() çağrısı Game.s'yi değiştiriyor; yol sınıflandırması tahmini olabilir" % info.fast_fn)
	check(bool(info.has_sim_seed) or bool(info.fake), "s.sim_seed yok (deterministik maç seed'i, Dalga 2-E)")
	# (5) tutarlılık
	for p: String in ["fast", "poisson_d"]:
		_apply(Lib.eval_consistency(p, accs[p]))
	var samp: String = "" if (st.stg_samples as Array).is_empty() else " örn: " + str(st.stg_samples[0])
	_apply([
		Lib._res("st_g", int(st.get("stg_bad", 0)) == 0, "Σ st.g farkı ≠ gol olayları: %d/%d hafta%s" % [int(st.get("stg_bad", 0)), int(st.get("stg_weeks", 0)), samp]),
		Lib._res("gf", int(st.get("gf_bad", 0)) == 0 and int(st.get("lg_checked", 0)) > 0, "lig Σ st.g = tablo gf = gol olayı: %d/%d lig-hafta uyumsuz%s" % [int(st.get("gf_bad", 0)), int(st.get("lg_checked", 0)), samp]),
	])
	# (2) yol başına dağılım + (2,3,4) iki yol farkı
	_apply(Lib.eval_bands("fast", mts.fast, z))
	_apply(Lib.eval_bands("poisson", mts.poisson, z))
	_apply(Lib.eval_pair("fast", mts.fast, "poisson", mts.poisson, z, false))
	_apply(Lib.eval_pair("fast", mts.fast, "poisson_d", mts.poisson_d, z, true))
	# (7) kayıt
	var sv: Dictionary = Lib.save_scan()
	check((sv.bad_keys as Array).is_empty(), "kayıtta yasak anahtar (tl/cards): %s" % str(sv.bad_keys))
	var ref: Dictionary = Lib.ref_size(_seed())
	if ref.is_empty():
		check(false, "kayıt boyutu referansı yok (%s) — hybrid_stats MODE=ref ile üretin" % Lib.REF_PATH)
	else:
		var ratio: float = float(sv.size) / maxf(1.0, float(ref.size))
		if check(ratio <= Lib.SIZE_MAX, "sezon sonu kayıt boyutu %d = Dalga 3 öncesinin %%%.1f'i (sınır %%%.0f; referans %d, %s)" % [sv.size, 100.0 * ratio, 100.0 * Lib.SIZE_MAX, ref.size, ref.how]):
			log_info("ok  kayıt boyutu %d = referansın %%%.1f'i (%s)" % [sv.size, 100.0 * ratio, ref.how])
	# (1) determinizm: yeni sezonun 1. haftası
	Game.finish_week()
	var det: Dictionary = Lib.determinism(info)
	if check(bool(det.ok), str(det.msg)):
		log_info("ok  " + str(det.msg))
	for x: String in det.samples:
		print("    ", x)
	# (6) sakatlık: izlenen yol
	var nw: int = Lib.env_int("HYBRID_WATCH", 30)
	var tw := Time.get_ticks_msec()
	var got: int = Lib.run_watched(nw, st)
	log_info("izlenen yol: %d maç, %d ms" % [got, Time.get_ticks_msec() - tw])
	check(got == nw, "izlenen yol için %d maç bulunamadı (%d)" % [nw, got])
	mts["watched"] = Lib.metrics(accs.watched)
	_log_metrics("watched", mts.watched)
	_apply(Lib.eval_consistency("watched", accs.watched))
	_apply(Lib.eval_injuries(mts, ["poisson_d", "fast", "watched"], z))

func _seed() -> int:
	var env_seed: String = OS.get_environment("CHECK_SEED")
	return env_seed.to_int() if env_seed.is_valid_int() else DEFAULT_SEED

func _log_metrics(p: String, mt: Dictionary) -> void:
	log_info("%-9s n=%d gol/maç %.2f ev %.1f%% ber %.1f%% dep %.1f%% 4+ %.1f%% ev/dep %.2f | rt %.2f±%.2f (n=%d) | golcü G/D/O/F %.0f/%.0f/%.0f/%.0f | dk %s | sakat %d/%d" % [
		p, mt.n, mt.gpm, mt.hw, mt.dr, mt.aw, mt.big, mt.ha, mt.rt_mean, mt.rt_sd, mt.rt_n,
		mt.grp.GK, mt.grp.DEF, mt.grp.MID, mt.grp.ATT,
		"/".join(PackedStringArray((mt.mins as Array).map(func(x: float) -> String: return "%.0f" % x))), mt.inj, mt.apps])
