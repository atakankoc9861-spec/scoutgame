extends RefCounted
## İzleyicinin (three/match_view.gd) _process -> _tick_live / _tick_seek / _moment_track / devre arası
## akışının ekransız eşi. tempo_check (süre) ve eye_check (Analist Gözü) ortak kullanır.
## Pacer ve EyeLogic.Director izleyicideki sınıfların kendisidir; burada yalnız kare döngüsü taklit edilir.
## Kullanıcı modeli (göz): soruya 1,5-6 sn içinde cevap verir, %15 cevapsız bırakır.

const LiveEngine = preload("res://sim/live_engine.gd")
const MatchView = preload("res://three/match_view.gd")
const EyeLogic = preload("res://sim/eye_logic.gd")

const FPS: float = 30.0                 # telefon kare hızı modeli
const PHONE_STEP_MS: float = 1.5        # telefonda bir motor adımının maliyeti (ms, modeli)
const INTRO_WALL: float = 5.3           # giriş kamerası (_tick_intro)
const REPLAY_WALL: float = 6.7 / 0.5    # gol tekrarı: 6,7 sn oyun zamanı, 0,5 hızla

static func pool(game, n: int) -> Array:
	var out: Array = []
	for lg: String in ["SL", "EN1", "ES1", "IT1", "DE1"]:
		if out.size() >= n or not game.s.fixtures.has(lg):
			continue
		var fm: Dictionary = game.s.fixtures[lg][0][0]
		game.ensure_squad(fm.h)
		game.ensure_squad(fm.a)
		out.append({"h": fm.h, "a": fm.a, "xi_h": game.best_xi(fm.h, true), "xi_a": game.best_xi(fm.a, true)})
	return out

static func watch(game, m: Dictionary, kind: String, sd: int, eye_on := true) -> Dictionary:
	var e = LiveEngine.new()
	e.setup(game, m.duplicate(true), false, sd)
	var urng := RandomNumberGenerator.new()
	urng.seed = sd * 31 + 7
	var pc = MatchView.Pacer.new()
	pc.kind = kind
	pc.video_max = 5 if kind == "video" else 0
	if kind == "video":
		pc.focus = [m.xi_h[9]]
	else:
		pc.focus = (m.xi_h as Array).slice(5, 11) if kind == "moments" else (m.xi_h as Array).slice(6, 9)
	var dir = EyeLogic.Director.new()
	dir.kind = kind
	dir.focus = pc.focus
	var fr: float = 1.0 / FPS
	var seek_steps: int = mini(MatchView.Pacer.SEEK_MAX, int(MatchView.Pacer.SEEK_MS / PHONE_STEP_MS))
	var r := {"wall": INTRO_WALL, "live_wall": 0.0, "seek_wall": 0.0, "wall_1x": 0.0, "goals": 0, "goals_seen": 0,
		"shots": 0, "shots_seen": 0, "per_half": [0, 0], "second_half": false, "watched_2h": false,
		"finished": false, "seen": 0, "ended_early": false, "eye": 0.0, "eye_wall": 0.0, "focus": pc.focus}
	var seeking: bool = pc.starts_seeking()
	var acc := 0.0
	var ev := 0
	var goal_t := -1.0
	var guard := 0
	var ans_t := 0.0
	var ans_i := -1
	while not e.finished and guard < 500000:
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
				if not found and eye_on and dir.seek_stop(e, pc):
					found = true
				var res: Dictionary = _consume(e, ev, pc, r, found)
				ev = res.ev
				if res.half:
					half_now = true
					dir.clear(e)
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
		if eye_on:
			rate = dir.rate(rate)
		r.wall += fr
		r.live_wall += fr
		pc.wall += fr
		if dir.state == "choose" or dir.state == "wait":
			r.eye_wall += fr
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
			if eye_on:
				dir.pre_step(e)
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
			dir.clear(e)
			seeking = pc.starts_seeking()
			continue
		if eye_on and not e.finished:
			var evn: String = dir.tick(fr, e, pc)
			if evn == "start":
				ans_t = urng.randf_range(1.5, 6.0)
				ans_i = -1 if urng.randf() < 0.15 else urng.randi_range(0, dir.opts.size() - 1)
			elif dir.state == "choose" and ans_i >= 0 and dir.t >= ans_t:
				dir.answer(ans_i)
		var tr: String = pc.track(e, goal_t > 0.0 or dir.state != "")
		if tr == "seek":
			seeking = true
		elif tr == "finish":
			r.ended_early = true
			break
	if dir.state != "verdict":
		dir.clear(e)
	r.finished = e.finished or r.ended_early
	r.seen = pc.seen
	r.eye = r.eye_wall
	r["eye_clock"] = dir.asked_at
	r["eye_min_rate"] = dir.min_rate
	r["fe"] = {"_eye_reads": dir.reads}
	return r

## Yeni motor olaylarını işler (izleyicinin _consume/_on_event eşi)
static func _consume(e, ev: int, pc, r: Dictionary, visible: bool) -> Dictionary:
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
