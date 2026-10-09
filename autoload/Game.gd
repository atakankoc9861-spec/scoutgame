extends Node
## Oyunun tüm durumu ve simülasyonu (v0.2). UI sadece buradaki fonksiyonları çağırır.

signal changed

const Timeline = preload("res://sim/timeline.gd")
const LiveEngine = preload("res://sim/live_engine.gd")

const SAVE_PATH := "user://kariyer.json"
const SAVE_VERSION := 5
const WEEKS := 34
const WORK_DAYS := 5          # Pzt-Cum
const WED := 2                # U19 günü
const WINDOWS := [[0, 2], [17, 19]]
## Lig yapısı: her grup ayrı bir lig kimliği. Kademe 1 = Süper Lig ... 5 = BAL
## lig -> kademe (Data.LG'den kurulur; tüm Avrupa + Brezilya)
var LEAGUES := {}
const TIER_GROUPS := {1: ["SL"], 2: ["L1"], 3: ["L2A", "L2B"]}
const TITLES := [[0, "title_0"], [20, "title_1"], [40, "title_2"], [60, "title_3"], [80, "title_4"]]

var s: Dictionary = {}
## eski sürüm (v0.17 ve öncesi) kaydı bulundu: yeni dünya ile uyumsuz
var old_save := false
var rng := RandomNumberGenerator.new()

var settings := {"quality": "medium", "sound": true, "music": true}
const SETTINGS_PATH := "user://ayarlar.cfg"
const CRASH_FLAG := "user://mac_suruyor.flag"

func _build_leagues() -> void:
	LEAGUES = {}
	for lg in Data.LG:
		# keşif ülkelerinin "havuz" ligleri simüle edilmez
		if not Data.is_scout_cc(str(Data.LG[lg].cc)):
			LEAGUES[lg] = int(Data.LG[lg].tier)

func tier_groups(cc: String, t: int) -> Array:
	return Data.COUNTRIES.get(cc, {}).get("tiers", {}).get(t, [])

func max_tier(cc: String) -> int:
	return Data.COUNTRIES.get(cc, {}).get("tiers", {}).size()

func _ready() -> void:
	_build_leagues()
	rng.randomize()
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		settings.quality = cf.get_value("g", "quality", "medium")
		settings.sound = cf.get_value("g", "sound", true)
		settings.music = cf.get_value("g", "music", true)

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("g", "quality", settings.quality)
	cf.set_value("g", "sound", settings.sound)
	cf.set_value("g", "music", settings.music)
	cf.save(SETTINGS_PATH)

func quality() -> String:
	return settings.quality

func q_scale() -> float:
	return {"high": 0.85, "medium": 0.7, "low": 0.55}.get(quality(), 0.7)

# ================================================================ yardımcılar

func ri(a: int, b: int) -> int:
	return rng.randi_range(a, b)

func rf() -> float:
	return rng.randf()

func pick(arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)]

func weighted_pick(d: Dictionary, idx: int) -> String:
	var total := 0.0
	for k in d:
		total += float(d[k][idx])
	var r := rf() * total
	for k in d:
		r -= float(d[k][idx])
		if r <= 0.0:
			return k
	return d.keys()[0]

func clampi20(v: float) -> int:
	return int(clamp(round(v), 1, 20))

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func player(pid: String) -> Dictionary:
	return s.players.get(pid, {})

func club(cid: String) -> Dictionary:
	return s.clubs.get(cid, {})

func my_club() -> Dictionary:
	return club(s.scout.club_id)

func pname(p: Dictionary) -> String:
	if p.is_empty():
		return "?"
	return "%s %s" % [p.first, p.last]

func short_name(p: Dictionary) -> String:
	if p.is_empty():
		return "?"
	return "%s. %s" % [String(p.first).substr(0, 1), p.last]

func in_window() -> bool:
	for w in WINDOWS:
		if s.week >= w[0] and s.week <= w[1]:
			return true
	return false

var _name_idx := {}
var _name_idx_n := -1

## Haber/metindeki isimden kulüp ya da oyuncu bul (tıklanabilir bağlantılar için)
func find_entity(name: String) -> Dictionary:
	if _name_idx_n != s.players.size():
		_name_idx.clear()
		for cid in s.clubs:
			_name_idx[String(s.clubs[cid].name)] = {"club": cid}
		for pid in s.players:
			var p: Dictionary = s.players[pid]
			var nm := pname(p)
			if not _name_idx.has(nm):
				_name_idx[nm] = {"player": pid}
		_name_idx_n = s.players.size()
	return _name_idx.get(name, {})

func add_news(key: String, args: Array = [], important := false, kind := "") -> void:
	s.news.push_front({"season": s.season, "week": s.week, "key": key, "args": args, "imp": important, "kind": kind})
	if s.news.size() > 160:
		s.news.resize(160)

func title_key() -> String:
	var k := "title_0"
	for t in TITLES:
		if float(s.scout.rep) >= float(t[0]):
			k = t[1]
	return k

func visible(p: Dictionary) -> bool:
	## Arama ve listelerde görünür mü (altyapı oyuncuları keşfedilene kadar gizli)
	if p.get("disc", false):
		return true
	if p.get("youth", false):
		return false
	return not Data.is_scout_cc(club_country(p.get("club", "")))

# ================================================================ oyuncu üretimi

func calc_ovr_f(p: Dictionary) -> float:
	var w: Dictionary = Data.POS_WEIGHTS[p.pos]
	var tot := 0.0
	var ws := 0.0
	for a in w:
		tot += float(p.attrs[a]) * w[a]
		ws += w[a]
	return tot / ws * 5.0

func calc_ovr(p: Dictionary) -> int:
	return int(round(calc_ovr_f(p)))

func gen_attrs(pos: String, target: int) -> Dictionary:
	var base := target / 5.0
	var attrs := {}
	var w: Dictionary = Data.POS_WEIGHTS[pos]
	for a in Data.ATTRS:
		var v := base + rng.randfn(0.0, 2.2)
		if w.has(a):
			v += 0.6 + w[a] * 0.15
		else:
			v -= 2.0
		if Data.ATTR_GROUP[a] == "gk" and pos != "GK":
			v = rng.randf_range(1, 5)
		if pos == "GK" and Data.ATTR_GROUP[a] == "tec" and a != "first_touch" and a != "passing":
			v = rng.randf_range(2, 8)
		attrs[a] = v
	for i in 6:
		var diff := target - calc_ovr_f({"pos": pos, "attrs": attrs})
		if abs(diff) < 0.6:
			break
		for a in w:
			attrs[a] += diff / 5.0
	for a in attrs:
		attrs[a] = clampi20(attrs[a])
	return attrs

func calc_value(p: Dictionary) -> int:
	var ovr := float(p.ovr)
	var v := 120000.0 * exp((ovr - 50.0) / 7.5)
	var age := int(p.age)
	if age <= 21:
		v *= 1.0 + maxf(0.0, float(p.pa) - ovr) / 22.0
	elif age >= 31:
		v *= maxf(0.25, 1.0 - (age - 30) * 0.18)
	v = clampf(v, 15000.0, 90000000.0)
	var step := 25000.0 if v < 1000000.0 else 100000.0
	return int(round(v / step) * step)

func new_player(pos: String, target: int, age: int, nat: String, cid: String, youth := false) -> String:
	var pid := "p%d" % s.next_pid
	s.next_pid += 1
	var p := {
		"id": pid,
		"first": "", "last": "",
		"nat": nat, "age": age, "pos": pos,
		"foot": "L" if (pos in ["LB", "LW"] and rf() < 0.75) or rf() < 0.2 else "R",
		"club": cid,
		"attrs": gen_attrs(pos, target),
		"hid": {}, "inj": 0,
		"st": {"apps": 0, "g": 0, "a": 0, "rs": 0.0},
		"hist": [],
		"contract": s.season + ri(1, 4),
		"agent": "%s %s" % [pick(Data.FIRST["TR"]), pick(Data.LAST["TR"])],
		"youth": youth, "disc": not youth, "rival": "",
		"skin": ri(0, 4), "hair": ri(0, 5), "seed": ri(0, 99999),
	}
	var nm := Data.name_pair(nat)
	p.first = nm[0]
	p.last = nm[1]
	if nat in ["NG", "SN", "GH", "CM"]:
		p.skin = ri(3, 4)
	elif nat in ["SE", "NL", "PL", "HR", "RS", "GE", "FR"]:
		p.skin = ri(0, 1)
	for h in Data.HIDDEN:
		p.hid[h] = ri(3, 19)
	p.ovr = calc_ovr(p)
	var room := 0
	if age <= 16:
		room = ri(10, 36)
	elif age <= 18:
		room = ri(4, 30)
	elif age <= 21:
		room = ri(2, 20)
	elif age <= 24:
		room = ri(0, 9)
	else:
		room = ri(0, 2)
	if rf() < 0.05 and age <= 19:
		room += ri(10, 22)    # nadir cevher
	p.pa = int(min(95, p.ovr + room))
	p.value = calc_value(p)
	s.players[pid] = p
	return pid

func league_country(lg: String) -> String:
	return str(Data.LG.get(lg, {}).get("cc", "TR"))

func club_country(cid: String) -> String:
	return club(cid).get("country", league_country(club(cid).get("league", "SL")))

func my_country() -> String:
	return club_country(s.scout.club_id) if s.scout.club_id != "" else str(s.get("start_cc", "TR"))

func country_lang(cc: String) -> String:
	return str(Data.COUNTRIES.get(cc, {}).get("lang", "EN"))

func nat_lang(nat: String) -> String:
	if Data.COUNTRIES.has(nat):
		return country_lang(nat)
	return {"AR": "ES", "UY": "ES", "BR": "PT"}.get(nat, "EN")

func pick_weight(d: Dictionary) -> String:
	var total := 0.0
	for k in d:
		total += float(d[k])
	var r := rf() * total
	for k in d:
		r -= float(d[k])
		if r <= 0.0:
			return k
	return d.keys()[0]

func tier(lg: String) -> int:
	return int(Data.LG.get(lg, {}).get("tier", 5))

func is_scout_club(cid: String) -> bool:
	return Data.is_scout_cc(club_country(cid))

func club_tier(cid: String) -> int:
	return tier(club(cid).get("league", "L2A"))

func tier_level(t: int, prestige: float) -> float:
	## Kademe ve prestije göre kadro hedef seviyesi (OVR)
	match t:
		1:
			return 50.0 + prestige * 0.28
		2:
			return 44.0 + prestige * 0.32
		3:
			return 40.0 + prestige * 0.33
		4:
			return 36.0 + prestige * 0.36
	return 32.0 + prestige * 0.42

func nat_for_tier(t: int) -> String:
	if t >= 4:
		return "TR" if rf() < 0.97 else weighted_pick(Data.NATIONS, 1)
	if t == 3:
		return "TR" if rf() < 0.9 else weighted_pick(Data.NATIONS, 1)
	return weighted_pick(Data.NATIONS, 0 if t == 1 else 1)

func club_level(cid: String) -> float:
	var c: Dictionary = s.clubs[cid]
	var cc := league_country(c.league)
	if cc != "TR":
		return float(Data.COUNTRIES[cc].base) + float(c.prestige) * 0.30
	return tier_level(tier(c.league), float(c.prestige))

func is_lazy(cid: String) -> bool:
	return s.clubs.has(cid) and bool(s.clubs[cid].get("lazy", false))

func ensure_squad(cid: String) -> bool:
	## Ayrıntısız (kadrosu üretilmemiş) kulübün kadrosunu ilk ihtiyaçta üret. Üretildiyse true.
	if not is_lazy(cid):
		return false
	var c: Dictionary = s.clubs[cid]
	c.erase("lazy")
	c.squad = []
	c.u19 = []
	gen_squad(cid, c.league)
	if Data.is_scout_cc(club_country(cid)):
		# keşif ülkesi: oyuncular gidip görülene kadar gizli
		for pid in c.squad + c.u19:
			s.players[pid].disc = false
	return true

func ensure_league(lg: String) -> int:
	var n := 0
	for cid in league_clubs(lg):
		if ensure_squad(cid):
			n += 1
	return n

func ensure_country(cc: String) -> void:
	for lg in Data.COUNTRIES.get(cc, {}).get("leagues", []):
		ensure_league(lg)

func has_u19(cid: String) -> bool:
	var c := club(cid)
	var t := tier(c.get("league", ""))
	return t <= 2 or (club_country(cid) == "TR" and t <= 3)

func club_nat(cid: String) -> String:
	var cc := league_country(s.clubs[cid].league)
	if cc != "TR":
		return pick_weight(Data.CLUB_NATS[cc])
	return nat_for_tier(tier(s.clubs[cid].league))

func gen_squad(cid: String, league: String) -> void:
	var c: Dictionary = s.clubs[cid]
	var t := tier(league)
	var lvl := club_level(cid)
	# önce tam bir ilk 11 + yedek kaleci, sonra derinlik (küçük kadrolarda forvet eksik kalmasın)
	var plan := ["GK", "CB", "CB", "LB", "RB", "DM", "CM", "CM", "AM", "LW", "RW", "ST", "GK", "ST", "CB", "CB",
		"LB", "RB", "CM", "DM", "AM", "LW", "RW", "ST", "GK", "CM"]
	var size: int = {1: 26, 2: 26, 3: 24, 4: 22, 5: 20}[t]
	plan = plan.slice(0, size)
	for i in plan.size():
		var pos: String = plan[i]
		var age := ri(18, 34)
		var tgt := int(lvl + rng.randfn(0.0, 4.5))
		if i % 3 == 0:
			tgt -= ri(3, 8)
		if age <= 20:
			tgt -= ri(4, 10)
		if age >= 32:
			tgt -= ri(0, 4)
		var nat := club_nat(cid)
		c.squad.append(new_player(pos, clampi(tgt, 28, 90), age, nat, cid))
	if has_u19(cid):
		gen_u19(cid, 16 if t <= 2 else 10)

const SQUAD_MIN := {1: 22, 2: 22, 3: 21, 4: 20, 5: 20}
const POS_MIN := {"GK": 2, "CB": 3, "LB": 1, "RB": 1, "DM": 1, "CM": 2, "AM": 1, "LW": 1, "RW": 1, "ST": 2}

## Eksik mevkileri ve asgari kadroyu lig seviyesine uygun oyuncularla tamamla
func fill_squad(cid: String) -> int:
	var c: Dictionary = s.clubs[cid]
	var t := tier(c.league)
	var lvl := club_level(cid)
	var cnt := {}
	for pid in c.squad:
		var p := player(pid)
		if not p.is_empty():
			cnt[p.pos] = int(cnt.get(p.pos, 0)) + 1
	var added := 0
	var need := []
	for pos in POS_MIN:
		for i in maxi(0, int(POS_MIN[pos]) - int(cnt.get(pos, 0))):
			need.append(pos)
	var depth := ["CM", "CB", "ST", "LW", "RW", "DM", "AM", "LB", "RB"]
	var di := 0
	while c.squad.size() + need.size() < int(SQUAD_MIN.get(t, 20)):
		need.append(depth[di % depth.size()])
		di += 1
	for pos in need:
		var age := ri(18, 29)
		var tgt := int(lvl + rng.randfn(0.0, 4.0)) - ri(0, 5)
		c.squad.append(new_player(pos, clampi(tgt, 28, 90), age, club_nat(cid), cid))
		added += 1
	return added

func gen_u19(cid: String, n: int, ages := [15, 18]) -> void:
	var c: Dictionary = s.clubs[cid]
	var plan := ["GK", "CB", "CB", "LB", "RB", "DM", "CM", "CM", "AM", "LW", "RW", "ST", "GK", "CB", "CM", "ST", "LW", "RW"]
	var base := 30.0 + float(c.prestige) * 0.18
	for i in n:
		var pos: String = plan[i % plan.size()]
		var age := ri(ages[0], ages[1])
		var tgt := int(base + (age - 15) * 3.0 + rng.randfn(0.0, 4.0))
		var cc := league_country(c.league)
		var home_nat: String = cc
		var nat := home_nat if rf() < 0.88 else (weighted_pick(Data.NATIONS, 1) if cc == "TR" else pick_weight(Data.CLUB_NATS[cc]))
		var pid := new_player(pos, clampi(tgt, 25, 64), age, nat, cid, true)
		if cc == "BR":
			# Brezilya: ham ama yüksek tavanlı gençler
			var bp: Dictionary = s.players[pid]
			bp.pa = mini(95, int(bp.pa) + ri(0, 9))
		c.u19.append(pid)

func new_manager(nat := "TR") -> Dictionary:
	var nm := Data.name_pair(nat)
	return {
		"name": "%s %s" % [nm[0], nm[1]],
		"style": pick(Data.MANAGER_STYLES),
		"pref": pick(["young", "exp", "none", "none"]),
	}

# ================================================================ yeni oyun

func new_game(scout_name: String, lang: String, start_cc := "TR") -> void:
	if not Data.COUNTRIES.has(start_cc) or Data.is_scout_cc(start_cc):
		start_cc = "TR"
	s = {
		"version": SAVE_VERSION, "lang": lang,
		"season": 2026, "week": 0,
		"clubs": {}, "players": {}, "next_pid": 1,
		"fixtures": {}, "table": {}, "u19fx": [],
		"scout": {
			"name": scout_name, "club_id": "", "rep": 15.0,
			"eye": 9, "net": 8, "xp_eye": 0, "xp_net": 0,
			"money": 2000, "salary": 0, "budget": 0, "spent": 0, "fatigue": 0,
			"knowledge": {}, "shortlist": [], "reports": [], "history": [], "langs": [country_lang(start_cc)],
			"stats": {"watched": 0, "disc": 0, "signed": 0, "tips": 0, "reports": 0, "finds": 0},
		},
		"cal": {},
		"assign": [], "next_aid": 1, "next_rid": 1,
		"plan": {"sat": "", "sun": "", "focus_sat": [], "focus_sun": [], "travel_sat": "", "travel_sun": ""},
		"pending": [], "last_obs": [], "season_summary": {}, "offers": [], "news": [],
		"staff": [], "staff_pool": [], "staff_reports": [], "next_sid": 1,
	}
	s["start_cc"] = start_cc
	_ensure_v15()
	var idx := 0
	for row in Data.SUPER_LIG:
		_make_club("c%d" % idx, row, "SL")
		idx += 1
	for row in Data.BIRINCI_LIG:
		_make_club("c%d" % idx, row, "L1")
		idx += 1
	var l2 := []
	for row in Data.IKINCI_LIG:
		_make_club("c%d" % idx, row, "L2A")
		l2.append("c%d" % idx)
		idx += 1
	_regroup(3, l2)
	for cc in Data.WORLD_CLUBS:
		var mnat: String = cc
		for row in Data.WORLD_CLUBS[cc]:
			var cid := "c%d" % idx
			_make_club(cid, row, row[6])
			s.clubs[cid].manager = new_manager(mnat if rf() < 0.8 else pick_weight(Data.CLUB_NATS[cc]))
			idx += 1
	for cid in s.clubs:
		s.clubs[cid].country = league_country(s.clubs[cid].league)
	# ayrıntı: yalnızca başlangıç ülkesi tam üretilir, diğerleri ilk ihtiyaçta
	for cid in s.clubs:
		if s.clubs[cid].country == start_cc:
			gen_squad(cid, s.clubs[cid].league)
		else:
			s.clubs[cid]["lazy"] = true
	var dbd: Dictionary = DB.active()
	if not dbd.is_empty():
		s["db_name"] = str(dbd.get("name", ""))
		DB.apply_to_world(dbd)
	make_fixtures()
	make_u19_fixtures()

func _make_club(cid: String, row: Array, league: String) -> void:
	s.clubs[cid] = {
		"id": cid, "name": row[0], "short": row[1], "city": row[2], "prestige": mini(99, int(row[3])),
		"c1": row[4], "c2": row[5], "league": league,
		"budget": int(round(300000.0 * exp(float(mini(99, int(row[3]))) / 20.0) / 50000.0) * 50000),
		"manager": new_manager(), "squad": [], "u19": [],
	}

func _regroup(t: int, ids: Array) -> void:
	## Kademedeki kulüpleri coğrafi olarak (boylama göre) gruplara böl (yalnızca Türkiye)
	var groups: Array = TIER_GROUPS[t]
	if groups.size() == 1:
		for cid in ids:
			s.clubs[cid].league = groups[0]
		return
	var keyed := []
	for cid in ids:
		var pos = Data.CITY_POS.get(s.clubs[cid].city, [39.0, 35.0])
		keyed.append([float(pos[1]) + float(pos[0]) * 0.15 + rf() * 0.01, cid])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	var per := int(ceil(float(keyed.size()) / groups.size()))
	for i in keyed.size():
		s.clubs[keyed[i][1]].league = groups[mini(i / per, groups.size() - 1)]

func tier_clubs(t: int, cc := "TR") -> Array:
	var out := []
	for cid in s.clubs:
		if tier(s.clubs[cid].league) == t and league_country(s.clubs[cid].league) == cc:
			out.append(cid)
	return out

func job_offers_start(cc := "") -> Array:
	## Başlangıç teklifleri: seçilen ülkenin farklı kademelerinden, alt kademeler ağırlıklı
	if cc == "":
		cc = str(s.get("start_cc", "TR"))
	var out := []
	var mt := maxi(1, max_tier(cc))
	var want := {}
	match mt:
		1:
			want = {1: 4}
		2:
			want = {1: 2, 2: 3}
		_:
			want = {1: 1, 2: 2, 3: 3}
	for t in want:
		var pool := []
		var all_t := tier_clubs(t, cc)
		all_t.sort_custom(func(a, b): return s.clubs[a].prestige < s.clubs[b].prestige)
		# üst kademede yalnızca alt yarı (yeni scout'a büyük kulüp gelmez)
		var lim := all_t.size() if t > 1 or mt == 1 else int(ceil(all_t.size() * 0.5))
		if mt == 1:
			lim = int(ceil(all_t.size() * 0.7))
		pool = all_t.slice(0, lim)
		pool.shuffle()
		out += pool.slice(0, want[t])
	out.sort_custom(func(a, b): return s.clubs[a].prestige > s.clubs[b].prestige)
	return out

func offer_salary(c: Dictionary) -> int:
	return 90 + int(c.prestige) * 8

func offer_budget(c: Dictionary) -> int:
	return 6000 + int(c.prestige) * 420

func take_job(cid: String) -> void:
	var c: Dictionary = s.clubs[cid]
	ensure_country(club_country(cid))
	s.scout.club_id = cid
	s.scout.salary = offer_salary(c)
	s.scout.budget = offer_budget(c)
	s.scout.spent = 0
	s.scout["rep_start"] = s.scout.rep
	s.assign = []
	add_news("n_hired", [c.name, c.manager.name], true, "career")
	make_assignments(3)
	save_game()

func league_clubs(lg: String) -> Array:
	var out := []
	for cid in s.clubs:
		if s.clubs[cid].league == lg:
			out.append(cid)
	return out

func make_fixtures() -> void:
	s.fixtures = {}
	s.table = {}
	for lg in LEAGUES:
		var ids := league_clubs(lg)
		if ids.size() < 2:
			continue
		ids.shuffle()
		var n := ids.size()
		var rounds := []
		var arr := ids.duplicate()
		for r in n - 1:
			var rnd := []
			for i in n / 2:
				var h: String = arr[i]
				var a: String = arr[n - 1 - i]
				if r % 2 == 1:
					var t := h
					h = a
					a = t
				rnd.append({"h": h, "a": a, "day": "sat" if i % 2 == 0 else "sun", "gh": -1, "ga": -1, "ev": []})
			rounds.append(rnd)
			var last = arr.pop_back()
			arr.insert(1, last)
		var second := []
		for rnd in rounds:
			var r2 := []
			for m in rnd:
				r2.append({"h": m.a, "a": m.h, "day": m.day, "gh": -1, "ga": -1, "ev": []})
			second.append(r2)
		s.fixtures[lg] = rounds + second
		var tb := {}
		for cid in ids:
			tb[cid] = {"p": 0, "w": 0, "d": 0, "l": 0, "gf": 0, "ga": 0, "pts": 0, "form": []}
		s.table[lg] = tb

func make_u19_fixtures() -> void:
	## Çarşamba U19 maçları: yakın kulüpler eşleşir (altyapısı olan kulüpler)
	var ids: Array = []
	var mc := my_country()
	for cid in s.clubs:
		if not s.clubs[cid].u19.is_empty() and club_country(cid) == mc:
			ids.append(cid)
	ids.shuffle()
	var fx := []
	var used := {}
	for a in ids:
		if used.has(a):
			continue
		var best := ""
		var bd := 1e9
		for b in ids:
			if b == a or used.has(b):
				continue
			var d := Data.city_distance(club(a).city, club(b).city) + rf() * 400.0
			if d < bd:
				bd = d
				best = b
		if best != "":
			used[a] = true
			used[best] = true
			fx.append({"h": a, "a": best})
	s.u19fx = fx

func round_for_week(lg: String, w: int) -> int:
	## Hafta -> tur. Kısa liglerin turları sezona eşit yayılır (bazı haftalar boş).
	if not s.fixtures.has(lg) or w < 1 or w > WEEKS:
		return -1
	var n: int = s.fixtures[lg].size()
	if n >= WEEKS:
		return w - 1 if w - 1 < n else -1
	for k in n:
		if 1 + int(round(float(k) * float(WEEKS - 1) / float(n - 1))) == w:
			return k
	return -1

func week_matches(lgs: Array = []) -> Array:
	var out := []
	if s.week < 1 or s.week > WEEKS:
		return out
	for lg in (LEAGUES.keys() if lgs.is_empty() else lgs):
		var r := round_for_week(lg, s.week)
		if r < 0:
			continue
		var rnd: Array = s.fixtures[lg][r]
		for i in rnd.size():
			out.append({"lg": lg, "idx": i, "m": rnd[i]})
	return out

func league_round_count(lg: String) -> int:
	return s.fixtures[lg].size() if s.fixtures.has(lg) else 0

func match_key(lg: String, idx: int) -> String:
	return "%s:%d" % [lg, idx]

func get_match(key: String) -> Dictionary:
	var parts := key.split(":")
	return s.fixtures[parts[0]][round_for_week(parts[0], s.week)][int(parts[1])]

func sorted_table(lg: String) -> Array:
	var ids: Array = s.table[lg].keys()
	ids.sort_custom(func(a, b):
		var ta = s.table[lg][a]
		var tb = s.table[lg][b]
		if ta.pts != tb.pts:
			return ta.pts > tb.pts
		var gda = ta.gf - ta.ga
		var gdb = tb.gf - tb.ga
		if gda != gdb:
			return gda > gdb
		return ta.gf > tb.gf)
	return ids

# ================================================================ seyahat ve takvim

func travel_info(city: String) -> Dictionary:
	var home: String = my_club().city
	var d := Data.city_distance(home, city)
	if Data.city_country(city) != Data.city_country(home):
		return {"cost": int(round((250.0 + d * 0.11) / 10.0) * 10), "fat": 22 + int(d / 1200.0), "mode": "plane_int", "km": int(d)}
	if d < 5:
		return {"cost": 40, "fat": 4, "mode": "local", "km": 0}
	if d < 320:
		return {"cost": 130, "fat": 10, "mode": "bus", "km": int(d)}
	if d < 650:
		return {"cost": 260, "fat": 16, "mode": "bus_hotel", "km": int(d)}
	return {"cost": 420, "fat": 20, "mode": "plane", "km": int(d)}

func _spend_travel(city: String) -> Dictionary:
	var info := travel_info(city)
	var room := maxi(0, int(s.scout.budget) - int(s.scout.spent))
	var cost: int = info.cost
	if cost > room:
		# bütçe bitti: fark scout'un kendi cebinden (para yetmezse bütçe aşılır)
		var pocket := mini(cost - room, int(s.scout.money))
		s.scout.money -= pocket
		cost -= pocket
		s.scout["pocket"] = int(s.scout.get("pocket", 0)) + pocket
	s.scout.spent += cost
	s.scout.fatigue = min(100, s.scout.fatigue + info.fat)
	return info

func free_days() -> int:
	return WORK_DAYS - s.cal.size()

func wed_free() -> bool:
	return not s.cal.has(str(WED))

func _take_day(act: String, pid: String, wed_only := false) -> int:
	## Bir iş gününü doldurur. Çarşamba U19 için saklanır.
	if wed_only:
		if not wed_free():
			return -1
		s.cal[str(WED)] = {"act": act, "pid": pid}
		return WED
	for d in [0, 1, 3, 4, 2]:
		if not s.cal.has(str(d)):
			s.cal[str(d)] = {"act": act, "pid": pid}
			return d
	return -1

func match_abroad(key: String) -> bool:
	if key == "":
		return false
	var m := get_match(key)
	return Data.city_country(club(m.h).city) != Data.city_country(my_club().city)

func plan_match(day: String, key: String) -> bool:
	## Yurtdışı maç: bir iş günü yolculuğa gider (cuma tercih edilir)
	var old: String = s.plan[day]
	if key != "":
		var mm := get_match(key)
		ensure_squad(mm.h)
		ensure_squad(mm.a)
	var td: String = s.plan.get("travel_" + day, "")
	if td != "":
		s.cal.erase(td)
		s.plan["travel_" + day] = ""
	if key != "" and match_abroad(key) and not board_abroad_ok(club_country(get_match(key).h)):
		return false
	if key != "" and match_abroad(key):
		var d := -1
		for cand in [4, 3, 1, 0]:
			if not s.cal.has(str(cand)):
				d = cand
				break
		if d < 0:
			s.plan[day] = old
			if old != "" and match_abroad(old) and td != "":
				s.cal[td] = {"act": "travel", "pid": ""}
				s.plan["travel_" + day] = td
			return false
		s.cal[str(d)] = {"act": "travel", "pid": ""}
		s.plan["travel_" + day] = str(d)
	s.plan[day] = key
	s.plan["focus_" + day] = []
	changed.emit()
	return true

func watch_mode(day: String) -> String:
	return str(s.plan.get("mode_" + day, s.scout.get("watch_pref", "full")))

func set_watch_mode(day: String, wm: String) -> void:
	s.plan["mode_" + day] = wm
	s.scout["watch_pref"] = wm
	var f: Array = s.plan["focus_" + day]
	while f.size() > focus_cap(day):
		f.pop_back()
	changed.emit()

func focus_cap(day: String) -> int:
	return 6 if watch_mode(day) == "moments" else 3

func toggle_focus(day: String, pid: String) -> void:
	var f: Array = s.plan["focus_" + day]
	if pid in f:
		f.erase(pid)
	elif f.size() < focus_cap(day):
		f.append(pid)
	changed.emit()

# ================================================================ bilgi / sis perdesi

func know(pid: String) -> Dictionary:
	if not s.scout.knowledge.has(pid):
		var e := {}
		var k := {}
		for a in Data.ATTRS:
			k[a] = 0.0
			e[a] = snappedf(rng.randfn(0.0, 3.0), 0.01)
		s.scout.knowledge[pid] = {"k": k, "e": e, "pa_k": 0.0, "pa_e": snappedf(rng.randfn(0.0, 10.0), 0.1),
			"hid": {}, "seen": 0, "vid": 0, "met": false, "notes": []}
	return s.scout.knowledge[pid]

func eye_factor() -> float:
	return 0.55 + float(s.scout.eye) / 20.0 * 0.75

func fatigue_factor() -> float:
	return 1.0 - clampf((float(s.scout.fatigue) - 40.0) / 100.0, 0.0, 0.45)

func observe(pid: String, strength: float, groups: Array, perf_noise_scale := 1.0) -> void:
	## Genel gözlem (video, antrenman)
	var p := player(pid)
	if p.is_empty():
		return
	var kn := know(pid)
	var w: Dictionary = Data.POS_WEIGHTS[p.pos]
	var cons := float(p.hid.consistency)
	for a in Data.ATTRS:
		var g: String = Data.ATTR_GROUP[a]
		if not (g in groups):
			continue
		if g == "gk" and p.pos != "GK":
			continue
		var vis := 1.3 if w.has(a) else 0.55
		var gain: float = clampf(strength * vis * eye_factor() * fatigue_factor() * area_learn_mult(pid) * rng.randf_range(0.7, 1.2), 0.0, 0.6)
		kn.k[a] = snappedf(minf(1.0, kn.k[a] + gain * (1.0 - kn.k[a]) * 1.4), 0.001)
		var perf := rng.randfn(0.0, (2.6 - cons * 0.11) * perf_noise_scale)
		kn.e[a] = snappedf(lerpf(float(kn.e[a]), perf, clampf(gain * 1.3, 0.0, 0.8)), 0.01)
	if int(p.age) <= 23:
		kn.pa_k = snappedf(minf(0.85, kn.pa_k + strength * 0.25 * eye_factor()), 0.001)
		kn.pa_e = snappedf(lerpf(float(kn.pa_e), rng.randfn(0.0, 4.0), strength * 0.3), 0.1)

func attr_range(pid: String, a: String) -> Array:
	var kn: Dictionary = s.scout.knowledge.get(pid, {})
	if kn.is_empty() or kn.k[a] < 0.05:
		return []
	var p := player(pid)
	var est := float(p.attrs[a]) + float(kn.e[a])
	var u := (1.0 - float(kn.k[a])) * 5.8 * (1.15 - float(s.scout.eye) / 40.0)
	return [clampi20(est - u), clampi20(est + u)]

func known_fraction(pid: String) -> float:
	var kn: Dictionary = s.scout.knowledge.get(pid, {})
	if kn.is_empty():
		return 0.0
	var p := player(pid)
	var w: Dictionary = Data.POS_WEIGHTS[p.pos]
	var t := 0.0
	var n := 0.0
	for a in w:
		t += float(kn.k[a]) * w[a]
		n += w[a]
	return t / n

func ovr_range(pid: String) -> Array:
	var p := player(pid)
	if p.is_empty() or known_fraction(pid) < 0.12:
		return []
	var w: Dictionary = Data.POS_WEIGHTS[p.pos]
	var lo := 0.0
	var hi := 0.0
	var ws := 0.0
	for a in w:
		var r := attr_range(pid, a)
		if r.is_empty():
			var c0 := prior_center(pid, a)
			r = [c0 - 6.0, c0 + 6.0]
		lo += float(r[0]) * w[a]
		hi += float(r[1]) * w[a]
		ws += w[a]
	return [int(round(lo / ws * 5.0)), int(round(hi / ws * 5.0))]

func pa_range(pid: String) -> Array:
	var kn: Dictionary = s.scout.knowledge.get(pid, {})
	if kn.is_empty() or kn.pa_k < 0.05:
		return []
	var p := player(pid)
	var est := float(p.pa) + float(kn.pa_e)
	var u := (1.0 - float(kn.pa_k)) * 22.0
	var o := ovr_range(pid)
	var floor_v := 30
	if not o.is_empty():
		floor_v = o[0]
	return [int(clamp(round(est - u), floor_v, 99)), int(clamp(round(est + u), floor_v, 99))]

## Radar ekseni: [anahtar, özellikler]
const RADAR := [["r_pac", ["pace", "agility"]], ["r_tec", ["dribbling", "first_touch"]], ["r_pas", ["passing", "vision", "crossing"]],
	["r_sho", ["finishing", "composure"]], ["r_def", ["tackling", "positioning", "heading"]], ["r_phy", ["strength", "stamina", "work_rate"]]]
const RADAR_GK := [["r_ref", ["reflexes"]], ["r_han", ["handling"]], ["r_pos", ["positioning", "decisions"]],
	["r_dis", ["passing", "first_touch"]], ["r_men", ["composure", "work_rate"]], ["r_phy", ["strength", "agility"]]]

func radar_data(pid: String) -> Array:
	## [[etiket, düşük, yüksek] ...] 1-20 ölçeği; bilinmeyen = []
	var p := player(pid)
	var axes: Array = RADAR_GK if p.pos == "GK" else RADAR
	var out := []
	for ax in axes:
		var lo := 0.0
		var hi := 0.0
		var known := 0
		for a in ax[1]:
			var r := attr_range(pid, a)
			if r.is_empty():
				lo += 1.0
				hi += 20.0
			else:
				lo += r[0]
				hi += r[1]
				known += 1
		var n: float = ax[1].size()
		out.append([ax[0], lo / n, hi / n, known > 0])
	return out

static func stars(v: float) -> float:
	return clampf(round((v - 40.0) / 10.0 * 2.0) / 2.0, 0.5, 5.0)

func hid_level(v: int) -> int:
	if v <= 7:
		return 0
	if v <= 13:
		return 1
	return 2

# ================================================================ hafta içi aksiyonlar

func do_video(pid: String, focus := "tec", sparks := 0) -> Dictionary:
	var p := player(pid)
	if p.get("youth", false):
		return {"ok": false, "msg": "no_footage"}
	if free_days() <= 0:
		return {"ok": false, "msg": "no_wp"}
	_take_day("video", pid)
	var kn := know(pid)
	kn.vid += 1
	var strength := 0.2 if p.st.apps > 0 else 0.08
	var groups: Array = FOCUS_GROUPS.get(focus, ["tec", "gk"])
	observe(pid, strength / (1.0 + kn.vid * 0.25) + 0.08 * sparks, groups, 1.3)
	_gain_xp("eye", 1)
	changed.emit()
	return {"ok": true, "msg": "video_done", "lines": _obs_lines(pid, groups, 3 + mini(sparks, 2)), "sparks": sparks}

func video_match_data(pid: String) -> Dictionary:
	## Video analizi: oyuncunun önceki bir maçı (kurgu maç) yalnızca onun anlarıyla oynatılır
	var p := player(pid)
	var cid: String = p.club
	ensure_squad(cid)
	var opps := []
	for oc in league_clubs(club(cid).get("league", "")):
		if oc != cid:
			opps.append(oc)
	if opps.is_empty():
		for oc in s.clubs:
			if oc != cid and club_country(oc) == club_country(cid):
				opps.append(oc)
	var opp: String = pick(opps) if not opps.is_empty() else cid
	ensure_squad(opp)
	var home := rf() < 0.5
	var m := {"h": cid if home else opp, "a": opp if home else cid, "day": "", "gh": -1, "ga": -1, "ev": []}
	m.xi_h = best_xi(m.h, true)
	m.xi_a = best_xi(m.a, true)
	var side := "xi_h" if home else "xi_a"
	var xi: Array = m[side]
	if not (pid in xi):
		# oyuncu ilk 11'de değilse aynı bölgedeki bir oyuncunun yerine koy
		var rep_i := -1
		for i in xi.size():
			if Data.POS_GROUP[player(xi[i]).pos] == Data.POS_GROUP[p.pos]:
				rep_i = i
		if rep_i < 0:
			rep_i = xi.size() - 1
		xi[rep_i] = pid
	var eng = LiveEngine.new()
	eng.setup(self, m, false)
	var weeks_ago := ri(1, 6)
	return {"key": "video:" + pid, "m": m, "tl": eng.events, "youth": false, "eng": eng, "lg": "",
		"video": true, "moments": true, "max_moments": 5, "vs": opp, "ago": weeks_ago, "vpid": pid}

func finish_video(pid: String, data: Dictionary, fe: Dictionary, focus := "tec") -> Dictionary:
	var p := player(pid)
	if p.is_empty():
		return {"ok": false, "msg": "no_footage"}
	_take_day("video", pid)
	var kn := know(pid)
	kn.vid += 1
	# yalnızca gerçekten izlenen anların olayları
	var seen_tl := []
	for i in fe.get(pid, []):
		if int(i) >= 0 and int(i) < data.tl.size():
			seen_tl.append(data.tl[int(i)])
	var agg := Timeline.aggregate(self, seen_tl, [pid])
	var decay := 1.0 / (1.0 + float(kn.vid - 1) * 0.25)
	_learn_from_agg(pid, agg[pid], clampf(0.25 + seen_tl.size() * 0.03, 0.25, 0.75) * decay)
	var groups: Array = FOCUS_GROUPS.get(focus, ["tec", "gk"])
	var sp: int = int(fe.get("_sparks", {}).get(pid, 0))
	observe(pid, (0.08 + 0.06 * mini(sp, 3)) * decay, groups, 1.2)
	var eyes: Array = fe.get("_eye", {}).get(pid, [])
	if not eyes.is_empty():
		var ag2 := {"attr": {}}
		for e in eyes:
			if float(e[2]) > 0.004:
				Timeline._credit(ag2, [["decisions", float(e[1]), float(e[2])], ["vision", float(e[1]), float(e[2]) * 0.5]], bool(e[0]))
		if not ag2.attr.is_empty():
			_learn_from_agg(pid, ag2, 1.4)
	var hits: int = int(fe.get("_eye_hits", {}).get(pid, 0))
	if hits > 0:
		_gain_xp("eye", 2 * hits)
	var m: Dictionary = data.m
	var notes := Timeline.notes_for(self, pid, agg[pid], m)
	kn.notes.push_front({"season": s.season, "week": s.week, "vs": data.get("vs", ""), "r": 0.0, "n": notes,
		"line": Timeline.stat_line(agg[pid]), "youth": false, "video": true})
	if kn.notes.size() > 8:
		kn.notes.resize(8)
	_gain_xp("eye", 1)
	changed.emit()
	return {"ok": true, "msg": "video_done", "lines": _obs_lines(pid, groups, 3 + mini(sp, 2)), "sparks": sp, "notes": notes}

const FOCUS_GROUPS := {"phy": ["phy"], "men": ["men"], "tec": ["tec", "gk"], "all": ["phy", "men", "tec", "gk"]}

func do_training(pid: String, focus := "all", sparks := 0) -> Dictionary:
	## sparks: gözlem sırasında yakalanan kıvılcım anları (0-3)
	if free_days() <= 0:
		return {"ok": false, "msg": "no_wp"}
	var p := player(pid)
	var c := club(p.club)
	_take_day("train", pid)
	_spend_travel(c.city)
	area_gain(area_of_club(p.club), 0.7)
	var groups: Array = FOCUS_GROUPS.get(focus, ["phy", "men"])
	observe(pid, (0.3 if focus != "all" else 0.18) + 0.1 * sparks, groups, 0.9)
	var kn := know(pid)
	var res := {"ok": true, "msg": "train_done", "focus": focus, "lines": _obs_lines(pid, groups, 3 + mini(sparks, 2)), "sparks": sparks}
	if rf() < 0.5 or sparks > 0:
		var lvl := hid_level(int(p.hid.professionalism))
		if rf() > 0.75 and sparks == 0:
			lvl = clampi(lvl + (1 if rf() < 0.5 else -1), 0, 2)
		kn.hid["professionalism"] = {"lvl": lvl, "src": "training"}
		res.trait = ["professionalism", lvl]
	if sparks >= 2:
		var t2: String = ["big_match", "consistency", "adaptability"][randi() % 3]
		var lv2 := hid_level(int(p.hid.get(t2, 10)))
		kn.hid[t2] = {"lvl": lv2, "src": "training"}
		res.trait2 = [t2, lv2]
	_gain_xp("eye", 1)
	changed.emit()
	return res

func _obs_lines(pid: String, groups: Array, n: int) -> Array:
	## Gözlem cümleleri: bilinen aralığa göre öne çıkan özellikler
	var p := player(pid)
	var cands := []
	for a in Data.ATTRS:
		if not (Data.ATTR_GROUP[a] in groups):
			continue
		if Data.ATTR_GROUP[a] == "gk" and p.pos != "GK":
			continue
		var r := attr_range(pid, a)
		if r.is_empty():
			continue
		var mid := (float(r[0]) + float(r[1])) / 2.0
		cands.append([absf(mid - 10.5) + rf() * 2.0, a, mid, r])
	cands.sort_custom(func(x, y): return x[0] > y[0])
	var out := []
	for c in cands.slice(0, n):
		var lvl := "hi" if c[2] >= 13.5 else ("lo" if c[2] <= 8.5 else "mid")
		out.append(["obsl_" + lvl, [T.t("a_" + c[1]), "%d–%d" % [c[3][0], c[3][1]]]])
	return out

func do_meet(pid: String, topics: Array = []) -> Dictionary:
	if free_days() <= 0:
		return {"ok": false, "msg": "no_wp"}
	var p := player(pid)
	var kn := know(pid)
	if kn.met:
		return {"ok": false, "msg": "already_met"}
	if not can_talk(pid):
		return {"ok": false, "msg": "need_lang"}
	_take_day("meet", pid)
	_spend_travel(club(p.club).city)
	area_gain(area_of_club(p.club), 1.0)
	kn.met = true
	var asked: Array = topics if not topics.is_empty() else ["professionalism", "adaptability"]
	var answers := []
	for t in asked:
		var lvl := hid_level(int(p.hid[t]))
		if rf() > 0.9:
			lvl = clampi(lvl + (1 if rf() < 0.5 else -1), 0, 2)
		kn.hid[t] = {"lvl": lvl, "src": "meet"}
		answers.append([t, lvl])
	_gain_xp("net", 2)
	changed.emit()
	return {"ok": true, "msg": "meet_done", "answers": answers}

func do_source(pid: String, kind: String, want := "") -> Dictionary:
	if free_days() <= 0:
		return {"ok": false, "msg": "no_wp"}
	var cost: int = {"coach": 60, "agent": 0, "journalist": 30}[kind]
	if s.scout.money < cost:
		return {"ok": false, "msg": "no_money"}
	_take_day("src_" + kind, pid)
	area_gain(area_of_player(pid), 0.6)
	s.scout.money -= cost
	var p := player(pid)
	var kn := know(pid)
	var net := float(s.scout.net)
	var pool: Array = {"coach": ["professionalism", "injury_prone", "adaptability"],
		"agent": ["professionalism", "big_match", "consistency", "adaptability"],
		"journalist": ["big_match", "consistency", "adaptability", "professionalism"]}[kind]
	var options := []
	for t in pool:
		if not kn.hid.has(t) or kn.hid[t].src == "agent":
			options.append(t)
	if options.is_empty():
		changed.emit()
		return {"ok": true, "msg": "src_nothing"}
	var success: float = {"coach": 0.45 + net / 40.0, "agent": 1.0, "journalist": 0.55 + net / 45.0}[kind]
	if not can_talk(pid):
		success *= 0.45
	if rf() > success:
		_gain_xp("net", 1)
		changed.emit()
		return {"ok": true, "msg": "src_fail_" + kind}
	var t: String = want if want in options else pick(options)
	var lvl := hid_level(int(p.hid[t]))
	var reliab: float = {"coach": 0.72 + net / 80.0, "agent": 0.4, "journalist": 0.6 + net / 70.0}[kind]
	if rf() > reliab:
		lvl = clampi(lvl + (1 if rf() < 0.6 else -1), 0, 2)
	if kind == "agent":
		if t == "injury_prone":
			lvl = 0
		elif rf() < 0.6:
			lvl = clampi(lvl + 1, 0, 2)
	kn.hid[t] = {"lvl": lvl, "src": kind}
	if kind == "coach" and int(p.age) <= 23:
		kn.pa_k = minf(0.9, kn.pa_k + 0.12)
		kn.pa_e = lerpf(float(kn.pa_e), rng.randfn(0.0, 3.0), 0.3)
	_gain_xp("net", 2)
	changed.emit()
	return {"ok": true, "msg": "src_ok", "trait": t, "lvl": lvl, "kind": kind}

# ================================================================ keşif seyahati

const TRIP_KINDS := ["academy", "league"]

func trip_city(cc: String) -> String:
	## Ülkenin ana şehri (veri dosyasındaki ilk şehir)
	for city in Data.CITY_W:
		if str(Data.CITY_W[city][2]) == cc:
			return city
	return ""

func trip_cost(cc: String) -> int:
	var city := trip_city(cc)
	if city == "" or my_club().is_empty():
		return 0
	return int(round(float(travel_info(city).cost) * 1.6 / 10.0) * 10)

func trip_check(cc: String) -> String:
	if s.week < 1:
		return "trip_preseason"
	if free_days() < 2:
		return "trip_days"
	if not board_abroad_ok(cc):
		return "need_board_abroad"
	return ""

func do_trip(cc: String, kind := "academy") -> Dictionary:
	## Keşif ülkesine 2 günlük seyahat: altyapı turnuvası ya da yerel lig. Gizli oyuncuları ortaya çıkarır.
	var why := trip_check(cc)
	if why != "":
		return {"ok": false, "msg": why}
	var city := trip_city(cc)
	_take_day("trip", "")
	_take_day("trip", "")
	var info := _spend_travel(city)
	s.scout.spent += int(float(info.cost) * 0.6)
	var clubs := []
	for cid in s.clubs:
		if club_country(cid) == cc:
			clubs.append(cid)
	clubs.shuffle()
	var visit: Array = clubs.slice(0, 4 if kind == "academy" else 3)
	var pool := []
	for cid in visit:
		ensure_squad(cid)
		var c := club(cid)
		for pid in (c.u19 + c.squad if kind == "academy" else c.squad):
			var p := player(pid)
			if p.is_empty():
				continue
			if kind == "academy" and int(p.age) > 19:
				continue
			if kind == "league" and int(p.age) > 30:
				continue
			pool.append(pid)
	var found := []
	var eye := float(s.scout.eye)
	var n := 6 if kind == "academy" else 5
	for i in n:
		var best := ""
		var bv := -999.0
		for k in 8:
			if pool.is_empty():
				break
			var pid: String = pick(pool)
			if pid in found:
				continue
			var p := player(pid)
			var val := float(p.pa if kind == "academy" else p.ovr)
			val += rng.randfn(0.0, (22.0 - eye) * 0.6)
			if val > bv:
				bv = val
				best = pid
		if best == "":
			continue
		found.append(best)
		var bp := player(best)
		if not bp.disc:
			bp.disc = true
			s.scout.stats.disc += 1
		observe(best, 0.16 if kind == "academy" else 0.13, ["tec", "phy", "men"], 1.1)
		log_discovery(best, "trip", Data.country_name(cc))
	area_gain(Data.zone_of(cc), 3.0)
	_gain_xp("eye", 1)
	add_news("n_trip", [Data.country_name(cc), found.size()], true, "career")
	changed.emit()
	return {"ok": true, "pids": found, "cc": cc, "kind": kind, "cost": int(info.cost * 1.6)}

func rest_day() -> bool:
	if free_days() <= 0:
		return false
	_take_day("rest", "")
	s.scout.fatigue = max(0, s.scout.fatigue - 30)
	changed.emit()
	return true

func _gain_xp(which: String, amt: int) -> void:
	var key := "xp_" + which
	s.scout[key] += amt
	var need := int(s.scout[which]) * 4
	if s.scout[key] >= need and s.scout[which] < 20:
		s.scout[key] -= need
		s.scout[which] += 1
		add_news("n_skill_up_" + which, [s.scout[which]], true, "career")

func course_cost(kind: String) -> int:
	return {"eye": 900 + s.scout.eye * 120, "net": 700 + s.scout.net * 100}[kind]

func buy_course(kind: String) -> bool:
	var cost := course_cost(kind)
	if s.scout.money < cost:
		return false
	s.scout.money -= cost
	_gain_xp(kind, int(s.scout[kind]) * 4)
	changed.emit()
	return true

func toggle_shortlist(pid: String) -> void:
	var sl: Array = s.scout.shortlist
	if pid in sl:
		sl.erase(pid)
	else:
		sl.append(pid)
	changed.emit()

# ================================================================ görevler ve raporlar

func make_assignments(n: int) -> void:
	var c := my_club()
	var avg := club_avg_ovr(c.id)
	for i in n:
		var kind: String = pick(["first11", "first11", "prospect", "backup", "wonderkid"])
		var grp: String = pick(["DEF", "MID", "ATT", "DEF", "ATT", "GK"])
		if kind == "wonderkid" and grp == "GK":
			grp = "ATT"
		var poss := []
		for p in Data.POSITIONS:
			if Data.POS_GROUP[p] == grp:
				poss.append(p)
		var pos: String = pick(poss)
		var a := {"id": "a%d" % s.next_aid, "pos": pos, "kind": kind, "status": "open",
			"deadline": min(WEEKS, s.week + ri(8, 16)), "season": s.season}
		s.next_aid += 1
		match kind:
			"first11":
				a.max_age = ri(24, 29)
				a.min_ovr = int(avg) + 2
				a.max_value = int(minf(c.budget * 0.6, 120000.0 * exp((a.min_ovr + 6 - 50.0) / 7.5)))
			"prospect":
				a.max_age = ri(19, 21)
				a.min_ovr = int(avg) - 14
				a.max_value = int(minf(c.budget * 0.25, 900000))
			"wonderkid":
				a.max_age = 17
				a.min_ovr = int(avg) - 24
				a.max_value = int(minf(c.budget * 0.15, 400000))
			_:
				a.max_age = ri(26, 32)
				a.min_ovr = int(avg) - 4
				a.max_value = int(minf(c.budget * 0.2, 600000))
		a.max_value = max(100000, int(round(a.max_value / 50000.0) * 50000))
		s.assign.append(a)

func club_avg_ovr(cid: String) -> float:
	if is_lazy(cid):
		return club_level(cid)
	var xi := best_xi(cid)
	var t := 0.0
	for pid in xi:
		t += player(pid).ovr
	return t / max(1, xi.size())

func assignment_need_stars(a: Dictionary) -> float:
	var extra := 0.0
	if a.kind == "prospect":
		extra = 20.0
	elif a.kind == "wonderkid":
		extra = 34.0
	return stars(float(a.min_ovr) + extra)

func submit_report(pid: String, aid: String, cur: float, pot: float, rec: String, tags: Array = []) -> void:
	s.scout["season_reports"] = int(s.scout.get("season_reports", 0)) + 1
	var r := {"id": "r%d" % s.next_rid, "pid": pid, "aid": aid, "cur": cur, "pot": pot, "rec": rec,
		"season": s.season, "week": s.week, "status": "pending", "from_club": player(pid).club,
		"age0": int(player(pid).age), "lg0": club(player(pid).club).get("league", "SL"),
		"ovr0": player(pid).ovr, "evals": 0, "tags": tags}
	s.next_rid += 1
	s.scout.reports.append(r)
	log_discovery(pid, "report")
	s.scout.stats.reports += 1
	for a in s.assign:
		if a.id == aid and rec == "sign":
			a.status = "submitted"
	changed.emit()

func assignment(aid: String) -> Dictionary:
	for a in s.assign:
		if a.id == aid:
			return a
	return {}

func _decide_report(r: Dictionary) -> void:
	var p := player(r.pid)
	var a := assignment(r.aid)
	var me := my_club()
	if r.rec != "sign" or a.is_empty() or a.status == "done":
		r.status = "filed"
		return
	a.status = "open"
	if p.is_empty() or p.club == me.id:
		r.status = "rejected"
		add_news("n_rej_gone", [pname(p)])
		return
	if Data.POS_GROUP[p.pos] != Data.POS_GROUP[a.pos] or int(p.age) > int(a.max_age) + 1:
		r.status = "rejected"
		s.scout.rep = maxf(0.0, s.scout.rep - 1.5)
		add_news("n_rej_criteria", [pname(p)], true, "bad")
		return
	var fee := int(p.value * rng.randf_range(1.0, 1.35))
	if p.rival != "":
		fee = int(fee * 1.15)
	if fee > int(a.max_value) * 1.15 or fee > me.budget:
		r.status = "rejected"
		add_news("n_rej_budget", [pname(p), money_str(fee)], true, "bad")
		return
	var need_st := assignment_need_stars(a)
	var trust := 0.35 + float(s.scout.rep) / 140.0 + badge_trust(p, a)
	var claim: float = r.pot if a.kind in ["prospect", "wonderkid"] else r.cur
	if claim < need_st:
		trust -= 0.3
	# etiketler: doğruysa güven artar, yanlışsa düşer (kod biçimi "+attr" / "-attr")
	for tg in r.tags:
		var tgs := String(tg)
		var attr := tgs.substr(1)
		if not p.attrs.has(attr):
			continue
		var v := float(p.attrs[attr])
		var right: bool = (v >= 13.0) if tgs.begins_with("+") else (v <= 9.0)
		trust += 0.04 if right else -0.07
	var m: Dictionary = me.manager
	var fit := 0.0
	for at in Data.STYLE_ATTRS[m.style]:
		fit += float(p.attrs[at])
	fit /= 3.0
	# eşik sabit değil: kulübün kendi kadrosunun bu özelliklerdeki ortalamasının biraz altı
	var sq_fit := 0.0
	var sq_n := 0
	for spid in me.squad:
		var sp := player(spid)
		if sp.is_empty():
			continue
		for at2 in Data.STYLE_ATTRS[m.style]:
			sq_fit += float(sp.attrs[at2])
		sq_n += 3
	var fit_need := (sq_fit / float(sq_n) - 1.5) if sq_n > 0 else 9.5
	if a.kind != "wonderkid" and fit < fit_need and rf() < 0.6:
		r.status = "rejected"
		add_news("n_rej_manager", [m.name, pname(p)], true, "bad")
		return
	if m.pref == "young" and int(p.age) >= 28 and rf() < 0.5:
		r.status = "rejected"
		add_news("n_rej_manager_age", [m.name, pname(p)], true, "bad")
		return
	if a.get("urgent", false):
		trust += 0.1
	if r.pid in shadow_of(a.pos):
		trust += 0.08
	if board().get("favor", "") == r.pid:
		trust += 0.35
		board().favor = ""
	if rf() > trust:
		r.status = "rejected"
		add_news("n_rej_board", [pname(p)], true, "bad")
		return
	var seller := club(p.club)
	if seller.prestige > me.prestige + 12 and rf() < 0.75:
		r.status = "rejected"
		add_news("n_rej_seller", [seller.name, pname(p)], true, "bad")
		return
	var kn: Dictionary = s.scout.knowledge.get(r.pid, {})
	var refuse := 0.4 if not kn.get("met", false) else 0.12
	if float(p.hid.adaptability) < 6 and seller.city != me.city and rf() < refuse:
		r.status = "rejected"
		add_news("n_rej_player", [pname(p)], true, "bad")
		return
	r.fee = fee
	a.status = "done"
	r["ceremony"] = true
	if in_window():
		_transfer(r.pid, me.id, fee)
		r.status = "signed"
		add_news("n_signed", [pname(p), seller.name, money_str(fee)], true, "good")
	else:
		r.status = "agreed"
		s.pending.append({"pid": r.pid, "to": me.id, "fee": fee, "rid": r.id})
		add_news("n_agreed", [pname(p), seller.name, money_str(fee)], true, "good")
	s.scout.stats.signed += 1
	if a.get("urgent", false):
		s.scout.rep = minf(100.0, s.scout.rep + 1.5)
		add_news("n_urgent_done", [pname(p)], true, "good")
	area_gain(area_of_club(seller.id), 5.0)
	s.scout.money += 250
	s.scout.rep = minf(100.0, s.scout.rep + 1.0)

func _transfer(pid: String, to: String, fee: int) -> void:
	var p := player(pid)
	var from := club(p.club)
	var dest := club(to)
	if not from.is_empty():
		from.squad.erase(pid)
		from.u19.erase(pid)
		from.budget += fee
	dest.squad.append(pid)
	dest.budget = max(0, dest.budget - fee)
	p.club = to
	p.youth = false
	p.disc = true
	p.rival = ""
	p.contract = s.season + ri(3, 5)
	if dest.squad.size() > 32:
		_release_worst(to)
	if not from.is_empty() and from.squad.size() < 18:
		var ft := tier(from.league)
		from.squad.append(new_player(pick(Data.POSITIONS), clampi(int(tier_level(ft, float(from.prestige))) - ri(6, 14), 28, 60), 17 + ri(0, 2), nat_for_tier(ft), from.id))

func _release_worst(cid: String) -> void:
	var c := club(cid)
	var worst := ""
	var wv := 999
	for pid in c.squad:
		var p := player(pid)
		if int(p.age) > 22 and p.ovr < wv:
			wv = p.ovr
			worst = pid
	if worst != "":
		c.squad.erase(worst)
		s.players[worst].club = ""

func money_str(v) -> String:
	var f := float(v)
	if f >= 1000000.0:
		return "€%.1fM" % (f / 1000000.0)
	if f >= 1000.0:
		return "€%dK" % int(round(f / 1000.0))
	return "€%d" % int(f)

# ================================================================ maç simülasyonu

func best_xi(cid: String, noise := false, youth := false) -> Array:
	var c := club(cid)
	var groups := {"GK": [], "DEF": [], "MID": [], "ATT": []}
	var src: Array = c.u19 if youth else c.squad
	for pid in src:
		var p := player(pid)
		if p.is_empty() or int(p.inj) > 0:
			continue
		var score := float(p.ovr) + (rng.randfn(0.0, 3.0) if noise else 0.0)
		groups[Data.POS_GROUP[p.pos]].append([score, pid])
	var need := {"GK": 1, "DEF": 4, "MID": 3, "ATT": 3}
	var xi := []
	var spare := []
	for g in need:
		var arr: Array = groups[g]
		arr.sort_custom(func(x, y): return x[0] > y[0])
		for i in arr.size():
			if i < need[g]:
				xi.append(arr[i][1])
			else:
				spare.append(arr[i])
	# eksik mevki varsa yedeklerle tamamla
	spare.sort_custom(func(x, y): return x[0] > y[0])
	while xi.size() < 11 and not spare.is_empty():
		xi.append(spare.pop_front()[1])
	return xi

func _poisson(lam: float) -> int:
	if is_nan(lam) or lam <= 0.0:
		return 0
	lam = minf(lam, 30.0)
	var l := exp(-lam)
	var k := 0
	var p := 1.0
	while k < 200:
		p *= rf()
		if p <= l:
			break
		k += 1
	return k

func team_str(xi: Array, big: bool) -> float:
	var t := 0.0
	for pid in xi:
		var p := player(pid)
		t += float(p.ovr)
		if big:
			t += (float(p.hid.big_match) - 10.0) * 0.15
	return t / max(1, xi.size())

func _lazy_str(cid: String) -> float:
	return club_level(cid) + rng.randfn(0.0, 1.5)

func sim_match(m: Dictionary, lg: String, youth := false) -> void:
	if not youth and (is_lazy(m.h) or is_lazy(m.a)):
		# ayrıntısız kulüp: oyuncu istatistiği olmadan, kulüp seviyesinden skor
		var lh := _lazy_str(m.h) if is_lazy(m.h) else team_str(best_xi(m.h, true), false)
		var la := _lazy_str(m.a) if is_lazy(m.a) else team_str(best_xi(m.a, true), false)
		lh += 2.0
		m.gh = _poisson(1.3 * exp((lh - la) / 11.0))
		m.ga = _poisson(1.05 * exp((la - lh) / 11.0))
		m.ev = []
		_update_table(lg, m.h, m.a, m.gh, m.ga)
		return
	var hx := best_xi(m.h, true, youth)
	var ax := best_xi(m.a, true, youth)
	var big_h: bool = club(m.a).prestige >= 80 and not youth
	var big_a: bool = club(m.h).prestige >= 80 and not youth
	var sh := team_str(hx, big_h) + 2.0
	var sa := team_str(ax, big_a)
	var gh := _poisson(1.3 * exp((sh - sa) / 11.0))
	var ga := _poisson(1.05 * exp((sa - sh) / 11.0))
	m.gh = gh
	m.ga = ga
	m.xi_h = hx
	m.xi_a = ax
	var ev := []
	var goals := {}
	var assists := {}
	for side in [["h", hx, gh], ["a", ax, ga]]:
		for i in side[2]:
			var sc := _pick_scorer(side[1])
			var asst := _pick_assister(side[1], sc)
			goals[sc] = goals.get(sc, 0) + 1
			if asst != "":
				assists[asst] = assists.get(asst, 0) + 1
			ev.append({"t": "g", "pid": sc, "as": asst, "side": side[0], "min": ri(1, 90)})
	ev.sort_custom(func(x, y): return x.min < y.min)
	m.ev = ev
	var ratings := {}
	for side in [[hx, gh - ga, big_h], [ax, ga - gh, big_a]]:
		var xi: Array = side[0]
		var avg := 0.0
		for pid in xi:
			avg += player(pid).ovr
		avg /= max(1, xi.size())
		for pid in xi:
			var p := player(pid)
			var cons := float(p.hid.consistency)
			var r: float = 6.4 + (float(p.ovr) - avg) / 9.0 + clampf(float(side[1]), -3.0, 3.0) * 0.18
			r += rng.randfn(0.0, 0.95 - cons * 0.03)
			if side[2]:
				r += (float(p.hid.big_match) - 10.0) * 0.04
			r += goals.get(pid, 0) * 0.7 + assists.get(pid, 0) * 0.4
			r = clampf(r, 4.5, 9.8)
			ratings[pid] = snappedf(r, 0.1)
			if youth:
				continue
			p.st.apps += 1
			p.st.g += goals.get(pid, 0)
			p.st.a += assists.get(pid, 0)
			p.st.rs += r
			var ip := 0.004 + float(p.hid.injury_prone) * 0.0007
			if rf() < ip:
				p.inj = ri(1, 9)
				ev.append({"t": "inj", "pid": pid, "min": ri(1, 90), "side": "h" if pid in hx else "a"})
	m.rt = ratings
	if not youth:
		_update_table(lg, m.h, m.a, gh, ga)

func _pick_scorer(xi: Array) -> String:
	var tot := 0.0
	var ws := []
	for pid in xi:
		var p := player(pid)
		var gw: float = {"GK": 0.0, "DEF": 0.25, "MID": 0.9, "ATT": 2.6}[Data.POS_GROUP[p.pos]]
		var w: float = gw * pow(float(p.attrs.finishing) / 10.0, 2.0)
		ws.append(w)
		tot += w
	var r := rf() * tot
	for i in xi.size():
		r -= ws[i]
		if r <= 0:
			return xi[i]
	return xi[xi.size() - 1]

func _pick_assister(xi: Array, scorer: String) -> String:
	if rf() < 0.25:
		return ""
	var tot := 0.0
	var ws := []
	for pid in xi:
		var p := player(pid)
		var w := 0.0 if pid == scorer else pow((float(p.attrs.passing) + float(p.attrs.crossing) + float(p.attrs.vision)) / 30.0, 2.0) * (0.2 if p.pos == "GK" else 1.0)
		ws.append(w)
		tot += w
	var r := rf() * tot
	for i in xi.size():
		r -= ws[i]
		if r <= 0:
			return xi[i]
	return ""

func _update_table(lg: String, h: String, a: String, gh: int, ga: int) -> void:
	var th = s.table[lg][h]
	var ta = s.table[lg][a]
	th.p += 1
	ta.p += 1
	th.gf += gh
	th.ga += ga
	ta.gf += ga
	ta.ga += gh
	var rh := "D"
	var ra := "D"
	if gh > ga:
		th.w += 1
		th.pts += 3
		ta.l += 1
		rh = "W"
		ra = "L"
	elif gh < ga:
		ta.w += 1
		ta.pts += 3
		th.l += 1
		rh = "L"
		ra = "W"
	else:
		th.d += 1
		ta.d += 1
		th.pts += 1
		ta.pts += 1
	for pair in [[th, rh], [ta, ra]]:
		var f: Array = pair[0].get("form", [])
		f.append(pair[1])
		if f.size() > 5:
			f.pop_front()
		pair[0].form = f

# ================================================================ canlı izleme

func play_day(day: String) -> String:
	## O günün lig maçlarını oynatır; planlı maç varsa anahtarını döndürür.
	var planned: String = s.plan[day]
	for wm in week_matches():
		if wm.m.day == day and int(wm.m.gh) < 0 and match_key(wm.lg, wm.idx) != planned:
			sim_match(wm.m, wm.lg)
	return planned

func watch_match_data(key: String) -> Dictionary:
	## 3D izleyici için maç + zaman çizelgesi
	var m := get_match(key)
	ensure_squad(m.h)
	ensure_squad(m.a)
	_spend_travel(club(m.h).city)
	var eng = LiveEngine.new()
	eng.setup(self, m, false)
	return {"key": key, "m": m, "tl": eng.events, "youth": false, "eng": eng, "lg": key.split(":")[0]}

func watch_u19_data(idx: int) -> Dictionary:
	var fx: Dictionary = s.u19fx[idx]
	var m := {"h": fx.h, "a": fx.a, "day": "wed", "gh": -1, "ga": -1, "ev": []}
	_take_day("u19", fx.h, true)
	_spend_travel(club(fx.h).city)
	var eng = LiveEngine.new()
	eng.setup(self, m, true)
	return {"key": "u19:%d" % idx, "m": m, "tl": eng.events, "youth": true, "eng": eng, "lg": ""}

func finish_live(data: Dictionary) -> void:
	## Canlı motorun sonucunu fikstüre, puan tablosuna ve oyuncu istatistiklerine yaz
	var eng = data.eng
	if not eng.finished:
		eng.run_to_end()
	var m: Dictionary = data.m
	m.gh = eng.score[0]
	m.ga = eng.score[1]
	m.ev = eng.goal_events()
	m.rt = eng.ratings()
	data.tl = eng.events
	data.erase("eng")
	if data.youth:
		return
	var goals := {}
	var assists := {}
	for e in m.ev:
		goals[e.pid] = goals.get(e.pid, 0) + 1
		if e["as"] != "":
			assists[e["as"]] = assists.get(e["as"], 0) + 1
	for pid in m.xi_h + m.xi_a:
		var p := player(pid)
		if p.is_empty():
			continue
		p.st.apps += 1
		p.st.g += goals.get(pid, 0)
		p.st.a += assists.get(pid, 0)
		p.st.rs += float(m.rt.get(pid, 6.0))
	if data.lg != "":
		_update_table(data.lg, m.h, m.a, m.gh, m.ga)

func apply_watch(data: Dictionary, focus_events: Dictionary) -> Dictionary:
	## İzlenen olaylardan bilgi üret. focus_events: pid -> [olay indeksleri] (odakta izlenenler)
	var m: Dictionary = data.m
	var tl: Array = data.tl
	var youth: bool = data.youth
	var all: Array = m.xi_h + m.xi_a
	s.scout.stats.watched += 1
	area_gain(area_of_club(m.h), 1.2 if not youth else 0.9)
	# her oyuncu için olay istatistikleri
	var agg := Timeline.aggregate(self, tl, all)
	var obs := {"key": data.key, "h": m.h, "a": m.a, "gh": m.gh, "ga": m.ga, "youth": youth, "rt": m.get("rt", {}),
		"notes": {}, "lines": {}, "standouts": [], "rival": "", "new_disc": []}
	# rakip scout
	if rf() < 0.35:
		var cands := []
		for cid in s.clubs:
			if cid != s.scout.club_id and club(cid).prestige >= my_club().prestige - 5:
				var same: bool = league_country(club(cid).league) == league_country(club(m.h).league)
				if same or (tier(club(m.h).league) <= 2 and league_country(club(cid).league) != "BR"):
					cands.append(cid)
		if not cands.is_empty():
			obs.rival = pick(cands)
	var quality := 1.0
	for pid in all:
		var p := player(pid)
		if p.is_empty():
			continue
		var focused: bool = focus_events.has(pid) and focus_events[pid].size() > 0
		var watched_frac := 1.0
		if focused:
			var tot_ev: int = agg[pid].n_events
			watched_frac = clampf(float(focus_events[pid].size()) / maxf(1.0, float(tot_ev)), 0.0, 1.0)
		var w := (0.55 + 0.45 * watched_frac) if focused else 0.28
		_learn_from_agg(pid, agg[pid], w * quality)
		if youth and not p.disc:
			p.disc = true
			obs.new_disc.append(pid)
			s.scout.stats.disc += 1
			log_discovery(pid, "u19")
		if focused:
			var kn := know(pid)
			kn.seen += 1
			log_discovery(pid, "match")
			var notes := Timeline.notes_for(self, pid, agg[pid], m)
			if obs.rival != "" and _rival_cares(pid, obs.rival):
				p.rival = obs.rival
				notes.append(["nt_rival", [club(obs.rival).name]])
			var line := Timeline.stat_line(agg[pid])
			kn.notes.push_front({"season": s.season, "week": s.week, "vs": m.a if pid in m.xi_h else m.h,
				"r": m.rt.get(pid, 0.0), "n": notes, "line": line, "youth": youth})
			if kn.notes.size() > 8:
				kn.notes.resize(8)
			var sp: int = int(focus_events.get("_sparks", {}).get(pid, 0))
			if sp > 0:
				_learn_from_agg(pid, agg[pid], 0.2 * mini(sp, 3))
				var ht: String = ["big_match", "consistency"][sp % 2]
				kn.hid[ht] = {"lvl": hid_level(int(p.hid.get(ht, 10))), "src": "match"}
				notes.push_front(["nt_spark", [str(sp), T.t("q_" + ht)]])
			# Analist Gözü: dondurulmuş anlarda kararın kalitesi
			var eyes: Array = focus_events.get("_eye", {}).get(pid, [])
			if not eyes.is_empty():
				var ag2 := {"attr": {}}
				var goods := 0
				for e in eyes:
					if bool(e[0]):
						goods += 1
					if float(e[2]) > 0.004:
						Timeline._credit(ag2, [["decisions", float(e[1]), float(e[2])], ["vision", float(e[1]), float(e[2]) * 0.5]], bool(e[0]))
				if not ag2.attr.is_empty():
					_learn_from_agg(pid, ag2, 1.6)
				notes.push_front(["nt_eye", [str(goods), str(eyes.size())]])
			var hits: int = int(focus_events.get("_eye_hits", {}).get(pid, 0))
			if hits > 0:
				_learn_from_agg(pid, agg[pid], 0.12 * hits)
				_gain_xp("eye", 3 * hits)
				notes.append(["nt_eye_hit", [str(hits)]])
			obs.notes[pid] = notes
			obs.lines[pid] = line
			_gain_xp("eye", 2)
	# göze çarpanlar
	var ranked := all.duplicate()
	ranked.sort_custom(func(x, y): return m.rt.get(x, 0) > m.rt.get(y, 0))
	for pid in ranked.slice(0, 4):
		if not obs.notes.has(pid):
			obs.standouts.append(pid)
	s.last_obs.append(obs)
	changed.emit()
	return obs

func _rival_cares(pid: String, rival: String) -> bool:
	var p := player(pid)
	var avg := club_avg_ovr(rival)
	return p.ovr >= avg - 6 or (int(p.age) <= 19 and p.pa >= avg)

func prior_center(pid: String, a: String) -> float:
	## Öncül: kulübün bilinen seviyesi + mevkinin önemli özelliği mi
	var p := player(pid)
	var lvl := 50.0
	if p.club != "":
		lvl = 40.0 + float(club(p.club).prestige) * 0.3
	if p.get("youth", false):
		lvl -= 14.0
	var key: bool = Data.POS_WEIGHTS[p.pos].has(a)
	return clampf(lvl / 5.0 + (1.5 if key else -2.5), 3.0, 17.0)

func _learn_from_agg(pid: String, ag: Dictionary, weight: float) -> void:
	## İzlenen olaylardan Bayesçi özellik tahmini. Kanıt biriktikçe sis dağılır.
	var p := player(pid)
	var kn := know(pid)
	if not kn.has("ev"):
		kn.ev = {}
	var inv0 := 1.0 / 16.0
	var w := weight * 1.5 * eye_factor() * fatigue_factor() * area_learn_mult(pid)
	for a in ag.attr:
		var d: Dictionary = ag.attr[a]
		if not kn.ev.has(a):
			kn.ev[a] = [0.0, 0.0]
		kn.ev[a][0] = snappedf(float(kn.ev[a][0]) + float(d.num) * w, 0.00001)
		kn.ev[a][1] = snappedf(float(kn.ev[a][1]) + float(d.den) * w, 0.00001)
		var c0 := prior_center(pid, a)
		var post := (c0 * inv0 + float(kn.ev[a][0])) / (inv0 + float(kn.ev[a][1]))
		var sd := sqrt(1.0 / (inv0 + float(kn.ev[a][1])))
		var k_ev := clampf(1.0 - sd / 4.0, 0.0, 0.97)
		var err := clampf(post - float(p.attrs[a]), -8.0, 8.0)
		var k_old := float(kn.k[a])
		if k_ev > k_old:
			# olay kanıtı daha güçlü: tahmini ona göre güncelle
			kn.e[a] = snappedf((float(kn.e[a]) * k_old + err * k_ev) / maxf(0.001, k_old + k_ev), 0.01)
			kn.k[a] = snappedf(k_ev, 0.001)
		else:
			kn.e[a] = snappedf(lerpf(float(kn.e[a]), err, 0.25), 0.01)
	if int(p.age) <= 23:
		kn.pa_k = snappedf(minf(0.85, kn.pa_k + weight * 0.12 * eye_factor()), 0.001)
		kn.pa_e = snappedf(lerpf(float(kn.pa_e), rng.randfn(0.0, 4.0), weight * 0.25), 0.1)

func finish_week() -> Dictionary:
	var result := {"obs": s.last_obs}
	# hafta sonu oynanmamış maçları tamamla
	for wm in week_matches():
		if int(wm.m.gh) < 0:
			sim_match(wm.m, wm.lg)
	for pid in s.players:
		var p = s.players[pid]
		if p.inj > 0:
			p.inj -= 1
	for r in s.scout.reports:
		if r.status == "pending" and not (r.season == s.season and r.week == s.week):
			_decide_report(r)
	s.scout.money += s.scout.salary
	s.scout.fatigue = max(0, s.scout.fatigue - 22)
	s.cal = {}
	s.plan = {"sat": "", "sun": "", "focus_sat": [], "focus_sun": [], "travel_sat": "", "travel_sun": ""}
	_staff_week()
	s.week += 1
	_week_events()
	make_u19_fixtures()
	if s.week > WEEKS:
		result.season_end = true
		_season_end()
	s.last_obs = []
	save_game()
	changed.emit()
	return result

func end_week_auto() -> Dictionary:
	## Testler için: planlı maçları odak listesiyle otomatik izle
	for day in ["sat", "sun"]:
		var key := play_day(day)
		if key != "":
			var data := watch_match_data(key)
			finish_live(data)
			var fe := {}
			for pid in s.plan["focus_" + day]:
				fe[pid] = range(data.tl.size())
			apply_watch(data, fe)
	return finish_week()

func _week_events() -> void:
	if in_window():
		for t in s.pending.duplicate():
			var p := player(t.pid)
			if not p.is_empty():
				_transfer(t.pid, t.to, t.fee)
				add_news("n_joined", [pname(p), club(t.to).name], true, "good")
				for r in s.scout.reports:
					if r.id == t.rid:
						r.status = "signed"
			s.pending.erase(t)
		if s.week == WINDOWS[1][0] or s.week == 1:
			_ai_transfers()
	for a in s.assign:
		if a.status == "open" and s.week > int(a.deadline):
			a.status = "expired"
			s.scout.rep = maxf(0.0, s.scout.rep - 2.0)
			add_news("n_assign_expired", [a.pos], true, "bad")
	var open := 0
	for a in s.assign:
		if a.status in ["open", "submitted"]:
			open += 1
	if open < 2 and s.week <= WEEKS - 6 and s.week % 4 == 0 and _organic_open() == 0:
		make_assignments(1)
		add_news("n_new_assign", [], true, "career")
	if s.week == 12 or s.week == 24:
		_manager_sackings()
	if s.week % 3 == 0:
		_flavor_news()
	_organic_requests()
	_tips()

func _tips() -> void:
	## Bağlantılardan altyapı ihbarı
	var best_area := 0.0
	for ar in s.scout.get("arep", {}):
		best_area = maxf(best_area, float(s.scout.arep[ar]))
	var chance := 0.18 + float(s.scout.net) * 0.017 + best_area * 0.0015
	if rf() > chance:
		return
	var best := ""
	var bv := -1.0
	for i in 14:
		var cid: String = pick(s.clubs.keys())
		var u: Array = club(cid).u19
		if u.is_empty():
			continue
		var pid: String = pick(u)
		var p := player(pid)
		if p.disc:
			continue
		var v := float(p.pa) + rng.randfn(0.0, 14.0 - float(s.scout.net) * 0.5) + area_rep(area_of_club(cid)) * 0.12
		if v > bv:
			bv = v
			best = pid
	if best == "":
		return
	var p := player(best)
	p.disc = true
	var kn := know(best)
	kn.pa_k = 0.08
	s.scout.stats.tips += 1
	s.scout.stats.disc += 1
	log_discovery(best, "tip")
	add_news("n_tip", [club(p.club).name, T.t("pos_" + p.pos), int(p.age), pname(p)], true, "tip")

func _ai_transfers() -> void:
	var sl: Array = s.scout.shortlist
	var all_ids: Array = s.players.keys()
	var by_rival := {}
	for pid in all_ids:
		var rv: String = s.players[pid].get("rival", "")
		if rv != "":
			if not by_rival.has(rv):
				by_rival[rv] = []
			by_rival[rv].append(pid)
	for cid in s.clubs:
		if cid == s.scout.club_id or is_lazy(cid) or is_scout_club(cid):
			continue
		var c := club(cid)
		# önce scoutlarının ilgilendiği oyuncular
		for pid in by_rival.get(cid, []):
			var p := player(pid)
			if p.is_empty() or p.club == "" or p.club == s.scout.club_id or p.club == cid:
				continue
			var fee := int(p.value * rng.randf_range(1.0, 1.3))
			if fee <= c.budget and rf() < 0.6:
				var from_name: String = club(p.club).name
				_transfer(pid, cid, fee)
				if pid in sl or s.scout.knowledge.has(pid):
					add_news("n_rival_took", [c.name, pname(p), money_str(fee)], true, "bad")
					_museum_mark(pid, "rival", c.id)
		var n := ri(0, 2) if tier(c.league) <= 3 else ri(0, 1)
		var bcc := league_country(c.league)
		for i in n:
			var avg := club_avg_ovr(cid)
			var tries := 0
			while tries < 30:
				tries += 1
				var pid: String = pick(all_ids)
				var p := player(pid)
				if p.is_empty() or p.club == "" or p.club == cid or p.club == s.scout.club_id or p.youth:
					continue
				var from := club(p.club)
				if not _market_ok(c, from, p):
					continue
				if from.prestige >= c.prestige:
					continue
				if p.ovr < avg - 1 and not (int(p.age) <= 20 and p.pa > avg + 5 and league_country(from.league) == bcc):
					continue
				if p.value > c.budget:
					continue
				var fee := int(p.value * rng.randf_range(1.0, 1.3))
				_transfer(pid, cid, fee)
				if pid in sl:
					add_news("n_rival_took", [c.name, pname(p), money_str(fee)], true, "bad")
				elif fee >= 1500000 or bcc != league_country(from.league):
					add_news("n_ai_transfer", [c.name, pname(p), from.name, money_str(fee)], false, "transfer")
				break

func _market_ok(buyer: Dictionary, seller: Dictionary, p: Dictionary) -> bool:
	## Gerçekçi transfer pazarı: kulüpler çoğunlukla kendi ülkesinden ve üst liglerden alır
	var bcc := league_country(buyer.league)
	var scc := league_country(seller.league)
	if bcc == scc:
		# ülke içi: en fazla iki kademe aşağıdan
		return tier(seller.league) - tier(buyer.league) <= 2
	# ülkeler arası: satıcı mutlaka üst lig (TR'de Süper Lig/1. Lig) ve şans süzgeci
	if tier(seller.league) > 2:
		return false
	var chance: float = {"EN": 0.35, "IT": 0.3, "ES": 0.3, "DE": 0.3, "FR": 0.25, "TR": 0.25, "PT": 0.2, "NL": 0.2, "BR": 0.05}.get(bcc, 0.1)
	# Brezilya kulüpleri neredeyse yalnızca Güney Amerikalı oyuncu alır
	if bcc == "BR" and not (p.nat in ["BR", "AR", "UY"]):
		return false
	return rf() < chance

func _manager_sackings() -> void:
	for lg in LEAGUES:
		if not s.table.has(lg):
			continue
		var order := sorted_table(lg)
		var by_pres := order.duplicate()
		by_pres.sort_custom(func(a, b): return club(a).prestige > club(b).prestige)
		for i in order.size():
			var cid: String = order[i]
			var expected := by_pres.find(cid)
			if i - expected >= 6 and rf() < 0.55:
				var c := club(cid)
				var old: String = c.manager.name
				c.manager = new_manager()
				add_news("n_sacked", [c.name, old, c.manager.name], cid == s.scout.club_id, "club")

func _flavor_news() -> void:
	var best := ""
	var bv := 0.0
	for pid in s.players:
		var p = s.players[pid]
		if int(p.age) <= 21 and p.st.apps >= 3:
			var avg: float = p.st.rs / p.st.apps
			if avg > bv:
				bv = avg
				best = pid
	if best != "":
		var p := player(best)
		add_news("n_young_star", [pname(p), club(p.club).name if p.club != "" else "-", "%.2f" % bv], false, "press")


# ================================================================ ekip (alt scoutlar, analistler)

const STAFF_ROLES := ["scout", "video", "data"]
const STAFF_PERS := ["optimist", "pessimist", "balanced", "balanced", "lazy", "hungry"]
## Ekip bölgeleri: "home1" (kendi ülkenin üst ligleri), "home2" (alt ligler) ya da bir bölge (Data.ZONES)
func regions() -> Array:
	var out := ["home1"]
	if max_tier(my_country()) >= 3:
		out.append("home2")
	var mc := my_country()
	for z in Data.ZONES:
		if Data.ZONES[z] != [mc]:
			out.append(z)
	return out

func region_leagues(rg: String) -> Array:
	var mc := my_country()
	var out := []
	if rg == "home1" or rg == "home2":
		for t in range(1, max_tier(mc) + 1):
			if (rg == "home1" and t <= 2) or (rg == "home2" and t >= 3):
				out += tier_groups(mc, t)
		return out
	for cc in Data.ZONES.get(rg, []):
		if cc == mc:
			continue
		for t in [1, 2]:
			out += tier_groups(cc, t)
	return out

func region_langs(rg: String) -> Array:
	if rg == "home1" or rg == "home2":
		return [country_lang(my_country())]
	var out := []
	for cc in Data.ZONES.get(rg, []):
		var l := country_lang(cc)
		if not (l in out):
			out.append(l)
	return out

func region_abroad(rg: String) -> bool:
	return not (rg == "home1" or rg == "home2")

func staff_slots() -> int:
	var c := my_club()
	var n := 1 + int(float(s.scout.rep) / 20.0)
	if int(c.get("prestige", 0)) >= 60:
		n += 1
	return clampi(mini(n, int(board().slots)), 1, 6)

func staff_cost() -> int:
	var t := 0
	for m in s.get("staff", []):
		t += int(m.salary)
	return t

func _new_staff() -> Dictionary:
	var role: String = pick(["scout", "scout", "scout", "video", "data"])
	var mc := my_country()
	var nat: String = mc if rf() < 0.6 else pick(Data.COUNTRY_ORDER.slice(0, 20) + ["BR", "AR"])
	var nm := Data.name_pair(nat)
	var age := ri(24, 62)
	var eye := clampi(int(rng.randfn(10.0, 3.2) + (age - 40) * 0.06), 3, 19)
	var net := clampi(int(rng.randfn(9.0, 3.5)), 2, 19)
	var langs := [nat_lang(nat)]
	if nat != mc and rf() < 0.35 and not (country_lang(mc) in langs):
		langs.append(country_lang(mc))
	if rf() < 0.3 + float(eye) * 0.01:
		var extra: String = pick(["EN", "EN", "ES", "DE", "FR", "IT", "PT", "RU"])
		if not (extra in langs):
			langs.append(extra)
	var m := {
		"id": "s%d" % s.next_sid, "name": "%s %s" % [nm[0], nm[1]], "nat": nat, "age": age, "role": role,
		"eye": eye, "net": net, "langs": langs, "spec": pick(["youth", "first", "", ""]),
		"pers": pick(STAFF_PERS), "morale": ri(55, 85), "region": "", "reports": 0, "weeks": 0,
		"skin": ri(0, 4), "hair": ri(0, 5),
	}
	s.next_sid += 1
	m.salary = int(round((60.0 + eye * 9.0 + net * 4.0 + (30.0 if langs.size() > 1 else 0.0)) * rng.randf_range(0.85, 1.2) / 5.0) * 5.0)
	return m

func refresh_staff_pool(force := false) -> void:
	if not s.has("staff_pool"):
		s.staff_pool = []
	if not force and not s.staff_pool.is_empty() and s.week % 4 != 0:
		return
	s.staff_pool = []
	for i in 6:
		s.staff_pool.append(_new_staff())

func hire_staff(sid: String) -> String:
	if s.staff.size() >= staff_slots():
		return "staff_full"
	for m in s.staff_pool:
		if m.id == sid:
			s.staff_pool.erase(m)
			m.weeks = 0
			s.staff.append(m)
			add_news("n_staff_hired", [m.name, T.t("role_" + m.role)], true, "career")
			changed.emit()
			return "staff_hired"
	return "staff_gone"

func fire_staff(sid: String) -> void:
	for m in s.staff:
		if m.id == sid:
			s.staff.erase(m)
			s.scout.spent += int(m.salary) * 2
			add_news("n_staff_fired", [m.name], false, "career")
			break
	changed.emit()

func assign_staff(sid: String, region: String) -> void:
	if region_abroad(region) and not (region in board().abroad):
		return
	for m in s.staff:
		if m.id == sid:
			m.region = region
	changed.emit()

func raise_staff(sid: String) -> void:
	for m in s.staff:
		if m.id == sid:
			m.salary = int(round(float(m.salary) * 1.25 / 5.0) * 5.0)
			m.morale = mini(100, int(m.morale) + 25)
			m.erase("offer")
	changed.emit()

func staff_pers_known(m: Dictionary) -> bool:
	return int(m.get("reports", 0)) >= 6

func team_langs() -> Array:
	var out: Array = s.scout.get("langs", ["TR"]).duplicate()
	for m in s.get("staff", []):
		for l in m.langs:
			if not (l in out):
				out.append(l)
	return out

func _staff_week() -> void:
	if not s.has("staff"):
		s.staff = []
		s.staff_reports = []
		s.next_sid = 1
	refresh_staff_pool()
	for m in s.staff.duplicate():
		m.weeks = int(m.weeks) + 1
		s.scout.spent += int(m.salary)
		# rakip kulüp teklifi
		if m.has("offer"):
			if int(m.offer) <= s.week:
				s.staff.erase(m)
				add_news("n_staff_left", [m.name], true, "bad")
				continue
		elif int(m.eye) >= 13 and int(m.weeks) > 6 and rf() < 0.03 + (100 - int(m.morale)) * 0.0006:
			m.offer = s.week + 2
			add_news("n_staff_poach", [m.name], true, "bad")
		m.morale = clampi(int(m.morale) + (1 if m.region != "" else -2), 10, 100)
		match m.role:
			"scout":
				if m.region != "":
					_staff_scout(m)
			"video":
				for pid in s.scout.shortlist.slice(0, 3):
					var p := player(pid)
					if not p.is_empty() and not p.youth:
						observe(pid, 0.05 + float(m.eye) * 0.004, ["tec", "gk"], 1.2)
			"data":
				_staff_data(m)
	if s.staff_reports.size() > 80:
		s.staff_reports = s.staff_reports.slice(s.staff_reports.size() - 80)

func _staff_estimate(m: Dictionary, v: float) -> float:
	## Personelin yıldız tahmini: göz seviyesi gürültüsü + kişilik yanlılığı
	var noise := rng.randfn(0.0, (21.0 - float(m.eye)) / 14.0)
	var bias: float = {"optimist": 0.6, "pessimist": -0.5, "lazy": 0.0, "hungry": 0.15}.get(m.pers, 0.0)
	return clampf(round((stars(v) + noise * 0.6 + bias) * 2.0) / 2.0, 0.5, 5.0)

func _staff_scout(m: Dictionary) -> void:
	var lgs: Array = region_leagues(m.region)
	var cands := []
	for cid in s.clubs:
		if club(cid).league in lgs:
			cands.append(cid)
	if cands.is_empty():
		return
	var n := 2 if m.pers != "lazy" else 1
	if m.pers == "hungry":
		n = 3
	for i in n:
		var cid: String = pick(cands)
		ensure_squad(cid)
		var c := club(cid)
		var lang_ok: bool = country_lang(club_country(cid)) in m.langs
		var pool: Array = c.squad.duplicate()
		if m.spec == "youth" or rf() < 0.25:
			pool += c.u19
		if pool.is_empty():
			continue
		# en dikkat çekeni seç (göz iyiyse gerçekten iyi olanı bulur)
		var best := ""
		var bv := -999.0
		for k in 6:
			var pid: String = pick(pool)
			var p := player(pid)
			if p.is_empty():
				continue
			var val := float(p.pa if (m.spec == "youth" or int(p.age) <= 21) else p.ovr)
			val += rng.randfn(0.0, (22.0 - float(m.eye)) * 0.6)
			if val > bv:
				bv = val
				best = pid
		if best == "":
			continue
		var p := player(best)
		if p.youth:
			if not lang_ok and rf() < 0.5:
				continue
			p.disc = true
		observe(best, 0.04 + float(m.eye) * 0.005, ["tec", "phy", "men"], 1.4)
		var rep := {"sid": m.id, "pid": best, "season": s.season, "week": s.week,
			"cur": _staff_estimate(m, float(p.ovr)), "pot": _staff_estimate(m, float(p.pa)),
			"note": pick(["sr_note_1", "sr_note_2", "sr_note_3", "sr_note_4", "sr_note_5"])}
		rep.pot = maxf(rep.pot, rep.cur)
		s.staff_reports.append(rep)
		log_discovery(best, "staff", m.name)
		m.reports = int(m.reports) + 1
		if float(rep.pot) >= 4.0 or float(rep.cur) >= 4.0:
			add_news("n_staff_report", [m.name, pname(p), club(p.club).name, _fs2(rep.cur), _fs2(rep.pot)], true, "tip")

func _staff_data(m: Dictionary) -> void:
	## Veri analisti: istatistik avcılığı (bilinmeyen ama formda oyuncu)
	var best := ""
	var bv := 0.0
	for k in 60:
		var pid: String = pick(s.players.keys())
		var p := player(pid)
		if p.is_empty() or p.club == "" or p.club == s.scout.club_id or int(p.st.apps) < 3:
			continue
		if s.scout.knowledge.has(pid):
			continue
		var avg: float = float(p.st.rs) / float(p.st.apps)
		avg += rng.randfn(0.0, (20.0 - float(m.eye)) * 0.02)
		if avg > bv:
			bv = avg
			best = pid
	if best != "" and bv > 7.0:
		var p := player(best)
		know(best)
		m.reports = int(m.reports) + 1
		s.staff_reports.append({"sid": m.id, "pid": best, "season": s.season, "week": s.week,
			"cur": _staff_estimate(m, float(p.ovr)), "pot": _staff_estimate(m, float(p.pa)), "note": "sr_note_data"})
		add_news("n_staff_data", [m.name, pname(p), club(p.club).name, "%.2f" % bv], false, "tip")

static func _fs2(v: float) -> String:
	return str(int(v)) if v == floor(v) else "%.1f" % v

func learn_lang_cost(code: String) -> int:
	return 1400

func learn_lang(code: String) -> bool:
	var cost := learn_lang_cost(code)
	if s.scout.money < cost:
		return false
	if not s.scout.has("langs"):
		s.scout.langs = ["TR"]
	if code in s.scout.langs:
		return false
	s.scout.money -= cost
	s.scout.langs.append(code)
	add_news("n_lang", [T.t("lang_" + code)], true, "career")
	changed.emit()
	return true

func can_talk(pid: String) -> bool:
	## Yabancı oyuncu/kulüp ile iletişim: senin ya da ekibinin dili
	var p := player(pid)
	var cc := club_country(p.get("club", ""))
	return country_lang(cc) in team_langs()


# ================================================================ yönetim kurulu / başkan

const PRES_PERS := ["patient", "ambitious", "stingy", "showman"]

func board() -> Dictionary:
	if not s.has("board") or s.board.is_empty() or s.board.get("club", "") != s.scout.club_id:
		var c := my_club()
		var nat := league_country(c.get("league", "SL"))
		var bn := Data.name_pair(nat)
		s.board = {"club": s.scout.club_id, "name": "%s %s" % [bn[0], bn[1]],
			"pers": pick(PRES_PERS), "mood": 55, "abroad": [], "slots": 1, "last": -10, "asked": {},
			"skin": ri(0, 3), "hair": ri(0, 5), "favor": ""}
	return s.board

func board_can_meet() -> String:
	var b := board()
	if s.week < 1:
		return "meet_preseason"
	if s.week - int(b.last) < 3:
		return "meet_wait"
	if free_days() <= 0:
		return "no_wp"
	return ""

func board_abroad_ok(cc: String) -> bool:
	## Yurtdışı izni bölge bazında verilir (Data.ZONES)
	if cc == my_country():
		return true
	return Data.zone_of(cc) in board().abroad

func _board_chance(base: float) -> float:
	var b := board()
	var c := base + (float(b.mood) - 50.0) * 0.008 + float(s.scout.rep) * 0.006
	match b.pers:
		"stingy":
			c -= 0.12
		"ambitious":
			c += 0.05
		"patient":
			c += 0.03
	return clampf(c, 0.05, 0.95)

func board_request(topic: String, arg := "") -> Dictionary:
	## Başkana talep. Bir iş günü sürer. {ok, key, args}
	var why := board_can_meet()
	if why != "":
		return {"ok": false, "key": why, "args": []}
	var b := board()
	_take_day("board", "")
	b.last = s.week
	var asked: Dictionary = b.asked
	asked[topic] = int(asked.get(topic, 0)) + 1
	var nag := float(asked[topic] - 1) * 0.12
	var res := {"ok": false, "key": "", "args": []}
	match topic:
		"abroad":
			var cost: int = {"brit": 4500, "west": 4200, "central": 4000, "south": 4000, "sa": 6000, "east": 4500, "nordic": 4200}.get(arg, 3800)
			var p := _board_chance(0.35 + float(s.scout.stats.signed) * 0.06 - nag)
			if rf() < p:
				b.abroad.append(arg)
				s.scout.budget += cost
				b.mood = clampi(int(b.mood) - 3, 0, 100)
				res = {"ok": true, "key": "pres_abroad_yes", "args": [T.t("zone_" + arg), money_str(cost)]}
			else:
				b.mood = clampi(int(b.mood) - 4, 0, 100)
				res = {"ok": false, "key": "pres_abroad_no", "args": [T.t("zone_" + arg)]}
		"staff":
			var cap := 1 + int(float(s.scout.rep) / 20.0) + (1 if int(my_club().prestige) >= 60 else 0)
			if int(b.slots) >= mini(cap, 6):
				res = {"ok": false, "key": "pres_staff_rep", "args": []}
			else:
				var p := _board_chance(0.45 - nag)
				if rf() < p:
					b.slots = int(b.slots) + 1
					res = {"ok": true, "key": "pres_staff_yes", "args": [int(b.slots)]}
				else:
					b.mood = clampi(int(b.mood) - 4, 0, 100)
					res = {"ok": false, "key": "pres_staff_no", "args": []}
		"budget":
			var p := _board_chance(0.3 - nag + (0.15 if s.scout.spent < s.scout.budget * 0.6 else -0.1))
			if rf() < p:
				var add := int(round(float(s.scout.budget) * 0.25 / 100.0) * 100)
				s.scout.budget += add
				b.mood = clampi(int(b.mood) - 5, 0, 100)
				res = {"ok": true, "key": "pres_budget_yes", "args": [money_str(add)]}
			else:
				b.mood = clampi(int(b.mood) - 6, 0, 100)
				res = {"ok": false, "key": "pres_budget_no", "args": []}
		"raise":
			var p := _board_chance(0.15 + float(s.scout.rep) * 0.006 - nag)
			if rf() < p:
				var add2 := int(round(float(s.scout.salary) * 0.2 / 10.0) * 10)
				s.scout.salary += add2
				res = {"ok": true, "key": "pres_raise_yes", "args": [money_str(add2)]}
			else:
				b.mood = clampi(int(b.mood) - 8, 0, 100)
				res = {"ok": false, "key": "pres_raise_no", "args": []}
		"push":
			var pp := player(arg)
			var p := _board_chance(0.35 - nag)
			if not pp.is_empty() and rf() < p:
				b.favor = arg
				res = {"ok": true, "key": "pres_push_yes", "args": [pname(pp)]}
			else:
				b.mood = clampi(int(b.mood) - 5, 0, 100)
				res = {"ok": false, "key": "pres_push_no", "args": [pname(pp)]}
		"report":
			# sadece durum raporu: ilişkiyi güçlendirir
			var gain := 4 if s.scout.stats.signed > 0 else 2
			b.mood = clampi(int(b.mood) + gain, 0, 100)
			res = {"ok": true, "key": "pres_report", "args": []}
	changed.emit()
	return res

func board_mood_key() -> String:
	var m := int(board().mood)
	if m >= 70:
		return "mood_hi"
	if m >= 40:
		return "mood_mid"
	return "mood_lo"

# ================================================================ sezon sonu

func _season_end() -> void:
	var summ := {"season": s.season, "rep_before": s.scout.rep, "evals": [], "champ": "", "promoted": [], "relegated": [], "promoted_youth": []}
	var slo := sorted_table(top_league(my_country()))
	summ.champ = slo[0]
	summ.champs = {}
	for lg in LEAGUES:
		if s.table.has(lg):
			summ.champs[lg] = sorted_table(lg)[0]
	var my_lg: String = my_club().get("league", "")
	var moves := _promotions()
	summ.promoted = moves.up.get(2, [])
	summ.relegated = moves.down.get(1, [])
	summ.moves = moves
	add_news("n_champion", [club(slo[0]).name], true, "club")
	if my_lg != "" and my_lg != top_league(my_country()) and summ.champs.has(my_lg):
		add_news("n_champion_lg", [club(summ.champs[my_lg]).name, T.t("league_" + my_lg)], true, "club")
	for r in s.scout.reports:
		if r.status != "signed" or r.evals >= 3:
			continue
		var p := player(r.pid)
		if p.is_empty():
			continue
		var act_cur := stars(float(p.ovr))
		var act_pot := stars(float(p.pa))
		var score := 2.0 - absf(float(r.cur) - act_cur) * 1.5 - absf(float(r.pot) - act_pot) * 0.8 - maxf(0.0, float(r.pot) - act_pot) * 0.7
		if p.st.apps >= 8:
			var avg: float = p.st.rs / p.st.apps
			if avg >= 7.0:
				score += 1.5
			elif avg < 6.3:
				score -= 1.5
		elif int(p.age) > 19:
			score -= 0.5
		if int(p.ovr) - int(r.ovr0) >= 8:
			score += 2.0
			s.scout.stats.finds += 1
			add_news("n_your_find", [pname(p)], true, "good")
			area_gain(area_of_club(r.get("from_club", "")), 6.0)
		if int(r.evals) == 0:
			_rep_track(r, p, score, act_pot)
		var weight := 1.0 / (1.0 + float(r.evals))
		var delta: float = clampf(score * 1.6 * weight, -6.0, 8.0)
		s.scout.rep = clampf(s.scout.rep + delta, 0.0, 100.0)
		r.evals += 1
		summ.evals.append({"pid": r.pid, "cur": r.cur, "pot": r.pot, "act_cur": act_cur, "act_pot": act_pot, "delta": delta,
			"apps": p.st.apps, "avg": (p.st.rs / p.st.apps) if p.st.apps > 0 else 0.0})
	# imzalanmayan raporların da isabeti sayılır (yarım ağırlık, tek sefer)
	for r in s.scout.reports:
		if r.status == "signed" or int(r.get("evals", 0)) > 0:
			continue
		var rp := player(r.pid)
		if rp.is_empty():
			continue
		var sc2 := 1.0 - absf(float(r.cur) - stars(float(rp.ovr))) * 1.0 - maxf(0.0, float(r.pot) - stars(float(rp.pa))) * 0.8
		s.scout.rep = clampf(s.scout.rep + clampf(sc2 * 0.6, -2.0, 2.0), 0.0, 100.0)
		_rep_track(r, rp, sc2, stars(float(rp.pa)))
		r.evals = 3
	_check_badges()
	if s.scout.spent > s.scout.budget:
		var over := float(s.scout.spent - s.scout.budget) / maxf(1.0, float(s.scout.budget))
		s.scout.rep = maxf(0.0, s.scout.rep - minf(over * 8.0, 5.0))
		summ.over_budget = true
	summ.rep_after = s.scout.rep
	var bd := board()
	bd.mood = clampi(int(bd.mood) + int(clampf((float(s.scout.rep) - float(summ.rep_before)) * 2.0, -20.0, 20.0)), 0, 100)
	bd.asked = {}
	# gelişim, yaş, emeklilik
	for pid in s.players.keys():
		var p = s.players[pid]
		if not p.youth:
			var avg: float = (p.st.rs / p.st.apps) if p.st.apps > 0 else 0.0
			p.hist.append({"season": s.season, "club": club(p.club).short if p.club != "" else "-", "apps": p.st.apps, "g": p.st.g, "a": p.st.a, "avg": snappedf(avg, 0.01)})
		_develop(p)
		p.st = {"apps": 0, "g": 0, "a": 0, "rs": 0.0}
		p.age += 1
		p.rival = ""
		var gone: bool = int(p.age) >= 36 or (int(p.age) >= 33 and p.ovr < 50 and rf() < 0.5) or p.club == ""
		if gone and not (pid in s.scout.shortlist):
			if p.club != "":
				club(p.club).squad.erase(pid)
			if not _is_tracked(pid):
				s.players.erase(pid)
				s.scout.knowledge.erase(pid)
	_museum_check(summ)
	# altyapı: yükselme ve yeni alımlar
	for cid in s.clubs:
		var c := club(cid)
		if is_lazy(cid):
			continue
		var avg := club_avg_ovr(cid)
		for pid in c.u19.duplicate():
			var p := player(pid)
			if p.is_empty():
				c.u19.erase(pid)
				continue
			if int(p.age) >= 19:
				c.u19.erase(pid)
				if p.ovr >= avg - 16 or p.pa >= avg + 4:
					p.youth = false
					p.disc = true
					c.squad.append(pid)
					if s.scout.knowledge.has(pid):
						summ.promoted_youth.append(pid)
				elif not _is_tracked(pid) and not (pid in s.scout.shortlist):
					s.players.erase(pid)
					s.scout.knowledge.erase(pid)
				else:
					p.club = ""
		if has_u19(cid):
			gen_u19(cid, ri(3, 5) if tier(c.league) <= 2 else ri(2, 3), [15, 15])
		while c.squad.size() > 32:
			_release_worst(cid)
		fill_squad(cid)
		c.budget = int(c.budget * 0.6 + 300000.0 * exp(float(c.prestige) / 20.0))
	# iş teklifleri
	s.offers = []
	var mine := my_club()
	for cid in s.clubs:
		var c := club(cid)
		if cid == mine.id or is_scout_club(cid):
			continue
		# yurtdışı teklif nadir: o bölgede ağın (itibarın) varsa artar
		var home_c := club_country(cid) == club_country(mine.id)
		var ar := area_rep(area_of_club(cid))
		var chance := 0.35 + ar * 0.003 if home_c else 0.0006 + ar * 0.002
		if s.scout.rep >= 10.0 and c.prestige > mine.prestige and c.prestige <= s.scout.rep + 35 + ar * 0.15 and rf() < chance:
			s.offers.append(cid)
	s.offers.shuffle()
	s.offers.sort_custom(func(a, b): return int(club_country(a) == club_country(mine.id)) > int(club_country(b) == club_country(mine.id)))
	s.offers = s.offers.slice(0, 3)
	var rep_start: float = float(s.scout.get("rep_start", summ.rep_before))
	var lazy: bool = int(s.scout.get("season_reports", 0)) == 0
	summ.fired = (s.scout.rep < float(mine.prestige) * 0.15 and s.scout.rep < rep_start - 4) or (lazy and rf() < 0.6)
	if summ.fired:
		add_news("n_fired", [mine.name], true, "bad")
		if s.offers.is_empty():
			for cid in s.clubs:
				if cid != mine.id and club(cid).prestige <= mine.prestige - 3 and club_country(cid) == club_country(mine.id):
					s.offers.append(cid)
			s.offers.shuffle()
			s.offers = s.offers.slice(0, 3)
	s.scout["rep_start"] = s.scout.rep
	for ar in s.scout.arep:
		s.scout.arep[ar] = snappedf(float(s.scout.arep[ar]) * 0.88, 0.01)
	s.scout["season_reports"] = 0
	s.scout["pocket"] = 0
	s.season_summary = summ
	s.scout.history.append({"season": s.season, "club": mine.short, "rep": snappedf(s.scout.rep, 0.1)})
	s.season += 1
	s.week = 0
	s.scout.spent = 0
	s.assign = []
	_prune_world()
	make_fixtures()
	make_u19_fixtures()
	if not summ.fired:
		make_assignments(3)

func _promotions() -> Dictionary:
	## Her ülkede kademeler arası yükselme/düşme. Dönüş: {cc, up{t: [..]}, down{t: [..]}, by{cc: {up, down}}}
	## up[t] = t kademesinden yükselenler, down[t] = t'den düşenler (oyuncunun ülkesi için)
	var by := {}
	for cc in Data.COUNTRIES:
		var mt := max_tier(cc)
		if mt < 2:
			continue
		var up := {}
		var down := {}
		for t in range(1, mt):
			var upper: Array = tier_groups(cc, t)
			var lower: Array = tier_groups(cc, t + 1)
			if upper.is_empty() or lower.is_empty() or not s.table.has(upper[0]):
				continue
			var usz: int = s.table[upper[0]].size()
			var n_move := 3 if usz >= 16 else (2 if usz >= 12 else 1)
			var o := sorted_table(upper[0])
			down[t] = o.slice(o.size() - n_move)
			var ups := []
			var seconds := []
			var per := maxi(1, n_move / lower.size())
			for lg in lower:
				if not s.table.has(lg):
					continue
				var lo := sorted_table(lg)
				ups += lo.slice(0, per)
				if lo.size() > per:
					seconds.append(lo[per])
			seconds.sort_custom(func(x, y): return _tb_better(x, y))
			while ups.size() < n_move and not seconds.is_empty():
				ups.append(seconds.pop_front())
			up[t + 1] = ups.slice(0, n_move)
		for t in up:
			for cid in up[t]:
				s.clubs[cid].league = tier_groups(cc, t - 1)[0]
				_promotion_boost(cid, t - 1)
		for t in down:
			for cid in down[t]:
				s.clubs[cid].league = tier_groups(cc, t + 1)[0]
				s.clubs[cid].prestige = maxi(3, int(s.clubs[cid].prestige) - 2)
		if cc == "TR":
			_regroup(3, tier_clubs(3, "TR"))
		by[cc] = {"up": up, "down": down}
	# altyapı: kademe değişince akademi aç/kapat
	for cid in s.clubs:
		var c := club(cid)
		if is_lazy(cid):
			continue
		if has_u19(cid) and c.u19.is_empty():
			gen_u19(cid, 8)
		elif not has_u19(cid) and not c.u19.is_empty():
			for pid in c.u19.duplicate():
				if not _is_tracked(pid) and not (pid in s.scout.shortlist):
					s.players.erase(pid)
					s.scout.knowledge.erase(pid)
				else:
					s.players[pid].club = ""
			c.u19 = []
	var mc := my_country()
	var mine: Dictionary = by.get(mc, {"up": {}, "down": {}})
	return {"cc": mc, "up": mine.up, "down": mine.down, "by": by}

func tier_name(cc: String, t: int) -> String:
	if cc == "TR":
		return T.t("tier_%d" % t)
	var g := tier_groups(cc, t)
	return T.t("league_" + g[0]) if not g.is_empty() else "-"

func top_league(cc: String) -> String:
	var g := tier_groups(cc, 1)
	return g[0] if not g.is_empty() else "SL"

func _promotion_boost(cid: String, new_tier: int) -> void:
	## Yükselen kulüp: prestij artar, yeni seviyeye uygun birkaç takviye yapar
	var c := club(cid)
	c.prestige = int(c.prestige) + 3
	c.budget = int(c.budget) + int(250000.0 * exp(float(c.prestige) / 25.0))
	if is_lazy(cid):
		return
	var lvl := club_level(cid)
	for i in 4:
		var pos: String = pick(["CB", "CM", "ST", "LW", "RW", "DM", "GK", "LB", "RB", "AM"])
		c.squad.append(new_player(pos, clampi(int(lvl + rng.randfn(-2.0, 3.0)), 30, 85), ri(23, 30), club_nat(cid), cid))
	while c.squad.size() > 30:
		_release_worst(cid)

func _prune_world() -> void:
	## Hafıza/kayıt boyutu: kendi ülken dışındaki, takip etmediğin kulüplerin kadrolarını tekrar "ayrıntısız" yap
	var keep_cc := my_country()
	var keep := {}
	for pid in s.scout.shortlist:
		keep[player(pid).get("club", "")] = true
	for pid in s.scout.knowledge:
		keep[player(pid).get("club", "")] = true
	for r in s.scout.reports:
		keep[player(r.pid).get("club", "")] = true
	for r in s.get("staff_reports", []):
		keep[player(r.pid).get("club", "")] = true
	var n := 0
	for cid in s.clubs:
		var c := club(cid)
		if is_lazy(cid) or club_country(cid) == keep_cc or keep.has(cid):
			continue
		for pid in c.squad + c.u19:
			if not _is_tracked(pid):
				s.players.erase(pid)
		c.squad = []
		c.u19 = []
		c["lazy"] = true
		n += 1
	if n > 0:
		print("[BC] budandı: ", n, " kulüp")

func _tb_better(a: String, b: String) -> bool:
	var ta = s.table[club_league_at_end(a)][a]
	var tb = s.table[club_league_at_end(b)][b]
	var pa := float(ta.pts) / maxf(1.0, float(ta.p))
	var pb := float(tb.pts) / maxf(1.0, float(tb.p))
	if absf(pa - pb) > 0.001:
		return pa > pb
	return (ta.gf - ta.ga) > (tb.gf - tb.ga)

func club_league_at_end(cid: String) -> String:
	for lg in s.table:
		if s.table[lg].has(cid):
			return lg
	return club(cid).league

func _is_tracked(pid: String) -> bool:
	if s.players.has(pid) and s.players[pid].get("keep", false):
		return true
	for r in s.scout.reports:
		if r.pid == pid:
			return true
	return false

func _develop(p: Dictionary) -> void:
	var age := int(p.age)
	var prof := float(p.hid.professionalism)
	var mins := clampf(float(p.st.apps) / 20.0, 0.2, 1.2)
	if p.youth:
		mins = 0.8
	var delta := 0.0
	if age <= 23:
		var room := float(p.pa) - float(p.ovr)
		delta = room * rng.randf_range(0.12, 0.38) * (0.6 + prof / 25.0) * (0.7 + mins * 0.4)
		if rf() < 0.08:
			delta *= 0.2
	elif age <= 28:
		delta = rng.randf_range(-1.0, 2.0) * (0.6 + prof / 25.0)
		delta = minf(delta, float(p.pa) - float(p.ovr))
	elif age <= 31:
		delta = rng.randf_range(-2.5, 0.5)
	else:
		delta = rng.randf_range(-5.0, -1.0)
	if absf(delta) < 0.3:
		return
	var w: Dictionary = Data.POS_WEIGHTS[p.pos]
	for a in Data.ATTRS:
		var g: String = Data.ATTR_GROUP[a]
		var f := 1.0 if w.has(a) else 0.5
		if delta < 0 and g == "phy":
			f *= 1.6
		if delta > 0 and g == "men" and age >= 22:
			f *= 1.3
		p.attrs[a] = clampi20(float(p.attrs[a]) + delta / 5.0 * f * rng.randf_range(0.5, 1.5))
	p.ovr = calc_ovr(p)
	p.pa = max(p.pa, p.ovr)
	p.value = calc_value(p)

func accept_offer(cid: String) -> void:
	take_job(cid)
	s.offers = []
	s.season_summary = {}
	save_game()

func dismiss_summary() -> void:
	s.season_summary = {}
	s.offers = []
	if s.scout.club_id != "" and s.assign.is_empty():
		make_assignments(3)
	save_game()

# ================================================================ arama

func search(filters: Dictionary) -> Array:
	var out := []
	for pid in s.players:
		var p = s.players[pid]
		if p.club == "" or p.club == s.scout.club_id:
			continue
		if not visible(p):
			continue
		if filters.get("youth_only", false) and not p.youth:
			continue
		if filters.get("lg", "") != "" and club(p.club).league != filters.lg:
			continue
		if filters.get("country", "") != "" and league_country(club(p.club).league) != filters.country:
			continue
		if int(filters.get("tier", 0)) > 0 and tier(club(p.club).league) != int(filters.tier):
			continue
		if filters.get("grp", "") != "" and Data.POS_GROUP[p.pos] != filters.grp:
			continue
		if int(p.age) > int(filters.get("max_age", 99)):
			continue
		if filters.get("known", false) and known_fraction(pid) < 0.05:
			continue
		out.append(pid)
	var sort: String = filters.get("sort", "rating")
	var keyed := []
	for pid in out:
		keyed.append([_sort_key(pid, sort), pid])
	keyed.sort_custom(func(x, y): return x[0] > y[0])
	out = []
	for k in keyed:
		out.append(k[1])
	return out.slice(0, 80)

func _sort_key(pid: String, sort: String) -> float:
	var p: Dictionary = s.players[pid]
	if sort == "age":
		return -float(p.age)
	if sort == "value":
		return float(p.value)
	if sort == "known":
		return known_fraction(pid)
	return (float(p.st.rs) + 6.6 * 4.0) / (float(p.st.apps) + 4.0)

func avg_rating(p: Dictionary) -> float:
	return (p.st.rs / p.st.apps) if p.st.apps > 0 else 0.0

func discovered_youth() -> Array:
	var out := []
	for pid in s.players:
		var p = s.players[pid]
		if p.youth and p.disc:
			out.append(pid)
	return out

# ================================================================ kayıt

func save_game() -> void:
	## Oyuncu özellikleri dizi olarak yazılır (dosya ~yarı boyut)
	var t0 := Time.get_ticks_msec()
	var packed := {}
	for pid in s.players:
		var p: Dictionary = s.players[pid]
		var q := p.duplicate(false)
		var aa := []
		for a in Data.ATTRS:
			aa.append(int(p.attrs[a]))
		var hh := []
		for h in Data.HIDDEN:
			hh.append(int(p.hid[h]))
		q.attrs = aa
		q.hid = hh
		packed[pid] = q
	var real_players: Dictionary = s.players
	s.players = packed
	var txt := JSON.stringify(s)
	s.players = real_players
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(txt)
		f.close()
	print("[BC] kayit ms ", Time.get_ticks_msec() - t0, " boyut ", txt.length())

# ================================================================ organik talepler + gölge kadro (v0.15)

const SHADOW_SLOTS := ["GK", "LB", "CB", "RB", "DM", "CM", "AM", "LW", "ST", "RW"]

func shadow_of(pos: String) -> Array:
	return s.scout.get("shadow", {}).get(pos, [])

func shadow_add(pid: String, pos: String) -> bool:
	if not s.scout.has("shadow"):
		s.scout["shadow"] = {}
	var arr: Array = s.scout.shadow.get(pos, [])
	if pid in arr:
		return true
	if arr.size() >= 3:
		return false
	arr.append(pid)
	s.scout.shadow[pos] = arr
	if not (pid in s.scout.shortlist):
		s.scout.shortlist.append(pid)
	changed.emit()
	return true

func shadow_remove(pid: String) -> void:
	for pos in s.scout.get("shadow", {}):
		s.scout.shadow[pos].erase(pid)
	changed.emit()

func shadow_slot_of(pid: String) -> String:
	for pos in s.scout.get("shadow", {}):
		if pid in s.scout.shadow[pos]:
			return pos
	return ""

func shadow_move(pid: String, dir: int) -> void:
	var pos := shadow_slot_of(pid)
	if pos == "":
		return
	var arr: Array = s.scout.shadow[pos]
	var i := arr.find(pid)
	var j := clampi(i + dir, 0, arr.size() - 1)
	if i != j:
		arr[i] = arr[j]
		arr[j] = pid
	changed.emit()

func starter_at(pos: String) -> String:
	## Kulübümüzde o mevkideki en iyi oyuncu
	var best := ""
	var bv := -1
	for pid in my_club().get("squad", []):
		var p := player(pid)
		if not p.is_empty() and p.pos == pos and int(p.ovr) > bv:
			bv = int(p.ovr)
			best = pid
	return best

func _organic_open() -> int:
	var n := 0
	for a in s.assign:
		if a.status in ["open", "submitted"] and a.has("why"):
			n += 1
	return n

func _has_req(why: String, ref: String) -> bool:
	for a in s.assign:
		if a.get("why", "") == why and a.get("ref", "") == ref and a.get("season", 0) == s.season:
			return true
	return false

func _organic_assign(kind: String, pos: String, why: String, ref: String, urgent: bool, weeks: int) -> Dictionary:
	var c := my_club()
	var avg := club_avg_ovr(c.id)
	var a := {"id": "a%d" % s.next_aid, "pos": pos, "kind": kind, "status": "open",
		"deadline": min(WEEKS, s.week + weeks), "season": s.season, "why": why, "ref": ref, "urgent": urgent}
	s.next_aid += 1
	match kind:
		"first11":
			a.max_age = 31 if urgent else ri(24, 29)
			a.min_ovr = int(avg) + (0 if urgent else 2)
			a.max_value = int(minf(c.budget * (0.7 if urgent else 0.6), 120000.0 * exp((a.min_ovr + 6 - 50.0) / 7.5)))
		"prospect":
			a.max_age = ri(19, 21)
			a.min_ovr = int(avg) - 14
			a.max_value = int(minf(c.budget * 0.25, 900000))
		_:
			a.max_age = ri(26, 32)
			a.min_ovr = int(avg) - 4
			a.max_value = int(minf(c.budget * 0.2, 600000))
	a.max_value = max(100000, int(round(a.max_value / 50000.0) * 50000))
	s.assign.append(a)
	var ready := shadow_of(pos).size()
	if ready > 0:
		add_news("n_req_ready", [T.t("pos_" + pos), ready], true, "career")
	return a

func _organic_requests() -> void:
	## Kulübün gerçek durumundan doğan talepler: sakatlık, satış, yaşlanma, hoca isteği, zayıf halka
	if s.scout.club_id == "" or s.week > WEEKS - 5 or _organic_open() >= 3:
		return
	var me := my_club()
	var xi := best_xi(me.id)
	# 1) uzun süreli sakatlık (sakatlar best_xi'de olmaz: kadroda en iyi oyunculara bak)
	var top := []
	for pid in me.squad:
		var p := player(pid)
		if not p.is_empty():
			top.append([int(p.ovr), pid])
	top.sort_custom(func(x, y): return x[0] > y[0])
	for row in top.slice(0, 13):
		var p := player(row[1])
		if int(p.inj) >= 5 and not _has_req("inj", row[1]):
			_organic_assign("first11", p.pos, "inj", row[1], true, 6)
			add_news("n_req_inj", [pname(p), int(p.inj), T.t("pos_" + p.pos)], true, "career")
			return
	# 2) büyük kulüp ilk 11'den oyuncu kapar (transfer dönemi)
	if in_window() and rf() < 0.12 and not xi.is_empty():
		var pid: String = pick(xi)
		var p := player(pid)
		var buyers := []
		for cid in s.clubs:
			var c := club(cid)
			if cid != me.id and int(c.prestige) > int(me.prestige) + 6 and league_country(c.league) == league_country(me.league):
				buyers.append(cid)
		if not buyers.is_empty() and not p.is_empty() and p.pos != "GK":
			var bc: String = pick(buyers)
			var fee := int(p.value * rng.randf_range(1.2, 1.6))
			_transfer(pid, bc, fee)
			add_news("n_req_sold", [club(bc).name, pname(p), money_str(fee)], true, "career")
			_organic_assign("first11", p.pos, "sold", pid, true, 7)
			return
	# 3) yaşlanan as: halef
	if s.week in [9, 21]:
		var old := ""
		var oa := 0
		for pid in xi:
			var p := player(pid)
			if int(p.age) >= 31 and int(p.age) > oa:
				oa = int(p.age)
				old = pid
		if old != "" and not _has_req("succ", old):
			var p := player(old)
			_organic_assign("prospect", p.pos, "succ", old, false, 12)
			add_news("n_req_succ", [pname(p), oa], true, "career")
			return
	# 4) hocanın oyun planı
	if s.week == 5 and not _has_req("style", me.manager.name):
		var grp: String = {"attack": "ATT", "counter": "ATT", "press": "MID", "possession": "MID", "defend": "DEF"}[me.manager.style]
		var poss := []
		for ps in Data.POSITIONS:
			if Data.POS_GROUP[ps] == grp:
				poss.append(ps)
		var pos: String = pick(poss)
		_organic_assign("first11", pos, "style", me.manager.name, false, 12)
		add_news("n_req_style", [me.manager.name, T.t("style_" + me.manager.style), T.t("pos_" + pos)], true, "career")
		return
	# 5) zayıf halka
	if s.week == 14 and not _has_req("weak", str(s.season)):
		var worst := ""
		var wv := 999.0
		for pid in xi:
			var p := player(pid)
			if p.is_empty():
				continue
			if float(p.ovr) < wv:
				wv = float(p.ovr)
				worst = pid
		if worst != "":
			var p := player(worst)
			_organic_assign("first11", p.pos, "weak", str(s.season), false, 10)
			add_news("n_req_weak", [T.t("pos_" + p.pos), pname(p)], true, "career")

# ================================================================ keşif tarihçesi + Kaçanlar Müzesi (v0.15)

func log_discovery(pid: String, how: String, by := "") -> void:
	if not s.scout.has("disc_log"):
		return
	for d in s.scout.disc_log:
		if d.pid == pid:
			return
	var p := player(pid)
	if p.is_empty():
		return
	s.scout.disc_log.append({"pid": pid, "season": s.season, "week": s.week, "how": how, "by": by,
		"club": p.club, "age": int(p.age), "ovr": int(p.ovr), "lg": club(p.club).get("league", "")})
	if s.scout.disc_log.size() > 400:
		s.scout.disc_log.pop_front()

func discovery(pid: String) -> Dictionary:
	for d in s.scout.get("disc_log", []):
		if d.pid == pid:
			return d
	return {}

func _museum_has(pid: String) -> bool:
	for e in s.get("museum", []):
		if e.pid == pid:
			return true
	return false

func _museum_mark(pid: String, why: String, to := "") -> void:
	## Rakibin elinden kaçırdığın oyuncu: hemen değil, yıldızlaşırsa müzeye girer
	var d := discovery(pid)
	if d.is_empty():
		log_discovery(pid, "match")
		d = discovery(pid)
	if not d.is_empty():
		d["lost"] = why
		d["lost_to"] = to

func _signed_by_me(pid: String) -> bool:
	for r in s.scout.reports:
		if r.pid == pid and r.status in ["signed", "agreed"]:
			return true
	return false

func _museum_check(summ: Dictionary) -> void:
	## Sezon sonu: gördüğün ama almadığın oyunculardan yıldızlaşanlar müzeye (sezon başına en çarpıcı 3)
	if not s.has("museum"):
		return
	summ["museum"] = []
	var me := my_club()
	var bar := club_avg_ovr(me.id) + 4.0
	var cands := []
	for d in s.scout.get("disc_log", []):
		var pid: String = d.pid
		if _museum_has(pid) or _signed_by_me(pid):
			continue
		var p := player(pid)
		if p.is_empty() or p.club == me.id or p.club == "":
			continue
		var grew := int(p.ovr) - int(d.ovr)
		if int(p.ovr) >= bar and grew >= 8 and int(s.season) > int(d.season):
			cands.append([grew + int(p.ovr) - bar, d])
	cands.sort_custom(func(x, y): return x[0] > y[0])
	for row in cands.slice(0, 3):
		var d: Dictionary = row[1]
		var pid: String = d.pid
		var p := player(pid)
		var why: String = d.get("lost", "")
		if why == "":
			why = "never"
			for r in s.scout.reports:
				if r.pid == pid:
					why = "rejected" if r.status == "rejected" else ("passed" if r.rec != "sign" else "never")
		var e := {"pid": pid, "name": pname(p), "pos": p.pos, "seen_season": d.season, "seen_age": d.age, "ovr0": d.ovr,
			"ovr": int(p.ovr), "club": p.club, "why": why, "season": s.season, "value": int(p.value), "how": d.how}
		s.museum.append(e)
		summ.museum.append(pid)
		add_news("n_museum", [pname(p), club(p.club).name, int(d.season)], true, "bad")
	# kaydedilen oyuncular silinmesin
	for e in s.museum:
		if s.players.has(e.pid):
			s.players[e.pid]["keep"] = true

# ================================================================ itibar (v0.15)

var AREAS: Array = ["tr", "brit", "west", "central", "south", "balkan", "nordic", "east", "sa"]
const BADGES := {
	"spec_GK": ["spec", "GK", 5.0], "spec_DEF": ["spec", "DEF", 6.0], "spec_MID": ["spec", "MID", 6.0], "spec_ATT": ["spec", "ATT", 6.0],
	"spec_youth": ["spec", "youth", 5.0], "spec_gem": ["spec", "gem", 5.0],
}

func area_of_club(cid: String) -> String:
	if cid == "" or not s.clubs.has(cid):
		return ""
	return Data.zone_of(club_country(cid))

func area_of_player(pid: String) -> String:
	var p := player(pid)
	return area_of_club(p.get("club", "")) if not p.is_empty() else ""

func area_rep(area: String) -> float:
	return float(s.scout.get("arep", {}).get(area, 0.0))

func area_gain(area: String, amt: float) -> void:
	## Bölge ağı: azalan getiri, 0-100
	if area == "" or not s.scout.has("arep"):
		return
	var r := area_rep(area)
	if amt > 0.0:
		r += amt * (1.0 - r / 110.0)
	else:
		r += amt
	s.scout.arep[area] = snappedf(clampf(r, 0.0, 100.0), 0.01)

func area_learn_mult(pid: String) -> float:
	## Yerel bağlantılar: aynı gözlemden daha çok bilgi
	return 1.0 + area_rep(area_of_player(pid)) / 250.0

func reliability() -> float:
	## Raporlarının isabet oranı (yeterli veri yoksa nötr 0.5)
	var acc: Dictionary = s.scout.get("acc", {})
	var n := int(acc.get("n", 0))
	if n < 3:
		return 0.5
	return float(acc.good) / float(n)

func scout_badges() -> Array:
	## Kazanılmış rozetler (olumsuz etiket dahil)
	var out := []
	var sp: Dictionary = s.scout.get("spec", {})
	for id in BADGES:
		var b: Array = BADGES[id]
		if float(sp.get(b[1], 0.0)) >= float(b[2]):
			out.append(id)
	var acc: Dictionary = s.scout.get("acc", {})
	if int(acc.get("n", 0)) >= 5 and reliability() >= 0.7:
		out.append("reliable")
	if int(acc.get("infl", 0)) >= 3 and float(acc.infl) / maxf(1.0, float(acc.n)) >= 0.4:
		out.append("inflater")
	return out

func badge_progress(id: String) -> float:
	if BADGES.has(id):
		var b: Array = BADGES[id]
		return clampf(float(s.scout.get("spec", {}).get(b[1], 0.0)) / float(b[2]), 0.0, 1.0)
	if id == "reliable":
		var n := int(s.scout.get("acc", {}).get("n", 0))
		return clampf(minf(float(n) / 5.0, reliability() / 0.7), 0.0, 1.0)
	return 0.0

func badge_trust(p: Dictionary, a: Dictionary) -> float:
	## Rozetlerin yönetim güvenine etkisi
	var b := scout_badges()
	var t := 0.0
	if ("spec_" + String(Data.POS_GROUP[p.pos])) in b:
		t += 0.07
	if "spec_youth" in b and a.get("kind", "") in ["prospect", "wonderkid"]:
		t += 0.07
	if "spec_gem" in b and club_tier(p.club) >= 3:
		t += 0.05
	if "reliable" in b:
		t += 0.06
	if "inflater" in b:
		t -= 0.1
	return t

func _rep_track(r: Dictionary, p: Dictionary, score: float, act_pot: float) -> void:
	## Rapor değerlendirmesi: isabet, uzmanlık puanı, abartma
	var acc: Dictionary = s.scout.acc
	acc.n = int(acc.n) + 1
	var good := score >= 0.5
	if good:
		acc.good = int(acc.good) + 1
	if float(r.pot) - act_pot >= 1.0:
		acc.infl = int(acc.infl) + 1
	var grp: String = Data.POS_GROUP.get(p.pos, "MID")
	var sp: Dictionary = s.scout.spec
	var dv := 1.0 if good else (-0.5 if score < -0.5 else 0.0)
	sp[grp] = maxf(0.0, float(sp.get(grp, 0.0)) + dv)
	if int(r.get("age0", p.age)) <= 19:
		sp.youth = maxf(0.0, float(sp.youth) + dv)
	if tier(r.get("lg0", "SL")) >= 3 and good:
		sp.gem = float(sp.gem) + 1.0

func _check_badges() -> void:
	var now := scout_badges()
	for id in now:
		if not (id in s.scout.badges):
			s.scout.badges.append(id)
			add_news("n_badge", [T.t("badge_" + id)], true, "bad" if id == "inflater" else "career")
	for id in s.scout.badges.duplicate():
		if not (id in now):
			s.scout.badges.erase(id)

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != SAVE_VERSION:
		if typeof(data) == TYPE_DICTIONARY and int(data.get("version", 0)) < SAVE_VERSION:
			old_save = true
		return false
	s = data
	for pid in s.players:
		var p: Dictionary = s.players[pid]
		if p.attrs is Array:
			var ad := {}
			for i in Data.ATTRS.size():
				ad[Data.ATTRS[i]] = int(p.attrs[i])
			p.attrs = ad
		if p.hid is Array:
			var hd := {}
			for i in Data.HIDDEN.size():
				hd[Data.HIDDEN[i]] = int(p.hid[i])
			p.hid = hd
	_fix_ints()
	# eski kayıtlar: eriyen/forvetsiz kadroları onar
	for cid in s.clubs:
		if not is_lazy(cid):
			fill_squad(cid)
	if not s.scout.has("rep_start"):
		s.scout["rep_start"] = s.scout.rep
	_ensure_v15()
	return true

func _ensure_v15() -> void:
	## v0.15 alanları (eski kayıtlarla uyum)
	var sc: Dictionary = s.scout
	if not sc.has("arep"):
		sc["arep"] = {}
	if not sc.has("spec"):
		sc["spec"] = {"GK": 0.0, "DEF": 0.0, "MID": 0.0, "ATT": 0.0, "youth": 0.0, "gem": 0.0}
	if not sc.has("acc"):
		sc["acc"] = {"n": 0, "good": 0, "infl": 0}
	if not sc.has("badges"):
		sc["badges"] = []
	if not sc.has("shadow"):
		sc["shadow"] = {}
	if not sc.has("disc_log"):
		sc["disc_log"] = []
	if not s.has("requests"):
		s["requests"] = []
	if not s.has("museum"):
		s["museum"] = []
	if not s.has("next_qid"):
		s["next_qid"] = 1

func _fix_ints() -> void:
	for k in ["season", "week", "next_pid", "next_aid", "next_rid"]:
		s[k] = int(s[k])
	for k in ["eye", "net", "xp_eye", "xp_net", "money", "salary", "budget", "spent", "fatigue"]:
		s.scout[k] = int(s.scout[k])
	for k in s.scout.stats:
		s.scout.stats[k] = int(s.scout.stats[k])
	for pid in s.players:
		var p = s.players[pid]
		for k in ["age", "ovr", "pa", "value", "inj", "contract", "skin", "hair", "seed"]:
			p[k] = int(p[k])
		p.st.apps = int(p.st.apps)
		p.st.g = int(p.st.g)
		p.st.a = int(p.st.a)
		for a in p.attrs:
			p.attrs[a] = int(p.attrs[a])
		for h in p.hid:
			p.hid[h] = int(p.hid[h])
	for cid in s.clubs:
		s.clubs[cid].prestige = int(s.clubs[cid].prestige)
		s.clubs[cid].budget = int(s.clubs[cid].budget)
	for lg in s.fixtures:
		for rnd in s.fixtures[lg]:
			for m in rnd:
				m.gh = int(m.gh)
				m.ga = int(m.ga)
	for lg in s.table:
		for cid in s.table[lg]:
			for k in ["p", "w", "d", "l", "gf", "ga", "pts"]:
				s.table[lg][cid][k] = int(s.table[lg][cid][k])

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
