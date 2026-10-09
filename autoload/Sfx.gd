extends Node
## Ses efektleri: oyunla birlikte gelen WAV dosyaları (en kararlı yol).
## Kısıtlamalar: az oynatıcı, sabit perde, sık tekrar sınırı.

const FILES := {
	"crowd": preload("res://audio/crowd.wav"),
	"crowd_hi": preload("res://audio/crowd_hi.wav"),
	"roar": preload("res://audio/roar.wav"),
	"ooh": preload("res://audio/ooh.wav"),
	"whistle": preload("res://audio/whistle.wav"),
	"whistle3": preload("res://audio/whistle3.wav"),
	"kick": preload("res://audio/kick.wav"),
	"net": preload("res://audio/net.wav"),
	"ring": preload("res://audio/ring.wav"),
	"pen": preload("res://audio/pen.wav"),
	"blip": preload("res://audio/blip.wav"),
	"spark": preload("res://audio/spark.wav"),
	"catch": preload("res://audio/catch.wav"),
	"cafe": preload("res://audio/cafe.wav"),
	"field": preload("res://audio/field.wav"),
}

const MUSIC := preload("res://audio/menu.ogg")
var music: AudioStreamPlayer
var _mus_target := -60.0
var _mus_pos := 0.0
var crowd: AudioStreamPlayer
var crowd2: AudioStreamPlayer
var pool: Array = []
var _target := 0.0
var _level := 0.0
var _last := {}

func _ready() -> void:
	crowd = AudioStreamPlayer.new()
	crowd.stream = FILES.crowd
	crowd.volume_db = -60
	add_child(crowd)
	crowd2 = AudioStreamPlayer.new()
	crowd2.stream = FILES.crowd_hi
	crowd2.volume_db = -60
	add_child(crowd2)
	music = AudioStreamPlayer.new()
	music.stream = MUSIC
	music.volume_db = -60
	add_child(music)
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)

func _on() -> bool:
	return Game.settings.get("sound", true)

func play(name: String, vol_db := 0.0, _pitch := 1.0) -> void:
	if not _on() or not FILES.has(name):
		return
	var now := Time.get_ticks_msec()
	var gap := 140 if name == "kick" else (45 if name == "blip" else 250)
	if now - int(_last.get(name, 0)) < gap:
		return
	_last[name] = now
	for p in pool:
		if not p.playing:
			p.stream = FILES[name]
			p.volume_db = vol_db
			p.play()
			return

## Sahne ortam sesi (kafe uğultusu, saha rüzgarı); döngü
var amb: AudioStreamPlayer
func amb_on(name: String, vol := -16.0) -> void:
	if not _on() or not FILES.has(name):
		return
	if amb == null:
		amb = AudioStreamPlayer.new()
		add_child(amb)
		amb.finished.connect(func(): if amb.stream: amb.play())
	amb.stream = FILES[name]
	amb.volume_db = vol
	amb.play()

func amb_off() -> void:
	if amb:
		amb.stream = null
		amb.stop()

func crowd_on(level := 0.35) -> void:
	if not _on():
		return
	_target = level
	if not crowd.playing:
		crowd.play()
	if not crowd2.playing:
		crowd2.play()

func crowd_level(level: float) -> void:
	_target = level

func crowd_off() -> void:
	_target = 0.0

func stop_all() -> void:
	_target = 0.0
	_level = 0.0
	crowd.stop()
	crowd2.stop()
	for p in pool:
		p.stop()

func music_on() -> void:
	if not Game.settings.get("music", true):
		music_off()
		return
	_mus_target = -15.0
	if not music.playing:
		music.volume_db = -40.0
		music.play(_mus_pos)

func music_off() -> void:
	_mus_target = -60.0

func _process(delta: float) -> void:
	if music.playing:
		music.volume_db = lerpf(music.volume_db, _mus_target, minf(1.0, delta * 1.5))
		if _mus_target <= -59.0 and music.volume_db < -50.0:
			_mus_pos = music.get_playback_position()
			music.stop()
	if not _on():
		if crowd.playing:
			stop_all()
		return
	_level = lerpf(_level, _target, minf(1.0, delta * 2.0))
	if _level < 0.01 and _target <= 0.0:
		if crowd.playing:
			crowd.stop()
			crowd2.stop()
		return
	crowd.volume_db = linear_to_db(clampf(_level, 0.001, 1.0)) - 4.0
	crowd2.volume_db = linear_to_db(clampf((_level - 0.4) * 1.6, 0.001, 1.0)) - 3.0
