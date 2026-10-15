extends Node
## Ortak test temeli (tests/check/*_check.gd bunu genişletir).
## - Sabit tohum (CHECK_SEED ortam değişkeniyle değiştirilebilir) -> tekrarlanabilir sonuç.
## - Motor/script hatalarını Logger ile yakalar: bir SCRIPT ERROR fonksiyonu yarıda kesse bile
##   test asılı kalmaz, sonunda quit(1) ile biter (eski tests/quick.gd bu yüzden asılı kalıyordu).
## - Sonuç satırı: "CHECK_RESULT: PASS" / "CHECK_RESULT: FAIL" (runner bunu da arar).
## Bu dosyanın adı *_check ile bitmez, runner onu test olarak çalıştırmaz.

class ErrorCatcher extends Logger:
	var count: int = 0
	var first: PackedStringArray = []
	var _mx: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mx.lock()
		count += 1
		if first.size() < 10:
			first.append("%s %s (%s:%d %s)" % [code, rationale, file, line, function])
		_mx.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

const DEFAULT_SEED: int = 20231015
const MAX_PRINTED_FAILS: int = 25

var _catcher: ErrorCatcher
var _fails: PackedStringArray = []
var _checks: int = 0
var _t0: int = 0
var _finished: bool = false

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	var sd: int = DEFAULT_SEED
	var env_seed: String = OS.get_environment("CHECK_SEED")
	if env_seed.is_valid_int():
		sd = env_seed.to_int()
	Game.rng.seed = sd
	seed(sd)
	print("[CHECK] %s seed=%d" % [check_name(), sd])
	await run_check()
	finish()

## Alt sınıf adını döndürür (çıktıda görünür)
func check_name() -> String:
	return str(get_script().resource_path.get_file().get_basename())

## Alt sınıf bunu doldurur. İçinde await kullanılabilir.
func run_check() -> void:
	pass

func check(cond: bool, msg: String) -> bool:
	_checks += 1
	if not cond:
		_fails.append(msg)
		if _fails.size() <= MAX_PRINTED_FAILS:
			print("  FAIL: ", msg)
	return cond

## Sayı mı, sonlu mu (NaN/inf değil) ve [lo, hi] aralığında mı
func check_num(v: Variant, label: String, lo: float = -INF, hi: float = INF) -> bool:
	var t: int = typeof(v)
	if not check(t == TYPE_INT or t == TYPE_FLOAT, "%s sayı değil (tip %d, değer %s)" % [label, t, str(v)]):
		return false
	var f: float = float(v)
	if not check(is_finite(f), "%s sonlu değil: %s" % [label, str(v)]):
		return false
	return check(f >= lo and f <= hi, "%s aralık dışı: %s (beklenen %s..%s)" % [label, str(v), str(lo), str(hi)])

func log_info(msg: String) -> void:
	print("  ", msg)

func failed() -> bool:
	return not _fails.is_empty() or _catcher.count > 0

## Scout'un para/itibar/bütçe durumu: NaN yok, eksi yok
func check_scout_state(tag: String) -> void:
	var sc: Dictionary = Game.s.get("scout", {})
	check_num(sc.get("money"), tag + " money", 0.0)
	check_num(sc.get("rep"), tag + " rep", 0.0, 100.0)
	check_num(sc.get("budget"), tag + " budget", 0.0)
	check_num(sc.get("spent"), tag + " spent", 0.0)
	check_num(sc.get("salary"), tag + " salary", 0.0)
	check_num(sc.get("fatigue"), tag + " fatigue", 0.0)
	for ar: Variant in sc.get("arep", {}):
		check_num(sc.arep[ar], "%s arep[%s]" % [tag, str(ar)], 0.0, 100.0)
	var life: Dictionary = Game.s.get("life", {})
	for k: Variant in life.get("rel", {}):
		check_num(life.rel[k], "%s life.rel[%s]" % [tag, str(k)], 0.0, 100.0)

## Kaydet → yükle → kaydet → yükle → kaydet.
## Kural: ikinci ve üçüncü kayıt metni birebir aynı olmalı (kalıcı durum yükle/kaydet ile değişmez).
## İlk tur için tek izin verilen fark: load_game() içindeki fill_squad() onarımının eklediği
## oyuncular (yeni pid'ler, kadro listesine eklenmeleri, next_pid artışı). CHECK_STRICT_SAVE=1
## ile bu tolerans kapatılır. Dönüş: onarımın eklediği oyuncu sayısı.
func check_save_roundtrip(tag: String) -> int:
	var before_money: Variant = Game.s.scout.money
	var before_rep: Variant = Game.s.scout.rep
	var before_season: int = int(Game.s.season)
	var before_week: int = int(Game.s.week)
	var before_club: String = str(Game.s.scout.club_id)
	Game.save_game()
	var txt_a: String = FileAccess.get_file_as_string(Game.SAVE_PATH)
	check(txt_a.length() > 1000, tag + " kayıt dosyası boş/kısa")
	check(Game.load_game(), tag + " load_game() #1 false döndü")
	check(int(Game.s.get("version", -1)) == Game.SAVE_VERSION, tag + " sürüm uyuşmuyor")
	check(Game.s.scout.money == before_money, "%s money yüklemeden sonra farklı: %s -> %s" % [tag, str(before_money), str(Game.s.scout.money)])
	check(is_equal_approx(float(Game.s.scout.rep), float(before_rep)), "%s rep yüklemeden sonra farklı: %s -> %s" % [tag, str(before_rep), str(Game.s.scout.rep)])
	check(int(Game.s.season) == before_season and int(Game.s.week) == before_week, tag + " sezon/hafta yüklemeden sonra farklı")
	check(str(Game.s.scout.club_id) == before_club, tag + " kulüp yüklemeden sonra farklı")
	check(typeof(Game.s.scout.money) == TYPE_INT, tag + " money yüklemeden sonra int değil")
	check(typeof(Game.s.week) == TYPE_INT and typeof(Game.s.season) == TYPE_INT, tag + " season/week int değil")
	var pk: Array = Game.s.players.keys()
	if check(not pk.is_empty(), tag + " yüklemeden sonra oyuncu yok"):
		var p0: Dictionary = Game.player(str(pk[0]))
		check(p0.attrs is Dictionary and p0.hid is Dictionary, tag + " attrs/hid sözlüğe açılmadı")
	check_scout_state(tag + " (yüklendi)")
	Game.save_game()
	var txt_b: String = FileAccess.get_file_as_string(Game.SAVE_PATH)
	check(Game.load_game(), tag + " load_game() #2 false döndü")
	Game.save_game()
	var txt_c: String = FileAccess.get_file_as_string(Game.SAVE_PATH)
	var pa: Variant = _parse_json(txt_a)
	var pb: Variant = _parse_json(txt_b)
	var pc: Variant = _parse_json(txt_c)
	if not check(pa is Dictionary and pb is Dictionary and pc is Dictionary, tag + " kayıt metni geçerli JSON değil (NaN/inf yazılmış olabilir)"):
		return 0
	if not check(txt_b == txt_c, "%s kaydet→yükle→kaydet kararlı değil (uzunluk %d vs %d)" % [tag, txt_b.length(), txt_c.length()]):
		var diffs_bc: PackedStringArray = []
		deep_diff(pb, pc, "", diffs_bc)
		for d: String in diffs_bc:
			print("    ", d)
	# A ile B: fill_squad onarımı dışında aynı olmalı
	var da: Dictionary = pa
	var db: Dictionary = pb
	var added: Array = []
	for pid: Variant in db.players:
		if not da.players.has(pid):
			added.append(pid)
	var strict: bool = OS.get_environment("CHECK_STRICT_SAVE") == "1"
	if not added.is_empty():
		log_info("%s: load_game() fill_squad onarımı %d oyuncu ekledi (%s)" % [tag, added.size(), ", ".join(PackedStringArray(added.map(func(x: Variant) -> String: return str(x))))])
		check(not strict, "%s ilk yükleme durumu değiştirdi (+%d oyuncu, CHECK_STRICT_SAVE=1)" % [tag, added.size()])
		for pid: Variant in added:
			var cid: String = str(db.players[pid].get("club", ""))
			check(db.clubs.has(cid) and pid in db.clubs[cid].squad, "%s onarım oyuncusu %s bir kadroda değil" % [tag, str(pid)])
			db.players.erase(pid)
		for cid: Variant in db.clubs:
			var sq: Array = db.clubs[cid].squad
			db.clubs[cid].squad = sq.filter(func(x: Variant) -> bool: return not (x in added))
		check(int(db.next_pid) == int(da.next_pid) + added.size(), "%s next_pid onarımla uyumsuz" % tag)
		db.next_pid = da.next_pid
	var diffs: PackedStringArray = []
	deep_diff(da, db, "", diffs)
	if not check(diffs.is_empty(), "%s kaydet→yükle→kaydet farkı: %d alan" % [tag, diffs.size()]):
		for d: String in diffs:
			print("    ", d)
	return added.size()

## JSON.parse_string yerine: hata motor hatası olarak loglanmaz, null döner
func _parse_json(txt: String) -> Variant:
	var j: JSON = JSON.new()
	if j.parse(txt) != OK:
		return null
	return j.data

## İki JSON ağacını karşılaştırır, farkları out'a yazar (en fazla 20)
func deep_diff(x: Variant, y: Variant, path: String, out: PackedStringArray) -> void:
	if out.size() >= 20:
		return
	if typeof(x) == TYPE_DICTIONARY and typeof(y) == TYPE_DICTIONARY:
		var dx: Dictionary = x
		var dy: Dictionary = y
		for k: Variant in dx:
			if not dy.has(k):
				out.append("eksik %s/%s" % [path, str(k)])
			else:
				deep_diff(dx[k], dy[k], path + "/" + str(k), out)
		for k: Variant in dy:
			if not dx.has(k):
				out.append("fazla %s/%s" % [path, str(k)])
	elif typeof(x) == TYPE_ARRAY and typeof(y) == TYPE_ARRAY:
		var ax: Array = x
		var ay: Array = y
		if ax.size() != ay.size():
			out.append("boyut %s %d != %d" % [path, ax.size(), ay.size()])
			return
		for i: int in ax.size():
			deep_diff(ax[i], ay[i], "%s[%d]" % [path, i], out)
	elif typeof(x) != typeof(y) or x != y:
		out.append("değer %s: %s != %s" % [path, str(x), str(y)])

func finish() -> void:
	if _finished:
		return
	_finished = true
	var ms: int = Time.get_ticks_msec() - _t0
	OS.remove_logger(_catcher)
	if _catcher.count > 0:
		_fails.append("%d motor/script hatası yakalandı" % _catcher.count)
		for e: String in _catcher.first:
			print("  ERROR: ", e)
	var ok: bool = _fails.is_empty()
	print("[CHECK] %s checks=%d fails=%d ms=%d" % [check_name(), _checks, _fails.size(), ms])
	print("CHECK_RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
