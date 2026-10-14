extends Node
## Donma bekçisi: ana iş parçacığı takılırsa (siyah ekran, ses devam) ayrı bir
## thread durumu diske yazar. Bir sonraki açılışta hata kaydına eklenir.

const BC_FILE := "user://watch_bc.txt"
const STALL_FILE := "user://watch_stall.txt"
const PREV_FILE := "user://watch_prev.txt"
const DIAG_FILE := "user://watch_diag.txt"
var diag_lines: PackedStringArray = []

var hb := 0          # son _process
var pre := 0         # son frame_pre_draw
var post := 0        # son frame_post_draw
var paused := false
var ring: PackedStringArray = []
var mx := Mutex.new()
var th: Thread
var alive := true
var reported := false
var prev_report := ""
var bg_exit := false   # önceki oturum arka plandayken kapandı (Android kapattı)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# önceki oturumun izleri
	var parts := []
	if FileAccess.file_exists(STALL_FILE):
		parts.append("=== ONCEKI OTURUM DONMA ===\n" + FileAccess.get_file_as_string(STALL_FILE))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STALL_FILE))
	if FileAccess.file_exists(BC_FILE):
		parts.append("=== ONCEKI OTURUM SON ADIMLAR ===\n" + FileAccess.get_file_as_string(BC_FILE))
	if FileAccess.file_exists(BC_FILE) and not FileAccess.file_exists(STALL_FILE):
		var last := FileAccess.get_file_as_string(BC_FILE).strip_edges().get_slice("\n", FileAccess.get_file_as_string(BC_FILE).strip_edges().count("\n"))
		if last.find("arka plana alindi") >= 0:
			bg_exit = true
			parts.append("=== NOT: uygulama arka plandayken kapandi (Android kapatti ya da donuste takildi) ===")
	if FileAccess.file_exists(DIAG_FILE):
		parts.append("=== ONCEKI 3B TESHIS ===\n" + FileAccess.get_file_as_string(DIAG_FILE))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIAG_FILE))
	var why := _exit_reason()
	if why != "":
		parts.append("=== ANDROID CIKIS NEDENI ===\n" + why)
	prev_report = "\n".join(parts)
	if prev_report != "":
		var f := FileAccess.open(PREV_FILE, FileAccess.WRITE)
		if f:
			f.store_string(prev_report)
			f.close()
	elif FileAccess.file_exists(PREV_FILE):
		prev_report = FileAccess.get_file_as_string(PREV_FILE)
	hb = Time.get_ticks_msec()
	pre = hb
	post = hb
	RenderingServer.frame_pre_draw.connect(func(): pre = Time.get_ticks_msec())
	RenderingServer.frame_post_draw.connect(func(): post = Time.get_ticks_msec())
	bc("oturum basladi")
	get_tree().create_timer(1.5).timeout.connect(func(): selftest("acilis"))
	th = Thread.new()
	th.start(_loop)

func _process(_d: float) -> void:
	hb = Time.get_ticks_msec()
	if reported:
		reported = false
		bc("donma bitti (ana thread geri geldi)")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not paused:
			bc("arka plana alindi (%s)" % ("pause" if what == NOTIFICATION_APPLICATION_PAUSED else "odak") + " " + _mon())
		paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if paused:
			bc("on plana geldi")
		paused = false
		hb = Time.get_ticks_msec()
		pre = hb
		post = hb
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		alive = false

func _exit_tree() -> void:
	alive = false
	if th and th.is_started():
		th.wait_to_finish()

func _mon() -> String:
	return "vmem=%dMB tex=%dMB nodes=%d obj=%d" % [int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6), int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT))]

const OPAQUE_SHADER := "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(texture(TEXTURE, UV).rgb, 1.0); }"
static var _opq_mat: ShaderMaterial
static func opaque_mat() -> ShaderMaterial:
	if _opq_mat == null:
		_opq_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = OPAQUE_SHADER
		_opq_mat.shader = sh
	return _opq_mat

## 3D görüntü kontrolü: birkaç kare sonra SubViewport içeriğini örnekler.
## Siyah/boşsa kayda yazar ve fallback'i (MSAA kapat, ölçek 1, glow kapat) çağırır.
var _vp_checks := 0
func check_vp(sv: SubViewport, tag: String, fallback := Callable(), tries := 2) -> void:
	# GPU'dan geri okuma pahalı: oturum başına sınırlı sayıda kontrol
	_vp_checks += 1
	if _vp_checks > 10 and not tag.ends_with("+fb"):
		return
	for i in 25:
		await get_tree().process_frame
		if not is_instance_valid(sv):
			return
	var img := sv.get_texture().get_image()
	if img == null or img.is_empty():
		bc("3D %s: goruntu alinamadi" % tag)
		return
	var w := img.get_width()
	var h := img.get_height()
	var lum := 0.0
	var alpha := 0.0
	var n := 0
	for yi in range(1, 8):
		for xi in range(1, 8):
			var c := img.get_pixel(w * xi / 8, h * yi / 8)
			lum += c.get_luminance()
			alpha += c.a
			n += 1
	lum /= n
	alpha /= n
	var bad := lum < 0.012 or alpha < 0.1
	var cam := sv.get_camera_3d()
	bc("3D %s: %s lum=%.3f a=%.2f boyut=%dx%d msaa=%d olcek=%.2f upd=%d cam=%s vis=%s" % [tag, "BOS/SIYAH" if bad else "ok", lum, alpha, w, h, sv.msaa_3d, sv.scaling_3d_scale, sv.render_target_update_mode, "var" if cam != null else "YOK", str(sv.get_parent() is CanvasItem and (sv.get_parent() as CanvasItem).is_visible_in_tree())])
	if bad and tries > 0:
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		sv.msaa_3d = Viewport.MSAA_DISABLED
		sv.scaling_3d_scale = 1.0
		if fallback.is_valid():
			fallback.call()
		Game.settings["safe3d"] = true
		check_vp(sv, tag + "+fb", Callable(), tries - 1)
	elif bad and tries == 0:
		diagnose(sv, tag, true)
	elif lum < 0.05 and not _diag_done.has(tag):
		diagnose(sv, tag + "(karanlik)", false)

## Ekranda gerçekten ne görünüyor: ana pencerenin görüntüsünü örnekle
var _scr_checks := 0
func check_screen(tag: String) -> void:
	_scr_checks += 1
	if _scr_checks > 12:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		bc("ekran %s: alinamadi" % tag)
		return
	var w := img.get_width()
	var h := img.get_height()
	var lum := 0.0
	var n := 0
	for yi in range(2, 7):
		for xi in range(2, 7):
			lum += img.get_pixel(w * xi / 8, h * yi / 8).get_luminance()
			n += 1
	bc("ekran %s: lum=%.3f %dx%d" % [tag, lum / n, w, h])

## Kısa iz bırak (ekran değişimi, sahne, maç vb.)
func bc(msg: String) -> void:
	var line := "%d %s" % [Time.get_ticks_msec() / 1000, msg]
	mx.lock()
	ring.append(line)
	if ring.size() > 40:
		ring = ring.slice(ring.size() - 40)
	var txt := "\n".join(ring)
	mx.unlock()
	var f := FileAccess.open(BC_FILE, FileAccess.WRITE)
	if f:
		f.store_string(txt)
		f.close()

func _loop() -> void:
	while alive:
		OS.delay_msec(500)
		if paused or reported:
			continue
		var now := Time.get_ticks_msec()
		# çizim durdu ama oyun mantığı çalışıyor (ekran donuk, dokunuşlar işleniyor)
		if now - hb < 1000 and now - post > 2500 and not reported:
			reported = true
			mx.lock()
			var t2 := "zaman=%ds tur=CIZIM DURDU (process calisiyor)\npost_draw %dms once fps=%d %s\n--- son adimlar ---\n%s" % [now / 1000, now - post, Engine.get_frames_per_second(), _mon(), "\n".join(ring)]
			mx.unlock()
			var f2 := FileAccess.open(STALL_FILE, FileAccess.WRITE)
			if f2:
				f2.store_string(t2)
				f2.close()
			continue
		if now - hb > 2500:
			reported = true
			var kind := "SCRIPT/MANTIK (process durdu, cizim de durdu)"
			if pre > post + 50:
				kind = "GPU/CIZIM (cizim basladi ama bitmedi)"
			elif post >= hb and pre >= hb:
				kind = "PROCESS (cizim devam etti ama process durdu)"
			mx.lock()
			var txt := "zaman=%ds tur=%s\nprocess %dms once, pre_draw %dms once, post_draw %dms once %s\n--- son adimlar ---\n%s" % [now / 1000, kind, now - hb, now - pre, now - post, _mon(), "\n".join(ring)]
			mx.unlock()
			var f := FileAccess.open(STALL_FILE, FileAccess.WRITE)
			if f:
				f.store_string(txt)
				f.close()


## Android 11+: önceki oturum neden bitti? (bellek, çökme, kullanıcı kapattı...)
const EXIT_REASONS := {0: "BILINMIYOR", 1: "UYGULAMA KENDI CIKTI", 2: "SINYAL (sistem oldurdu)", 3: "DUSUK BELLEK (Android kapatti)", 4: "COKME (Java)", 5: "COKME (yerel/native)",
	6: "ANR (yanit vermiyor)", 7: "BASLATMA HATASI", 8: "IZIN DEGISTI", 9: "ASIRI KAYNAK KULLANIMI", 10: "KULLANICI KAPATTI (son uygulamalardan)", 11: "KULLANICI DURDURDU",
	12: "BAGIMLILIK OLDU", 13: "DIGER", 14: "DONDURUCU", 15: "PAKET DURUMU", 16: "GUNCELLEME"}

func _exit_reason() -> String:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return ""
	var rt = Engine.get_singleton("AndroidRuntime")
	if rt == null:
		return ""
	var act = rt.getActivity()
	if act == null:
		return ""
	var am = act.getSystemService("activity")
	if am == null:
		return ""
	var lst = am.getHistoricalProcessExitReasons(act.getPackageName(), 0, 1)
	if lst == null or int(lst.size()) == 0:
		return ""
	var info = lst.get(0)
	if info == null:
		return ""
	var code := int(info.getReason())
	var desc = info.getDescription()
	var pss := int(info.getPss()) / 1024
	var rss := int(info.getRss()) / 1024
	var imp := int(info.getImportance())
	return "neden=%d %s | onem=%d | bellek pss=%dMB rss=%dMB | %s" % [code, EXIT_REASONS.get(code, "?"), imp, pss, rss, str(desc) if desc != null else ""]


# ================================================================ 3B teşhis
## Görüntü boş/karanlıksa: materyalleri grup grup gizleyip hangisinin bozduğunu bulur,
## suçluyu gizli bırakır (oyun oynanır kalsın) ve sonucu kayda yazar.
var _diag_done := {}
var _diag_running := false

func _sample(sv: SubViewport) -> Vector2:
	for i in 3:
		await RenderingServer.frame_post_draw
	if not is_instance_valid(sv):
		return Vector2(-1, -1)
	var img := sv.get_texture().get_image()
	if img == null or img.is_empty():
		return Vector2(-1, -1)
	var w := img.get_width()
	var h := img.get_height()
	var lum := 0.0
	var a := 0.0
	for yi in range(1, 6):
		for xi in range(1, 6):
			var c := img.get_pixel(w * xi / 6, h * yi / 6)
			lum += c.get_luminance()
			a += c.a
	return Vector2(lum / 25.0, a / 25.0)

static func mat_label(g: GeometryInstance3D) -> String:
	var m: Material = g.material_override
	if m == null and g is MeshInstance3D and (g as MeshInstance3D).mesh and (g as MeshInstance3D).mesh.get_surface_count() > 0:
		m = (g as MeshInstance3D).get_active_material(0)
	if m == null:
		return "yok:" + g.get_class()
	if m is ShaderMaterial:
		var sh: Shader = (m as ShaderMaterial).shader
		if sh == null:
			return "sh:bos"
		var code := sh.code
		var names := []
		var rx := RegEx.new()
		rx.compile("uniform\\s+\\w+\\s+(\\w+)")
		for r in rx.search_all(code):
			names.append(r.get_string(1))
			if names.size() >= 3:
				break
		return "sh%d[%s]" % [absi(code.hash()) % 100000, ",".join(names)]
	if m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		return "std" + ("+tex" if sm.albedo_texture else "") + ("+alpha" if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else "")
	return m.get_class()

func diagnose(sv: SubViewport, tag: String, keep := true) -> void:
	if _diag_running or _diag_done.has(tag) or not is_instance_valid(sv):
		return
	_diag_running = true
	_diag_done[tag] = true
	var base := await _sample(sv)
	dbc("TESHIS %s: baslangic lum=%.3f a=%.2f" % [tag, base.x, base.y])
	var groups := {}
	for n in sv.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.visible:
			continue
		var k := mat_label(g)
		if not groups.has(k):
			groups[k] = []
		groups[k].append(g)
	dbc("TESHIS %s: %d materyal grubu" % [tag, groups.size()])
	# 1) hepsi gizli: arka plan/ortam tek başına çiziliyor mu
	for k in groups:
		for g in groups[k]:
			if is_instance_valid(g):
				g.visible = false
	var empty := await _sample(sv)
	dbc("TESHIS %s: tum geometri gizli lum=%.3f a=%.2f" % [tag, empty.x, empty.y])
	for k in groups:
		for g in groups[k]:
			if is_instance_valid(g):
				g.visible = true
	var good := func(v: Vector2) -> bool: return v.y > 0.5 and v.x > maxf(0.03, base.x + 0.02)
	# 2) her grubu tek tek gizle
	var culprits := []
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a].size() > groups[b].size())
	for k in keys.slice(0, 30):
		for g in groups[k]:
			if is_instance_valid(g):
				g.visible = false
		var v := await _sample(sv)
		var fix: bool = good.call(v)
		dbc("TESHIS %s: gizli %s (n=%d, ilk=%s) lum=%.3f a=%.2f%s" % [tag, k, groups[k].size(), str(groups[k][0].name) if is_instance_valid(groups[k][0]) else "?", v.x, v.y, "  <== SUCLU" if fix else ""])
		if fix:
			culprits.append(k)
			if keep:
				continue   # gizli kalsın
		for g in groups[k]:
			if is_instance_valid(g):
				g.visible = true
	# 3) ortam ayarları
	if culprits.is_empty() and keep:
		var envs := sv.find_children("*", "WorldEnvironment", true, false)
		var cam := sv.get_camera_3d()
		if cam and cam.environment:
			envs.append(cam)
		for e in envs:
			var env: Environment = e.environment
			if env == null:
				continue
			for step in ["fog", "glow", "tonemap", "adj", "bg"]:
				match step:
					"fog": env.fog_enabled = false
					"glow": env.glow_enabled = false
					"tonemap": env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
					"adj": env.adjustment_enabled = false
					"bg":
						env.background_mode = Environment.BG_COLOR
						env.background_color = Color(0.2, 0.25, 0.3)
				var v := await _sample(sv)
				dbc("TESHIS %s: ortam %s kapali lum=%.3f a=%.2f" % [tag, step, v.x, v.y])
				if good.call(v):
					dbc("TESHIS %s: SUCLU ortam ayari %s" % [tag, step])
					break
		var lights := sv.find_children("*", "Light3D", true, false)
		for l in lights:
			(l as Light3D).shadow_enabled = false
		var v2 := await _sample(sv)
		dbc("TESHIS %s: golgeler kapali lum=%.3f a=%.2f" % [tag, v2.x, v2.y])
	dbc("TESHIS %s bitti: suclu=%s" % [tag, str(culprits)])
	_diag_running = false

func dbc(msg: String) -> void:
	bc(msg)
	diag_lines.append(msg)
	var f := FileAccess.open(DIAG_FILE, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(diag_lines))
		f.close()

# ================================================================ taze görünüm testi
## Yeni bir SubViewport açıp gerçekten çizilip çizilmediğine bakar (2B ve 3B, küçük ve büyük).
var _st_count := 0
func selftest(tag: String) -> String:
	_st_count += 1
	if _st_count > 8:
		return ""
	var holder := Node.new()
	add_child(holder)
	var res := []
	for variant in ["2d", "3d", "3d_buyuk"]:
		var sv := SubViewport.new()
		sv.size = Vector2i(1459, 720) if variant == "3d_buyuk" else Vector2i(128, 128)
		sv.own_world_3d = true
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		holder.add_child(sv)
		if variant == "2d":
			var cr := ColorRect.new()
			cr.color = Color(0.9, 0.2, 0.2)
			cr.size = Vector2(128, 128)
			sv.add_child(cr)
		else:
			var we := WorldEnvironment.new()
			var env := Environment.new()
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.2, 0.6, 0.3)
			we.environment = env
			sv.add_child(we)
			var cam := Camera3D.new()
			cam.position = Vector3(0, 0, 3)
			sv.add_child(cam)
			var mi := MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			sv.add_child(mi)
			var l := DirectionalLight3D.new()
			l.rotation_degrees = Vector3(-40, 30, 0)
			sv.add_child(l)
		for i in 4:
			await RenderingServer.frame_post_draw
		var txt := "?"
		var img := sv.get_texture().get_image()
		if img and not img.is_empty():
			var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
			var e := img.get_pixel(3, 3)
			txt = "orta(%.2f,%.2f,%.2f,a%.1f) kose(%.2f,%.2f,%.2f,a%.1f)" % [c.r, c.g, c.b, c.a, e.r, e.g, e.b, e.a]
			txt = ("OK " if e.a > 0.5 else "BOS ") + txt
		res.append(variant + "=" + txt)
	holder.queue_free()
	var line := "OZTEST %s (portre=%d): %s" % [tag, Portrait.rendered, " | ".join(res)]
	dbc(line)
	return line
