extends "res://tests/check/check_base.gd"
## Maç temposu (v0.24 4A): izlenen maçın gerçek (duvar saati) süresi.
## İzleyicinin kullandığı tempo mantığını (match_view.gd içindeki Pacer) ekransız sürer:
## LiveEngine'i izleyicinin kare döngüsüyle aynı kurallarla adımlar (canlı oynatımda hız x kare
## süresi, atlamada kare başına sınırlı adım), gol tekrarlarının ve Analist Gözü'nün süresini ekler.
## Hedefler (giriş dahil): Normal ≤14 dk (~12), Özet ≤6 dk (~5), Anlar ≤4 dk (~3);
## her modda 2. yarıya ulaşılır ve 2. yarıdan da görüntü izlenir; Anlar devre başına ≤4 an;
## Özet'te goller her zaman 1x görünür; video modu 5 an.

const LiveEngine = preload("res://sim/live_engine.gd")
const MatchView = preload("res://three/match_view.gd")

const FPS: float = 30.0                 # telefon kare hızı modeli
const PHONE_STEP_MS: float = 1.5        # telefonda bir motor adımının maliyeti (ms, modeli)
const INTRO_WALL: float = 5.3           # giriş kamerası (_tick_intro)
const REPLAY_WALL: float = 6.7 / 0.5    # gol tekrarı: 6,7 sn oyun zamanı, 0,5 hızla
const EYE_WALL: float = 12.0            # Analist Gözü başına ek süre payı (seç + bekle)
const LIMIT := {"full": 14.0, "hl": 6.0, "moments": 4.0}
const AIM := {"full": 12.0, "hl": 5.0, "moments": 3.0}
const N_MATCH: int = 5

func watchdog_sec() -> float:
	return 800.0

func run_check() -> void:
	Game.new_game("T", "tr")
	Game.take_job(str(Game.job_offers_start()[0]))
	var pool: Array = _pool(N_MATCH)
	check(pool.size() == N_MATCH, "maç havuzu eksik: %d" % pool.size())
	var sums := {"full": 0.0, "hl": 0.0, "moments": 0.0}
	var worst := {"full": 0.0, "hl": 0.0, "moments": 0.0}
	var shots_all := 0
	var shots_seen := 0
	for i: int in pool.size():
		var m: Dictionary = pool[i]
		for kind: String in ["full", "hl", "moments", "video"]:
			var r: Dictionary = _watch(m, kind, 7000 + i * 13)
			var tag := "maç %d %s" % [i, kind]
			log_info("%s: %.2f dk (canlı %.0f sn, atlama %.0f sn, 1x %.0f sn, tekrar %d, göz payı %.0f sn) anlar %s, şut %d/%d, gol %d/%d" % [
				tag, r.wall / 60.0, r.live_wall, r.seek_wall, r.wall_1x, r.goals, r.eye, str(r.per_half), r.shots_seen, r.shots, r.goals_seen, r.goals])
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

func _pool(n: int) -> Array:
	var out: Array = []
	var lgs: Array = ["SL", "EN1", "ES1", "IT1", "DE1"]
	for lg: String in lgs:
		if out.size() >= n or not Game.s.fixtures.has(lg):
			continue
		var fm: Dictionary = Game.s.fixtures[lg][0][0]
		Game.ensure_squad(fm.h)
		Game.ensure_squad(fm.a)
		out.append({"h": fm.h, "a": fm.a, "xi_h": Game.best_xi(fm.h, true), "xi_a": Game.best_xi(fm.a, true)})
	return out

## İzleyicinin _process -> _tick_live / _tick_seek / _moment_track / devre arası akışının ekransız eşi
func _watch(m: Dictionary, kind: String, sd: int) -> Dictionary:
	var e = LiveEngine.new()
	e.setup(Game, m.duplicate(true), false, sd)
	var pc = MatchView.Pacer.new()
	pc.kind = kind
	pc.video_max = 5 if kind == "video" else 0
	if kind == "video":
		pc.focus = [m.xi_h[9]]
	else:
		pc.focus = (m.xi_h as Array).slice(5, 11) if kind == "moments" else (m.xi_h as Array).slice(6, 9)
	var fr: float = 1.0 / FPS
	var seek_steps: int = mini(MatchView.Pacer.SEEK_MAX, int(MatchView.Pacer.SEEK_MS / PHONE_STEP_MS))
	var r := {"wall": INTRO_WALL, "live_wall": 0.0, "seek_wall": 0.0, "wall_1x": 0.0, "goals": 0, "goals_seen": 0,
		"shots": 0, "shots_seen": 0, "per_half": [0, 0], "second_half": false, "watched_2h": false,
		"finished": false, "seen": 0, "ended_early": false, "eye": 0.0}
	var seeking: bool = pc.starts_seeking()
	var acc := 0.0
	var ev := 0
	var goal_t := -1.0
	var guard := 0
	while not e.finished and guard < 400000:
		guard += 1
		if seeking:
			r.wall += fr
			r.seek_wall += fr
			pc.wall += fr
			var n := 0
			var half_now := false
			while n < seek_steps and not e.finished:
				n += 1
				e.step(LiveEngine.DT)
				var found: bool = pc.seek_found(e)
				var res: Dictionary = _consume(e, ev, pc, r, found)
				ev = res.ev
				if res.half:
					half_now = true
					break
				if found:
					seeking = false
					pc.open(e)
					r.per_half[1 if pc.second_half else 0] += 1
					break
			if half_now:
				seeking = pc.starts_seeking()
			continue
		var rate: float = pc.rate(e)
		r.wall += fr
		r.live_wall += fr
		pc.wall += fr
		if rate <= 1.001:
			r.wall_1x += fr
		if pc.second_half:
			r.watched_2h = true
		acc += fr * rate
		var g := 0
		var half_live := false
		while acc >= LiveEngine.DT and not e.finished and g < MatchView.Pacer.LIVE_GUARD:
			g += 1
			acc -= LiveEngine.DT
			e.step(LiveEngine.DT)
			var res: Dictionary = _consume(e, ev, pc, r, true)
			ev = res.ev
			if res.goal:
				goal_t = e.t
			if goal_t > 0.0 and e.t > goal_t + 3.0:
				goal_t = -1.0
				r.wall += REPLAY_WALL
				r.live_wall += REPLAY_WALL
				pc.wall += REPLAY_WALL
				break
			if res.half:
				half_live = true
				break
		if half_live:
			acc = 0.0
			seeking = pc.starts_seeking()
			continue
		var tr: String = pc.track(e, goal_t > 0.0)
		if tr == "seek":
			seeking = true
		elif tr == "finish":
			r.ended_early = true
			break
	r.finished = e.finished or r.ended_early
	r.seen = pc.seen
	if kind == "full":
		r.eye = EYE_WALL * 4.0
	elif kind == "moments":
		r.eye = EYE_WALL * 6.0
	r.wall += r.eye
	return r

## Yeni motor olaylarını işler (izleyicinin _consume/_on_event eşi)
func _consume(e, ev: int, pc, r: Dictionary, visible: bool) -> Dictionary:
	var out := {"ev": ev, "goal": false, "half": false}
	while out.ev < e.events.size():
		var x: Dictionary = e.events[out.ev]
		out.ev += 1
		match str(x.ty):
			"shot":
				r.shots += 1
				if visible:
					r.shots_seen += 1
			"goal":
				r.goals += 1
				if visible:
					r.goals_seen += 1
					out.goal = true
			"half":
				r.second_half = true
				pc.on_half(e)
				out.half = pc.kind != "video"
	return out
