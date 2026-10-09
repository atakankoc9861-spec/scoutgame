extends Node
## Donma bekçisi: ana iş parçacığı takılırsa (siyah ekran, ses devam) ayrı bir
## thread durumu diske yazar. Bir sonraki açılışta hata kaydına eklenir.

const BC_FILE := "user://watch_bc.txt"
const STALL_FILE := "user://watch_stall.txt"
const PREV_FILE := "user://watch_prev.txt"

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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# önceki oturumun izleri
	var parts := []
	if FileAccess.file_exists(STALL_FILE):
		parts.append("=== ONCEKI OTURUM DONMA ===\n" + FileAccess.get_file_as_string(STALL_FILE))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STALL_FILE))
	if FileAccess.file_exists(BC_FILE):
		parts.append("=== ONCEKI OTURUM SON ADIMLAR ===\n" + FileAccess.get_file_as_string(BC_FILE))
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
	th = Thread.new()
	th.start(_loop)

func _process(_d: float) -> void:
	hb = Time.get_ticks_msec()
	if reported:
		reported = false
		bc("donma bitti (ana thread geri geldi)")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		paused = true
		bc("arka plana alindi")
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		paused = false
		hb = Time.get_ticks_msec()
		bc("on plana geldi")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		alive = false

func _exit_tree() -> void:
	alive = false
	if th and th.is_started():
		th.wait_to_finish()

func _mon() -> String:
	return "vmem=%dMB tex=%dMB nodes=%d obj=%d" % [int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6), int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT))]

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
