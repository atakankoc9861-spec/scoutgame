extends "res://tests/check/check_base.gd"
## Tech-art Faz 2 kapısı (v0.24 3B, headless):
## - Traits3D: boy/kilo deterministik ve sınırlı; ölçek [0.92,1.10]; kır saç/dönüş/yorgunluk aralıkta.
## - Bayrak kapalı (traits3d=false ya da safe3d=true) -> mocap_man eskisiyle birebir (look, ölçek, kemik, klip).
## - Vuruş ayağı: sol ayaklıda kick/shot sol uyluk klibi, sağ ayaklıda sağ.
## - Adım: ölçekli oyuncu aynı hızda daha az döngü atar (faz/sn = 1/s).
## - Küçük saha: statik dekor birleştirmesi vekil draw call'u düşürür, üçgen sayısı aynı kalır.

const TR = preload("res://three/traits3d.gd")
const FB = preload("res://three/mocap_man.gd")
const Stadium = preload("res://three/stadium.gd")

func watchdog_sec() -> float:
	return 180.0

func _players(n: int) -> Array:
	var out: Array = []
	var ids: Array = Game.s.players.keys()
	for pid in ids:
		out.append(Game.player(pid))
		if out.size() >= n:
			break
	return out

func _man(p: Dictionary) -> Node3D:
	var m: Node3D = FB.new()
	m.lod = true
	add_child(m)
	m.apply_look(p)
	m.build(FB.kit_mats(Color.RED, Color.WHITE, Color.RED), int(p.get("skin", 1)), int(p.get("hair", 0)), int(p.get("seed", 0)), 7)
	return m

func _sig(m: Node3D) -> String:
	var hb: int = m.skel.find_bone("head")
	var parts := []
	for k in m.parts:
		var mi: MeshInstance3D = m.parts[k]
		var w := []
		for i in mi.get_blend_shape_count():
			w.append(snappedf(mi.get_blend_shape_value(i), 0.0001))
		parts.append([k, w, mi.material_override.get_instance_id() if mi.material_override else 0])
	parts.sort()
	return JSON.stringify([m._inst.scale, m.skel.get_bone_pose_scale(hb), parts])

func _proxy_dc(root: Node) -> int:
	var n := 0
	for g in root.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		if mi.visible and mi.mesh:
			n += mi.mesh.get_surface_count()
	for g in root.find_children("*", "MultiMeshInstance3D", true, false):
		n += 1
	return n

func _tris(root: Node) -> int:
	var n := 0
	for g in root.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			n += (idx.size() if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n

func run_check() -> void:
	Game.new_game("T", "tr")
	var ps := _players(60)
	check(ps.size() >= 40, "yeterli oyuncu yok (%d)" % ps.size())

	# --- eşleme: deterministik + sınırlı
	var hs := []
	for p in ps:
		var a: Dictionary = TR.phys(p)
		var b: Dictionary = TR.phys(p.duplicate(true))
		check(a == b, "phys deterministik değil: %s" % str(p.get("id", "")))
		check_num(a.h_cm, "boy", 162.0, 199.0)
		check_num(a.kg, "kilo", 50.0, 110.0)
		var s: float = TR.scale_for(a.h_cm)
		check_num(s, "ölçek", 0.92, 1.10)
		check_num(TR.head_comp(s), "kafa telafisi", 0.94, 1.06)
		check_num(TR.grey(float(p.age)), "kır saç", 0.0, 0.5)
		check_num(TR.turn_gain(float(p.attrs.get("agility", 10))), "dönüş", 0.7, 1.4)
		hs.append(a.h_cm)
	hs.sort()
	check(hs[-1] - hs[0] >= 12.0, "boy yayılımı çok dar: %.1f..%.1f" % [hs[0], hs[-1]])
	var gk := {"seed": 5, "pos": "GK", "age": 26, "attrs": {"strength": 12}}
	var wg := {"seed": 5, "pos": "RW", "age": 26, "attrs": {"strength": 12}}
	check(TR.phys(gk).h_cm > TR.phys(wg).h_cm, "kaleci aynı tohumlu kanattan uzun olmalı")
	check(TR.grey(30.0) == 0.0 and TR.grey(34.0) > 0.2, "kır saç yaş eşiği")
	check(TR.tired(6.0, 4000.0) == 0.0 and TR.tired(6.0, 5400.0) > 0.7 and TR.tired(16.0, 5400.0) == 0.0, "yorgunluk eşlemesi")
	check(TR.turn_gain(18.0) > 1.2 and TR.turn_gain(4.0) < 0.85, "çeviklik kazancı")

	# --- bayrak kapalı -> eskisiyle birebir; safe3d de kapatır
	var p0: Dictionary = ps[0].duplicate(true)
	p0["age"] = 34
	Game.settings["traits3d"] = false
	var m_off := _man(p0)
	var sig_off := _sig(m_off)
	check(m_off.traits.is_empty(), "bayrak kapalıyken traits dolu")
	var ref := FB.look_for(int(p0.seed), int(p0.get("skin", 1)), p0)
	check(m_off.look == ref, "bayrak kapalıyken look eski look_for'dan farklı")
	Game.settings["traits3d"] = true
	Game.settings["safe3d"] = true
	var m_safe := _man(p0)
	check(m_safe.traits.is_empty() and _sig(m_safe) == sig_off, "safe3d açıkken görünüm farklı")
	Game.settings.erase("safe3d")
	Game.settings.erase("traits3d")
	var m_on := _man(p0)
	check(not m_on.traits.is_empty(), "varsayılan bayrakla traits boş")
	check(_sig(m_on) != sig_off, "bayrak açıkken görünüm değişmedi")
	check(is_equal_approx(m_on._inst.scale.x, float(m_on.traits.scale)), "model ölçeği boydan değil")
	var hb: int = m_on.skel.find_bone("head")
	check(m_on.skel.get_bone_pose_scale(hb).x < 1.0 == (float(m_on.traits.scale) > 1.0), "kafa telafisi yönü")
	for m in [m_off, m_safe, m_on]:
		m.free()

	# --- vuruş ayağı veriden
	check(FB.clip_foot("pass") != FB.clip_foot("pass_m"), "pass/pass_m aynı ayak: %s" % FB.clip_foot("pass"))
	check(FB.clip_foot("shot") != FB.clip_foot("shot_m"), "shot/shot_m aynı ayak")
	var nl := 0
	for p in ps.slice(0, 24):
		var m := _man(p)
		for act in ["kick", "shot"]:
			m.play(act)
			check(FB.clip_foot(m.act_clip) == str(p.foot), "%s ayak %s ama %s klibi %s" % [act, p.foot, m.act_clip, FB.clip_foot(m.act_clip)])
			m.action = ""
		if str(p.foot) == "L":
			nl += 1
		m.free()
	log_info("vuruş ayağı: 24 oyuncu (%d sol ayaklı) eşleşti" % nl)

	# --- adım: aynı hızda faz ilerlemesi 1/s
	var tall := {"seed": 11, "pos": "CB", "age": 27, "attrs": {"strength": 18, "agility": 8}, "foot": "R"}
	var m_t := _man(tall)
	var s_t: float = m_t.traits.scale
	Game.settings["traits3d"] = false
	var m_r := _man(tall)
	Game.settings.erase("traits3d")
	m_t.phase = 0.0
	m_r.phase = 0.0
	for i in 20:
		m_t.tick(1.0 / 60.0, 3.6 * s_t)
		m_r.tick(1.0 / 60.0, 3.6)
	check(absf(m_t.phase - m_r.phase) < 0.002, "adım ölçeklenmesi: %.4f vs %.4f (s=%.3f)" % [m_t.phase, m_r.phase, s_t])
	m_t.free()
	m_r.free()

	# --- küçük saha dekor birleştirme (vekil draw call, üçgen korunur)
	for t in [2, 3]:
		var res := {}
		for mg in [false, true]:
			Game.settings["ta_merge_decor"] = mg
			var sd: Node3D = Stadium.new()
			add_child(sd)
			sd.configure(t, "day", "clear")
			sd.build(Color.RED, Color.WHITE, Color.BLUE, false, false, true)
			res[mg] = [_proxy_dc(sd), _tris(sd)]
			sd.free()
		Game.settings.erase("ta_merge_decor")
		check(res[true][0] < res[false][0] - 40, "tier%d dekor birleştirme yetersiz: %d -> %d" % [t, res[false][0], res[true][0]])
		check(res[true][1] == res[false][1], "tier%d üçgen sayısı değişti: %d -> %d" % [t, res[false][1], res[true][1]])
		log_info("stadyum tier%d vekil draw call %d -> %d, üçgen %d" % [t, res[false][0], res[true][0], res[true][1]])
