extends Control
## Canlı maç izleyici v4: yatay ekran, takım şekli yapay zekâsı (savunma hattı, pres, markaj,
## koşular, bindirmeler), gerçek top/oyuncu hızları, yayın kameraları, oyun zamanı tabanlı tekrar.
## Olaylar zaman çizelgesinden gelir (bilgi modeli bunlara dayanır); hareket burada üretilir.
## finished(focus_events) sinyali: pid -> [izlenen olay indeksleri]

signal finished(focus_events: Dictionary)

const Stadium = preload("res://three/stadium.gd")
const Timeline = preload("res://sim/timeline.gd")
const LiveEngine = preload("res://sim/live_engine.gd")
const FB = preload("res://three/mocap_man.gd")
const Glass = preload("res://ui/glass.gd")
const Icon = preload("res://ui/icon.gd")

const C_ACCENT := Color("#e8c547")
const C_TEXT := Color("#eef3ef")
const C_MUTED := Color("#9db0a3")
const C_GOOD := Color("#5ccf7a")
const C_BAD := Color("#e86a5c")
const C_INK := Color("#14210f")

const RATE_FF := 3.2
const RATE_HL := 14.0
const BALL_R := 0.11

var data: Dictionary
var tl: Array
var eng
var acc := 0.0
var ev_seen := 0
var prev := {}
var prev_ball := Vector3.ZERO
var cur_ball := Vector3.ZERO
var last_kick_t := -9.0
var skip_prog := 0.0
var m: Dictionary
var youth := false
var font_head: Font
var font_body: Font

# 3D
var svc: SubViewportContainer
var sv: SubViewport
var world: Node3D
var stadium
var cam: Camera3D
var ball: MeshInstance3D
var ball_shadow: MeshInstance3D
var men := {}
var slot := {}
var cam_mode := "tv"
var cam_target := Vector3.ZERO
var cam_modes := ["tv", "wide", "stand", "goal", "player"]
var ball_vel := Vector3.ZERO
var _prev_ball := Vector3.ZERO

# oynatma
var mode := "intro"      # intro | live | replay | end
var idx := 0
var ev_time := 0.0
var ev_dur := 0.6
var rate := 1.0
var seg := {}
var speed := 1.0
var highlights := false
var paused := false
var done := false
var score := [0, 0]
var focus: Array = []
var focus_events := {}
var live := {}
var celebrate := 0.0
var scorer := ""
var skipping := false
var intro_t := 0.0
var game_t := 0.0
var replay_buf: Array = []
var replay_frames: Array = []
var replay_t := 0.0
var goal_pending_replay := false
var goal_gt := 0.0
var poss := "h"
var orient_set := false

# HUD
var hud: Control
var lbl_score: Label
var lbl_clock: Label
var ff_badge: Control
var ticker: VBoxContainer
var chips: VBoxContainer
var speed_btn: Button
var pause_icon
var cam_btn: Button
var minimap: Control
var banner: Control
var banner_lbl: Label
var banner_sub: Label
var replay_badge: Control
var letterbox: Array = []
var list_panel: PanelContainer
var intro_lbl: Label
var overlay: PanelContainer
var fader: ColorRect
var rail: HBoxContainer
var bottom_left: Control

func setup(d: Dictionary, fhead: Font, fbody: Font, initial_focus: Array) -> void:
	data = d
	eng = d.eng
	tl = eng.events
	m = d.m
	youth = d.youth
	font_head = fhead
	font_body = fbody
	for pid in initial_focus:
		if pid in m.xi_h or pid in m.xi_a:
			focus.append(pid)
	for pid in focus:
		focus_events[pid] = []

func _ready() -> void:
	print("[BC] viewer _ready")
	if get_parent() is Control:
		position = Vector2.ZERO
		size = (get_parent() as Control).size
	else:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	svc = SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	svc.gui_input.connect(_on_view_input)
	svc.material = Watch.opaque_mat()
	add_child(svc)
	sv = SubViewport.new()
	sv.own_world_3d = true
	# görünürlük tespitine güvenme (CanvasLayer içinde bazı GPU'larda hiç çizilmiyor)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var q: String = Game.quality()
	sv.msaa_3d = Viewport.MSAA_2X if q == "high" and not Game.settings.get("safe3d", false) else Viewport.MSAA_DISABLED
	# mantıksal boyut fiziksel ekrandan büyük olabilir (stretch=expand); gerçek piksele göre ölçekle
	var ratio := 1.0
	var lg := get_viewport().get_visible_rect().size
	if lg.x < lg.y:
		lg = Vector2(lg.y, lg.x)
	var ph := Vector2(DisplayServer.window_get_size())
	if ph.x < ph.y:
		ph = Vector2(ph.y, ph.x)
	if lg.x > 0 and ph.x > 0:
		ratio = clampf(minf(ph.x / lg.x, ph.y / lg.y), 0.3, 1.0)
	sv.scaling_3d_scale = clampf(Game.q_scale() * ratio * 0.92, 0.3, 1.0)
	print("[BC] viewer olcek ", sv.scaling_3d_scale, " mantiksal ", lg, " fiziksel ", ph)
	sv.audio_listener_enable_3d = false
	svc.add_child(sv)
	_build_world()
	print("[BC] viewer world ok")
	Watch.check_vp(sv, "mac", func(): stadium.disable_glow())
	_build_hud()
	_update_chips()
	_update_score()
	_start_intro()
	if Game.settings.get("sound", true):
		Sfx.crowd_on(0.35)

# ================================================================ yardımcılar

func _lbl(t: String, sz: int, col := C_TEXT, head := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", font_head if head else font_body)
	return l

func _sb(col: Color, r := 12, pad := 10, border := 0, bcol := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(r)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.set_border_width_all(border)
	s.border_color = bcol
	s.anti_aliasing = true
	return s

func _btn(t: String, cb: Callable, sz := 22) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", sz)
	b.add_theme_font_override("font", font_head)
	b.add_theme_stylebox_override("normal", _sb(Color(0.02, 0.05, 0.04, 0.72), 14, 14, 1, Color(1, 1, 1, 0.14)))
	b.add_theme_stylebox_override("hover", _sb(Color(0.05, 0.09, 0.07, 0.8), 14, 14, 1, Color(1, 1, 1, 0.2)))
	b.add_theme_stylebox_override("pressed", _sb(Color(C_ACCENT, 0.3), 14, 14, 2, C_ACCENT))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", C_TEXT)
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(cb)
	return b

func _icon_btn(icon: String, cb: Callable, text := "") -> Button:
	var b := _btn("", cb, 21)
	b.custom_minimum_size = Vector2(72, 64)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var ic = Icon.new().setup(icon, C_TEXT, 26)
	hb.add_child(ic)
	if text != "":
		var l := _lbl(text, 22, C_TEXT, true)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(l)
		b.set_meta("label", l)
		b.custom_minimum_size.x = 64 + l.get_minimum_size().x + 28
	b.set_meta("icon", ic)
	return b

func _glass_panel(radius := 18.0, tint := Color(0.04, 0.08, 0.06, 0.6)) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), int(radius), 14))
	if Game.quality() == "high":
		var g = Glass.new().setup(tint, radius)
		pc.add_child(g)
	else:
		pc.add_theme_stylebox_override("panel", _sb(Color(tint.r, tint.g, tint.b, 0.88), int(radius), 14))
	return pc

func _club_color(side: String) -> Color:
	return Color(Game.club(m.h if side == "h" else m.a).c1)

# ================================================================ HUD (yatay)

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	var safe := 28.0 if OS.has_feature("mobile") else 16.0
	# letterbox (tekrar)
	for i in 2:
		var lb := ColorRect.new()
		lb.color = Color(0, 0, 0, 0.92)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if i == 0 else Control.PRESET_BOTTOM_WIDE)
		if i == 0:
			lb.offset_bottom = 0
		else:
			lb.offset_top = 0
		hud.add_child(lb)
		letterbox.append(lb)
	# skorbord (sol üst)
	var sbx := HBoxContainer.new()
	sbx.position = Vector2(safe + 8, 18)
	sbx.add_theme_constant_override("separation", 0)
	hud.add_child(sbx)
	var hc: Dictionary = Game.club(m.h)
	var ac: Dictionary = Game.club(m.a)
	var live_badge := _lbl(" ● " + T.t("mv_live") + " ", 18, Color.WHITE, true)
	live_badge.add_theme_stylebox_override("normal", _sb(Color("#c62828"), 6, 8))
	sbx.add_child(live_badge)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(8, 0)
	sbx.add_child(gap)
	sbx.add_child(_team_tag(hc, true))
	var sc_box := PanelContainer.new()
	sc_box.add_theme_stylebox_override("panel", _sb(Color("#0b120e"), 0, 14))
	lbl_score = _lbl("0 - 0", 32, C_TEXT, true)
	sc_box.add_child(lbl_score)
	sbx.add_child(sc_box)
	sbx.add_child(_team_tag(ac, false))
	var ck := PanelContainer.new()
	ck.add_theme_stylebox_override("panel", _sb(C_ACCENT, 0, 12))
	lbl_clock = _lbl("00:00", 28, C_INK, true)
	ck.add_child(lbl_clock)
	sbx.add_child(ck)
	ff_badge = HBoxContainer.new()
	var ffp := PanelContainer.new()
	ffp.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.55), 0, 10))
	var ffh := HBoxContainer.new()
	ffh.add_theme_constant_override("separation", 4)
	ffh.add_child(Icon.new().setup("ff", C_ACCENT, 20))
	ffh.add_child(_lbl(T.t("mv_ff"), 18, C_ACCENT, true))
	ffp.add_child(ffh)
	ff_badge.add_child(ffp)
	ff_badge.visible = false
	sbx.add_child(ff_badge)
	# sağ üst kontrol rayı
	rail = HBoxContainer.new()
	rail.add_theme_constant_override("separation", 8)
	rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rail.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	rail.offset_right = -safe - 8
	rail.offset_top = 14
	rail.offset_left = -safe - 8
	hud.add_child(rail)
	cam_btn = _icon_btn("camera", _cycle_cam, T.t("cam_tv"))
	cam_btn.custom_minimum_size.x = 250
	rail.add_child(cam_btn)
	speed_btn = _btn("1x", _cycle_speed, 24)
	speed_btn.custom_minimum_size = Vector2(110, 64)
	rail.add_child(speed_btn)
	var pb := _icon_btn("pause", _toggle_pause)
	pause_icon = pb.get_meta("icon")
	rail.add_child(pb)
	rail.add_child(_icon_btn("people", _open_list, T.t("mv_players")))
	rail.add_child(_icon_btn("skip", _skip_to_end))
	# sol sütun: odak kartları
	chips = VBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.position = Vector2(safe + 8, 92)
	chips.custom_minimum_size = Vector2(300, 0)
	hud.add_child(chips)
	# sol alt: olay şeridi
	bottom_left = _glass_panel(16.0, Color(0.02, 0.05, 0.04, 0.55))
	bottom_left.anchor_top = 1.0
	bottom_left.anchor_bottom = 1.0
	bottom_left.offset_left = safe + 8
	bottom_left.offset_right = safe + 8 + 560
	bottom_left.offset_bottom = -18
	bottom_left.offset_top = -18 - 84
	bottom_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bottom_left)
	ticker = VBoxContainer.new()
	ticker.add_theme_constant_override("separation", 0)
	bottom_left.add_child(ticker)
	# sağ alt: mini harita
	minimap = Control.new()
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_right = -safe - 8
	minimap.offset_left = -safe - 8 - 300
	minimap.offset_bottom = -18
	minimap.offset_top = -18 - 194
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	hud.add_child(minimap)
	# tekrar rozeti
	replay_badge = HBoxContainer.new()
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", _sb(C_ACCENT, 6, 12))
	var rh := HBoxContainer.new()
	rh.add_child(Icon.new().setup("replay", C_INK, 28))
	rh.add_child(_lbl(T.t("mv_replay"), 28, C_INK, true))
	rp.add_child(rh)
	replay_badge.add_child(rp)
	replay_badge.position = Vector2(safe + 8, 28)
	replay_badge.visible = false
	hud.add_child(replay_badge)
	# gol bandı
	banner = Control.new()
	banner.anchor_left = 0.0
	banner.anchor_right = 1.0
	banner.anchor_top = 0.5
	banner.anchor_bottom = 0.5
	banner.offset_top = -100
	banner.offset_bottom = 100
	banner.visible = false
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band := ColorRect.new()
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	band.color = Color(C_ACCENT, 0.94)
	banner.add_child(band)
	var stripe := ColorRect.new()
	stripe.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stripe.offset_top = -10
	stripe.color = C_INK
	banner.add_child(stripe)
	var bv := VBoxContainer.new()
	bv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_theme_constant_override("separation", -8)
	banner.add_child(bv)
	banner_lbl = _lbl("GOL!", 110, C_INK, true)
	banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(banner_lbl)
	banner_sub = _lbl("", 30, C_INK, true)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(banner_sub)
	hud.add_child(banner)
	# intro yazısı
	intro_lbl = _lbl("", 34, Color.WHITE, true)
	intro_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	intro_lbl.offset_top = -200
	intro_lbl.offset_bottom = -120
	intro_lbl.offset_left = -600
	intro_lbl.offset_right = 600
	intro_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_lbl.add_theme_constant_override("outline_size", 12)
	intro_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hud.add_child(intro_lbl)
	# geçiş karartması
	fader = ColorRect.new()
	fader.color = Color(0, 0, 0, 0)
	fader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fader)
	# odak listesi
	list_panel = _glass_panel(22.0, Color(0.03, 0.06, 0.05, 0.9))
	list_panel.anchor_left = 0.5
	list_panel.anchor_right = 0.5
	list_panel.anchor_top = 0.0
	list_panel.anchor_bottom = 1.0
	list_panel.offset_left = -620
	list_panel.offset_right = 620
	list_panel.offset_top = 96
	list_panel.offset_bottom = -30
	list_panel.visible = false
	list_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(list_panel)
	overlay = _glass_panel(22.0, Color(0.03, 0.06, 0.05, 0.88))
	overlay.anchor_left = 0.5
	overlay.anchor_right = 0.5
	overlay.anchor_top = 0.5
	overlay.anchor_bottom = 0.5
	overlay.offset_left = -380
	overlay.offset_right = 380
	overlay.offset_top = -170
	overlay.offset_bottom = 170
	overlay.visible = false
	add_child(overlay)

func _team_tag(c: Dictionary, left: bool) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(Color("#121b16"), 0, 12))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	pc.add_child(h)
	var bar := ColorRect.new()
	bar.color = Color(c.c1)
	bar.custom_minimum_size = Vector2(7, 32)
	var l := _lbl(c.short + (" U19" if youth else ""), 28, C_TEXT, true)
	if left:
		h.add_child(bar)
		h.add_child(l)
	else:
		h.add_child(l)
		h.add_child(bar)
	return pc

func _toggle_pause() -> void:
	paused = not paused
	pause_icon.icon = "resume" if paused else "pause"
	pause_icon.queue_redraw()

func _cycle_speed() -> void:
	# 1x -> 2x -> Özet -> 1x
	if not highlights and speed == 1.0:
		speed = 2.0
	elif not highlights and speed == 2.0:
		speed = 1.0
		highlights = true
	else:
		speed = 1.0
		highlights = false
	speed_btn.text = T.t("mv_hl") if highlights else "%dx" % int(speed)
	paused = false
	pause_icon.icon = "pause"
	pause_icon.queue_redraw()

func _cycle_cam() -> void:
	var i := cam_modes.find(cam_mode)
	_set_cam(cam_modes[(i + 1) % cam_modes.size()])

func _set_cam(c: String) -> void:
	if c == "close":
		c = "player"
	cam_mode = c
	var l: Label = cam_btn.get_meta("label")
	l.text = T.t("cam_" + c)

func _open_list() -> void:
	list_panel.visible = true
	_fill_list()

var list_scrolls: Array = []
var list_dragged := false
var _list_drag_acc := 0.0

func _list_input(ev: InputEvent) -> void:
	## döndürülmüş ekranda kendi kaydırmamız (ScrollContainer dokunmatikte çalışmıyor)
	if not list_panel.visible:
		return
	if ev is InputEventScreenTouch and ev.pressed:
		list_dragged = false
		_list_drag_acc = 0.0
	elif ev is InputEventMouseButton and ev.pressed and not DisplayServer.is_touchscreen_available():
		list_dragged = false
		_list_drag_acc = 0.0
	elif ev is InputEventScreenDrag or (ev is InputEventMouseMotion and not DisplayServer.is_touchscreen_available() and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
		for sc: ScrollContainer in list_scrolls:
			if not is_instance_valid(sc):
				continue
			var inv := sc.get_global_transform_with_canvas().affine_inverse()
			var lp: Vector2 = inv * ev.position
			if Rect2(Vector2.ZERO, sc.size).has_point(lp):
				var rel: Vector2 = inv.basis_xform(ev.relative)
				sc.scroll_vertical -= int(rel.y)
				_list_drag_acc += absf(rel.y)
				if _list_drag_acc > 14.0:
					list_dragged = true

func _input(ev: InputEvent) -> void:
	_list_input(ev)

func _fill_list() -> void:
	list_scrolls.clear()
	var rts: Dictionary = eng.ratings(true)
	for c in list_panel.get_children():
		if c is Glass:
			continue
		c.queue_free()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.add_child(_lbl(T.t("mv_pick", [focus.size()]), 28, C_ACCENT, true))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)
	list_panel.add_child(outer)
	for side in [["h", m.xi_h], ["a", m.xi_a]]:
		var c: Dictionary = Game.club(m.h if side[0] == "h" else m.a)
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cols.add_child(sc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(v)
		v.add_child(_lbl(c.name, 24, Color(c.c1).lightened(0.3), true))
		list_scrolls.append(sc)
		for pid in side[1]:
			var p: Dictionary = Game.player(pid)
			var on: bool = pid in focus
			var id: String = pid
			var rt: float = float(rts.get(pid, 6.0))
			var offp: bool = eng.pl.has(pid) and eng.pl[pid].off
			var b := _btn("%s  %s  %s (%d)%s   %s" % ["◉" if on else "○", p.pos, Game.pname(p), int(p.age), "  ★" if pid in Game.s.scout.shortlist else "", "🟥" if offp else "%.1f" % rt], func():
				if list_dragged:
					return
				_toggle_focus(id)
				_fill_list(), 21)
			b.mouse_filter = Control.MOUSE_FILTER_PASS
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, 56)
			if on:
				b.add_theme_color_override("font_color", C_ACCENT)
			v.add_child(b)
	var close := _btn(T.t("close"), func(): list_panel.visible = false, 24)
	outer.add_child(close)

func _toggle_focus(pid: String) -> void:
	if pid in focus:
		focus.erase(pid)
	else:
		if focus.size() >= 3:
			focus.pop_front()
		focus.append(pid)
		if not focus_events.has(pid):
			focus_events[pid] = []
	_refresh_rings()
	_update_chips()

func _live_rating(st: Dictionary) -> float:
	var r := 6.2
	r += st.get("po", 0) * 0.03 - (st.get("p", 0) - st.get("po", 0)) * 0.07
	r += st.get("do", 0) * 0.15 - (st.get("d", 0) - st.get("do", 0)) * 0.06
	r += st.get("t", 0) * 0.07 + st.get("so", 0) * 0.3 + st.get("g", 0) * 0.9 + st.get("sv", 0) * 0.35
	return clampf(r, 3.5, 10.0)

func _update_chips() -> void:
	for c in chips.get_children():
		c.queue_free()
	if focus.is_empty():
		var pc0 := PanelContainer.new()
		pc0.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.45), 12, 12))
		var l := _lbl(T.t("mv_no_focus"), 18, C_MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		pc0.add_child(l)
		chips.add_child(pc0)
		return
	for pid in focus:
		var p: Dictionary = Game.player(pid)
		var st: Dictionary = live.get(pid, {})
		var side: String = men[pid].side if men.has(pid) else "h"
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(300, 0)
		pc.add_theme_stylebox_override("panel", _sb(Color(0.01, 0.03, 0.02, 0.66), 12, 12, 2, Color(C_ACCENT, 0.75)))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		pc.add_child(v)
		var top := HBoxContainer.new()
		var bar := ColorRect.new()
		bar.color = _club_color(side)
		bar.custom_minimum_size = Vector2(5, 0)
		top.add_child(bar)
		var nl := _lbl(" %s  %s" % [p.pos, Game.short_name(p)], 21, C_ACCENT, true)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		top.add_child(nl)
		var rt := _live_rating(st)
		var rl := _lbl(" %.1f " % rt, 21, C_INK, true)
		rl.add_theme_stylebox_override("normal", _sb(C_GOOD if rt >= 7.0 else (C_BAD if rt < 6.0 else C_TEXT), 6, 4))
		top.add_child(rl)
		v.add_child(top)
		v.add_child(_lbl("%s %d/%d   %s %d/%d" % [T.t("mv_pass"), st.get("po", 0), st.get("p", 0), T.t("mv_drib"), st.get("do", 0), st.get("d", 0)], 17, C_TEXT))
		v.add_child(_lbl("%s %d   %s %d" % [T.t("mv_tkl"), st.get("t", 0), T.t("mv_shot"), st.get("s", 0)], 17, C_MUTED))
		var id: String = pid
		pc.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed:
				_set_cam("player")
				focus.erase(id)
				focus.push_front(id)
				_update_chips())
		chips.add_child(pc)

func _push_ticker(text: String, col := C_TEXT) -> void:
	if skipping and not text.begins_with("⚽"):
		return
	var l := _lbl(text, 20, col)
	l.clip_text = true
	ticker.add_child(l)
	ticker.move_child(l, 0)
	l.modulate.a = 0.0
	create_tween().tween_property(l, "modulate:a", 1.0, 0.25)
	while ticker.get_child_count() > 2:
		var last := ticker.get_child(ticker.get_child_count() - 1)
		ticker.remove_child(last)
		last.queue_free()

func _update_score() -> void:
	lbl_score.text = " %d - %d " % [score[0], score[1]]

func _draw_minimap() -> void:
	var w := minimap.size.x
	var h := minimap.size.y
	minimap.draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.1, 0.05, 0.8), true)
	for i in 10:
		if i % 2 == 0:
			minimap.draw_rect(Rect2(w * i / 10.0, 0, w / 10.0, h), Color(1, 1, 1, 0.025), true)
	minimap.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.4), false, 1.5)
	minimap.draw_line(Vector2(w / 2.0, 0), Vector2(w / 2.0, h), Color(1, 1, 1, 0.3), 1.0)
	minimap.draw_arc(Vector2(w / 2.0, h / 2.0), h * 0.13, 0, TAU, 24, Color(1, 1, 1, 0.3), 1.0)
	for sx in [0.0, 1.0]:
		var bx := 0.0 if sx == 0.0 else w - w * 0.157
		minimap.draw_rect(Rect2(bx, h * 0.2, w * 0.157, h * 0.6), Color(1, 1, 1, 0.3), false, 1.0)
	var to_map := func(p: Vector3) -> Vector2:
		return Vector2((p.x + 52.5) / 105.0 * w, (p.z + 34.0) / 68.0 * h)
	for pid in men:
		var mm: Dictionary = men[pid]
		var pos: Vector2 = to_map.call(mm.fb.position)
		var col := _club_color(mm.side)
		if pid in focus:
			minimap.draw_circle(pos, 7.0, C_ACCENT)
		minimap.draw_circle(pos, 4.4, col)
		minimap.draw_arc(pos, 4.4, 0, TAU, 10, Color(0, 0, 0, 0.6), 1.0)
	minimap.draw_circle(to_map.call(ball.position), 3.4, Color.WHITE)
	# kamera görüş alanı göstergesi
	var cx: float = to_map.call(cam_target).x
	minimap.draw_rect(Rect2(cx - w * 0.22, 1, w * 0.44, h - 2), Color(1, 1, 1, 0.12), false, 1.0)

func _show_banner(title: String, sub: String) -> void:
	banner.visible = true
	banner_lbl.text = title
	banner_sub.text = sub
	banner.pivot_offset = banner.size / 2.0
	banner.scale = Vector2(1.0, 0.0)
	banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(banner, "scale", Vector2(1, 1), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(banner_lbl, "scale", Vector2(1.0, 1.0), 0.3).from(Vector2(1.5, 1.5))
	tw.tween_interval(1.6)
	tw.tween_property(banner, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func(): banner.visible = false)
	banner_lbl.pivot_offset = Vector2(banner.size.x / 2.0, 60)

func _set_letterbox(on: bool) -> void:
	for i in 2:
		var lb: ColorRect = letterbox[i]
		var tw := create_tween()
		if i == 0:
			tw.tween_property(lb, "offset_bottom", 90.0 if on else 0.0, 0.3)
		else:
			tw.tween_property(lb, "offset_top", -90.0 if on else 0.0, 0.3)
	replay_badge.visible = on
	bottom_left.visible = not on
	minimap.visible = not on
	chips.visible = not on
	rail.visible = not on

func _show_overlay(title: String, sub: String, btn_text := "", cb := Callable()) -> void:
	for c in overlay.get_children():
		if c is Glass:
			continue
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := _lbl(title, 58, C_ACCENT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := _lbl(sub, 32, C_TEXT, true)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	if btn_text != "":
		var b := _btn(btn_text, cb, 30)
		b.add_theme_stylebox_override("normal", _sb(C_ACCENT, 12, 10))
		b.add_theme_color_override("font_color", C_INK)
		b.custom_minimum_size = Vector2(0, 80)
		v.add_child(b)
	overlay.add_child(v)
	overlay.visible = true
	overlay.pivot_offset = overlay.size / 2.0
	overlay.scale = Vector2(0.85, 0.85)
	overlay.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(overlay, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.2)

func _fade(cb: Callable) -> void:
	if skipping:
		cb.call()
		return
	var tw := create_tween()
	tw.tween_property(fader, "color:a", 1.0, 0.18)
	tw.tween_callback(cb)
	tw.tween_property(fader, "color:a", 0.0, 0.3)

# ================================================================ 3D sahne

func _build_world() -> void:
	world = Node3D.new()
	sv.add_child(world)
	stadium = Stadium.new()
	stadium.fx_enabled = Game.quality() != "low"
	world.add_child(stadium)
	var hc: Dictionary = Game.club(m.h)
	var ac: Dictionary = Game.club(m.a)
	stadium.build(Color(hc.c1), Color(hc.c2), Color(ac.c1), true, Game.quality() == "high")
	# seyirci yoğunluğu: lig seviyesi (BAL ligi neredeyse boş, Süper Lig dolu)
	var tl := Game.tier(hc.get("league", "SL"))
	var fill: float = [0.92, 0.92, 0.62, 0.4, 0.24, 0.12][clampi(tl, 0, 5)]
	if data.get("youth", false):
		fill = 0.06
	stadium.set_fill(fill)
	cam = Camera3D.new()
	cam.fov = 28
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 500
	cam.near = 0.2
	world.add_child(cam)
	ball = MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = BALL_R
	bm.height = BALL_R * 2.0
	ball.mesh = bm
	var bmat := StandardMaterial3D.new()
	var img := Image.create(64, 32, false, Image.FORMAT_RGB8)
	for x in 64:
		for y in 32:
			var pent := (int(x / 8) + int(y / 8)) % 2 == 0 and (x % 8 > 2 and y % 8 > 2)
			img.set_pixel(x, y, Color(0.08, 0.08, 0.1) if pent else Color(0.97, 0.97, 0.97))
	bmat.albedo_texture = ImageTexture.create_from_image(img)
	bmat.roughness = 0.35
	bmat.emission_enabled = true
	bmat.emission = Color(1, 1, 1)
	bmat.emission_energy_multiplier = 0.2
	ball.material_override = bmat
	ball.scale = Vector3.ONE * 1.25   # yayın görüntüsünde okunurluk
	world.add_child(ball)
	ball_shadow = _shadow_quad(0.55)
	world.add_child(ball_shadow)
	var sh := Timeline.slots(Game, m.xi_h)
	var sa := Timeline.slots(Game, m.xi_a)
	var kh := _kits("h", hc, ac)
	var ka := _kits("a", ac, hc)
	var num := 1
	for pid in m.xi_h:
		slot[pid] = sh[pid]
		men[pid] = _make_man(pid, "h", kh, num)
		num += 1
	num = 1
	for pid in m.xi_a:
		slot[pid] = sa[pid]
		men[pid] = _make_man(pid, "a", ka, num)
		num += 1
	_refresh_rings()
	_build_refs()

var refs := {}

func _build_refs() -> void:
	## orta hakem + iki yan hakem
	var kit := FB.kit_mats(Color("#151515"), Color("#151515"), Color("#151515"))
	for k in ["ref", "lin1", "lin2"]:
		var r = FB.new()
		world.add_child(r)
		r.build(kit, hash(k) % 4, 0, hash(k) % 7 + 1, 0, font_head)
		r.number_lbl.visible = false
		refs[k] = r
	refs.lin1.position = Vector3(0, 0, 35.2)
	refs.lin2.position = Vector3(0, 0, -35.2)

func _refs_tick(delta: float) -> void:
	if refs.is_empty():
		return
	var bp := ball.position
	var r = refs.ref
	# top ile çapraz, 12-18 m geride
	var want := Vector3(bp.x - 10.0 * (1.0 if eng.poss == "h" else -1.0), 0, bp.z * 0.55 + 9.0)
	var d: Vector3 = want - r.position
	var spd := 0.0
	if d.length() > 1.5:
		var v := d.normalized() * minf(d.length() * 1.2, 6.5)
		r.position += v * delta
		spd = v.length()
	var to_ball: Vector3 = bp - r.position
	r.rotation.y = lerp_angle(r.rotation.y, atan2(to_ball.x, to_ball.z), minf(1.0, delta * 4.0))
	r.tick(delta, spd)
	# yan hakemler: kendi yarılarında ofsayt çizgisini takip eder
	for k in ["lin1", "lin2"]:
		var ln = refs[k]
		var half := 1.0 if k == "lin1" else -1.0
		var line_x := clampf(eng._offside_line("h" if half > 0 else "a"), 0.0, 52.0) * half if (bp.x * half) > -5.0 else 26.0 * half
		var tx := clampf(line_x, -52.0, 52.0)
		var dx: float = tx - ln.position.x
		var sp2 := clampf(dx * 1.5, -6.0, 6.0)
		ln.position.x += sp2 * delta
		ln.rotation.y = PI if k == "lin1" else 0.0
		ln.tick(delta, absf(sp2))

func _ref_signal(kind: String, e: Dictionary) -> void:
	if refs.is_empty():
		return
	if kind == "offside":
		var ln = refs.lin1 if e.x > 0.0 else refs.lin2
		ln.play("card", 1.5)
	else:
		refs.ref.play("card", 2.0)

func _similar(a: Color, b: Color) -> bool:
	return absf(a.h - b.h) < 0.08 and absf(a.v - b.v) < 0.35

func _kits(side: String, c: Dictionary, opp: Dictionary) -> Dictionary:
	var shirt := Color(c.c1)
	var shorts := Color(c.c2)
	if side == "a" and _similar(Color(c.c1), Color(opp.c1)):
		shirt = Color("#f2f2f2")
		shorts = Color(c.c1)
	var outfield := FB.kit_mats(shirt, shorts, shirt.darkened(0.15))
	var pat: int = [0, 0, 1, 2, 3, 0, 1][hash(String(c.get("name", ""))) % 7]
	if shirt == Color("#f2f2f2"):
		pat = 0
	outfield["pattern"] = pat
	outfield["c2"] = shorts if not _similar(shorts, shirt) else Color("#f2f2f2")
	var gk_col := Color("#2ec4b6") if side == "h" else Color("#c77dff")
	var gk := FB.kit_mats(gk_col, Color("#111111"), gk_col.darkened(0.3))
	return {"out": outfield, "gk": gk}

func _shadow_quad(sz: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(sz, sz)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = gt
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position.y = 0.02
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _make_man(pid: String, side: String, kits: Dictionary, num: int) -> Dictionary:
	var p: Dictionary = Game.player(pid)
	var fb = FB.new()
	world.add_child(fb)
	fb.build(kits.gk if p.pos == "GK" else kits.out, int(p.get("skin", 1)), int(p.get("hair", 0)), int(p.get("seed", 0)), num if p.pos != "GK" else 1, font_head)
	var sm := _shadow_quad(1.3)
	sm.position.y = 0.025
	fb.add_child(sm)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.72
	ring.mesh = tm
	ring.position.y = 0.04
	ring.scale = Vector3(1, 0.12, 1)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = C_ACCENT
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.visible = false
	fb.add_child(ring)
	var tag := Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 64
	tag.outline_size = 18
	tag.fixed_size = true
	tag.pixel_size = 0.00048
	tag.position.y = 2.4
	tag.modulate = C_ACCENT
	tag.text = Game.short_name(p)
	tag.font = font_head
	tag.visible = false
	fb.add_child(tag)
	var attrs: Dictionary = p.attrs
	var d := 1.0 if side == "h" else -1.0
	var base: Vector2 = slot[pid]
	return {
		"fb": fb, "ring": ring, "tag": tag, "side": side, "d": d, "pid": pid,
		"pos": p.pos, "gk": p.pos == "GK", "base": base,
		"fx": clampf((base.x + 35.0) / 46.0, 0.0, 1.0),
		"vel": Vector3.ZERO,
		"vmax": 6.3 + float(attrs.get("pace", 10)) * 0.14,
		"acc": 4.6 + float(attrs.get("agility", 10)) * 0.13,
		"seed": randf() * TAU,
	}

func _refresh_rings() -> void:
	for pid in men:
		var on: bool = pid in focus
		men[pid].ring.visible = on
		men[pid].tag.visible = on or mode == "intro"

# ================================================================ intro

func _start_intro() -> void:
	mode = "intro"
	intro_t = 0.0
	var hc: Dictionary = Game.club(m.h)
	var ac: Dictionary = Game.club(m.a)
	intro_lbl.text = "%s  —  %s\n%s" % [hc.name, ac.name, T.t("mv_tap_skip")]
	var i := 0
	for pid in m.xi_h:
		var fb = men[pid].fb
		fb.position = Vector3(-1.0 - i * 1.0, 0, 3.0)
		fb.rotation.y = 0.0
		i += 1
	i = 0
	for pid in m.xi_a:
		var fb = men[pid].fb
		fb.position = Vector3(1.0 + i * 1.0, 0, 3.0)
		fb.rotation.y = 0.0
		i += 1
	var k := 0
	for pid in men:
		men[pid].tag.fixed_size = false
		men[pid].tag.pixel_size = 0.0042
		men[pid].tag.position.y = 2.15 + (0.26 if k % 2 == 1 else 0.0)
		k += 1
	ball.position = Vector3(0, BALL_R, 0)
	cam.fov = 34
	cam.position = Vector3(-14, 1.9, 9.5)
	cam_target = Vector3(-9, 1.3, 3)
	cam.look_at(cam_target)
	_refresh_rings()
	Sfx.play("whistle", -6.0)

func _end_intro() -> void:
	mode = "live"
	for pid in men:
		men[pid].tag.fixed_size = true
		men[pid].tag.pixel_size = 0.00048
		men[pid].tag.position.y = 2.4
	intro_lbl.text = ""
	_snapshot()
	_place_kickoff()
	_snap_camera()
	_refresh_rings()
	Sfx.play("whistle", -2.0)
	Sfx.crowd_level(0.45)

func _place_kickoff() -> void:
	_sync_men(1.0, 0.0)

# ================================================================ canlı motor oynatımı

func _snapshot() -> void:
	for pid in eng.pl:
		var q = eng.pl[pid]
		prev[pid] = q.pos
	prev_ball = Vector3(eng.ball.x, BALL_R + eng.ball_h, eng.ball.y)
	cur_ball = prev_ball

func _sync_men(alpha: float, gdt: float) -> void:
	for pid in men:
		var q = eng.pl[pid]
		var mm: Dictionary = men[pid]
		var fb = mm.fb
		if q.off:
			fb.visible = false
			continue
		var p0: Vector2 = prev.get(pid, q.pos)
		var p: Vector2 = p0.lerp(q.pos, alpha)
		fb.position = Vector3(p.x, 0, p.y)
		var face: Vector2 = q.face
		if not (fb.is_busy() and fb.action == "dive"):
			var ang := atan2(face.x, face.y)
			fb.rotation.y = lerp_angle(fb.rotation.y, ang, minf(1.0, 0.2 + gdt * 8.0))
		fb.tick(gdt, q.vel.length())
		if mm.ring.visible:
			var pulse := 1.0 + sin(eng.t * 5.0) * 0.08
			mm.ring.scale = Vector3(pulse, 0.12, pulse)

func _consume() -> void:
	## Motorun yeni olaylarını ve animasyonlarını işle
	while ev_seen < eng.events.size():
		var e: Dictionary = eng.events[ev_seen]
		ev_seen += 1
		_on_engine_event(e)
	for an in eng.anims:
		if men.has(an[0]) and not skipping:
			men[an[0]].fb.play(an[1], an[2], an[3])
			if an[1] in ["kick", "shot"] and eng.t - last_kick_t > 0.12:
				last_kick_t = eng.t
				Sfx.play("kick", -14.0)
	eng.anims.clear()

func _on_engine_event(e: Dictionary) -> void:
	match e.ty:
		"goal":
			_on_goal(e)
		"shot":
			if not skipping:
				Sfx.crowd_level(0.75)
		"save":
			if not skipping:
				Sfx.play("ooh", -4.0)
				Sfx.crowd_level(0.45)
		"foul":
			if not skipping:
				Sfx.play("whistle", -10.0)
		"kickoff":
			if ev_seen > 1 and not skipping:
				_fade(func(): _snapshot())
	_on_event(e)

var _frames := 0
var _hb_t := 0.0
var spark_pid := ""
var spark_t := 0.0
var spark_n := 0
var spark_ring: MeshInstance3D
var spark_caught := {}

func _spark_start(pid: String) -> void:
	spark_pid = pid
	spark_t = 0.0
	spark_n += 1
	if spark_ring == null:
		spark_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.8
		tm.outer_radius = 1.0
		spark_ring.mesh = tm
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = Color(1.0, 0.82, 0.2)
		sm.no_depth_test = true
		spark_ring.material_override = sm
		world.add_child(spark_ring)
	spark_ring.visible = true
	_popup(pid, "✦ " + T.t("spark_now"), Color(1.0, 0.85, 0.2))
	Sfx.play("spark", -8.0)

func _spark_tick(delta: float) -> void:
	if spark_pid == "":
		return
	spark_t += delta
	if men.has(spark_pid):
		var pulse := 1.0 + sin(spark_t * 14.0) * 0.15
		spark_ring.position = men[spark_pid].fb.position + Vector3(0, 0.06, 0)
		spark_ring.scale = Vector3(pulse, 0.15, pulse)
	if spark_t > 1.4:
		_popup(spark_pid, T.t("spark_missed"), Color(0.8, 0.8, 0.8))
		spark_pid = ""
		spark_ring.visible = false

func _spark_catch() -> void:
	spark_caught[spark_pid] = int(spark_caught.get(spark_pid, 0)) + 1
	_popup(spark_pid, "✦ " + T.t("spark_caught"), Color(1.0, 0.85, 0.2))
	Sfx.play("catch", -4.0)
	Input.vibrate_handheld(60)
	spark_pid = ""
	spark_ring.visible = false

# ================================================================ Analist Gözü

var eye_left := 3
var eye_state := ""          # "" | choose | wait | verdict
var eye_owner := ""
var eye_prev_owner := ""
var eye_cd := -9999.0
var eye_t := 0.0
var eye_opts: Array = []
var eye_best := -1
var eye_guess := -1
var eye_nodes: Array = []
var eye_panel: PanelContainer
var eye_title: Label
var eye_sub: Label
var eye_bar: ColorRect
var eye_btns: HBoxContainer
var eye_log := {}
var eye_hits := {}

func _eye_tick(delta: float) -> void:
	match eye_state:
		"":
			var oid: String = eng.owner.id if eng.owner != null else ""
			if oid != eye_prev_owner:
				eye_prev_owner = oid
				if oid != "" and oid in focus and _eye_can(eng.owner) and randf() < 0.55:
					_eye_start(eng.owner)
		"choose":
			eye_t += delta
			eye_bar.scale.x = clampf(1.0 - eye_t / 9.0, 0.0, 1.0)
			_eye_pulse()
			if eye_t > 9.0:
				_eye_choose(-1)
		"wait":
			eye_t += delta
			_eye_pulse()
			if not eng.eye_res.is_empty():
				_eye_verdict()
			elif eng.owner == null and eng.flight.is_empty() or (eng.owner != null and eng.owner.id != eye_owner) or eye_t > 5.0 or eng.phase != "play":
				_eye_verdict()
		"verdict":
			eye_t += delta
			if eye_t > 3.6:
				_eye_clear()

func _eye_can(o) -> bool:
	if eye_left <= 0 or skipping or highlights or done or mode != "live":
		return false
	if o.gk or eng.phase != "play" or eng.clock - eye_cd < 780.0 or o.decide_t < 0.2:
		return false
	var good := 0
	for op in eng.eye_preview(o):
		if op.k == "pass" and float(op.v) > -0.5:
			good += 1
	return good >= 3

func _eye_start(o) -> void:
	eye_state = "choose"
	eye_owner = o.id
	eye_t = 0.0
	eye_guess = -1
	eng.eye_pid = o.id
	eng.eye_res = {}
	var all: Array = eng.eye_preview(o)
	all.sort_custom(func(a, b): return float(a.v) > float(b.v))
	eye_opts = []
	var passes := 0
	for op in all:
		if op.k == "pass":
			if op.get("offside", false) or passes >= 5:
				continue
			passes += 1
		eye_opts.append(op)
	eye_best = 0
	var lab := 0
	for i in eye_opts.size():
		var op: Dictionary = eye_opts[i]
		if op.k != "pass":
			_eye_lane(o.pos, op.tp, -1.0, i)
			continue
		lab += 1
		op.lab = lab
		_eye_lane(o.pos, op.tp, op.risk, i)
		if men.has(op.to):
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.fixed_size = true
			l.pixel_size = 0.0006
			l.font_size = 64
			l.outline_size = 18
			l.text = str(lab)
			l.font = font_head
			l.modulate = Color(1, 1, 1)
			world.add_child(l)
			l.position = men[op.to].fb.position + Vector3(0, 2.7, 0)
			l.set_meta("opt", i)
			eye_nodes.append(l)
	_eye_ui()
	Sfx.play("spark", -6.0)
	_push_ticker(T.t("eye_title") + " — " + Game.short_name(Game.player(o.id)), C_ACCENT)

func _eye_lane(from: Vector2, to: Vector2, risk: float, i: int) -> void:
	var a := Vector3(from.x, 0.08, from.y)
	var b := Vector3(to.x, 0.08, to.y)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var ln := a.distance_to(b)
	bm.size = Vector3(0.45, 0.02, ln)
	mi.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.no_depth_test = true
	var col := Color("#4be37a") if risk < 0.3 else (Color("#f2d024") if risk < 0.6 else Color("#ff5a4a"))
	if risk < 0.0:
		col = Color("#6ad7ff")
		bm.size.x = 0.3
	sm.albedo_color = Color(col, 0.85)
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.position = (a + b) * 0.5
	mi.look_at_from_position(mi.position, b, Vector3.UP)
	mi.set_meta("opt", i)
	eye_nodes.append(mi)
	# hedef halkası
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.7
	tm.outer_radius = 0.95
	ring.mesh = tm
	ring.material_override = sm
	world.add_child(ring)
	ring.position = b + Vector3(0, 0.02, 0)
	ring.scale = Vector3(1, 0.1, 1)
	ring.set_meta("opt", i)
	eye_nodes.append(ring)

func _eye_pulse() -> void:
	for n in eye_nodes:
		if not is_instance_valid(n):
			continue
		var i: int = n.get_meta("opt", -1)
		var chosen := i == eye_guess and eye_guess >= 0
		if n is Label3D:
			n.modulate = C_ACCENT if chosen else Color(1, 1, 1, 0.95)
			n.scale = Vector3.ONE * (1.35 if chosen else 1.0)
		elif eye_state == "wait" and eye_guess >= 0 and not chosen:
			(n as MeshInstance3D).transparency = 0.75

func _eye_ui() -> void:
	if eye_panel == null:
		eye_panel = _glass_panel(20.0, Color(0.02, 0.05, 0.04, 0.82))
		eye_panel.anchor_left = 0.5
		eye_panel.anchor_right = 0.5
		eye_panel.anchor_top = 1.0
		eye_panel.anchor_bottom = 1.0
		eye_panel.offset_left = -430
		eye_panel.offset_right = 430
		eye_panel.offset_bottom = -16
		eye_panel.offset_top = -16 - 190
		eye_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		hud.add_child(eye_panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		eye_panel.add_child(v)
		var th := HBoxContainer.new()
		th.alignment = BoxContainer.ALIGNMENT_CENTER
		th.add_theme_constant_override("separation", 10)
		v.add_child(th)
		th.add_child(Icon.new().setup("eye", C_ACCENT, 30))
		eye_title = _lbl("", 30, C_ACCENT, true)
		th.add_child(eye_title)
		eye_sub = _lbl("", 21, C_TEXT)
		eye_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		eye_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(eye_sub)
		eye_btns = HBoxContainer.new()
		eye_btns.alignment = BoxContainer.ALIGNMENT_CENTER
		eye_btns.add_theme_constant_override("separation", 10)
		v.add_child(eye_btns)
		var bar_bg := ColorRect.new()
		bar_bg.color = Color(1, 1, 1, 0.12)
		bar_bg.custom_minimum_size = Vector2(0, 6)
		v.add_child(bar_bg)
		eye_bar = ColorRect.new()
		eye_bar.color = C_ACCENT
		eye_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bar_bg.add_child(eye_bar)
	eye_panel.visible = true
	bottom_left.visible = false
	minimap.visible = false
	eye_title.text = T.t("eye_title")
	eye_sub.text = T.t("eye_ask", [Game.short_name(Game.player(eye_owner))])
	for c in eye_btns.get_children():
		c.queue_free()
	for i in eye_opts.size():
		var op: Dictionary = eye_opts[i]
		if op.k == "pass":
			continue
		var idx := i
		var b := _btn(T.t("eye_" + op.k), func(): _eye_choose(idx), 22)
		b.custom_minimum_size = Vector2(170, 58)
		eye_btns.add_child(b)
	var sk := _btn(T.t("eye_skip"), func(): _eye_choose(-1), 20)
	sk.custom_minimum_size = Vector2(130, 58)
	eye_btns.add_child(sk)
	eye_btns.visible = true
	eye_bar.get_parent().visible = true
	eye_bar.scale.x = 1.0

func _eye_tap(p: Vector2) -> void:
	var scale_f := Vector2(sv.size) / svc.size
	var best := -1
	var bd := 110.0
	for i in eye_opts.size():
		var op: Dictionary = eye_opts[i]
		var dd := 1e9
		if op.k == "pass" and men.has(op.to):
			var wp: Vector3 = men[op.to].fb.position + Vector3(0, 1.0, 0)
			if not cam.is_position_behind(wp):
				dd = (cam.unproject_position(wp) / scale_f).distance_to(p)
		var tpp := Vector3(op.tp.x, 0.1, op.tp.y)
		if not cam.is_position_behind(tpp):
			dd = minf(dd, (cam.unproject_position(tpp) / scale_f).distance_to(p))
		if dd < bd:
			bd = dd
			best = i
	if best >= 0:
		_eye_choose(best)

func _eye_choose(i: int) -> void:
	if eye_state != "choose":
		return
	eye_guess = i
	eye_state = "wait"
	eye_t = 0.0
	eye_btns.visible = false
	eye_bar.get_parent().visible = false
	eye_sub.text = T.t("eye_watch") if i >= 0 else T.t("eye_watch_skip")
	Sfx.play("blip", -8.0)

func _eye_opt_name(op: Dictionary) -> String:
	if op.k == "pass":
		return T.t("eye_pass_to", [Game.short_name(Game.player(op.to))])
	return T.t("eye_" + str(op.k))

func _eye_verdict() -> void:
	var res: Dictionary = eng.eye_res
	eng.eye_pid = ""
	eng.eye_res = {}
	eye_state = "verdict"
	eye_t = 0.0
	eye_cd = eng.clock
	eye_left -= 1
	var best: Dictionary = eye_opts[eye_best]
	var best_v := float(best.v)
	var lines := [T.t("eye_best", [_eye_opt_name(best)])]
	if res.is_empty():
		lines.append(T.t("eye_lost"))
	else:
		var pick := {"k": res.k, "to": res.to}
		var pick_txt := _eye_opt_name(pick)
		var verdict: String
		if res.k == best.k and res.to == best.to:
			verdict = "✓ " + T.t("eye_p_best")
		elif res.good:
			verdict = "✓ " + T.t("eye_p_good")
		else:
			verdict = "✗ " + T.t("eye_p_bad")
		lines.append(T.t("eye_player", [Game.short_name(Game.player(eye_owner)), pick_txt]) + "  " + verdict)
		if not eye_log.has(eye_owner):
			eye_log[eye_owner] = []
		eye_log[eye_owner].append([res.good, res.p10, res.sl])
	var hit := false
	if eye_guess >= 0:
		var g: Dictionary = eye_opts[eye_guess]
		hit = eye_guess == eye_best or float(g.v) >= best_v - LiveEngine.EYE_GOOD
		if hit:
			eye_hits[eye_owner] = int(eye_hits.get(eye_owner, 0)) + 1
			Sfx.play("catch", -4.0)
		lines.append(T.t("eye_you_ok") if hit else T.t("eye_you_bad"))
	eye_title.text = T.t("eye_title_ok") if hit else T.t("eye_title")
	eye_sub.text = "\n".join(lines)
	# en iyi seçeneği vurgula
	eye_guess = eye_best
	for n in eye_nodes:
		if is_instance_valid(n) and n is MeshInstance3D:
			(n as MeshInstance3D).transparency = 0.0 if int(n.get_meta("opt", -1)) == eye_best else 0.8

func _eye_clear() -> void:
	for n in eye_nodes:
		if is_instance_valid(n):
			n.queue_free()
	eye_nodes = []
	if eng != null and eye_state != "":
		eng.eye_pid = ""
		eng.eye_res = {}
	eye_state = ""
	if eye_panel:
		eye_panel.visible = false
		bottom_left.visible = true
		minimap.visible = true

func _process(delta: float) -> void:
	_spark_tick(minf(delta, 0.05))
	if mode == "live" and not skipping and not paused:
		_refs_tick(minf(delta, 0.05) * speed)
	_frames += 1
	if _frames == 1 or _frames == 30 or _frames == 300:
		print("[BC] viewer kare ", _frames, " mod=", mode)
	_hb_t += delta
	if _hb_t > 3.0:
		_hb_t = 0.0
		Watch.bc("mac nabiz kare=%d mod=%s fps=%d dk=%d %s" % [_frames, mode, Engine.get_frames_per_second(), int(eng.clock / 60.0), Watch._mon()])
	delta = minf(delta, 0.05)
	match mode:
		"intro":
			_tick_intro(delta)
		"live":
			if skipping:
				_tick_skip()
			else:
				_tick_live(delta)
		"replay":
			_tick_replay(delta)
		"end":
			_sync_men(1.0, delta * 0.5)
			_update_camera(delta)
	if minimap.visible:
		minimap.queue_redraw()

func _tick_intro(delta: float) -> void:
	intro_t += delta
	var f := clampf(intro_t / 5.0, 0.0, 1.0)
	var ef := f * f * (3.0 - 2.0 * f)
	cam.position = Vector3(lerpf(-13.0, 13.0, ef), 1.9 + ef * 0.8, 9.0)
	cam.look_at(Vector3(cam.position.x * 0.85, 1.25, 3.0))
	for pid in men:
		men[pid].fb.tick(delta, 0.0)
	if intro_t > 5.3:
		_end_intro()

func _current_rate() -> float:
	if eng.intense() or eng.celebrate_t > 0.0:
		return 1.0
	for pid in focus:
		if eng.owner != null and eng.owner.id == pid:
			return 1.0
	return RATE_HL if highlights else RATE_FF

func _tick_live(delta: float) -> void:
	rate = _current_rate()
	if eye_state == "wait":
		rate = 0.3
	var gdt := 0.0 if paused or done or eye_state == "choose" else delta * speed * rate
	if eye_state == "wait":
		gdt = 0.0 if paused else delta * rate
	acc += gdt
	var guard := 0
	while acc >= LiveEngine.DT and not done and guard < 12:
		guard += 1
		acc -= LiveEngine.DT
		_snapshot()
		eng.step(LiveEngine.DT)
		game_t = eng.t
		_consume()
		if goal_pending_replay and eng.t > goal_gt + 3.0:
			goal_pending_replay = false
			_start_replay()
			return
		if eng.finished:
			_finish()
			break
	_eye_tick(delta)
	ff_badge.visible = rate > 1.01 and not done
	var alpha := clampf(acc / LiveEngine.DT, 0.0, 1.0)
	var target_ball := Vector3(eng.ball.x, BALL_R + eng.ball_h, eng.ball.y)
	var bp := prev_ball.lerp(target_ball, alpha)
	if gdt > 0:
		ball_vel = (bp - ball.position) / maxf(gdt, 0.0001)
		var hv := Vector2(ball_vel.x, ball_vel.z).length()
		ball.rotate_x(gdt * hv / BALL_R * 0.4)
	ball.position = bp
	ball_shadow.position = Vector3(bp.x, 0.02, bp.z)
	ball_shadow.scale = Vector3.ONE * clampf(1.0 - bp.y * 0.08, 0.3, 1.0)
	_sync_men(alpha, gdt)
	_update_camera(delta)
	lbl_clock.text = "%02d:%02d" % [int(eng.clock / 60.0), int(eng.clock) % 60]
	_record_frame()
	stadium.set_excite(clampf(eng.celebrate_t / 4.0, 0.0, 1.0))

func _tick_skip() -> void:
	## Sona atla: motoru kare başına parça parça koştur
	var t0 := Time.get_ticks_msec()
	while not eng.finished and Time.get_ticks_msec() - t0 < 24:
		eng.step(0.3)
		_consume()
	skip_prog = clampf(eng.clock / 5600.0, 0.0, 1.0)
	intro_lbl.text = T.t("mv_simulating", [int(skip_prog * 100)])
	lbl_clock.text = "%02d:%02d" % [int(eng.clock / 60.0), int(eng.clock) % 60]
	if eng.finished:
		skipping = false
		intro_lbl.text = ""
		_snapshot()
		_sync_men(1.0, 0.0)
		_update_chips()
		_update_score()
		_finish()

# ================================================================ kamera

func _snap_camera() -> void:
	_update_camera(10.0)

func _update_camera(delta: float) -> void:
	var bp := ball.position
	var tp := bp
	if not eng.flight.is_empty():
		var ft: Vector2 = eng.flight.to
		tp = bp.lerp(Vector3(ft.x, 0.0, ft.y), 0.25)
	poss = eng.poss
	var pos := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := 28.0
	var stiff := 2.4
	var pd := 1.0 if poss == "h" else -1.0
	if (eye_state == "choose" or eye_state == "wait") and men.has(eye_owner):
		# Analist Gözü: hücum yönüne bakan yüksek açı
		var op: Vector3 = men[eye_owner].fb.position
		var lo := Vector2(op.x, op.z)
		var hi := lo
		for o2 in eye_opts:
			var tpv: Vector2 = o2.tp
			if o2.k == "shot":
				tpv = Vector2(op.x, op.z).lerp(tpv, 0.5)
			lo = Vector2(minf(lo.x, tpv.x), minf(lo.y, tpv.y))
			hi = Vector2(maxf(hi.x, tpv.x), maxf(hi.y, tpv.y))
		var c := (lo + hi) * 0.5
		var ext := maxf((hi.x - lo.x) * 0.62, (hi.y - lo.y)) + 8.0
		var hgt := clampf(ext * 0.95, 14.0, 46.0)
		# yayın tarafından, yüksek; içerik ekranın üst kısmında kalsın (alt panel)
		look = Vector3(c.x, 0.0, c.y + ext * 0.2)
		pos = Vector3(c.x, hgt, c.y + hgt * 0.95)
		fov = 50.0
		stiff = 4.0
	elif eng.celebrate_t > 0.0 and scorer != "" and men.has(scorer):
		var sp: Vector3 = men[scorer].fb.position
		pos = sp + Vector3(-4.0 * signf(sp.x), 2.6, 7.0)
		look = sp + Vector3(0, 1.2, 0)
		fov = 40.0
		stiff = 2.0
	else:
		match cam_mode:
			"wide":
				pos = Vector3(clampf(tp.x * 0.5, -26.0, 26.0), 30.0, 39.0)
				look = Vector3(clampf(tp.x * 0.7, -34.0, 34.0), 0.0, clampf(tp.z * 0.8 + 4.0, -14.0, 22.0))
				fov = 50.0
				stiff = 1.6
			"stand":
				pos = Vector3(clampf(tp.x * 0.7, -36.0, 36.0), 6.5, 39.0)
				look = Vector3(tp.x, 0.6, tp.z * 0.85)
				fov = 40.0
			"goal":
				var gx := 52.5 * pd
				pos = Vector3(gx + 8.5 * pd, 7.0, clampf(tp.z * 0.3, -8.0, 8.0))
				look = Vector3(tp.x, 0.4, tp.z)
				fov = 46.0
			"player":
				var who: String = focus[0] if not focus.is_empty() and men.has(focus[0]) else (eng.owner.id if eng.owner != null else "")
				var pp := bp
				if men.has(who):
					pp = men[who].fb.position
				var away := Vector3(pp.x - bp.x, 0, pp.z - bp.z)
				if away.length() < 3.0:
					away = Vector3(-pd, 0, 0.35)
				away = away.normalized()
				pos = pp + away * 9.0 + Vector3(0, 4.2, 0) + Vector3(0, 0, 4.0)
				look = pp.lerp(bp, 0.35) + Vector3(0, 1.0, 0)
				fov = 42.0
				stiff = 2.8
			_:
				# klasik yayın: ana tribün çatısı, top yönünü önceden takip eder
				pos = Vector3(clampf(tp.x * 0.8, -40.0, 40.0), 21.0, 47.0)
				# yakın taç çizgisi de kadrajda kalsın: z ekseninde topu tam takip et
				look = Vector3(clampf(tp.x * 0.93, -46.0, 46.0), 0.0, clampf(tp.z * 0.9, -18.0, 30.0) + 1.0)
				fov = (24.5 if absf(tp.x) < 36.0 else 27.0) + maxf(0.0, tp.z - 12.0) * 0.25
	var k := 1.0 - exp(-delta * stiff)
	cam.position = cam.position.lerp(pos, k)
	cam_target = cam_target.lerp(look, minf(1.0, k * 1.3))
	cam.fov = lerpf(cam.fov, fov, k)
	cam.look_at(cam_target)

# ================================================================ gol

func _on_goal(e: Dictionary) -> void:
	var home: bool = e.side == "h"
	score = [eng.score[0], eng.score[1]]
	_update_score()
	scorer = e.pid
	if skipping:
		return
	var gx := 52.5 * (1.0 if home else -1.0)
	stadium.net_hit(gx, Vector3(0, ball.position.y, ball.position.z))
	stadium.goal_fx(gx, home)
	stadium.set_excite(1.0)
	Sfx.play("net", -6.0)
	Sfx.play("roar", 0.0)
	Sfx.crowd_level(1.0)
	var p: Dictionary = Game.player(e.pid)
	var asst := ""
	if e.tgt != "":
		asst = T.t("mv_assist", [Game.short_name(Game.player(e.tgt))])
	_show_banner(T.t("mv_goal") + "!", "%s %d'%s" % [Game.pname(p), int(e.t / 60.0) + 1, ("  •  " + asst) if asst != "" else ""])
	var tw := create_tween()
	lbl_score.pivot_offset = lbl_score.size / 2.0
	tw.tween_property(lbl_score, "scale", Vector2(1.4, 1.4), 0.15)
	tw.tween_property(lbl_score, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	goal_pending_replay = true
	goal_gt = eng.t

# ================================================================ tekrar

func _record_frame() -> void:
	if skipping:
		return
	if not replay_buf.is_empty() and game_t - float(replay_buf[-1].gt) < 1.0 / 30.0:
		return
	var fr := {"gt": game_t, "b": ball.position, "p": {}}
	for pid in men:
		var fb = men[pid].fb
		fr.p[pid] = [fb.position, fb.rotation.y, fb.rotation.z, fb.pose_state()]
	replay_buf.append(fr)
	while replay_buf.size() > 2 and game_t - float(replay_buf[0].gt) > 12.0:
		replay_buf.pop_front()

func _start_replay() -> void:
	_eye_clear()
	replay_frames = []
	for fr in replay_buf:
		if float(fr.gt) >= goal_gt - 5.5 and float(fr.gt) <= goal_gt + 1.2:
			replay_frames.append(fr)
	if replay_frames.size() < 20:
		return
	mode = "replay"
	replay_t = float(replay_frames[0].gt)
	_set_letterbox(true)
	Sfx.crowd_level(0.6)
	if replay_badge.has_meta("cut"):
		replay_badge.remove_meta("cut")
	var b0: Vector3 = replay_frames[0].b
	cam.position = b0 + Vector3(0, 4.5, 17.0)
	cam_target = b0

var _rp_i := 0
func _tick_replay(delta: float) -> void:
	replay_t += delta * 0.5
	while _rp_i < replay_frames.size() - 2 and float(replay_frames[_rp_i + 1].gt) < replay_t:
		_rp_i += 1
	if replay_t >= float(replay_frames[-1].gt):
		_rp_i = 0
		_after_replay()
		return
	var fa: Dictionary = replay_frames[_rp_i]
	var fbb: Dictionary = replay_frames[_rp_i + 1]
	var span := maxf(0.0001, float(fbb.gt) - float(fa.gt))
	var f := clampf((replay_t - float(fa.gt)) / span, 0.0, 1.0)
	ball.position = (fa.b as Vector3).lerp(fbb.b, f)
	ball_shadow.position = Vector3(ball.position.x, 0.02, ball.position.z)
	for pid in men:
		var a: Array = fa.p[pid]
		var b: Array = fbb.p[pid]
		var fb = men[pid].fb
		fb.position = (a[0] as Vector3).lerp(b[0], f)
		fb.rotation.y = lerp_angle(a[1], b[1], f)
		fb.set_pose_state(a[3])
		fb.rotation.z = a[2]
	var gx := 52.5 * signf(replay_frames[-1].b.x if absf(replay_frames[-1].b.x) > 1 else 1.0)
	var bpos := ball.position
	var pos := Vector3(bpos.x - 6.0 * signf(gx), 4.5, bpos.z + 17.0)
	var fov := 38.0
	if replay_t > goal_gt - 1.4:
		pos = Vector3(gx + 7.0 * signf(gx), 3.0, bpos.z * 0.35 + 3.0)
		fov = 42.0
		if not replay_badge.has_meta("cut"):
			replay_badge.set_meta("cut", true)
			cam.position = pos
	cam.position = cam.position.lerp(pos, minf(1.0, delta * 2.5))
	cam.fov = lerpf(cam.fov, fov, minf(1.0, delta * 2.0))
	cam_target = cam_target.lerp(ball.position + Vector3(0, 0.4, 0), minf(1.0, delta * 5.0))
	cam.look_at(cam_target)

func _after_replay() -> void:
	mode = "live"
	_rp_i = 0
	_set_letterbox(false)
	replay_buf.clear()
	Sfx.crowd_level(0.45)
	_snapshot()

# ================================================================ olay kaydı ve canlı istatistik

func _on_event(e: Dictionary) -> void:
	for pid in focus:
		if e.pid == pid or e.tgt == pid:
			focus_events[pid].append(ev_seen - 1)
	_live_stats(e)
	var mins := int(e.t / 60.0) + 1
	var pa: Dictionary = Game.player(e.pid) if e.pid != "" else {}
	var nm := Game.short_name(pa) if not pa.is_empty() else ""
	match e.ty:
		"goal":
			_push_ticker("⚽ %d' %s! %s" % [mins, T.t("mv_goal"), nm], C_ACCENT)
		"shot":
			_push_ticker("%d' %s — %s" % [mins, T.t("mv_shot_ev") if e.ok else T.t("mv_shot_wide"), nm], C_TEXT if e.ok else C_MUTED)
		"save":
			_push_ticker("%d' %s — %s" % [mins, T.t("mv_save_held") if e.ok else T.t("mv_save_parry"), nm], C_TEXT)
		"corner":
			_push_ticker("%d' %s — %s" % [mins, T.t("mv_corner"), Game.club(m.h if e.side == "h" else m.a).short], C_MUTED)
		"half":
			_push_ticker("— %s —" % T.t("mv_half"), C_ACCENT)
			if not skipping:
				Sfx.play("whistle", -4.0)
				_show_banner(T.t("mv_half").to_upper(), "%s %d - %d %s" % [Game.club(m.h).short, score[0], score[1], Game.club(m.a).short])
		"foul":
			_push_ticker("%d' %s — %s" % [mins, T.t("mv_foul"), nm], C_MUTED)
		"header":
			if e.ok:
				_push_ticker("%d' %s — %s" % [mins, T.t("mv_header"), nm], C_TEXT)
		"offside":
			_push_ticker("%d' 🚩 %s — %s" % [mins, T.t("mv_offside"), nm], C_MUTED)
			if not skipping:
				Sfx.play("whistle", -6.0)
				_ref_signal("offside", e)
		"yellow":
			_push_ticker("%d' 🟨 %s — %s" % [mins, T.t("mv_yellow"), nm], Color("#f2d024"))
			if not skipping:
				Sfx.play("whistle", -4.0)
				_ref_signal("card", e)
				_popup(e.pid, "🟨", Color("#f2d024"))
		"red":
			_push_ticker("%d' 🟥 %s — %s%s" % [mins, T.t("mv_red"), nm, (" (" + T.t("mv_2y") + ")") if e.tgt == "2y" else ""], Color("#ff4d4d"))
			if not skipping:
				Sfx.play("whistle3", -2.0)
				_ref_signal("card", e)
				_show_banner(T.t("mv_red").to_upper(), Game.pname(pa))
		"penalty":
			_push_ticker("%d' ⚠ %s! — %s" % [mins, T.t("mv_penalty"), nm], C_ACCENT)
			if not skipping:
				Sfx.play("whistle3", -2.0)
				_ref_signal("pen", e)
				_show_banner(T.t("mv_penalty").to_upper() + "!", Game.club(m.h if e.side == "h" else m.a).name)
	if skipping:
		return
	if e.pid in focus and e.ty in ["pass", "dribble", "shot", "cross", "header", "press", "sprint", "save", "tackle"]:
		_popup(e.pid, ("✓ " if e.ok else "✗ ") + T.t("ev_" + e.ty), C_GOOD if e.ok else C_BAD)
		# kıvılcım anı: odaktaki oyuncunun nadir parlak hareketi
		if e.ok and spark_pid == "" and spark_n < 4 and e.ty in ["dribble", "shot", "cross", "tackle", "header"] and randf() < 0.22:
			_spark_start(e.pid)
	if e.tgt in focus and e.ty in ["dribble", "header", "sprint"] and not e.ok:
		_popup(e.tgt, "✓ " + T.t("ev_def_" + e.ty), C_GOOD)
	if e.tgt in focus and e.ty == "pass" and not e.ok:
		_popup(e.tgt, "✓ " + T.t("ev_intercept"), C_GOOD)

func _live_stats(e: Dictionary) -> void:
	for pid in [e.pid, e.tgt]:
		if pid == "" or not men.has(pid):
			continue
		if not live.has(pid):
			live[pid] = {"p": 0, "po": 0, "d": 0, "do": 0, "t": 0, "s": 0, "so": 0, "g": 0, "sv": 0}
	if e.pid != "" and live.has(e.pid):
		var st: Dictionary = live[e.pid]
		match e.ty:
			"pass":
				st.p += 1
				if e.ok:
					st.po += 1
			"dribble":
				st.d += 1
				if e.ok:
					st.do += 1
			"shot":
				st.s += 1
				if e.ok:
					st.so += 1
			"tackle", "press":
				if e.ok:
					st.t += 1
			"goal":
				st.g += 1
			"save":
				st.sv += 1
	if e.tgt != "" and live.has(e.tgt) and not e.ok and e.ty in ["dribble", "pass"]:
		live[e.tgt].t += 1
	if not skipping and ((e.pid in focus) or (e.tgt in focus)):
		_update_chips()

func _popup(pid: String, text: String, col: Color) -> void:
	if not men.has(pid) or skipping:
		return
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.text = text
	l.font_size = 56
	l.outline_size = 16
	l.fixed_size = true
	l.pixel_size = 0.0005
	l.modulate = col
	l.font = font_head
	world.add_child(l)
	l.position = men[pid].fb.position + Vector3(0, 3.2, 0)
	var life := 1.3 / maxf(1.0, speed * rate * 0.6)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.4, life)
	tw.tween_property(l, "modulate:a", 0.0, life).set_delay(life * 0.4)
	tw.chain().tween_callback(l.queue_free)

# ================================================================ giriş / bitiş

func _on_view_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if mode == "intro":
		_end_intro()
		return
	if mode == "replay":
		_after_replay()
		return
	if eye_state == "choose":
		_eye_tap(ev.position)
		return
	if spark_pid != "":
		_spark_catch()
		return
	var best := ""
	var bd := 90.0
	var scale_f := Vector2(sv.size) / svc.size
	for pid in men:
		var wp: Vector3 = men[pid].fb.position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp) / scale_f
		var dd := sp.distance_to(ev.position)
		if dd < bd:
			bd = dd
			best = pid
	if best != "":
		_toggle_focus(best)
		var p: Dictionary = Game.player(best)
		_push_ticker(("◉ " if best in focus else "○ ") + Game.pname(p), C_ACCENT)

func _skip_to_end() -> void:
	if done:
		return
	if mode == "intro":
		_end_intro()
	goal_pending_replay = false
	if mode == "replay":
		_set_letterbox(false)
		mode = "live"
	_eye_clear()
	skipping = true
	paused = false

func skip_now() -> void:
	## Testler için: bekletmeden sona koştur
	_skip_to_end()
	while skipping:
		_tick_skip()

func _finish() -> void:
	if done:
		return
	_eye_clear()
	done = true
	mode = "end"
	ff_badge.visible = false
	Sfx.play("whistle3", -2.0)
	Sfx.crowd_level(0.25)
	var hc: Dictionary = Game.club(m.h)
	var ac: Dictionary = Game.club(m.a)
	_show_overlay(T.t("mv_fulltime"), "%s  %d - %d  %s" % [hc.short, score[0], score[1], ac.short], T.t("mv_to_report"), func():
		Sfx.crowd_off()
		focus_events["_sparks"] = spark_caught
		focus_events["_eye"] = eye_log
		focus_events["_eye_hits"] = eye_hits
		finished.emit(focus_events))
