extends "res://ui/kit.gd"
## v0.24 Dalga 2B görsel kontrol: "Gece Dosyası" teması, Türkçe mühürler, yeni düğmeler/kartlar.
## Çalıştır: xvfb-run godot --path . --rendering-driver opengl3 res://tests/tema_shots.tscn
## Çıktı: TEMA_SHOT_DIR (varsayılan user://tema_shots/) altında tema_01.png, tema_02_calm.png

func _ready() -> void:
	_load_fonts()
	theme = _make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var out := OS.get_environment("TEMA_SHOT_DIR")
	if out == "":
		out = OS.get_user_data_dir() + "/tema_shots"
	DirAccess.make_dir_recursive_absolute(out)
	Game.settings["calm"] = false
	_build()
	await _wait(70)
	get_viewport().get_texture().get_image().save_png(out + "/tema_01.png")
	print("shot ", out + "/tema_01.png")
	for c in get_children():
		c.queue_free()
	Game.settings["calm"] = true
	await get_tree().process_frame
	_build()
	await _wait(3)
	get_viewport().get_texture().get_image().save_png(out + "/tema_02_calm.png")
	print("shot ", out + "/tema_02_calm.png")
	get_tree().quit(0)

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_DESK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 28)
	add_child(m)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", _paper_style(C_PAPER, 26, 8, 7))
	m.add_child(sheet)
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	sheet.add_child(page)
	_title("Gece dosyası · tema", page)
	var row := _h(page, 18)
	var s1 := _stamp("GÖNDERİLDİ", C_RED, -8.0, 34)
	var s2 := _stamp("TAKİPTE", C_BLUE, 5.0, 30)
	row.add_child(s1)
	row.add_child(s2)
	_stamp_slam(s1)
	_stamp_slam(s2)
	_h(page).add_child(_stamp("şığ çiğ öğün", C_GREEN, -3.0, 30))
	var c1 := _card(page)
	_accent_top(c1, Color("#1f4e8c"))
	c1.add_child(_head("ŞIĞ ÇİĞ ÖĞÜN — İSTANBUL", 32))
	c1.add_child(_lbl("Gövde (Barlow): Gözcü raporu: sağ kanatta çığır açan bir oyuncu, ğ ş ı İ Ö Ç Ü.", 22))
	c1.add_child(_typed("ETİKET (Plex Mono): FORM-07 · BİLGİ %64 · ŞUBAT", 20, C_INK2))
	_kv(c1, "Potansiyel", "4–5★")
	_kv(c1, "Değer", "1,2 M€", C_GREEN)
	var cnt := _lbl("0", 44, C_INK, false, F_DISP)
	c1.add_child(cnt)
	Motion.count_up(cnt, 2847.0, func(v: float) -> String: return "İTİBAR %d" % int(v), 0.6)
	_bar(c1, 0.64, C_BLUE)
	var memo := _card(page, "memo")
	memo.add_child(_hand("El notu (Caveat): çığlık atan taraftar, ağır top; İzmir'e git.", 30))
	var cta := _btn("Mühürle ve gönder", func(): pass, "primary", page)
	_cta_shine(cta)
	var h2 := _h(page, 12)
	_expand(_btn("Takibe al", func(): pass, "small", h2))
	_expand(_btn("Gölge kadro", func(): pass, "ghost", h2))
	var h3 := _h(page, 12)
	_expand(_btn("Reddet", func(): pass, "red", h3))
	_expand(_btn("Seçili", func(): pass, "toggle_on", h3))
	_expand(_btn("Sil", func(): pass, "danger", h3))
	var dk := _card(page, "dark")
	dk.add_child(_lbl("Deri üstü (dark kart)", 22, C_CREAM))
	_btn("Haftayı bitir", func(): pass, "dark", dk)
	Motion.deal_in([_card_panel(c1), _card_panel(memo), _card_panel(dk)])
