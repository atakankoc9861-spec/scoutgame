## Sahneler (diyaloglu eylemler): antrenman/gözlem, görüşme, telefon, video — main.gd'den taşındı (v0.23 G).
## main.gd'nin durumunu (değişkenler, sinyaller, kit yardımcıları) `m` üzerinden kullanır.
extends RefCounted

const MainT = preload("res://ui/main.gd")
var m: MainT

func _init(main_node) -> void:
	m = main_node

func _scene_open(set_name: String, place: String) -> void:
	## 3D sahne + çizgi roman tarzı arayüz (konuşma balonu, anlatım kutusu, not defteri, seçenekler)
	Watch.bc("sahne " + set_name + " / " + place)
	if m.hub:
		m.hub.set_active(false)
	m.dlg_layer = Control.new()
	m.dlg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.dlg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(m.dlg_layer)
	var blk2 := ColorRect.new()
	blk2.color = Color.BLACK
	blk2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blk2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.dlg_layer.add_child(blk2)
	if set_name == "drill":
		m.stage = Drill2D.new()
		m.dlg_layer.add_child(m.stage)
		m.stage.setup(m._drill_req[0], m._drill_req[1], m._drill_req[2])
	else:
		m.stage = m.Stage3D.new()
		m.dlg_layer.add_child(m.stage)
		m.stage.setup(set_name, set_name == "phone")
	m.scene_ready = false
	m.dlg_root = Control.new()
	m.dlg_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.dlg_root.mouse_filter = Control.MOUSE_FILTER_STOP
	m.dlg_layer.add_child(m.dlg_root)
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
	m.dlg_root.add_child(shade2)
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
		m.dlg_root.add_child(bar)
	# mekân etiketi
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", m._paper_style(m.C_MANILA, 14, 4, 5))
	tag.add_child(m._lbl(place.to_upper(), 20, m.C_INK, false, m.F_HEAD))
	var tagw := m._tilt(tag, -3.0)
	tagw.position = Vector2(20, 66)
	m.dlg_root.add_child(tagw)
	# anlatım kutusu (üst)
	m.caption_box = PanelContainer.new()
	m.caption_box.add_theme_stylebox_override("panel", m._paper_style(m.C_HL.lightened(0.35), 18, 4, 6))
	m.caption_box.anchor_right = 1.0
	m.caption_box.offset_left = 24
	m.caption_box.offset_right = -24
	m.caption_box.offset_top = 128
	m.caption_box.visible = false
	m.caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.caption_text = m._lbl("", 23, m.C_INK, true, m.F_BODY)
	m.caption_box.add_child(m.caption_text)
	m.dlg_root.add_child(m.caption_box)
	# konuşma balonu
	m.bubble = PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color("#fffdf6")
	bs.set_corner_radius_all(26)
	bs.set_border_width_all(3)
	bs.border_color = m.C_INK
	bs.content_margin_left = 22
	bs.content_margin_right = 22
	bs.content_margin_top = 14
	bs.content_margin_bottom = 16
	bs.shadow_color = Color(0, 0, 0, 0.35)
	bs.shadow_size = 8
	bs.shadow_offset = Vector2(0, 4)
	m.bubble.add_theme_stylebox_override("panel", bs)
	m.bubble.custom_minimum_size = Vector2(300, 0)
	m.bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 2)
	m.bubble.add_child(bv)
	m.bubble_name = m._lbl("", 17, m.C_RED, false, m.F_TYPEB)
	bv.add_child(m.bubble_name)
	m.bubble_text = m._lbl("", 25, m.C_INK, true, m.F_BODY)
	m.bubble_text.custom_minimum_size = Vector2(250, 0)
	bv.add_child(m.bubble_text)
	m.bubble.visible = false
	m.dlg_root.add_child(m.bubble)
	m.bubble_tail = Control.new()
	m.bubble_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.bubble_tail.draw.connect(_draw_tail)
	m.bubble_tail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.dlg_root.add_child(m.bubble_tail)
	m.dlg_root.move_child(m.bubble_tail, m.bubble.get_index())
	# not defteri (alt)
	m.note_box = PanelContainer.new()
	m.note_box.add_theme_stylebox_override("panel", m._paper_style(m.C_CARD, 20, 5, 7))
	m.note_box.anchor_top = 1.0
	m.note_box.anchor_bottom = 1.0
	m.note_box.anchor_right = 1.0
	m.note_box.offset_left = 22
	m.note_box.offset_right = -22
	m.note_box.offset_bottom = -64
	m.note_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	m.note_box.visible = false
	m.note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	m.note_box.add_child(nv)
	var nh := m._h(nv, 10)
	nh.add_child(m.Icon.new().setup("report", m.C_RED, 26))
	nh.add_child(m._lbl(T.t("sc_notebook").to_upper(), 17, m.C_RED, false, m.F_TYPEB))
	m.note_list = VBoxContainer.new()
	m.note_list.add_theme_constant_override("separation", -4)
	nv.add_child(m.note_list)
	m.dlg_root.add_child(m.note_box)
	# seçenekler (alt)
	m.choice_box = PanelContainer.new()
	m.choice_box.add_theme_stylebox_override("panel", m._paper_style(m.C_PAPER, 18, 6, 7))
	m.choice_box.anchor_top = 1.0
	m.choice_box.anchor_bottom = 1.0
	m.choice_box.anchor_right = 1.0
	m.choice_box.offset_left = 18
	m.choice_box.offset_right = -18
	m.choice_box.offset_bottom = -54
	m.choice_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	m.choice_box.visible = false
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	m.choice_box.add_child(cv)
	m.choice_prompt = m._hand("", 30, m.C_BLUE)
	cv.add_child(m.choice_prompt)
	m.dlg_choices = VBoxContainer.new()
	m.dlg_choices.add_theme_constant_override("separation", 8)
	cv.add_child(m.dlg_choices)
	m.dlg_root.add_child(m.choice_box)
	m.dlg_hint = m._typed(T.t("tap_continue"), 16, m.C_CREAM)
	m.dlg_hint.anchor_left = 1.0
	m.dlg_hint.anchor_right = 1.0
	m.dlg_hint.anchor_top = 1.0
	m.dlg_hint.anchor_bottom = 1.0
	m.dlg_hint.offset_left = -260
	m.dlg_hint.offset_right = -24
	m.dlg_hint.offset_top = -30
	m.dlg_hint.offset_bottom = -4
	m.dlg_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	m.dlg_hint.visible = false
	m.dlg_root.add_child(m.dlg_hint)
	m.dlg_root.gui_input.connect(_dlg_input)
	m.root.visible = false
	m.shade.visible = false
	m.dlg_root.modulate.a = 0.0
	m.create_tween().tween_property(m.dlg_root, "modulate:a", 1.0, 0.35)
	m.set_process(true)
	m._scene_cover(place)

func _dlg_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	if m.stage and m.stage.drill_on:
		if m.stage.try_catch():
			_spark_pop(true)
		return
	if not m._dlg_waiting:
		return
	if m._typing and m._typing.visible_ratio < 1.0:
		if m._type_tw:
			m._type_tw.kill()
		m._typing.visible_ratio = 1.0
		return
	m._dlg_waiting = false
	m.dlg_next.emit("")

func _scene_tick() -> void:
	## balonu konuşanın başının üstüne yerleştir (main._process çağırır)
	if m.bubble == null or not m.bubble.visible or m.stage == null:
		return
	var vs := m.dlg_root.size
	var hp: Vector2 = m.stage.head_screen(m.bubble_owner, m.bubble_vp)
	var bsz := m.bubble.size
	var want := Vector2(vs.x * 0.5 - bsz.x * 0.5, 150)
	if hp.x >= 0.0:
		want = Vector2(hp.x - bsz.x * 0.5, hp.y - bsz.y - 70)
	want.x = clampf(want.x, 18, vs.x - bsz.x - 18)
	want.y = clampf(want.y, 70, vs.y * 0.62 - bsz.y)
	m.bubble.position = m.bubble.position.lerp(want, 0.35)
	m.bubble_tail.set_meta("from", m.bubble.position + Vector2(bsz.x * 0.5, bsz.y - 4))
	m.bubble_tail.set_meta("to", hp if hp.x >= 0.0 else m.bubble.position + Vector2(bsz.x * 0.5, bsz.y + 40))
	m.bubble_tail.queue_redraw()

func _draw_tail() -> void:
	if m.bubble == null or not m.bubble.visible or not m.bubble_tail.has_meta("from"):
		return
	var a: Vector2 = m.bubble_tail.get_meta("from")
	var b: Vector2 = m.bubble_tail.get_meta("to")
	var d := (b - a)
	var L := minf(d.length() * 0.75, 90.0)
	var tip := a + d.normalized() * L
	var perp := Vector2(-d.y, d.x).normalized() * 16.0
	var pts := PackedVector2Array([a - perp + Vector2(0, -6), tip, a + perp + Vector2(0, -6)])
	m.bubble_tail.draw_colored_polygon(pts, Color("#fffdf6"))
	m.bubble_tail.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), m.C_INK, 3.0, true)

func _type(lbl: Label, text: String, cps := 48.0) -> void:
	m._typing = lbl
	lbl.text = text
	lbl.visible_ratio = 0.0
	if m._type_tw:
		m._type_tw.kill()
	m._type_tw = m.create_tween()
	m._type_tw.tween_property(lbl, "visible_ratio", 1.0, clampf(text.length() / cps, 0.25, 2.6))
	# yazı sesi: birkaç tık
	var n := mini(6, text.length() / 12 + 1)
	for i in n:
		m.get_tree().create_timer(i * 0.09).timeout.connect(func(): Sfx.play("blip", -20.0))

func _wait_tap() -> void:
	m.dlg_hint.visible = true
	m._dlg_waiting = true
	await m.dlg_next
	m.dlg_hint.visible = false

## Karakter konuşur: kamera ona keser, balon başının üstünde
func _line(id: String, name: String, text: String, listener := "", vp := 0, emo := "") -> void:
	await m._scene_gate()
	m.caption_box.visible = false
	m.choice_box.visible = false
	if m.stage:
		if m.stage.views.size() > 1:
			m.stage.focus_speaker(id, "", vp)
		else:
			m.stage.focus_speaker(id, listener, vp)
		m.stage.say(id, text, emo)
	m.bubble_owner = id
	m.bubble_vp = vp
	m.bubble_name.text = name.to_upper()
	m.bubble.visible = true
	m.bubble.size = Vector2.ZERO
	m.bubble.modulate.a = 0.0
	m.bubble.scale = Vector2(0.85, 0.85)
	m.bubble.pivot_offset = Vector2(150, 60)
	var tw := m.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m.bubble, "modulate:a", 1.0, 0.15)
	tw.tween_property(m.bubble, "scale", Vector2.ONE, 0.25)
	_type(m.bubble_text, text)
	await _wait_tap()
	m.bubble.visible = false
	m.bubble_tail.queue_redraw()

## Anlatım kutusu (üstte)
func _caption(text: String) -> void:
	await m._scene_gate()
	m.bubble.visible = false
	m.choice_box.visible = false
	m.caption_box.visible = true
	m.caption_box.modulate.a = 0.0
	m.create_tween().tween_property(m.caption_box, "modulate:a", 1.0, 0.2)
	_type(m.caption_text, text, 60.0)
	await _wait_tap()
	m.caption_box.visible = false

## Not defterine el yazısıyla not
func _note(text: String, col := MainT.C_BLUE) -> void:
	await m._scene_gate()
	m.bubble.visible = false
	m.choice_box.visible = false
	m.note_box.visible = true
	while m.note_list.get_child_count() > 4:
		m.note_list.get_child(0).free()
	var l := m._hand("– " + text, 30, col)
	m.note_list.add_child(l)
	Sfx.play("pen", -10.0)
	_type(l, "– " + text, 34.0)
	await _wait_tap()

func _choose(opts: Array, prompt := "") -> String:
	await m._scene_gate()
	## opts: [[anahtar, etiket], ...]
	m.bubble.visible = false
	m.caption_box.visible = false
	m.note_box.visible = false
	for c in m.dlg_choices.get_children():
		c.queue_free()
	m.choice_prompt.text = prompt
	m.choice_prompt.visible = prompt != ""
	m.choice_box.visible = true
	m._dlg_waiting = false
	for o in opts:
		var key: String = o[0]
		var b := m._btn(o[1], func(): m.dlg_next.emit(key), "small", m.dlg_choices)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.choice_box.modulate.a = 0.0
	m.create_tween().tween_property(m.choice_box, "modulate:a", 1.0, 0.2)
	var was := m._busy
	m._busy = false
	var val = await m.dlg_next
	m._busy = was
	m.choice_box.visible = false
	for c in m.dlg_choices.get_children():
		c.queue_free()
	return str(val)

func _after_close_test(tag: String) -> void:
	for i in 10:
		await m.get_tree().process_frame
	var r: String = await Watch.selftest(tag)
	if r.contains("BOS") and not m._gpu_warned:
		m._gpu_warned = true
		m._toast(T.t("gpu_stuck"))

func _scene_close(back_to_menu := true) -> void:
	_after_close_test.call_deferred("sahne sonrasi")
	Watch.bc("sahne kapandi")
	Sfx.amb_off()
	if m.dlg_layer:
		m.dlg_layer.queue_free()
		m.dlg_layer = null
	m.stage = null
	m.bubble = null
	if not back_to_menu:
		return
	if m.hub:
		m.hub.set_active(true)
	m.root.visible = true
	m._refresh()

# ---------------------------------------------------------------- kıvılcım arayüzü

func _spark_ui_build(vcr := false) -> void:
	m.spark_ui = Control.new()
	m.spark_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.spark_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.dlg_root.add_child(m.spark_ui)
	var lbl := m._lbl("", 54, m.C_HL, false, m.F_HEAD)
	lbl.name = "Pop"
	lbl.add_theme_color_override("font_outline_color", m.C_INK)
	lbl.add_theme_constant_override("outline_size", 12)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.3
	lbl.anchor_bottom = 0.3
	lbl.visible = false
	m.spark_ui.add_child(lbl)
	var cnt := m._lbl("", 22, m.C_CREAM, false, m.F_TYPEB)
	cnt.name = "Count"
	cnt.position = Vector2(24, 128)
	m.spark_ui.add_child(cnt)
	if vcr:
		m.vcr_ui = Control.new()
		m.vcr_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		m.vcr_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.dlg_root.add_child(m.vcr_ui)
		m.dlg_root.move_child(m.vcr_ui, 1)
		var scan := ColorRect.new()
		scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform float t;\nvoid fragment(){ float l = step(0.5, fract(FRAGCOORD.y / 3.0)); float n = fract(sin(dot(FRAGCOORD.xy + t, vec2(12.9898, 78.233))) * 43758.5453); COLOR = vec4(vec3(n * 0.12), l * 0.10 + 0.06); }"
		sm.shader = sh
		scan.material = sm
		m.vcr_ui.add_child(scan)
		var rec := m._lbl("● REC   ▶ 1×", 24, Color("#ff4d4d"), false, m.F_TYPEB)
		rec.position = Vector2(24, 170)
		m.vcr_ui.add_child(rec)
		var tc := m._lbl("00:00:00", 24, m.C_CREAM, false, m.F_TYPEB)
		tc.name = "TC"
		tc.anchor_left = 1.0
		tc.anchor_right = 1.0
		tc.offset_left = -170
		tc.position.y = 170
		m.vcr_ui.add_child(tc)

func _spark_pop(caught: bool) -> void:
	if m.spark_ui == null:
		return
	var lbl: Label = m.spark_ui.get_node("Pop")
	lbl.text = T.t("spark_caught") if caught else T.t("spark_missed")
	lbl.add_theme_color_override("font_color", m.C_HL if caught else Color("#cfcfcf"))
	lbl.visible = true
	lbl.scale = Vector2(0.6, 0.6)
	lbl.pivot_offset = Vector2(360, 30)
	var tw := m.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.25)
	tw.tween_interval(0.6)
	tw.tween_callback(func(): lbl.visible = false)
	if caught:
		Sfx.play("catch", -4.0)
		if Game.settings.get("haptic", true) and OS.has_feature("mobile"): Input.vibrate_handheld(60)
	(m.spark_ui.get_node("Count") as Label).text = "✦ %d" % m.stage.sparks_caught

## Gözlem aşaması: oyuncu çalışır, kıvılcımlar belirir; yakalanan sayısını döndürür
func _observe_phase(dur: float, n: int, vcr := false, focus := "all") -> int:
	await m._scene_gate()
	_spark_ui_build(vcr)
	m.stage.spark_shown.connect(func(_i):
		Sfx.play("spark", -6.0)
		var lbl: Label = m.spark_ui.get_node("Pop")
		lbl.text = T.t("spark_now")
		lbl.add_theme_color_override("font_color", m.C_HL)
		lbl.visible = true)
	m.stage.spark_missed.connect(func(_i): _spark_pop(false))
	m.stage.start_drills("p", dur, n, focus)
	var t0 := Time.get_ticks_msec()
	while m.stage and m.stage.drill_on:
		await m.get_tree().process_frame
		if m.vcr_ui:
			var el := (Time.get_ticks_msec() - t0) / 1000.0
			(m.vcr_ui.get_node("TC") as Label).text = "00:%02d:%02d" % [int(el) / 60, int(el) % 60]
			var sc: ColorRect = m.vcr_ui.get_child(0)
			(sc.material as ShaderMaterial).set_shader_parameter("t", el * 37.0)
	var caught: int = m.stage.sparks_caught
	m.stage.follow = false
	if m.spark_ui:
		m.spark_ui.queue_free()
		m.spark_ui = null
	if m.vcr_ui:
		m.vcr_ui.queue_free()
		m.vcr_ui = null
	return caught

func _who_player(p: Dictionary) -> Dictionary:
	return {"name": Game.pname(p), "role": "%s • %s" % [T.t("pos_" + p.pos), Game.club(p.club).get("name", "")], "face": p, "pid": p.id}

func _who_npc(name: String, role: String, seed_v: int) -> Dictionary:
	return {"name": name, "role": role, "face": {"skin": seed_v % 4, "hair": (seed_v / 3) % 6, "seed": seed_v, "club": ""}}

func _seat(id: String, info: Dictionary, chair_x: float, face: float) -> void:
	## sandalyeye oturt: oturma klibinde pelvis 0.33 m geride
	var dir := 1.0 if face > 0.0 else -1.0
	var a = m.stage.add_actor(id, info, Vector3(chair_x + 0.33 * dir, 0, 0), face, "sit")
	a.set_meta("seated", true)
## Antrenman görünümü: ilk seferde sorulur, açılış ekranından değiştirilebilir
func _drill_style() -> String:
	var st: String = Game.settings.get("drill_style", "")
	if st in ["board", "cine", "3d"]:
		return st
	var lv: Array = m._modal_layer(0.18, 0.82)
	var v: VBoxContainer = lv[1]
	var was := m._busy
	m._busy = false
	v.add_child(m._head(T.t("drill_style_q"), 26, m.C_INK))
	for o in [["board", "drill_board"], ["cine", "drill_cine"], ["3d", "drill_3d"]]:
		var key: String = o[0]
		m._btn(T.t(o[1]), func(): m._choice_done.emit(key), "primary" if key != "3d" else "ghost", v, "check")
	var r = await m._choice_done
	m._busy = was
	m._close_modal(lv[0])
	st = str(r) if str(r) in ["board", "cine", "3d"] else "board"
	Game.settings["drill_style"] = st
	Game.save_settings()
	return st

func _do_action(pid: String, kind: String) -> void:
	if m._busy:
		return
	var p := Game.player(pid)
	var cl := Game.club(p.club)
	if Game.free_days() <= 0:
		m._toast(T.t("no_wp"))
		return
	var me_name: String = Game.s.scout.name
	m._busy = true
	match kind:
		"video":
			if p.youth:
				m._busy = false
				m._toast(T.t("no_footage"))
				return
			var vdata := Game.video_match_data(pid)
			var vs_c := Game.club(vdata.vs)
			_scene_open("video", T.t("sc_place_video"))
			m.stage.wide()
			await _caption(T.t("sc_video_intro2", [Game.pname(p), vs_c.get("name", "?"), int(vdata.ago)]))
			var vf := await _choose([["tec", T.t("foc_tec")], ["men", T.t("foc_men2")], ["phy", T.t("foc_phy2")]], T.t("sc_focus_q"))
			await _caption(T.t("sc_video_hint2"))
			_scene_close(false)
			m._landscape(true)
			var vfe = await m._run_viewer(vdata, [pid])
			m._landscape(false)
			var vres := Game.finish_video(pid, vdata, vfe, vf)
			_scene_open("video", T.t("sc_place_video"))
			m.stage.wide()
			if vres.ok:
				if int(vres.sparks) > 0:
					await _note(T.t("sc_spark_note", [vres.sparks]), m.C_RED)
				for ln in vres.notes.slice(0, 3):
					await _note(T.t(ln[0], ln[1]))
				for ln in vres.lines:
					await _note(T.t(ln[0], ln[1]))
		"train":
			var is_vid := false
			var dstyle: String = await _drill_style()
			if dstyle != "3d":
				m._drill_req = [dstyle, p, cl]
				_scene_open("drill", T.t("sc_place_train", [cl.get("name", "")]))
			else:
				_scene_open("video" if is_vid else "training", T.t("sc_place_video") if is_vid else T.t("sc_place_train", [cl.get("name", "")]))
				m.stage.add_actor("p", {"kind": "player", "p": p, "club": cl, "training": not is_vid}, Vector3(-10, 0, 4), PI / 2.0, "idle")
			if not is_vid and dstyle == "3d":
				m.stage.add_mates(cl, 6)
				var me = m.stage.add_actor("me", m.SCOUT_LOOK, Vector3(-3.0, 0, 9.5), PI, "idle")
				me.overlay = "notebook"
				me.set_meta("talker", false)
			m.stage.wide()
			if is_vid:
				await _caption(T.t("sc_video_intro", [Game.pname(p)]))
			else:
				await _caption(T.t("sc_train_intro", [Game.pname(p), cl.get("city", "")]))
			var f := await _choose([["phy", T.t("foc_phy")], ["men", T.t("foc_men")], ["tec", T.t("foc_tec")]] if not is_vid else [["tec", T.t("foc_tec")], ["men", T.t("foc_men2")], ["phy", T.t("foc_phy2")]], T.t("sc_focus_q"))
			await _caption(T.t("sc_spark_hint"))
			var caught := await _observe_phase(34.0, 4, false, f)
			var res := Game.do_video(pid, f, caught) if is_vid else Game.do_training(pid, f, caught)
			if not is_vid and dstyle == "3d":
				m.stage.shot(0, Vector3(-2.35, 1.62, 8.15), Vector3(-3.0, 1.35, 9.5), 3.0)
			if res.ok:
				if caught > 0:
					await _note(T.t("sc_spark_note", [caught]), m.C_RED)
				for ln in res.lines:
					await _note(T.t(ln[0], ln[1]))
				if res.has("trait"):
					await _note(T.t("sc_prof_%d" % int(res.trait[1])))
				if res.has("trait2"):
					await _note(T.t("sc_trait2", [T.t("q_" + res.trait2[0])]), m.C_RED)
				if res.lines.is_empty():
					await _note(T.t("sc_nothing"))
		"meet":
			var kn: Dictionary = Game.s.scout.knowledge.get(pid, {})
			if kn.get("met", false):
				m._busy = false
				m._toast(T.t("already_met"))
				return
			if not Game.can_talk(pid):
				m._busy = false
				m._toast(T.t("need_lang"))
				return
			var home := int(p.age) <= 18
			_scene_open("home" if home else "lobby", T.t("sc_place_home", [cl.get("city", "")]) if home else T.t("sc_place_meet", [cl.get("city", "")]))
			_seat("me", m.SCOUT_LOOK, -1.0, PI / 2.0)
			var pinfo := {"kind": "player", "p": p, "club": cl, "casual": true, "top": Color(cl.get("c1", "#334455")).darkened(0.25)}
			var par_name := ""
			if home:
				var pa = m.stage.add_actor("p", pinfo, Vector3(1.17, 0, -0.45), -PI / 2.0, "sit")
				pa.set_meta("seated", true)
				var pr = m.stage.add_actor("parent", {"top": Color("#6a5a4a"), "pants": Color("#2e2a26"), "skin": int(p.get("skin", 1)), "hair": 2, "seed": int(p.get("seed", 0)) + 101}, Vector3(1.17, 0, 0.5), -PI / 2.0, "sit")
				pr.set_meta("seated", true)
				par_name = T.t("parent_title", [String(p.get("last", ""))])
			else:
				_seat("p", pinfo, 1.0, -PI / 2.0)
			m.stage.wide()
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
					m.stage.listener_react("me", int(an[1]) >= 1)
				m.stage.wide()
				await _note(T.t("sc_meet_end"))
		_:
			var costs := {"coach": 60, "agent": 0, "journalist": 30}
			if Game.s.scout.money < int(costs[kind]):
				m._busy = false
				m._toast(T.t("not_enough_money"))
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
					var jk := 0
					while Data.NAME_BLOCK.has(nm) and jk < 60:
						jk += 1
						nm = "%s %s" % [Data.FIRST["TR"][hash(pid + str(jk)) % Data.FIRST["TR"].size()], Data.LAST["TR"][hash(pid + "j" + str(jk)) % Data.LAST["TR"].size()]]
					look = {"top": Color("#8a3a2a"), "pants": Color("#3b4a6b"), "shoes": Color("#2a1a12"), "skin": hash(nm) % 4, "hair": hash(nm) % 6, "seed": 8}
				"agent":
					nm = p.agent
					look = {"top": Color("#2b2d33"), "pants": Color("#2b2d33"), "shoes": Color("#0e0e0e"), "skin": hash(nm) % 4, "hair": hash(nm) % 6, "seed": 6}
			if on_phone:
				_scene_open("phone", T.t("sc_place_phone"))
				_seat("me", m.SCOUT_LOOK, 0.0, PI)
				m.stage.actors["me"].position = Vector3(0, 0, -0.28)
				m.stage.actors["me"].overlay = "phone"
				var npc = m.stage.add_actor("npc", look, Vector3(40, 0, 0), 0.0, "idle")
				npc.overlay = "phone"
				m.stage.wide(0)
				m.stage.wide(1)
				Sfx.play("ring", -6.0)
				await m.get_tree().create_timer(1.2).timeout
				await _line("npc", nm, T.t("sc_intro_" + kind, [Game.pname(p)]), "", 1)
			else:
				_scene_open("cafe", T.t("sc_place_cafe", [cl.get("city", "")]))
				_seat("me", m.SCOUT_LOOK, -0.98, PI / 2.0)
				_seat("npc", look, 0.98, -PI / 2.0)
				m.stage.wide()
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
					await _note(T.t("sc_agent_warn"), m.C_RED)
			elif res4.msg == "src_nothing":
				await _line("npc", nm, T.t("src_nothing"), "me", vp2)
			else:
				await _line("npc", nm, T.t("sc_fail_" + kind), "me", vp2)
	m._busy = false
	_scene_close()
