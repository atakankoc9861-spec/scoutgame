extends RefCounted
## Analist Gözü (v0.24 5A) — saf mantık, görüntüden bağımsız.
## 1) options(sit): topu alan odak oyuncunun seçenekleri futbol mantığıyla puanlanır
##    (motorun iç puanı değil): pas yolu açık/dar/kapalı, alıcı boş/gevşek/sıkı markajda,
##    ara pasında hedef çevresindeki kalabalık, şut açısı/mesafesi/önündeki adam, topla ilerleme alanı,
##    bölgeye göre ödül (ileri ve merkez değerli) ve top kaybının bedeli (kendi yarında pahalı).
## 2) judge / reason / attr_for: doğru mu, kısa gerekçe (TR/EN anahtarları), soru hangi özelliği ölçüyor.
## 3) Director: maç içi zamanlama (mod başına kota, iki yarıya yayılım, ≥8 dk ara, yalnız odak
##    oyuncunun karar anı), ağır çekim / bekleme hızları, karar tutma ve _eye_reads kaydı.
##    match_view.gd ve tests/check/watch_sim.gd aynı sınıfı sürer.
## sit: {d, pos, pid, mates: [{id, pos, role, name}], opps: [{pos, gk}]}

const L := 52.5
const W := 34.0
## Soru hangi özelliği ölçer (Data.ATTRS anahtarları)
const ATTR_KEYS := ["passing", "vision", "decisions", "composure", "finishing", "dribbling"]
## v0.24 göz v2 — "Önce izle, sonra yargıla": soru oyuncunun GERÇEK kararı üzerine.
## watch: odak oyuncu topu aldı, ağır çekim, hiçbir ipucu yok -> oyuncu kendi kararını verir
## judge: hamle anında oyun neredeyse durur (top yolda süzülür); "Kararı nasıldı? İyi / Makul / Kötü"
## verdict: pas yolları / boş adamlar / baskı ancak şimdi açılır + gerekçe; doğru okuma bilgiye işlenir.
## Mod -> [1. yarı, 2. yarı] soru kotası (Normal 3, Anlar 2, Özet 1, video 2)
const QUOTA := {"full": [2, 1], "moments": [1, 1], "hl": [1, 0], "video": [1, 1]}
const GAP := 600.0          # iki soru arası en az 10 oyun dakikası (maç saati, sn)
const SLOW := 0.35          # izleme ağır çekimi
const JUDGE_RATE := 0.06    # yargılarken top yolda yavaşça süzülür (oyun durmaz)
const VERDICT_RATE := 0.15  # açıklama okunurken
const CHOOSE_MAX := 10.0    # yargı süresi (gerçek sn)
const HOLD := 1.0           # oyuncunun kararını en çok bu kadar sim sn geciktir (izleyene zaman)
const WATCH_MAX := 8.0      # gerçek sn: oyuncu karar vermezse soru iptal (sayılmaz)
const VERDICT_T := 6.0
const GOOD_GAP := 0.02      # en iyiye bu kadar yakın karar "İyi" (ölçüm: ~%33 iyi, ~%28 makul, ~%38 kötü)
const BAD_GAP := 0.10      # en iyiden bu kadar uzak (ya da kapalı yola pas) "Kötü"
const GRADES := ["good", "ok", "bad"]
const TOL := 0.012          # en iyiye bu kadar yakın seçenek de doğru sayılır
const MAX_OPTS := 4
const TEXT_KEYS := ["eye_rs_ok", "eye_rs_no", "eye_rs_best", "eye_rb_free", "eye_rb_open", "eye_rb_through",
	"eye_rb_shot", "eye_rb_shot2", "eye_rb_carry", "eye_rw_blocked", "eye_rw_traffic", "eye_rw_marked",
	"eye_rw_safe", "eye_rw_long", "eye_rw_less", "eye_rw_shot_block", "eye_rw_shot_far", "eye_rw_crowd",
	"eye_rw_slow", "eye_pause", "eye_resume", "eye_noans", "eye_gain2",
	"eye_g_good", "eye_g_ok", "eye_g_bad", "eye_watch3", "eye_judge", "eye_did", "eye_rs_why", "eye_rs_alt",
	"eye_v_hit", "eye_v_miss", "eye_v_none", "eye_lbl_his", "eye_lbl_best", "eye_howto3"]

# ================================================================ değerlendirme

static func zone_reward(p: Vector2, d: float) -> float:
	## Topun bu noktada olmasının değeri: ileri ve merkez değerli, ceza sahası ayrıca
	var lx := p.x * d
	var prog := clampf((lx + L) / (2.0 * L), 0.0, 1.0)
	var v := 0.04 + 0.26 * prog * prog
	if lx > L - 16.5 and absf(p.y) < 20.0:
		v += 0.06
	return v * (1.0 - clampf(absf(p.y) / W, 0.0, 1.0) * 0.4)

static func loss_cost(p: Vector2, d: float) -> float:
	## Burada top kaybetmenin bedeli: kendi üçte birinde pahalı, rakip yarıda ucuz
	var lx := p.x * d
	if lx < -17.5:
		return 0.30
	if lx < 17.5:
		return 0.14
	return 0.06

static func shot_q(p: Vector2, d: float) -> float:
	## Açı + mesafe (önündeki adam ayrıca)
	var goal := Vector2(L * d, 0.0)
	var dist := p.distance_to(goal)
	var ang := absf(atan2(absf(p.y), maxf(0.5, L - p.x * d)))
	return clampf(0.75 * exp(-dist / 11.0) * (1.0 - clampf(ang / 1.4, 0.0, 0.85)), 0.003, 0.7)

static func _seg_dist(a: Vector2, b: Vector2, q: Vector2, t0: float, t1: float) -> float:
	var ab := b - a
	var l2 := maxf(0.01, ab.length_squared())
	var tt := clampf((q - a).dot(ab) / l2, t0, t1)
	return q.distance_to(a + ab * tt)

static func offside_line(sit: Dictionary) -> float:
	var d: float = sit.d
	var xs: Array = []
	for o: Dictionary in sit.opps:
		xs.append((o.pos as Vector2).x * d)
	xs.sort()
	var line: float = xs[xs.size() - 2] if xs.size() >= 2 else L
	return maxf(line, (sit.pos as Vector2).x * d)

static func options(sit: Dictionary) -> Array:
	var d: float = sit.d
	var pos: Vector2 = sit.pos
	var opps: Array = sit.opps
	var out: Array = []
	var press := 99.0
	for o: Dictionary in opps:
		press = minf(press, (o.pos as Vector2).distance_to(pos))
	var cost := loss_cost(pos, d)
	var off_line := offside_line(sit)
	# paslar
	for mt: Dictionary in sit.mates:
		var tp: Vector2 = mt.pos
		var dist := tp.distance_to(pos)
		if dist < 4.0 or dist > 45.0:
			continue
		if tp.x * d > off_line + 0.3 and tp.x * d > pos.x * d:
			continue
		var lane_d := 99.0
		var mark_d := 99.0
		var traffic := 0
		for o: Dictionary in opps:
			var op: Vector2 = o.pos
			if not o.get("gk", false):
				lane_d = minf(lane_d, _seg_dist(pos, tp, op, 0.12, 0.88))
			var md := op.distance_to(tp)
			mark_d = minf(mark_d, md)
			if md < 6.0:
				traffic += 1
		var lane := "open" if lane_d >= 3.5 else ("tight" if lane_d >= 1.8 else "blocked")
		var mark := "free" if mark_d >= 5.0 else ("loose" if mark_d >= 2.5 else "tight")
		var fwd := (tp.x - pos.x) * d
		var through := fwd > 12.0
		var lane_pen: float = {"open": 0.0, "tight": 0.18, "blocked": 0.5}[lane]
		var mark_pen: float = {"free": 0.0, "loose": 0.12, "tight": 0.3}[mark]
		var p: float = 0.96 - dist / 140.0 - lane_pen - mark_pen
		if through:
			p -= 0.08 * maxf(0.0, float(traffic) - 1.0)
		p = clampf(p, 0.05, 0.97)
		var rew := zone_reward(tp, d)
		out.append({"k": "pass", "to": str(mt.id), "name": str(mt.get("name", mt.id)), "role": str(mt.get("role", "")),
			"tp": tp, "dist": dist, "lane": lane, "mark": mark, "fwd": fwd, "through": through, "traffic": traffic,
			"p": p, "rew": rew, "score": p * rew - (1.0 - p) * cost})
	# şut
	var lx := pos.x * d
	if lx > 15.0 and absf(pos.y) < 26.0:
		var goal := Vector2(L * d, 0.0)
		var blockers := 0
		for o: Dictionary in opps:
			if o.get("gk", false):
				continue
			if _seg_dist(pos, goal, o.pos, 0.05, 1.0) < 1.5:
				blockers += 1
		var q := shot_q(pos, d) * pow(0.35, blockers) * (0.8 if press < 1.8 else 1.0)
		out.append({"k": "shot", "to": "", "name": "", "tp": goal, "blockers": blockers, "q": shot_q(pos, d),
			"p": q, "rew": q, "score": q, "lane": "open" if blockers == 0 else "blocked"})
	# topla ilerleme
	var ahead := 99.0
	for o: Dictionary in opps:
		var rel: Vector2 = (o.pos as Vector2) - pos
		if rel.x * d > -1.0 and rel.x * d < 9.0 and absf(rel.y) < 4.5:
			ahead = minf(ahead, rel.length())
	# topla ilerleme: 6 m, alan varsa %80 (pas kadar hızlı ilerletmez, rakip geri döner)
	var carry := Vector2(clampf(pos.x + d * 6.0, -L + 2.0, L - 2.0), pos.y)
	var pd := 0.8 if ahead >= 6.0 else (0.5 if ahead >= 3.0 else 0.3)
	var rw := zone_reward(carry, d)
	if carry.x * d > 36.0:
		# ceza sahasına taşımak yine şutla biter (kaleci çıkar): değeri oradan atılacak şut
		rw = shot_q(carry, d) * 0.75
	out.append({"k": "dribble", "to": "", "name": "", "tp": carry, "space": ahead, "p": pd, "rew": rw,
		"score": pd * rw - (1.0 - pd) * cost, "lane": "open" if ahead >= 6.0 else ("tight" if ahead >= 3.0 else "blocked")})
	for o: Dictionary in out:
		o["press"] = press
	return out

static func best_index(opts: Array) -> int:
	var bi := -1
	for i: int in opts.size():
		if bi < 0 or float(opts[i].score) > float(opts[bi].score):
			bi = i
	return bi

static func judge(opts: Array, i: int) -> bool:
	if i < 0 or i >= opts.size():
		return false
	return float(opts[i].score) >= float(opts[best_index(opts)].score) - TOL

static func pick_set(all: Array) -> Array:
	## Ekrandaki seçenekler: en iyi + şut (varsa) + en güvenli pas + en iddialı pas, en çok 4
	if all.is_empty():
		return []
	var srt := all.duplicate()
	srt.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	var out: Array = [srt[0]]
	var safe: Variant = null
	var bold: Variant = null
	var shot: Variant = null
	for o: Dictionary in srt:
		if o.k == "shot":
			shot = o
		elif o.k == "pass":
			if safe == null or float(o.p) > float(safe.p):
				safe = o
			if bold == null or float(o.fwd) > float(bold.fwd):
				bold = o
	for c: Variant in [shot, bold, safe]:
		if c != null and not out.has(c) and out.size() < MAX_OPTS:
			out.append(c)
	for o: Dictionary in srt:
		if out.size() >= MAX_OPTS:
			break
		if not out.has(o):
			out.append(o)
	return out

static func attr_for(opts: Array, bi: int) -> String:
	## Bu karar oyuncunun hangi özelliğini sınar
	if bi < 0 or bi >= opts.size():
		return "decisions"
	var b: Dictionary = opts[bi]
	var pressed := float(b.get("press", 99.0)) < 2.5
	match str(b.k):
		"shot":
			return "composure" if pressed or int(b.get("blockers", 0)) > 0 else "finishing"
		"dribble":
			return "dribbling" if float(b.get("space", 99.0)) < 6.0 else "decisions"
	if pressed:
		return "composure"
	if float(b.fwd) >= 12.0 or float(b.dist) >= 30.0:
		return "vision"
	for o: Dictionary in opts:
		if o != b and float(o.get("rew", 0.0)) > float(b.rew) + 0.03:
			return "decisions"     # daha cazip ama riskli bir seçeneğe kanmamak
	return "passing"

static func _why_good(o: Dictionary) -> Array:
	match str(o.k):
		"shot":
			return ["eye_rb_shot", []] if int(o.get("blockers", 0)) == 0 else ["eye_rb_shot2", []]
		"dribble":
			return ["eye_rb_carry", []]
	if bool(o.through) and o.lane == "open":
		return ["eye_rb_through", [o.name]]
	if o.mark == "free":
		return ["eye_rb_free", [o.name]]
	return ["eye_rb_open", [o.name]]

static func _why_bad(o: Dictionary, b: Dictionary) -> Array:
	match str(o.k):
		"shot":
			return ["eye_rw_shot_block", []] if int(o.get("blockers", 0)) > 0 else ["eye_rw_shot_far", []]
		"dribble":
			return ["eye_rw_crowd", []] if float(o.get("space", 99.0)) < 6.0 else ["eye_rw_slow", []]
	if bool(o.through) and int(o.traffic) >= 2:
		return ["eye_rw_traffic", []]
	if o.lane == "blocked":
		return ["eye_rw_blocked", [o.name]]
	if o.mark == "tight":
		return ["eye_rw_marked", [o.name]]
	if float(o.dist) > 32.0 and o.lane != "open":
		return ["eye_rw_long", []]
	if float(o.fwd) < 0.0 and float(o.rew) + 0.03 < float(b.get("rew", 0.0)):
		return ["eye_rw_safe", [o.name]]
	return ["eye_rw_less", [o.name]]

static func reason(opts: Array, pick: int, unanswered: bool) -> Array:
	## Kısa gerekçe: [[anahtar, argümanlar], ...]  ör. "Doğrusu: rb boştu, yol açıktı; ara pası kalabalığa gidiyordu"
	var bi := best_index(opts)
	if bi < 0:
		return []
	var b: Dictionary = opts[bi]
	if unanswered or pick < 0:
		return [["eye_rs_best", []], _why_good(b)]
	if judge(opts, pick):
		return [["eye_rs_ok", []], _why_good(opts[pick])]
	return [["eye_rs_no", []], _why_good(b), _why_bad(opts[pick], b)]

static func render(parts: Array, tr_fn: Callable) -> String:
	## tr_fn(anahtar, argümanlar) -> metin. İlk parça ön ek, sonrakiler "; " ile
	var s := ""
	for i: int in parts.size():
		var args: Array = []
		for a: Variant in parts[i][1]:
			args.append(tr_fn.call(str(a[0]), a[1]) if a is Array else a)
		var txt: String = tr_fn.call(str(parts[i][0]), args)
		if i == 0:
			s = txt + " "
		elif i == 1:
			s += txt
		else:
			s += "; " + txt
	return s

# ================================================================ v2: oyuncunun kararını yargıla

static func find_actual(all: Array, res: Dictionary) -> int:
	## Motorun kaydettiği gerçek hamle hangi seçenek (çapraz/uzaklaştırma -> -1, soru iptal)
	if res.is_empty():
		return -1
	for i: int in all.size():
		var o: Dictionary = all[i]
		if str(o.k) != str(res.get("k", "")):
			continue
		if o.k != "pass" or str(o.to) == str(res.get("to", "")):
			return i
	return -1

static func grade(all: Array, ai: int) -> int:
	## 0 iyi, 1 makul, 2 kötü — bizim futbol mantığımıza göre (motorun iç puanı değil)
	var b: Dictionary = all[best_index(all)]
	var o: Dictionary = all[ai]
	var gap := float(b.score) - float(o.score)
	if gap <= GOOD_GAP:
		return 0
	if gap >= BAD_GAP or (o.k == "pass" and o.lane == "blocked"):
		return 2
	return 1

static func read_attr(all: Array, ai: int) -> String:
	## Bu karar oyuncunun neyini gösterir
	var o: Dictionary = all[ai]
	if o.k == "pass" and (float(o.fwd) >= 12.0 or float(o.dist) >= 30.0):
		return "vision"
	if float(o.get("press", 99.0)) < 2.5:
		return "composure"
	return "decisions"

static func verdict_parts(all: Array, ai: int) -> Array:
	## "Neden: <iyi/kötü sebebi>; daha iyisi: <en iyi seçenek>"
	var bi := best_index(all)
	var o: Dictionary = all[ai]
	var g := grade(all, ai)
	if g == 0 or bi == ai:
		return [["eye_rs_why", []], _why_good(o)]
	return [["eye_rs_why", []], _why_bad(o, all[bi]), ["eye_rs_alt", [_why_good(all[bi])]]]

static func reveal_set(all: Array, ai: int) -> Array:
	## Açıklamada gösterilecek yollar: oyuncunun seçimi + en iyi + 2 alternatif
	var out: Array = pick_set(all)
	if ai >= 0 and not out.has(all[ai]):
		if out.size() >= MAX_OPTS:
			out.pop_back()
		out.append(all[ai])
	return out

# ================================================================ maç içi akış

static func sit_from(eng, o, name_fn: Callable) -> Dictionary:
	## Motor durumundan pozisyon (hareket yönünde kısa öngörüyle)
	var mates: Array = []
	var opps: Array = []
	for q in eng.team[o.side]:
		if q == o or q.gk or q.off:
			continue
		mates.append({"id": q.id, "pos": q.pos + q.vel * 0.4, "role": q.role, "name": name_fn.call(q.id, q.role)})
	for q in eng.team[eng.other(o.side)]:
		if q.off:
			continue
		opps.append({"pos": q.pos + q.vel * 0.3, "gk": q.gk})
	return {"d": o.d, "pos": o.pos, "pid": o.id, "mates": mates, "opps": opps}

class Director extends RefCounted:
	const EL = preload("res://sim/eye_logic.gd")
	var kind := "full"
	var focus: Array = []
	var name_fn: Callable = func(id: String, _r: String) -> String: return id
	var asked: Array = [0, 0]
	var asked_at: Array = []      # [[maç saati, yarı]]
	var last_clock := -99999.0
	var state := ""               # "" | watch | judge | verdict
	var t := 0.0
	var hold := 0.0
	var pid := ""
	var sit := {}
	var all: Array = []           # oyuncunun tüm seçenekleri (karar anındaki dizilişle)
	var opts: Array = []          # açıklamada gösterilen yollar (en çok 4)
	var best := -1                # opts içinde en iyi
	var act := -1                 # opts içinde oyuncunun gerçek seçimi
	var truth := -1               # gerçek not: 0 iyi, 1 makul, 2 kötü
	var pick := -1                # kullanıcının notu
	var ok := false
	var attr := ""
	var res := {}                 # oyuncunun gerçek hamlesi (motorun eye_res kaydı)
	var reads: Array = []         # [{pid, attr, ok, ans, k}]
	var prev_owner := ""
	var fresh := false
	var pending := ""             # tick'in bir sonraki dönüşü (answer -> "verdict")
	var min_rate := 99.0
	var parts: Array = []
	var aborts := 0
	var gap := 0.0
	var blocked := false

	func quota(h: int) -> int:
		var q: Array = EL.QUOTA.get(kind, [0, 0])
		return int(q[h])

	func total() -> int:
		return quota(0) + quota(1)

	func _half(pacer) -> int:
		return 1 if pacer.second_half else 0

	func slot_ready(eng, pacer) -> bool:
		var h := _half(pacer)
		var k := quota(h)
		var i: int = asked[h]
		if i >= k or eng.clock - last_clock < EL.GAP:
			return false
		var hp: float = pacer.half_prog(eng)
		var start := 0.08 + 0.8 * float(i) / float(k)
		if k == 1:
			start = 0.15
		return hp >= start

	func urgent(eng, pacer) -> bool:
		## Yarı bitiyor ve kota dolmadı: koşulları gevşet
		return pacer.half_prog(eng) > 0.72

	func candidate(eng, pacer) -> bool:
		## Odak oyuncu topu yeni aldı ve gerçek bir karar anında
		var o = eng.owner
		var oid: String = o.id if o != null else ""
		var changed := oid != prev_owner
		prev_owner = oid
		if not changed or o == null or not (oid in focus) or o.gk or eng.phase != "play":
			return false
		if o.decide_t < 0.15 or not slot_ready(eng, pacer):
			return false
		var urg := urgent(eng, pacer)
		if o.pos.x * o.d < -36.0 and not urg:
			return false
		var s := EL.sit_from(eng, o, name_fn)
		var al: Array = EL.options(s)
		var shown: Array = EL.pick_set(al)
		var passes := shown.filter(func(x: Dictionary) -> bool: return x.k == "pass").size()
		if shown.size() < (2 if urg else 3) or passes < 1:
			return false
		if not urg:
			var hi := -9.0
			var lo := 9.0
			for x: Dictionary in shown:
				hi = maxf(hi, float(x.score))
				lo = minf(lo, float(x.score))
			if hi - lo < 0.02:
				return false      # hepsi aynı: anlamlı karar yok
		_start(eng, s, al, shown)
		return true

	func seek_stop(eng, pacer) -> bool:
		## Özet / Anlar atlarken: soru zamanı geldiyse ve odak oyuncu karar anındaysa dur
		if state != "" or kind == "video" or kind == "full":
			return false
		if kind == "moments" and (pacer.seen_half >= pacer.PER_HALF or eng.t - pacer.seg_from < 20.0):
			return false
		return candidate(eng, pacer)

	func _start(eng, s: Dictionary, al: Array, shown: Array) -> void:
		state = "watch"
		fresh = true
		pending = ""
		t = 0.0
		hold = EL.HOLD
		pid = str(s.pid)
		sit = s
		all = al
		opts = shown
		best = -1
		act = -1
		truth = -1
		pick = -1
		ok = false
		res = {}
		parts = []
		attr = ""
		asked_at.append([eng.clock, -1])
		last_clock = eng.clock
		eng.eye_pid = pid
		eng.eye_res = {}

	func mark_half(pacer) -> void:
		## _start'ta yarıyı Pacer'dan yaz (motor saati uzatmada HALF'ı geçebilir)
		var h := _half(pacer)
		if not asked_at.is_empty() and int(asked_at[-1][1]) < 0:
			asked_at[-1][1] = h
			asked[h] += 1

	func pre_step(eng) -> void:
		## İzlerken oyuncunun kararını biraz geciktir (göze zaman); bu kısa sürede rakip top kapma denemez
		if state != "watch" or hold <= 0.0 or eng.owner == null or eng.owner.id != pid:
			return
		eng.owner.decide_t = maxf(eng.owner.decide_t, 0.3)
		for q in eng.team[eng.other(eng.owner.side)]:
			q.tackle_cd = maxf(q.tackle_cd, 0.2)
		hold -= 0.1

	func rate(base: float) -> float:
		var r := base
		match state:
			"watch":
				r = EL.SLOW
			"judge":
				r = EL.JUDGE_RATE
			"verdict":
				r = EL.VERDICT_RATE
		if state != "":
			min_rate = minf(min_rate, r)
		return r

	func answer(g: int) -> void:
		if state != "judge":
			return
		pick = g
		_verdict()
		pending = "verdict"

	func _acted(eng) -> bool:
		if not eng.eye_res.is_empty():
			return true
		if eng.phase != "play":
			return true
		return eng.owner == null and eng.flight.is_empty() or (eng.owner != null and eng.owner.id != pid)

	## Kare başına: dt gerçek süre (duraklatılmışsa 0).
	## Dönüş: "" | "start" (izle) | "judge" | "verdict" | "clear"
	func tick(dt: float, eng, pacer) -> String:
		if pending != "":
			var p := pending
			pending = ""
			return p
		match state:
			"":
				if candidate(eng, pacer):
					mark_half(pacer)
					fresh = false
					return "start"
			"watch":
				if fresh:
					fresh = false
					mark_half(pacer)
					return "start"
				t += dt
				if _acted(eng):
					return _to_judge(eng)
				if t > EL.WATCH_MAX:
					aborts += 1
					clear(eng)
					return "clear"
			"judge":
				t += dt
				if t > EL.CHOOSE_MAX:
					_verdict()
					return "verdict"
			"verdict":
				t += dt
				if t > EL.VERDICT_T:
					clear(eng)
					return "clear"
		return ""

	func _to_judge(eng) -> String:
		res = eng.eye_res.duplicate()
		eng.eye_pid = ""
		eng.eye_res = {}
		var ai := EL.find_actual(all, res)
		if ai < 0:
			# topu kaptırdı / orta / uzaklaştırma: yargılanacak net karar yok, soru sayılmaz
			aborts += 1
			clear(eng)
			return "clear"
		truth = EL.grade(all, ai)
		gap = float(all[EL.best_index(all)].score) - float(all[ai].score)
		blocked = all[ai].k == "pass" and all[ai].lane == "blocked"
		attr = EL.read_attr(all, ai)
		parts = EL.verdict_parts(all, ai)
		opts = EL.reveal_set(all, ai)
		act = opts.find(all[ai])
		best = opts.find(all[EL.best_index(all)])
		state = "judge"
		t = 0.0
		hold = 0.0
		return "judge"

	func _verdict() -> void:
		var answered := pick >= 0
		ok = answered and pick == truth
		reads.append({"pid": pid, "attr": attr, "ok": ok, "ans": answered, "k": EL.GRADES[truth], "gap": snappedf(gap, 0.001), "blk": blocked})
		state = "verdict"
		t = 0.0
		hold = 0.0

	func clear(eng) -> void:
		## Soru kapanır (devre arası / atlama / bitiş / iptal): yargılanmadıysa sayılmaz
		if state == "watch" or state == "judge":
			if state == "judge":
				_verdict()       # yargı ekranındayken kesildi: cevapsız sayılır
			elif not asked_at.is_empty():
				var h := int(asked_at[-1][1])
				if h >= 0:
					asked[h] -= 1
				asked_at.pop_back()
				last_clock = float(asked_at[-1][0]) if not asked_at.is_empty() else -99999.0
				if eng != null:
					# iptal: hemen yeni soru açılmasın (1,5 oyun dakikası nefes)
					last_clock = maxf(last_clock, float(eng.clock) - EL.GAP + 90.0)
		if eng != null:
			eng.eye_pid = ""
			eng.eye_res = {}
		state = ""
		fresh = false
		pending = ""
		t = 0.0
		hold = 0.0
