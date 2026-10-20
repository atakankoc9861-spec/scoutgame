extends RefCounted
## v0.23 3b — Hibrit maç yolu (Poisson / hızlı motor / izlenen) ortak test + ölçüm kodu.
## Kullananlar: tests/check/hybrid_check.gd (küçük örnek, örnekleme toleranslı)
##              tests/baseline/hybrid_stats.gd (≥5 seed × 2000 maç, kesin eşikler)
##
## Yol tespiti (çalışma anında, hiçbir şey preload edilmez):
##   - hızlı motor: res://sim/quick_engine.gd (HYBRID_QE ile değiştirilebilir) var mı,
##     static simulate(g, m, youth, seed_v) -> Dictionary var mı
##   - yönlendirme: Game._use_fast(...) var mı (HYBRID_FAST_FN ile ad değiştirilebilir).
##     Müdür planındaki diğer adlar (_post_match_injuries, _credit_stats, s.sim_seed) raporlanır.
##   - HYBRID_FAKE_ROUTE=1: SADECE test kodunun kendisini doğrulamak için sahte yönlendirme
##     ("oyuncunun ligi = hızlı" diye etiketler, maçlar yine Poisson oynar).
##
## Yollar (acc anahtarları): "fast" (hızlı motor), "poisson_d" (ayrıntılı Poisson, oyunculu),
## "poisson_l" (ayrıntısız kulüp, oyuncusuz Poisson), "watched" (canlı motor, izlenen maç).

const QE_PATH_DEFAULT := "res://sim/quick_engine.gd"
const FAST_FN_DEFAULT := "_use_fast"
const PLANNED_FNS := ["_use_fast", "_post_match_injuries", "_credit_stats"]
const PATHS := ["fast", "poisson_d", "poisson_l", "watched"]
const GROUPS := ["GK", "DEF", "MID", "ATT"]
const SHORTLIST_N := 15

# --- Dalga 3 kapısı (Müdür planı §4) hedefleri: GERÇEK FUTBOL (BASELINE §3)
const T_GPM := [2.5, 3.1]
const T_HW := [41.0, 48.0]
const T_DR := [22.0, 29.0]
const T_BIG_MAX := 6.0          # 4+ farklı maç %
const T_HA := [1.15, 1.35]      # ev/dep gol oranı
const D_RATE := 3.0             # iki yol farkı, puan (ev/beraberlik/dep/4+)
const D_GPM_REL := 0.10         # iki yol gol/maç farkı, oransal
const D_RT_MEAN := 0.15
const D_RT_SD_REL := 0.15
const D_SCORER := 5.0           # golcü mevki grubu payı, puan
const D_MIN := 3.0              # 15 dk gol kovası payı, puan
const D_INJ_REL := 0.20         # sakatlık oranı, üç yol
const SIZE_MAX := 1.05          # kayıt boyutu / Dalga 3 öncesi
const FAST_SHORTLIST_CAP := 12  # Atakan kararı 2: haftada en fazla 12 shortlist maçı hızlı motora

# ================================================================ ortam / tespit

static func env_str(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

static func env_int(k: String, d: int) -> int:
	var v := OS.get_environment(k)
	return int(v) if v.is_valid_int() else d

static func qe_path() -> String:
	return env_str("HYBRID_QE", QE_PATH_DEFAULT)

## quick_engine betiği (yoksa null). preload değil: dosya yokken parse hatası olmasın.
static func load_qe() -> Script:
	var p := qe_path()
	if not ResourceLoader.exists(p):
		return null
	var sc = load(p)
	return sc as Script

## simulate sözleşmesi: static, 4 argüman. Sorun yoksa "" döner.
static func qe_contract_problem(sc: Script) -> String:
	if sc == null:
		return "betik yüklenemedi"
	for md: Dictionary in sc.get_script_method_list():
		if str(md.name) != "simulate":
			continue
		var nargs: int = (md.args as Array).size()
		if nargs != 4:
			return "simulate %d argüman alıyor (beklenen 4: g, m, youth, seed_v)" % nargs
		if (int(md.flags) & METHOD_FLAG_STATIC) == 0:
			return "simulate static değil"
		return ""
	return "simulate fonksiyonu yok"

static func _game_methods() -> Dictionary:
	var out := {}
	var sc: Script = Game.get_script()
	if sc == null:
		return out
	for md: Dictionary in sc.get_script_method_list():
		out[str(md.name)] = md
	return out

## Game yönlendirmesinin durumu: hangi planlı adlar var, benzer adlar, kaynakta quick_engine geçiyor mu
static func routing_info() -> Dictionary:
	var ms := _game_methods()
	var fn := env_str("HYBRID_FAST_FN", FAST_FN_DEFAULT)
	var info := {"fast_fn": fn, "has_fast": ms.has(fn), "fast_args": [], "planned": {}, "similar": [],
		"mentions_qe": false, "fake": OS.get_environment("HYBRID_FAKE_ROUTE") == "1", "has_sim_seed": false}
	if ms.has(fn):
		for a: Dictionary in ms[fn].args:
			info.fast_args.append(str(a.name))
	for n: String in PLANNED_FNS:
		info.planned[n] = ms.has(n)
	var re := RegEx.create_from_string("fast|quick|credit|injur|route|path")
	for n: String in ms:
		if re.search(n.to_lower()) != null:
			info.similar.append(n)
	var sc: Script = Game.get_script()
	if sc != null and sc.has_source_code():
		info.mentions_qe = sc.source_code.contains("quick_engine")
	info.has_sim_seed = Game.s.has("sim_seed")
	return info

static func routing_ready(info: Dictionary) -> bool:
	return bool(info.has_fast) or bool(info.fake)

## Bu maç hızlı yola mı gidecek? (maç oynanmadan önce sorulur)
static func is_fast(info: Dictionary, wm: Dictionary) -> bool:
	if bool(info.fake):
		var my_lg: String = str(Game.club(str(Game.s.scout.club_id)).get("league", ""))
		return wm.lg == my_lg and not is_lazy_match(wm.m)
	var args := []
	var names: Array = info.fast_args
	for i in names.size():
		var n: String = str(names[i]).to_lower()
		if n in ["m", "match", "match_d", "md", "fx"]:
			args.append(wm.m)
		elif n in ["lg", "league", "lgid"]:
			args.append(wm.lg)
		elif n in ["youth", "is_youth", "u19"]:
			args.append(false)
		elif n in ["wm", "entry", "w"]:
			args.append(wm)
		elif n in ["key", "mkey"]:
			args.append(Game.match_key(wm.lg, wm.idx))
		elif n in ["idx", "i"]:
			args.append(wm.idx)
		else:
			# bilinmeyen ad: konuma göre m, lg, false
			args.append([wm.m, wm.lg, false][mini(i, 2)])
	return bool(Game.callv(str(info.fast_fn), args))

static func routing_text(info: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("%s(%s)=%s" % [info.fast_fn, ", ".join(PackedStringArray(info.fast_args)), "var" if info.has_fast else "YOK"])
	for n: String in info.planned:
		if n != info.fast_fn:
			parts.append("%s=%s" % [n, "var" if info.planned[n] else "yok"])
	parts.append("s.sim_seed=%s" % ("var" if info.has_sim_seed else "yok"))
	parts.append("Game kaynağında quick_engine=%s" % ("geçiyor" if info.mentions_qe else "geçmiyor"))
	if not (info.similar as Array).is_empty():
		parts.append("benzer adlar: " + ", ".join(PackedStringArray(info.similar)))
	if info.fake:
		parts.append("SAHTE YÖNLENDİRME (HYBRID_FAKE_ROUTE=1, yalnız test kodu doğrulaması)")
	return "; ".join(parts)

static func is_lazy_match(m: Dictionary) -> bool:
	return Game.is_lazy(str(m.h)) or Game.is_lazy(str(m.a))

# ================================================================ birikimci

static func new_acc() -> Dictionary:
	return {"n": 0, "goals": 0, "goals_sq": 0, "gh": 0, "ga": 0, "hw": 0, "dr": 0, "aw": 0, "big": 0,
		"ev_n": 0, "grp": {"GK": 0, "DEF": 0, "MID": 0, "ATT": 0}, "mins": [0, 0, 0, 0, 0, 0],
		"rt_n": 0, "rt_sum": 0.0, "rt_sq": 0.0, "apps": 0, "inj": 0,
		"bad_count": 0, "bad_scorer": 0, "bad_min": 0, "no_xi": 0, "no_rt": 0, "detailed": 0, "bad_samples": []}

static func new_accs() -> Dictionary:
	var a := {}
	for p: String in PATHS:
		a[p] = new_acc()
	return a

static func merge_acc(dst: Dictionary, src: Dictionary) -> void:
	for k: String in src:
		var v = src[k]
		if k == "bad_samples":
			for x in v:
				if (dst[k] as Array).size() < 10:
					dst[k].append(x)
		elif v is Dictionary:
			for kk in v:
				dst[k][kk] = dst[k].get(kk, 0) + v[kk]
		elif v is Array:
			for i in (v as Array).size():
				dst[k][i] += v[i]
		else:
			dst[k] += v

static func _bad(a: Dictionary, msg: String) -> void:
	if (a.bad_samples as Array).size() < 10:
		a.bad_samples.append(msg)

## Oynanmış bir maçı birikimciye ekler. detailed: iki kulüp de ayrıntılı (oyunculu).
## inj/apps: bu maçta sakatlanan / oynayan oyuncu sayısı (ilk 11'den).
static func add_match(a: Dictionary, m: Dictionary, detailed: bool, inj: int, apps: int, tag: String) -> void:
	var gh: int = int(m.gh)
	var ga: int = int(m.ga)
	a.n += 1
	a.goals += gh + ga
	a.goals_sq += (gh + ga) * (gh + ga)
	a.gh += gh
	a.ga += ga
	if gh > ga:
		a.hw += 1
	elif gh == ga:
		a.dr += 1
	else:
		a.aw += 1
	if absi(gh - ga) >= 4:
		a.big += 1
	a.inj += inj
	a.apps += apps
	if not detailed:
		return
	a.detailed += 1
	var xh: Array = m.get("xi_h", [])
	var xa: Array = m.get("xi_a", [])
	if xh.is_empty() or xa.is_empty():
		a.no_xi += 1
		_bad(a, "%s ilk 11 kaydı yok" % tag)
	var cnt := {"h": 0, "a": 0}
	for e: Dictionary in m.get("ev", []):
		if str(e.get("t", "")) != "g":
			continue
		var sd: String = str(e.get("side", ""))
		cnt[sd] = int(cnt.get(sd, 0)) + 1
		var pid: String = str(e.get("pid", ""))
		var xi: Array = xh if sd == "h" else xa
		if not (pid in xi):
			a.bad_scorer += 1
			_bad(a, "%s golcü %s %s tarafının ilk 11'inde değil" % [tag, pid, sd])
		var p: Dictionary = Game.player(pid)
		if not p.is_empty():
			a.grp[Data.POS_GROUP[p.pos]] += 1
		var mn: int = int(e.get("min", -1))
		if mn < 1 or mn > 90:
			a.bad_min += 1
			_bad(a, "%s gol dakikası aralık dışı: %d" % [tag, mn])
		else:
			a.mins[mini(5, (mn - 1) / 15)] += 1
		a.ev_n += 1
	if int(cnt.h) != gh or int(cnt.a) != ga:
		a.bad_count += 1
		_bad(a, "%s gol olayı %d-%d, skor %d-%d" % [tag, int(cnt.h), int(cnt.a), gh, ga])
	var rt: Dictionary = m.get("rt", {})
	if rt.is_empty():
		a.no_rt += 1
	for pid in rt:
		var r: float = float(rt[pid])
		a.rt_n += 1
		a.rt_sum += r
		a.rt_sq += r * r

# ================================================================ ölçütler

static func _pct(k: int, n: int) -> float:
	return 100.0 * k / maxf(1.0, float(n))

static func _se_pct(k: int, n: int) -> float:
	var p := float(k) / maxf(1.0, float(n))
	return 100.0 * sqrt(maxf(p * (1.0 - p), 0.0) / maxf(1.0, float(n)))

## Birikimciden oranlar + standart hatalar
static func metrics(a: Dictionary) -> Dictionary:
	var n: int = int(a.n)
	var nn := maxf(1.0, float(n))
	var gpm: float = a.goals / nn
	var var_g: float = maxf(0.0, a.goals_sq / nn - gpm * gpm)
	var out := {
		"n": n, "detailed": int(a.detailed),
		"gpm": gpm, "gpm_se": sqrt(var_g / nn),
		"hw": _pct(a.hw, n), "hw_se": _se_pct(a.hw, n),
		"dr": _pct(a.dr, n), "dr_se": _se_pct(a.dr, n),
		"aw": _pct(a.aw, n), "aw_se": _se_pct(a.aw, n),
		"big": _pct(a.big, n), "big_se": _se_pct(a.big, n),
		"ha": float(a.gh) / maxf(1.0, float(a.ga)),
		"ha_se": (float(a.gh) / maxf(1.0, float(a.ga))) * sqrt(1.0 / maxf(1.0, float(a.gh)) + 1.0 / maxf(1.0, float(a.ga))),
		"ev_n": int(a.ev_n), "rt_n": int(a.rt_n),
		"rt_mean": 0.0, "rt_sd": 0.0, "rt_mean_se": 0.0,
		"grp": {}, "grp_se": {}, "mins": [], "mins_se": [],
		"apps": int(a.apps), "inj": int(a.inj),
		"inj_rate": float(a.inj) / maxf(1.0, float(a.apps)),
		"inj_se": sqrt(float(a.inj)) / maxf(1.0, float(a.apps)),
	}
	if int(a.rt_n) > 0:
		var mu: float = a.rt_sum / float(a.rt_n)
		out.rt_mean = mu
		out.rt_sd = sqrt(maxf(0.0, a.rt_sq / float(a.rt_n) - mu * mu))
		# aynı maçtaki reytingler bağımlı: etkin örnek ~ maç sayısı × 2
		out.rt_mean_se = out.rt_sd / sqrt(maxf(1.0, 2.0 * float(a.detailed)))
	for gname: String in GROUPS:
		out.grp[gname] = _pct(a.grp[gname], a.ev_n)
		out.grp_se[gname] = _se_pct(a.grp[gname], a.ev_n)
	for i in 6:
		out.mins.append(_pct(a.mins[i], a.ev_n))
		out.mins_se.append(_se_pct(a.mins[i], a.ev_n))
	return out

## Sonuç satırı: {id, ok, msg}. z = örnekleme toleransı (0 = kesin eşik).
static func _res(id: String, ok: bool, msg: String) -> Dictionary:
	return {"id": id, "ok": ok, "msg": msg}

static func band(id: String, v: float, se: float, lo: float, hi: float, z: float, fmt := "%.2f") -> Dictionary:
	var tol := z * se
	var ok := v >= lo - tol and v <= hi + tol
	return _res(id, ok, ("%s = " + fmt + " (hedef " + fmt + "–" + fmt + ", örnekleme payı ±" + fmt + ")") % [id, v, lo, hi, tol])

static func diff(id: String, a: float, b: float, se_a: float, se_b: float, thr: float, z: float, fmt := "%.2f") -> Dictionary:
	var tol := z * sqrt(se_a * se_a + se_b * se_b)
	var d := absf(a - b)
	return _res(id, d <= thr + tol, ("%s: " + fmt + " vs " + fmt + ", fark " + fmt + " (eşik " + fmt + " + örnekleme " + fmt + ")") % [id, a, b, d, thr, tol])

## Tek yolun gerçek futbol bantları
static func eval_bands(path: String, mt: Dictionary, z: float) -> Array:
	var out := []
	out.append(band(path + ".gol_mac", mt.gpm, mt.gpm_se, T_GPM[0], T_GPM[1], z))
	out.append(band(path + ".ev_galibiyet_%", mt.hw, mt.hw_se, T_HW[0], T_HW[1], z, "%.1f"))
	out.append(band(path + ".beraberlik_%", mt.dr, mt.dr_se, T_DR[0], T_DR[1], z, "%.1f"))
	out.append(band(path + ".4+_fark_%", mt.big, mt.big_se, 0.0, T_BIG_MAX, z, "%.1f"))
	out.append(band(path + ".ev/dep_gol", mt.ha, mt.ha_se, T_HA[0], T_HA[1], z))
	return out

## İki yolun farkı: oranlar, gol/maç, reyting, golcü grubu, gol dakikası
static func eval_pair(pa: String, a: Dictionary, pb: String, b: Dictionary, z: float, with_detail: bool) -> Array:
	var out := []
	var t := pa + "~" + pb
	for k: String in ["hw", "dr", "aw", "big"]:
		out.append(diff("%s.%s_%%" % [t, k], a[k], b[k], a[k + "_se"], b[k + "_se"], D_RATE, z, "%.1f"))
	var ref_g: float = maxf(0.01, (float(a.gpm) + float(b.gpm)) / 2.0)
	out.append(diff(t + ".gol_mac", a.gpm, b.gpm, a.gpm_se, b.gpm_se, D_GPM_REL * ref_g, z))
	if not with_detail:
		return out
	out.append(diff(t + ".reyting_ort", a.rt_mean, b.rt_mean, a.rt_mean_se, b.rt_mean_se, D_RT_MEAN, z))
	var sd_ref: float = maxf(0.01, float(b.rt_sd))
	var sd_rel: float = absf(float(a.rt_sd) - sd_ref) / sd_ref
	var sd_tol: float = z * 1.0 / sqrt(maxf(1.0, 2.0 * float(mini(int(a.detailed), int(b.detailed)))))
	out.append(_res(t + ".reyting_sd", sd_rel <= D_RT_SD_REL + sd_tol,
		"%s.reyting_sd: %.3f vs %.3f, oransal fark %%%.1f (eşik %%%.0f + örnekleme %%%.1f)" % [t, a.rt_sd, b.rt_sd, 100.0 * sd_rel, 100.0 * D_RT_SD_REL, 100.0 * sd_tol]))
	for gname: String in GROUPS:
		out.append(diff("%s.golcu_%s_%%" % [t, gname], a.grp[gname], b.grp[gname], a.grp_se[gname], b.grp_se[gname], D_SCORER, z, "%.1f"))
	for i in 6:
		out.append(diff("%s.gol_dk_%d-%d_%%" % [t, i * 15 + 1, i * 15 + 15], a.mins[i], b.mins[i], a.mins_se[i], b.mins_se[i], D_MIN, z, "%.1f"))
	return out

## Sakatlık oranı: her yol, tüm yolların ortalamasına göre ±%20 (+ örnekleme)
static func eval_injuries(mts: Dictionary, paths: Array, z: float) -> Array:
	var out := []
	var tot_inj := 0
	var tot_apps := 0
	for p: String in paths:
		tot_inj += int(mts[p].inj)
		tot_apps += int(mts[p].apps)
	var ref: float = float(tot_inj) / maxf(1.0, float(tot_apps))
	for p: String in paths:
		var mt: Dictionary = mts[p]
		if int(mt.apps) == 0:
			out.append(_res("sakatlik." + p, false, "sakatlik.%s: hiç maç/oyuncu yok" % p))
			continue
		var rel: float = absf(float(mt.inj_rate) - ref) / maxf(1e-9, ref)
		# örnekleme payı: ortak oran doğruysa bu yolda beklenen Poisson sapması
		var expct: float = ref * float(mt.apps)
		var tol: float = z / sqrt(maxf(1e-9, expct))
		var ok: bool = ref > 0.0 and rel <= D_INJ_REL + tol
		if expct >= 5.0 and int(mt.inj) == 0:
			ok = false   # beklenen ≥5 iken sıfır: yol sakatlık uygulamıyor
		out.append(_res("sakatlik." + p, ok,
			"sakatlik.%s: %.4f/oyuncu-maç (%d/%d), ortak %.4f, oransal fark %%%.0f (eşik %%%.0f + örnekleme %%%.0f)" % [p, mt.inj_rate, mt.inj, mt.apps, ref, 100.0 * rel, 100.0 * D_INJ_REL, 100.0 * tol]))
	return out

## Tutarlılık: olay sayısı = skor, golcü ilk 11'de, dakika 1..90 (örnekleme yok, kesin)
static func eval_consistency(path: String, a: Dictionary) -> Array:
	var out := []
	var samp: String = "" if (a.bad_samples as Array).is_empty() else " örn: " + str(a.bad_samples[0])
	out.append(_res(path + ".gol_olayi=skor", int(a.bad_count) == 0, "%s: %d/%d ayrıntılı maçta gol olayı sayısı skora eşit değil%s" % [path, a.bad_count, a.detailed, samp]))
	out.append(_res(path + ".golcu_ilk11", int(a.bad_scorer) == 0, "%s: %d golcü kendi tarafının ilk 11'inde değil" % [path, a.bad_scorer]))
	out.append(_res(path + ".gol_dk_1-90", int(a.bad_min) == 0, "%s: %d gol dakikası 1..90 dışında" % [path, a.bad_min]))
	out.append(_res(path + ".ilk11_kaydi", int(a.no_xi) == 0, "%s: %d ayrıntılı maçta xi_h/xi_a yok" % [path, a.no_xi]))
	out.append(_res(path + ".reyting_kaydi", int(a.no_rt) == 0, "%s: %d ayrıntılı maçta rt yok" % [path, a.no_rt]))
	return out

# ================================================================ dünya / sezon akışı

## Yeni oyun + iş + shortlist (başka liglerden SHORTLIST_N oyuncu; 12 maç sınırını da yoklar).
## rng'ye dokunmaz (ölçüm referansıyla aynı akış).
static func setup_game() -> void:
	Game.new_game("T", "tr")
	var offers: Array = Game.job_offers_start()
	Game.take_job(str(offers[0]))
	var my_lg: String = str(Game.my_club().get("league", ""))
	var picked := 0
	var leagues: Array = Game.s.fixtures.keys()
	leagues.sort()
	for lg: String in leagues:
		if lg == my_lg or picked >= SHORTLIST_N:
			continue
		for cid: String in Game.league_clubs(lg):
			if Game.is_lazy(cid) or picked >= SHORTLIST_N:
				continue
			var sq: Array = Game.club(cid).squad
			if sq.is_empty():
				continue
			var pid: String = str(sq[0])
			if not (pid in Game.s.scout.shortlist):
				Game.toggle_shortlist(pid)
				picked += 1
			break

static func _goal_events(m: Dictionary) -> int:
	var n := 0
	for e: Dictionary in m.get("ev", []):
		if str(e.get("t", "")) == "g":
			n += 1
	return n

static func _sum_st_g() -> int:
	var t := 0
	for pid in Game.s.players:
		t += int(Game.s.players[pid].st.g)
	return t

## Ayrıntılı kulüplerin oyuncu -> lig haritası
static func _pid_league() -> Dictionary:
	var out := {}
	for cid in Game.s.clubs:
		if Game.is_lazy(str(cid)) or Game.is_scout_club(str(cid)):
			continue
		var lg: String = str(Game.s.clubs[cid].league)
		for pid in Game.s.clubs[cid].squad:
			out[pid] = lg
	return out

## Bir haftayı oynatır: maçlar play_day ile (yönlendirme orada/ sim_match'te), sonra finish_week.
## Her maçı yoluna göre birikimciye ekler, sakatlıkları ilk 11'den sayar, st.g / tablo gf tutarlılığını ölçer.
## st: sezon durumu sözlüğü (birikimciler + sayaçlar). Dönüş: finish_week sonucu.
static func play_week(info: Dictionary, st: Dictionary) -> Dictionary:
	var wms: Array = Game.week_matches()
	var route := routing_ready(info)
	var classes := []
	var fast_other := 0
	var my_lg: String = str(Game.my_club().get("league", ""))
	var s_before := ""
	if route and not bool(st.get("purity_checked", false)) and not wms.is_empty():
		s_before = JSON.stringify(Game.s)
	for wm: Dictionary in wms:
		var c := {"wm": wm, "path": "", "detailed": false}
		if int(wm.m.gh) < 0:
			var f := route and is_fast(info, wm)
			c.detailed = not is_lazy_match(wm.m)
			c.path = "fast" if f else ("poisson_d" if c.detailed else "poisson_l")
			if f and wm.lg != my_lg:
				fast_other += 1
		classes.append(c)
	if s_before != "":
		st.purity_checked = true
		st.fast_fn_pure = JSON.stringify(Game.s) == s_before
	st.max_fast_other = maxi(int(st.get("max_fast_other", 0)), fast_other)
	var inj0 := {}
	for pid in Game.s.players:
		inj0[pid] = int(Game.s.players[pid].inj)
	var g0 := _sum_st_g()
	var pl0 := _pid_league()
	var sg0 := _league_st_g(pl0)
	var gf0 := _league_gf()
	for day in ["sat", "sun"]:
		Game.play_day(day)
	var ev_goals := 0
	var lg_ev := {}
	var lg_all_detailed := {}
	for c: Dictionary in classes:
		var m: Dictionary = c.wm.m
		var lg: String = c.wm.lg
		if c.path == "":
			continue
		if int(m.gh) < 0:
			st.unplayed = int(st.get("unplayed", 0)) + 1
			continue
		var xi: Array = (m.get("xi_h", []) as Array) + (m.get("xi_a", []) as Array)
		var inj := 0
		for pid in xi:
			if int(inj0.get(pid, 0)) == 0 and int(Game.player(str(pid)).get("inj", 0)) > 0:
				inj += 1
		add_match(st.accs[c.path], m, c.detailed, inj, xi.size(), "%s %s:%d s%dw%d" % [c.path, lg, c.wm.idx, int(Game.s.season), int(Game.s.week)])
		var ng := _goal_events(m)
		ev_goals += ng
		lg_ev[lg] = int(lg_ev.get(lg, 0)) + ng
		lg_all_detailed[lg] = bool(lg_all_detailed.get(lg, true)) and c.detailed
	# (a) Σ st.g farkı = gol olayları (tüm maçlar; ayrıntısız maçta ikisi de 0)
	var dg := _sum_st_g() - g0
	st.stg_weeks = int(st.get("stg_weeks", 0)) + 1
	if dg != ev_goals:
		st.stg_bad = int(st.get("stg_bad", 0)) + 1
		if (st.stg_samples as Array).size() < 5:
			st.stg_samples.append("s%dw%d: Δ Σst.g=%d, gol olayı=%d" % [int(Game.s.season), int(Game.s.week), dg, ev_goals])
	# (b) tüm maçları ayrıntılı liglerde: Σ Δst.g (lig oyuncuları) = Δ tablo gf = gol olayları
	var sg1 := _league_st_g(pl0)
	var gf1 := _league_gf()
	for lg in lg_all_detailed:
		if not lg_all_detailed[lg]:
			continue
		var dgf: int = int(gf1.get(lg, 0)) - int(gf0.get(lg, 0))
		var dsg: int = int(sg1.get(lg, 0)) - int(sg0.get(lg, 0))
		st.lg_checked = int(st.get("lg_checked", 0)) + 1
		if dgf != dsg or dgf != int(lg_ev.get(lg, 0)):
			st.gf_bad = int(st.get("gf_bad", 0)) + 1
			if (st.stg_samples as Array).size() < 5:
				st.stg_samples.append("s%dw%d %s: Δgf=%d, Δ Σst.g=%d, gol olayı=%d" % [int(Game.s.season), int(Game.s.week), lg, dgf, dsg, int(lg_ev.get(lg, 0))])
	return Game.finish_week()

static func _league_st_g(pl: Dictionary) -> Dictionary:
	var out := {}
	for pid in pl:
		var p: Dictionary = Game.player(str(pid))
		if p.is_empty():
			continue
		out[pl[pid]] = int(out.get(pl[pid], 0)) + int(p.st.g)
	return out

static func _league_gf() -> Dictionary:
	var out := {}
	for lg in Game.s.table:
		var t := 0
		for cid in Game.s.table[lg]:
			t += int(Game.s.table[lg][cid].gf)
		out[lg] = t
	return out

## Bir sezonu oynatır (week 0'dan sezon devrine kadar). Dönüş: st (birikimciler ve sayaçlar).
static func run_season(info: Dictionary, st: Dictionary = {}) -> Dictionary:
	if st.is_empty():
		st = {"accs": new_accs(), "stg_samples": [], "weeks": 0, "week_ms_max": 0}
	var s0: int = int(Game.s.season)
	var guard := 0
	while int(Game.s.season) == s0 and guard < Game.WEEKS + 5:
		var t0 := Time.get_ticks_msec()
		play_week(info, st)
		st.week_ms_max = maxi(int(st.week_ms_max), Time.get_ticks_msec() - t0)
		st.weeks = int(st.weeks) + 1
		guard += 1
	return st

## Poisson yolu tek birikimci (ayrıntılı + ayrıntısız)
static func poisson_all(accs: Dictionary) -> Dictionary:
	var a := new_acc()
	merge_acc(a, accs.poisson_d)
	merge_acc(a, accs.poisson_l)
	return a

# ================================================================ izlenen yol

## Bu haftadan başlayarak n maçı izlenen yol ile oynatır (watch_match_data → finish_live → apply_watch),
## kalan maçlar finish_week ile biter. Dönüş: izlenen maç sayısı.
static func run_watched(n: int, st: Dictionary) -> int:
	var count := 0
	var guard := 0
	while count < n and guard < Game.WEEKS + 5:
		guard += 1
		if int(Game.s.week) < 1 or int(Game.s.week) > Game.WEEKS:
			Game.finish_week()
			continue
		for wm: Dictionary in Game.week_matches():
			if count >= n:
				break
			if int(wm.m.gh) >= 0 or is_lazy_match(wm.m):
				continue
			var inj0 := {}
			for cid in [wm.m.h, wm.m.a]:
				for pid in Game.club(str(cid)).squad:
					inj0[pid] = int(Game.player(str(pid)).get("inj", 0))
			var data: Dictionary = Game.watch_match_data(Game.match_key(wm.lg, wm.idx))
			Game.finish_live(data)
			Game.apply_watch(data, {})
			var m: Dictionary = data.m
			var xi: Array = (m.get("xi_h", []) as Array) + (m.get("xi_a", []) as Array)
			var inj := 0
			for pid in xi:
				if int(inj0.get(pid, 0)) == 0 and int(Game.player(str(pid)).get("inj", 0)) > 0:
					inj += 1
			add_match(st.accs.watched, m, true, inj, xi.size(), "watched %s:%d s%dw%d" % [wm.lg, wm.idx, int(Game.s.season), int(Game.s.week)])
			count += 1
		Game.finish_week()
	return count

# ================================================================ determinizm

static func _write_save(txt: String) -> void:
	var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(txt)
		f.close()

static func _rt_sorted(rt: Dictionary) -> Array:
	var keys: Array = rt.keys()
	keys.sort()
	var out := []
	for k in keys:
		out.append([str(k), snappedf(float(rt[k]), 0.1)])
	return out

static func _goal_ev_only(ev: Array) -> Array:
	var out := []
	for e: Dictionary in ev:
		if str(e.get("t", "")) == "g":
			out.append([str(e.pid), str(e.get("as", "")), str(e.side), int(e.min)])
	return out

## Aynı kayıt + aynı hafta iki kez (FARKLI Game.rng tohumuyla) oynanır; hızlı yol maçlarının
## gh/ga/ev(gol)/rt özeti birebir aynı olmalı. Hafta >= 1 olmalı. Durum sonunda kayıttan geri yüklenir.
static func determinism(info: Dictionary) -> Dictionary:
	var out := {"ok": false, "fast": 0, "same": 0, "xi_diff": 0, "inj_ev_diff": 0, "class_diff": false, "msg": "", "samples": []}
	Game.save_game()
	var txt := FileAccess.get_file_as_string(Game.SAVE_PATH)
	var runs := []
	for sd: int in [11, 977]:
		_write_save(txt)
		if not Game.load_game():
			out.msg = "determinizm: load_game() false"
			return out
		var keys := []
		for wm: Dictionary in Game.week_matches():
			if int(wm.m.gh) < 0 and is_fast(info, wm):
				keys.append(wm)
		Game.rng.seed = sd
		seed(sd * 7 + 1)
		for day in ["sat", "sun"]:
			Game.play_day(day)
		var r := {}
		for wm: Dictionary in keys:
			var m: Dictionary = wm.m
			var k: String = Game.match_key(wm.lg, wm.idx)
			r[k] = {
				"h": JSON.stringify([int(m.gh), int(m.ga), _goal_ev_only(m.get("ev", [])), _rt_sorted(m.get("rt", {}))]),
				"xi": JSON.stringify([m.get("xi_h", []), m.get("xi_a", [])]),
				"all_ev": JSON.stringify(m.get("ev", [])),
			}
		runs.append(r)
	_write_save(txt)
	Game.load_game()
	var a: Dictionary = runs[0]
	var b: Dictionary = runs[1]
	out.fast = a.size()
	out.class_diff = a.keys() != b.keys()
	for k in a:
		if not b.has(k):
			continue
		if a[k].h == b[k].h:
			out.same += 1
		elif (out.samples as Array).size() < 3:
			out.samples.append("%s: %s | %s" % [k, str(a[k].h).left(100), str(b[k].h).left(100)])
		if a[k].xi != b[k].xi:
			out.xi_diff += 1
		if a[k].all_ev != b[k].all_ev:
			out.inj_ev_diff += 1
	out.ok = out.fast > 0 and not out.class_diff and out.same == out.fast
	var why := ""
	if out.fast == 0:
		why = "bu hafta hiç hızlı yol maçı yok"
	elif out.class_diff:
		why = "iki oynatmada hızlı yol seçimi farklı"
	elif out.same != out.fast:
		why = "ilk 11 Game.rng ile seçiliyor (sim_seed'den türetilmeli)" if out.xi_diff > 0 else "ilk 11 aynı ama motor sonucu farklı (seed_v / çağrı sırası / global rng)"
	out.msg = "determinizm: %d hızlı maçın %d'i aynı (ilk 11 farklı: %d, sakatlık dahil ev farklı: %d)%s" % [out.fast, out.same, out.xi_diff, out.inj_ev_diff, (" — " + why) if why != "" else ""]
	return out

# ================================================================ kayıt

static func _scan_keys(v: Variant, path: String, bad: Array, keys: Array) -> void:
	if bad.size() >= 10:
		return
	if v is Dictionary:
		for k in v:
			if str(k) in keys and bad.size() < 10:
				bad.append(path + "/" + str(k))
			_scan_keys(v[k], path + "/" + str(k), bad, keys)
	elif v is Array:
		for i in (v as Array).size():
			_scan_keys(v[i], "%s[%d]" % [path, i], bad, keys)

## Kaydı yazar, boyutunu ve yasak anahtarları (tl, cards) döndürür
static func save_scan() -> Dictionary:
	Game.save_game()
	var txt := FileAccess.get_file_as_string(Game.SAVE_PATH)
	var j := JSON.new()
	var bad := []
	if j.parse(txt) == OK:
		_scan_keys(j.data, "", bad, ["tl", "cards"])
	else:
		bad.append("(kayıt JSON değil)")
	return {"size": txt.length(), "bad_keys": bad}

const REF_PATH := "res://tests/baseline/hybrid_ref.json"

## Dalga 3 öncesi kayıt boyutu referansı (hybrid_stats MODE=ref ile üretilir). seed yoksa ortalama.
static func ref_size(sd: int) -> Dictionary:
	if not FileAccess.file_exists(REF_PATH):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(REF_PATH)) != OK:
		return {}
	var d: Dictionary = j.data
	var by: Dictionary = d.get("save_size_after_season", {})
	if by.has(str(sd)):
		return {"size": int(by[str(sd)]), "how": "seed %d" % sd, "commit": str(d.get("commit", ""))}
	if by.is_empty():
		return {}
	var t := 0
	for k in by:
		t += int(by[k])
	return {"size": t / by.size(), "how": "%d seed ortalaması" % by.size(), "commit": str(d.get("commit", ""))}

# ================================================================ motor düzeyi (quick_engine doğrudan)

## Ayrıntılı kulüpler arasındaki fikstür maçlarından n maç kopyası (xi önceden dolu)
static func engine_matches(n: int) -> Array:
	var out := []
	var leagues: Array = Game.s.fixtures.keys()
	leagues.sort()
	var pairs := []
	for lg: String in leagues:
		for rnd: Array in Game.s.fixtures[lg]:
			for m: Dictionary in rnd:
				if not is_lazy_match(m):
					pairs.append([m.h, m.a])
	if pairs.is_empty():
		return out
	var i := 0
	while out.size() < n:
		var pr: Array = pairs[i % pairs.size()]
		out.append({"h": pr[0], "a": pr[1], "day": "sat", "gh": -1, "ga": -1, "ev": [],
			"xi_h": Game.best_xi(str(pr[0]), true), "xi_a": Game.best_xi(str(pr[1]), true)})
		i += 1
	return out

static func _rt_ok(rt: Dictionary, xi: Array) -> String:
	for pid in xi:
		if not rt.has(pid):
			return "rt'de %s yok" % str(pid)
	for pid in rt:
		var r: float = float(rt[pid])
		if not is_finite(r) or r < 1.0 or r > 10.0:
			return "rt[%s]=%s aralık dışı" % [str(pid), str(rt[pid])]
		if absf(r * 10.0 - roundf(r * 10.0)) > 0.001:
			return "rt[%s]=%s 0.1 adımında değil" % [str(pid), str(rt[pid])]
	return ""

## quick_engine'i doğrudan sınar: sözleşme, saflık, determinizm, çağrı sırası, tutarlılık, hız.
## Dönüş: {results:[{id,ok,msg}], acc, ms_median, ms_max, ms_p99}
static func engine_checks(qe: Script, n: int, seed_base: int) -> Dictionary:
	var res := []
	var acc := new_acc()
	var ms := []
	var matches := engine_matches(n)
	if matches.is_empty():
		res.append(_res("motor.ornek", false, "motor: ayrıntılı maç bulunamadı"))
		return {"results": res, "acc": acc, "ms_median": 0.0, "ms_max": 0.0, "ms_p99": 0.0}
	var s_hash := JSON.stringify(Game.s).hash()
	var rng_state: int = Game.rng.state
	var bad_contract := 0
	var bad_pure := 0
	var bad_rt := 0
	var first_bad := ""
	var outs := []
	for i in matches.size():
		var m: Dictionary = matches[i]
		var before := JSON.stringify(m)
		var t0 := Time.get_ticks_usec()
		var r = qe.call("simulate", Game, m, false, seed_base + i)
		ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		if JSON.stringify(m) != before:
			bad_pure += 1
			if first_bad == "":
				first_bad = "m değiştirildi (maç %d)" % i
		if not (r is Dictionary) or not (r.has("gh") and r.has("ga") and r.has("ev") and r.has("rt") and r.has("cards") and r.has("team")):
			bad_contract += 1
			if first_bad == "":
				first_bad = "dönüş anahtarları eksik: %s" % (str(r.keys()) if r is Dictionary else str(typeof(r)))
			outs.append("")
			continue
		var d: Dictionary = r
		outs.append(JSON.stringify(d, "", true))
		var m2 := m.duplicate(true)
		m2.gh = int(d.gh)
		m2.ga = int(d.ga)
		m2.ev = d.ev
		m2.rt = d.rt
		add_match(acc, m2, true, 0, 0, "motor maç %d" % i)
		var why := _rt_ok(d.rt, (m.xi_h as Array) + (m.xi_a as Array))
		if why != "":
			bad_rt += 1
			if first_bad == "":
				first_bad = why
		for e: Dictionary in d.ev:
			if str(e.get("t", "")) != "g" or not e.has("as"):
				bad_contract += 1
				if first_bad == "":
					first_bad = "ev öğesi gol biçiminde değil: %s" % str(e)
				break
	res.append(_res("motor.sozlesme", bad_contract == 0, "motor: %d/%d dönüş sözleşmeye uymuyor%s" % [bad_contract, matches.size(), (" — " + first_bad) if first_bad != "" else ""]))
	res.append(_res("motor.saf_m", bad_pure == 0, "motor: %d maçta m değişti" % bad_pure))
	res.append(_res("motor.saf_rng", Game.rng.state == rng_state, "motor: Game.rng durumu %s" % ("DEĞİŞTİ" if Game.rng.state != rng_state else "değişmedi")))
	var s_same := JSON.stringify(Game.s).hash() == s_hash
	res.append(_res("motor.saf_s", s_same, "motor: Game.s %s" % ("DEĞİŞTİ" if not s_same else "değişmedi")))
	res.append(_res("motor.reyting", bad_rt == 0, "motor: %d maçta rt sorunlu (her ilk 11 oyuncusu var, 1..10, 0.1 adım)" % bad_rt))
	# determinizm + çağrı sırasından bağımsızlık: ilk K maç ters sırayla, aynı seed
	var k := mini(60, matches.size())
	var same := 0
	for j in range(k - 1, -1, -1):
		var r2 = qe.call("simulate", Game, matches[j], false, seed_base + j)
		if r2 is Dictionary and JSON.stringify(r2, "", true) == outs[j]:
			same += 1
	res.append(_res("motor.determinizm", same == k, "motor: aynı seed, ters çağrı sırası: %d/%d maç birebir aynı" % [same, k]))
	# farklı seed farklı sonuç (sabit skor üretmiyor)
	var seen := {}
	for j in 20:
		var r3 = qe.call("simulate", Game, matches[0], false, seed_base + 100000 + j * 7919)
		if r3 is Dictionary:
			seen["%d-%d" % [int(r3.gh), int(r3.ga)]] = true
	res.append(_res("motor.seed_cesitlilik", seen.size() >= 3, "motor: 20 farklı seed'de %d farklı skor" % seen.size()))
	res.append_array(eval_consistency("motor", acc))
	ms.sort()
	return {"results": res, "acc": acc, "ms_median": ms[ms.size() / 2], "ms_max": ms[ms.size() - 1],
		"ms_p99": ms[mini(ms.size() - 1, int(ms.size() * 0.99))]}
