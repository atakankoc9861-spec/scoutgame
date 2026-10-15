extends Control
class_name Coach
## v0.22 rehber katmanı: ekranı karartır, hedef düğmenin etrafında delik açar (dokunuş geçer),
## yanında Hakkı Usta'nın konuşma balonu durur. Hedef yoksa yalnızca balon görünür.

signal tapped

var target: Control
var hole := Rect2()
var bubble: Control
var info_mode := false      # true: herhangi bir yere dokununca ilerler (hedef sadece gösterilir)
var t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _has_point(p: Vector2) -> bool:
	if info_mode:
		return true
	if hole.size.x > 0 and hole.has_point(p):
		return false
	# balonun düğmeleri tıklanabilsin
	return true

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		tapped.emit()

func _process(delta: float) -> void:
	t += delta
	var nh := Rect2()
	if target and is_instance_valid(target) and target.is_visible_in_tree():
		var r := target.get_global_rect()
		var inv := get_global_transform_with_canvas().affine_inverse()
		nh = Rect2(inv * r.position, r.size).grow(10)
	hole = nh
	_place_bubble()
	queue_redraw()

func _place_bubble() -> void:
	if bubble == null or not is_instance_valid(bubble):
		return
	var W := size.x
	var H := size.y
	bubble.size.x = W - 40
	bubble.reset_size()
	bubble.size.x = W - 40
	var bh := bubble.get_combined_minimum_size().y
	var y := H * 0.5 - bh * 0.5
	if hole.size.x > 0:
		var c := hole.get_center()
		if c.y > H * 0.52:
			y = hole.position.y - bh - 26
		else:
			y = hole.end.y + 26
	y = clampf(y, 70, H - bh - 20)
	bubble.position = Vector2(20, lerpf(bubble.position.y, y, 0.35) if bubble.position.y > 1 else y)

func _draw() -> void:
	var dim := Color(0.02, 0.015, 0.01, 0.62)
	if hole.size.x <= 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(dim, 0.45))
		return
	var r := hole
	draw_rect(Rect2(0, 0, size.x, r.position.y), dim)
	draw_rect(Rect2(0, r.end.y, size.x, size.y - r.end.y), dim)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), dim)
	draw_rect(Rect2(r.end.x, r.position.y, size.x - r.end.x, r.size.y), dim)
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	draw_rect(r, Color("#ffd23f"), false, 4.0)
	draw_rect(r.grow(4 + pulse * 8.0), Color(1.0, 0.82, 0.25, 0.55 * (1.0 - pulse)), false, 3.0)
	# işaret oku
	var c := r.get_center()
	var up := c.y > size.y * 0.52
	var tip := Vector2(c.x, r.position.y - 8) if up else Vector2(c.x, r.end.y + 8)
	var dirv := -1.0 if up else 1.0
	var bob := sin(t * 6.0) * 5.0
	tip.y += dirv * (-bob)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-14, dirv * 20), tip + Vector2(14, dirv * 20)]), Color("#ffd23f"))
