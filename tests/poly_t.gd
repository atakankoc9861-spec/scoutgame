extends Node
const Europe = preload("res://ui/europe.gd")
func _ready() -> void:
	var i := 0
	for poly in Europe.LAND + Europe.WATER:
		var pp := PackedVector2Array()
		for q in poly:
			pp.append(Vector2(q[0], q[1]))
		var t := Geometry2D.triangulate_polygon(pp)
		print("[POLY] ", i, " n=", pp.size(), " tris=", t.size() / 3)
		i += 1
	get_tree().quit()
