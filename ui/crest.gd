extends Control
## Prosedürel kulüp arması: kalkan, çapraz iki renk, kısa ad.

var c1 := Color.WHITE
var c2 := Color.BLACK
var letters := ""
var font: Font
var style := 0

func setup(club: Dictionary, sz := 48.0, f: Font = null) -> Control:
	c1 = Color(club.c1)
	c2 = Color(club.c2)
	letters = String(club.short).substr(0, 3)
	font = f
	style = int(String(club.id).substr(1)) % 3
	custom_minimum_size = Vector2(sz, sz * 1.15)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return self

func _shield(w: float, h: float, inset := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(inset, inset))
	pts.append(Vector2(w - inset, inset))
	pts.append(Vector2(w - inset, h * 0.55))
	for i in 9:
		var t := i / 8.0
		var x := lerpf(w - inset, w / 2.0, t)
		var y := h * 0.55 + (h - inset - h * 0.55) * sin(t * PI / 2.0)
		pts.append(Vector2(x, y))
	for i in range(1, 9):
		var t := i / 8.0
		var x := lerpf(w / 2.0, inset, t)
		var y := (h - inset) - (h - inset - h * 0.55) * (1.0 - cos(t * PI / 2.0))
		pts.append(Vector2(x, y))
	pts.append(Vector2(inset, h * 0.55))
	return pts

func _draw() -> void:
	var w := size.x
	var h := size.y
	var outer := _shield(w, h)
	draw_colored_polygon(outer, Color(1, 1, 1, 0.9))
	var inner := _shield(w, h, w * 0.07)
	draw_colored_polygon(inner, c1)
	# ikinci renk deseni
	var pts := PackedVector2Array()
	match style:
		0:
			for p in inner:
				if p.x >= w / 2.0:
					pts.append(p)
			pts.insert(0, Vector2(w / 2.0, w * 0.07))
			pts.append(Vector2(w / 2.0, h - w * 0.07))
		1:
			for p in inner:
				if p.y <= p.x * (h / w) * 0.9 + 1:
					pts.append(p)
		_:
			var band := PackedVector2Array([Vector2(w * 0.07, h * 0.3), Vector2(w * 0.93, h * 0.3), Vector2(w * 0.93, h * 0.5), Vector2(w * 0.07, h * 0.5)])
			pts = band
	if pts.size() >= 3:
		draw_colored_polygon(pts, c2)
	var line := outer.duplicate()
	line.append(outer[0])
	draw_polyline(line, Color(0, 0, 0, 0.35), 1.5, true)
	if font and letters != "":
		var fs := int(w * 0.34)
		var tw := font.get_string_size(letters, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2((w - tw) / 2.0, h * 0.62)
		draw_string_outline(font, pos, letters, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.55))
		draw_string(font, pos, letters, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
