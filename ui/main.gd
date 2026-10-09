extends "res://ui/kit.gd"
## GÖZCÜ v0.8 arayüzü — "scout dosyası". Deri kaplı üst/alt bar, 3D ofis arka planı,
## kâğıt sayfalar, klasör alt sekmeleri. Tüm ekranlar koddan kurulur.

const TrMap = preload("res://ui/map.gd")
const MatchView = preload("res://three/match_view.gd")
const Hub3D = preload("res://three/hub3d.gd")
const Stage3D = preload("res://three/stage3d.gd")
const VERSION := "v0.20"

var bg: ColorRect
var hub
var hero_node: Control
var shade: TextureRect
var root: VBoxContainer
var topbar: PanelContainer
var top_box: VBoxContainer
var holder: Control
var scroll: ScrollContainer
var outer: VBoxContainer
var navbar: PanelContainer
var nav_row: HBoxContainer
var nav_pill: Panel
var toast: PanelContainer
var toast_lbl: Label
var toast_t := 0.0
var viewer: Control = null

var stack: Array = []
var cur_tab := "home"
var sub := {"home": "summary", "week": "this", "tasks": "requests", "players": "shortlist", "news": "news",
	"player": "file", "club": "squad", "match": "h", "team": "staff"}
var search_f := {"tier": 0, "grp": "", "max_age": 99, "sort": "rating", "known": false, "youth_only": false}
var players_mode := "shortlist"
var week_tier := 0
var week_lg := ""
var ng_country := "TR"
var table_lg := ""
var fix_lg := ""
var fix_round := -1
var news_filter := ""
var compare: Array = []
var pending_result: Dictionary = {}
var pending_obs: Dictionary = {}
var shown_vals := {}
var _press_pos := Vector2.ZERO
var _no_anim := false

# ================================================================ kurulum

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_fonts()
	theme = _make_theme()
	_build_shell()
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)
	if Game.has_save() and Game.load_game():
		T.lang = Game.s.get("lang", "tr")
	var crashed := FileAccess.file_exists(Game.CRASH_FLAG)
	_set_flag(true)
	if crashed:
		_show("crash", null, false)
		return
	_show("title", null, false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if viewer != null:
			return
		if stack.size() > 1:
			_back()
		elif not stack.is_empty() and stack[-1][0] != "title" and stack[-1][0] != "home" and Game.s.get("scout", {}).get("club_id", "") != "":
			_goto_tab("home")
		else:
			if not Game.s.is_empty():
				Game.save_game()
			_set_flag(false)
			get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_set_flag(false)
		if not Game.s.is_empty() and Game.s.scout.club_id != "":
			Game.save_game()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_set_flag(true)

var _sd_active := false
var _sd_moved := false
var _sd_start := Vector2.ZERO
var _sd_vel := 0.0
var _sd_acc := 0.0

func _input(ev: InputEvent) -> void:
	## Kendi sürükle-kaydır: dokunma hangi denetime düşerse düşsün sayfa kayar
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_press_pos = ev.position
	if viewer != null:
		return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_sd_active = holder.get_global_rect().has_point(ev.position) or _modal_scroll != null
			_sd_start = ev.position
			_sd_moved = false
			_sd_vel = 0.0
			_sd_acc = 0.0
			_dragged = false
		else:
			_sd_active = false
	elif ev is InputEventScreenDrag and _sd_active:
		if not _sd_moved and absf(ev.position.y - _sd_start.y) > 16.0:
			_sd_moved = true
			_dragged = true
		if _sd_moved:
			_sd_acc -= ev.relative.y
			var step := int(_sd_acc)
			_sd_acc -= step
			if _modal_scroll != null and is_instance_valid(_modal_scroll):
				_modal_scroll.scroll_vertical += step
			else:
				scroll.scroll_vertical += step
			_sd_vel = lerpf(_sd_vel, -ev.velocity.y, 0.5)

var _safe_t := 0.0

func _process(delta: float) -> void:
	_hub_band()
	# güvenlik ağı: sahne hatayla yarıda kalırsa arayüz görünmez/kilitli kalmasın
	_scene_tick()
	_safe_t += delta
	if _safe_t > 1.0:
		_safe_t = 0.0
		if root and not root.visible and dlg_layer == null and viewer == null:
			Watch.bc("guvenlik: arayuz geri acildi")
			root.visible = true
			_busy = false
			_refresh()
	if not _sd_active and absf(_sd_vel) > 20.0 and viewer == null:
		scroll.scroll_vertical += int(_sd_vel * delta)
		_sd_vel *= exp(-3.5 * delta)
	elif not _sd_active:
		_sd_vel = 0.0
	if toast_t > 0:
		toast_t -= delta
		if toast_t <= 0:
			var tw := create_tween()
			tw.tween_property(toast, "modulate:a", 0.0, 0.25)
			tw.tween_callback(func(): toast.visible = false)

# ================================================================ iskelet

func _leather_style(pad_x := 16, pad_y := 12) -> StyleBoxFlat:
	var sb := _sb(C_LEATHER, 0, 0, C_LINE, pad_x)
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb

func _stitch(panel: Control, top: bool) -> void:
	## Deri üzerine dikiş çizgisi
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var y := 7.0 if top else c.size.y - 7.0
		var x := 6.0
		while x < c.size.x:
			c.draw_line(Vector2(x, y), Vector2(x + 9, y), Color(C_BRASS, 0.45), 1.5)
			x += 16.0
		# deri dokusu: ince nokta deseni
		var rr := RandomNumberGenerator.new()
		rr.seed = 7
		for i in 140:
			c.draw_circle(Vector2(rr.randf() * c.size.x, rr.randf() * c.size.y), rr.randf_range(0.6, 1.4), Color(0, 0, 0, 0.18)))
	panel.add_child(c)
	panel.move_child(c, 0)
	c.resized.connect(c.queue_redraw)

func _build_shell() -> void:
	bg = ColorRect.new()
	bg.color = C_DESK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	hub = Hub3D.new()
	add_child(hub)
	hub.setup_font(F_HEAD)
	shade = TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0.05, 0.035, 0.025, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.25)
	gt.fill_to = Vector2(0, 0.75)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	root = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	var safe_top := 0
	if OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var scr := DisplayServer.screen_get_size()
		if scr.y > 0:
			safe_top = int(float(sa.position.y) / float(scr.y) * get_viewport_rect().size.y)
		safe_top = max(safe_top, 26)
	var sp := ColorRect.new()
	sp.color = C_LEATHER
	sp.custom_minimum_size = Vector2(0, safe_top)
	sp.name = "SafeTop"
	root.add_child(sp)
	topbar = PanelContainer.new()
	topbar.add_theme_stylebox_override("panel", _leather_style(18, 12))
	_stitch(topbar, false)
	top_box = VBoxContainer.new()
	top_box.add_theme_constant_override("separation", 8)
	topbar.add_child(top_box)
	root.add_child(topbar)
	holder = Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	root.add_child(holder)
	scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 100000
	holder.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 30)
	scroll.add_child(margin)
	outer = VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 0)
	margin.add_child(outer)
	page = outer
	navbar = PanelContainer.new()
	navbar.add_theme_stylebox_override("panel", _leather_style(6, 6))
	_stitch(navbar, true)
	var nav_stack := Control.new()
	nav_stack.custom_minimum_size = Vector2(0, 92)
	navbar.add_child(nav_stack)
	nav_pill = Panel.new()
	var pill := _sb(Color(C_BRASS, 0.22), 14, 2, Color(C_BRASS, 0.85), 4)
	nav_pill.add_theme_stylebox_override("panel", pill)
	nav_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_stack.add_child(nav_pill)
	nav_row = HBoxContainer.new()
	nav_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nav_row.add_theme_constant_override("separation", 0)
	nav_stack.add_child(nav_row)
	root.add_child(navbar)
	var bsafe := ColorRect.new()
	bsafe.color = C_LEATHER
	bsafe.custom_minimum_size = Vector2(0, 18 if OS.has_feature("mobile") else 0)
	root.add_child(bsafe)
	_build_nav()
	toast = PanelContainer.new()
	toast.add_theme_stylebox_override("panel", _paper_style(Color("#fbf0bd"), 20, 4, 8))
	toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toast.offset_left = 34
	toast.offset_right = -34
	toast.offset_top = 150
	toast.visible = false
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_lbl = _hand("", 30, C_INK)
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(toast_lbl)
	add_child(toast)

func _build_nav() -> void:
	for tab in [["home", "home"], ["week", "calendar"], ["tasks", "task"], ["players", "people"], ["team", "team"], ["news", "news"]]:
		var b := Button.new()
		b.flat = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Icon.new().setup(tab[1], C_CREAM2, 34)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var l := _lbl(T.t("tab_" + tab[0]).to_upper(), 16, C_CREAM2, false, F_HEADR)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		var badge := Control.new()
		badge.name = "B"
		badge.visible = false
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		b.add_child(badge)
		b.set_meta("tab", tab[0])
		b.set_meta("icon", ic)
		b.set_meta("label", l)
		var name: String = tab[0]
		b.pressed.connect(func(): _goto_tab(name))
		nav_row.add_child(b)

func _refresh_nav(animate := true) -> void:
	var open := 0
	for a in Game.s.get("assign", []):
		if a.status == "open":
			open += 1
	for b in nav_row.get_children():
		var on: bool = b.get_meta("tab") == cur_tab
		b.get_meta("icon").set_color(C_BRASS if on else C_CREAM2)
		var l: Label = b.get_meta("label")
		l.text = T.t("tab_" + b.get_meta("tab")).to_upper()
		l.add_theme_color_override("font_color", C_CREAM if on else C_CREAM2)
		if b.get_meta("tab") == "tasks":
			var bd: Control = b.get_node("B")
			bd.visible = open > 0
			for ch in bd.get_children():
				ch.queue_free()
			if open > 0:
				# kırmızı mühür mumu
				var seal := Control.new()
				seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var n := open
				seal.draw.connect(func():
					seal.draw_circle(Vector2(14, 14), 14, C_RED)
					seal.draw_arc(Vector2(14, 14), 11, 0, TAU, 20, Color(1, 1, 1, 0.25), 1.5, true)
					var t := str(n)
					var w := F_HEAD.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
					seal.draw_string(F_HEAD, Vector2(14 - w / 2.0, 20), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, C_CREAM))
				bd.add_child(seal)
				bd.position = Vector2(b.size.x / 2.0 + 10, 6)
	await get_tree().process_frame
	for b in nav_row.get_children():
		if b.get_meta("tab") == "tasks":
			b.get_node("B").position = Vector2(b.size.x / 2.0 + 10, 6)
		if b.get_meta("tab") == cur_tab:
			var r := Rect2(b.position + Vector2(12, 6), b.size - Vector2(24, 12))
			if animate and nav_pill.size.x > 1:
				var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(nav_pill, "position", r.position, 0.3)
				tw.tween_property(nav_pill, "size", r.size, 0.3)
			else:
				nav_pill.position = r.position
				nav_pill.size = r.size

func _refresh_topbar() -> void:
	for c in top_box.get_children():
		c.queue_free()
	var sc: Dictionary = Game.s.scout
	var row := _h(top_box)
	row.add_child(_id_badge(sc.name, 56))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -4)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(_lbl(String(sc.name).to_upper(), 24, C_CREAM, false, F_HEAD))
	var mc := Game.my_club()
	nv.add_child(_lbl(T.t(Game.title_key()) + "  •  " + mc.get("name", ""), 17, C_BRASS, false, F_SEMI))
	row.add_child(nv)
	# hafta etiketi (bagaj etiketi)
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", _paper_style(C_MANILA, 12, 4, 4))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -6)
	tag.add_child(tv)
	var wk := T.t("preseason_short") if Game.s.week == 0 else T.t("week_n", [Game.s.week])
	var wl := _lbl(wk.to_upper(), 20, C_INK, false, F_HEAD)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(wl)
	var sl := _lbl("%d/%02d%s" % [Game.s.season, (Game.s.season + 1) % 100, ("  •  " + T.t("window_short")) if Game.in_window() else ""], 14, C_RED if Game.in_window() else C_INK2, false, F_TYPEB)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(sl)
	row.add_child(_tilt(tag, 3.0))
	var stats := _h(top_box, 8)
	var fat := int(sc.fatigue)
	_stat_pill(stats, "star", "rep", float(sc.rep), "%d", C_BRASS)
	_stat_pill(stats, "wallet", "money", float(sc.money), "€", C_CREAM)
	_stat_pill(stats, "calendar", "days", float(Game.free_days()), "%d/5", Color("#8fc1e8"))
	_stat_pill(stats, "bolt", "fat", float(fat), "%d%%", Color("#7fd28f") if fat < 40 else (C_BRASS if fat < 70 else Color("#ff8a7a")))

func _id_badge(name: String, sz: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(sz, sz)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parts := name.split(" ", false)
	var ini := ""
	for p in parts.slice(0, 2):
		ini += p.substr(0, 1)
	c.draw.connect(func():
		var ctr := c.size / 2.0
		c.draw_circle(ctr, sz / 2.0, C_BRASS)
		c.draw_circle(ctr, sz / 2.0 - 3, C_LEATHER2)
		c.draw_arc(ctr, sz / 2.0 - 7, 0, TAU, 32, Color(C_BRASS, 0.5), 1.0, true)
		var fs := int(sz * 0.4)
		var w := F_HEAD.get_string_size(ini, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string(F_HEAD, Vector2(ctr.x - w / 2.0, ctr.y + fs * 0.36), ini, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_BRASS))
	return c

func _stat_pill(parent: Control, icon: String, key: String, val: float, fmt: String, col: Color) -> void:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.28), 8, 1, Color(C_BRASS, 0.3), 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	pc.add_child(h)
	h.add_child(Icon.new().setup(icon, col, 22))
	var l := _lbl("", 22, col, false, F_HEAD)
	h.add_child(l)
	if key == "fat":
		var sub := _lbl(T.t("fat_short"), 13, Color(col, 0.8), false, F_SEMI)
		sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(sub)
	parent.add_child(pc)
	# dokununca ne işe yaradığını anlat
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.gui_input.connect(func(e):
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _dragged:
			_stat_info(key))
	var prev: float = shown_vals.get(key, val)
	shown_vals[key] = val
	var setter := func(v: float):
		if fmt == "€":
			l.text = Game.money_str(v)
		else:
			l.text = fmt % int(round(v))
	setter.call(prev)
	if absf(prev - val) > 0.01:
		var tw := create_tween()
		tw.tween_method(setter, prev, val, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		pc.pivot_offset = Vector2(60, 20)
		var tw2 := create_tween()
		tw2.tween_property(pc, "scale", Vector2(1.08, 1.08), 0.12)
		tw2.tween_property(pc, "scale", Vector2.ONE, 0.25)

func _stat_info(key: String) -> void:
	var sc: Dictionary = Game.s.scout
	var txt := ""
	match key:
		"rep":
			txt = T.t("info_rep", [int(sc.rep)])
		"money":
			txt = T.t("info_money", [Game.money_str(sc.money), Game.money_str(sc.salary), Game.money_str(maxi(0, int(sc.budget) - int(sc.spent)))])
		"days":
			txt = T.t("info_days", [Game.free_days()])
		"fat":
			var loss := int(round((1.0 - Game.fatigue_factor()) * 100.0))
			txt = T.t("info_fat", [int(sc.fatigue), loss])
	await _confirm(txt, T.t("ok_got_it"), T.t("close"))

signal _confirm_done(v: bool)

## Evet/Hayır onay kutusu
func _confirm(text: String, yes: String, no: String) -> bool:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _paper_style(C_CARD, 26, 8, 8))
	card.anchor_left = 0.0
	card.anchor_right = 1.0
	card.anchor_top = 0.35
	card.offset_left = 36
	card.offset_right = -36
	layer.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	v.add_child(_lbl(text, 24, C_INK, true, F_BODY))
	var was := _busy
	_busy = false
	_btn(yes, func(): _confirm_done.emit(true), "primary", v, "check")
	_btn(no, func(): _confirm_done.emit(false), "ghost", v, "cross")
	var r: bool = await _confirm_done
	_busy = was
	layer.queue_free()
	return r

signal _pick_done(key: String)
var _modal_scroll: ScrollContainer = null

func _pick_list(title: String, items: Array, cur := "") -> String:
	## Kaydırılabilir seçim listesi. items: [[anahtar, metin, (alt metin)]]. İptal -> ""
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _paper_style(C_CARD, 22, 8, 8))
	card.anchor_left = 0.0
	card.anchor_right = 1.0
	card.anchor_top = 0.08
	card.anchor_bottom = 0.92
	card.offset_left = 24
	card.offset_right = -24
	layer.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var hh := _h(v)
	var tl := _head(title.to_upper(), 30)
	hh.add_child(tl)
	var was := _busy
	_busy = false
	var xb := _btn("", func(): _pick_done.emit(""), "ghost", hh, "cross")
	xb.custom_minimum_size = Vector2(66, 58)
	xb.size_flags_horizontal = Control.SIZE_SHRINK_END
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 100000
	v.add_child(sc)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 8)
	sc.add_child(lv)
	var cur_btn: Control = null
	for it in items:
		var k: String = it[0]
		var txt: String = it[1]
		if it.size() > 2 and str(it[2]) != "":
			txt += "  •  " + str(it[2])
		var b := _btn(txt, func(): _pick_done.emit(k), "toggle_on" if k == cur else "small", lv)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if k == cur:
			cur_btn = b
	_modal_scroll = sc
	if cur_btn:
		(func():
			await get_tree().process_frame
			if is_instance_valid(sc) and is_instance_valid(cur_btn):
				sc.scroll_vertical = int(maxf(0.0, cur_btn.position.y - 200.0))).call()
	var r: String = await _pick_done
	_modal_scroll = null
	_busy = was
	layer.queue_free()
	return r

func _country_items(playable := true) -> Array:
	var out := []
	for cc in (Data.playable_countries() if playable else Data.COUNTRY_ORDER):
		var c: Dictionary = Data.COUNTRIES[cc]
		var n := 0
		for lg in c.leagues:
			n += 1
		out.append([cc, Data.country_name(cc), T.t("trip_pick") if Data.is_scout_cc(cc) else T.t("n_leagues", [c.tiers.size()])])
	return out

func _toast(text: String) -> void:
	toast_lbl.text = text
	toast.visible = true
	toast.modulate.a = 0.0
	toast.rotation_degrees = -1.5
	toast.position.y = 120
	var tw := create_tween().set_parallel(true)
	tw.tween_property(toast, "modulate:a", 1.0, 0.2)
	tw.tween_property(toast, "position:y", 150.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	toast_t = 3.0

# ================================================================ gezinme

const HERO := {"team": 210, "home": 250, "week": 300, "tasks": 190, "players": 230, "player": 330, "report": 200, "news": 170,
	"table": 160, "club": 200, "match": 170, "newgame": 230, "offers": 200, "result": 150, "season": 170, "obs": 150}

func _show(screen: String, arg = null, push := true, dir := 1) -> void:
	print("[BC] ekran: ", screen)
	Watch.bc("ekran " + str(screen))
	if push:
		stack.append([screen, arg])
	else:
		stack = [[screen, arg]]
	for c in outer.get_children():
		c.queue_free()
	page = outer
	scroll.scroll_vertical = 0
	var chrome := not (screen in ["title", "newgame", "offers", "result", "season", "obs", "crash"])
	topbar.visible = chrome
	navbar.visible = chrome
	root.get_node("SafeTop").color = C_LEATHER if chrome else Color(0, 0, 0, 0)
	shade.visible = screen != "title"
	_hub_for(screen, arg)
	if hub:
		hub.set_pitch(15.0 if chrome else 4.0)
	if HERO.has(screen):
		var hero := Control.new()
		hero.custom_minimum_size = Vector2(0, HERO[screen])
		hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_child(hero)
		hero_node = hero
	else:
		hero_node = null
		if hub:
			hub.set_band(Rect2())
	if chrome:
		_refresh_topbar()
		_refresh_nav()
	match screen:
		"title": _scr_title()
		"newgame": _scr_newgame()
		"offers": _scr_offers()
		"home": _scr_home()
		"week": _scr_week()
		"match": _scr_match_plan(arg)
		"tasks": _scr_tasks()
		"players": _scr_players()
		"player": _scr_player(arg)
		"report": _scr_report(arg)
		"news": _scr_news()
		"team": _scr_team()
		"table": _scr_table()
		"club": _scr_club(arg)
		"result": _scr_result()
		"obs": _scr_obs()
		"season": _scr_season()
		"crash": _scr_crash()
		"trip": _scr_trip()
	_fix_filters(outer)
	if viewer == null:
		Sfx.music_on()
	if not _no_anim:
		_animate_in(dir)

func _fix_filters(n: Node) -> void:
	## Kaydırma için: etkileşimsiz denetimler dokunmayı ScrollContainer'a geçirmeli
	if n is Control and not (n is BaseButton or n is LineEdit or n is Range or n is ScrollContainer):
		if n.mouse_filter == Control.MOUSE_FILTER_STOP and n.gui_input.get_connections().is_empty():
			n.mouse_filter = Control.MOUSE_FILTER_PASS
	for c in n.get_children():
		_fix_filters(c)

func _sheet(items: Array = [], cur := "", cb := Callable(), kind := "paper") -> VBoxContainer:
	## Klasör sekmeleri + kâğıt sayfa. page bu sayfanın içine yönlenir.
	if not items.is_empty():
		_tabs(outer, items, cur, cb)
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _paper_style(C_PAPER if kind == "paper" else C_MANILA, 18, 4, 8))
	pc.custom_minimum_size = Vector2(0, maxf(500.0, get_viewport_rect().size.y * 0.55))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	pc.add_child(v)
	outer.add_child(pc)
	page = v
	return v

func _sub_cb(key: String) -> Callable:
	return func(k: String):
		sub[key] = k
		_refresh_soft()

func _animate_in(dir: int) -> void:
	scroll.offset_left = 40.0 * dir
	scroll.offset_right = 40.0 * dir
	scroll.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(scroll, "offset_left", 0.0, 0.3)
	tw.tween_property(scroll, "offset_right", 0.0, 0.3)
	tw.tween_property(scroll, "modulate:a", 1.0, 0.22)
	await get_tree().process_frame
	var i := 0
	for c in page.get_children():
		if not (c is Control) or i > 9:
			continue
		var ctl: Control = c
		ctl.modulate.a = 0.0
		var t2 := ctl.create_tween()
		t2.tween_property(ctl, "modulate:a", 1.0, 0.25).set_delay(0.035 * i)
		i += 1

func _back() -> void:
	if stack.size() > 1:
		stack.pop_back()
		var top = stack.pop_back()
		_show(top[0], top[1], true, -1)
	else:
		_goto_tab(cur_tab)

func _goto_tab(tab: String) -> void:
	cur_tab = tab
	stack = []
	_show(tab)

func _refresh() -> void:
	var sv := scroll.scroll_vertical
	var top = stack.pop_back()
	_no_anim = true
	_show(top[0], top[1])
	_no_anim = false
	scroll.offset_left = 0
	scroll.offset_right = 0
	scroll.modulate.a = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = sv

func _refresh_soft() -> void:
	## alt sekme değişimi: kaydırmayı koru, yumuşak geçiş
	var sv := scroll.scroll_vertical
	var top = stack.pop_back()
	_no_anim = true
	_show(top[0], top[1])
	_no_anim = false
	scroll.modulate.a = 1.0
	scroll.offset_left = 0
	scroll.offset_right = 0
	for c in page.get_children():
		if c is Control:
			c.modulate.a = 0.0
			c.create_tween().tween_property(c, "modulate:a", 1.0, 0.18)
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = mini(sv, HERO.get(top[0], 0))

func _back_row(title := "") -> void:
	var h := _h(page)
	var b := _btn("", _back, "ghost", h, "back")
	b.custom_minimum_size = Vector2(66, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if title != "":
		var l := _head(title.to_upper(), 30)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)

func _hub_band() -> void:
	## 3B arka planı yalnızca UI üstündeki boş şeride çerçevele
	if hub == null or hero_node == null or not is_instance_valid(hero_node) or not hero_node.is_inside_tree():
		return
	var y := scroll.get_global_rect().position.y + outer.position.y + hero_node.position.y
	var r := Rect2(0, roundf(y), get_viewport_rect().size.x, hero_node.size.y)
	if r != hub.band:
		hub.set_band(r)

func _hub_for(screen: String, arg) -> void:
	if hub == null:
		return
	match screen:
		"title":
			hub.goto("stadium_orbit" if Game.quality() != "low" else "office")
		"home", "newgame", "offers":
			if not Game.s.is_empty() and Game.s.scout.club_id != "":
				var c := Game.my_club()
				hub.set_club(Color(c.c1), Color(c.c2))
				hub.set_trophies(int(Game.s.scout.stats.signed) + int(Game.s.scout.stats.finds))
			hub.goto("office")
			hub.notify_news()
		"news":
			hub.goto("desk")
		"week":
			var home: String = Game.my_club().city
			var mc := []
			var planned := []
			var labels := {}
			for wm in Game.week_matches(_leagues_of(Game.my_club().get("league", "SL"))):
				mc.append(Game.club(wm.m.h).city)
			for day in ["sat", "sun"]:
				if Game.s.plan[day] != "":
					var mm := Game.get_match(Game.s.plan[day])
					var city: String = Game.club(mm.h).city
					planned.append(city)
					labels[city] = Game.club(mm.h).short + "–" + Game.club(mm.a).short
			labels[home] = home
			hub.set_map(home, mc, planned, labels)
			hub.goto("map")
		"team":
			hub.goto("office")
		"players", "tasks":
			var cards := []
			var src: Array = Game.s.scout.shortlist if screen == "players" else Game.s.scout.reports.map(func(r): return r.pid)
			for pid in src.slice(-9):
				var p := Game.player(pid)
				if p.is_empty():
					continue
				var c := Game.club(p.club)
				cards.append({"name": Game.short_name(p), "c1": c.get("c1", "#888888"), "c2": c.get("c2", "#333333"), "stars": _star_txt(Game.ovr_range(pid))})
			hub.set_board(cards)
			hub.goto("board")
		"player", "report":
			var p := Game.player(str(arg))
			if not p.is_empty():
				hub.set_pedestal(p, Game.club(p.club))
			hub.goto("pedestal")
		_:
			hub.goto("stadium")

func _league_picker(cur: String, cb: Callable, groups := true) -> void:
	## Ülke (liste) -> kademe -> grup seçici. cb(lig_kimliği)
	var cc := Game.league_country(cur)
	var r0 := _h(page, 8)
	var cb_country := func():
		var k := await _pick_list(T.t("pick_country"), _country_items(), cc)
		if k != "":
			cb.call(Data.COUNTRIES[k].leagues[0])
	_expand(_btn(T.t("country_lbl", [Data.country_name(cc)]), cb_country, "small", r0, "globe"))
	var mc := Game.my_country()
	if cc != mc:
		var mb := _btn(Data.country_name(mc), func(): cb.call(Game.my_club().get("league", Data.COUNTRIES[mc].leagues[0])), "ghost", r0)
		mb.size_flags_horizontal = Control.SIZE_SHRINK_END
	var t := Game.tier(cur)
	var mt := Game.max_tier(cc)
	if mt > 1:
		var r2 := HFlowContainer.new()
		r2.add_theme_constant_override("h_separation", 8)
		r2.add_theme_constant_override("v_separation", 8)
		page.add_child(r2)
		for k in range(1, mt + 1):
			var kk: int = k
			_btn(Game.tier_name(cc, k), func(): cb.call(Game.tier_groups(cc, kk)[0]), "toggle_on" if t == k else "ghost", r2).custom_minimum_size = Vector2(0, 50)
	var gl: Array = Game.tier_groups(cc, t)
	if groups and gl.size() > 1:
		var gr := _h(page, 8)
		for lg in gl:
			var l2: String = lg
			_expand(_btn(T.t("league_" + lg).replace(T.t("tier_%d" % t), "").strip_edges(), func(): cb.call(l2), "toggle_on" if cur == lg else "ghost", gr))

func _leagues_of(lg: String) -> Array:
	return Game.tier_groups(Game.league_country(lg), Game.tier(lg))

func _my_tier() -> int:
	var c := Game.my_club()
	return Game.tier(c.get("league", "SL")) if not c.is_empty() else 1

# ================================================================ başlık / yeni oyun / teklifler

func _scr_title() -> void:
	_gap(outer, 300)
	# deri kapaklı dosya
	var cover := PanelContainer.new()
	cover.add_theme_stylebox_override("panel", _sb(Color(C_LEATHER, 0.93), 14, 2, Color(C_BRASS, 0.6), 26, 14))
	_stitch(cover, true)
	outer.add_child(cover)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	cover.add_child(cv)
	var top := _lbl(T.t("title_kicker").to_upper(), 18, C_BRASS, true, F_TYPEB)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(top)
	var t := _lbl(T.t("title"), 110, C_CREAM, true, F_HEAD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 0)
	cv.add_child(t)
	var st := _lbl(T.t("subtitle").to_upper(), 24, C_BRASS, true, F_HEADR)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(st)
	var conf := _stamp(T.t("confidential"), Color("#d9443a"), -7.0, 26)
	conf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cv.add_child(conf)
	_gap(cv, 8)
	if not Game.s.is_empty() and Game.s.get("scout", {}).get("club_id", "") != "":
		var c := Game.my_club()
		var cc := _card(cv, "paper")
		var h := _h(cc)
		h.add_child(_crest(c, 50))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_head(Game.s.scout.name, 26))
		v.add_child(_typed("%s • %d/%02d • %s" % [c.name, Game.s.season, (Game.s.season + 1) % 100, T.t("preseason") if Game.s.week == 0 else T.t("week_n", [Game.s.week])], 18, C_INK2))
		h.add_child(v)
		_btn(T.t("continue"), func():
			if not Game.s.season_summary.is_empty():
				_show("season", null, false)
			else:
				_goto_tab("home"), "primary", cc, "ball")
	if Game.old_save and Game.s.is_empty():
		var oc := _card(cv, "memo", 14)
		oc.add_child(_hand(T.t("old_save_note"), 24, C_RED))
	_btn(T.t("new_game"), func(): _show("newgame"), "brass" if Game.s.is_empty() else "dark", cv, "plus")
	var qh := _h(cv)
	_expand(_btn(T.t("language"), func():
		T.lang = "en" if T.lang == "tr" else "tr"
		if not Game.s.is_empty():
			Game.s.lang = T.lang
		_show("title", null, false), "dark", qh))
	_expand(_btn(T.t("quality_" + Game.quality()), func():
		_cycle_quality()
		_show("title", null, false), "dark", qh, "eye"))
	_expand(_btn(T.t("sound_on") if Game.settings.sound else T.t("sound_off"), func():
		Game.settings.sound = not Game.settings.sound
		Game.save_settings()
		_show("title", null, false), "dark", qh, "bell"))
	_btn(T.t("music_on") if Game.settings.get("music", true) else T.t("music_off"), func():
		Game.settings.music = not Game.settings.get("music", true)
		Game.save_settings()
		_show("title", null, false), "dark", cv, "play")
	_btn(T.t("crash_copy"), func():
		DisplayServer.clipboard_set(_last_log(true))
		_toast(T.t("crash_copied")), "dark", cv, "report")
	var v2 := _lbl(VERSION + " • " + T.t("proto"), 16, C_CREAM2, true, F_TYPE)
	v2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(v2)

func _set_flag(on: bool) -> void:
	if on:
		var ff := FileAccess.open(Game.CRASH_FLAG, FileAccess.WRITE)
		if ff:
			ff.store_string(Time.get_datetime_string_from_system())
			ff.close()
	elif FileAccess.file_exists(Game.CRASH_FLAG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.CRASH_FLAG))

func _last_log(current := false) -> String:
	var dir := DirAccess.open("user://logs")
	if dir == null:
		return "(log yok)"
	var files := []
	for f in dir.get_files():
		if f.ends_with(".log") and f != "godot.log":
			files.append(f)
	files.sort()
	var path: String = "user://logs/" + (files[-1] if not files.is_empty() and not current else "godot.log")
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return "(log okunamadı)"
	var txt := fa.get_as_text()
	fa.close()
	var info := "Gözcü %s | %s | %s | %s | kalite=%s ses=%s\n" % [VERSION, OS.get_model_name(), OS.get_name(), OS.get_version(), Game.quality(), str(Game.settings.sound)]
	info += RenderingServer.get_video_adapter_name() + " / " + RenderingServer.get_video_adapter_api_version() + "\n---\n"
	var prev: String = Watch.prev_report
	if prev != "":
		info += prev.right(3000) + "\n"
	# önceki oturumun log dosyasından hatalar
	if current and not files.is_empty():
		var pf := FileAccess.open("user://logs/" + files[-1], FileAccess.READ)
		if pf:
			var errs := []
			for ln in pf.get_as_text().split("\n"):
				if ln.contains("ERROR") or ln.contains("SCRIPT") or ln.contains("at: ") or ln.contains("[BC]"):
					errs.append(ln)
			pf.close()
			info += "=== ONCEKI LOG (" + files[-1] + ") ===\n" + "\n".join(errs.slice(maxi(0, errs.size() - 60))) + "\n"
	info += "=== LOG ===\n"
	return info + txt.right(5000)

func _scr_crash() -> void:
	_gap(outer, 120)
	_sheet()
	_title(T.t("crash_title"), null, 36, "bell")
	var c := _card(null, "memo")
	c.add_child(_lbl(T.t("crash_text"), 22))
	var log_txt := _last_log()
	_btn(T.t("crash_copy"), func():
		DisplayServer.clipboard_set(log_txt)
		_toast(T.t("crash_copied")), "primary", c, "report")
	c.add_child(_typed(T.t("crash_quality"), 18, C_INK2))
	var hh := _h(c)
	_expand(_btn(T.t("sound_on") if Game.settings.sound else T.t("sound_off"), func():
		Game.settings.sound = not Game.settings.sound
		Game.save_settings()
		_refresh(), "small", hh, "bell"))
	_expand(_btn(T.t("quality_" + Game.quality()), func():
		_cycle_quality()
		_refresh(), "small", hh, "eye"))
	c.add_child(_typed(log_txt.right(1200), 13, C_INK2))
	_btn(T.t("continue"), func(): _show("title", null, false), "ghost", page, "arrow")

func _cycle_quality() -> void:
	Game.settings.quality = {"high": "medium", "medium": "low", "low": "high"}[Game.quality()]
	Game.save_settings()
	if hub:
		hub.apply_quality()

func _scr_newgame() -> void:
	_sheet()
	_back_row(T.t("new_game"))
	# scout lisansı
	var lic := _card(null, "manila", 22)
	var lp := _card_panel(lic)
	_clip_deco(lp)
	lic.add_child(_lbl(T.t("license_title").to_upper(), 26, C_INK, true, F_HEAD))
	lic.add_child(_typed(T.t("license_sub"), 17, C_INK2))
	_rule(lic)
	lic.add_child(_typed(T.t("your_name").to_upper(), 18, C_INK2))
	var le := LineEdit.new()
	le.text = "Atakan Koç"
	le.custom_minimum_size = Vector2(0, 76)
	le.add_theme_font_size_override("font_size", 34)
	le.add_theme_font_override("font", F_HAND)
	le.add_theme_color_override("font_color", C_BLUE)
	lic.add_child(le)
	var sh := _h(lic)
	sh.add_child(_typed(T.t("license_no", ["%04d" % (randi() % 9000 + 1000)]), 16, C_INK2))
	var st := _stamp(T.t("approved"), C_GREEN, -6.0, 22)
	sh.add_child(st)
	# başlangıç ülkesi
	var cc_card := _card(null, "paper", 18)
	_section(T.t("start_country"), cc_card, "globe")
	cc_card.add_child(_typed(T.t("start_country_hint"), 16, C_INK2))
	var cinfo: Dictionary = Data.COUNTRIES.get(ng_country, Data.COUNTRIES["TR"])
	var ch := _h(cc_card, 10)
	var nm := _head(Data.country_name(ng_country), 34)
	ch.add_child(nm)
	var cnt := 0
	for cid_row in Data.WORLD_CLUBS.get(ng_country, []):
		cnt += 1
	if ng_country == "TR":
		cnt = Data.SUPER_LIG.size() + Data.BIRINCI_LIG.size() + Data.IKINCI_LIG.size()
	cc_card.add_child(_typed(T.t("country_info", [cinfo.tiers.size(), cnt, T.t("lang_" + cinfo.lang)]), 17, C_INK))
	_btn(T.t("change_country"), func():
		var k := await _pick_list(T.t("pick_country"), _country_items(), ng_country)
		if k != "":
			ng_country = k
			_show("newgame", null, false), "small", cc_card, "globe")
	var tips := _card(null, "memo")
	_section(T.t("how_title"), tips, "eye")
	for k in ["how_1", "how_2", "how_3", "how_4"]:
		tips.add_child(_lbl("•  " + T.t(k), 20))
	_btn(T.t("start"), func():
		var n := le.text.strip_edges()
		if n == "":
			n = "Scout"
		_busy = true
		await get_tree().process_frame
		Game.new_game(n, T.lang, ng_country)
		_busy = false
		shown_vals = {}
		_show("offers", null, false), "primary", page, "arrow")

func _scr_offers() -> void:
	_sheet()
	var fired: bool = Game.s.season_summary.get("fired", false)
	var list: Array = Game.s.offers if not Game.s.offers.is_empty() else Game.job_offers_start()
	if Game.s.offers.is_empty():
		Game.s.offers = list
	_title(T.t("choose_club"), null, 38, "task")
	page.add_child(_hand(T.t("fired_text") if fired else T.t("choose_club_sub"), 28, C_INK2))
	for cid in list:
		var c := Game.club(cid)
		var v := _card(null, "card", 22)
		_accent_top(v, Color(c.c1))
		# antetli kâğıt
		var h := _h(v)
		h.add_child(_crest(c, 66))
		var nv := VBoxContainer.new()
		nv.add_theme_constant_override("separation", 0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(_head(c.name.to_upper(), 26))
		nv.add_child(_typed("%s • %s" % [T.t("league_" + c.league), c.city], 17, C_INK2))
		h.add_child(nv)
		_rule(v)
		v.add_child(_typed(T.t("offer_letter", [Game.s.scout.name]), 18, C_INK))
		var m: Dictionary = c.manager
		var pref := T.t("pref_" + m.pref)
		_kv(v, T.t("manager"), m.name)
		_kv(v, T.t("style"), T.t("style_" + m.style) + ((", " + pref) if pref != "" else ""))
		_kv(v, T.t("salary"), T.t("salary_w", [Game.money_str(Game.offer_salary(c))]), C_GREEN)
		_kv(v, T.t("travel_budget"), Game.money_str(Game.offer_budget(c)), C_BLUE)
		var ph := _h(v)
		ph.add_child(_typed(T.t("prestige"), 17, C_INK2, false))
		_bar(ph, float(c.prestige) / 100.0, C_BRASS, 12).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ph.add_child(_lbl(str(c.prestige), 20, C_INK, false, F_HEAD))
		var id: String = cid
		var bh := _h(v)
		bh.add_child(_hand(T.t("sign_here"), 26, C_INK2, false))
		var b := _btn(T.t("accept"), func(): pass, "red", bh, "check")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			if _dragged:
				return
			var stp := _stamp(T.t("signed_stamp"), C_RED, -10.0, 34)
			v.add_child(stp)
			_stamp_slam(stp)
			_busy = true
			await get_tree().create_timer(0.5).timeout
			_busy = false
			Game.s.offers = []
			Game.s.season_summary = {}
			Game.take_job(id)
			_goto_tab("home"))

# ================================================================ OFİS (ana)

func _scr_home() -> void:
	_sheet([["summary", T.t("st_summary")], ["board", T.t("st_board")], ["career", T.t("st_career")], ["archive", T.t("st_archive")], ["club", T.t("st_myclub")]], sub.home, _sub_cb("home"))
	match sub.home:
		"archive":
			_home_archive()
		"board":
			_home_board()
		"career":
			_home_career()
		"club":
			_home_club()
		_:
			_home_summary()

func _home_summary() -> void:
	var sc: Dictionary = Game.s.scout
	var c := Game.my_club()
	# kulüp antedi
	var v := _card()
	_accent_top(v, Color(c.c1))
	var h := _h(v)
	h.add_child(_crest(c, 72))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", -2)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_child(_head(c.name.to_upper(), 28))
	var order := Game.sorted_table(c.league)
	var rank := order.find(c.id) + 1
	var tb: Dictionary = Game.s.table[c.league][c.id]
	cv.add_child(_typed("%s • %d. • %d %s" % [T.t("league_" + c.league), rank, int(tb.pts), T.t("pts")], 18, C_INK2))
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 4)
	cv.add_child(fh)
	var form: Array = tb.get("form", [])
	if form.is_empty():
		fh.add_child(_typed(T.t("form") + ": —", 16, C_INK2, false))
	for r in form:
		_chip(T.t("res_" + r), {"W": C_GREEN, "D": C_INK2, "L": C_RED}[r], fh, true)
	h.add_child(cv)
	# bu hafta: çizgili not
	var w := _card(null, "memo", 20)
	var wh := _h(w)
	wh.add_child(_lbl(T.t("next_step").to_upper(), 22, C_INK, true, F_HEAD))
	wh.add_child(_hand(T.t("week_n", [Game.s.week]) if Game.s.week > 0 else T.t("preseason"), 26, C_RED, false))
	w.add_child(_cal_strip())
	var plans := []
	for day in ["sat", "sun"]:
		var key: String = Game.s.plan[day]
		if key != "":
			var mm := Game.get_match(key)
			plans.append("%s: %s – %s" % [T.t(day), Game.club(mm.h).short, Game.club(mm.a).short])
	if Game.s.week == 0:
		w.add_child(_hand(T.t("preseason_hint"), 26, C_BLUE))
	elif plans.is_empty():
		w.add_child(_hand(T.t("plan_summary_none"), 26, C_BLUE))
	else:
		w.add_child(_hand(T.t("plan_summary", [", ".join(plans)]), 26, C_BLUE))
	var open := 0
	for a in Game.s.assign:
		if a.status == "open":
			open += 1
	if open > 0:
		var oh := _h(w)
		oh.add_child(Icon.new().setup("task", C_RED, 26))
		oh.add_child(_lbl(T.t("tasks_open", [open]), 20, C_RED, true, F_SEMI))
	var cta := _btn(T.t("end_preseason") if Game.s.week == 0 else T.t("go_weekend"), _play_weekend, "primary", w, "ball")
	var ptw := cta.create_tween().set_loops()
	ptw.tween_property(cta, "modulate", Color(1.12, 1.12, 1.12), 0.9)
	ptw.tween_property(cta, "modulate", Color.WHITE, 0.9)
	# masadaki dosyalar
	_section(T.t("on_desk"), null, "pin")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	page.add_child(grid)
	var tips := 0
	for n in Game.s.news:
		if n.get("kind", "") == "tip" and int(n.season) == int(Game.s.season):
			tips += 1
	for it in [["star", str(sc.shortlist.size()), T.t("pm_shortlist"), "players", "shortlist"],
			["task", str(open), T.t("st_requests"), "tasks", "requests"],
			["phone", str(tips), T.t("st_tips"), "news", "news"]]:
		var rb := _row_button(grid, 120, "card")
		var b: Button = rb[0]
		var inner: HBoxContainer = rb[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vv := VBoxContainer.new()
		vv.add_theme_constant_override("separation", -2)
		vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vv.alignment = BoxContainer.ALIGNMENT_CENTER
		vv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(Icon.new().setup(it[0], C_RED, 26))
		top.add_child(_lbl(it[1], 34, C_INK, false, F_HEAD))
		vv.add_child(top)
		var ll := _lbl(it[2], 16, C_INK2, true, F_TYPEB)
		vv.add_child(ll)
		inner.add_child(vv)
		_ignore_all(inner)
		var tab: String = it[3]
		var sk: String = it[4]
		b.pressed.connect(func():
			if _dragged:
				return
			sub[tab] = sk
			_goto_tab(tab))
	# son haberler
	if not Game.s.news.is_empty():
		_section(T.t("latest"), null, "news")
		for n in Game.s.news.slice(0, 3):
			_clipping(page, n, false)


func _pres_face() -> Dictionary:
	var b := Game.board()
	return {"skin": b.skin, "hair": b.hair, "seed": 7, "club": ""}

func _home_board() -> void:
	var b := Game.board()
	var c := Game.my_club()
	var v := _card(null, "manila", 22)
	_clip_deco(_card_panel(v))
	var h := _h(v, 14)
	h.add_child(_avatar(_pres_face(), 96))
	var nv := _v(h, -2)
	nv.add_child(_typed(T.t("president").to_upper(), 15, C_INK2))
	nv.add_child(_head(b.name, 28))
	nv.add_child(_typed(T.t("pres_" + b.pers), 16, C_INK2))
	var mh := _h(v)
	mh.add_child(_typed(T.t("board_trust"), 17, C_INK2, false))
	_bar(mh, float(b.mood) / 100.0, C_GREEN if int(b.mood) >= 60 else (C_BRASS if int(b.mood) >= 40 else C_RED), 12).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mh.add_child(_lbl("%d" % int(b.mood), 20, C_INK, false, F_HEAD))
	v.add_child(_hand(T.t(Game.board_mood_key()), 26, C_BLUE))
	var pc := _card()
	_section(T.t("board_perms"), pc, "check")
	var ab := []
	for cc in b.abroad:
		ab.append(T.t("zone_" + cc))
	_kv(pc, T.t("perm_abroad"), ", ".join(ab) if not ab.is_empty() else T.t("none"))
	_kv(pc, T.t("perm_slots"), str(int(b.slots)))
	_kv(pc, T.t("travel_budget"), Game.money_str(Game.s.scout.budget))
	_kv(pc, T.t("salary"), T.t("salary_w", [Game.money_str(Game.s.scout.salary)]))
	if b.get("favor", "") != "":
		_kv(pc, T.t("perm_favor"), Game.pname(Game.player(b.favor)))
	var why := Game.board_can_meet()
	var mc := _card(null, "memo", 20)
	_section(T.t("board_meeting"), mc, "chat")
	mc.add_child(_hand(T.t("board_hint"), 25, C_INK2))
	if why != "":
		mc.add_child(_hand(T.t(why), 25, C_RED))
	else:
		_btn(T.t("board_ask"), _board_meeting, "red", mc, "chat")

func _board_meeting() -> void:
	if _busy:
		return
	_busy = true
	var b := Game.board()
	var me_name: String = Game.s.scout.name
	_scene_open("office", T.t("sc_place_board"))
	var pf := _pres_face()
	_seat("pres", {"top": Color("#1f2a44"), "pants": Color("#1f2a44"), "shoes": Color("#111111"), "skin": int(pf.skin), "hair": int(pf.hair), "seed": 7}, 1.75, -PI / 2.0)
	_seat("me", SCOUT_LOOK, -0.85, PI / 2.0)
	stage.wide()
	await get_tree().create_timer(0.6).timeout
	await _line("pres", b.name, T.t("pres_hello_" + Game.board_mood_key().replace("mood_", ""), [me_name]), "me")
	var opts := []
	var home_zone := Data.zone_of(Game.my_country())
	var zopts := []
	for z in Data.ZONES:
		if z != home_zone and not (z in b.abroad):
			zopts.append([z, T.t("zone_" + z)])
	if not zopts.is_empty():
		opts.append(["abroad", T.t("pt_abroad_any")])
	opts.append(["staff", T.t("pt_staff")])
	opts.append(["budget", T.t("pt_budget")])
	if not Game.s.scout.shortlist.is_empty():
		opts.append(["push", T.t("pt_push")])
	opts.append(["raise", T.t("pt_raise")])
	opts.append(["report", T.t("pt_report")])
	var pick := await _choose(opts, T.t("sc_board_q"))
	var topic := pick
	var arg := ""
	if pick == "abroad":
		topic = "abroad"
		arg = await _choose(zopts, T.t("sc_abroad_q"))
		await _line("me", me_name, T.t("ask_abroad", [T.t("zone_" + arg)]), "pres")
	elif pick == "push":
		var po := []
		for pid in Game.s.scout.shortlist.slice(0, 6):
			var pp := Game.player(pid)
			if not pp.is_empty():
				po.append([pid, "%s • %s • %s" % [Game.pname(pp), _pos_short(pp.pos), Game.club(pp.club).get("short", "")]])
		arg = await _choose(po, T.t("sc_push_q"))
		await _line("me", me_name, T.t("ask_push", [Game.pname(Game.player(arg))]), "pres")
	else:
		await _line("me", me_name, T.t("ask_" + pick), "pres")
	var res := Game.board_request(topic, arg)
	stage.listener_react("pres", res.ok)
	await _line("pres", b.name, T.t(res.key, res.args), "me", 0, "smirk" if res.ok else "annoyed")
	await _line("pres", b.name, T.t("pres_bye_" + ("ok" if res.ok else "no")), "me")
	_busy = false
	_scene_close()

func _home_career() -> void:
	var sc: Dictionary = Game.s.scout
	# lisans kartı
	var lic := _card(null, "manila", 22)
	_clip_deco(_card_panel(lic))
	var lh := _h(lic)
	lh.add_child(_id_badge(sc.name, 70))
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", -2)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_child(_head(String(sc.name).to_upper(), 28))
	lv.add_child(_typed(T.t(Game.title_key()) + " • " + Game.my_club().get("name", ""), 17, C_INK2))
	lh.add_child(lv)
	var rh := _h(lic)
	rh.add_child(_lbl("%d" % int(sc.rep), 64, C_INK, false, F_HEAD))
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_child(_typed(T.t("rep") + " / 100", 17, C_INK2))
	var nxt := 100
	var nxt_key := ""
	for tt in Game.TITLES:
		if float(tt[0]) > float(sc.rep):
			nxt = int(tt[0])
			nxt_key = tt[1]
			break
	_bar(rv, float(sc.rep) / float(nxt), C_RED, 14)
	if nxt_key != "":
		rv.add_child(_hand(T.t("next_title", [T.t(nxt_key), nxt]), 24, C_BLUE))
	rh.add_child(rv)
	_rep_card()
	# istatistikler
	var sv := _card()
	_section(T.t("career"), sv, "trophy")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 14)
	sv.add_child(grid)
	for st in ["watched", "disc", "signed", "tips", "reports", "finds"]:
		_stat_box(grid, str(int(sc.stats.get(st, 0))), T.t("st_" + st))
	# itibar grafiği
	var hist: Array = sc.history.duplicate()
	var pts := []
	for hrow in hist:
		pts.append(float(hrow.rep))
	pts.append(float(sc.rep))
	if pts.size() >= 2:
		var gc := _card()
		_section(T.t("rep_chart"), gc, "star")
		var ch := Control.new()
		ch.custom_minimum_size = Vector2(0, 170)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch.draw.connect(func():
			var w := ch.size.x
			var hh := ch.size.y
			for k in 5:
				var y := hh - k * hh / 4.0
				ch.draw_line(Vector2(0, y), Vector2(w, y), Color(C_INK, 0.08), 1.0)
			var poly := PackedVector2Array()
			for i in pts.size():
				poly.append(Vector2(lerpf(20, w - 20, float(i) / maxf(1.0, pts.size() - 1)), hh - 10 - (hh - 20) * pts[i] / 100.0))
			ch.draw_polyline(poly, C_RED, 3.0, true)
			for p2 in poly:
				ch.draw_circle(p2, 5, C_INK))
		gc.add_child(ch)
	# yetenekler
	var sk := _card()
	_section(T.t("home_skills"), sk, "eye")
	for pair in [["eye", sc.eye, sc.xp_eye], ["net", sc.net, sc.xp_net]]:
		var row := _h(sk)
		var nl := _lbl(T.t(pair[0]), 21, C_INK, false, F_SEMI)
		nl.custom_minimum_size = Vector2(190, 0)
		row.add_child(nl)
		_bar(row, float(pair[1]) / 20.0, C_BLUE, 14).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_lbl("%d" % pair[1], 24, C_INK, false, F_HEAD))
		sk.add_child(_typed(T.t("xp_line", [int(pair[2]), int(pair[1]) * 4]), 15, C_INK2))
	sk.add_child(_typed(T.t("skills_hint"), 16, C_INK2))
	var ch2 := _h(sk)
	for kk in ["eye", "net"]:
		var kind: String = kk
		var b := _btn(T.t("course_" + kk, [Game.money_str(Game.course_cost(kk))]), func():
			if Game.buy_course(kind):
				_toast(T.t("course_done"))
				_refresh()
			else:
				_toast(T.t("not_enough_money")), "small", ch2)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
	# diller
	var lc := _card()
	_section(T.t("languages"), lc, "globe")
	var mine: Array = sc.get("langs", ["TR"])
	var known := []
	for l in mine:
		known.append(T.t("lang_" + l))
	lc.add_child(_hand(", ".join(known), 28, C_BLUE))
	lc.add_child(_typed(T.t("lang_hint"), 15, C_INK2))
	var lang_row := _h(lc, 8)
	var sugg := []
	for code in ["EN", "ES", "DE", "FR", "IT", "PT"]:
		if not (code in mine) and sugg.size() < 2:
			sugg.append(code)
	var others := []
	for code in Data.LANG_NAMES:
		if not (code in mine):
			others.append([code, Data.lang_name(code), Game.money_str(Game.learn_lang_cost(code))])
	others.sort_custom(func(a, b): return a[1] < b[1])
	_btn(T.t("other_lang"), func():
		var k := await _pick_list(T.t("languages"), others)
		if k != "":
			if Game.learn_lang(k):
				_toast(T.t("lang_learned"))
				_refresh()
			else:
				_toast(T.t("not_enough_money")), "ghost", lc, "globe")
	for code in sugg:
		var cd: String = code
		_expand(_btn(T.t("lang_course", [T.t("lang_" + code), Game.money_str(Game.learn_lang_cost(code))]), func():
			if Game.learn_lang(cd):
				_toast(T.t("lang_learned"))
				_refresh()
			else:
				_toast(T.t("not_enough_money")), "small", lang_row)).add_theme_font_size_override("font_size", 17)
	# geçmiş
	var hc := _card()
	_section(T.t("career_history"), hc, "report")
	if hist.is_empty():
		hc.add_child(_hand(T.t("no_history"), 26, C_INK2))
	for hrow in hist:
		_kv(hc, "%d/%02d  %s" % [int(hrow.season), (int(hrow.season) + 1) % 100, hrow.club], T.t("rep") + " %d" % int(hrow.rep))

func _rep_card() -> void:
	## İtibar: bölge ağı + uzmanlık rozetleri + rapor isabeti
	var sc: Dictionary = Game.s.scout
	var v := _card()
	_section(T.t("rep_map"), v, "globe")
	v.add_child(_typed(T.t("rep_map_hint"), 15, C_INK2))
	for ar in Game.AREAS:
		var val := Game.area_rep(ar)
		var row := _h(v)
		var nl := _lbl(T.t("area_" + ar), 19, C_INK if val > 0.5 else C_INK2, false, F_SEMI)
		nl.custom_minimum_size = Vector2(230, 0)
		row.add_child(nl)
		_bar(row, val / 100.0, C_GREEN, 12).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var vl := _lbl("%d" % int(val), 22, C_INK, false, F_HEAD)
		vl.custom_minimum_size = Vector2(44, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
	var acc: Dictionary = sc.get("acc", {})
	if int(acc.get("n", 0)) > 0:
		_kv(v, T.t("rep_accuracy"), "%d%%  (%d)" % [int(Game.reliability() * 100.0), int(acc.n)], C_GREEN if Game.reliability() >= 0.6 else C_INK)
	var bv := _card()
	_section(T.t("badges"), bv, "star")
	var have := Game.scout_badges()
	if "inflater" in have:
		var wc := _card(bv, "memo", 12)
		wc.add_child(_head(T.t("badge_inflater"), 22))
		wc.add_child(_typed(T.t("badge_inflater_d"), 15, C_RED))
	for id in Game.BADGES.keys() + ["reliable"]:
		var got: bool = id in have
		var bc := _h(bv, 10)
		bc.add_child(Icon.new().setup("star", C_BRASS if got else Color(C_INK, 0.22), 30))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bc.add_child(tv)
		tv.add_child(_lbl(T.t("badge_" + id), 20, C_INK if got else C_INK2, false, F_SEMI))
		tv.add_child(_typed(T.t("badge_" + id + "_d"), 14, C_INK2))
		if not got:
			_bar(tv, Game.badge_progress(id), C_BRASS, 8)

func _home_archive() -> void:
	## Kaçanlar Müzesi + keşif tarihçesi
	var mus: Array = Game.s.get("museum", []).duplicate()
	mus.reverse()
	var mv := _card(null, "manila", 20)
	_section(T.t("museum_title"), mv, "trophy")
	mv.add_child(_typed(T.t("museum_hint"), 15, C_INK2))
	if mus.is_empty():
		mv.add_child(_hand(T.t("museum_empty"), 26, C_INK2))
	for e in mus:
		var pc := _card(mv, "card", 14)
		var hh := _h(pc, 10)
		var p := Game.player(e.pid)
		if not p.is_empty():
			hh.add_child(_avatar(p, 56))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hh.add_child(tv)
		tv.add_child(_head(String(e.name), 22))
		tv.add_child(_typed(T.t("museum_then", [_pos_short(e.pos), int(e.seen_season), int(e.seen_age)]), 15, C_INK2))
		var now_club: Dictionary = Game.club(e.club)
		tv.add_child(_typed(T.t("museum_now", [now_club.get("name", "-"), Game.money_str(int(e.value))]), 15, C_INK))
		hh.add_child(_stamp(T.t("mwhy_" + String(e.why)), C_RED, 6.0, 15))
		if not p.is_empty():
			var id: String = e.pid
			_btn("", func(): _show("player", id), "ghost", hh, "arrow").custom_minimum_size = Vector2(56, 50)
	# keşif tarihçesi
	var log: Array = Game.s.scout.get("disc_log", [])
	var hv := _card()
	_section(T.t("disc_title"), hv, "youth")
	if log.is_empty():
		hv.add_child(_hand(T.t("disc_empty"), 26, C_INK2))
		return
	var by := {}
	for d in log:
		by[d.how] = int(by.get(d.how, 0)) + 1
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	hv.add_child(grid)
	_stat_box(grid, str(log.size()), T.t("disc_total"))
	for how in ["match", "u19", "tip", "staff", "report"]:
		if by.has(how):
			_stat_box(grid, str(by[how]), T.t("dhow_" + how))
	hv.add_child(_typed(T.t("disc_hint"), 15, C_INK2))
	# en çok yol alanlar (kamuya açık bilgi: kulüp, değer, maç puanı)
	var rows := []
	for d in log:
		var p := Game.player(d.pid)
		if p.is_empty():
			continue
		var moved: bool = p.club != d.club
		var score := float(p.value) / 100000.0 + (20.0 if moved and Game.club(p.club).get("prestige", 0) > Game.club(d.club).get("prestige", 0) else 0.0)
		rows.append([score, d, p])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	for row in rows.slice(0, 25):
		var d: Dictionary = row[1]
		var p: Dictionary = row[2]
		var rb := _row_button(hv, 86)
		var inner: HBoxContainer = rb[1]
		inner.add_child(_avatar(p, 50))
		var nv := VBoxContainer.new()
		nv.add_theme_constant_override("separation", -2)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_child(nv)
		var nl := _lbl(Game.pname(p), 19, C_INK, false, F_SEMI)
		nl.clip_text = true
		nv.add_child(nl)
		var then_c: Dictionary = Game.club(d.club)
		var now_c: Dictionary = Game.club(p.club)
		var line := T.t("disc_line", [int(d.season), T.t("dhow_" + String(d.how)).to_lower(), then_c.get("short", "-"), int(d.age)])
		nv.add_child(_typed(line, 14, C_INK2, false))
		var nowl := T.t("disc_now", [now_c.get("short", "-"), Game.money_str(int(p.value))])
		var avg := (float(p.st.rs) / float(p.st.apps)) if int(p.st.apps) > 0 else 0.0
		if avg > 0.0:
			nowl += "  •  %.1f" % avg
		nv.add_child(_typed(nowl, 14, C_GREEN if p.club != d.club else C_INK, false))
		_ignore_all(inner)
		var id: String = d.pid
		(rb[0] as Button).pressed.connect(func():
			if not _dragged:
				_show("player", id))

func _home_club() -> void:
	var sc: Dictionary = Game.s.scout
	var c := Game.my_club()
	var v := _card()
	_accent_top(v, Color(c.c1))
	var h := _h(v)
	h.add_child(_crest(c, 80))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", -2)
	nv.add_child(_head(c.name.to_upper(), 28))
	nv.add_child(_typed("%s • %s" % [T.t("league_" + c.league), c.city], 17, C_INK2))
	h.add_child(nv)
	_kv(v, T.t("prestige"), str(c.prestige))
	_kv(v, T.t("club_budget"), Game.money_str(c.budget), C_GREEN)
	_kv(v, T.t("salary"), T.t("salary_w", [Game.money_str(sc.salary)]))
	var bl: int = int(sc.budget) - int(sc.spent)
	var bh := _h(v)
	bh.add_child(_typed(T.t("travel_left"), 17, C_INK2, false))
	_bar(bh, float(bl) / maxf(1.0, float(sc.budget)), C_BLUE if bl > 0 else C_RED, 12).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(_lbl(Game.money_str(bl), 20, C_RED if bl < 0 else C_INK, false, F_HEAD))
	var hb := _h(v)
	_expand(_btn(T.t("squad"), func(): _show("club", c.id), "small", hb, "shirt"))
	_expand(_btn(T.t("standings"), func():
		sub.news = "table"
		table_lg = c.league
		_goto_tab("news"), "small", hb, "trophy"))
	# teknik direktör dosyası
	var m: Dictionary = c.manager
	var mc := _card(null, "memo", 20)
	_section(T.t("manager_file"), mc, "chat")
	mc.add_child(_head(m.name, 26))
	_kv(mc, T.t("style"), T.t("style_" + m.style))
	var pref := T.t("pref_" + m.pref)
	_kv(mc, T.t("preference"), pref if pref != "" else "—")
	var wants := []
	for a in Data.STYLE_ATTRS[m.style]:
		wants.append(T.t("a_" + a))
	mc.add_child(_hand(T.t("manager_wants", [", ".join(wants)]), 26, C_BLUE))
	# mini puan durumu
	var order := Game.sorted_table(c.league)
	var rank := order.find(c.id)
	var tc := _card()
	_section(T.t("league_" + c.league), tc, "trophy")
	for i in range(maxi(0, rank - 2), mini(order.size(), rank + 3)):
		var cid: String = order[i]
		var tb: Dictionary = Game.s.table[c.league][cid]
		var row := _h(tc)
		row.add_child(_lbl("%d." % (i + 1), 20, C_INK2, false, F_HEAD))
		row.add_child(_crest(Game.club(cid), 26))
		var nl := _lbl(Game.club(cid).name, 19, C_RED if cid == c.id else C_INK, true, F_SEMI)
		nl.clip_text = true
		nl.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(nl)
		row.add_child(_lbl("%d" % int(tb.pts), 20, C_INK, false, F_HEAD))

func _cal_strip() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var acts := {"video": "play", "train": "cone", "meet": "chat", "src_coach": "phone", "src_agent": "phone", "src_journalist": "phone", "u19": "youth", "rest": "moon", "travel": "plane", "board": "chat", "trip": "plane"}
	for d in 7:
		var pc := PanelContainer.new()
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var filled := false
		var icon := ""
		var col := C_INK2
		if d < 5:
			var e = Game.s.cal.get(str(d), null)
			if e != null:
				filled = true
				icon = acts.get(e.act, "check")
				col = C_INK
			elif d == Game.WED:
				icon = "youth"
				col = Color(C_INK2, 0.5)
		else:
			var key: String = Game.s.plan["sat" if d == 5 else "sun"]
			if key != "":
				filled = true
				icon = "ball"
				col = C_INK
		pc.add_theme_stylebox_override("panel", _sb(C_HL if filled else Color(1, 1, 1, 0.35), 6, 2 if filled else 1, C_INK if filled else Color(C_INK, 0.2), 4))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		pc.add_child(v)
		var l := _lbl(T.t("d%d" % d).to_upper(), 15, C_RED if d >= 5 else C_INK, false, F_HEAD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		var ic := Icon.new().setup(icon if icon != "" else "plus", col if icon != "" else Color(C_INK, 0.15), 26)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		h.add_child(pc)
	return h

# ================================================================ hafta sonu akışı

func _play_weekend() -> void:
	if _busy:
		return
	_busy = true
	Game.save_game()
	if Game.s.week >= 1:
		for day in ["sat", "sun"]:
			var key := Game.play_day(day)
			if key != "":
				_landscape(true)
				var data := Game.watch_match_data(key)
				data["moments"] = Game.watch_mode(day) == "moments"
				var fe = await _run_viewer(data, Game.s.plan["focus_" + day])
				Game.finish_live(data)
				Game.apply_watch(data, fe)
				Watch.bc("gozlem kaydedildi " + str(day))
		_landscape(false)
	Watch.bc("finish_week")
	pending_result = Game.finish_week()
	Watch.bc("finish_week tamam")
	for r in Game.s.scout.reports:
		if r.get("ceremony", false):
			r.erase("ceremony")
			await _signing_scene(r)
			break
	_busy = false
	_show("result", null, false)

func _landscape(on: bool) -> void:
	Watch.bc("mac ekrani " + ("acik" if on else "kapali"))

class RotHolder extends Control:
	## Dikey ekranda yatay maç: içerik 90° döner; telefonun hangi yana çevrildiğine göre yön seçer
	var dir := 1.0
	var _t := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_pick_dir()
		_fit()
		get_viewport().size_changed.connect(_fit)
	func _pick_dir() -> void:
		var acc := Input.get_accelerometer()
		if absf(acc.x) > 3.0:
			dir = -1.0 if acc.x > 0.0 else 1.0
	func _fit() -> void:
		var vs := get_viewport().get_visible_rect().size
		if vs.x > vs.y:
			# zaten yatay (masaüstü): döndürme yok
			rotation = 0.0
			position = Vector2.ZERO
			size = vs
		else:
			size = Vector2(vs.y, vs.x)
			rotation = PI / 2.0 * dir
			position = Vector2(vs.x, 0.0) if dir > 0.0 else Vector2(0.0, vs.y)
		for c in get_children():
			if c is Control:
				c.position = Vector2.ZERO
				c.size = size
	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.6:
			_t = 0.0
			var old := dir
			_pick_dir()
			if old != dir:
				_fit()

func _run_viewer(data: Dictionary, focus: Array):
	Game.save_game()
	Watch.bc("mac basliyor youth=" + str(data.youth))
	Sfx.music_off()
	# CanvasLayer yerine ana ağaçta en üst kardeş (bazı GPU'larda CanvasLayer içindeki 3D çizilmiyor)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var blk := ColorRect.new()
	blk.color = Color.BLACK
	blk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(blk)
	# Ekran yönü değiştirilmez (siyah ekran sorunu): içerik 90° döndürülür, telefon yan tutulur
	var rot := RotHolder.new()
	layer.add_child(rot)
	# 1) yükleme ekranı: önce menü 3D'si tamamen kapanır, sonra maç kurulur (iki 3D sahne üst üste binmez)
	var load_ui := _match_loading(data)
	rot.add_child(load_ui)
	for i in 3:
		await get_tree().process_frame
	root.visible = false
	if hub:
		hub.set_active(false)
	for i in 3:
		await get_tree().process_frame
	Watch.bc("yukleme: menu 3D kapandi " + Watch._mon())
	var mv = MatchView.new()
	mv.setup(data, F_HEAD, F_BODY, focus)
	mv.hold = true
	viewer = mv
	rot.add_child(mv)
	rot.move_child(load_ui, -1)
	load_ui.position = Vector2.ZERO
	load_ui.size = rot.size
	# 2) maç sahnesi arkada birkaç kare çizilsin (ilk karelerdeki siyahlık görünmesin)
	var t0 := Time.get_ticks_msec()
	for i in 45:
		await get_tree().process_frame
		var pb: ProgressBar = load_ui.get_meta("bar")
		pb.value = float(i) / 44.0 * 100.0
	while Time.get_ticks_msec() - t0 < 1400:
		await get_tree().process_frame
	Watch.bc("yukleme bitti " + Watch._mon())
	mv.hold = false
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(load_ui, "modulate:a", 0.0, 0.35)
	tw.tween_callback(load_ui.queue_free)
	var fe = await mv.finished
	Watch.bc("mac bitti")
	var tw2 := create_tween()
	tw2.tween_property(mv, "modulate:a", 0.0, 0.25)
	await tw2.finished
	layer.visible = false
	layer.queue_free()
	root.visible = true
	viewer = null
	if hub:
		hub.set_active(true)
	Watch.bc("viewer kapandi")
	return fe

## İmza töreni: başkan ve oyuncu el sıkışır, atkıyla basın fotoğrafı
func _signing_scene(r: Dictionary) -> void:
	var p := Game.player(r.pid)
	if p.is_empty():
		return
	var me := Game.my_club()
	_scene_open("office", T.t("sc_place_sign", [me.get("name", "")]))
	var pf := _pres_face()
	var pres = stage.add_actor("pres", {"top": Color("#1f2a44"), "pants": Color("#1f2a44"), "shoes": Color("#111111"), "skin": int(pf.skin), "hair": int(pf.hair), "seed": 7}, Vector3(-0.15, 0, 1.1), PI / 2.0, "idle")
	var pl = stage.add_actor("p", {"kind": "player", "p": p, "club": me}, Vector3(0.75, 0, 1.1), -PI / 2.0, "idle")
	var sc = stage.add_actor("me", SCOUT_LOOK, Vector3(2.2, 0, 1.7), -2.2, "idle")
	for a in [pres, pl, sc]:
		a.set_meta("talker", false)
	stage.shot(0, Vector3(0.35, 1.55, 3.3), Vector3(0.3, 1.25, 1.1), 3.0, true)
	await _caption(T.t("sign_intro", [Game.pname(p), me.get("name", ""), Game.money_str(int(r.get("fee", 0)))]))
	pres.overlay = "shake"
	pl.overlay = "shake"
	pres.emote("happy")
	pl.emote("happy")
	stage.shot(0, Vector3(0.3, 1.5, 2.2), Vector3(0.3, 1.3, 1.1), 4.0)
	for i in 3:
		await get_tree().create_timer(0.45).timeout
		stage.flash()
	await get_tree().create_timer(0.6).timeout
	pres.overlay = ""
	pl.overlay = "scarf"
	pl.rotation.y = 0.0
	stage.attach_scarf("p", Color(me.get("c1", "#b5121b")), Color(me.get("c2", "#ffffff")))
	stage.shot(0, Vector3(0.75, 1.65, 2.6), Vector3(0.75, 1.55, 1.1), 3.0, true)
	for i in 2:
		await get_tree().create_timer(0.5).timeout
		stage.flash()
	await _line("p", Game.pname(p), T.t("sign_quote_%d" % (randi() % 3), [me.get("name", "")]), "")
	pl.overlay = ""
	await _line("pres", Game.board().name, T.t("sign_pres", [Game.s.scout.name]), "me", 0, "smirk")
	sc.nod()
	await _note(T.t("sign_note", [Game.pname(p)]), C_RED)
	_scene_close()

func _match_loading(data: Dictionary) -> Control:
	## Maç öncesi yükleme ekranı (yatay): armalar, maç adı, ipucu, ilerleme çubuğu
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var vs := get_viewport().get_visible_rect().size
	c.size = Vector2(maxf(vs.x, vs.y), minf(vs.x, vs.y))
	var bg := ColorRect.new()
	bg.color = Color("#0b120e")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	c.add_child(v)
	var m: Dictionary = data.m
	var hc := Game.club(m.h)
	var ac := Game.club(m.a)
	var hh := HBoxContainer.new()
	hh.alignment = BoxContainer.ALIGNMENT_CENTER
	hh.add_theme_constant_override("separation", 28)
	v.add_child(hh)
	hh.add_child(_crest(hc, 150))
	var vsl := _lbl("—", 54, Color("#e8c547"), false, F_HEAD)
	hh.add_child(vsl)
	hh.add_child(_crest(ac, 150))
	var nm := _lbl("%s  vs  %s%s" % [hc.get("name", ""), ac.get("name", ""), "  (U19)" if data.youth else ""], 46, Color("#eef3ef"), false, F_HEAD)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var from_c: String = Game.my_club().get("city", "")
	var to_c: String = hc.get("city", "")
	if data.get("video", false):
		to_c = from_c
	if to_c != "" and from_c != "" and to_c != from_c:
		var tr := HBoxContainer.new()
		tr.alignment = BoxContainer.ALIGNMENT_CENTER
		tr.add_theme_constant_override("separation", 14)
		v.add_child(tr)
		tr.add_child(_lbl(from_c, 30, Color("#eef3ef"), false, F_HEAD))
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(260, 40)
		tr.add_child(bar)
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.25)
		line.position = Vector2(0, 19)
		line.size = Vector2(260, 2)
		bar.add_child(line)
		var far := Data.city_country(to_c) != Data.city_country(from_c) or true
		var ic = Icon.new().setup("plane" if far else "bus", Color("#e8c547"), 36)
		bar.add_child(ic)
		ic.position = Vector2(0, 2)
		var tw := c.create_tween().set_loops()
		tw.tween_property(ic, "position:x", 224.0, 1.4).from(0.0)
		tr.add_child(_lbl(to_c, 30, Color("#e8c547"), false, F_HEAD))
	var st := _lbl(T.t("load_tape") if data.get("video", false) else T.t("load_going"), 30, Color("#9db0a3"), false, F_BODY)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(680, 14)
	pb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#e8c547")
	fill.set_corner_radius_all(5)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(5)
	pb.add_theme_stylebox_override("fill", fill)
	pb.add_theme_stylebox_override("background", back)
	v.add_child(pb)
	c.set_meta("bar", pb)
	var tip := _lbl(T.t("load_tip_%d" % (randi() % 6)), 28, Color("#eef3ef", 0.8), true, F_BODY)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.custom_minimum_size = Vector2(1100, 0)
	tip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(tip)
	var rh := _lbl(T.t("load_rotate"), 24, Color("#9db0a3"), false, F_BODY)
	rh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rh)
	return c

func _watch_u19(idx: int) -> void:
	if _busy:
		return
	if not Game.wed_free():
		_toast(T.t("wed_used"))
		return
	_busy = true
	_landscape(true)
	var data := Game.watch_u19_data(idx)
	var fe = await _run_viewer(data, [])
	_landscape(false)
	Game.finish_live(data)
	pending_obs = Game.apply_watch(data, fe)
	Game.save_game()
	_busy = false
	_show("obs", null, true)

# ================================================================ TAKVİM

var trip_res := {}

func _trip_flow() -> void:
	## Keşif seyahati: ülke -> tür -> sonuç
	var items := []
	for cc in Data.scout_countries():
		var lock := "" if Game.board_abroad_ok(cc) else T.t("locked_s")
		items.append([cc, Data.country_name(cc), "%s%s" % [Game.money_str(Game.trip_cost(cc)), ("  • " + lock) if lock != "" else ""]])
	items.sort_custom(func(a, b): return a[1] < b[1])
	var cc := await _pick_list(T.t("trip_pick"), items)
	if cc == "":
		return
	var why := Game.trip_check(cc)
	if why != "":
		_toast(T.t(why))
		return
	var kind := await _pick_list(T.t("trip_kind"), [["academy", T.t("trip_academy"), T.t("trip_academy_d")], ["league", T.t("trip_league"), T.t("trip_league_d")]])
	if kind == "":
		return
	var r := Game.do_trip(cc, kind)
	if not r.ok:
		_toast(T.t(r.msg))
		return
	Sfx.play("pen", -8.0)
	trip_res = r
	Game.save_game()
	_show("trip")

func _scr_trip() -> void:
	_sheet()
	_back_row(T.t("trip_title"))
	var r := trip_res
	if r.is_empty():
		return
	var v := _card(null, "manila", 20)
	v.add_child(_head(Data.country_name(r.cc).to_upper(), 34))
	v.add_child(_typed(T.t("trip_" + r.kind) + " • " + T.t("trip_cost_l", [Game.money_str(r.cost)]), 17, C_INK2))
	v.add_child(_hand(T.t("trip_found", [r.pids.size()]), 28, C_BLUE))
	_section(T.t("trip_list"), null, "eye")
	for pid in r.pids:
		_search_row(pid)
	page.add_child(_typed(T.t("trip_hint"), 16, C_INK2))

func _scr_week() -> void:
	_sheet([["this", T.t("st_thisweek")], ["matches", T.t("st_matches")], ["u19", T.t("st_u19")]], sub.week, _sub_cb("week"))
	match sub.week:
		"matches":
			_week_matches()
		"u19":
			_week_u19()
		_:
			_week_this()

func _week_this() -> void:
	_title(T.t("tab_week"), null, 36, "calendar")
	page.add_child(_cal_strip())
	page.add_child(_hand(T.t("days_left", [Game.free_days()]), 26, C_INK2))
	if Game.s.week >= 1 and Game.free_days() > 0:
		_btn(T.t("act_rest"), func():
			Game.rest_day()
			_toast(T.t("rest_done"))
			_refresh(), "ghost", page, "moon")
	if Game.s.week >= 1:
		_btn(T.t("trip_btn"), _trip_flow, "small", page, "plane")
	# planlanan maçlar
	_section(T.t("weekend_plan"), null, "ball")
	for day in ["sat", "sun"]:
		var key: String = Game.s.plan[day]
		if key == "":
			var em := _card(null, "memo")
			var eh := _h(em)
			eh.add_child(_lbl(T.t(day).to_upper(), 22, C_RED, false, F_HEAD))
			eh.add_child(_hand(T.t("no_plan_day"), 26, C_INK2))
			var dd: String = day
			_btn(T.t("pick_match"), func():
				sub.week = "matches"
				_refresh_soft(), "small", em, "pin")
			continue
		var m := Game.get_match(key)
		_match_ticket(page, key, m, true)
	# seyahat bütçesi
	var sc: Dictionary = Game.s.scout
	var bl: int = int(sc.budget) - int(sc.spent)
	var bc := _card()
	var bh := _h(bc)
	bh.add_child(_typed(T.t("travel_left"), 17, C_INK2, false))
	_bar(bh, float(bl) / maxf(1.0, float(sc.budget)), C_BLUE if bl > 0 else C_RED, 12).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(_lbl(Game.money_str(bl), 20, C_RED if bl < 0 else C_INK, false, F_HEAD))
	bc.add_child(_typed(T.t("travel_hint"), 15, C_INK2))
	_btn(T.t("end_preseason") if Game.s.week == 0 else T.t("go_weekend"), _play_weekend, "primary", page, "ball")

func _match_ticket(parent: Control, key: String, m: Dictionary, planned: bool) -> void:
	var hc := Game.club(m.h)
	var ac := Game.club(m.a)
	var info := Game.travel_info(hc.city)
	var h := _ticket(parent, Color("#fbf0bd") if planned else C_CARD, C_RED if planned else Color(hc.c1))
	var stub := VBoxContainer.new()
	stub.custom_minimum_size = Vector2(72, 0)
	stub.alignment = BoxContainer.ALIGNMENT_CENTER
	stub.add_theme_constant_override("separation", -4)
	var dl := _lbl(T.t("d5" if m.day == "sat" else "d6").to_upper(), 26, C_INK, false, F_HEAD)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stub.add_child(dl)
	var tl := _lbl("19:00" if m.day == "sat" else "16:00", 15, C_INK2, false, F_TYPEB)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stub.add_child(tl)
	h.add_child(stub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(8, 0)
	h.add_child(gap)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 6)
	tr.add_child(_crest(hc, 30))
	var nm := _lbl("%s – %s" % [hc.short, ac.short], 24, C_INK, false, F_HEAD)
	tr.add_child(nm)
	tr.add_child(_crest(ac, 30))
	mid.add_child(tr)
	var names := _lbl("%s – %s" % [hc.name, ac.name], 16, C_INK2, true, F_SEMI)
	names.clip_text = true
	names.autowrap_mode = TextServer.AUTOWRAP_OFF
	mid.add_child(names)
	var mode := T.t("travel_" + info.mode, [info.km]) if info.mode != "local" else T.t("travel_local")
	mid.add_child(_typed("%s • %s • %s" % [hc.city, mode, Game.money_str(info.cost)], 15, C_INK2))
	if planned:
		mid.add_child(_hand(T.t("focus_count", [Game.s.plan["focus_" + m.day].size()]), 24, C_BLUE))
	h.add_child(mid)
	var k2 := key
	var go := _btn("", func(): _show("match", k2), "ghost", h, "arrow")
	go.custom_minimum_size = Vector2(62, 62)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _week_matches() -> void:
	if week_lg == "":
		week_lg = Game.my_club().get("league", "SL")
	_title(T.t("weekend_matches"), null, 34, "ball")
	_league_picker(week_lg, func(lg):
		week_lg = lg
		_refresh_soft(), false)
	if Game.league_country(week_lg) != Game.my_country():
		page.add_child(_hand(T.t("abroad_hint"), 25, C_RED))
	var home: String = Game.my_club().city
	var ms := Game.week_matches(_leagues_of(week_lg))
	if Game.s.week == 0:
		_empty(page, "calendar", T.t("no_matches"))
		_btn(T.t("end_preseason"), _play_weekend, "primary", page, "ball")
		return
	if ms.is_empty():
		_empty(page, "ball", T.t("no_matches_tier"))
		return
	ms.sort_custom(func(a, b):
		if a.m.day != b.m.day:
			return a.m.day < b.m.day
		return Data.city_distance(home, Game.club(a.m.h).city) < Data.city_distance(home, Game.club(b.m.h).city))
	page.add_child(_typed(T.t("matches_sorted"), 15, C_INK2))
	var cur_day := ""
	for wm in ms:
		if wm.m.day != cur_day:
			cur_day = wm.m.day
			_section(T.t(cur_day + "_long"), null, "calendar")
		var key := Game.match_key(wm.lg, wm.idx)
		_match_ticket(page, key, wm.m, Game.s.plan[wm.m.day] == key)
	_btn(T.t("go_weekend"), _play_weekend, "primary", page, "ball")

func _week_u19() -> void:
	_title(T.t("u19_title"), null, 34, "youth")
	page.add_child(_hand(T.t("u19_hint"), 26, C_INK2))
	if Game.s.week < 1:
		_empty(page, "youth", T.t("u19_preseason"))
		return
	if not Game.wed_free():
		_empty(page, "youth", T.t("wed_used"))
		return
	var home: String = Game.my_club().city
	var fx: Array = Game.s.u19fx.duplicate()
	var order := []
	for i in fx.size():
		order.append([Data.city_distance(home, Game.club(fx[i].h).city), i])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for o in order.slice(0, 10):
		var i: int = o[1]
		var f: Dictionary = fx[i]
		var hc := Game.club(f.h)
		var ac := Game.club(f.a)
		var info := Game.travel_info(hc.city)
		var h := _ticket(page, C_CARD, C_BLUE)
		var stub := VBoxContainer.new()
		stub.custom_minimum_size = Vector2(72, 0)
		stub.alignment = BoxContainer.ALIGNMENT_CENTER
		var dl := _lbl(T.t("d2").to_upper(), 22, C_INK, false, F_HEAD)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stub.add_child(dl)
		var ul := _lbl("U19", 16, C_BLUE, false, F_TYPEB)
		ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stub.add_child(ul)
		h.add_child(stub)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(8, 0)
		h.add_child(gap)
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 0)
		var tr := HBoxContainer.new()
		tr.add_child(_crest(hc, 28))
		tr.add_child(_lbl("%s – %s" % [hc.short, ac.short], 22, C_INK, false, F_HEAD))
		tr.add_child(_crest(ac, 28))
		mid.add_child(tr)
		mid.add_child(_typed("%s • %s • %s" % [T.t("league_" + hc.league), hc.city, Game.money_str(info.cost)], 15, C_INK2))
		h.add_child(mid)
		var idx := i
		var b := _btn(T.t("go_u19"), func(): _watch_u19(idx), "small", h, "eye")
		b.custom_minimum_size = Vector2(150, 58)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _scr_match_plan(key: String) -> void:
	var _mm := Game.get_match(key)
	Game.ensure_squad(_mm.h)
	Game.ensure_squad(_mm.a)
	_sheet()
	_back_row()
	var m := Game.get_match(key)
	var day: String = m.day
	var planned: bool = Game.s.plan[day] == key
	var hc := Game.club(m.h)
	var ac := Game.club(m.a)
	# büyük bilet
	var hero := _card(null, "hl" if planned else "card", 22)
	_accent_top(hero, C_RED)
	var tl := _lbl(("%s • %s" % [T.t(day + "_long"), T.t("league_" + hc.league)]).to_upper(), 17, C_INK2, true, F_TYPEB)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(tl)
	var hh := _h(hero)
	for pair in [[hc, true], [ac, false]]:
		var c: Dictionary = pair[0]
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var cr := _crest(c, 78)
		cr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(cr)
		var n := _lbl(c.name, 22, C_INK, true, F_HEAD)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(n)
		hh.add_child(col)
		if pair[1]:
			var vs := _lbl("VS", 40, C_RED, false, F_HEAD)
			vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			hh.add_child(vs)
	var info := Game.travel_info(hc.city)
	_kv(hero, T.t("venue"), hc.city)
	_kv(hero, T.t("travel"), (T.t("travel_" + info.mode, [info.km]) if info.mode != "local" else T.t("travel_local")))
	_kv(hero, T.t("cost"), Game.money_str(info.cost), C_BLUE)
	if not planned:
		if Game.match_abroad(key):
			hero.add_child(_hand(T.t("abroad_cost"), 25, C_RED))
		_btn(T.t("go_match"), func():
			if Game.match_abroad(key) and not Game.board_abroad_ok(Game.club_country(m.h)):
				_toast(T.t("need_board_abroad"))
				return
			var cur: String = Game.s.plan.get(day, "")
			if cur != "" and cur != key:
				var cm := Game.get_match(cur)
				var nm := "%s – %s" % [Game.club(cm.h).get("short", "?"), Game.club(cm.a).get("short", "?")]
				if not await _confirm(T.t("plan_same_day", [T.t(day + "_long"), nm]), T.t("plan_replace"), T.t("plan_keep")):
					return
			if not Game.plan_match(day, key):
				_toast(T.t("need_travel_day"))
				return
			_refresh(), "primary", hero, "pin")
	else:
		var st := _stamp(T.t("planned_stamp"), C_RED, -6.0, 26)
		st.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hero.add_child(st)
		_btn(T.t("cancel_plan"), func():
			Game.plan_match(day, "")
			_refresh(), "ghost", hero, "cross")
		# izleme şekli
		var wc := _card(null, "paper", 16)
		_section(T.t("watch_mode"), wc, "play")
		var wmode: String = Game.watch_mode(day)
		var wh := _h(wc, 8)
		for wm in ["full", "moments"]:
			var w2: String = wm
			_expand(_btn(T.t("wm_" + wm), func():
				Game.set_watch_mode(day, w2)
				_refresh(), "toggle_on" if wmode == wm else "ghost", wh))
		wc.add_child(_typed(T.t("wm_" + wmode + "_d"), 16, C_INK2))
		var fc := _card(null, "memo", 20)
		_section(T.t("focus_title") + "  %d/%d" % [Game.s.plan["focus_" + day].size(), Game.focus_cap(day)], fc, "eye")
		fc.add_child(_hand(T.t("focus_hint"), 25, C_BLUE))
	if sub.match != "h" and sub.match != "a":
		sub.match = "h"
	var tabs := _tabs(page, [["h", hc.short + " • " + T.t("squad")], ["a", ac.short + " • " + T.t("squad")]], sub.match, _sub_cb("match"))
	var cid: String = m.h if sub.match == "h" else m.a
	var c := Game.club(cid)
	var v := _card(null, "paper", 14)
	var xi := Game.best_xi(cid)
	var others := []
	for pid in c.squad:
		if not (pid in xi):
			others.append(pid)
	v.add_child(_typed(T.t("probable_xi"), 16, C_INK2))
	for pid in xi:
		_player_row(v, pid, day if planned else "", true)
	_rule(v)
	v.add_child(_typed(T.t("bench"), 16, C_INK2))
	for pid in others:
		_player_row(v, pid, day if planned else "", false)

func _player_row(parent: Control, pid: String, focus_day := "", starter := true) -> void:
	var p := Game.player(pid)
	if p.is_empty():
		return
	var focused: bool = focus_day != "" and pid in Game.s.plan["focus_" + focus_day]
	var row := _h(parent, 8)
	var rb := _row_button(row, 82, "hl" if focused else "card")
	var b: Button = rb[0]
	var inner: HBoxContainer = rb[1]
	var av := _avatar(p, 58)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(av)
	var pb := VBoxContainer.new()
	pb.alignment = BoxContainer.ALIGNMENT_CENTER
	_pos_badge(p.pos, pb)
	inner.add_child(pb)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -2)
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := Game.pname(p) + ("  ★" if pid in Game.s.scout.shortlist else "") + ("  ✚" if int(p.inj) > 0 else "")
	var nl := _lbl(nm, 21, C_INK if starter else C_INK2, false, F_SEMI)
	nl.clip_text = true
	nv.add_child(nl)
	var o := Game.ovr_range(pid)
	nv.add_child(_typed("%d %s • %s%s" % [int(p.age), T.t("yo"), p.nat, "  U19" if p.youth else ""], 15, C_INK2, false))
	inner.add_child(nv)
	var est := _hand(_star_txt(o), 26, C_BLUE if not o.is_empty() else C_INK2, false)
	inner.add_child(est)
	_ignore_all(inner)
	b.pressed.connect(func():
		if _dragged:
			return
		_show("player", pid))
	if focus_day != "":
		var fb := Button.new()
		fb.custom_minimum_size = Vector2(74, 74)
		fb.mouse_filter = Control.MOUSE_FILTER_PASS
		var eic = Icon.new().setup("eye", C_INK if focused else C_INK2, 34)
		eic.position = Vector2(20, 20)
		fb.add_child(eic)
		fb.add_theme_stylebox_override("normal", _sb(C_HL if focused else C_CARD, 10, 2, C_INK if focused else Color(C_INK, 0.3), 8))
		fb.add_theme_stylebox_override("hover", _sb(C_HL if focused else C_CARD, 10, 2, C_INK, 8))
		fb.add_theme_stylebox_override("pressed", _sb(C_HL, 10, 2, C_INK, 8))
		fb.pressed.connect(func():
			if _dragged:
				return
			Game.toggle_focus(focus_day, pid)
			_refresh())
		_press_fx(fb)
		row.add_child(fb)

# ================================================================ GÖREVLER

func _scr_tasks() -> void:
	_sheet([["requests", T.t("st_requests")], ["reports", T.t("st_reports")], ["transfers", T.t("st_transfers")]], sub.tasks, _sub_cb("tasks"))
	match sub.tasks:
		"reports":
			_tasks_reports()
		"transfers":
			_tasks_transfers()
		_:
			_tasks_requests()

func _tasks_requests() -> void:
	_title(T.t("tasks_title"), null, 34, "task")
	var mgr: Dictionary = Game.my_club().get("manager", {})
	var any := false
	for a in Game.s.assign:
		any = true
		var open: bool = a.status == "open"
		var v := _card(null, "memo", 20)
		var top := _h(v)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", -2)
		tv.add_child(_typed(T.t("memo_from", [mgr.get("name", "")]).to_upper(), 15, C_INK2))
		tv.add_child(_head(T.t("kind_" + a.kind).to_upper(), 28))
		tv.add_child(_lbl(T.t("pos_" + a.pos), 21, C_INK, true, F_SEMI))
		top.add_child(tv)
		var stc: Color = {"open": C_BLUE, "submitted": C_BRASS.darkened(0.2), "done": C_GREEN, "expired": C_RED}.get(a.status, C_INK)
		top.add_child(_stamp(T.t("status_" + a.status), stc, 8.0, 20))
		if a.has("why"):
			var ref: String = a.get("ref", "")
			var rp := Game.player(ref)
			var rname: String = Game.pname(rp) if not rp.is_empty() else ref
			if a.get("urgent", false):
				top.add_child(_stamp(T.t("urgent"), C_RED, -6.0, 18))
			v.add_child(_hand(T.t("why_" + String(a.why), [rname]), 26, C_BLUE))
		else:
			v.add_child(_hand(T.t("memo_" + a.kind), 26, C_BLUE))
		var sh: Array = Game.shadow_of(a.pos)
		if not sh.is_empty() and open:
			var names := []
			for spid in sh:
				var sp := Game.player(spid)
				if not sp.is_empty():
					names.append(Game.short_name(sp))
			v.add_child(_typed(T.t("shadow_ready", [", ".join(names)]), 16, C_GREEN))
		_kv(v, T.t("max_age"), "≤ %d" % int(a.max_age))
		_kv(v, T.t("max_value"), Game.money_str(a.max_value), C_GREEN)
		var lh := _h(v)
		lh.add_child(_typed((T.t("pa_est") if a.kind in ["prospect", "wonderkid"] else T.t("ovr_est")) + ":", 18, C_INK2, false))
		var st := Stars.new()
		st.setup(Game.assignment_need_stars(a), -1.0, 24)
		lh.add_child(st)
		if open:
			var left: int = int(a.deadline) - Game.s.week
			var dh := _h(v)
			dh.add_child(_lbl(T.t("weeks_left", [max(0, left)]), 18, C_RED if left <= 2 else C_INK2, false, F_TYPEB))
			_bar(dh, clampf(float(left) / 16.0, 0.0, 1.0), C_RED if left <= 2 else C_INK, 10).size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var aa: Dictionary = a
			_btn(T.t("find_players"), func():
				search_f = {"tier": 0, "grp": Data.POS_GROUP[aa.pos], "max_age": int(aa.max_age), "sort": "known", "known": false, "youth_only": aa.kind == "wonderkid"}
				sub.players = "youth" if aa.kind == "wonderkid" else "search"
				_goto_tab("players"), "small", v, "search")
	if not any:
		_empty(page, "task", T.t("no_tasks"))

func _tasks_reports() -> void:
	_title(T.t("my_reports"), null, 34, "report")
	var reps: Array = Game.s.scout.reports.duplicate()
	reps.reverse()
	if reps.is_empty():
		_empty(page, "report", T.t("no_reports"))
	for r in reps.slice(0, 40):
		var p := Game.player(r.pid)
		if p.is_empty():
			continue
		var rb := _row_button(page, 108)
		var b: Button = rb[0]
		var inner: HBoxContainer = rb[1]
		var av := _avatar(p, 64)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(av)
		var nv := VBoxContainer.new()
		nv.add_theme_constant_override("separation", -2)
		nv.alignment = BoxContainer.ALIGNMENT_CENTER
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nl := _lbl(Game.pname(p), 22, C_INK, false, F_SEMI)
		nl.clip_text = true
		nv.add_child(nl)
		nv.add_child(_typed("%s • %d/H%d" % [T.t("rec_" + r.rec), int(r.season), int(r.week)], 15, C_INK2, false))
		nv.add_child(_hand("%s★ / %s★" % [_fs(float(r.cur)), _fs(float(r.pot))], 24, C_BLUE, false))
		inner.add_child(nv)
		var sc: Color = {"signed": C_GREEN, "rejected": C_RED, "agreed": C_BLUE, "pending": C_BRASS.darkened(0.25)}.get(r.status, C_INK2)
		inner.add_child(_stamp(T.t("rep_status_" + r.status), sc, -8.0, 17))
		_ignore_all(inner)
		var pid: String = r.pid
		b.pressed.connect(func():
			if _dragged:
				return
			_show("player", pid))

func _tasks_transfers() -> void:
	_title(T.t("st_transfers"), null, 34, "swap")
	var pend: Array = Game.s.pending
	if not pend.is_empty():
		_section(T.t("pending_transfers"), null, "calendar")
		for t in pend:
			var p := Game.player(t.pid)
			if p.is_empty():
				continue
			var v := _card(null, "hl")
			var h := _h(v)
			h.add_child(_avatar(p, 56))
			var nv := _v(h, 0)
			nv.add_child(_lbl(Game.pname(p), 21, C_INK, true, F_SEMI))
			nv.add_child(_typed(T.t("joins_window", [Game.money_str(t.fee)]), 15, C_INK2))
	_section(T.t("my_signings"), null, "check")
	var any := false
	for r in Game.s.scout.reports:
		if r.status != "signed":
			continue
		var p := Game.player(r.pid)
		if p.is_empty():
			continue
		any = true
		var rb := _row_button(page, 96)
		var inner: HBoxContainer = rb[1]
		inner.add_child(_avatar(p, 56))
		var nv := VBoxContainer.new()
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.alignment = BoxContainer.ALIGNMENT_CENTER
		nv.add_theme_constant_override("separation", -2)
		nv.add_child(_lbl(Game.pname(p), 21, C_INK, false, F_SEMI))
		var avg := Game.avg_rating(p)
		nv.add_child(_typed("%d/H%d • %s • %s" % [int(r.season), int(r.week), Game.money_str(r.get("fee", 0)), ("%.2f" % avg) if avg > 0 else "-"], 15, C_INK2, false))
		inner.add_child(nv)
		_ignore_all(inner)
		var pid: String = r.pid
		rb[0].pressed.connect(func():
			if not _dragged:
				_show("player", pid))
	if not any:
		page.add_child(_hand(T.t("no_signings"), 26, C_INK2))
	_section(T.t("market_news"), null, "news")
	var n_shown := 0
	for n in Game.s.news:
		if n.get("kind", "") == "transfer" or n.key in ["n_rival_took", "n_ai_transfer"]:
			_clipping(page, n, false)
			n_shown += 1
			if n_shown >= 8:
				break
	if n_shown == 0:
		page.add_child(_hand(T.t("no_market"), 26, C_INK2))

# ================================================================ OYUNCULAR

func _scr_players() -> void:
	_sheet([["shortlist", T.t("pm_shortlist")], ["shadow", T.t("pm_shadow")], ["search", T.t("pm_search")], ["youth", T.t("pm_youth")], ["compare", T.t("pm_compare")]], sub.players, _sub_cb("players"))
	players_mode = sub.players
	match sub.players:
		"shadow":
			_players_shadow()
		"search":
			search_f.youth_only = false
			_players_search()
		"youth":
			_players_youth()
		"compare":
			_players_compare()
		_:
			_players_shortlist()

func _players_shadow() -> void:
	## Gölge kadro: her mevki için yedek aday listesi (saha düzeninde)
	_title(T.t("pm_shadow"), null, 34, "team")
	page.add_child(_typed(T.t("shadow_hint"), 15, C_INK2))
	var pitch := PanelContainer.new()
	pitch.add_theme_stylebox_override("panel", _sb(Color("#2f6b3a"), 14, 2, Color(1, 1, 1, 0.35), 10))
	page.add_child(pitch)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pitch.add_child(col)
	for row in [["LW", "ST", "RW"], ["AM"], ["CM", "DM"], ["LB", "CB", "RB"], ["GK"]]:
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 8)
		col.add_child(h)
		for pos in row:
			h.add_child(_shadow_slot(pos))
	var need := []
	for a in Game.s.assign:
		if a.status == "open":
			need.append(T.t("pos_" + a.pos))
	if not need.is_empty():
		page.add_child(_typed(T.t("shadow_need", [", ".join(need)]), 16, C_RED))

func _shadow_slot(pos: String) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(212, 0)
	pc.add_theme_stylebox_override("panel", _sb(Color(0.96, 0.94, 0.86, 0.95), 8, 1, Color(C_INK, 0.3), 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	var hd := _h(v, 6)
	var pl := _lbl(_pos_short(pos), 20, C_CARD, false, F_HEAD)
	pl.add_theme_stylebox_override("normal", _sb(C_INK, 4, 0, C_LINE, 6))
	hd.add_child(pl)
	var st := Game.starter_at(pos)
	var sp := Game.player(st)
	var sl := _lbl((Game.short_name(sp) + " (%d)" % int(sp.age)) if not sp.is_empty() else "—", 15, C_INK2, true, F_BODY)
	sl.clip_text = true
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(sl)
	var arr: Array = Game.shadow_of(pos)
	if arr.is_empty():
		v.add_child(_typed(T.t("shadow_empty"), 14, Color(C_INK, 0.45), false))
	var i := 0
	for pid in arr:
		var p := Game.player(pid)
		if p.is_empty():
			continue
		i += 1
		var id: String = pid
		var o := Game.ovr_range(pid)
		var b := _btn("%d. %s %s" % [i, Game.short_name(p), _star_txt(o)], func(): _show("player", id), "ghost", v)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 15)
	return pc

func _players_shortlist() -> void:
	_title(T.t("pm_shortlist"), null, 34, "star")
	var list: Array = Game.s.scout.shortlist.duplicate()
	if list.is_empty():
		_empty(page, "star", T.t("empty_shortlist"))
		return
	page.add_child(_typed(T.t("shortlist_hint"), 15, C_INK2))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 22)
	page.add_child(grid)
	var i := 0
	for pid in list:
		var p := Game.player(pid)
		if p.is_empty():
			continue
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		var pol := _polaroid(p, 300, Game.short_name(p), -2.5 if i % 2 == 0 else 2.0)
		pol.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(pol)
		var o := Game.ovr_range(pid)
		var pr := Game.pa_range(pid)
		var info := _hand("%s %s  %s" % [_pos_short(p.pos), _star_txt(o), ("↗" + _star_txt(pr)) if not pr.is_empty() else ""], 26, C_BLUE, false)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(info)
		var sl := _typed("%d %s • %s" % [int(p.age), T.t("yo"), Game.club(p.club).get("short", "-")], 15, C_INK2, false)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(sl)
		_ignore_all(cell)
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		var id: String = pid
		cell.gui_input.connect(func(e):
			if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _dragged:
				_show("player", id))
		grid.add_child(cell)
		i += 1

func _players_search() -> void:
	_title(T.t("pm_search"), null, 34, "search")
	var fc := _card(null, "manila", 16)
	fc.add_child(_typed(T.t("filters").to_upper(), 15, C_INK2))
	var f1 := HFlowContainer.new()
	f1.add_theme_constant_override("h_separation", 8)
	f1.add_theme_constant_override("v_separation", 8)
	fc.add_child(f1)
	var scc: String = search_f.get("country", "")
	_btn(T.t("all_leagues"), func():
		search_f.country = ""
		search_f.tier = 0
		_refresh(), "toggle_on" if scc == "" else "small", f1).custom_minimum_size = Vector2(0, 52)
	var mcc := Game.my_country()
	_btn(Data.country_name(mcc), func():
		search_f.country = mcc
		search_f.tier = 0
		_refresh(), "toggle_on" if scc == mcc else "small", f1).custom_minimum_size = Vector2(0, 52)
	_btn(T.t("country_lbl", [Data.country_name(scc)]) if scc != "" and scc != mcc else T.t("other_country"), func():
		var k := await _pick_list(T.t("pick_country"), _country_items(false), scc)
		if k != "":
			search_f.country = k
			search_f.tier = 0
			_refresh(), "toggle_on" if scc != "" and scc != mcc else "small", f1, "globe").custom_minimum_size = Vector2(0, 52)
	if scc != "" and Data.is_scout_cc(scc):
		fc.add_child(_hand(T.t("scout_country_note"), 22, C_RED))
	if scc != "" and Game.max_tier(scc) > 1 and not Data.is_scout_cc(scc):
		var f1b := HFlowContainer.new()
		f1b.add_theme_constant_override("h_separation", 8)
		f1b.add_theme_constant_override("v_separation", 8)
		fc.add_child(f1b)
		for t in range(0, Game.max_tier(scc) + 1):
			var tt: int = t
			_btn("—" if t == 0 else Game.tier_name(scc, t), func():
				search_f.tier = tt
				_refresh(), "toggle_on" if int(search_f.tier) == t else "ghost", f1b).custom_minimum_size = Vector2(0, 50)
	if scc != "" and not Data.is_scout_cc(scc):
		# yabancı ülke: aranan ligin kadroları ilk kez burada üretilir
		var tsel := int(search_f.tier)
		for t in range(1, Game.max_tier(scc) + 1):
			if (tsel == 0 and t == 1) or tsel == t:
				for lg in Game.tier_groups(scc, t):
					Game.ensure_league(lg)
	var f2 := _h(fc, 8)
	var grp_txt := T.t("all_pos") if search_f.grp == "" else T.t("grp_" + search_f.grp)
	_expand(_btn(grp_txt, func():
		search_f.grp = {"": "GK", "GK": "DEF", "DEF": "MID", "MID": "ATT", "ATT": ""}[search_f.grp]
		_refresh(), "toggle_on" if search_f.grp != "" else "small", f2))
	_expand(_btn(T.t("age_max", [search_f.max_age if search_f.max_age < 99 else "∞"]), func():
		var ages := [99, 23, 21, 19, 17]
		var i := ages.find(int(search_f.max_age))
		search_f.max_age = ages[(i + 1) % ages.size()] if i >= 0 else 99
		_refresh(), "toggle_on" if search_f.max_age < 99 else "small", f2))
	var f3 := _h(fc, 8)
	_expand(_btn(T.t("sort_" + search_f.sort), func():
		search_f.sort = {"rating": "age", "age": "value", "value": "known", "known": "rating"}[search_f.sort]
		_refresh(), "small", f3))
	_expand(_btn(T.t("only_known"), func():
		search_f.known = not search_f.known
		_refresh(), "toggle_on" if search_f.known else "small", f3))
	var list := Game.search(search_f)
	page.add_child(_typed(T.t("results", [list.size()]) + (" (max 80)" if list.size() >= 80 else ""), 16, C_INK2))
	for pid in list:
		_search_row(pid)

func _players_youth() -> void:
	_title(T.t("pm_youth"), null, 34, "youth")
	page.add_child(_hand(T.t("youth_hint"), 25, C_INK2))
	var list := Game.discovered_youth()
	list.sort_custom(func(a, b): return Game.pa_range(a).size() > Game.pa_range(b).size())
	if list.is_empty():
		_empty(page, "youth", T.t("youth_empty"))
	for pid in list:
		_search_row(pid)

func _players_compare() -> void:
	_title(T.t("pm_compare"), null, 34, "swap")
	var sl: Array = Game.s.scout.shortlist
	if sl.size() < 2:
		_empty(page, "swap", T.t("compare_need"))
		return
	compare = compare.filter(func(x): return x in sl)
	page.add_child(_hand(T.t("compare_hint"), 25, C_INK2))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 8)
	fl.add_theme_constant_override("v_separation", 8)
	page.add_child(fl)
	for pid in sl:
		var p := Game.player(pid)
		if p.is_empty():
			continue
		var id: String = pid
		_btn(Game.short_name(p), func():
			if id in compare:
				compare.erase(id)
			else:
				if compare.size() >= 2:
					compare.pop_front()
				compare.append(id)
			_refresh(), "toggle_on" if pid in compare else "small", fl).custom_minimum_size = Vector2(0, 52)
	if compare.size() < 2:
		return
	var a: String = compare[0]
	var b: String = compare[1]
	var pa := Game.player(a)
	var pb := Game.player(b)
	var hc := _card(null, "card", 16)
	var hh := _h(hc)
	for pid in [a, b]:
		var p := Game.player(pid)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pol := _polaroid(p, 220, Game.short_name(p), -2.0 if pid == a else 2.0)
		pol.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(pol)
		var l := _hand("%s %s • %d %s" % [_pos_short(p.pos), _star_txt(Game.ovr_range(pid)), int(p.age), T.t("yo")], 24, C_BLUE if pid == a else C_RED, false)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		hh.add_child(col)
	var rh := _h(hc)
	for pid in [a, b]:
		var rd = Radar.new().setup(Game.radar_data(pid), F_HEAD, 300)
		rd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rh.add_child(rd)
	var tc := _card()
	_section(T.t("compare_attrs"), tc, "report")
	var hdr := _h(tc)
	hdr.add_child(_lbl("", 16, C_INK2))
	for pid in [a, b]:
		var hl := _lbl(Game.player(pid).last, 18, C_BLUE if pid == a else C_RED, false, F_HEAD)
		hl.custom_minimum_size = Vector2(110, 0)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hdr.add_child(hl)
	for at in Data.ATTRS:
		if Data.ATTR_GROUP[at] == "gk" and pa.pos != "GK" and pb.pos != "GK":
			continue
		var ra := Game.attr_range(a, at)
		var rbb := Game.attr_range(b, at)
		var row := _h(tc)
		row.add_child(_typed(T.t("a_" + at), 17, C_INK, true))
		for pair in [[ra, rbb], [rbb, ra]]:
			var r: Array = pair[0]
			var o: Array = pair[1]
			var txt := "?" if r.is_empty() else (str(r[0]) if r[0] == r[1] else "%d–%d" % [r[0], r[1]])
			var better: bool = not r.is_empty() and not o.is_empty() and (r[0] + r[1]) > (o[0] + o[1]) + 1
			var l := _lbl(txt, 19, C_GREEN if better else C_INK, false, F_TYPEB)
			l.custom_minimum_size = Vector2(110, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(l)

func _search_row(pid: String) -> void:
	var p := Game.player(pid)
	if p.is_empty():
		return
	var rb := _row_button(page, 108)
	var b: Button = rb[0]
	var inner: HBoxContainer = rb[1]
	var av := _avatar(p, 72)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inner.add_child(av)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	_pos_badge(p.pos, top)
	var nm := _lbl(Game.pname(p), 21, C_INK, false, F_SEMI)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	nv.add_child(top)
	var cl := Game.club(p.club)
	var avg := Game.avg_rating(p)
	var line := "%d %s • %s • %s%s" % [int(p.age), T.t("yo"), p.nat, cl.get("short", "-"), " U19" if p.youth else ""]
	if not p.youth:
		line += " • %d %s • %s" % [p.st.apps, T.t("apps_s"), ("%.2f" % avg) if avg > 0 else "-"]
	var ll := _typed(line, 15, C_INK2, false)
	ll.clip_text = true
	nv.add_child(ll)
	inner.add_child(nv)
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_theme_constant_override("separation", -4)
	var o := Game.ovr_range(pid)
	var pr := Game.pa_range(pid)
	var l1 := _hand(_star_txt(o), 28, C_BLUE if not o.is_empty() else C_INK2, false)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(l1)
	if not pr.is_empty():
		var l2 := _hand("↗ " + _star_txt(pr), 22, C_GREEN, false)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rv.add_child(l2)
	var kp := int(Game.known_fraction(pid) * 100)
	var l3 := _typed("%d%%" % kp, 14, C_INK2, false)
	l3.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(l3)
	inner.add_child(rv)
	_ignore_all(inner)
	b.pressed.connect(func():
		if _dragged:
			return
		_show("player", pid))

# ================================================================ OYUNCU DOSYASI

func _scr_player(pid: String) -> void:
	var p := Game.player(pid)
	_sheet([["file", T.t("pt_file")], ["attrs", T.t("pt_attrs")], ["notes", T.t("pt_notes")], ["career", T.t("pt_career")]], sub.player, _sub_cb("player"))
	_back_row()
	if p.is_empty():
		page.add_child(_lbl("—"))
		return
	_player_header(pid, p)
	match sub.player:
		"attrs":
			_player_attrs(pid, p)
		"notes":
			_player_notes(pid, p)
		"career":
			_player_career(pid, p)
		_:
			_player_file(pid, p)

func _player_header(pid: String, p: Dictionary) -> void:
	var cl := Game.club(p.club)
	var card := _card(null, "manila", 20)
	_clip_deco(_card_panel(card))
	var top := _h(card, 16)
	var pol := _polaroid(p, 210, "", -3.0)
	pol.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(pol)
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_theme_constant_override("separation", 2)
	top.add_child(rv)
	rv.add_child(_typed(T.t("dossier_no", [String(pid).substr(1)]).to_upper(), 14, C_INK2))
	rv.add_child(_lbl(String(p.first).to_upper(), 22, C_INK, true, F_HEADR))
	rv.add_child(_lbl(String(p.last).to_upper(), 36, C_INK, true, F_HEAD))
	var ph := HBoxContainer.new()
	_pos_badge(p.pos, ph)
	ph.add_child(_typed(T.t("pos_" + p.pos), 16, C_INK2, false))
	rv.add_child(ph)
	if not cl.is_empty():
		var chh := HBoxContainer.new()
		chh.add_child(_crest(cl, 30))
		var cn := _lbl(cl.name, 17, C_INK, true, F_SEMI)
		chh.add_child(cn)
		rv.add_child(chh)
	var o := Game.ovr_range(pid)
	var big := _hand(_star_txt(o), 44, C_BLUE if not o.is_empty() else C_INK2, false)
	rv.add_child(big)
	# mühürler
	var stamps := HFlowContainer.new()
	stamps.add_theme_constant_override("h_separation", 6)
	card.add_child(stamps)
	if pid in Game.s.scout.shortlist:
		stamps.add_child(_stamp(T.t("st_tracking"), C_BLUE, -5.0, 17))
	if Game.shadow_slot_of(pid) != "":
		stamps.add_child(_stamp(T.t("st_shadow", [_pos_short(Game.shadow_slot_of(pid))]), C_INK, 3.0, 17))
	if p.youth:
		stamps.add_child(_stamp("U19", C_GREEN, 4.0, 17))
	if int(p.inj) > 0:
		stamps.add_child(_stamp(T.t("st_injured", [int(p.inj)]), C_RED, -3.0, 17))
	if p.get("rival", "") != "":
		stamps.add_child(_stamp(T.t("rival_chip", [Game.club(p.rival).short]), C_RED, 6.0, 17))
	var sh := _h(card)
	var in_sl: bool = pid in Game.s.scout.shortlist
	_expand(_btn(T.t("shortlist_remove") if in_sl else T.t("shortlist_add"), func():
		Game.toggle_shortlist(pid)
		_refresh(), "toggle_on" if in_sl else "small", sh, "star"))
	if not cl.is_empty():
		var cid: String = cl.id
		_expand(_btn(cl.short, func(): _show("club", cid), "small", sh, "shirt"))
	if p.club != Game.s.scout.club_id:
		var slot := Game.shadow_slot_of(pid)
		var ppos: String = p.pos
		var b := _btn(T.t("shadow_remove") if slot != "" else T.t("shadow_add", [_pos_short(ppos)]), func():
			if slot != "":
				Game.shadow_remove(pid)
			elif not Game.shadow_add(pid, ppos):
				_toast(T.t("shadow_full"))
				return
			else:
				_toast(T.t("shadow_added"))
			_refresh(), "toggle_on" if slot != "" else "small", card, "team")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _player_file(pid: String, p: Dictionary) -> void:
	var cl := Game.club(p.club)
	var kn: Dictionary = Game.s.scout.knowledge.get(pid, {})
	var o := Game.ovr_range(pid)
	var pr := Game.pa_range(pid)
	# kimlik
	var idc := _card()
	_section(T.t("identity"), idc, "report")
	_kv(idc, T.t("age"), "%d" % int(p.age))
	_kv(idc, T.t("nation"), p.nat)
	_kv(idc, T.t("foot"), T.t("foot_" + p.foot))
	_kv(idc, T.t("value"), Game.money_str(p.value), C_GREEN)
	_kv(idc, T.t("contract"), str(int(p.contract)))
	_kv(idc, T.t("agent"), p.agent)
	# değerlendirme
	var ev := _card()
	_section(T.t("your_view"), ev, "eye")
	var kp := Game.known_fraction(pid)
	var kh := _h(ev)
	kh.add_child(_typed(T.t("knowledge"), 17, C_INK2, false))
	_bar(kh, kp, C_BLUE, 12).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kh.add_child(_lbl("%d%%" % int(kp * 100), 20, C_INK, false, F_HEAD))
	ev.add_child(_typed(T.t("seen_count", [int(kn.get("seen", 0)), int(kn.get("vid", 0))]) + ("  •  " + T.t("met_yes") if kn.get("met", false) else ""), 15, C_INK2))
	for row in [[T.t("ovr_est"), o], [T.t("pa_est"), pr]]:
		var r1 := _h(ev)
		var ll := _lbl(row[0], 20, C_INK, false, F_SEMI)
		ll.custom_minimum_size = Vector2(180, 0)
		r1.add_child(ll)
		var s1 := Stars.new()
		if row[1].is_empty():
			s1.set_unknown(28)
		else:
			s1.setup(Game.stars(row[1][0]), Game.stars(row[1][1]), 28)
		r1.add_child(s1)
		var stl := _hand(_star_txt(row[1]), 26, C_BLUE, false)
		stl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r1.add_child(stl)
	var rd = Radar.new().setup(Game.radar_data(pid), F_HEAD, 560)
	rd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ev.add_child(rd)
	var srs := []
	for r in Game.s.get("staff_reports", []):
		if r.pid == pid:
			srs.append(r)
	if not srs.is_empty():
		var sc := _card(null, "memo", 20)
		_section(T.t("staff_views"), sc, "team")
		for r in srs.slice(-4):
			var rh := _h(sc)
			rh.add_child(_typed(_staff_name(r.sid), 16, C_INK2, true))
			rh.add_child(_hand("%s★ / ↗%s★" % [_fs(float(r.cur)), _fs(float(r.pot))], 26, C_BLUE, false))
	# aksiyonlar
	if p.club != Game.s.scout.club_id:
		var ac := _card(null, "memo", 20)
		_section(T.t("actions") + "  •  " + T.t("days_left_s", [Game.free_days()]), ac, "calendar")
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		ac.add_child(grid)
		var acts := [["video", "play"], ["train", "cone"], ["meet", "chat"], ["coach", "phone"], ["journalist", "news"], ["agent", "wallet"]]
		for a in acts:
			var kind: String = a[0]
			var b := _btn(T.t("act_" + kind), func(): _do_action(pid, kind), "small", grid, a[1])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0, 72)
			b.add_theme_font_size_override("font_size", 18)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		ac.add_child(_typed(T.t("act_costs", [Game.money_str(Game.travel_info(cl.get("city", "")).cost) if not cl.is_empty() else "-"]), 15, C_INK2))
		_btn(T.t("act_report"), func(): _show("report", pid), "red", ac, "report")

func _player_attrs(pid: String, p: Dictionary) -> void:
	var kn: Dictionary = Game.s.scout.knowledge.get(pid, {})
	var groups := ["phy", "tec", "men"]
	if p.pos == "GK":
		groups = ["gk", "men", "phy", "tec"]
	page.add_child(_typed(T.t("attrs_hint"), 15, C_INK2))
	for g in groups:
		var gc := _card(null, "card", 16)
		_section(T.t("grp_" + g), gc)
		for a in Data.ATTRS:
			if Data.ATTR_GROUP[a] != g:
				continue
			var row := _h(gc)
			var important: bool = Data.POS_WEIGHTS[p.pos].has(a)
			var nl := _lbl(T.t("a_" + a) + (" •" if important else ""), 20, C_INK if important else C_INK2, false, F_SEMI if important else F_BODY)
			nl.custom_minimum_size = Vector2(210, 0)
			row.add_child(nl)
			var r := Game.attr_range(pid, a)
			var rb := RangeBar.new()
			rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rb.setup(r)
			row.add_child(rb)
			var vt := "?" if r.is_empty() else (str(r[0]) if r[0] == r[1] else "%d–%d" % [r[0], r[1]])
			var vl := _lbl(vt, 21, C_INK if not r.is_empty() else C_INK2, false, F_TYPEB)
			vl.custom_minimum_size = Vector2(76, 0)
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(vl)
	var hc := _card(null, "memo", 20)
	_section(T.t("hidden"), hc, "eye")
	var hid: Dictionary = kn.get("hid", {})
	for t in Data.HIDDEN:
		var row := _h(hc)
		row.add_child(_lbl(T.t("h_" + t), 20, C_INK, true, F_SEMI))
		if hid.has(t):
			var lv2 := int(hid[t].lvl)
			var good := lv2 == 2 if t != "injury_prone" else lv2 == 0
			var bad := lv2 == 0 if t != "injury_prone" else lv2 == 2
			row.add_child(_hand(T.t("lvl_%d" % lv2), 26, C_GREEN if good else (C_RED if bad else C_INK), false))
			row.add_child(_typed("(" + T.t("src_" + hid[t].src) + ")", 14, C_INK2, false))
		else:
			row.add_child(_hand("???", 26, C_INK2, false))

func _player_notes(pid: String, p: Dictionary) -> void:
	var kn: Dictionary = Game.s.scout.knowledge.get(pid, {})
	var notes: Array = kn.get("notes", [])
	if notes.is_empty():
		_empty(page, "report", T.t("no_notes"))
		return
	for n in notes:
		var vs := Game.club(n.vs)
		var nc := _card(null, "memo", 22)
		var nh := _h(nc)
		nh.add_child(_lbl("%d / H%d" % [int(n.season), int(n.week)], 20, C_RED, false, F_HEAD))
		nh.add_child(_typed("vs %s%s" % [vs.get("name", "?"), " U19" if n.get("youth", false) else ""], 17, C_INK, true))
		nh.add_child(_hand("%.1f" % float(n.r), 32, C_BLUE, false))
		if n.has("line"):
			nc.add_child(_typed(T.t(n.line[0], n.line[1]), 15, C_INK2))
		for item in n.n:
			nc.add_child(_hand("– " + T.t(item[0], item[1]), 26, C_BLUE))

func _player_career(pid: String, p: Dictionary) -> void:
	var pub := _card()
	_section(T.t("public_stats"), pub, "news")
	var avg := Game.avg_rating(p)
	var sg := _h(pub)
	for st in [[T.t("apps"), str(p.st.apps)], [T.t("goals"), str(p.st.g)], [T.t("assists"), str(p.st.a)], [T.t("avg"), ("%.2f" % avg) if avg > 0 else "-"]]:
		_stat_box(sg, st[1], st[0])
	var hc := _card()
	_section(T.t("history"), hc, "calendar")
	if p.hist.is_empty():
		hc.add_child(_hand(T.t("no_history"), 26, C_INK2))
	for hrow in p.hist:
		_kv(hc, "%d/%02d  %s" % [int(hrow.season), (int(hrow.season) + 1) % 100, hrow.club], "%d %s • %d %s • %.2f" % [int(hrow.apps), T.t("apps_s"), int(hrow.g), T.t("goals_s"), float(hrow.avg)])

# ================================================================ SAHNELER (diyaloglu eylemler)

signal dlg_next(val)
var dlg_layer: Control = null
var stage = null
var dlg_root: Control = null
var bubble: PanelContainer = null
var bubble_tail: Control = null
var bubble_name: Label = null
var bubble_text: Label = null
var bubble_owner := ""
var bubble_vp := 0
var caption_box: PanelContainer = null
var caption_text: Label = null
var note_box: PanelContainer = null
var note_list: VBoxContainer = null
var choice_box: PanelContainer = null
var dlg_choices: VBoxContainer = null
var choice_prompt: Label = null
var dlg_hint: Label = null
var spark_ui: Control = null
var vcr_ui: Control = null
var _dlg_waiting := false
var _typing: Label = null
var _type_tw: Tween = null

const SCOUT_LOOK := {"top": Color("#2a3550"), "pants": Color("#3a3d44"), "shoes": Color("#2a1a10"), "skin": 1, "hair": 0, "seed": 4}

func _scene_open(set_name: String, place: String) -> void:
	## 3D sahne + çizgi roman tarzı arayüz (konuşma balonu, anlatım kutusu, not defteri, seçenekler)
	Watch.bc("sahne " + set_name + " / " + place)
	if hub:
		hub.set_active(false)
	dlg_layer = Control.new()
	dlg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dlg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dlg_layer)
	var blk2 := ColorRect.new()
	blk2.color = Color.BLACK
	blk2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blk2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg_layer.add_child(blk2)
	stage = Stage3D.new()
	dlg_layer.add_child(stage)
	stage.setup(set_name, set_name == "phone")
	dlg_root = Control.new()
	dlg_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dlg_root.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg_layer.add_child(dlg_root)
	# alt kararma (okunabilirlik)
	var shade2 := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0.03, 0.02, 0.02, 0.7))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.55)
	gt.fill_to = Vector2(0, 1.0)
	shade2.texture = gt
	shade2.stretch_mode = TextureRect.STRETCH_SCALE
	shade2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg_root.add_child(shade2)
	# sinematik siyah bantlar
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.85)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.offset_bottom = 54
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
			bar.offset_top = -30
		dlg_root.add_child(bar)
	# mekân etiketi
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", _paper_style(C_MANILA, 14, 4, 5))
	tag.add_child(_lbl(place.to_upper(), 20, C_INK, false, F_HEAD))
	var tagw := _tilt(tag, -3.0)
	tagw.position = Vector2(20, 66)
	dlg_root.add_child(tagw)
	# anlatım kutusu (üst)
	caption_box = PanelContainer.new()
	caption_box.add_theme_stylebox_override("panel", _paper_style(C_HL.lightened(0.35), 18, 4, 6))
	caption_box.anchor_right = 1.0
	caption_box.offset_left = 24
	caption_box.offset_right = -24
	caption_box.offset_top = 128
	caption_box.visible = false
	caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_text = _lbl("", 23, C_INK, true, F_BODY)
	caption_box.add_child(caption_text)
	dlg_root.add_child(caption_box)
	# konuşma balonu
	bubble = PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color("#fffdf6")
	bs.set_corner_radius_all(26)
	bs.set_border_width_all(3)
	bs.border_color = C_INK
	bs.content_margin_left = 22
	bs.content_margin_right = 22
	bs.content_margin_top = 14
	bs.content_margin_bottom = 16
	bs.shadow_color = Color(0, 0, 0, 0.35)
	bs.shadow_size = 8
	bs.shadow_offset = Vector2(0, 4)
	bubble.add_theme_stylebox_override("panel", bs)
	bubble.custom_minimum_size = Vector2(300, 0)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 2)
	bubble.add_child(bv)
	bubble_name = _lbl("", 17, C_RED, false, F_TYPEB)
	bv.add_child(bubble_name)
	bubble_text = _lbl("", 25, C_INK, true, F_BODY)
	bubble_text.custom_minimum_size = Vector2(250, 0)
	bv.add_child(bubble_text)
	bubble.visible = false
	dlg_root.add_child(bubble)
	bubble_tail = Control.new()
	bubble_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_tail.draw.connect(_draw_tail)
	bubble_tail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dlg_root.add_child(bubble_tail)
	dlg_root.move_child(bubble_tail, bubble.get_index())
	# not defteri (alt)
	note_box = PanelContainer.new()
	note_box.add_theme_stylebox_override("panel", _paper_style(C_CARD, 20, 5, 7))
	note_box.anchor_top = 1.0
	note_box.anchor_bottom = 1.0
	note_box.anchor_right = 1.0
	note_box.offset_left = 22
	note_box.offset_right = -22
	note_box.offset_bottom = -64
	note_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	note_box.visible = false
	note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	note_box.add_child(nv)
	var nh := _h(nv, 10)
	nh.add_child(Icon.new().setup("report", C_RED, 26))
	nh.add_child(_lbl(T.t("sc_notebook").to_upper(), 17, C_RED, false, F_TYPEB))
	note_list = VBoxContainer.new()
	note_list.add_theme_constant_override("separation", -4)
	nv.add_child(note_list)
	dlg_root.add_child(note_box)
	# seçenekler (alt)
	choice_box = PanelContainer.new()
	choice_box.add_theme_stylebox_override("panel", _paper_style(C_PAPER, 18, 6, 7))
	choice_box.anchor_top = 1.0
	choice_box.anchor_bottom = 1.0
	choice_box.anchor_right = 1.0
	choice_box.offset_left = 18
	choice_box.offset_right = -18
	choice_box.offset_bottom = -54
	choice_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	choice_box.visible = false
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	choice_box.add_child(cv)
	choice_prompt = _hand("", 30, C_BLUE)
	cv.add_child(choice_prompt)
	dlg_choices = VBoxContainer.new()
	dlg_choices.add_theme_constant_override("separation", 8)
	cv.add_child(dlg_choices)
	dlg_root.add_child(choice_box)
	dlg_hint = _typed(T.t("tap_continue"), 16, C_CREAM)
	dlg_hint.anchor_left = 1.0
	dlg_hint.anchor_right = 1.0
	dlg_hint.anchor_top = 1.0
	dlg_hint.anchor_bottom = 1.0
	dlg_hint.offset_left = -260
	dlg_hint.offset_right = -24
	dlg_hint.offset_top = -30
	dlg_hint.offset_bottom = -4
	dlg_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dlg_hint.visible = false
	dlg_root.add_child(dlg_hint)
	dlg_root.gui_input.connect(_dlg_input)
	root.visible = false
	shade.visible = false
	dlg_root.modulate.a = 0.0
	create_tween().tween_property(dlg_root, "modulate:a", 1.0, 0.35)
	set_process(true)

func _dlg_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	if stage and stage.drill_on:
		if stage.try_catch():
			_spark_pop(true)
		return
	if not _dlg_waiting:
		return
	if _typing and _typing.visible_ratio < 1.0:
		if _type_tw:
			_type_tw.kill()
		_typing.visible_ratio = 1.0
		return
	_dlg_waiting = false
	dlg_next.emit("")

func _scene_tick() -> void:
	## balonu konuşanın başının üstüne yerleştir (main._process çağırır)
	if bubble == null or not bubble.visible or stage == null:
		return
	var vs := dlg_root.size
	var hp: Vector2 = stage.head_screen(bubble_owner, bubble_vp)
	var bsz := bubble.size
	var want := Vector2(vs.x * 0.5 - bsz.x * 0.5, 150)
	if hp.x >= 0.0:
		want = Vector2(hp.x - bsz.x * 0.5, hp.y - bsz.y - 70)
	want.x = clampf(want.x, 18, vs.x - bsz.x - 18)
	want.y = clampf(want.y, 70, vs.y * 0.62 - bsz.y)
	bubble.position = bubble.position.lerp(want, 0.35)
	bubble_tail.set_meta("from", bubble.position + Vector2(bsz.x * 0.5, bsz.y - 4))
	bubble_tail.set_meta("to", hp if hp.x >= 0.0 else bubble.position + Vector2(bsz.x * 0.5, bsz.y + 40))
	bubble_tail.queue_redraw()

func _draw_tail() -> void:
	if bubble == null or not bubble.visible or not bubble_tail.has_meta("from"):
		return
	var a: Vector2 = bubble_tail.get_meta("from")
	var b: Vector2 = bubble_tail.get_meta("to")
	var d := (b - a)
	var L := minf(d.length() * 0.75, 90.0)
	var tip := a + d.normalized() * L
	var perp := Vector2(-d.y, d.x).normalized() * 16.0
	var pts := PackedVector2Array([a - perp + Vector2(0, -6), tip, a + perp + Vector2(0, -6)])
	bubble_tail.draw_colored_polygon(pts, Color("#fffdf6"))
	bubble_tail.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), C_INK, 3.0, true)

func _type(lbl: Label, text: String, cps := 48.0) -> void:
	_typing = lbl
	lbl.text = text
	lbl.visible_ratio = 0.0
	if _type_tw:
		_type_tw.kill()
	_type_tw = create_tween()
	_type_tw.tween_property(lbl, "visible_ratio", 1.0, clampf(text.length() / cps, 0.25, 2.6))
	# yazı sesi: birkaç tık
	var n := mini(6, text.length() / 12 + 1)
	for i in n:
		get_tree().create_timer(i * 0.09).timeout.connect(func(): Sfx.play("blip", -20.0))

func _wait_tap() -> void:
	dlg_hint.visible = true
	_dlg_waiting = true
	await dlg_next
	dlg_hint.visible = false

## Karakter konuşur: kamera ona keser, balon başının üstünde
func _line(id: String, name: String, text: String, listener := "", vp := 0, emo := "") -> void:
	caption_box.visible = false
	choice_box.visible = false
	if stage:
		if stage.views.size() > 1:
			stage.focus_speaker(id, "", vp)
		else:
			stage.focus_speaker(id, listener, vp)
		stage.say(id, text, emo)
	bubble_owner = id
	bubble_vp = vp
	bubble_name.text = name.to_upper()
	bubble.visible = true
	bubble.size = Vector2.ZERO
	bubble.modulate.a = 0.0
	bubble.scale = Vector2(0.85, 0.85)
	bubble.pivot_offset = Vector2(150, 60)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(bubble, "modulate:a", 1.0, 0.15)
	tw.tween_property(bubble, "scale", Vector2.ONE, 0.25)
	_type(bubble_text, text)
	await _wait_tap()
	bubble.visible = false
	bubble_tail.queue_redraw()

## Anlatım kutusu (üstte)
func _caption(text: String) -> void:
	bubble.visible = false
	choice_box.visible = false
	caption_box.visible = true
	caption_box.modulate.a = 0.0
	create_tween().tween_property(caption_box, "modulate:a", 1.0, 0.2)
	_type(caption_text, text, 60.0)
	await _wait_tap()
	caption_box.visible = false

## Not defterine el yazısıyla not
func _note(text: String, col := C_BLUE) -> void:
	bubble.visible = false
	choice_box.visible = false
	note_box.visible = true
	while note_list.get_child_count() > 4:
		note_list.get_child(0).free()
	var l := _hand("– " + text, 30, col)
	note_list.add_child(l)
	Sfx.play("pen", -10.0)
	_type(l, "– " + text, 34.0)
	await _wait_tap()

func _choose(opts: Array, prompt := "") -> String:
	## opts: [[anahtar, etiket], ...]
	bubble.visible = false
	caption_box.visible = false
	note_box.visible = false
	for c in dlg_choices.get_children():
		c.queue_free()
	choice_prompt.text = prompt
	choice_prompt.visible = prompt != ""
	choice_box.visible = true
	_dlg_waiting = false
	for o in opts:
		var key: String = o[0]
		var b := _btn(o[1], func(): dlg_next.emit(key), "small", dlg_choices)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choice_box.modulate.a = 0.0
	create_tween().tween_property(choice_box, "modulate:a", 1.0, 0.2)
	var was := _busy
	_busy = false
	var val = await dlg_next
	_busy = was
	choice_box.visible = false
	for c in dlg_choices.get_children():
		c.queue_free()
	return str(val)

func _scene_close(back_to_menu := true) -> void:
	Watch.bc("sahne kapandi")
	Sfx.amb_off()
	if dlg_layer:
		dlg_layer.queue_free()
		dlg_layer = null
	stage = null
	bubble = null
	if not back_to_menu:
		return
	if hub:
		hub.set_active(true)
	root.visible = true
	_refresh()

# ---------------------------------------------------------------- kıvılcım arayüzü

func _spark_ui_build(vcr := false) -> void:
	spark_ui = Control.new()
	spark_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	spark_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg_root.add_child(spark_ui)
	var lbl := _lbl("", 54, C_HL, false, F_HEAD)
	lbl.name = "Pop"
	lbl.add_theme_color_override("font_outline_color", C_INK)
	lbl.add_theme_constant_override("outline_size", 12)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.3
	lbl.anchor_bottom = 0.3
	lbl.visible = false
	spark_ui.add_child(lbl)
	var cnt := _lbl("", 22, C_CREAM, false, F_TYPEB)
	cnt.name = "Count"
	cnt.position = Vector2(24, 128)
	spark_ui.add_child(cnt)
	if vcr:
		vcr_ui = Control.new()
		vcr_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vcr_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dlg_root.add_child(vcr_ui)
		dlg_root.move_child(vcr_ui, 1)
		var scan := ColorRect.new()
		scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform float t;\nvoid fragment(){ float l = step(0.5, fract(FRAGCOORD.y / 3.0)); float n = fract(sin(dot(FRAGCOORD.xy + t, vec2(12.9898, 78.233))) * 43758.5453); COLOR = vec4(vec3(n * 0.12), l * 0.10 + 0.06); }"
		sm.shader = sh
		scan.material = sm
		vcr_ui.add_child(scan)
		var rec := _lbl("● REC   ▶ 1×", 24, Color("#ff4d4d"), false, F_TYPEB)
		rec.position = Vector2(24, 170)
		vcr_ui.add_child(rec)
		var tc := _lbl("00:00:00", 24, C_CREAM, false, F_TYPEB)
		tc.name = "TC"
		tc.anchor_left = 1.0
		tc.anchor_right = 1.0
		tc.offset_left = -170
		tc.position.y = 170
		vcr_ui.add_child(tc)

func _spark_pop(caught: bool) -> void:
	if spark_ui == null:
		return
	var lbl: Label = spark_ui.get_node("Pop")
	lbl.text = T.t("spark_caught") if caught else T.t("spark_missed")
	lbl.add_theme_color_override("font_color", C_HL if caught else Color("#cfcfcf"))
	lbl.visible = true
	lbl.scale = Vector2(0.6, 0.6)
	lbl.pivot_offset = Vector2(360, 30)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.25)
	tw.tween_interval(0.6)
	tw.tween_callback(func(): lbl.visible = false)
	if caught:
		Sfx.play("catch", -4.0)
		Input.vibrate_handheld(60)
	(spark_ui.get_node("Count") as Label).text = "✦ %d" % stage.sparks_caught

## Gözlem aşaması: oyuncu çalışır, kıvılcımlar belirir; yakalanan sayısını döndürür
func _observe_phase(dur: float, n: int, vcr := false, focus := "all") -> int:
	_spark_ui_build(vcr)
	stage.spark_shown.connect(func(_i):
		Sfx.play("spark", -6.0)
		var lbl: Label = spark_ui.get_node("Pop")
		lbl.text = T.t("spark_now")
		lbl.add_theme_color_override("font_color", C_HL)
		lbl.visible = true)
	stage.spark_missed.connect(func(_i): _spark_pop(false))
	stage.start_drills("p", dur, n, focus)
	var t0 := Time.get_ticks_msec()
	while stage and stage.drill_on:
		await get_tree().process_frame
		if vcr_ui:
			var el := (Time.get_ticks_msec() - t0) / 1000.0
			(vcr_ui.get_node("TC") as Label).text = "00:%02d:%02d" % [int(el) / 60, int(el) % 60]
			var sc: ColorRect = vcr_ui.get_child(0)
			(sc.material as ShaderMaterial).set_shader_parameter("t", el * 37.0)
	var caught: int = stage.sparks_caught
	stage.follow = false
	if spark_ui:
		spark_ui.queue_free()
		spark_ui = null
	if vcr_ui:
		vcr_ui.queue_free()
		vcr_ui = null
	return caught

func _who_player(p: Dictionary) -> Dictionary:
	return {"name": Game.pname(p), "role": "%s • %s" % [T.t("pos_" + p.pos), Game.club(p.club).get("name", "")], "face": p, "pid": p.id}

func _who_npc(name: String, role: String, seed_v: int) -> Dictionary:
	return {"name": name, "role": role, "face": {"skin": seed_v % 4, "hair": (seed_v / 3) % 6, "seed": seed_v, "club": ""}}

func _seat(id: String, info: Dictionary, chair_x: float, face: float) -> void:
	## sandalyeye oturt: oturma klibinde pelvis 0.33 m geride
	var dir := 1.0 if face > 0.0 else -1.0
	var a = stage.add_actor(id, info, Vector3(chair_x + 0.33 * dir, 0, 0), face, "sit")
	a.set_meta("seated", true)

func _do_action(pid: String, kind: String) -> void:
	if _busy:
		return
	var p := Game.player(pid)
	var cl := Game.club(p.club)
	if Game.free_days() <= 0:
		_toast(T.t("no_wp"))
		return
	var me_name: String = Game.s.scout.name
	_busy = true
	match kind:
		"video":
			if p.youth:
				_busy = false
				_toast(T.t("no_footage"))
				return
			var vdata := Game.video_match_data(pid)
			var vs_c := Game.club(vdata.vs)
			_scene_open("video", T.t("sc_place_video"))
			stage.wide()
			await _caption(T.t("sc_video_intro2", [Game.pname(p), vs_c.get("name", "?"), int(vdata.ago)]))
			var vf := await _choose([["tec", T.t("foc_tec")], ["men", T.t("foc_men2")], ["phy", T.t("foc_phy2")]], T.t("sc_focus_q"))
			await _caption(T.t("sc_video_hint2"))
			_scene_close(false)
			_landscape(true)
			var vfe = await _run_viewer(vdata, [pid])
			_landscape(false)
			var vres := Game.finish_video(pid, vdata, vfe, vf)
			_scene_open("video", T.t("sc_place_video"))
			stage.wide()
			if vres.ok:
				if int(vres.sparks) > 0:
					await _note(T.t("sc_spark_note", [vres.sparks]), C_RED)
				for ln in vres.notes.slice(0, 3):
					await _note(T.t(ln[0], ln[1]))
				for ln in vres.lines:
					await _note(T.t(ln[0], ln[1]))
		"train":
			var is_vid := false
			_scene_open("video" if is_vid else "training", T.t("sc_place_video") if is_vid else T.t("sc_place_train", [cl.get("name", "")]))
			stage.add_actor("p", {"kind": "player", "p": p, "club": cl, "training": not is_vid}, Vector3(-10, 0, 4), PI / 2.0, "idle")
			if not is_vid:
				stage.add_mates(cl, 6)
				var me = stage.add_actor("me", SCOUT_LOOK, Vector3(-3.0, 0, 9.5), PI, "idle")
				me.overlay = "notebook"
				me.set_meta("talker", false)
			stage.wide()
			if is_vid:
				await _caption(T.t("sc_video_intro", [Game.pname(p)]))
			else:
				await _caption(T.t("sc_train_intro", [Game.pname(p), cl.get("city", "")]))
			var f := await _choose([["phy", T.t("foc_phy")], ["men", T.t("foc_men")], ["tec", T.t("foc_tec")]] if not is_vid else [["tec", T.t("foc_tec")], ["men", T.t("foc_men2")], ["phy", T.t("foc_phy2")]], T.t("sc_focus_q"))
			await _caption(T.t("sc_spark_hint"))
			var caught := await _observe_phase(34.0, 4, false, f)
			var res := Game.do_video(pid, f, caught) if is_vid else Game.do_training(pid, f, caught)
			if not is_vid:
				stage.shot(0, Vector3(-2.35, 1.62, 8.15), Vector3(-3.0, 1.35, 9.5), 3.0)
			if res.ok:
				if caught > 0:
					await _note(T.t("sc_spark_note", [caught]), C_RED)
				for ln in res.lines:
					await _note(T.t(ln[0], ln[1]))
				if res.has("trait"):
					await _note(T.t("sc_prof_%d" % int(res.trait[1])))
				if res.has("trait2"):
					await _note(T.t("sc_trait2", [T.t("q_" + res.trait2[0])]), C_RED)
				if res.lines.is_empty():
					await _note(T.t("sc_nothing"))
		"meet":
			var kn: Dictionary = Game.s.scout.knowledge.get(pid, {})
			if kn.get("met", false):
				_busy = false
				_toast(T.t("already_met"))
				return
			if not Game.can_talk(pid):
				_busy = false
				_toast(T.t("need_lang"))
				return
			var home := int(p.age) <= 18
			_scene_open("home" if home else "lobby", T.t("sc_place_home", [cl.get("city", "")]) if home else T.t("sc_place_meet", [cl.get("city", "")]))
			_seat("me", SCOUT_LOOK, -1.0, PI / 2.0)
			var pinfo := {"kind": "player", "p": p, "club": cl, "casual": true, "top": Color(cl.get("c1", "#334455")).darkened(0.25)}
			var par_name := ""
			if home:
				var pa = stage.add_actor("p", pinfo, Vector3(1.17, 0, -0.45), -PI / 2.0, "sit")
				pa.set_meta("seated", true)
				var pr = stage.add_actor("parent", {"top": Color("#6a5a4a"), "pants": Color("#2e2a26"), "skin": int(p.get("skin", 1)), "hair": 2, "seed": int(p.get("seed", 0)) + 101}, Vector3(1.17, 0, 0.5), -PI / 2.0, "sit")
				pr.set_meta("seated", true)
				par_name = T.t("parent_title", [String(p.get("last", ""))])
			else:
				_seat("p", pinfo, 1.0, -PI / 2.0)
			stage.wide()
			await _caption(T.t("sc_home_intro", [p.first]) if home else T.t("sc_meet_intro", [p.first]))
			if home:
				var plvl: int = Game.hid_level(int(p.hid.get("professionalism", 10)))
				await _line("parent", par_name, T.t("parent_%d" % plvl, [p.first]), "me", 0, ["worried", "thinking", "happy"][clampi(plvl, 0, 2)])
			var pool := ["professionalism", "adaptability", "big_match", "injury_prone", "consistency"]
			var picked := []
			for k in 2:
				var opts := []
				for tr in pool:
					if not (tr in picked):
						opts.append([tr, T.t("q_" + tr)])
				picked.append(await _choose(opts, T.t("sc_ask_q", [k + 1])))
			var res3 := Game.do_meet(pid, picked)
			if res3.ok:
				for i in res3.answers.size():
					var an: Array = res3.answers[i]
					await _line("me", me_name, T.t("q_" + str(an[0])), "p")
					await _line("p", Game.pname(p), T.t("a_%s_%d" % [an[0], int(an[1])]), "me", 0, ["worried", "thinking", "happy"][clampi(int(an[1]), 0, 2)])
					stage.listener_react("me", int(an[1]) >= 1)
				stage.wide()
				await _note(T.t("sc_meet_end"))
		_:
			var costs := {"coach": 60, "agent": 0, "journalist": 30}
			if Game.s.scout.money < int(costs[kind]):
				_busy = false
				_toast(T.t("not_enough_money"))
				return
			var nm := ""
			var look := {}
			var on_phone := kind != "journalist"
			match kind:
				"coach":
					nm = cl.get("manager", {}).get("name", "?")
					look = {"top": Color(cl.get("c1", "#334455")).darkened(0.15), "pants": Color("#1d2028"), "shoes": Color("#efefef"), "skin": hash(nm) % 4, "hair": hash(nm) % 6, "seed": 5}
				"journalist":
					nm = "%s %s" % [Data.FIRST["TR"][hash(pid) % Data.FIRST["TR"].size()], Data.LAST["TR"][hash(pid + "j") % Data.LAST["TR"].size()]]
					look = {"top": Color("#8a3a2a"), "pants": Color("#3b4a6b"), "shoes": Color("#2a1a12"), "skin": hash(nm) % 4, "hair": hash(nm) % 6, "seed": 8}
				"agent":
					nm = p.agent
					look = {"top": Color("#2b2d33"), "pants": Color("#2b2d33"), "shoes": Color("#0e0e0e"), "skin": hash(nm) % 4, "hair": hash(nm) % 6, "seed": 6}
			if on_phone:
				_scene_open("phone", T.t("sc_place_phone"))
				_seat("me", SCOUT_LOOK, 0.0, PI)
				stage.actors["me"].position = Vector3(0, 0, -0.28)
				stage.actors["me"].overlay = "phone"
				var npc = stage.add_actor("npc", look, Vector3(40, 0, 0), 0.0, "idle")
				npc.overlay = "phone"
				stage.wide(0)
				stage.wide(1)
				Sfx.play("ring", -6.0)
				await get_tree().create_timer(1.2).timeout
				await _line("npc", nm, T.t("sc_intro_" + kind, [Game.pname(p)]), "", 1)
			else:
				_scene_open("cafe", T.t("sc_place_cafe", [cl.get("city", "")]))
				_seat("me", SCOUT_LOOK, -0.98, PI / 2.0)
				_seat("npc", look, 0.98, -PI / 2.0)
				stage.wide()
				await _caption(T.t("sc_intro_" + kind, [Game.pname(p)]))
			var topics := ["professionalism", "injury_prone", "adaptability"] if kind == "coach" else (["professionalism", "big_match", "consistency", "adaptability"])
			var opts2 := []
			for tp in topics:
				opts2.append([tp, T.t("q3_" + tp, [p.first])])
			var want := await _choose(opts2, T.t("sc_what_ask"))
			await _line("me", me_name, T.t("q3_" + want, [p.first]), "npc", 0)
			var res4 := Game.do_source(pid, kind, want)
			var vp2 := 1 if on_phone else 0
			if not res4.ok:
				await _line("npc", nm, T.t(res4.msg), "me", vp2)
			elif res4.msg == "src_ok":
				await _line("npc", nm, T.t("s_%s_%d" % [res4["trait"], int(res4.lvl)], [p.first]), "me", vp2, ["worried", "thinking", "happy"][clampi(int(res4.lvl), 0, 2)])
				await _note(T.t("sc_noted_trait", [T.t("q_" + str(res4["trait"]))]))
				if kind == "agent":
					await _note(T.t("sc_agent_warn"), C_RED)
			elif res4.msg == "src_nothing":
				await _line("npc", nm, T.t("src_nothing"), "me", vp2)
			else:
				await _line("npc", nm, T.t("sc_fail_" + kind), "me", vp2)
	_busy = false
	_scene_close()

# ================================================================ RAPOR FORMU

func _scr_report(pid: String) -> void:
	_sheet()
	_back_row()
	var p := Game.player(pid)
	var form := _card(null, "card", 22)
	_accent_top(form, C_RED)
	var fh := _h(form)
	var fv := VBoxContainer.new()
	fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fv.add_theme_constant_override("separation", -2)
	fv.add_child(_typed(T.t("form_code").to_upper(), 14, C_INK2))
	fv.add_child(_head(T.t("report_title").to_upper(), 32))
	fv.add_child(_typed(Game.my_club().get("name", "") + " • " + T.t("scouting_dept"), 15, C_INK2))
	fh.add_child(fv)
	fh.add_child(_crest(Game.my_club(), 56))
	_rule(form)
	var hh := _h(form)
	hh.add_child(_avatar(p, 64))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(_head(Game.pname(p), 24))
	hv.add_child(_typed("%s • %d %s • %s" % [T.t("pos_" + p.pos), int(p.age), T.t("yo"), Game.club(p.club).get("name", "-")], 15, C_INK2))
	hh.add_child(hv)
	var open := []
	for a in Game.s.assign:
		if a.status == "open":
			open.append(a)
	var state := {"aid": open[0].id if not open.is_empty() else "", "cur": 2.5, "pot": 3.0, "rec": "sign" if not open.is_empty() else "monitor", "tags": []}
	var o := Game.ovr_range(pid)
	if not o.is_empty():
		state.cur = Game.stars((o[0] + o[1]) / 2.0)
	var pr := Game.pa_range(pid)
	state.pot = maxf(state.cur, Game.stars((pr[0] + pr[1]) / 2.0)) if not pr.is_empty() else state.cur
	# 1. talep
	var v := _card()
	_section("1. " + T.t("report_for"), v, "task")
	var task_btns := []
	if open.is_empty():
		v.add_child(_hand(T.t("no_open_task"), 26, C_RED))
	for a in open:
		var b := _btn("%s — %s (≤%d, %s)" % [T.t("kind_" + a.kind), T.t("pos_" + a.pos), int(a.max_age), Game.money_str(a.max_value)], func(): pass, "small", v)
		b.add_theme_font_size_override("font_size", 18)
		task_btns.append([b, a.id])
	var paint_tasks := func():
		for tb in task_btns:
			var on: bool = tb[1] == state.aid
			tb[0].add_theme_stylebox_override("normal", _sb(C_HL if on else C_CARD, 10, 2, C_INK if on else Color(C_INK, 0.3), 12))
	for tb in task_btns:
		var aid2: String = tb[1]
		tb[0].pressed.connect(func():
			state.aid = aid2
			paint_tasks.call())
	paint_tasks.call()
	# 2-3. yıldızlar
	var n := 2
	for which in ["cur", "pot"]:
		var w: String = which
		var sc := _card()
		_section("%d. %s" % [n, T.t("report_" + w)], sc, "star")
		n += 1
		var sh := _h(sc)
		var st := Stars.new()
		st.setup(state[w], -1.0, 44)
		sh.add_child(st)
		var vl := _hand(_fs(state[w]) + "★", 44, C_BLUE, false)
		sh.add_child(vl)
		var sl := HSlider.new()
		sl.min_value = 0.5
		sl.max_value = 5.0
		sl.step = 0.5
		sl.value = state[w]
		sl.custom_minimum_size = Vector2(0, 60)
		sl.value_changed.connect(func(val):
			state[w] = val
			st.setup(val, -1.0, 44)
			vl.text = _fs(val) + "★")
		sc.add_child(sl)
		var ref := o if w == "cur" else pr
		sc.add_child(_typed(T.t("your_estimate", [_star_txt(ref)]), 15, C_INK2))
	# 4. etiketler
	var tc := _card()
	_section("4. " + T.t("report_tags"), tc, "report")
	tc.add_child(_typed(T.t("report_tags_hint"), 15, C_INK2))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	tc.add_child(flow)
	var any_tag := false
	for a in Data.POS_WEIGHTS[p.pos]:
		var r := Game.attr_range(pid, a)
		if r.is_empty():
			continue
		var mid: float = (r[0] + r[1]) / 2.0
		var tag := ""
		var code := ""
		if mid >= 14:
			tag = "+" + T.t("a_" + a)
			code = "+" + a
		elif mid <= 9:
			tag = "−" + T.t("a_" + a)
			code = "-" + a
		if tag == "":
			continue
		any_tag = true
		var tb := Button.new()
		tb.text = tag
		tb.add_theme_font_override("font", F_TYPEB)
		tb.add_theme_font_size_override("font_size", 18)
		tb.custom_minimum_size = Vector2(0, 52)
		var good := tag.begins_with("+")
		var paint := func(on: bool):
			var c: Color = C_GREEN if good else C_RED
			tb.add_theme_stylebox_override("normal", _sb(Color(c, 0.18 if on else 0.04), 8, 2 if on else 1, Color(c, 0.9 if on else 0.4), 10))
			tb.add_theme_stylebox_override("hover", _sb(Color(c, 0.18 if on else 0.08), 8, 2, Color(c, 0.9), 10))
			tb.add_theme_color_override("font_color", c)
			tb.add_theme_color_override("font_hover_color", c)
			tb.add_theme_color_override("font_pressed_color", c)
		paint.call(false)
		var tg := code
		tb.pressed.connect(func():
			var tags: Array = state.tags
			if tg in tags:
				tags.erase(tg)
			else:
				tags.append(tg)
			paint.call(tg in tags))
		flow.add_child(tb)
	if not any_tag:
		tc.add_child(_hand(T.t("no_tags"), 24, C_INK2))
	# 5. öneri
	var rc := _card()
	_section("5. " + T.t("rec"), rc, "check")
	var rh := _h(rc)
	var rec_btns := []
	for r in ["sign", "monitor", "reject"]:
		var b := Button.new()
		b.text = T.t("rec_" + r).to_upper()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 66)
		b.add_theme_font_override("font", F_STAMP)
		b.add_theme_font_size_override("font_size", 21)
		rh.add_child(b)
		rec_btns.append([b, r])
	var paint_rec := func():
		for rb in rec_btns:
			var on: bool = rb[1] == state.rec
			var col: Color = {"sign": C_GREEN, "monitor": C_BLUE, "reject": C_RED}[rb[1]]
			for s in ["normal", "hover", "pressed"]:
				rb[0].add_theme_stylebox_override(s, _sb(Color(col, 0.16) if on else Color(0, 0, 0, 0), 4, 3 if on else 1, Color(col, 1.0 if on else 0.35), 8))
			for k in ["font_color", "font_hover_color", "font_pressed_color"]:
				rb[0].add_theme_color_override(k, col if on else Color(col, 0.55))
	for rb in rec_btns:
		var rr: String = rb[1]
		rb[0].pressed.connect(func():
			state.rec = rr
			paint_rec.call())
	paint_rec.call()
	page.add_child(_typed(T.t("report_warn"), 15, C_INK2))
	var sig := _h(page)
	sig.add_child(_typed(T.t("signature") + ":", 16, C_INK2, false))
	sig.add_child(_hand(Game.s.scout.name, 34, C_BLUE, false))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 10)
	page.add_child(holder)
	var sb := _btn(T.t("submit"), func(): pass, "red", page, "report")
	sb.pressed.connect(func():
		if _dragged or _busy:
			return
		_busy = true
		var stp := _stamp(T.t("sent_stamp"), C_RED, -8.0, 34)
		stp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		page.add_child(stp)
		page.move_child(stp, holder.get_index())
		_stamp_slam(stp)
		await get_tree().create_timer(0.55).timeout
		_busy = false
		Game.submit_report(pid, state.aid, state.cur, state.pot, state.rec, state.tags)
		Game.save_game()
		_toast(T.t("report_sent"))
		sub.tasks = "reports"
		_goto_tab("tasks"))


# ================================================================ EKİP

func _scr_team() -> void:
	_sheet([["staff", T.t("tm_staff")], ["pool", T.t("tm_pool")], ["reports", T.t("tm_reports")]], sub.team, _sub_cb("team"))
	if not Game.s.has("staff"):
		Game.s.staff = []
		Game.s.staff_pool = []
		Game.s.staff_reports = []
		Game.s.next_sid = 1
	if Game.s.staff_pool.is_empty():
		Game.refresh_staff_pool(true)
	match sub.team:
		"pool":
			_team_pool()
		"reports":
			_team_reports()
		_:
			_team_staff()

func _team_header() -> void:
	var hc := _card(null, "manila", 18)
	var h := _h(hc)
	h.add_child(Icon.new().setup("team", C_INK, 44))
	var v := _v(h, 0)
	v.add_child(_head(T.t("dept_title").to_upper(), 26))
	v.add_child(_typed(T.t("dept_sub", [Game.s.staff.size(), Game.staff_slots()]), 16, C_INK2))
	_kv(hc, T.t("staff_wages"), T.t("salary_w", [Game.money_str(Game.staff_cost())]), C_RED)
	var langs := []
	for l in Game.team_langs():
		langs.append(T.t("lang_" + l))
	_kv(hc, T.t("team_langs"), ", ".join(langs))
	hc.add_child(_typed(T.t("slots_hint"), 14, C_INK2))

func _staff_card(parent: Control, m: Dictionary, hire := false) -> void:
	var v := _card(parent, "card", 18)
	_accent_top(v, {"scout": C_RED, "video": C_BLUE, "data": C_GREEN}[m.role])
	var h := _h(v, 12)
	var face := {"club": "", "skin": m.get("skin", 1), "hair": m.get("hair", 0), "seed": 0, "pos": "CM", "first": m.name, "last": ""}
	h.add_child(_avatar(face, 72))
	var nv := _v(h, -2)
	nv.add_child(_head(m.name, 24))
	nv.add_child(_typed("%s • %d %s • %s" % [T.t("role_" + m.role), int(m.age), T.t("yo"), m.nat], 15, C_INK2))
	var ls := []
	for l in m.langs:
		ls.append(l)
	nv.add_child(_typed(T.t("langs_s") + ": " + ", ".join(ls), 14, C_INK2))
	if m.has("offer"):
		h.add_child(_stamp(T.t("st_poached"), C_RED, 8.0, 16))
	# yetenek çubukları
	for pair in [[T.t("eye"), int(m.eye)], [T.t("net"), int(m.net)]]:
		var r := _h(v)
		var l := _lbl(pair[0], 18, C_INK, false, F_SEMI)
		l.custom_minimum_size = Vector2(160, 0)
		r.add_child(l)
		_bar(r, float(pair[1]) / 20.0, C_BLUE, 10).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(_lbl(str(pair[1]), 20, C_INK, false, F_HEAD))
	var spec: String = m.get("spec", "")
	if spec != "":
		_kv(v, T.t("spec"), T.t("spec_" + spec))
	_kv(v, T.t("salary"), T.t("salary_w", [Game.money_str(m.salary)]), C_RED)
	if not hire:
		_kv(v, T.t("character"), T.t("pers_" + m.pers) if Game.staff_pers_known(m) else T.t("pers_unknown"))
		_kv(v, T.t("morale"), "%d%%" % int(m.morale))
		_kv(v, T.t("staff_reports_n"), str(int(m.reports)))
		var id: String = m.id
		if m.role == "scout":
			v.add_child(_typed(T.t("assign_region").to_upper(), 14, C_INK2))
			var fl := GridContainer.new()
			fl.columns = 2
			fl.add_theme_constant_override("h_separation", 6)
			fl.add_theme_constant_override("v_separation", 6)
			v.add_child(fl)
			for rg in Game.regions():
				var r2: String = rg
				var lang_ok := false
				for l in Game.region_langs(rg):
					if l in m.langs:
						lang_ok = true
				var locked: bool = Game.region_abroad(rg) and not (rg in Game.board().abroad)
				var rb := _btn(T.t("rg_" + rg) + ("" if lang_ok else " (!)") + ((" • " + T.t("locked_s")) if locked else ""), func():
					if locked:
						_toast(T.t("need_board_abroad"))
						return
					Game.assign_staff(id, r2)
					_refresh(), "toggle_on" if m.region == rg else "ghost", fl)
				rb.custom_minimum_size = Vector2(0, 50)
				rb.autowrap_mode = TextServer.AUTOWRAP_OFF
				rb.clip_text = true
				rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				rb.add_theme_font_size_override("font_size", 17)
				if locked:
					rb.modulate = Color(1, 1, 1, 0.55)
			if m.region != "" and Game.region_langs(m.region).filter(func(l): return l in m.langs).is_empty():
				v.add_child(_hand(T.t("lang_warn"), 24, C_RED))
		else:
			v.add_child(_hand(T.t("role_desc_" + m.role), 24, C_BLUE))
		var bh := _h(v)
		if m.has("offer"):
			_expand(_btn(T.t("give_raise"), func():
				Game.raise_staff(id)
				_toast(T.t("raise_done"))
				_refresh(), "red", bh, "wallet"))
		_expand(_btn(T.t("fire"), func():
			Game.fire_staff(id)
			_refresh(), "danger", bh, "cross"))
	else:
		v.add_child(_hand(T.t("role_desc_" + m.role), 24, C_BLUE))
		var id2: String = m.id
		_btn(T.t("hire"), func():
			var res := Game.hire_staff(id2)
			_toast(T.t(res))
			if res == "staff_hired":
				sub.team = "staff"
			_refresh(), "red", v, "check")

func _team_staff() -> void:
	_team_header()
	if Game.s.staff.is_empty():
		_empty(page, "team", T.t("no_staff"))
		_btn(T.t("tm_pool"), func():
			sub.team = "pool"
			_refresh_soft(), "primary", page, "search")
		return
	for m in Game.s.staff:
		_staff_card(page, m)

func _team_pool() -> void:
	_title(T.t("tm_pool"), null, 34, "search")
	page.add_child(_hand(T.t("pool_hint"), 25, C_INK2))
	if Game.s.staff.size() >= Game.staff_slots():
		page.add_child(_hand(T.t("staff_full"), 25, C_RED))
	for m in Game.s.staff_pool:
		_staff_card(page, m, true)

func _staff_name(sid: String) -> String:
	for m in Game.s.staff:
		if m.id == sid:
			return m.name
	return "—"

func _team_reports() -> void:
	_title(T.t("tm_reports"), null, 34, "report")
	var reps: Array = Game.s.get("staff_reports", []).duplicate()
	reps.reverse()
	if reps.is_empty():
		_empty(page, "report", T.t("no_staff_reports"))
		return
	for r in reps.slice(0, 40):
		var p := Game.player(r.pid)
		if p.is_empty():
			continue
		var rb := _row_button(page, 116)
		var inner: HBoxContainer = rb[1]
		var av := _avatar(p, 66)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(av)
		var nv := VBoxContainer.new()
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.alignment = BoxContainer.ALIGNMENT_CENTER
		nv.add_theme_constant_override("separation", -2)
		var top := HBoxContainer.new()
		_pos_badge(p.pos, top)
		var nl := _lbl(Game.pname(p), 20, C_INK, false, F_SEMI)
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nl)
		nv.add_child(top)
		nv.add_child(_typed("%d %s • %s • %s" % [int(p.age), T.t("yo"), Game.club(p.club).get("short", "-"), T.t("from_staff", [_staff_name(r.sid)])], 14, C_INK2, false))
		nv.add_child(_hand(T.t(r.note), 22, C_BLUE, false))
		inner.add_child(nv)
		var sv := VBoxContainer.new()
		sv.alignment = BoxContainer.ALIGNMENT_CENTER
		sv.add_child(_hand("%s★" % _fs(float(r.cur)), 28, C_INK, false))
		sv.add_child(_hand("↗ %s★" % _fs(float(r.pot)), 22, C_GREEN, false))
		inner.add_child(sv)
		_ignore_all(inner)
		var pid: String = r.pid
		rb[0].pressed.connect(func():
			if not _dragged:
				_show("player", pid))

# ================================================================ DÜNYA: gazete / ligler / fikstür

func _clipping(parent: Control, n: Dictionary, big: bool) -> void:
	## Gazete kupürü
	var kind: String = n.get("kind", "")
	var col: Color = {"tip": C_BLUE, "good": C_GREEN, "bad": C_RED, "career": C_BRASS.darkened(0.2), "transfer": C_INK, "club": C_RED}.get(kind, C_INK2)
	var v := _card(parent, "paper" if not big else "card", 16 if not big else 22)
	var h := _h(v, 8)
	var kl := _lbl(T.t("nk_" + (kind if kind != "" else "misc")).to_upper(), 14, C_CARD, false, F_HEAD)
	kl.add_theme_stylebox_override("normal", _sb(col, 3, 0, C_LINE, 6))
	h.add_child(kl)
	h.add_child(_typed("%d • %s" % [int(n.season), T.t("preseason") if int(n.week) == 0 else T.t("week_n", [int(n.week)])], 14, C_INK2, true))
	if big:
		v.add_child(_lbl(T.t(n.key, n.args), 30, C_INK, true, F_HEAD))
	else:
		v.add_child(_lbl(T.t(n.key, n.args), 19 if not n.imp else 20, C_INK, true, F_SEMI if n.imp else F_BODY))
	_entity_links(v, n.args)

## Metindeki kulüp/oyuncu isimleri için tıklanabilir etiketler (FM tarzı)
func _entity_links(parent: Control, args: Array) -> void:
	var fl: HFlowContainer = null
	var seen := {}
	for a in args:
		if not (a is String) or seen.has(a):
			continue
		seen[a] = true
		var e := Game.find_entity(a)
		if e.is_empty():
			continue
		if fl == null:
			fl = HFlowContainer.new()
			fl.add_theme_constant_override("h_separation", 6)
			fl.add_theme_constant_override("v_separation", 6)
			parent.add_child(fl)
		if e.has("club"):
			var cid: String = e.club
			var b := _btn(a, func(): _show("club", cid), "small", fl, "")
			b.autowrap_mode = TextServer.AUTOWRAP_OFF
			b.custom_minimum_size = Vector2(0, 42)
			b.add_theme_font_size_override("font_size", 17)
			b.add_theme_color_override("font_color", C_BLUE)
		else:
			var pid: String = e.player
			var b2 := _btn(a, func(): _show("player", pid), "small", fl, "")
			b2.autowrap_mode = TextServer.AUTOWRAP_OFF
			b2.custom_minimum_size = Vector2(0, 42)
			b2.add_theme_font_size_override("font_size", 17)
			b2.add_theme_color_override("font_color", C_RED)

## Etiketi tıklanabilir yap
func _linkify(l: Label, cb: Callable) -> Label:
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	l.gui_input.connect(func(e):
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _dragged:
			cb.call())
	return l

func _scr_news() -> void:
	_sheet([["news", T.t("wt_news")], ["table", T.t("wt_table")], ["fixtures", T.t("wt_fixtures")]], sub.news, _sub_cb("news"))
	match sub.news:
		"table":
			_world_table()
		"fixtures":
			_world_fixtures()
		_:
			_world_news()

func _world_news() -> void:
	# gazete başlığı
	var mast := VBoxContainer.new()
	mast.add_theme_constant_override("separation", 0)
	page.add_child(mast)
	mast.add_child(_dash_rule(Color(C_INK, 0.8)))
	var t := _lbl(T.t("paper_name"), 50, C_INK, true, F_HEAD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mast.add_child(t)
	var dl := _typed("%s  •  %d/%02d  •  %s" % [T.t("paper_motto"), Game.s.season, (Game.s.season + 1) % 100, T.t("preseason") if Game.s.week == 0 else T.t("week_n", [Game.s.week])], 14, C_INK2)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mast.add_child(dl)
	mast.add_child(_dash_rule(Color(C_INK, 0.8)))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 8)
	fl.add_theme_constant_override("v_separation", 8)
	page.add_child(fl)
	for f in [["", T.t("nf_all")], ["transfer", T.t("nf_transfer")], ["tip", T.t("nf_tip")], ["club", T.t("nf_club")], ["career", T.t("nf_career")]]:
		var key: String = f[0]
		_btn(f[1], func():
			news_filter = key
			_refresh(), "toggle_on" if news_filter == key else "small", fl).custom_minimum_size = Vector2(0, 50)
	var items := []
	for n in Game.s.news:
		var k: String = n.get("kind", "")
		var ok := news_filter == ""
		match news_filter:
			"transfer":
				ok = k == "transfer" or n.key in ["n_rival_took", "n_ai_transfer", "n_joined", "n_signed", "n_agreed"]
			"tip":
				ok = k == "tip"
			"club":
				ok = k in ["club", "press"]
			"career":
				ok = k in ["career", "good", "bad"]
		if ok:
			items.append(n)
	if items.is_empty():
		_empty(page, "news", T.t("no_news"))
		return
	_clipping(page, items[0], true)
	for n in items.slice(1, 60):
		_clipping(page, n, false)

func _world_table() -> void:
	if table_lg == "" or not Game.s.table.has(table_lg):
		table_lg = Game.my_club().get("league", "SL")
	var t := Game.tier(table_lg)
	var tcc := Game.league_country(table_lg)
	var foreign := false
	var tsz: int = Game.s.table[table_lg].size()
	var nmv := 3 if tsz >= 16 else (2 if tsz >= 12 else 1)
	var tmax := Game.max_tier(tcc)
	_league_picker(table_lg, func(lg):
		table_lg = lg
		_refresh())
	_title(T.t("league_" + table_lg), null, 30, "trophy")
	var v := _card(null, "card", 12)
	var hdr := _h(v)
	hdr.add_child(_typed("#", 15, C_INK2, false))
	hdr.add_child(_typed(T.t("club"), 15, C_INK2, true))
	hdr.add_child(_typed(T.t("tbl_hdr"), 15, C_INK2, false))
	var order := Game.sorted_table(table_lg)
	var n := order.size()
	var i := 0
	for cid in order:
		i += 1
		var tb: Dictionary = Game.s.table[table_lg][cid]
		var c := Game.club(cid)
		var mine: bool = cid == Game.s.scout.club_id
		var zone := Color(0, 0, 0, 0)
		var ng := Game.tier_groups(tcc, t).size()
		if t == 1 and i == 1:
			zone = C_BRASS
		elif t == 1 and tmax == 1 and i <= 3:
			zone = C_GREEN
		elif t > 1 and i <= maxi(1, nmv / ng):
			zone = C_GREEN
		if t < tmax and i > n - nmv:
			zone = C_RED
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 54)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.add_theme_stylebox_override("normal", _sb(Color(C_HL, 0.7) if mine else (Color(C_INK, 0.03) if i % 2 == 0 else Color(0, 0, 0, 0)), 4, 0, C_LINE, 6))
		b.add_theme_stylebox_override("hover", _sb(Color(C_INK, 0.06), 4, 0, C_LINE, 6))
		b.add_theme_stylebox_override("pressed", _sb(C_HL, 4, 0, C_LINE, 6))
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.offset_left = 4
		row.offset_right = -6
		var zb := ColorRect.new()
		zb.color = zone
		zb.custom_minimum_size = Vector2(5, 0)
		row.add_child(zb)
		var nl := _lbl("%d" % i, 19, C_INK, false, F_HEAD)
		nl.custom_minimum_size = Vector2(32, 0)
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(nl)
		var cr := _crest(c, 26)
		cr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cr)
		var nm := _lbl(c.name, 18, C_INK, true, F_SEMI if mine else F_BODY)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.clip_text = true
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(nm)
		var st := _lbl("%2d  %+3d  %3d" % [tb.p, tb.gf - tb.ga, tb.pts], 19, C_INK, false, F_TYPEB)
		st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(st)
		b.add_child(row)
		_ignore_all(row)
		var id: String = cid
		b.pressed.connect(func():
			if not _dragged:
				_show("club", id))
		v.add_child(b)
	var lg := _h(page, 14)
	_chip(T.t("zone_up"), C_GREEN, lg, true)
	_chip(T.t("zone_down"), C_RED, lg, true)

func _world_fixtures() -> void:
	if fix_lg == "" or not Game.s.fixtures.has(fix_lg):
		fix_lg = Game.my_club().get("league", "SL")
	var rounds: int = Game.league_round_count(fix_lg)
	if fix_round < 0 or fix_round >= rounds:
		var cur := -1
		for w in range(maxi(1, Game.s.week), Game.WEEKS + 1):
			cur = Game.round_for_week(fix_lg, w)
			if cur >= 0:
				break
		fix_round = clampi(cur if cur >= 0 else rounds - 1, 0, rounds - 1)
	_league_picker(fix_lg, func(lg):
		fix_lg = lg
		fix_round = -1
		_refresh())
	var nav := _h(page)
	var pb := _btn("", func():
		fix_round = maxi(0, fix_round - 1)
		_refresh(), "small", nav, "back")
	pb.custom_minimum_size = Vector2(70, 58)
	var rl := _lbl(T.t("round_n", [fix_round + 1, rounds]).to_upper(), 26, C_INK, true, F_HEAD)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(rl)
	var nb := _btn("", func():
		fix_round = mini(rounds - 1, fix_round + 1)
		_refresh(), "small", nav, "arrow")
	nb.custom_minimum_size = Vector2(70, 58)
	page.add_child(_typed(T.t("league_" + fix_lg), 16, C_INK2))
	var v := _card(null, "card", 14)
	for m in Game.s.fixtures[fix_lg][fix_round]:
		var mine: bool = m.h == Game.s.scout.club_id or m.a == Game.s.scout.club_id
		var h := _h(v, 8)
		var hl := _lbl(Game.club(m.h).name, 18, C_INK, true, F_SEMI if mine else F_BODY)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hl.clip_text = true
		hl.autowrap_mode = TextServer.AUTOWRAP_OFF
		var hid: String = m.h
		_linkify(hl, func(): _show("club", hid))
		h.add_child(hl)
		var played := int(m.gh) >= 0
		var sc := _lbl(" %d - %d " % [int(m.gh), int(m.ga)] if played else T.t(m.day).to_upper(), 19, C_CARD if played else C_INK2, false, F_TYPEB)
		sc.add_theme_stylebox_override("normal", _sb(C_RED if mine and played else (C_INK if played else Color(0, 0, 0, 0.05)), 4, 0, C_LINE, 6))
		sc.custom_minimum_size = Vector2(84, 0)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(sc)
		var al := _lbl(Game.club(m.a).name, 18, C_INK, true, F_SEMI if mine else F_BODY)
		al.clip_text = true
		al.autowrap_mode = TextServer.AUTOWRAP_OFF
		var aid: String = m.a
		_linkify(al, func(): _show("club", aid))
		h.add_child(al)

func _scr_table() -> void:
	sub.news = "table"
	_goto_tab("news")

# ================================================================ KULÜP

func _scr_club(cid: String) -> void:
	Game.ensure_squad(cid)
	var c := Game.club(cid)
	_sheet([["squad", T.t("ct_squad")], ["youth", T.t("ct_youth")], ["info", T.t("ct_info")]], sub.club, _sub_cb("club"))
	_back_row()
	var v := _card()
	_accent_top(v, Color(c.c1))
	var h := _h(v)
	h.add_child(_crest(c, 80))
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", -2)
	nv.add_child(_head(c.name.to_upper(), 28))
	nv.add_child(_typed("%s • %s" % [T.t("league_" + c.league), c.city], 16, C_INK2))
	h.add_child(nv)
	match sub.club:
		"youth":
			var known_u19 := []
			for pid in c.u19:
				if Game.player(pid).get("disc", false):
					known_u19.append(pid)
			_section(T.t("u19_squad", [known_u19.size(), c.u19.size()]), null, "youth")
			if c.u19.is_empty():
				_empty(page, "youth", T.t("no_academy"))
			elif known_u19.is_empty():
				_empty(page, "youth", T.t("u19_unknown"))
			for pid in known_u19:
				_player_row(page, pid, "", true)
		"info":
			var ic := _card()
			_kv(ic, T.t("prestige"), str(c.prestige))
			_kv(ic, T.t("club_budget"), Game.money_str(c.budget), C_GREEN)
			var axi := Game.club_avg_ovr(cid)
			_kv(ic, T.t("avg_xi"), _star_txt([axi, axi]))
			var m: Dictionary = c.manager
			var mc := _card(null, "memo", 20)
			_section(T.t("manager_file"), mc, "chat")
			mc.add_child(_head(m.name, 24))
			_kv(mc, T.t("style"), T.t("style_" + m.style))
			var pref := T.t("pref_" + m.pref)
			_kv(mc, T.t("preference"), pref if pref != "" else "—")
			if Game.s.table.has(c.league) and Game.s.table[c.league].has(cid):
				var tb: Dictionary = Game.s.table[c.league][cid]
				var order := Game.sorted_table(c.league)
				_kv(ic, T.t("rank"), "%d. • %d %s" % [order.find(cid) + 1, int(tb.pts), T.t("pts")])
		_:
			var sq := _card(null, "paper", 14)
			var xi := Game.best_xi(cid)
			var ordered: Array = c.squad.duplicate()
			if Game.is_scout_club(cid):
				ordered = ordered.filter(func(x): return Game.visible(Game.player(x)))
				page.add_child(_hand(T.t("scout_country_note"), 22, C_RED))
			ordered.sort_custom(func(a, b):
				var pa := Game.player(a)
				var pb := Game.player(b)
				var ga: int = ["GK", "DEF", "MID", "ATT"].find(Data.POS_GROUP[pa.pos])
				var gb: int = ["GK", "DEF", "MID", "ATT"].find(Data.POS_GROUP[pb.pos])
				if ga != gb:
					return ga < gb
				return (a in xi) and not (b in xi))
			var cur_g := ""
			for pid in ordered:
				var g: String = Data.POS_GROUP[Game.player(pid).pos]
				if g != cur_g:
					cur_g = g
					sq.add_child(_typed(T.t("grp_" + g).to_upper(), 15, C_RED))
				_player_row(sq, pid, "", pid in xi)

# ================================================================ hafta sonucu / gözlem / sezon sonu

func _obs_card(obs: Dictionary) -> void:
	var v := _card(null, "card", 20)
	_accent_top(v, C_BLUE)
	_section(T.t("obs_title") + (" — U19" if obs.youth else ""), v, "eye")
	var hdr := _h(v)
	hdr.alignment = BoxContainer.ALIGNMENT_CENTER
	hdr.add_child(_crest(Game.club(obs.h), 46))
	var sl := _lbl("%s  %d – %d  %s" % [Game.club(obs.h).short, int(obs.gh), int(obs.ga), Game.club(obs.a).short], 34, C_INK, false, F_HEAD)
	hdr.add_child(sl)
	hdr.add_child(_crest(Game.club(obs.a), 46))
	if obs.rival != "":
		var rh := _h(v)
		rh.add_child(Icon.new().setup("eye", C_RED, 24))
		rh.add_child(_hand(T.t("rival_seen", [Game.club(obs.rival).name]), 25, C_RED))
	for pid in obs.notes:
		var p := Game.player(pid)
		if p.is_empty():
			continue
		var pc := _card(v, "memo", 18)
		var ph := _h(pc)
		ph.add_child(_avatar(p, 56))
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 0)
		pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nh := _h(pv, 8)
		nh.add_child(_head(Game.pname(p), 22))
		if obs.get("rt", {}).has(pid):
			nh.add_child(_rating_chip(float(obs.rt[pid])))
		if obs.lines.has(pid):
			pv.add_child(_typed(T.t(obs.lines[pid][0], obs.lines[pid][1]), 14, C_INK2))
		ph.add_child(pv)
		var id: String = pid
		var b := _btn("", func(): _show("player", id), "ghost", ph, "arrow")
		b.custom_minimum_size = Vector2(60, 54)
		for item in obs.notes[pid]:
			pc.add_child(_hand("– " + T.t(item[0], item[1]), 25, C_BLUE))
	if not obs.new_disc.is_empty():
		var dc := _card(v, "hl", 14)
		_section(T.t("new_disc", [obs.new_disc.size()]), dc, "youth")
		var best: Array = obs.new_disc.duplicate()
		best.sort_custom(func(a, b2): return Game.player(a).pa > Game.player(b2).pa)
		for pid in best.slice(0, 5):
			_player_row(dc, pid, "", true)
	if not obs.standouts.is_empty():
		v.add_child(_typed(T.t("standouts").to_upper(), 15, C_INK2))
		for pid in obs.standouts:
			_player_row(v, pid, "", true)
	# tüm oyuncuların maç puanları
	var rt: Dictionary = obs.get("rt", {})
	if not rt.is_empty():
		v.add_child(_typed(T.t("obs_rating").to_upper(), 15, C_INK2))
		var cols := _h(v, 10)
		for side in [obs.h, obs.a]:
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_theme_constant_override("separation", 2)
			cols.add_child(col)
			var lst := []
			for pid in rt:
				var pp := Game.player(pid)
				if not pp.is_empty() and (pp.club == side or (obs.youth and Game.club(pp.club).get("id", "") == side)):
					lst.append(pid)
			if lst.is_empty():
				for pid in rt:
					var pp2 := Game.player(pid)
					if not pp2.is_empty() and pp2.get("club", "") == side:
						lst.append(pid)
			lst.sort_custom(func(a, b2): return float(rt[a]) > float(rt[b2]))
			col.add_child(_lbl(Game.club(side).get("short", ""), 18, C_INK2, false, F_TYPEB))
			for pid in lst:
				var pp3 := Game.player(pid)
				var id2: String = pid
				var rb := _h(col, 6)
				var nb := _btn("%s %s" % [_pos_short(pp3.pos), Game.short_name(pp3)], func(): _show("player", id2), "ghost", rb)
				nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
				nb.custom_minimum_size = Vector2(0, 44)
				nb.add_theme_font_size_override("font_size", 17)
				rb.add_child(_rating_chip(float(rt[pid])))

func _rating_chip(r: float) -> Label:
	var col := C_GREEN if r >= 7.0 else (C_INK if r >= 6.0 else C_RED)
	var l := _lbl("%.1f" % r, 18, C_CARD, false, F_TYPEB)
	l.add_theme_stylebox_override("normal", _sb(col, 5, 0, C_LINE, 6))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

func _scr_obs() -> void:
	_sheet()
	_title(T.t("u19_done"), null, 36, "youth")
	if not pending_obs.is_empty():
		_obs_card(pending_obs)
	_btn(T.t("ok"), func(): _goto_tab("week"), "primary", page, "check")

func _scr_result() -> void:
	_sheet()
	var r := pending_result
	var mast := _lbl(T.t("week_report"), 44, C_INK, true, F_HEAD)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(mast)
	var dl := _typed(T.t("week_n", [Game.s.week - 1]) + "  •  " + Game.my_club().get("name", ""), 15, C_INK2)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(dl)
	page.add_child(_dash_rule(Color(C_INK, 0.7)))
	for obs in r.get("obs", []):
		if not obs.get("youth", false):
			_obs_card(obs)
	if not r.get("season_end", false):
		var lg: String = Game.my_club().league
		var rd := Game.round_for_week(lg, Game.s.week - 1)
		if Game.s.fixtures.has(lg) and rd >= 0:
			var v := _card()
			_section(T.t("results_title") + " — " + T.t("league_" + lg), v, "ball")
			for m in Game.s.fixtures[lg][rd]:
				var mine: bool = m.h == Game.s.scout.club_id or m.a == Game.s.scout.club_id
				var h := _h(v, 8)
				var hl := _lbl(Game.club(m.h).name, 18, C_INK, true, F_SEMI if mine else F_BODY)
				hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				hl.clip_text = true
				hl.autowrap_mode = TextServer.AUTOWRAP_OFF
				var hid2: String = m.h
				_linkify(hl, func(): _show("club", hid2))
				h.add_child(hl)
				var sc := _lbl(" %d - %d " % [int(m.gh), int(m.ga)], 20, C_CARD, false, F_TYPEB)
				sc.add_theme_stylebox_override("normal", _sb(C_RED if mine else C_INK, 4, 0, C_LINE, 6))
				h.add_child(sc)
				var al := _lbl(Game.club(m.a).name, 18, C_INK, true, F_SEMI if mine else F_BODY)
				al.clip_text = true
				al.autowrap_mode = TextServer.AUTOWRAP_OFF
				var aid2: String = m.a
				_linkify(al, func(): _show("club", aid2))
				h.add_child(al)
	_section(T.t("tab_news"), null, "news")
	var shown := 0
	for n in Game.s.news:
		if shown >= 6:
			break
		_clipping(page, n, shown == 0)
		shown += 1
	_btn(T.t("ok"), func():
		if r.get("season_end", false):
			_show("season", null, false)
		else:
			_goto_tab("home"), "primary", page, "check")

func _scr_season() -> void:
	var sm: Dictionary = Game.s.season_summary
	if sm.is_empty():
		_goto_tab("home")
		return
	_sheet()
	_title(T.t("season_over", [int(sm.season)]), null, 36, "trophy")
	var v := _card(null, "card", 20)
	_accent_top(v, C_BRASS)
	var ch := _h(v)
	ch.add_child(_crest(Game.club(sm.champ), 70))
	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_child(_typed(T.t("champion_t").to_upper(), 15, C_INK2))
	cv.add_child(_head(Game.club(sm.champ).name, 30))
	ch.add_child(cv)
	var moves: Dictionary = sm.get("moves", {})
	if not moves.is_empty():
		var mc := _card(null, "paper", 16)
		_section(T.t("moves_title"), mc, "swap")
		var mcc: String = moves.get("cc", Game.my_country())
		var mtt := Game.max_tier(mcc)
		if mtt <= 1:
			mc.add_child(_typed(T.t("no_moves"), 16, C_INK2))
		for t in range(2, mtt + 1):
			var ups: Array = moves.up.get(t, moves.up.get(str(t), []))
			mc.add_child(_typed("↑ %s → %s" % [Game.tier_name(mcc, t), Game.tier_name(mcc, t - 1)], 15, C_GREEN))
			mc.add_child(_lbl(", ".join(ups.map(func(c): return Game.club(c).name)), 17, C_INK))
		for t in range(1, mtt):
			var downs: Array = moves.down.get(t, moves.down.get(str(t), []))
			mc.add_child(_typed("↓ %s → %s" % [Game.tier_name(mcc, t), Game.tier_name(mcc, t + 1)], 15, C_RED))
			mc.add_child(_lbl(", ".join(downs.map(func(c): return Game.club(c).name)), 17, C_INK))
	var rc := _card(null, "manila", 20)
	_section(T.t("rep"), rc, "star")
	var big := _lbl("%d" % int(sm.rep_before), 76, C_INK, true, F_HEAD)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rc.add_child(big)
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_method(func(x): big.text = "%d" % int(round(x)), float(sm.rep_before), float(sm.rep_after), 1.4).set_trans(Tween.TRANS_CUBIC)
	var delta := float(sm.rep_after) - float(sm.rep_before)
	var dl := _hand("%+d" % int(round(delta)), 40, C_GREEN if delta >= 0 else C_RED)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rc.add_child(dl)
	if sm.get("over_budget", false):
		rc.add_child(_hand(T.t("over_budget"), 26, C_RED))
	var ev := _card()
	_section(T.t("evals"), ev, "report")
	if sm.evals.is_empty():
		ev.add_child(_hand(T.t("no_evals"), 26, C_INK2))
	for e in sm.evals:
		var p := Game.player(e.pid)
		var eh := _h(ev)
		if not p.is_empty():
			eh.add_child(_avatar(p, 52))
		var evv := VBoxContainer.new()
		evv.add_theme_constant_override("separation", 0)
		evv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		evv.add_child(_lbl(Game.pname(p), 21, C_INK, true, F_SEMI))
		evv.add_child(_typed(T.t("eval_line", [e.cur, e.pot, e.act_cur, e.act_pot, int(e.apps), "%.2f" % float(e.avg)]), 14, C_INK2))
		eh.add_child(evv)
		eh.add_child(_hand("%+.1f" % float(e.delta), 30, C_GREEN if e.delta >= 0 else C_RED, false))
	if not sm.get("promoted_youth", []).is_empty():
		var yc := _card(null, "hl")
		_section(T.t("youth_promoted"), yc, "youth")
		for pid in sm.promoted_youth.slice(0, 6):
			_player_row(yc, pid, "", true)
	if sm.get("fired", false):
		var fc := _card(null, "memo")
		var st := _stamp(T.t("fired_stamp"), C_RED, -8.0, 34)
		fc.add_child(st)
		fc.add_child(_head(T.t("fired_title"), 28, C_RED))
		_btn(T.t("offers"), func(): _show("offers", null, false), "primary", page, "arrow")
		return
	if not Game.s.offers.is_empty():
		var oc := _card()
		_section(T.t("offers"), oc, "task")
		for cid in Game.s.offers:
			var c := Game.club(cid)
			var h := _h(oc)
			h.add_child(_crest(c, 42))
			var vv := VBoxContainer.new()
			vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vv.add_theme_constant_override("separation", 0)
			vv.add_child(_lbl(c.name, 20, C_INK, true, F_SEMI))
			vv.add_child(_typed("%s • %s %d • %s" % [T.t("league_" + c.league), T.t("prestige"), c.prestige, T.t("salary_w", [Game.money_str(Game.offer_salary(c))])], 14, C_INK2))
			h.add_child(vv)
			var id: String = cid
			var b := _btn(T.t("accept"), func():
				Game.accept_offer(id)
				_goto_tab("home"), "small", h, "check")
			b.custom_minimum_size = Vector2(150, 58)
	_btn(T.t("stay"), func():
		Game.dismiss_summary()
		_goto_tab("home"), "primary", page, "home")
