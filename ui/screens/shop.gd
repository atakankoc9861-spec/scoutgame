## Sponsor arası (ödüllü reklam yeri) ve dükkân — main.gd'den taşındı (v0.23 G).
## main.gd'nin durumunu (değişkenler, sinyaller, kit yardımcıları) `m` üzerinden kullanır.
extends RefCounted

const MainT = preload("res://ui/main.gd")
var m: MainT

func _init(main_node) -> void:
	m = main_node

# ================================================================ v0.21: sponsor arası (ödüllü reklam yeri) ve dükkân
## Gerçek reklam SDK'sı (AdMob) bağlanana kadar oyunun kendi sponsor kartı gösterilir.
func _rewarded(kind: String) -> bool:
	var lv: Array = m._modal_layer(0.25, 0.75)
	var v: VBoxContainer = lv[1]
	var was := m._busy
	m._busy = false
	v.add_child(m._lbl(T.t("rw_title"), 26, m.C_INK2, true, m.F_TYPEB))
	# atlastan rastgele bir pano tasarımı
	var atlas: Texture2D = load("res://assets/ads/atlas.png")
	var n := int(atlas.get_height() / 128)
	var at := AtlasTexture.new()
	at.atlas = atlas
	at.region = Rect2(0, 128 * (randi() % maxi(1, n)), 1024, 128)
	var tr := TextureRect.new()
	tr.texture = at
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tr.custom_minimum_size = Vector2(0, 86)
	v.add_child(tr)
	v.add_child(m._typed(T.t("rw_note"), 15, m.C_INK2))
	var b := m._btn(T.t("rw_wait", [5]), func(): m._choice_done.emit(true), "primary", v, "check")
	b.disabled = true
	m._btn(T.t("close"), func(): m._choice_done.emit(false), "ghost", v, "cross")
	for i in range(5, 0, -1):
		b.text = T.t("rw_wait", [i])
		await m.get_tree().create_timer(1.0).timeout
	b.disabled = false
	b.text = T.t("rw_claim")
	var ok: bool = await m._choice_done
	m._busy = was
	m._close_modal(lv[0])
	return ok

func _shop() -> void:
	var lv: Array = m._modal_layer(0.06, 0.94)
	var v: VBoxContainer = lv[1]
	var was := m._busy
	m._busy = false
	var hh := m._h(v, 10)
	hh.add_child(m.Icon.new().setup("star", m.C_BRASS, 34))
	hh.add_child(m._lbl(T.t("shop_title"), 32, m.C_INK, true, m.F_HEAD))
	v.add_child(m._typed(T.t("shop_hint"), 15, m.C_INK2))
	m._section(T.t("shop_themes"), v, "eye")
	var cur: String = Game.settings.get("theme", "classic")
	for id in Game.THEMES:
		var th: Dictionary = Game.THEMES[id]
		var c := m._card(v, "card", 12)
		var row := m._h(c, 10)
		var sw := Panel.new()
		sw.custom_minimum_size = Vector2(90, 54)
		sw.add_theme_stylebox_override("panel", m._leather_tex_style(th.tint, 4, 4))
		row.add_child(sw)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", -2)
		row.add_child(tv)
		tv.add_child(m._head(T.t("theme_" + id), 22))
		var tid: String = id
		if Game.theme_owned(id):
			tv.add_child(m._typed(T.t("shop_owned") if id != cur else T.t("shop_using"), 14, m.C_GREEN))
			if id != cur:
				m._btn(T.t("shop_use"), func():
					Game.settings["theme"] = tid
					Game.save_settings()
					m._choice_done.emit("apply"), "small", row)
		else:
			tv.add_child(m._typed(T.t("shop_progress", [Game.theme_progress(id), int(th.price)]), 14, m.C_INK2))
			m._btn(T.t("shop_watch"), func():
				if await _rewarded("theme"):
					if Game.theme_add_ad(tid):
						m._toast(T.t("shop_unlocked"))
					m._choice_done.emit("reopen"), "brass", row, "play")
	m._section(T.t("shop_support"), v, "trophy")
	var sc := m._card(v, "hl", 14)
	sc.add_child(m._hand(T.t("shop_support_d"), 24, m.C_INK))
	var sb := m._btn(T.t("shop_soon"), func(): pass, "dark", sc)
	sb.disabled = true
	m._btn(T.t("close"), func(): m._choice_done.emit("close"), "primary", v, "check")
	var r = await m._choice_done
	m._busy = was
	m._close_modal(lv[0])
	if r is String and r == "apply":
		m.topbar.add_theme_stylebox_override("panel", m._leather_style(18, 12))
		m.navbar.add_theme_stylebox_override("panel", m._leather_style(6, 6))
		m._show("title", null, false)
	elif r is String and r == "reopen":
		_shop()
