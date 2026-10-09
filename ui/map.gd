extends Control
## Stilize Türkiye haritası: ev şehri, maç şehirleri, planlanan rotalar.

const OUTLINE := [
	[26.0, 41.7], [26.6, 42.0], [27.9, 42.0], [28.1, 41.6], [29.1, 41.25], [30.5, 41.15], [31.4, 41.3], [32.4, 41.75],
	[33.4, 42.0], [34.9, 42.05], [35.5, 41.65], [36.4, 41.25], [37.5, 41.05], [38.4, 40.95], [39.6, 41.05], [40.6, 41.0],
	[41.5, 41.5], [42.5, 41.45], [43.4, 41.1], [43.7, 40.7], [44.6, 39.75], [44.4, 39.4], [44.2, 38.4], [44.4, 37.2],
	[43.0, 37.3], [42.2, 37.1], [41.2, 37.1], [40.0, 36.85], [38.8, 36.75], [38.2, 36.9], [37.0, 36.6], [36.6, 36.2],
	[36.2, 35.9], [35.9, 36.6], [35.2, 36.6], [34.6, 36.8], [33.9, 36.2], [32.8, 36.0], [32.0, 36.6], [31.0, 36.85],
	[30.5, 36.3], [29.6, 36.2], [28.9, 36.6], [28.0, 36.7], [27.4, 37.0], [27.2, 37.6], [26.4, 38.2], [26.8, 38.7],
	[26.9, 39.3], [26.2, 39.6], [26.6, 40.2], [26.2, 40.6], [26.0, 41.0],
]
const GOLD := Color("#e8c547")

var home := ""
var marks := {}       # şehir -> renk
var routes := []      # şehir listesi (planlı)
var labels := {}      # şehir -> metin
var font: Font
var t := 0.0

func setup(home_city: String, f: Font, h := 300.0) -> Control:
	home = home_city
	font = f
	custom_minimum_size = Vector2(0, h)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _proj(lon: float, lat: float) -> Vector2:
	var pad := 14.0
	var w := size.x - pad * 2
	var h := size.y - pad * 2
	var aspect := 2.25
	var uw := minf(w, h * aspect)
	var uh := uw / aspect
	var ox := pad + (w - uw) / 2.0
	var oy := pad + (h - uh) / 2.0
	var x := (lon - 25.6) / (45.0 - 25.6)
	var y := (42.3 - lat) / (42.3 - 35.6)
	return Vector2(ox + x * uw, oy + y * uh)

func _city(c: String) -> Vector2:
	var p = Data.CITY_POS.get(c, [39.0, 35.0])
	return _proj(p[1], p[0])

func _draw() -> void:
	var pts := PackedVector2Array()
	for p in OUTLINE:
		pts.append(_proj(p[0], p[1]))
	draw_colored_polygon(pts, Color("#1a2e22"))
	var ol := pts.duplicate()
	ol.append(pts[0])
	draw_polyline(ol, Color("#3c5e48"), 2.0, true)
	# rotalar
	var hp := _city(home)
	for c in routes:
		var cp := _city(c)
		var n := int(hp.distance_to(cp) / 10.0) + 1
		for i in n:
			var f0 := (float(i) + fmod(t * 1.5, 1.0)) / n
			var f1 := f0 + 0.45 / n
			if f1 > 1.0:
				continue
			draw_line(hp.lerp(cp, f0), hp.lerp(cp, f1), Color(GOLD, 0.85), 2.5, true)
	# şehirler
	for c in Data.CITY_POS:
		var cp := _city(c)
		var col: Color = marks.get(c, Color(1, 1, 1, 0.18))
		var r := 4.0 if marks.has(c) else 2.5
		if marks.has(c):
			draw_circle(cp, r + 4.0, Color(col, 0.18))
		draw_circle(cp, r, col)
	# ev
	var pulse := 6.0 + sin(t * 3.0) * 2.0
	draw_circle(hp, pulse + 6.0, Color(GOLD, 0.15))
	draw_circle(hp, 6.0, GOLD)
	if font:
		for c in labels:
			var cp := _city(c)
			var txt: String = labels[c]
			draw_string_outline(font, cp + Vector2(8, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.7))
			draw_string(font, cp + Vector2(8, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
