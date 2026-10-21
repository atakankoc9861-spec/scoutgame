extends "res://tests/check/check_base.gd"
## v0.24 Dalga 2B: tema + hareket + düğmeler.
## 1) Sakin mod (Game.settings.calm) açıkken tüm hareket süreleri 0; yardımcılar tween kurmaz,
##    son durumu hemen yazar. Kapalıyken süreler > 0 ve tween kurulur.
## 2) Kit yazı tipleri yüklenir ve ğ ş ı İ Ö Ç Ü (+ Ğ Ş ö ç ü) glifleri kendi dosyalarında var
##    (sistem fontuna düşmez). Kaldırılan yazı tipleri (Oswald, Special Elite) kitte anılmaz.
## 3) ui/motion.gd ve ui/kit.gd içinde kökten create_tween() yok (hepsi node.create_tween()).
## 4) Türkçe büyük harf: "gönderildi" → "GÖNDERİLDİ".

const Kit := preload("res://ui/kit.gd")
const TV := preload("res://ui/theme_v24.gd")
const Motion := preload("res://ui/motion.gd")
const TR_CHARS := "ğşıİÖÇÜĞŞöçü"

func check_name() -> String:
	return "tema_check"

func run_check() -> void:
	var had: bool = Game.settings.has("calm")
	var old: Variant = Game.settings.get("calm", false)
	await _check_calm(true)
	await _check_calm(false)
	if had:
		Game.settings["calm"] = old
	else:
		Game.settings.erase("calm")
	_check_fonts()
	_check_no_root_tween()
	check(TV.upper("gönderildi", "tr") == "GÖNDERİLDİ", "TR büyük harf: %s" % TV.upper("gönderildi", "tr"))
	check(TV.upper("şığ çiğ öğün", "tr") == "ŞIĞ ÇİĞ ÖĞÜN", "TR büyük harf 2: %s" % TV.upper("şığ çiğ öğün", "tr"))
	check(TV.upper("tip", "en") == "TIP", "EN büyük harf")
	# düğme türleri: hepsi geçerli stil döndürür
	for k: String in ["primary", "brass", "red", "ink", "dark", "toggle_on", "ghost", "danger", "small"]:
		var st: Dictionary = TV.button(k)
		check(st.n is StyleBox and st.h is StyleBox and st.p is StyleBox, "düğme stili eksik: " + k)
		check(int(st.min) >= 72, "dokunma hedefi küçük (%s): %d" % [k, int(st.min)])

func _check_calm(on: bool) -> void:
	Game.settings["calm"] = on
	var tag := "calm=%s" % str(on)
	check(Motion.calm() == on, tag + ": Motion.calm() okumuyor")
	var d: Dictionary = Motion.durations()
	for k: String in d:
		if on:
			check(float(d[k]) == 0.0, "%s: %s süresi 0 değil (%s)" % [tag, k, str(d[k])])
		else:
			check(float(d[k]) > 0.0, "%s: %s süresi 0" % [tag, k])
	var host := Control.new()
	add_child(host)
	var lbl := Label.new()
	host.add_child(lbl)
	var tw: Tween = Motion.count_up(lbl, 120.0)
	var st := Control.new()
	st.custom_minimum_size = Vector2(100, 40)
	host.add_child(st)
	var tw2: Tween = Motion.stamp_slam(st)
	var btn := Button.new()
	host.add_child(btn)
	var tw3: Tween = Motion.press_down(btn)
	var tw4: Tween = Motion.shine(btn)
	var cards: Array = []
	for i in 3:
		var c := PanelContainer.new()
		host.add_child(c)
		cards.append(c)
	Motion.deal_in(cards)
	if on:
		check(tw == null and tw2 == null and tw3 == null and tw4 == null, tag + ": tween kuruldu")
		check(lbl.text == "120", tag + ": sayaç son değeri yazmadı: " + lbl.text)
		check(st.scale == Vector2.ONE and st.modulate.a == 1.0, tag + ": mühür son durumda değil")
		check(btn.get_node_or_null("Shine") == null, tag + ": ışık süpürmesi eklendi")
		for c: Control in cards:
			check(c.modulate.a == 1.0 and c.scale == Vector2.ONE, tag + ": kart son durumda değil")
	else:
		check(tw != null and tw2 != null and tw3 != null and tw4 != null, tag + ": tween kurulmadı")
		check(btn.get_node_or_null("Shine") != null, tag + ": ışık şeridi yok")
		check(cards[0].modulate.a == 0.0, tag + ": kart dağıtma başlamadı")
		await get_tree().create_timer(1.2).timeout
		check(lbl.text == "120", tag + ": sayaç bitmedi: " + lbl.text)
		check(st.scale.is_equal_approx(Vector2.ONE), tag + ": mühür oturmadı")
		for c: Control in cards:
			check(is_equal_approx(c.modulate.a, 1.0), tag + ": kart görünmedi")
	host.queue_free()
	await get_tree().process_frame

func _check_fonts() -> void:
	var kit: Control = Kit.new()
	kit._load_fonts()
	for fname: String in ["F_BODY", "F_SEMI", "F_HEAD", "F_HEADR", "F_TYPE", "F_TYPEB", "F_HAND", "F_STAMP", "F_DISP"]:
		var f: Font = kit.get(fname)
		if not check(f != null, "yazı tipi yüklenmedi: " + fname):
			continue
		var base: Font = f
		if f is FontVariation:
			base = (f as FontVariation).base_font
		check(base is FontFile, fname + " FontFile değil")
		var missing := ""
		for ch in TR_CHARS:
			# fallback'e bakmadan yalnız dosyanın kendisi
			var ff := base as FontFile
			if ff == null or not ff.has_char(ch.unicode_at(0)):
				missing += ch
		check(missing == "", "%s (%s) glif eksik: %s" % [fname, base.resource_path.get_file(), missing])
	for path: String in ["res://fonts/IBMPlexMono-Medium.ttf", "res://fonts/IBMPlexMono-SemiBold.ttf"]:
		check(ResourceLoader.exists(path), "yok: " + path)
	kit.free()
	var src := FileAccess.get_file_as_string("res://ui/kit.gd") + FileAccess.get_file_as_string("res://ui/theme_v24.gd")
	for gone: String in ["Oswald", "SpecialElite", "CourierPrime"]:
		check(src.find(gone + "-") < 0 and src.find("\"" + gone + "\"") < 0, "kit hâlâ anıyor: " + gone)

func _check_no_root_tween() -> void:
	var re := RegEx.new()
	# satırda "create_tween(" önünde "." yoksa ya da get_tree().create_tween ise kökten sayılır
	re.compile("(^|[^.\\w])create_tween\\(|get_tree\\(\\)\\.create_tween\\(")
	for path: String in ["res://ui/motion.gd", "res://ui/kit.gd"]:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		check(lines.size() > 10, "okunamadı: " + path)
		for i in lines.size():
			var ln: String = lines[i]
			if ln.strip_edges().begins_with("#"):
				continue
			check(re.search(ln) == null, "%s:%d kökten create_tween: %s" % [path, i + 1, ln.strip_edges()])
