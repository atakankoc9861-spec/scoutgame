extends "res://tests/check/check_base.gd"
## Maç temposu (v0.24 4A): izlenen maçın gerçek (duvar saati) süresi.
## İzleyicinin kullandığı tempo mantığını (match_view.gd içindeki Pacer) ekransız sürer:
## LiveEngine'i izleyicinin kare döngüsüyle aynı kurallarla adımlar (tests/check/watch_sim.gd: canlı
## oynatımda hız x kare süresi, atlamada kare başına sınırlı adım, gol tekrarları). v0.24 5A: Analist
## Gözü sabit pay değil, gerçek akışla (EyeLogic.Director: ağır çekim, Özet/Anlar'da soru duruşu) ölçülür.
## Hedefler (giriş dahil): Normal ≤14 dk (~12), Özet ≤6 dk (~5), Anlar ≤4 dk (~3);
## her modda 2. yarıya ulaşılır ve 2. yarıdan da görüntü izlenir; Anlar devre başına ≤4 an;
## Özet'te goller her zaman 1x görünür; video modu 5 an.

const LiveEngine = preload("res://sim/live_engine.gd")
const MatchView = preload("res://three/match_view.gd")

const WatchSim = preload("res://tests/check/watch_sim.gd")
const LIMIT := {"full": 14.0, "hl": 6.0, "moments": 4.0}
const AIM := {"full": 12.0, "hl": 5.0, "moments": 3.0}
const N_MATCH: int = 5

func watchdog_sec() -> float:
	return 800.0

func run_check() -> void:
	Game.new_game("T", "tr")
	Game.take_job(str(Game.job_offers_start()[0]))
	var pool: Array = WatchSim.pool(Game, N_MATCH)
	check(pool.size() == N_MATCH, "maç havuzu eksik: %d" % pool.size())
	var sums := {"full": 0.0, "hl": 0.0, "moments": 0.0}
	var worst := {"full": 0.0, "hl": 0.0, "moments": 0.0}
	var shots_all := 0
	var shots_seen := 0
	for i: int in pool.size():
		var m: Dictionary = pool[i]
		for kind: String in ["full", "hl", "moments", "video"]:
			var r: Dictionary = WatchSim.watch(Game, m, kind, 7000 + i * 13, true)
			var tag := "maç %d %s" % [i, kind]
			log_info("%s: %.2f dk (canlı %.0f sn, atlama %.0f sn, 1x %.0f sn, tekrar %d, göz %.0f sn, %d soru) anlar %s, şut %d/%d, gol %d/%d" % [
				tag, r.wall / 60.0, r.live_wall, r.seek_wall, r.wall_1x, r.goals, r.eye, (r.eye_clock as Array).size(), str(r.per_half), r.shots_seen, r.shots, r.goals_seen, r.goals])
			check(r.finished, tag + ": maç sona ulaşmadı")
			check_num(r.wall, tag + " süre", 1.0, 3600.0)
			if kind == "video":
				# video: eskisi gibi 5 an, sonra biter (2. yarı şartı yok)
				check(int(r.seen) == 5 or not r.ended_early, "%s: video 5 an yerine %d" % [tag, int(r.seen)])
				continue
			check(r.second_half, tag + ": 2. yarıya ulaşılmadı")
			check(r.watched_2h, tag + ": 2. yarıdan hiç görüntü izlenmedi")
			var mins: float = r.wall / 60.0
			check(mins <= float(LIMIT[kind]), "%s: %.2f dk > %.1f dk sınırı" % [tag, mins, float(LIMIT[kind])])
			sums[kind] = float(sums[kind]) + mins
			worst[kind] = maxf(float(worst[kind]), mins)
			if kind == "moments":
				for h: int in 2:
					check(int(r.per_half[h]) <= 4, "%s: %d. yarıda %d an (>4)" % [tag, h + 1, int(r.per_half[h])])
				check(int(r.per_half[1]) >= 1, tag + ": 2. yarıda an yok")
			if kind == "hl":
				check(int(r.goals_seen) == int(r.goals), "%s: Özet'te gol kaçtı (%d/%d)" % [tag, int(r.goals_seen), int(r.goals)])
				shots_all += int(r.shots)
				shots_seen += int(r.shots_seen)
	for kind: String in ["full", "hl", "moments"]:
		var avg: float = float(sums[kind]) / float(N_MATCH)
		log_info("ORT %s: %.2f dk (hedef ~%.0f, sınır %.0f), en kötü %.2f dk" % [kind, avg, float(AIM[kind]), float(LIMIT[kind]), float(worst[kind])])
		check(avg <= float(AIM[kind]) + 1.0, "%s ortalama %.2f dk hedefin (~%.0f) çok üstünde" % [kind, avg, float(AIM[kind])])
		check(avg >= float(AIM[kind]) * 0.5, "%s ortalama %.2f dk: fazla kısa, maç izlenmiyor" % [kind, avg])
	var sp: float = 100.0 * float(shots_seen) / maxf(1.0, float(shots_all))
	log_info("Özet: şutların %%%.0f'i 1x görüldü (%d/%d)" % [sp, shots_seen, shots_all])
	check(sp >= 85.0, "Özet şutların yalnızca %%%.0f'ini 1x gösteriyor" % sp)
	_check_static()

## Saf kurallar: elle kurulmuş durumlar
func _check_static() -> void:
	var pc = MatchView.Pacer.new()
	pc.kind = "full"
	check(pc.boost(0.0, 0.5) >= 1.0, "boost < 1")
	check(pc.boost(500.0, 0.1) > 2.0, "geride kalan izleme hızlanmıyor")
	check(is_equal_approx(pc.boost(0.0, 0.9), 1.0), "zamanında izlemede boost 1 değil")
	pc.kind = "moments"
	check(pc.slot_open(0, 0.0) and not pc.slot_open(1, 0.05) and pc.slot_open(3, 0.8), "an dilimleri yanlış")
	check(not pc.slot_open(4, 0.99), "devre başına 4 an tavanı yok")
