extends "res://tests/check/check_base.gd"
## Maç motorları (v0.23 Dalga 2-F):
## - Hızlı motor (sim/quick_engine.gd) arayüzü: dönüş alanları, gol olayları, reyting ölçeği, kartlar
## - Saflık: m, Game.rng ve oyuncu kayıtları değişmiyor
## - Determinizm: aynı seed -> aynı sonuç, araya başka maç girse de (çağrı sırasından bağımsız)
## - Dağılım (küçük örneklem, geniş sınırlar; asıl kabul ölçümü tests/baseline/engine_stats)
## - Özellikler görünür: güçlü kadro daha çok kazanır
## - Hız: maç başına medyan / en kötü süre
## - Canlı motor: aynı seed aynı skor; seed 0 rastgele davranışı korunur; ortak formüller tutarlı

const QuickEngine = preload("res://sim/quick_engine.gd")
const LiveEngine = preload("res://sim/live_engine.gd")
const N_DIST: int = 600

func watchdog_sec() -> float:
	return 600.0

func run_check() -> void:
	Game.new_game("T", "tr")
	Game.take_job(str(Game.job_offers_start()[0]))
	var pool: Array = _pool(N_DIST)
	check(pool.size() == N_DIST, "maç havuzu eksik: %d" % pool.size())
	_check_interface(pool[0])
	_check_purity(pool[1])
	_check_determinism(pool)
	_check_distribution(pool)
	_check_live()

func _pool(n: int) -> Array:
	var out: Array = []
	var lgs: Array = ["SL", "EN1", "ES1", "IT1", "DE1", "FR1"]
	var r: int = 0
	while out.size() < n and r < 40:
		for lg: String in lgs:
			if not Game.s.fixtures.has(lg) or r >= Game.s.fixtures[lg].size():
				continue
			for fm: Dictionary in Game.s.fixtures[lg][r]:
				if out.size() >= n:
					break
				Game.ensure_squad(fm.h)
				Game.ensure_squad(fm.a)
				out.append({"h": fm.h, "a": fm.a, "day": "sat", "gh": -1, "ga": -1, "ev": [],
					"xi_h": Game.best_xi(fm.h, true), "xi_a": Game.best_xi(fm.a, true)})
		r += 1
	return out

func _check_interface(m: Dictionary) -> void:
	var out: Dictionary = QuickEngine.simulate(Game, m, false, 12345)
	for k: String in ["gh", "ga", "ev", "rt", "cards", "team"]:
		check(out.has(k), "dönüşte %s yok" % k)
	if failed():
		return
	check(typeof(out.gh) == TYPE_INT and typeof(out.ga) == TYPE_INT, "gh/ga int değil")
	check(int(out.gh) >= 0 and int(out.ga) >= 0, "eksi skor")
	var xi: Array = m.xi_h + m.xi_a
	check(out.rt.size() == xi.size(), "reyting sayısı %d, ilk 11 toplamı %d" % [out.rt.size(), xi.size()])
	for pid: String in xi:
		if check(out.rt.has(pid), "reyting yok: " + pid):
			var r: float = float(out.rt[pid])
			check_num(r, "reyting " + pid, 3.5, 9.8)
			check(is_equal_approx(r, snappedf(r, 0.1)), "reyting 0.1 adımlı değil: %s" % str(r))
	var nh: int = 0
	var na: int = 0
	var last_min: int = 0
	for e: Dictionary in out.ev:
		check(e.get("t", "") == "g", "olay tipi 'g' değil")
		check(e.side == "h" or e.side == "a", "olay tarafı geçersiz")
		check(int(e["min"]) >= 1 and int(e["min"]) <= 90, "gol dakikası aralık dışı: %s" % str(e["min"]))
		check(int(e["min"]) >= last_min, "gol olayları dakikaya göre sıralı değil")
		last_min = int(e["min"])
		check(pid_in(e.pid, m.xi_h if e.side == "h" else m.xi_a), "golcü kendi ilk 11'inde değil: " + str(e.pid))
		if str(e["as"]) != "":
			check(pid_in(e["as"], m.xi_h if e.side == "h" else m.xi_a), "asist kendi ilk 11'inde değil")
			check(e["as"] != e.pid, "golcü kendine asist")
		if e.side == "h":
			nh += 1
		else:
			na += 1
	check(nh == int(out.gh) and na == int(out.ga), "gol olayı sayısı skorla uyuşmuyor")
	for pid: String in out.cards:
		check(pid in xi, "kart sahibi ilk 11'de değil")
		check(out.cards[pid].has("yc") and out.cards[pid].has("rc"), "kart alanları eksik")
	for sd: String in ["h", "a"]:
		for k: String in ["sh", "sot", "fouls", "corners", "poss"]:
			check(out.team[sd].has(k), "team.%s.%s yok" % [sd, k])
	check(absf(float(out.team.h.poss) + float(out.team.a.poss) - 100.0) < 0.3, "topla oynama toplamı 100 değil")

func pid_in(pid: Variant, arr: Array) -> bool:
	return str(pid) in arr

func _check_purity(m: Dictionary) -> void:
	var m_before: String = JSON.stringify(m)
	var rng_state: int = Game.rng.state
	var pl_before: String = ""
	for pid: String in m.xi_h + m.xi_a:
		pl_before += JSON.stringify(Game.player(pid))
	var tbl_before: String = JSON.stringify(Game.s.table)
	QuickEngine.simulate(Game, m, false, 777)
	QuickEngine.simulate(Game, m, true, 778)
	check(JSON.stringify(m) == m_before, "simulate m'yi değiştirdi")
	check(Game.rng.state == rng_state, "simulate Game.rng'yi ilerletti")
	var pl_after: String = ""
	for pid: String in m.xi_h + m.xi_a:
		pl_after += JSON.stringify(Game.player(pid))
	check(pl_after == pl_before, "simulate oyuncu kayıtlarını değiştirdi")
	check(JSON.stringify(Game.s.table) == tbl_before, "simulate puan tablosunu değiştirdi")

func _check_determinism(pool: Array) -> void:
	var a: String = JSON.stringify(QuickEngine.simulate(Game, pool[2], false, 4242))
	QuickEngine.simulate(Game, pool[3], false, 1)
	QuickEngine.simulate(Game, pool[4], false, 99)
	var b: String = JSON.stringify(QuickEngine.simulate(Game, pool[2], false, 4242))
	check(a == b, "aynı seed farklı sonuç (araya başka maç girince)")
	var c: String = JSON.stringify(QuickEngine.simulate(Game, pool[2], false, 4243))
	check(a != c, "farklı seed birebir aynı sonuç")
	# seed 0 da deterministik (sabit tohuma düşer)
	check(JSON.stringify(QuickEngine.simulate(Game, pool[2], false, 0)) == JSON.stringify(QuickEngine.simulate(Game, pool[2], false, 0)), "seed 0 deterministik değil")
	# hash: aynı havuz + seed'ler -> aynı toplam (Dalga 3 hibrit testleri için referans)
	var h: int = 0
	for i: int in 50:
		var o: Dictionary = QuickEngine.simulate(Game, pool[i], false, 1000 + i)
		h = hash(str(h) + str(o.gh) + "-" + str(o.ga) + JSON.stringify(o.rt))
	var h2: int = 0
	for i: int in 50:
		var o2: Dictionary = QuickEngine.simulate(Game, pool[i], false, 1000 + i)
		h2 = hash(str(h2) + str(o2.gh) + "-" + str(o2.ga) + JSON.stringify(o2.rt))
	check(h == h2, "50 maçlık determinizm hash'i tutmuyor")
	log_info("determinizm hash (50 maç): %d" % h)

func _check_distribution(pool: Array) -> void:
	var n: int = pool.size()
	var goals: int = 0
	var gh: int = 0
	var ga: int = 0
	var hw: int = 0
	var dr: int = 0
	var big: int = 0
	var strong_n: int = 0
	var strong_w: int = 0
	var rt_sum: float = 0.0
	var rt_n: int = 0
	var ms: Array = []
	for i: int in n:
		var m: Dictionary = pool[i]
		var t0: int = Time.get_ticks_usec()
		var o: Dictionary = QuickEngine.simulate(Game, m, false, 50000 + i)
		ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		goals += int(o.gh) + int(o.ga)
		gh += int(o.gh)
		ga += int(o.ga)
		if o.gh > o.ga:
			hw += 1
		elif o.gh == o.ga:
			dr += 1
		if absi(int(o.gh) - int(o.ga)) >= 4:
			big += 1
		var sh: float = Game.team_str(m.xi_h, false)
		var sa: float = Game.team_str(m.xi_a, false)
		if absf(sh - sa) >= 3.0:
			strong_n += 1
			if (sh > sa and o.gh > o.ga) or (sa > sh and o.ga > o.gh):
				strong_w += 1
		for pid: String in o.rt:
			rt_sum += float(o.rt[pid])
			rt_n += 1
	var nf: float = float(n)
	var gpm: float = goals / nf
	var hwp: float = 100.0 * hw / nf
	var drp: float = 100.0 * dr / nf
	var bigp: float = 100.0 * big / nf
	var ratio: float = float(gh) / maxf(1.0, float(ga))
	var swp: float = 100.0 * strong_w / maxf(1.0, float(strong_n))
	ms.sort()
	var med: float = ms[ms.size() / 2]
	var worst: float = ms[ms.size() - 1]
	log_info("hızlı motor %d maç: gol/maç %.2f, ev %.1f%%, beraberlik %.1f%%, 4+ fark %.1f%%, ev/dep gol %.2f, güçlü kazanır %.1f%% (%d), reyting ort %.2f" % [n, gpm, hwp, drp, bigp, ratio, swp, strong_n, rt_sum / maxf(1.0, float(rt_n))])
	log_info("hız: medyan %.2f ms, en kötü %.2f ms" % [med, worst])
	# küçük örneklem: hedef aralıklar (2.5-3.1, 41-48, 22-29, <=6, 1.15-1.35) + örneklem payı
	check(gpm >= 2.3 and gpm <= 3.3, "gol/maç aralık dışı: %.2f" % gpm)
	check(hwp >= 36.0 and hwp <= 53.0, "ev sahibi galibiyet aralık dışı: %.1f" % hwp)
	check(drp >= 18.0 and drp <= 33.0, "beraberlik aralık dışı: %.1f" % drp)
	check(bigp <= 8.0, "4+ farklı maç çok: %.1f" % bigp)
	check(ratio >= 1.05 and ratio <= 1.5, "ev/dep gol oranı aralık dışı: %.2f" % ratio)
	check(strong_n < 20 or swp > 50.0, "belirgin güçlü kadro yeterince kazanmıyor: %.1f%%" % swp)
	# hız: hedef medyan <=3 ms, en kötü <=10 ms (paylaşılan test makinesinde pay bırakılır)
	check(med <= 4.5, "hızlı motor medyan süre yüksek: %.2f ms" % med)
	check(ms[int(ms.size() * 0.99)] <= 15.0, "hızlı motor p99 süre yüksek: %.2f ms" % ms[int(ms.size() * 0.99)])

func _check_live() -> void:
	# ortak formüller
	check(is_equal_approx(LiveEngine.duel_p(12.0, 10.0, 0.5, 0.03), clampf(0.5 + 0.03 * LiveEngine.DUEL_K * 2.0, 0.04, 0.96)), "duel_p formülü")
	check(LiveEngine.lead_shift(3) < LiveEngine.lead_shift(1), "lead_shift: farklı önde olan yavaşlamıyor")
	check(LiveEngine.lead_shift(-1) > 0.0, "lead_shift: geride olan risk almıyor")
	var p: Dictionary = _pool(1)[0]
	var m1: Dictionary = {"h": p.h, "a": p.a, "xi_h": p.xi_h.duplicate(), "xi_a": p.xi_a.duplicate()}
	var m2: Dictionary = {"h": p.h, "a": p.a, "xi_h": p.xi_h.duplicate(), "xi_a": p.xi_a.duplicate()}
	var e1 = LiveEngine.new()
	e1.setup(Game, m1, false, 31337)
	e1.run_to_end()
	var e2 = LiveEngine.new()
	e2.setup(Game, m2, false, 31337)
	e2.run_to_end()
	check(e1.finished and e2.finished, "canlı motor bitmedi")
	check(e1.score == e2.score and e1.events.size() == e2.events.size(), "canlı motor aynı seed farklı sonuç")
	check(JSON.stringify(e1.ratings(true)) == JSON.stringify(e2.ratings(true)), "canlı motor reytingleri farklı")
	var e3 = LiveEngine.new()
	e3.setup(Game, {"h": p.h, "a": p.a}, false, 0)
	var e4 = LiveEngine.new()
	e4.setup(Game, {"h": p.h, "a": p.a}, false, 0)
	check(e3.rng.seed != e4.rng.seed, "seed 0 rastgele davranışı bozuldu")
	# izleyici gibi adım adım: olaylar ve animasyon kuyruğu akıyor
	var steps: int = 0
	var anim_n: int = 0
	while not e3.finished and steps < 3000:
		e3.step()
		anim_n += e3.anims.size()
		e3.anims.clear()
		steps += 1
	check(e3.events.size() > 20 and anim_n > 50, "canlı adım akışı: olay %d, animasyon %d" % [e3.events.size(), anim_n])
	# v0.24: ölü topta (aut/korner/gol sonrası) top havada asılı kalmamalı
	var e5 = LiveEngine.new()
	e5.setup(Game, {"h": p.h, "a": p.a, "xi_h": p.xi_h.duplicate(), "xi_a": p.xi_a.duplicate()}, false, 4242)
	var dead_n: int = 0
	var dead_air: int = 0
	var st5: int = 0
	while not e5.finished and st5 < 6000:
		e5.step()
		e5.anims.clear()
		if e5.phase == "dead":
			dead_n += 1
			if e5.ball_h > 0.05:
				dead_air += 1
		st5 += 1
	check(dead_n > 10, "ölü top anı bulunamadı (%d)" % dead_n)
	check(dead_air == 0, "ölü topta top havada: %d/%d adım" % [dead_air, dead_n])
	log_info("canlı: %d-%d (%d olay), adım akışı %d olay / %d animasyon" % [e1.score[0], e1.score[1], e1.events.size(), e3.events.size(), anim_n])
