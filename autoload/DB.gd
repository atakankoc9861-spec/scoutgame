extends Node
## Topluluk veritabanı: içe/dışa aktarma ve yeni kariyere uygulama.
## Oyun yalnızca aracı sağlar; gerçek isimli dosyalar oyunla dağıtılmaz.
##
## Biçim (JSON):
## {
##   "format": "gozcu-db", "version": 1, "name": "...", "author": "...",
##   "leagues": {"SL": "Lig adı", ...},                       (isteğe bağlı)
##   "clubs": [
##     {"id": "c0", "name": "...", "short": "ABC", "city": "İstanbul", "prestige": 80,
##      "c1": "#ff0000", "c2": "#ffffff", "manager": "Ad Soyad",
##      "players": [ {"first": "Ad", "last": "Soyad", "age": 24, "pos": "ST", "nat": "TR",
##                    "foot": "R", "ovr": 72, "pa": 80, "u19": false, "attrs": {...}} ]}
##   ]
## }
## Kulüp eşleşmesi: önce "id", sonra isim, sonra kısa ad. "players" verilirse kadro
## tamamen değişir (eksik mevkiler otomatik tamamlanır).

const ACTIVE_PATH := "user://veritabani.json"
const FORMAT := "gozcu-db"
const DIR_NAME := "Gozcu"

var _cache := {}
var _cache_ok := false

# ---------------------------------------------------------------- etkin dosya

func active() -> Dictionary:
	if _cache_ok:
		return _cache
	_cache_ok = true
	_cache = {}
	if not FileAccess.file_exists(ACTIVE_PATH):
		return _cache
	var r := parse(FileAccess.get_file_as_string(ACTIVE_PATH))
	if r.ok:
		_cache = r.data
	return _cache

func active_info() -> Dictionary:
	var d := active()
	if d.is_empty():
		return {}
	return info(d)

func info(d: Dictionary) -> Dictionary:
	var np := 0
	var nc := 0
	for c in d.get("clubs", []):
		if c is Dictionary:
			nc += 1
			np += (c.get("players", []) as Array).size() if c.get("players") is Array else 0
	return {"name": str(d.get("name", "?")), "author": str(d.get("author", "")), "clubs": nc, "players": np}

func install(text: String) -> Dictionary:
	var r := parse(text)
	if not r.ok:
		return r
	var f := FileAccess.open(ACTIVE_PATH, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "err": "write"}
	f.store_string(text)
	f.close()
	_cache_ok = false
	return {"ok": true, "info": info(r.data)}

func remove() -> void:
	if FileAccess.file_exists(ACTIVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ACTIVE_PATH))
	_cache_ok = false

func parse(text: String) -> Dictionary:
	text = text.strip_edges()
	if text == "":
		return {"ok": false, "err": "empty"}
	# BOM
	if text.unicode_at(0) == 0xFEFF:
		text = text.substr(1)
	var j := JSON.new()
	if j.parse(text) != OK:
		return {"ok": false, "err": "json", "line": j.get_error_line()}
	var d = j.data
	if not d is Dictionary:
		return {"ok": false, "err": "format"}
	if str(d.get("format", "")) != FORMAT or not d.get("clubs") is Array:
		return {"ok": false, "err": "format"}
	return {"ok": true, "data": d}

# ---------------------------------------------------------------- uygulama

func _find_club(e: Dictionary) -> String:
	var g = Game
	if e.has("id") and g.s.clubs.has(str(e.id)):
		return str(e.id)
	var nm := str(e.get("match", e.get("name", ""))).to_lower()
	var sh := str(e.get("short", "")).to_lower()
	if nm != "":
		for cid in g.s.clubs:
			if str(g.s.clubs[cid].name).to_lower() == nm:
				return cid
	if sh != "":
		for cid in g.s.clubs:
			if str(g.s.clubs[cid].short).to_lower() == sh:
				return cid
	return ""

func apply_to_world(d: Dictionary) -> Dictionary:
	## Game.new_game içinde, kadrolar üretildikten sonra çağrılır.
	var g = Game
	var stats := {"clubs": 0, "players": 0}
	if d.get("leagues") is Dictionary:
		var ln := {}
		for k in d.leagues:
			if g.LEAGUES.has(str(k)) and str(d.leagues[k]).strip_edges() != "":
				ln[str(k)] = str(d.leagues[k]).strip_edges().left(40)
		g.s["league_names"] = ln
	for e in d.get("clubs", []):
		if not e is Dictionary:
			continue
		var cid := _find_club(e)
		if cid == "":
			continue
		var c: Dictionary = g.s.clubs[cid]
		apply_club_fields(c, e)
		stats.clubs += 1
		if e.get("players") is Array and not (e.players as Array).is_empty():
			stats.players += replace_squad(cid, e.players)
	return stats

func apply_club_fields(c: Dictionary, e: Dictionary) -> void:
	for k in ["name", "city"]:
		if e.has(k) and str(e[k]).strip_edges() != "":
			c[k] = str(e[k]).strip_edges().left(40)
	if e.has("short") and str(e.short).strip_edges() != "":
		c.short = str(e.short).strip_edges().to_upper().left(4)
	for k in ["c1", "c2"]:
		if e.has(k) and Color.html_is_valid(str(e[k])):
			c[k] = "#" + Color(str(e[k])).to_html(false)
	if e.has("prestige"):
		c.prestige = clampi(int(e.prestige), 1, 99)
		c.budget = int(round(300000.0 * exp(float(c.prestige) / 20.0) / 50000.0) * 50000)
	if e.has("manager") and str(e.manager).strip_edges() != "":
		c.manager.name = str(e.manager).strip_edges().left(40)

func replace_squad(cid: String, plist: Array) -> int:
	var g = Game
	var c: Dictionary = g.s.clubs[cid]
	for pid in c.squad + c.u19:
		g.s.players.erase(pid)
	c.squad = []
	c.u19 = []
	var n := 0
	for pe in plist:
		if not pe is Dictionary:
			continue
		var pid := make_player(cid, pe)
		if pid == "":
			continue
		n += 1
		if g.s.players[pid].youth:
			c.u19.append(pid)
		else:
			c.squad.append(pid)
	g.fill_squad(cid)
	return n

func make_player(cid: String, pe: Dictionary) -> String:
	var g = Game
	var first := str(pe.get("first", "")).strip_edges()
	var last := str(pe.get("last", "")).strip_edges()
	if first == "" and last == "" and pe.has("name"):
		var parts := str(pe.name).strip_edges().split(" ", false)
		if parts.size() == 1:
			last = parts[0]
		elif parts.size() > 1:
			last = parts[parts.size() - 1]
			first = " ".join(parts.slice(0, parts.size() - 1))
	if first == "" and last == "":
		return ""
	var pos := str(pe.get("pos", "CM")).to_upper()
	if not Data.POS_WEIGHTS.has(pos):
		pos = "CM"
	var age := clampi(int(pe.get("age", 24)), 14, 45)
	var ovr := clampi(int(pe.get("ovr", g.club_level(cid))), 20, 97)
	var nat := str(pe.get("nat", "TR")).to_upper().left(3)
	var youth := bool(pe.get("u19", false)) and age <= 19
	var pid: String = g.new_player(pos, ovr, age, nat if Data.FIRST.has(nat) else "TR", cid, youth)
	var p: Dictionary = g.s.players[pid]
	p.first = first
	p.last = last
	p.nat = nat
	p.disc = not youth
	if pe.has("foot"):
		p.foot = "L" if str(pe.foot).to_upper().begins_with("L") or str(pe.foot).to_upper().begins_with("S") else "R"
	if pe.get("attrs") is Dictionary:
		for a in pe.attrs:
			if p.attrs.has(a):
				p.attrs[a] = clampi(int(pe.attrs[a]), 1, 20)
	elif pe.has("ovr"):
		set_ovr(p, ovr)
	p.ovr = g.calc_ovr(p)
	if pe.has("pa"):
		p.pa = clampi(int(pe.pa), p.ovr, 99)
	else:
		p.pa = maxi(p.pa, p.ovr)
	if pe.get("hid") is Dictionary:
		for h in pe.hid:
			if p.hid.has(h):
				p.hid[h] = clampi(int(pe.hid[h]), 1, 20)
	if pe.has("contract"):
		p.contract = clampi(int(pe.contract), g.s.season, g.s.season + 8)
	p.value = g.calc_value(p)
	return pid

func set_ovr(p: Dictionary, target: int) -> void:
	## Özellikleri mevkie göre ölçekleyerek hedef OVR'a yaklaştır (profili koru).
	var g = Game
	var w: Dictionary = Data.POS_WEIGHTS[p.pos]
	var raw := {}
	for a in p.attrs:
		raw[a] = float(p.attrs[a])
	for i in 10:
		var cur: float = g.calc_ovr_f({"pos": p.pos, "attrs": raw})
		var diff := float(target) - cur
		if absf(diff) < 0.4:
			break
		for a in w:
			raw[a] = clampf(raw[a] + diff / 5.0, 1.0, 20.0)
	for a in raw:
		p.attrs[a] = clampi(int(round(raw[a])), 1, 20)
	p.ovr = g.calc_ovr(p)

# ---------------------------------------------------------------- dışa aktarma

func export_text(leagues: Array = [], with_attrs := false, name := "", author := "") -> String:
	## Mevcut dünyayı (kariyer yoksa taze bir dünya) şablon olarak yazar.
	## Her oyuncu tek satır: metin düzenleyicide kolay düzenlensin.
	var g = Game
	var temp := false
	var backup: Dictionary = {}
	if g.s.is_empty() or not g.s.has("clubs"):
		temp = true
		backup = g.s
		g.new_game("Scout", T.lang)
	var L := []
	L.append("{")
	L.append('  "format": "%s", "version": 1,' % FORMAT)
	L.append('  "name": %s,' % JSON.stringify(name if name != "" else "Gözcü veritabanı"))
	L.append('  "author": %s,' % JSON.stringify(author))
	var ln := {}
	for lg in g.LEAGUES:
		ln[lg] = T.t("league_" + lg)
	L.append('  "leagues": %s,' % JSON.stringify(ln))
	L.append('  "clubs": [')
	var ids: Array = g.s.clubs.keys()
	ids.sort_custom(func(a, b): return int(str(a).substr(1)) < int(str(b).substr(1)))
	var blocks := []
	for cid in ids:
		var c: Dictionary = g.s.clubs[cid]
		if not leagues.is_empty() and not (c.league in leagues):
			continue
		var b := []
		var head := {"id": cid, "league": c.league, "name": c.name, "short": c.short, "city": c.city,
			"prestige": int(c.prestige), "c1": c.c1, "c2": c.c2, "manager": c.manager.name}
		var hs := JSON.stringify(head)
		b.append("    " + hs.substr(0, hs.length() - 1) + ', "players": [')
		var rows := []
		for pid in c.squad + c.u19:
			var p: Dictionary = g.s.players.get(pid, {})
			if p.is_empty():
				continue
			var pe := {"first": p.first, "last": p.last, "age": int(p.age), "pos": p.pos, "nat": p.nat,
				"foot": p.foot, "ovr": int(p.ovr), "pa": int(p.pa)}
			if p.youth:
				pe["u19"] = true
			if with_attrs:
				var at := {}
				for a in Data.ATTRS:
					at[a] = int(p.attrs[a])
				pe["attrs"] = at
			rows.append("      " + JSON.stringify(pe))
		b.append(",\n".join(rows))
		b.append("    ]}")
		blocks.append("\n".join(b))
	L.append(",\n".join(blocks))
	L.append("  ]")
	L.append("}")
	if temp:
		g.s = backup
	return "\n".join(L) + "\n"

# ---------------------------------------------------------------- dosya konumları

func share_dir() -> String:
	## Android 11+: uygulamanın kendi oluşturduğu dosyalar İndirilenler'e izinsiz yazılabilir.
	var base := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if base == "":
		base = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if base == "":
		return ProjectSettings.globalize_path("user://")
	return base.path_join(DIR_NAME)

func write_share(fname: String, text: String) -> String:
	## Başarılıysa tam yolu döndürür; olmazsa user:// içine yazar ve onu döndürür.
	var dir := share_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(fname)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
		return path
	path = "user://" + fname
	f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
		return ProjectSettings.globalize_path(path)
	return ""

func list_share() -> Array:
	var out := []
	var dir := share_dir()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for fn in da.get_files():
		if fn.to_lower().ends_with(".json"):
			out.append(dir.path_join(fn))
	return out

func read_any(path: String) -> String:
	## content:// URI dahil (Android yerel seçici) okumayı dene
	var t := FileAccess.get_file_as_string(path)
	if t == "":
		var b := FileAccess.get_file_as_bytes(path)
		if not b.is_empty():
			t = b.get_string_from_utf8()
	return t
