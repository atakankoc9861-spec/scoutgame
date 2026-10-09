extends Control
## Yıldız gösterimi. Tek değer ya da aralık (lo-hi) çizer. Yarım yıldız destekli.

var lo := 0.0
var hi := 0.0
var known := true
var star_size := 26.0
var GOLD := Color("#c79a1e")
var DIM := Color(0.15, 0.12, 0.08, 0.14)
var RANGE := Color("#c79a1e", 0.4)

func dark_mode() -> void:
	DIM = Color(1, 1, 1, 0.15)
	GOLD = Color("#e8c547")
	RANGE = Color("#e8c547", 0.4)

func setup(a: float, b := -1.0, sz := 26.0) -> void:
	lo = a
	hi = a if b < 0 else b
	star_size = sz
	custom_minimum_size = Vector2(sz * 5 + 16, sz + 4)
	queue_redraw()

func set_unknown(sz := 26.0) -> void:
	known = false
	star_size = sz
	custom_minimum_size = Vector2(sz * 5 + 16, sz + 4)
	queue_redraw()

func _star_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	return pts

func _draw() -> void:
	var r := star_size / 2.0
	for i in 5:
		var c := Vector2(r + i * (star_size + 3), r + 2)
		var pts := _star_points(c, r)
		draw_colored_polygon(pts, DIM)
		if not known:
			continue
		var fill_lo: float = clamp(lo - i, 0.0, 1.0)
		var fill_hi: float = clamp(hi - i, 0.0, 1.0)
		if fill_hi > 0.0:
			_draw_partial(pts, c, r, fill_hi, RANGE)
		if fill_lo > 0.0:
			_draw_partial(pts, c, r, fill_lo, GOLD)

func _draw_partial(pts: PackedVector2Array, c: Vector2, r: float, frac: float, col: Color) -> void:
	if frac >= 0.99:
		draw_colored_polygon(pts, col)
		return
	# yarım yıldız: sol yarıyı kırp
	var clip_x := c.x - r + 2.0 * r * frac
	var half := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		if a.x <= clip_x:
			half.append(a)
		if (a.x <= clip_x) != (b.x <= clip_x):
			var t := (clip_x - a.x) / (b.x - a.x)
			half.append(a.lerp(b, t))
	if half.size() >= 3:
		draw_colored_polygon(half, col)
