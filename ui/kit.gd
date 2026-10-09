extends Control
## Gözcü arayüz kiti: "scout dosyası" görsel dili.
## Kâğıt dokulu kartlar, klasör sekmeleri, mühürler, polaroidler, bilet kartları, el yazısı notlar.
## main.gd bu sınıftan türer; tüm ekranlar buradaki yardımcıları kullanır.

const RangeBar = preload("res://ui/range_bar.gd")
const Stars = preload("res://ui/stars.gd")
const Icon = preload("res://ui/icon.gd")
const Crest = preload("res://ui/crest.gd")
const Avatar = preload("res://ui/avatar.gd")
const Radar = preload("res://ui/radar.gd")

# --- palet: kâğıt üstü
const C_PAPER := Color("#efe6d1")
const C_CARD := Color("#f8f3e7")
const C_MANILA := Color("#dcc391")
const C_MANILA_D := Color("#bfa065")
const C_INK := Color("#27241e")
const C_INK2 := Color("#6a6150")
const C_LINE := Color(0.15, 0.12, 0.08, 0.14)
const C_RED := Color("#b3261e")
const C_BLUE := Color("#1f4e8c")
const C_GREEN := Color("#2c7a39")
const C_HL := Color("#f3d65b")
const C_BRASS := Color("#c9a24a")
# --- palet: koyu (deri, masa)
const C_LEATHER := Color("#2b1e17")
const C_LEATHER2 := Color("#3b2a20")
const C_DESK := Color("#15100c")
const C_CREAM := Color("#f1e6cf")
const C_CREAM2 := Color("#b8a888")
# eski adlar (bazı yardımcılar için)
const C_ACCENT := C_BRASS
const C_TEXT := C_INK
const C_MUTED := C_INK2
const C_GOOD := C_GREEN
const C_BAD := C_RED

var F_BODY: Font
var F_SEMI: Font
var F_HEAD: Font
var F_HEADR: Font
var F_TYPE: Font
var F_TYPEB: Font
var F_HAND: Font
var F_STAMP: Font
var F_DISP: Font

var page: VBoxContainer        # şu anki içerik kabı (kâğıt sayfası)
var _dragged := false
var _busy := false
var _tex_cache := {}

# ================================================================ yazı tipleri ve tema

func _load_fonts() -> void:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Roboto", "Noto Sans", "Noto Sans Symbols 2", "sans-serif"])
	var table := [["F_BODY", "Barlow-Medium"], ["F_SEMI", "Barlow-SemiBold"], ["F_HEAD", "Oswald-Bold"], ["F_HEADR", "Oswald-Regular"],
		["F_TYPE", "CourierPrime-Regular"], ["F_TYPEB", "CourierPrime-Bold"], ["F_HAND", "Caveat-Bold"], ["F_STAMP", "SpecialElite"],
		["F_DISP", "BarlowCondensed-ExtraBold"]]
	for pair in table:
		var f: FontFile = load("res://fonts/%s.ttf" % pair[1])
		f.fallbacks = [sys]
		set(pair[0], f)

func _sb(col: Color, radius := 12, border := 0, bcol := C_LINE, pad := 14, shadow := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = bcol
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	if shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = Color(0, 0, 0, 0.28)
		sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = F_BODY
	th.default_font_size = 24
	th.set_color("font_color", "Label", C_INK)
	th.set_font("font", "Button", F_HEAD)
	th.set_font_size("font_size", "Button", 24)
	th.set_stylebox("normal", "Button", _sb(C_CARD, 10, 2, C_INK, 14))
	th.set_stylebox("hover", "Button", _sb(C_CARD.darkened(0.03), 10, 2, C_INK, 14))
	th.set_stylebox("pressed", "Button", _sb(C_HL, 10, 2, C_INK, 14))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_stylebox("disabled", "Button", _sb(Color(0, 0, 0, 0.05), 10, 1, C_LINE, 14))
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color", "font_pressed_color"]:
		th.set_color(k, "Button", C_INK)
	th.set_color("font_disabled_color", "Button", Color(C_INK, 0.35))
	th.set_stylebox("normal", "LineEdit", _sb(C_CARD, 8, 2, C_INK, 14))
	th.set_stylebox("focus", "LineEdit", _sb(Color.WHITE, 8, 3, C_BLUE, 14))
	th.set_color("font_color", "LineEdit", C_INK)
	th.set_color("caret_color", "LineEdit", C_BLUE)
	th.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	th.set_stylebox("slider", "HSlider", _sb(Color(C_INK, 0.15), 6, 0, C_LINE, 4))
	th.set_stylebox("grabber_area", "HSlider", _sb(C_INK, 6, 0, C_LINE, 4))
	th.set_stylebox("grabber_area_highlight", "HSlider", _sb(C_BLUE, 6, 0, C_LINE, 4))
	var g := Image.create(46, 46, false, Image.FORMAT_RGBA8)
	g.fill(Color(0, 0, 0, 0))
	for x in 46:
		for y in 46:
			var d := Vector2(x - 22.5, y - 22.5).length()
			if d < 21:
				g.set_pixel(x, y, C_RED if d < 15 else C_INK)
	var gt := ImageTexture.create_from_image(g)
	th.set_icon("grabber", "HSlider", gt)
	th.set_icon("grabber_highlight", "HSlider", gt)
	th.set_constant("separation", "VBoxContainer", 12)
	th.set_constant("separation", "HBoxContainer", 10)
	var vsb := StyleBoxFlat.new()
	vsb.bg_color = Color(C_INK, 0.35)
	vsb.set_corner_radius_all(4)
	vsb.content_margin_left = 3
	vsb.content_margin_right = 3
	th.set_stylebox("grabber", "VScrollBar", vsb)
	th.set_stylebox("grabber_highlight", "VScrollBar", vsb)
	th.set_stylebox("grabber_pressed", "VScrollBar", vsb)
	th.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return th

# ================================================================ kâğıt dokuları (9-parça, prosedürel)

func _paper_tex(base: Color, radius := 8, shadow := 7, grain := 0.05, fiber := true) -> Texture2D:
	var key := "%s_%d_%d_%.2f_%s" % [base.to_html(), radius, shadow, grain, str(fiber)]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var inner := Rect2(shadow, shadow - 2, n - shadow * 2, n - shadow * 2)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			# yuvarlatılmış dikdörtgene mesafe
			var cx := clampf(p.x, inner.position.x + radius, inner.end.x - radius)
			var cy := clampf(p.y, inner.position.y + radius, inner.end.y - radius)
			var d := p.distance_to(Vector2(cx, cy)) - radius
			if d <= 0.0:
				var v := rng.randf_range(-grain, grain)
				var c := Color(base.r + v, base.g + v, base.b + v * 0.8, 1.0)
				# kenarlara doğru hafif koyulaşma (eskimiş kâğıt)
				var edge := minf(minf(p.x - inner.position.x, inner.end.x - p.x), minf(p.y - inner.position.y, inner.end.y - p.y))
				if edge < 6.0:
					c = c.darkened((6.0 - edge) / 6.0 * 0.06)
				c.a = clampf(-d + 0.5, 0.0, 1.0)
				img.set_pixel(x, y, c)
			else:
				# gölge
				var sh := pow(clampf(1.0 - d / float(shadow), 0.0, 1.0), 2.0) * 0.32
				img.set_pixel(x, y, Color(0, 0, 0, sh))
	if fiber:
		for i in 26:
			var x0 := rng.randi_range(shadow + 4, n - shadow - 14)
			var y0 := rng.randi_range(shadow + 4, n - shadow - 6)
			var c := img.get_pixel(x0, y0).darkened(0.05)
			for k in rng.randi_range(3, 8):
				if x0 + k < n - shadow:
					img.set_pixel(x0 + k, y0, c)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

func _paper_style(base: Color, pad := 18, radius := 8, shadow := 7) -> StyleBoxTexture:
	var st := StyleBoxTexture.new()
	st.texture = _paper_tex(base, radius, shadow)
	var m := float(radius + shadow + 2)
	st.texture_margin_left = m
	st.texture_margin_right = m
	st.texture_margin_top = m
	st.texture_margin_bottom = m
	st.expand_margin_left = shadow
	st.expand_margin_right = shadow
	st.expand_margin_top = shadow - 2
	st.expand_margin_bottom = shadow + 2
	st.content_margin_left = pad
	st.content_margin_right = pad
	st.content_margin_top = pad * 0.8
	st.content_margin_bottom = pad * 0.8
	st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return st

func _empty_box(px: int, py: int) -> StyleBoxEmpty:
	var e := StyleBoxEmpty.new()
	e.content_margin_left = px
	e.content_margin_right = px
	e.content_margin_top = py
	e.content_margin_bottom = py
	return e

# ================================================================ temel yardımcılar

func _lbl(text: String, sz := 24, col := C_INK, wrap := true, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _typed(text: String, sz := 22, col := C_INK, wrap := true) -> Label:
	return _lbl(text, sz, col, wrap, F_TYPE)

func _hand(text: String, sz := 30, col := C_BLUE, wrap := true) -> Label:
	return _lbl(text, sz, col, wrap, F_HAND)

func _head(text: String, sz := 30, col := C_INK, wrap := true) -> Label:
	return _lbl(text, sz, col, wrap, F_HEAD)

func _h(parent: Control, sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h

func _v(parent: Control, sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v

func _gap(parent: Control, h := 10.0) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)

func _press_fx(b: Control) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	if b is BaseButton:
		b.button_down.connect(func():
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2(0.96, 0.96), 0.07))
		b.button_up.connect(func():
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

# ================================================================ düğmeler

func _btn_styles(kind: String) -> Dictionary:
	## normal/hover/pressed stil + yazı rengi + yazı tipi boyutu
	match kind:
		"primary":
			return {"n": _sb(C_INK, 10, 0, C_LINE, 18, 4), "h": _sb(C_INK.lightened(0.1), 10, 0, C_LINE, 18, 4),
				"p": _sb(Color("#000000"), 10, 0, C_LINE, 18), "fc": C_CREAM, "fs": 28, "min": 80}
		"red":
			return {"n": _sb(C_RED, 10, 0, C_LINE, 18, 4), "h": _sb(C_RED.lightened(0.1), 10, 0, C_LINE, 18, 4),
				"p": _sb(C_RED.darkened(0.2), 10, 0, C_LINE, 18), "fc": C_CREAM, "fs": 28, "min": 80}
		"brass":
			return {"n": _sb(C_BRASS, 10, 0, C_LINE, 18, 6), "h": _sb(C_BRASS.lightened(0.1), 10, 0, C_LINE, 18, 6),
				"p": _sb(C_BRASS.darkened(0.15), 10, 0, C_LINE, 18), "fc": C_LEATHER, "fs": 28, "min": 80}
		"dark":
			return {"n": _sb(Color(1, 1, 1, 0.06), 10, 1, Color(C_CREAM, 0.25), 16), "h": _sb(Color(1, 1, 1, 0.1), 10, 1, Color(C_CREAM, 0.35), 16),
				"p": _sb(Color(C_BRASS, 0.3), 10, 2, C_BRASS, 16), "fc": C_CREAM, "fs": 22, "min": 64}
		"toggle_on":
			return {"n": _sb(C_HL, 10, 2, C_INK, 12), "h": _sb(C_HL, 10, 2, C_INK, 12),
				"p": _sb(C_HL.darkened(0.1), 10, 2, C_INK, 12), "fc": C_INK, "fs": 21, "min": 58}
		"ghost":
			return {"n": _sb(Color(0, 0, 0, 0), 10, 1, Color(C_INK, 0.35), 12), "h": _sb(Color(C_INK, 0.05), 10, 1, Color(C_INK, 0.5), 12),
				"p": _sb(C_HL, 10, 2, C_INK, 12), "fc": C_INK, "fs": 21, "min": 58}
		"danger":
			return {"n": _sb(Color(C_RED, 0.06), 10, 2, C_RED, 12), "h": _sb(Color(C_RED, 0.1), 10, 2, C_RED, 12),
				"p": _sb(Color(C_RED, 0.2), 10, 2, C_RED, 12), "fc": C_RED, "fs": 21, "min": 58}
	# small (varsayılan)
	return {"n": _sb(C_CARD, 10, 2, C_INK, 12), "h": _sb(Color("#fffaf0"), 10, 2, C_INK, 12),
		"p": _sb(C_HL, 10, 2, C_INK, 12), "fc": C_INK, "fs": 21, "min": 58}

func _btn(text: String, cb: Callable, kind := "small", parent: Control = null, icon := "") -> Button:
	var b := Button.new()
	b.text = text
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	if text.length() > 22:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var st := _btn_styles(kind)
	b.custom_minimum_size = Vector2(0, st.min)
	b.add_theme_stylebox_override("normal", st.n)
	b.add_theme_stylebox_override("hover", st.h)
	b.add_theme_stylebox_override("pressed", st.p)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, st.fc)
	b.add_theme_font_size_override("font_size", st.fs)
	if icon != "":
		var isz := 30 if st.fs >= 26 else 26
		var ic = Icon.new().setup(icon, st.fc, isz)
		b.add_child(ic)
		b.resized.connect(func(): ic.position = Vector2(16, (b.size.y - isz) / 2.0))
		var padl := 16 + isz + 10
		for s in ["normal", "hover", "pressed"]:
			var sbx = b.get_theme_stylebox(s)
			var c2 = sbx.duplicate()
			c2.content_margin_left = maxf(c2.content_margin_left, padl)
			b.add_theme_stylebox_override(s, c2)
	b.pressed.connect(func():
		if _dragged or _busy:
			return
		cb.call())
	_press_fx(b)
	if parent:
		parent.add_child(b)
	return b

func _expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

# ================================================================ kartlar ve yüzeyler

func _card(parent: Control = null, kind := "card", pad := 18) -> VBoxContainer:
	## kind: card (fiş kartı) | paper | manila | memo (çizgili not) | dark
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	match kind:
		"manila":
			pc.add_theme_stylebox_override("panel", _paper_style(C_MANILA, pad, 6, 6))
		"paper":
			pc.add_theme_stylebox_override("panel", _paper_style(C_PAPER, pad, 6, 6))
		"dark":
			pc.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.06, 0.05, 0.82), 12, 1, Color(C_CREAM, 0.15), pad, 6))
		"hl":
			pc.add_theme_stylebox_override("panel", _paper_style(Color("#fbf0bd"), pad, 6, 6))
		_:
			pc.add_theme_stylebox_override("panel", _paper_style(C_CARD, pad, 6, 6))
	if kind == "memo":
		var lines := Control.new()
		lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.draw.connect(func():
			var y := 46.0
			while y < lines.size.y - 6:
				lines.draw_line(Vector2(4, y), Vector2(lines.size.x - 4, y), Color(C_BLUE, 0.12), 1.0)
				y += 34.0
			lines.draw_line(Vector2(36, 0), Vector2(36, lines.size.y), Color(C_RED, 0.25), 1.5))
		pc.add_child(lines)
		lines.resized.connect(lines.queue_redraw)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	(parent if parent else page).add_child(pc)
	return v

func _card_panel(v: VBoxContainer) -> PanelContainer:
	return v.get_parent() as PanelContainer

func _accent_top(v: VBoxContainer, col: Color) -> void:
	## Kartın üstüne renkli şerit (kulüp rengi vb.)
	var pc := _card_panel(v)
	var strip := Control.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.draw.connect(func():
		strip.draw_rect(Rect2(-4, -10, strip.size.x + 8, 6), col, true))
	pc.add_child(strip)
	pc.move_child(strip, 0)

func _title(text: String, parent: Control = null, sz := 40, icon := "") -> Label:
	## Sayfa başlığı: kalın baskı + fosforlu kalem çizgisi
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	if icon != "":
		var ic = Icon.new().setup(icon, C_INK, sz * 0.8)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var l := _lbl(text.to_upper(), sz, C_INK, false, F_HEAD)
	var hl := Control.new()
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl.show_behind_parent = true
	l.add_child(hl)
	hl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hl.draw.connect(func():
		var w: float = l.get_minimum_size().x
		var y0 := hl.size.y * 0.55
		var pts := PackedVector2Array([Vector2(-6, y0 + 2), Vector2(w + 8, y0 - 3), Vector2(w + 4, hl.size.y - 4), Vector2(-4, hl.size.y - 1)])
		hl.draw_colored_polygon(pts, Color(C_HL, 0.8)))
	h.add_child(l)
	(parent if parent else page).add_child(h)
	return l

func _section(text: String, parent: Control = null, icon := "") -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	if icon != "":
		var ic = Icon.new().setup(icon, C_RED, 24)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	h.add_child(_lbl(text.to_upper(), 22, C_INK, true, F_HEAD))
	v.add_child(h)
	v.add_child(_dash_rule(Color(C_INK, 0.35)))
	(parent if parent else page).add_child(v)

func _dash_rule(col := Color(0.15, 0.12, 0.08, 0.25)) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 6)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var x := 0.0
		while x < c.size.x:
			c.draw_line(Vector2(x, 3), Vector2(minf(x + 8, c.size.x), 3), col, 1.5)
			x += 13.0)
	return c

func _rule(parent: Control) -> void:
	parent.add_child(_dash_rule())

func _kv(parent: Control, key: String, value: String, vcol := C_INK) -> void:
	## anahtar ..... değer (daktilo)
	var h := _h(parent, 6)
	var k := _lbl(key, 20, C_INK2, false, F_TYPE)
	h.add_child(k)
	var dots := Control.new()
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dots.custom_minimum_size = Vector2(20, 20)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.draw.connect(func():
		var x := 4.0
		while x < dots.size.x - 4:
			dots.draw_circle(Vector2(x, dots.size.y * 0.72), 1.1, Color(C_INK, 0.3))
			x += 8.0)
	h.add_child(dots)
	h.add_child(_lbl(value, 21, vcol, false, F_TYPEB))

func _chip(text: String, col: Color, parent: Control, filled := false) -> Label:
	var l := _lbl(text, 17, C_CARD if filled else col, false, F_HEAD)
	l.add_theme_stylebox_override("normal", _sb(col if filled else Color(col, 0.08), 6, 0 if filled else 2, col, 8))
	parent.add_child(l)
	return l

func _bar(parent: Control, frac: float, col: Color, h := 12.0) -> Control:
	## Mürekkep çubuğu: çizgili zemin + dolgu, animasyonlu
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var state := {"f": 0.0}
	c.draw.connect(func():
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(C_INK, 0.07), true)
		var x := 0.0
		while x < c.size.x:
			c.draw_line(Vector2(x, c.size.y), Vector2(x + c.size.y, 0), Color(C_INK, 0.08), 1.0)
			x += 6.0
		c.draw_rect(Rect2(Vector2.ZERO, Vector2(c.size.x * state.f, c.size.y)), col, true)
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(C_INK, 0.5), false, 1.0))
	parent.add_child(c)
	var tw := c.create_tween()
	tw.tween_method(func(v):
		state.f = v
		c.queue_redraw(), 0.0, clampf(frac, 0.0, 1.0), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return c

func _crest(c: Dictionary, sz := 44.0) -> Control:
	return Crest.new().setup(c, sz, F_HEAD)

func _avatar(p: Dictionary, sz := 64.0) -> Control:
	return Avatar.new().setup(p, Game.club(p.get("club", "")), sz)

func _empty(parent: Control, icon: String, text: String) -> void:
	var v := _card(parent, "memo")
	var h := _h(v)
	var ic = Icon.new().setup(icon, C_INK2, 44)
	h.add_child(ic)
	h.add_child(_hand(text, 28, C_INK2))

# ================================================================ dosya öğeleri

class Tilt extends Control:
	## Container içinde döndürülmüş öğe (container dönüşü sıfırladığı için sarmalayıcı)
	var child: Control
	var deg := 0.0
	func setup(c: Control, d: float) -> Tilt:
		child = c
		deg = d
		mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(c)
		resized.connect(_fit)
		c.minimum_size_changed.connect(func(): custom_minimum_size = child.get_combined_minimum_size())
		custom_minimum_size = c.get_combined_minimum_size()
		return self
	func _fit() -> void:
		child.size = size
		child.position = Vector2.ZERO
		child.pivot_offset = size / 2.0
		child.rotation_degrees = deg

func _tilt(c: Control, deg: float) -> Control:
	return Tilt.new().setup(c, deg)

func _stamp(text: String, col := C_RED, deg := -9.0, sz := 30) -> Control:
	## Lastik mühür: çift çerçeve, eskitilmiş mürekkep
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := text.to_upper()
	var w := F_STAMP.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + 34
	c.custom_minimum_size = Vector2(w, sz + 26)
	var seed := hash(text)
	c.draw.connect(func():
		var r := Rect2(Vector2(3, 3), c.size - Vector2(6, 6))
		var ink := Color(col, 0.82)
		c.draw_rect(r, ink, false, 3.0)
		c.draw_rect(r.grow(-6), ink, false, 1.5)
		c.draw_string(F_STAMP, Vector2(17, c.size.y / 2.0 + sz * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, ink)
		# mürekkep boşlukları
		var rr := RandomNumberGenerator.new()
		rr.seed = seed
		for i in 22:
			var p := Vector2(rr.randf_range(0, c.size.x), rr.randf_range(0, c.size.y))
			c.draw_circle(p, rr.randf_range(0.8, 2.4), Color(C_CARD, 0.75)))
	return _tilt(c, deg)

func _stamp_slam(st: Control) -> void:
	## Mühür vurma animasyonu
	st.pivot_offset = st.custom_minimum_size / 2.0
	st.scale = Vector2(2.2, 2.2)
	st.modulate.a = 0.0
	var tw := st.create_tween().set_parallel(true)
	tw.tween_property(st, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(st, "modulate:a", 1.0, 0.12)

func _polaroid(p: Dictionary, w := 200.0, caption := "", deg := 0.0, tape := true) -> Control:
	## Polaroid fotoğraf: avatar + el yazısı altyazı + bant
	var pc := PanelContainer.new()
	var st := _sb(Color("#fbfaf6"), 3, 0, C_LINE, 10, 6)
	st.content_margin_bottom = 12
	pc.add_theme_stylebox_override("panel", st)
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	var photo := PanelContainer.new()
	photo.add_theme_stylebox_override("panel", _sb(Color(Game.club(p.get("club", "")).get("c1", "#556655")).darkened(0.35), 0, 0, C_LINE, 0))
	var av := _avatar(p, w - 20)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	photo.add_child(av)
	v.add_child(photo)
	var cap := _hand(caption if caption != "" else Game.short_name(p), 28, C_INK, false)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.clip_text = true
	cap.custom_minimum_size = Vector2(w - 20, 0)
	v.add_child(cap)
	if tape:
		var tp := Control.new()
		tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tp.draw.connect(func():
			var cx := tp.size.x / 2.0
			var pts := PackedVector2Array([Vector2(cx - 38, -12), Vector2(cx + 36, -16), Vector2(cx + 38, 10), Vector2(cx - 36, 14)])
			tp.draw_colored_polygon(pts, Color(0.95, 0.92, 0.75, 0.55)))
		pc.add_child(tp)
	return _tilt(pc, deg) if deg != 0.0 else pc

func _ticket(parent: Control, col := C_CARD, accent := C_RED) -> HBoxContainer:
	## Bilet kartı: solda koçan (renkli), delikli ayırıcı, sağda içerik
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _paper_style(col, 14, 6, 6))
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var deco := Control.new()
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func():
		deco.draw_rect(Rect2(-8, -8, 14, deco.size.y + 16), accent, true)
		var x := 96.0
		var y := 0.0
		while y < deco.size.y:
			deco.draw_line(Vector2(x, y), Vector2(x, y + 6), Color(C_INK, 0.35), 1.5)
			y += 11.0
		deco.draw_circle(Vector2(x, -9), 8, C_PAPER.darkened(0.1))
		deco.draw_circle(Vector2(x, deco.size.y + 9), 8, C_PAPER.darkened(0.1)))
	pc.add_child(deco)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	pc.add_child(h)
	parent.add_child(pc)
	return h

func _clip_deco(parent_panel: Control) -> void:
	## Ataş (sağ üst) — panel kabı onu tam boyuta yayar, sağa göre çiziyoruz
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var o := Vector2(c.size.x - 56, -26)
		var col := Color("#8c8f96")
		c.draw_arc(o + Vector2(15, 14), 10, PI, TAU, 16, col, 3.0, true)
		c.draw_line(o + Vector2(5, 14), o + Vector2(5, 62), col, 3.0, true)
		c.draw_line(o + Vector2(25, 14), o + Vector2(25, 54), col, 3.0, true)
		c.draw_arc(o + Vector2(10, 62), 5, 0, PI, 10, col, 3.0, true)
		c.draw_line(o + Vector2(15, 62), o + Vector2(15, 24), col, 3.0, true))
	parent_panel.add_child(c)

# ================================================================ klasör sekmeleri

func _tabs(parent: Control, items: Array, cur: String, cb: Callable) -> Control:
	## items: [[anahtar, etiket], ...] — aktif sekme kâğıtla birleşir
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		var key: String = it[0]
		var on := key == cur
		var b := Button.new()
		b.text = it[1]
		b.flat = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 62 if on else 56)
		b.size_flags_vertical = Control.SIZE_SHRINK_END
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.clip_text = true
		b.add_theme_font_override("font", F_HEAD)
		b.add_theme_font_size_override("font_size", 20 if items.size() > 3 else 22)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, C_INK if on else Color(C_INK, 0.65))
		for s in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(s, _empty_box(6, 4))
		var bg := Control.new()
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.show_behind_parent = true
		b.add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var fill := C_PAPER if on else C_MANILA.darkened(0.04)
		bg.draw.connect(func():
			var w := bg.size.x
			var hh := bg.size.y + (8 if on else 0)
			var pts := PackedVector2Array()
			var slope := 12.0
			pts.append(Vector2(0, hh))
			pts.append(Vector2(slope * 0.6, 8))
			pts.append(Vector2(slope, 0))
			pts.append(Vector2(w - slope, 0))
			pts.append(Vector2(w - slope * 0.6, 8))
			pts.append(Vector2(w, hh))
			bg.draw_colored_polygon(pts, fill)
			var outline := pts.duplicate()
			bg.draw_polyline(outline, Color(C_INK, 0.25 if on else 0.18), 1.5, true)
			if on:
				bg.draw_line(Vector2(slope + 6, 6), Vector2(w - slope - 6, 6), Color(C_RED, 0.8), 3.0))
		b.pressed.connect(func():
			if _dragged:
				return
			cb.call(key))
		row.add_child(b)
	parent.add_child(row)
	return row

# ================================================================ küçük göstergeler

func _pos_short(pos: String) -> String:
	return pos if T.lang == "en" else {"GK": "KL", "CB": "STP", "LB": "SLB", "RB": "SĞB", "DM": "ÖL", "CM": "MO", "AM": "OOS", "LW": "SLK", "RW": "SĞK", "ST": "SNT"}[pos]

func _pos_col(pos: String) -> Color:
	return {"GK": Color("#b7791f"), "DEF": C_BLUE, "MID": C_GREEN, "ATT": C_RED}[Data.POS_GROUP[pos]]

func _pos_badge(pos: String, parent: Control) -> void:
	var l := _chip(_pos_short(pos), _pos_col(pos), parent, true)
	l.custom_minimum_size = Vector2(58, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _fs(v: float) -> String:
	return str(int(v)) if v == floor(v) else "%.1f" % v

func _star_txt(r: Array) -> String:
	if r.is_empty():
		return "?"
	var a := Game.stars(r[0])
	var b := Game.stars(r[1])
	return ("%s★" % _fs(a)) if a == b else ("%s–%s★" % [_fs(a), _fs(b)])

func _stat_box(parent: Control, value: String, label: String, col := C_INK) -> void:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", -4)
	var vl := _lbl(value, 34, col, false, F_HEAD)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(vl)
	var tl := _lbl(label.to_upper(), 15, C_INK2, false, F_TYPEB)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	parent.add_child(v)

func _row_button(parent: Control, h := 96.0, kind := "card") -> Array:
	## Tıklanabilir satır: [Button, iç HBox]
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, h)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var base := C_CARD if kind == "card" else (Color("#fbf0bd") if kind == "hl" else C_PAPER)
	b.add_theme_stylebox_override("normal", _paper_style(base, 12, 6, 5))
	b.add_theme_stylebox_override("hover", _paper_style(base.lightened(0.03), 12, 6, 5))
	b.add_theme_stylebox_override("pressed", _paper_style(C_HL, 12, 6, 5))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var inner := HBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 14
	inner.offset_right = -14
	inner.add_theme_constant_override("separation", 12)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)
	_press_fx(b)
	parent.add_child(b)
	return [b, inner]

func _ignore_all(c: Node) -> void:
	if c is Control:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		_ignore_all(ch)
