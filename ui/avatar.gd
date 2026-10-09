extends Control
## Prosedürel oyuncu portresi: ten, saç, forma rengi (tohuma göre sabit).

const SKIN := [Color("#f1c9a5"), Color("#e0ac85"), Color("#c68863"), Color("#8d5a3b"), Color("#5a3825")]
const HAIR := [Color("#1b1410"), Color("#2c1d14"), Color("#4a3020"), Color("#0e0b0a"), Color("#8a5a2b"), Color("#c9a45c")]

var skin := 0
var hair := 0
var seed := 0
var shirt := Color("#e8c547")
var shirt2 := Color("#123524")
var ring := Color(1, 1, 1, 0.12)
var unknown := false

func setup(p: Dictionary, club: Dictionary, sz := 64.0) -> Control:
	skin = clampi(int(p.get("skin", 1)), 0, 4)
	hair = clampi(int(p.get("hair", 0)), 0, 5)
	seed = int(p.get("seed", 0))
	if not club.is_empty():
		shirt = Color(club.c1)
		shirt2 = Color(club.c2)
	custom_minimum_size = Vector2(sz, sz)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return self

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := Vector2(size.x / 2.0, size.y / 2.0)
	var r := s / 2.0
	draw_circle(c, r, Color("#5d6a70"))
	draw_circle(c, r * 0.94, Color("#8c9aa1"))
	# forma (omuzlar)
	var sh := PackedVector2Array()
	for i in 21:
		var a := lerpf(PI, TAU, i / 20.0)
		sh.append(c + Vector2(cos(a) * r * 0.78, r * 0.98 + sin(a) * r * 0.42))
	draw_colored_polygon(sh, shirt)
	var collar := PackedVector2Array([c + Vector2(-r * 0.18, r * 0.56), c + Vector2(r * 0.18, r * 0.56), c + Vector2(0, r * 0.74)])
	draw_colored_polygon(collar, shirt2)
	# boyun
	var sk: Color = SKIN[skin]
	draw_rect(Rect2(c + Vector2(-r * 0.13, r * 0.25), Vector2(r * 0.26, r * 0.32)), sk.darkened(0.1))
	# yüz
	var face := PackedVector2Array()
	for i in 32:
		var a := i / 32.0 * TAU
		face.append(c + Vector2(cos(a) * r * 0.36, -r * 0.08 + sin(a) * r * 0.45))
	draw_colored_polygon(face, sk)
	# kulaklar
	draw_circle(c + Vector2(-r * 0.36, -r * 0.06), r * 0.08, sk.darkened(0.08))
	draw_circle(c + Vector2(r * 0.36, -r * 0.06), r * 0.08, sk.darkened(0.08))
	# saç
	var hc: Color = HAIR[hair]
	var style := seed % 4
	var hp := PackedVector2Array()
	match style:
		0:   # kısa
			for i in 17:
				var a := lerpf(PI * 1.05, PI * 1.95, i / 16.0)
				hp.append(c + Vector2(cos(a) * r * 0.4, -r * 0.12 + sin(a) * r * 0.46))
			hp.append(c + Vector2(r * 0.34, -r * 0.18))
			hp.append(c + Vector2(-r * 0.34, -r * 0.18))
		1:   # dolgun
			for i in 17:
				var a := lerpf(PI * 0.95, PI * 2.05, i / 16.0)
				hp.append(c + Vector2(cos(a) * r * 0.44, -r * 0.1 + sin(a) * r * 0.54))
			hp.append(c + Vector2(r * 0.3, -r * 0.22))
			hp.append(c + Vector2(-r * 0.3, -r * 0.22))
		2:   # kazınmış
			for i in 17:
				var a := lerpf(PI * 1.1, PI * 1.9, i / 16.0)
				hp.append(c + Vector2(cos(a) * r * 0.37, -r * 0.1 + sin(a) * r * 0.45))
			hp.append(c + Vector2(r * 0.25, -r * 0.3))
			hp.append(c + Vector2(-r * 0.25, -r * 0.3))
		_:   # uzun/kıvırcık
			for i in 21:
				var a := lerpf(PI * 0.8, PI * 2.2, i / 20.0)
				var rr := r * (0.47 + 0.04 * sin(i * 2.3))
				hp.append(c + Vector2(cos(a) * rr, -r * 0.1 + sin(a) * rr * 1.1))
			hp.append(c + Vector2(r * 0.36, r * 0.05))
			hp.append(c + Vector2(r * 0.3, -r * 0.2))
			hp.append(c + Vector2(-r * 0.3, -r * 0.2))
			hp.append(c + Vector2(-r * 0.36, r * 0.05))
	if hp.size() >= 3:
		draw_colored_polygon(hp, hc)
	# gözler, kaşlar, ağız
	var eye_y := -r * 0.06
	for sx in [-1.0, 1.0]:
		draw_circle(c + Vector2(sx * r * 0.14, eye_y), r * 0.04, Color("#1a1a1a"))
		draw_line(c + Vector2(sx * r * 0.2, eye_y - r * 0.1), c + Vector2(sx * r * 0.08, eye_y - r * 0.11), hc.lightened(0.1), maxf(1.5, r * 0.04), true)
	draw_line(c + Vector2(-r * 0.1, r * 0.2), c + Vector2(r * 0.1, r * 0.2), sk.darkened(0.35), maxf(1.5, r * 0.035), true)
	if seed % 5 == 0:   # sakal
		var bd := PackedVector2Array()
		for i in 13:
			var a := lerpf(0.1, PI - 0.1, i / 12.0)
			bd.append(c + Vector2(cos(a) * r * 0.34, -r * 0.02 + sin(a) * r * 0.4))
		bd.append(c + Vector2(-r * 0.2, r * 0.12))
		bd.append(c + Vector2(r * 0.2, r * 0.12))
		draw_colored_polygon(bd, Color(hc, 0.75))
		draw_line(c + Vector2(-r * 0.1, r * 0.2), c + Vector2(r * 0.1, r * 0.2), sk.darkened(0.35), maxf(1.5, r * 0.035), true)
	draw_arc(c, r * 0.97, 0, TAU, 48, ring, maxf(2.0, r * 0.05), true)
