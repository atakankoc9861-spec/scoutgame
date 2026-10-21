extends RefCounted
## Tech-art Faz 2 (v0.24 3B): oyuncu verisinden görünür fiziksel özellikler.
## Kayda hiçbir şey yazılmaz: boy/kilo tohum + pozisyon + güç + yaştan deterministik türetilir.
## Bayrak: Game.settings.traits3d (varsayılan açık); safe3d açıkken her zaman kapalı.

const GREY := Color(0.62, 0.6, 0.58)
# pozisyon -> [ortalama boy cm, sapma]
const H_POS := {
	"GK": [187.0, 4.5], "CB": [186.0, 4.0], "ST": [182.0, 6.0], "CF": [182.0, 6.0],
	"DM": [180.0, 5.0], "CM": [178.0, 5.0], "LB": [176.0, 4.5], "RB": [176.0, 4.5],
	"LWB": [175.0, 4.5], "RWB": [175.0, 4.5], "AM": [175.0, 5.0], "LW": [174.0, 5.0], "RW": [174.0, 5.0],
	"LM": [176.0, 5.0], "RM": [176.0, 5.0],
}
const S_MIN := 0.92
const S_MAX := 1.10

static func enabled() -> bool:
	if Game.settings.get("safe3d", false):
		return false
	return bool(Game.settings.get("traits3d", true))

static func _attr(p: Dictionary, k: String, def := 10.0) -> float:
	var a: Dictionary = p.get("attrs", {})
	return float(a.get(k, def))

## {h_cm, kg}: deterministik (aynı oyuncu -> hep aynı sonuç), sınırlı aralıkta
static func phys(p: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(p.get("seed", 0)) * 7349 + 101)
	var hp: Array = H_POS.get(str(p.get("pos", "CM")), [179.0, 5.0])
	var z := clampf(rng.randfn(0.0, 1.0), -2.0, 2.0)
	var stg := _attr(p, "strength")
	var age := float(p.get("age", 24))
	var h: float = hp[0] + z * hp[1] + (stg - 10.0) * 0.5
	if age < 18.0:
		h -= clampf((18.0 - age) * 1.5, 0.0, 6.0)
	h = clampf(h, 162.0, 199.0)
	var bmi := 22.4 + (stg - 10.0) * 0.22 - (_attr(p, "pace") - 10.0) * 0.08 + maxf(0.0, age - 30.0) * 0.25 + clampf(rng.randfn(0.0, 0.9), -1.8, 1.8)
	bmi = clampf(bmi, 19.0, 27.5)
	var kg := bmi * pow(h / 100.0, 2.0)
	return {"h_cm": snappedf(h, 0.1), "kg": snappedf(kg, 0.1), "bmi": bmi}

## Model ölçeği (180 cm = 1.0)
static func scale_for(h_cm: float) -> float:
	return clampf(h_cm / 180.0, S_MIN, S_MAX)

## Kafa kemiği ölçeği: uzun oyuncunun kafası orantısız büyümesin (net kafa ölçeği s^0.4)
static func head_comp(s: float) -> float:
	return pow(s, -0.6)

## 31 yaştan sonra saç/sakal kırlaşması (0 = yok)
static func grey(age: float) -> float:
	if age < 31.0:
		return 0.0
	return clampf(0.2 + (age - 31.0) * 0.07, 0.2, 0.5)

## Dönüş kazancı: çevik oyuncu hedef yöne daha hızlı döner
static func turn_gain(agility: float) -> float:
	return clampf(1.0 + (agility - 10.0) * 0.04, 0.7, 1.4)

## Yorgunluk 0..1: 70. dakikadan (4200 sn) sonra düşük kondisyonda artar
static func tired(stamina: float, clock: float) -> float:
	if clock <= 4200.0:
		return 0.0
	return clampf((12.0 - stamina) / 7.0, 0.0, 1.0) * clampf((clock - 4200.0) / 1200.0, 0.0, 1.0)

## Mocap için özellik paketi (bayrak kapalıysa boş sözlük)
static func for_player(p: Dictionary) -> Dictionary:
	if p.is_empty() or not enabled():
		return {}
	var ph := phys(p)
	var s := scale_for(ph.h_cm)
	return {
		"h_cm": ph.h_cm, "kg": ph.kg, "bmi": ph.bmi,
		"scale": s, "head": head_comp(s),
		"grey": grey(float(p.get("age", 24))),
		"turn": turn_gain(_attr(p, "agility")),
		"stamina": _attr(p, "stamina"),
		"foot": "L" if str(p.get("foot", "R")) == "L" else "R",
	}

## Yapıdan daha cesur gövde morph'ları (mevcut morph'lar, maç uzaklığında siluet farkı)
static func body_morphs(L: Dictionary, tr: Dictionary, p: Dictionary) -> void:
	var bmi: float = tr.bmi
	var stg := _attr(p, "strength")
	L["muscle"] = clampf((stg - 8.0) / 7.0, 0.0, 1.0)
	L["heavy"] = clampf((bmi - 23.5) / 3.0, 0.0, 0.9)
	L["thin"] = clampf((21.8 - bmi) / 2.5, 0.0, 0.9)
	L["lean"] = clampf((9.0 - stg) / 6.0, 0.0, 0.9)
