extends Control
## Özellik aralığı çubuğu: 1-20 ölçeğinde [düşük, yüksek] tahmin.

var lo := 0
var hi := 0
var max_v := 20.0
var known := false

func setup(r: Array, maxv := 20.0) -> void:
	max_v = maxv
	known = not r.is_empty()
	if known:
		lo = int(r[0])
		hi = int(r[1])
	custom_minimum_size = Vector2(150, 22)
	queue_redraw()

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
	var x0 := (float(lo) - 1.0) / (max_v - 1.0) * w if max_v > 20.0 else (float(lo) - 1.0) / 19.0 * w
	var x1 := (float(hi) - 1.0) / (max_v - 1.0) * w if max_v > 20.0 else (float(hi) - 1.0) / 19.0 * w
	x1 = max(x1, x0 + 6.0)
	var c := _col((lo + hi) / 2.0)
	draw_rect(Rect2(x0, y, x1 - x0, h), c, true)
	if hi - lo <= 1:
		draw_rect(Rect2(x0, y - 3, x1 - x0, h + 6), c, false, 2.0)
