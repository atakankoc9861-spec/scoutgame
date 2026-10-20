extends Node
## v0.23 3b — Hibrit yol ölçümü (Dalga 3 kapısı, kesin eşikler). Çalıştırma: tests/baseline/hybrid_run.sh
##
## MODE=full (varsayılan): her seed için yeni oyun; hızlı yolda ≥N_FAST maç birikene kadar sezon oynatır
##   (en çok SEASONS_MAX), ilk sezon sonunda kayıt boyutu/anahtarları, yeni sezon 1. haftada determinizm,
##   sonra N_LIVE izlenen maç, sonra N_ENGINE maçlık doğrudan motor ölçümü. Tüm seed'ler birleştirilip
##   Müdür planı §4 kriterleri ÖRNEKLEME PAYI OLMADAN (z=0) değerlendirilir.
##   quick_engine yoksa "SKIP: quick_engine yok", yönlendirme yoksa "SKIP: Game yönlendirmesi yok"; çıkış 0.
## MODE=ref: Dalga 3 ÖNCESİ commit'te kayıt boyutu referansı (sezon sonu) -> hybrid_ref.json.
##   check ile aynı akış (setup_game + run_season), yönlendirme varsa reddeder.
##
## Ortam: SEEDS ("2301 4711 9001 1234 5678"), N_FAST (2000), N_LIVE (60/seed), N_ENGINE (2000/seed),
##        SEASONS_MAX (8), OUT (çıktı klasörü), COMMIT (ref için), HYBRID_QE / HYBRID_FAST_FN / HYBRID_FAKE_ROUTE.
## Çıktı: "HYBRID_RESULT: PASS|FAIL|SKIP", OUT/hybrid_report.json, OUT/hybrid_criteria.csv, OUT/hybrid_paths.csv

const Lib = preload("res://tests/baseline/hybrid_lib.gd")

func _seeds(d: String) -> Array:
	var out := []
	for x in Lib.env_str("SEEDS", d).split(" ", false):
		if x.is_valid_int():
			out.append(int(x))
	return out

func _out_dir() -> String:
	var d := Lib.env_str("OUT", ProjectSettings.globalize_path("user://hybrid_out"))
	DirAccess.make_dir_recursive_absolute(d)
	return d

func _ready() -> void:
	var mode := Lib.env_str("MODE", "full")
	if mode == "ref":
		_ref()
	else:
		_full()

func _start(sd: int) -> void:
	# check_base ile aynı tohumlama sırası
	Game.rng.seed = sd
	seed(sd)
	Lib.setup_game()

# ================================================================ referans

func _ref() -> void:
	var seeds := _seeds("20231015 2301 4711 9001 1234 5678")
	var sizes := {}
	var bad := {}
	for sd: int in seeds:
		_start(sd)
		var info := Lib.routing_info()
		if Lib.routing_ready(info) or bool(info.mentions_qe):
			print("HATA: ref yalnız Dalga 3 öncesi (yönlendirmesiz) commit'te üretilir: ", Lib.routing_text(info))
			print("HYBRID_RESULT: FAIL")
			get_tree().quit(1)
			return
		var t0 := Time.get_ticks_msec()
		Lib.run_season(info)
		var sv := Lib.save_scan()
		sizes[str(sd)] = sv.size
		bad[str(sd)] = sv.bad_keys
		print("ref seed %d: kayıt %d bayt, yasak anahtar %s, %d ms" % [sd, sv.size, str(sv.bad_keys), Time.get_ticks_msec() - t0])
	var vals: Array = sizes.values()
	var mn: int = vals.min()
	var mx: int = vals.max()
	var out := {"note": "Dalga 3 öncesi sezon sonu kayıt boyutu (Lib.setup_game + Lib.run_season, Game.save_game). hybrid_check ve hybrid_stats bunu ≤%105 sınırı için kullanır.",
		"commit": Lib.env_str("COMMIT", ""), "date": Time.get_date_string_from_system(),
		"save_size_after_season": sizes, "forbidden_keys_pre": bad,
		"spread_pct": snappedf(100.0 * (mx - mn) / maxf(1.0, float(mn)), 0.01)}
	var path := Lib.env_str("REF_OUT", ProjectSettings.globalize_path(Lib.REF_PATH))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ", true) + "\n")
	f.close()
	print("ref yazıldı: %s (seed'ler arası yayılım %%%.2f)" % [path, out.spread_pct])
	print("HYBRID_RESULT: PASS")
	get_tree().quit(0)

# ================================================================ tam ölçüm

func _full() -> void:
	var qe: Script = Lib.load_qe()
	if qe == null:
		print("SKIP: quick_engine yok (%s)" % Lib.qe_path())
		print("HYBRID_RESULT: SKIP")
		get_tree().quit(0)
		return
	var prob := Lib.qe_contract_problem(qe)
	if prob != "":
		print("quick_engine sözleşmesi: ", prob)
		print("HYBRID_RESULT: FAIL")
		get_tree().quit(1)
		return
	var seeds := _seeds("2301 4711 9001 1234 5678")
	var n_fast := Lib.env_int("N_FAST", 2000)
	var n_live := Lib.env_int("N_LIVE", 60)
	var n_eng := Lib.env_int("N_ENGINE", 2000)
	var smax := Lib.env_int("SEASONS_MAX", 8)
	var pooled := Lib.new_accs()
	var eng_acc := Lib.new_acc()
	var results := []
	var per_seed := []
	var routing := ""
	var t_all := Time.get_ticks_msec()
	for sd: int in seeds:
		var t0 := Time.get_ticks_msec()
		_start(sd)
		var info := Lib.routing_info()
		routing = Lib.routing_text(info)
		var row := {"seed": sd}
		if Lib.routing_ready(info):
			var st := {"accs": Lib.new_accs(), "stg_samples": [], "weeks": 0, "week_ms_max": 0}
			var seasons := 0
			while seasons < smax:
				Lib.run_season(info, st)
				seasons += 1
				if seasons == 1:
					var sv := Lib.save_scan()
					var ref := Lib.ref_size(sd)
					row.save_size = sv.size
					row.save_ref = ref.get("size", 0)
					row.save_ratio = float(sv.size) / maxf(1.0, float(ref.get("size", 0)))
					row.bad_keys = sv.bad_keys
					results.append(Lib._res("kayit.anahtar.s%d" % sd, (sv.bad_keys as Array).is_empty(), "seed %d kayıtta tl/cards: %s" % [sd, str(sv.bad_keys)]))
					if ref.is_empty():
						results.append(Lib._res("kayit.boyut.s%d" % sd, false, "seed %d: referans yok (%s)" % [sd, Lib.REF_PATH]))
					else:
						results.append(Lib._res("kayit.boyut.s%d" % sd, row.save_ratio <= Lib.SIZE_MAX, "seed %d: kayıt %d = referansın %%%.1f'i (%s, sınır %%%.0f)" % [sd, sv.size, 100.0 * row.save_ratio, ref.how, 100.0 * Lib.SIZE_MAX]))
				if int(st.accs.fast.n) >= n_fast:
					break
			row.seasons = seasons
			row.week_ms_max = st.week_ms_max
			row.max_fast_other = st.get("max_fast_other", 0)
			results.append(Lib._res("yonlendirme.12sinir.s%d" % sd, int(row.max_fast_other) <= Lib.FAST_SHORTLIST_CAP, "seed %d: haftada lig dışı en çok %d hızlı maç (sınır %d)" % [sd, row.max_fast_other, Lib.FAST_SHORTLIST_CAP]))
			results.append(Lib._res("tutarlilik.st_g.s%d" % sd, int(st.get("stg_bad", 0)) == 0 and int(st.get("gf_bad", 0)) == 0,
				"seed %d: Σst.g≠gol olayı %d hafta, lig gf uyumsuz %d/%d %s" % [sd, int(st.get("stg_bad", 0)), int(st.get("gf_bad", 0)), int(st.get("lg_checked", 0)), str(st.stg_samples.slice(0, 2))]))
			Game.finish_week()
			var det := Lib.determinism(info)
			results.append(Lib._res("determinizm.s%d" % sd, bool(det.ok), "seed %d %s" % [sd, det.msg]))
			var got := Lib.run_watched(n_live, st)
			row.watched = got
			for p: String in Lib.PATHS:
				Lib.merge_acc(pooled[p], st.accs[p])
			row.n = {}
			for p: String in Lib.PATHS:
				row.n[p] = int(st.accs[p].n)
		else:
			row.routing = "yok"
		var er := Lib.engine_checks(qe, n_eng, sd * 100003)
		for r: Dictionary in er.results:
			r.id = "%s.s%d" % [r.id, sd]
			results.append(r)
		Lib.merge_acc(eng_acc, er.acc)
		row.engine_ms = {"median": er.ms_median, "p99": er.ms_p99, "max": er.ms_max}
		results.append(Lib._res("motor.hiz.s%d" % sd, float(er.ms_median) <= 3.2 and float(er.ms_p99) <= 10.0, "seed %d motor süre medyan %.2f ms, p99 %.2f ms, en kötü %.2f ms (hedef medyan ≤3.2 / p99 ≤10; Dalga 2'de kabul edildi)" % [sd, er.ms_median, er.ms_p99, er.ms_max]))
		row.ms = Time.get_ticks_msec() - t0
		per_seed.append(row)
		print("seed %d bitti: %s" % [sd, JSON.stringify(row)])
	# birleşik değerlendirme (z = 0: kesin eşik)
	var mts := {"motor": Lib.metrics(eng_acc)}
	results.append_array(Lib.eval_bands("motor", mts.motor, 0.0))
	results.append_array(Lib.eval_consistency("motor", eng_acc))
	var have_route := int(pooled.fast.n) > 0 or int(pooled.poisson_d.n) > 0
	if have_route:
		for p: String in Lib.PATHS:
			mts[p] = Lib.metrics(pooled[p])
		mts["poisson"] = Lib.metrics(Lib.poisson_all(pooled))
		results.append(Lib._res("ornek.fast", int(mts.fast.n) >= n_fast * seeds.size(), "hızlı yol %d maç (hedef ≥%d)" % [mts.fast.n, n_fast * seeds.size()]))
		results.append_array(Lib.eval_bands("fast", mts.fast, 0.0))
		results.append_array(Lib.eval_bands("poisson", mts.poisson, 0.0))
		results.append_array(Lib.eval_pair("fast", mts.fast, "poisson", mts.poisson, 0.0, false))
		results.append_array(Lib.eval_pair("fast", mts.fast, "poisson_d", mts.poisson_d, 0.0, true))
		for p: String in ["fast", "poisson_d", "watched"]:
			results.append_array(Lib.eval_consistency(p, pooled[p]))
		results.append_array(Lib.eval_injuries(mts, ["poisson_d", "fast", "watched"], 0.0))
		# izlenen yol bilgi amaçlı (kapı değil): bantlar
		for r: Dictionary in Lib.eval_bands("watched", mts.watched, 0.0):
			r.id = "bilgi." + r.id
			r.info = true
			results.append(r)
	else:
		print("SKIP: Game yönlendirmesi yok — yalnız motor düzeyi ölçüldü")
	var fails := 0
	for r: Dictionary in results:
		var info_only := bool(r.get("info", false))
		if not bool(r.ok) and not info_only:
			fails += 1
		print("%s %s" % ["BILGI" if info_only else ("OK  " if r.ok else "FAIL"), r.msg])
	var verdict := "PASS" if fails == 0 else "FAIL"
	_write(results, mts, per_seed, routing, verdict, Time.get_ticks_msec() - t_all)
	print("HYBRID_RESULT: %s (%d kriter, %d kaldı, %d ms)" % [verdict, results.size(), fails, Time.get_ticks_msec() - t_all])
	get_tree().quit(0 if fails == 0 else 1)

func _write(results: Array, mts: Dictionary, per_seed: Array, routing: String, verdict: String, ms: int) -> void:
	var d := _out_dir()
	var rep := {"verdict": verdict, "routing": routing, "seeds": per_seed, "metrics": mts, "criteria": results, "ms": ms,
		"targets": {"gpm": Lib.T_GPM, "home_win_pct": Lib.T_HW, "draw_pct": Lib.T_DR, "big4_max_pct": Lib.T_BIG_MAX, "home_away_goal_ratio": Lib.T_HA,
			"path_diff_pts": Lib.D_RATE, "path_diff_gpm_rel": Lib.D_GPM_REL, "rt_mean": Lib.D_RT_MEAN, "rt_sd_rel": Lib.D_RT_SD_REL,
			"scorer_group_pts": Lib.D_SCORER, "minute_bucket_pts": Lib.D_MIN, "injury_rel": Lib.D_INJ_REL, "save_size_max": Lib.SIZE_MAX}}
	var f := FileAccess.open(d + "/hybrid_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  ", true) + "\n")
	f.close()
	f = FileAccess.open(d + "/hybrid_criteria.csv", FileAccess.WRITE)
	f.store_line("kriter,sonuc,mesaj")
	for r: Dictionary in results:
		f.store_line("%s,%s,\"%s\"" % [r.id, "BILGI" if r.get("info", false) else ("OK" if r.ok else "FAIL"), str(r.msg).replace("\"", "'")])
	f.close()
	f = FileAccess.open(d + "/hybrid_paths.csv", FileAccess.WRITE)
	f.store_line("yol,mac,gol_mac,ev_gal_pct,ber_pct,dep_pct,fark4_pct,ev_dep_gol,rt_ort,rt_sd,golcu_gk,golcu_def,golcu_mid,golcu_att,dk1_15,dk16_30,dk31_45,dk46_60,dk61_75,dk76_90,sakat,oyuncu_mac,sakat_oran")
	for p: String in mts:
		var mt: Dictionary = mts[p]
		var mins: Array = mt.mins
		f.store_line("%s,%d,%.3f,%.2f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.2f,%s,%d,%d,%.5f" % [p, mt.n, mt.gpm, mt.hw, mt.dr, mt.aw, mt.big, mt.ha, mt.rt_mean, mt.rt_sd,
			mt.grp.GK, mt.grp.DEF, mt.grp.MID, mt.grp.ATT, ",".join(PackedStringArray(mins.map(func(x: float) -> String: return "%.2f" % x))), mt.inj, mt.apps, mt.inj_rate])
	f.close()
	print("çıktı: %s/hybrid_report.json, hybrid_criteria.csv, hybrid_paths.csv" % d)
