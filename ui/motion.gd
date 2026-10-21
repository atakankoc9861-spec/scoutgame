extends RefCounted
## Gözcü v0.24 hareket yardımcıları (UI planı A: kâğıt kayar, kart dağıtılır, sayı sayar, mühür vurulur).
## Kurallar:
## - Her tween bir düğüme bağlıdır (node.create_tween()): düğüm silinince tween de ölür.
##   Kökten (SceneTree / main) create_tween() YOK — silinmiş düğüme yazma hatası veriyordu.
## - Sakin mod: Game.settings.get("calm", false) açıkken tüm süreler 0. Yardımcı o zaman tween
##   kurmaz, son durumu hemen yazar ve null döner (işlev aynı, hareket yok).
## - Sonsuz döngülü tween ekranda en fazla 2 (CTA ışığı + canlı rozet).
## Kullanım: const Motion := preload("res://ui/motion.gd"); Motion.count_up(lbl, 120.0)

const FAST := 0.14    # düğme basma, küçük geri bildirim
const BASE := 0.28    # öğe girişi
const PAGE := 0.38    # sayfa/sekme geçişi
const COUNT := 0.8    # sayı sayma
const DEAL_STEP := 0.07   # kart dağıtma aralığı
const DEAL_MAX := 8       # en fazla bu kadar kart sırayla gelir, gerisi hemen
const SLAM := 0.22        # mühür iniş süresi
const SHINE_EVERY := 3.2  # CTA ışık süpürmesi periyodu

## Sakin mod açık mı (Game autoload yoksa kapalı sayılır).
static func calm() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var g: Node = tree.root.get_node_or_null("Game") if tree else null
	if g == null:
		return false
	var st = g.get("settings")
	return st is Dictionary and bool(st.get("calm", false))

## Süre: sakin modda 0.
static func dur(d: float) -> float:
	return 0.0 if calm() else d

## Kart dağıtma: kartlar sırayla hafif dönük ve küçük gelip yerine oturur.
## Container çocuklarında konum ezildiği için yalnız scale/rotation/modulate kullanılır.
static func deal_in(cards: Array, step := DEAL_STEP, max_n := DEAL_MAX) -> void:
	var i := 0
	for c in cards:
		var ctl := c as Control
		if ctl == null or not is_instance_valid(ctl):
			continue
		if calm() or i >= max_n:
			ctl.modulate.a = 1.0
			ctl.scale = Vector2.ONE
			ctl.rotation = 0.0
			continue
		ctl.modulate.a = 0.0
		var tw := ctl.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var dl := step * i
		tw.tween_callback(func(): ctl.pivot_offset = ctl.size / 2.0).set_delay(dl)
		tw.tween_property(ctl, "modulate:a", 1.0, BASE).set_delay(dl)
		tw.tween_property(ctl, "scale", Vector2.ONE, BASE).from(Vector2(0.97, 0.97)).set_delay(dl)
		tw.tween_property(ctl, "rotation", 0.0, BASE).from(deg_to_rad(1.4)).set_delay(dl)
		i += 1

## Sayı sayma: etiket from → to. fmt: func(v: float) -> String (varsayılan tamsayı).
static func count_up(lbl: Label, to: float, fmt: Callable = Callable(), d := COUNT, from := 0.0) -> Tween:
	var f: Callable = fmt if fmt.is_valid() else func(v: float) -> String: return str(int(round(v)))
	if calm() or is_equal_approx(from, to):
		lbl.text = f.call(to)
		return null
	lbl.text = f.call(from)
	var tw := lbl.create_tween()
	tw.tween_method(func(v: float): lbl.text = f.call(v), from, to, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw

## Mühür vurma: 2.4 kattan iner, %70'te 0.94 ezilir, oturur. on_hit iniş anında (ses/titreşim).
static func stamp_slam(st: Control, on_hit: Callable = Callable()) -> Tween:
	st.pivot_offset = (st.size if st.size != Vector2.ZERO else st.custom_minimum_size) / 2.0
	if calm():
		st.scale = Vector2.ONE
		st.modulate.a = 1.0
		if on_hit.is_valid():
			on_hit.call()
		return null
	st.scale = Vector2(2.4, 2.4)
	st.modulate.a = 0.0
	var tw := st.create_tween()
	tw.set_parallel(true)
	tw.tween_property(st, "scale", Vector2(0.94, 0.94), SLAM).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(st, "modulate:a", 1.0, SLAM * 0.55)
	tw.set_parallel(false)
	if on_hit.is_valid():
		tw.tween_callback(on_hit)
	tw.tween_property(st, "scale", Vector2.ONE, FAST).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw

## Düğmeye basma: çöker (0.96). Bırakınca yaylanarak döner.
static func press_down(b: Control) -> Tween:
	b.pivot_offset = b.size / 2.0
	if calm():
		return null
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(0.96, 0.96), FAST * 0.5)
	return tw

static func press_up(b: Control) -> Tween:
	if calm():
		b.scale = Vector2.ONE
		return null
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2.ONE, FAST + 0.04).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw

## CTA ışık süpürmesi: düğmenin içinde dar, yarı saydam şerit soldan sağa geçer (shader yok).
## modulate > 1 nabzının yerine. Sakin modda eklenmez. Dönen tween şeride bağlıdır.
static func shine(btn: Control) -> Tween:
	if calm():
		return null
	btn.clip_contents = true
	var bar := ColorRect.new()
	bar.name = "Shine"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.color = Color(1, 1, 1, 0.22)
	bar.rotation = deg_to_rad(14)
	btn.add_child(bar)
	var tw := bar.create_tween().set_loops()
	tw.tween_callback(func():
		bar.size = Vector2(maxf(btn.size.x * 0.12, 24.0), btn.size.y * 1.6)
		bar.position = Vector2(-bar.size.x * 2.0, -btn.size.y * 0.3))
	tw.tween_interval(1.0)
	tw.tween_method(func(t: float): bar.position.x = lerpf(-bar.size.x * 2.0, btn.size.x + bar.size.x, t), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(SHINE_EVERY - 1.9)
	return tw

## Bu yardımcıların kurduğu tüm süreler (test: sakin modda hepsi 0 olmalı).
static func durations() -> Dictionary:
	return {"FAST": dur(FAST), "BASE": dur(BASE), "PAGE": dur(PAGE), "COUNT": dur(COUNT), "DEAL_STEP": dur(DEAL_STEP),
		"SLAM": dur(SLAM), "SHINE_EVERY": dur(SHINE_EVERY)}
