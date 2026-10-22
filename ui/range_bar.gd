extends Control
## Özellik aralığı çubuğu: 1-20 ölçeğinde [düşük, yüksek] tahmin.

var lo := 0
var hi := 0
var max_v := 20.0
var known := false
## Çizimde kullanılan (animasyonlu) uçlar; setup() ile lo/hi'ye eşit
var _dlo := 0.0
var _dhi := 0.0
var _mark := false   # daralma bitince ince vurgu çerçevesi

const Motion = preload("res://ui/motion.gd")
const NARROW := 0.7   # daralma süresi (sakin modda 0)

func setup(r: Array, maxv := 20.0) -> void:
	max_v = maxv
	known = not r.is_empty()
	if known:
		lo = int(r[0])
		hi = int(r[1])
	_dlo = float(lo)
	_dhi = float(hi)
	custom_minimum_size = Vector2(150, 22)
	queue_redraw()

## v0.24 (5B) "Bu maçta öğrendiklerin": eski aralıktan yenisine daralır. r0 boşsa (bilinmiyordu)
## tüm ölçekten (sis) başlar. Sakin modda tween kurmaz, son hâli hemen çizer. Tween düğüme bağlı.
func narrow_from(r0: Array, delay := 0.0) -> Tween:
	if not known:
		return null
	var a0 := 1.0 if r0.is_empty() else float(r0[0])
	var b0 := max_v if r0.is_empty() else float(r0[1])
	var d := Motion.dur(NARROW)
	if d <= 0.0 or (is_equal_approx(a0, float(lo)) and is_equal_approx(b0, float(hi))):
		_dlo = float(lo)
		_dhi = float(hi)
		_mark = true
		queue_redraw()
		return null
	_dlo = a0
	_dhi = b0
	_mark = false
	queue_redraw()
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_method(func(t: float):
		_dlo = lerpf(a0, float(lo), t)
		_dhi = lerpf(b0, float(hi), t)
		queue_redraw(), 0.0, 1.0, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_mark = true
		queue_redraw())
	return tw

func _col(v: float) -> Color:
	var f := v / max_v
	if f >= 0.75:
		return Color("#2c7a39")
	if f >= 0.55:
		return Color("#7a8f2a")
	if f >= 0.4:
		return Color("#c27a1a")
	return Color("#b3261e")

func _draw() -> void:
	var w := size.x
	var h := 12.0
	var y := (size.y - h) / 2.0
	draw_rect(Rect2(0, y, w, h), Color(0.15, 0.12, 0.08, 0.08), true)
	for t in [5.0, 10.0, 15.0]:
		var tx: float = (t - 1.0) / 19.0 * w
		draw_line(Vector2(tx, y - 2), Vector2(tx, y + h + 2), Color(0.15, 0.12, 0.08, 0.25), 1.0)
	if not known:
		return
	var x0 := (_dlo - 1.0) / (max_v - 1.0) * w if max_v > 20.0 else (_dlo - 1.0) / 19.0 * w
	var x1 := (_dhi - 1.0) / (max_v - 1.0) * w if max_v > 20.0 else (_dhi - 1.0) / 19.0 * w
	x1 = max(x1, x0 + 6.0)
	var c := _col((_dlo + _dhi) / 2.0)
	draw_rect(Rect2(x0, y, x1 - x0, h), c, true)
	if hi - lo <= 1 or _mark:
		draw_rect(Rect2(x0, y - 3, x1 - x0, h + 6), c, false, 2.0)
