extends RefCounted
## Gözcü v0.24 tema tokenları — UI planı seçenek A "Gece Dosyası" (analist masası).
## Koyu deri masa üstünde krem dosyalar. Pirinç yalnız etkileşim (CTA, aktif, odak),
## mühür kırmızısı yalnız mühür ve uyarı, mavi mürekkep yalnız oyuncunun kendi notu.
## Yalnız sabitler + saf yardımcılar: durum tutmaz, autoload değildir.
## Kullanım: const TV := preload("res://ui/theme_v24.gd"); kit.gd C_* sabitleri bunlara takma addır.
## Mobil: yalnız StyleBoxFlat / doku; shader, blur, ekran kopyası yok.

# ---------------------------------------------------------------- renk tokenları
const DESK := Color("#13100c")       # ekran zemini
const LEATHER := Color("#2a1f17")    # üst bar, nav
const LEATHER2 := Color("#3a2b20")
const PAPER := Color("#efe6d1")      # sayfa
const CARD := Color("#f7f1e3")       # kart
const MEMO := Color("#fbf7ec")       # çizgili not
const MANILA := Color("#dcc391")     # klasör, oyuncu başlığı
const MANILA_D := Color("#bfa065")
const INK := Color("#1f1c17")        # metin
const INK2 := Color("#6a6150")       # ikincil metin (kâğıtta ~5.4:1)
const LINE := Color(0.24, 0.16, 0.08, 0.16)
const BRASS := Color("#d4a84b")      # CTA, aktif nav, odak
const BRASS_HI := Color("#f0c96a")
const BRASS_LO := Color("#a8802f")   # pirinç düğmenin "kalınlık" kenarı
const STAMP := Color("#c0352b")      # mühür, uyarı, rapor
const STAMP_LO := Color("#8e241d")
const BLUE := Color("#2350a0")       # el notu, bilgi
const GOOD := Color("#2f7d40")       # olumlu
const HL := Color("#f3d65b")         # seçili (fosforlu kalem)
const CREAM := Color("#f1e6cf")      # deri üstü metin
const CREAM2 := Color("#b8a888")
const SHADOW := Color(0.24, 0.15, 0.06, 0.30)   # sıcak gölge (siyah değil)

# ---------------------------------------------------------------- tipografi
## Dosyalar res://fonts/<ad>.ttf. Hepsi OFL ve Türkçe tam (ğ ş ı İ Ö Ç Ü).
## Hiyerarşi yazı tipi değişimiyle değil boyut/ağırlıkla kurulur.
const FONT_BODY := "Barlow-Medium"              # gövde
const FONT_SEMI := "Barlow-SemiBold"
const FONT_HEAD := "BarlowCondensed-ExtraBold"  # başlık, düğme, sayı
const FONT_HEADR := "BarlowCondensed-Bold"
const FONT_MONO := "IBMPlexMono-Medium"         # etiket, form kodu
const FONT_MONOB := "IBMPlexMono-SemiBold"      # mühür, değer
const FONT_HAND := "Caveat-Bold"                # yalnız el notları
const FONT_DISP := "BarlowCondensed-ExtraBold"
## Harf aralığı (piksel, FontVariation.spacing_glyph)
const TRACK_HEAD := 1
const TRACK_STAMP := 3
const TRACK_MONO := 0

# ---------------------------------------------------------------- ölçüler
const R_CARD := 6          # kart köşesi
const R_BTN := 10
const R_STAMP := 3
const SHADOW_CARD := 6     # kartta ≤ 8 (compat'ta ucuz kalsın)
const CORNER_DETAIL := 5   # mobilde gereksiz tepe noktası üretme
const BTN_MIN := 80        # birincil düğme yüksekliği
const BTN_MIN_SMALL := 72  # küçük düğme (≈ 48 dp dokunma hedefi)
const BTN_EDGE := 4        # pirinç/kırmızı düğmenin alt "kalınlık" kenarı

# ---------------------------------------------------------------- yardımcılar

## Türkçe büyük harf: "i"→"İ", "ı"→"I" (String.to_upper() Türkçe kuralı bilmez).
static func upper(text: String, lang := "tr") -> String:
	if lang == "tr":
		text = text.replace("i", "İ").replace("ı", "I")
	return text.to_upper()

## Düz yüzey: köşe, kenar, iç boşluk ve isteğe bağlı sıcak gölge.
static func flat(col: Color, radius := R_BTN, border := 0, bcol := LINE, pad := 14, shadow := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.corner_detail = CORNER_DETAIL
	sb.set_border_width_all(border)
	sb.border_color = bcol
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	if shadow > 0:
		sb.shadow_size = mini(shadow, 8)
		sb.shadow_color = SHADOW
		sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb

## Kalın düğme (pirinç/kırmızı/mürekkep): yüz + koyu alt kenar ("kalınlık") + gölge.
## pressed=true: alt kenar kaybolur, yazı 2 px aşağı iner (çökme hissi).
static func raised(face: Color, edge: Color, pad := 18, pressed := false) -> StyleBoxFlat:
	var sb := flat(face, R_BTN, 0, LINE, pad, 0 if pressed else 6)
	sb.border_color = edge
	sb.border_width_bottom = 0 if pressed else BTN_EDGE
	sb.border_blend = false
	if pressed:
		sb.content_margin_top += 2
		sb.content_margin_bottom = maxf(sb.content_margin_bottom - 2, 0)
	return sb

## Düğme türleri: {n, h, p, fc, fs, min}. kit.gd::_btn_styles bunu kullanır.
static func button(kind: String) -> Dictionary:
	match kind:
		"primary", "brass":
			return {"n": raised(BRASS, BRASS_LO), "h": raised(BRASS_HI, BRASS_LO),
				"p": raised(BRASS.darkened(0.08), BRASS_LO, 18, true), "fc": LEATHER, "fs": 28, "min": BTN_MIN}
		"red":
			return {"n": raised(STAMP, STAMP_LO), "h": raised(STAMP.lightened(0.08), STAMP_LO),
				"p": raised(STAMP.darkened(0.1), STAMP_LO, 18, true), "fc": Color("#fbeee0"), "fs": 28, "min": BTN_MIN}
		"ink":
			return {"n": raised(INK, Color("#000000")), "h": raised(INK.lightened(0.08), Color("#000000")),
				"p": raised(Color("#000000"), Color("#000000"), 18, true), "fc": CREAM, "fs": 28, "min": BTN_MIN}
		"dark":
			return {"n": flat(Color(1, 1, 1, 0.06), R_BTN, 1, Color(CREAM, 0.25), 16), "h": flat(Color(1, 1, 1, 0.1), R_BTN, 1, Color(CREAM, 0.35), 16),
				"p": flat(Color(BRASS, 0.3), R_BTN, 2, BRASS, 16), "fc": CREAM, "fs": 22, "min": BTN_MIN_SMALL}
		"toggle_on":
			return {"n": flat(HL, R_BTN, 2, INK, 12), "h": flat(HL, R_BTN, 2, INK, 12),
				"p": flat(HL.darkened(0.1), R_BTN, 2, INK, 12), "fc": INK, "fs": 21, "min": BTN_MIN_SMALL}
		"ghost":
			return {"n": flat(Color(1, 1, 1, 0.35), R_BTN, 2, Color(INK, 0.55), 12), "h": flat(Color(1, 1, 1, 0.5), R_BTN, 2, Color(INK, 0.7), 12),
				"p": flat(HL, R_BTN, 2, INK, 12), "fc": INK, "fs": 21, "min": BTN_MIN_SMALL}
		"danger":
			return {"n": flat(Color(STAMP, 0.06), R_BTN, 2, STAMP, 12), "h": flat(Color(STAMP, 0.1), R_BTN, 2, STAMP, 12),
				"p": flat(Color(STAMP, 0.2), R_BTN, 2, STAMP, 12), "fc": STAMP, "fs": 21, "min": BTN_MIN_SMALL}
	# small (varsayılan): kart rengi, mürekkep çerçeve, basınca fosforlu
	return {"n": flat(CARD, R_BTN, 2, INK, 12), "h": flat(Color("#fffaf0"), R_BTN, 2, INK, 12),
		"p": flat(HL, R_BTN, 2, INK, 12), "fc": INK, "fs": 21, "min": BTN_MIN_SMALL}
