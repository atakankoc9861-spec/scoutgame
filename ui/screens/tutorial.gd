## Rehber: eski tutorial kartı ve Hakkı Usta katmanı — main.gd'den taşındı (v0.23 G).
## main.gd'nin durumunu (değişkenler, sinyaller, kit yardımcıları) `m` üzerinden kullanır.
extends RefCounted

const MainT = preload("res://ui/main.gd")
var m: MainT

func _init(main_node) -> void:
	m = main_node

func _tut_card() -> void:
	var st := Game.tut_step()
	var v := m._card(m.outer, "hl", 14)
	var h := m._h(v, 8)
	h.add_child(m.Icon.new().setup("eye", m.C_RED, 28))
	h.add_child(m._lbl(T.t("tut_title"), 18, m.C_RED, false, m.F_HEAD))
	var dots := ""
	for i in Game.TUT_STEPS.size():
		dots += "●" if i <= st else "○"
	var dl := m._lbl(dots, 14, m.C_INK2, false, m.F_BODY)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(dl)
	v.add_child(m._hand(T.t("tut_%d" % clampi(st, 0, 5)), 25, m.C_INK))
	var bh := m._h(v, 8)
	if st >= 5:
		m._expand(m._btn(T.t("tut_ok"), func():
			Game.tut_skip()
			m._refresh(), "primary", bh))
	else:
		m._btn(T.t("tut_skip"), func():
			Game.tut_skip()
			m._refresh(), "ghost", bh).add_theme_font_size_override("font_size", 17)
func _coach_find() -> Dictionary:
	var out := {}
	for n in m.root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		if c.has_meta("tut"):
			var k: String = c.get_meta("tut")
			if not out.has(k):
				out[k] = c
		if c.has_meta("tab"):
			out["nav_" + str(c.get_meta("tab"))] = c
	return out

func _coach_plan() -> Array:
	## [hedef, metin anahtarı, bilgi adımı mı]
	var st := Game.tut_step()
	var f := _coach_find()
	var scr: String = m.stack[-1][0] if not m.stack.is_empty() else ""
	match st:
		0:
			var seq := [["", "co_intro_1"], ["", "co_intro_2"], ["stat_rep", "co_rep"], ["stat_money", "co_money"], ["stat_days", "co_days"], ["stat_fat", "co_fat"]]
			var it: Array = seq[clampi(m._coach_intro, 0, seq.size() - 1)]
			return [f.get(it[0]) if it[0] != "" else null, it[1], true]
		1:
			return [f.get("nav_week"), "co_week", false]
		2:
			if f.has("go_match"):
				return [f.go_match, "co_go_match", false]
			if f.has("ticket"):
				return [f.ticket, "co_ticket", false]
			if f.has("pick_match"):
				return [f.pick_match, "co_pick", false]
			return [f.get("nav_week"), "co_week", false]
		3:
			if f.has("focus_btn"):
				return [f.focus_btn, "co_focus", false]
			return [f.get("nav_week"), "co_back_match", false]
		4:
			if f.has("go_weekend"):
				return [f.go_weekend, "co_weekend", false]
			return [f.get("nav_home"), "co_back_home", false]
		5:
			if scr == "player" and f.has("act_report"):
				return [f.act_report, "co_report", false]
			if scr == "players":
				return [f.get("player_row"), "co_player", false]
			return [f.get("nav_players"), "co_players", false]
		6:
			return [f.get("nav_tasks"), "co_done", true]
	return [null, "", true]

func _coach_tick(delta: float) -> void:
	m._coach_t += delta
	if m._coach_t < 0.2:
		return
	m._coach_t = 0.0
	var show: bool = not Game.s.is_empty() and Game.tut_on() and m.dlg_layer == null and m.viewer == null and m._modal_scroll == null and m.root.visible and not m.stack.is_empty() and not (m.stack[-1][0] in ["title", "newgame", "offers", "result", "season", "obs", "crash"])
	if not show:
		if m.coach:
			m.coach.visible = false
		return
	var plan := _coach_plan()
	if plan[1] == "":
		return
	if m.coach == null:
		m.coach = Coach.new()
		m.add_child(m.coach)
		m.move_child(m.coach, m.toast.get_index())
		m.coach.tapped.connect(_coach_tapped)
	m.coach.visible = true
	var tgt = plan[0]
	m.coach.target = tgt if tgt is Control else null
	m.coach.info_mode = plan[2]
	if m.coach.target and m.scroll.is_ancestor_of(m.coach.target):
		var vr := m.scroll.get_global_rect()
		var tr := m.coach.target.get_global_rect()
		if tr.position.y < vr.position.y + 40 or tr.end.y > vr.end.y - 300:
			m.scroll.scroll_vertical = int(clampf(m.scroll.scroll_vertical + (tr.get_center().y - (vr.position.y + vr.size.y * 0.35)), 0.0, 1e6))
	var key := "%s|%d" % [plan[1], Game.tut_step()]
	if key != m._coach_key:
		m._coach_key = key
		_coach_bubble(plan[1], plan[2])
		if m.coach.target and m.scroll.is_ancestor_of(m.coach.target):
			m.scroll.ensure_control_visible.call_deferred(m.coach.target)

func _coach_bubble(text_key: String, info: bool) -> void:
	if m.coach.bubble and is_instance_valid(m.coach.bubble):
		m.coach.bubble.queue_free()
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#fffaf0")
	sb.border_color = m.C_INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 5)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	pc.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	pc.add_child(h)
	var av := m._avatar(m.COACH_FACE, 76)
	av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(av)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	var nh := HBoxContainer.new()
	nh.add_child(m._lbl(T.t("co_name"), 18, m.C_RED, false, m.F_TYPEB))
	var dots := ""
	for i in Game.TUT_STEPS.size():
		dots += "●" if i <= Game.tut_step() else "○"
	var dl := m._lbl(dots, 13, m.C_INK2, false, m.F_BODY)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nh.add_child(dl)
	v.add_child(nh)
	var tl := m._lbl(T.t(text_key), 23, m.C_INK, true, m.F_BODY)
	tl.custom_minimum_size = Vector2(420, 0)
	v.add_child(tl)
	if text_key == "co_intro_2":
		v.add_child(_coach_loop())
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	v.add_child(bh)
	var sk := m._btn(T.t("co_skip"), func():
		Game.tut_skip()
		if m.coach:
			m.coach.visible = false
		m._refresh(), "ghost", bh)
	sk.add_theme_font_size_override("font_size", 16)
	sk.custom_minimum_size = Vector2(0, 44)
	if info:
		var nx := m._btn(T.t("co_ok") if Game.tut_step() >= 6 else T.t("co_next"), _coach_tapped, "primary", bh, "arrow")
		nx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nx.custom_minimum_size = Vector2(0, 50)
	else:
		var hint := m._hand(T.t("co_tap_hint"), 24, m.C_BLUE)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bh.add_child(hint)
	m.coach.add_child(pc)
	m.coach.bubble = pc
	pc.position = Vector2(20, -1)
	pc.modulate.a = 0.0
	m.create_tween().tween_property(pc, "modulate:a", 1.0, 0.25)
	Sfx.play("page", -14.0)

func _coach_loop() -> Control:
	## işin döngüsü: İZLE → NOT AL → RAPOR → İMZA → İTİBAR
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 96)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var steps := [["eye", "co_l1"], ["report", "co_l2"], ["task", "co_l3"], ["star", "co_l4"]]
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 2)
	c.add_child(hb)
	for i in steps.size():
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		var ic = m.Icon.new().setup(steps[i][0], m.C_RED if i == 0 else m.C_INK, 34)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
		var l := m._lbl(T.t(steps[i][1]), 15, m.C_INK, false, m.F_HEAD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		hb.add_child(col)
		if i < steps.size() - 1:
			var ar := m._lbl("→", 26, m.C_RED, false, m.F_HEAD)
			ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(ar)
	return c

func _coach_tapped() -> void:
	if m.coach == null or not m.coach.info_mode:
		return
	var st := Game.tut_step()
	if st == 0:
		m._coach_intro += 1
		if m._coach_intro >= 6:
			Game.tut_event("intro")
		m._coach_t = 1.0
	elif st >= 6:
		Game.tut_skip()
		m.coach.visible = false
		m._refresh()
