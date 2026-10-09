extends Control
## Altıgen radar grafiği. Bilinen aralığı iki çokgenle (min dolu, max soluk) gösterir.

var data: Array = []     # [[etiket, lo, hi, known], ...]
var font: Font
var anim := 0.0
const GOLD := Color("#b3261e")
const INK := Color("#27241e")

func setup(d: Array, f: Font, sz := 320.0) -> Control:
	data = d
	font = f
	custom_minimum_size = Vector2(sz, sz * 0.92)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anim = 0.0
	var tw := create_tween()
	tw.tween_property(self, "anim", 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return self

func _process(_d: float) -> void:
	if anim < 1.0:
		queue_redraw()

func _pt(i: int, v: float, c: Vector2, r: float) -> Vector2:
	var n := data.size()
	var a := -PI / 2.0 + i * TAU / n
	return c + Vector2(cos(a), sin(a)) * r * clampf(v / 20.0, 0.0, 1.0)

func _draw() -> void:
	if data.is_empty():
		return
	var c := size / 2.0 + Vector2(0, 8)
	var r := minf(size.x, size.y) * 0.34
	var n := data.size()
	for ring in [0.25, 0.5, 0.75, 1.0]:
		var pts := PackedVector2Array()
		for i in n + 1:
			pts.append(_pt(i % n, 20.0 * ring, c, r))
		draw_polyline(pts, Color(INK, 0.12 if ring < 1.0 else 0.35), 1.5, true)
	for i in n:
		draw_line(c, _pt(i, 20.0, c, r), Color(INK, 0.12), 1.0, true)
	var hi := PackedVector2Array()
	var lo := PackedVector2Array()
	for i in n:
		var d: Array = data[i]
		hi.append(_pt(i, float(d[2]) * anim, c, r))
		lo.append(_pt(i, float(d[1]) * anim, c, r))
	draw_colored_polygon(hi, Color(GOLD, 0.12))
	var hl := hi.duplicate()
	hl.append(hi[0])
	draw_polyline(hl, Color(GOLD, 0.45), 1.5, true)
	draw_colored_polygon(lo, Color(GOLD, 0.35))
	var ll := lo.duplicate()
	ll.append(lo[0])
	draw_polyline(ll, GOLD, 2.5, true)
	for i in n:
		draw_circle(lo[i], 4.0, GOLD)
	if font:
		for i in n:
			var d: Array = data[i]
			var p := _pt(i, 27.0, c, r)
			var txt: String = T.t(d[0])
			var val := "?" if not d[3] else "%d" % int(round((float(d[1]) + float(d[2])) / 2.0 * 5.0))
			var fs := 22
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, p - Vector2(tw / 2.0, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#6a6150"))
			var vw := font.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_string(font, p + Vector2(-vw / 2.0, 24), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, INK if d[3] else Color(INK, 0.3))
