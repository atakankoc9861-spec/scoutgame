extends SubViewportContainer
## Başlık ekranının arkasındaki yavaşça dönen 3D stadyum.

const Stadium = preload("res://three/stadium.gd")
var sv: SubViewport
var cam: Camera3D
var ang := 0.0
var men := []

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sv = SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_2X
	sv.scaling_3d_scale = 0.8
	add_child(sv)
	var w := Node3D.new()
	sv.add_child(w)
	var st = Stadium.new()
	w.add_child(st)
	st.build(Color("#e8c547"), Color("#123524"), Color("#b5121b"))
	st.set_excite(0.3)
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 400
	w.add_child(cam)
	for i in 14:
		var col := Color("#e8c547") if i < 7 else Color("#f2f2f2")
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.32
		cm.height = 1.9
		mi.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mi.material_override = mat
		w.add_child(mi)
		mi.position = Vector3(randf_range(-40, 40), 0.95, randf_range(-25, 25))
		men.append({"n": mi, "t": Vector3(randf_range(-40, 40), 0.95, randf_range(-25, 25))})

func _process(delta: float) -> void:
	ang += delta * 0.07
	cam.position = Vector3(sin(ang) * 80.0, 34.0 + sin(ang * 0.7) * 6.0, cos(ang) * 80.0)
	cam.look_at(Vector3(0, 0, 0))
	for m in men:
		var n: MeshInstance3D = m.n
		var to: Vector3 = m.t - n.position
		if to.length() < 1.0:
			m.t = Vector3(randf_range(-45, 45), 0.95, randf_range(-28, 28))
		n.position += to.normalized() * delta * 4.0
