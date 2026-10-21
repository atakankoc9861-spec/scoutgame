extends "res://tests/check/check_base.gd"
## v0.24 Dalga 1K: titreşim ayarı + üst bar tween'i.
## 1) Oyun kodunda (ui/, three/, autoload/, sim/) Input.vibrate_handheld yalnız ayar kapısının
##    arkasında çağrılabilir: aynı satırda Game.settings "haptic" kontrolü ya da kit.gd::_haptic içi.
## 2) ui/main.gd üst bar sayaç tween'leri kökten değil düğümden açılır (silinmiş etikete yazmaz).
## 3) Davranış: haptic=false iken kit._haptic hiçbir şey çağırmaz (masaüstünde zaten no-op; burada
##    kapı ifadesinin değerlendirilebildiği doğrulanır).

func check_name() -> String:
	return "hata_paketi_check"

func run_check() -> void:
	var files: Array = []
	for d in ["res://ui", "res://ui/screens", "res://three", "res://autoload", "res://sim"]:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.ends_with(".gd"):
				files.append(d + "/" + f)
	check(files.size() > 10, "taranan dosya sayısı az: %d" % files.size())
	var bad := 0
	var calls := 0
	for path in files:
		var txt := FileAccess.get_file_as_string(path)
		var lines := txt.split("\n")
		for i in lines.size():
			var ln: String = lines[i]
			if ln.find("Input.vibrate_handheld") < 0 or ln.strip_edges().begins_with("#"):
				continue
			calls += 1
			var gated := ln.find("\"haptic\"") >= 0
			if not gated and path.ends_with("kit.gd"):
				# kit.gd::_haptic: bir önceki satır kapı
				gated = i > 0 and lines[i - 1].find("\"haptic\"") >= 0
			if not check(gated, "%s:%d ayar kapısı olmadan titreşim: %s" % [path, i + 1, ln.strip_edges()]):
				bad += 1
	check(calls >= 5, "beklenen titreşim çağrıları bulunamadı (%d)" % calls)
	log_info("titreşim çağrısı: %d, kapısız: %d" % [calls, bad])

	var mt := FileAccess.get_file_as_string("res://ui/main.gd")
	check(mt.find("var tw := l.create_tween()") >= 0, "üst bar sayı tween'i etikete bağlı değil")
	check(mt.find("var tw2 := pc.create_tween()") >= 0, "üst bar kapsül tween'i düğüme bağlı değil")

	var old: Variant = Game.settings.get("haptic", true)
	Game.settings["haptic"] = false
	check(not (Game.settings.get("haptic", true) and OS.has_feature("mobile")), "haptic=false iken kapı açık")
	Game.settings["haptic"] = old
