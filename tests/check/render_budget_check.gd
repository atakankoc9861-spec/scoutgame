extends "res://tests/check/check_base.gd"
## Tech-art Faz 0+1 kapısı (headless, sayım tabanlı; GPU sayacı headless'ta 0 gelir):
## - Stadyum: lamba kutuları tek mesh'te (bayrak açık), vekil draw call bayrak kapalıdan az.
## - Uzak oyuncu animasyon seyreltmesi: >35 m'de 2 karede 1 atlar, yakında/aksiyonda/bayrak kapalıyken atlamaz.
## - 3 doku VRAM sıkıştırılmış + mipmap'li; render_baseline.json var ve draw call artmamış.
## - stage3d MSAA kuralı mobilde kapalı (match_view ile aynı); Watch perf satırı çalışıyor.

const Stadium = preload("res://three/stadium.gd")
const FB = preload("res://three/mocap_man.gd")

func watchdog_sec() -> float:
	return 120.0

## Görünür GeometryInstance3D yüzeyleri (Compat'ta ~draw call vekili)
func _proxy_dc(root: Node) -> int:
	var n := 0
	for g in root.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		if mi.visible and mi.mesh:
			n += mi.mesh.get_surface_count()
	return n

func _stadium(merge: bool) -> Node3D:
	Game.settings["ta_merge_lamps"] = merge
	Game.settings["ta_merge_decor"] = false   # v0.24 3B genel dekor birleştirmesi ayrı ölçülür (traits3d_check)
	var sd: Node3D = Stadium.new()
	add_child(sd)
	sd.configure(0, "night", "clear")
	sd.build(Color.RED, Color.WHITE, Color.BLUE, true, false, true)
	return sd

func run_check() -> void:
	# --- stadyum lamba birleştirme
	var a := _stadium(false)
	var dc_off := _proxy_dc(a)
	var lamp_boxes := 0
	for g in a.find_children("*", "MeshInstance3D", true, false):
		var bm := (g as MeshInstance3D).mesh as BoxMesh
		if bm and bm.size.is_equal_approx(Vector3(1.6, 1.0, 0.2)):
			lamp_boxes += 1
	a.free()
	var b := _stadium(true)
	var dc_on := _proxy_dc(b)
	var lamps := b.find_child("Lamps", false, false) as MeshInstance3D
	check(lamps != null, "birleşik Lamps mesh'i yok")
	if lamps:
		# tier 0: 4 kule x 4x3 kutu = 48 kutu, her biri 36 indeks (12 üçgen)
		var am := lamps.mesh as ArrayMesh
		var idx: int = am.surface_get_array_index_len(0)
		var tris: int = idx if idx > 0 else am.surface_get_array_len(0)
		check(tris / 3 == lamp_boxes * 12, "Lamps üçgen sayısı %d != %d kutu x 12" % [tris / 3, lamp_boxes])
	check(lamp_boxes == 48, "tier0 lamba kutusu beklenen 48, bulunan %d" % lamp_boxes)
	check(dc_on == dc_off - lamp_boxes + 1, "vekil draw call: açık %d, kapalı %d, kutu %d" % [dc_on, dc_off, lamp_boxes])
	log_info("stadyum tier0 gece vekil draw call: %d -> %d (lamba kutusu %d -> 1)" % [dc_off, dc_on, lamp_boxes])
	b.free()
	Game.settings.erase("ta_merge_lamps")
	Game.settings.erase("ta_merge_decor")

	# --- uzak oyuncu animasyon seyreltme
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var near: Node3D = FB.new()
	var far: Node3D = FB.new()
	for m in [near, far]:
		m.lod = true
		add_child(m)
		m.build(FB.kit_mats(Color.RED, Color.WHITE, Color.RED), 1, 0, 3, 7)
	near.position = Vector3(0, 0, -10)
	far.position = Vector3(0, 0, -60)
	FB.thin_skipped = 0
	for i in 10:
		await get_tree().process_frame
		near.tick(1.0 / 60.0, 3.0)
	check(FB.thin_skipped == 0, "yakın oyuncu seyreltildi (%d)" % FB.thin_skipped)
	FB.thin_skipped = 0
	var ph0: float = far.phase
	for i in 10:
		await get_tree().process_frame
		far.tick(1.0 / 60.0, 3.0)
	check(FB.thin_skipped == 5, "uzak oyuncu 10 karede 5 atlamalı, atlanan %d" % FB.thin_skipped)
	check(not is_equal_approx(far.phase, ph0), "seyreltmede faz ilerlemedi")
	# aksiyon sırasında atlanmaz
	FB.thin_skipped = 0
	far.play("kick")
	for i in 6:
		await get_tree().process_frame
		far.tick(1.0 / 60.0, 3.0)
	check(FB.thin_skipped == 0, "aksiyonda seyreltme olmamalı (%d)" % FB.thin_skipped)
	# bayrak kapalı
	Game.settings["ta_anim_thin"] = false
	FB.thin_skipped = 0
	for i in 60:
		far.tick(1.0 / 60.0, 3.0)   # aksiyon bitsin
	FB.thin_skipped = 0
	for i in 6:
		await get_tree().process_frame
		far.tick(1.0 / 60.0, 3.0)
	check(FB.thin_skipped == 0, "bayrak kapalıyken seyreltme olmamalı (%d)" % FB.thin_skipped)
	Game.settings.erase("ta_anim_thin")
	near.free()
	far.free()
	cam.free()

	# --- doku içe aktarma: VRAM sıkıştırma + mipmap
	for p in ["res://assets/mh/skin_detail.png", "res://assets/mh/skin_detail2.png", "res://assets/ads/atlas.png"]:
		var cf := ConfigFile.new()
		check(cf.load(p + ".import") == OK, p + ".import okunamadı")
		check(int(cf.get_value("params", "compress/mode", 0)) == 2, p + " VRAM sıkıştırılmış değil")
		check(bool(cf.get_value("params", "mipmaps/generate", false)), p + " mipmap yok")
		var tex := load(p) as Texture2D
		check(tex != null and tex.get_width() > 0, p + " yüklenemedi")

	# --- stage3d MSAA kuralı (kaynak düzeyi: mobil koşulu match_view ile aynı)
	var src := FileAccess.get_file_as_string("res://three/stage3d.gd")
	var rx := RegEx.new()
	rx.compile("sv\\.msaa_3d = Viewport\\.MSAA_2X if [^\\n]*")
	for r in rx.search_all(src):
		check(r.get_string().find("not OS.has_feature(\"mobile\")") >= 0, "stage3d MSAA satırında mobil koşulu yok: " + r.get_string())
	check(rx.search_all(src).size() >= 1, "stage3d MSAA satırı bulunamadı")

	# --- Watch perf satırı + gizli anahtar
	var line: String = Watch.perf_line()
	check(line.begins_with("PERF dc="), "perf satırı biçimi: " + line)
	var was: bool = Watch.perf_on()
	Watch.set_perf(true)
	check(Watch.perf_on() and Watch._perf_layer != null, "perf göster açılmadı")
	Watch.set_perf(false)
	check(not Watch.perf_on(), "perf göster kapanmadı")
	Watch.set_perf(was)

	# --- render_baseline.json: var, ölçüm alanları dolu, draw call artmamış
	const RB := "res://tests/baseline/render_baseline.json"
	var js: Variant = JSON.parse_string(FileAccess.get_file_as_string(RB)) if FileAccess.file_exists(RB) else null
	check(js is Dictionary, "render_baseline.json yok/bozuk")
	if js is Dictionary:
		var bef: Dictionary = js.get("before", {})
		var aft: Dictionary = js.get("after", {})
		check(not bef.is_empty() and bef.size() == aft.size(), "before/after sahneleri eksik")
		for sc in bef:
			if not aft.has(sc):
				check(false, "after'da %s yok" % sc)
				continue
			for k in ["draw_calls", "primitives", "texture_mem_mb"]:
				check(bef[sc].has(k) and aft[sc].has(k), "%s.%s eksik" % [sc, k])
			check(float(aft[sc].draw_calls) <= float(bef[sc].draw_calls), "%s draw call arttı: %s -> %s" % [sc, str(bef[sc].draw_calls), str(aft[sc].draw_calls)])
