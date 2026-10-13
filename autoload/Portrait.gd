extends Node
## 3D vesikalık: oyuncunun maçtaki modelinden stüdyo fotoğrafı üretir.
## Bir kez çizilir, diske kaydedilir (user://portraits). Büyük polaroidlerde kullanılır.

const FB = preload("res://three/mocap_man.gd")
const SIZE := 192
const DIR := "user://portraits/"
const MAX_MEM := 90
const VER := 2          # görünüm değişirse eski önbellek geçersiz

var sv: SubViewport
var rig: Node3D
var cam: Camera3D
var queue: Array = []          # [{p, cbs}]
var busy := false
var mem := {}                  # anahtar -> ImageTexture
var order: Array = []
var waiting := {}              # anahtar -> [Callable]

func enabled() -> bool:
	return Game.quality() != "low" and not Game.settings.get("safe3d", false)

func key_of(p: Dictionary) -> String:
	var c := Game.club(p.get("club", ""))
	return "%s_%s_%d_%d" % [str(p.get("id", "x")), String(c.get("c1", "#888888")).trim_prefix("#"), int(p.get("age", 20)), VER]

func get_tex(p: Dictionary) -> Texture2D:
	var k := key_of(p)
	if mem.has(k):
		return mem[k]
	var path := DIR + k + ".png"
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img and not img.is_empty():
			return _remember(k, ImageTexture.create_from_image(img))
	return null

func request(p: Dictionary, cb: Callable) -> void:
	if not enabled() or p.is_empty():
		return
	var t := get_tex(p)
	if t:
		cb.call(t)
		return
	var k := key_of(p)
	if waiting.has(k):
		waiting[k].append(cb)
		return
	waiting[k] = [cb]
	queue.append(p.duplicate())
	if not busy:
		_run.call_deferred()

func _remember(k: String, t: Texture2D) -> Texture2D:
	mem[k] = t
	order.append(k)
	while order.size() > MAX_MEM:
		mem.erase(order.pop_front())
	return t

func _setup() -> void:
	if sv:
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	sv = SubViewport.new()
	sv.size = Vector2i(SIZE, SIZE)
	sv.own_world_3d = true
	sv.transparent_bg = false
	sv.msaa_3d = Viewport.MSAA_2X if Game.quality() == "high" else Viewport.MSAA_DISABLED
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sv)
	var w := Node3D.new()
	sv.add_child(w)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.4, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	we.environment = env
	w.add_child(we)
	# stüdyo fonu: dikey degrade kâğıt
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3, 3)
	bg.mesh = q
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded;\nvoid fragment(){ vec2 d = UV - vec2(0.5, 0.42); float v = 1.0 - dot(d, d) * 1.6; ALBEDO = mix(vec3(0.16, 0.18, 0.2), vec3(0.52, 0.56, 0.58), clamp(v, 0.0, 1.0)); }"
	var bm := ShaderMaterial.new()
	bm.shader = sh
	bg.material_override = bm
	bg.position = Vector3(0, 1.55, -0.9)
	w.add_child(bg)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-22, -38, 0)
	key.light_energy = 1.1
	key.light_color = Color(1.0, 0.95, 0.88)
	w.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_energy = 1.1
	rim.light_color = Color(0.75, 0.85, 1.0)
	w.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.9, 1.5, 1.2)
	fill.light_energy = 0.35
	fill.omni_range = 4.0
	w.add_child(fill)
	cam = Camera3D.new()
	cam.fov = 24.0
	w.add_child(cam)
	rig = Node3D.new()
	w.add_child(rig)

func _run() -> void:
	if busy:
		return
	busy = true
	_setup()
	while not queue.is_empty():
		var p: Dictionary = queue.pop_front()
		var k := key_of(p)
		var tex := await _render(p)
		var cbs: Array = waiting.get(k, [])
		waiting.erase(k)
		if tex:
			_remember(k, tex)
			for cb in cbs:
				if cb.is_valid():
					cb.call(tex)
		await get_tree().process_frame
	busy = false

func _render(p: Dictionary) -> Texture2D:
	for c in rig.get_children():
		c.queue_free()
	var club := Game.club(p.get("club", ""))
	var c1 := Color(club.get("c1", "#cccccc"))
	var c2 := Color(club.get("c2", "#333333"))
	var kit := FB.kit_mats(c1, c2, c1.darkened(0.15))
	if p.get("pos", "") == "GK":
		kit = FB.kit_mats(Color("#2ec4b6"), Color("#111111"), Color("#1f8a80"))
	var man = FB.new()
	rig.add_child(man)
	man.apply_look(p)
	man.build(kit, int(p.get("skin", 1)), int(p.get("hair", 0)), int(p.get("seed", 0)), 0, null)
	man.set_base("idle")
	man.tick(0.0, 0.0)
	man.number_lbl.visible = false
	var sk: Skeleton3D = man.skel
	var hb := sk.find_bone("head")
	var head := (sk.global_transform * sk.get_bone_global_pose(hb)).origin
	var face := head + Vector3(0, 0.06, 0)
	cam.position = face + Vector3(0.1, 0.03, 1.12)
	cam.look_at(face + Vector3(0, -0.035, 0))
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	man.queue_free()
	if img == null or img.is_empty():
		Watch.bc("portre alinamadi")
		return null
	img.convert(Image.FORMAT_RGB8)
	img.save_png(ProjectSettings.globalize_path(DIR + key_of(p) + ".png"))
	return ImageTexture.create_from_image(img)
