# Gözcü v0.24 — Arayüz Planı (UI Designer)

Mockup dosyası: `/tmp/claude-0/-home-claude-scoutgame/57852014-e0f7-5c93-9de4-c4c1759bf64e/scratchpad/v024/ui-mockups.html` (2 seçenek × 4 ekran, 390×844, sekme geçiş demoları dahil, telefonlar etkileşimli).
Ekran görüntüleri: aynı klasörde `shot_a.png`, `shot_b.png`, `shot_aspec.png`, `shot_bdemo.png`.

Kapsam: yalnızca tasarım. Repoda hiçbir şey değiştirilmedi. `ui/main.gd` refactor sürdüğü için öneriler `ui/kit.gd` ve yeni dosyalara (`ui/theme_v24.gd`, `ui/motion.gd`) yönlendirildi.

---

## 1. Denetim bulguları (kod üzerinden)

### 1.1 Yapı
- **Tuval:** 720×1280, `canvas_items` + `expand`, dikey. Renderer `gl_compatibility` (mobil dahil).
- **Kabuk (`_build_shell`):** Alt katmanda masa rengi (`C_DESK`) ve 3D `Hub3D` arka planı, üstünde gradyan gölge, deri üst bar (`topbar`), kaydırılabilir içerik (`scroll → margin → outer`), deri alt nav (`navbar`, 92 px) ve toast.
- **Gezinme modeli:** 6 alt sekme (Ofis, Takvim, Görevler, Oyuncular, Ekip, Dünya). Her sekmenin içinde **klasör alt sekmeleri** var (`_sheet` + `_tabs`). Detay ekranları `stack`'e itiliyor (player, report, club, match, table, trip). Krom gösterilmeyen tam ekranlar: title, newgame, offers, result, season, obs, crash. Modallar `_modal_layer` ile açılıyor. Hikâye sahneleri `_scene_*` ile yönetiliyor.
- **Ekran listesi (`_show`):** title, newgame, offers, home (summary/board/career/archive/club), week, match (plan), tasks (requests/reports/transfers), players (shadow/shortlist/search/youth/compare), player (file/attrs/notes/career), report, news (news/table/fixtures), team (staff/pool/reports), table, club, result, obs, season, crash, trip. Bunlara ek olarak maç görüntüleyici (`three/match_view.gd`, kendi HUD'ı) ve olay popup'ları (deadline, tournament, dilemma, life, rumor, legend, rival, story).
- **HERO bandı:** Ekran başına 150–330 px boş alan bırakılıp 3D hub içinden görünüyor (`HERO` sözlüğü).

### 1.2 Görsel dil (bugün)
- “Scout dosyası” teması: prosedürel kâğıt dokusu (9 parça `StyleBoxTexture`), manila klasör sekmeleri, deri bar ve dikiş çizgisi, mühürler (`_stamp`, `_stamp_slam`), polaroid, bilet kartı, ataş, el yazısı not (Caveat), daktilo (Courier Prime), Special Elite mühür fontu.
- **Palet:** kâğıt `#EFE6D1`, kart `#F8F3E7`, manila `#DCC391`, mürekkep `#27241E`, kırmızı `#B3261E`, mavi `#1F4E8C`, yeşil `#2C7A39`, fosforlu `#F3D65B`, pirinç `#C9A24A`, deri `#2B1E17`, masa `#15100C`.
- **Yazı tipleri:** 9 dosya, 6 aile (Barlow, Barlow Condensed, Oswald, Courier Prime, Caveat, Special Elite) ve sistem fallback.
- **Mevcut hareket:** Ekran girişinde 40 px kayma ve opaklık; ilk 10 çocukta 35 ms aralıklı opaklık; nav kapsülü `TRANS_BACK` ile kayıyor; düğmeye basınca 0.96 ölçek ve titreşim; mühür vurma; radar 0.7 sn büyüme; CTA'da sonsuz `modulate` nabzı.

### 1.3 Sorunlar
1. **Yazı tipi gürültüsü:** Bir kartta 4 farklı yazı tipi görülebiliyor (Oswald başlık, Barlow gövde, Courier etiket, Caveat not). Hiyerarşi yazı tipi değişimiyle kuruluyor, boyut ve ağırlıkla kurulmuyor. **Special Elite'te ğ, ş, ı ve İ yok**, bu harfler sistem fontuna düşüyor (mühürlerde "GÖNDERİLDİ" ve "TAKİPTE" karışık görünüyor).
2. **Her şey kâğıt:** Kart, sayfa, sekme ve düğme aynı krem tonlarında. Vurgu (CTA) ile içerik ayrışmıyor. Birincil düğme (`primary`) siyah mürekkep, ikincil düğme krem. "Asıl yapılacak iş" gözü çekmiyor.
3. **Alt sekme geçişi yok:** `_sub_cb → _refresh_soft` tüm sayfayı yeniden kuruyor. Klasör sekmesine basınca içerik "pat" diye değişiyor. Atakan'ın istediği "animasyonlu sekme" hissinin en büyük eksiği bu.
4. **Sayılar statik:** İtibar, para, bilgi yüzdesi ve maç puanı hiç sayarak gelmiyor. Ödül anları (rapor gönderme, hafta sonucu) sessiz geçiyor.
5. **Görsel olarak en zayıf ekranlar:**
   - **Hafta sonucu (`_scr_result`):** Uzun bir kart listesi. Doruk anı yok, sayıların sayılması yok, "ne kazandım" özeti en üstte değil.
   - **Scout raporu (`_scr_report`):** Form gibi uzun ve düz. Gönderme anının bir ritüeli yok (mühür yok). Kaydırıcılar varsayılan Godot görünümünde.
   - **Ana ekran özeti:** "Sıradaki adım" ile "masadaki dosyalar" aynı görsel ağırlıkta. CTA nabzı `modulate > 1` ile yapılıyor ve ucuz görünüyor.
   - **Maç HUD'ı (`match_view.gd`):** Genel bir yayın şablonu. Scout fantezisine (not alma, odak oyuncu) bağlanmıyor.
   - **Oyuncu dosyası:** Bilgi zengin ama kartlar arasında öncelik yok. Radar ve özellik çubukları ince ve soluk.
6. **Teknik:** `glass.gd` her örnekte `hint_screen_texture` okuyor, bu da compat renderer'da ekran kopyası anlamına geliyor. `_fix_filters` her `_show`'da tüm ağacı dolaşıyor. `_animate_in` konteyner çocuklarının yalnızca `modulate` değerini anime edebiliyor, çünkü konum konteyner tarafından ezilir.

---

## 2. Seçenekler

### Seçenek A — “Gece Dosyası” (analist masası) ★ ÖNERİLEN
Bugünkü kimliğin olgun ve premium hâli: koyu deri masa üstünde krem dosyalar. Pirinç rengi yalnızca etkileşim için, kırmızı yalnızca mühür ve uyarı için, mavi mürekkep yalnızca oyuncunun kendi gözlemi için kullanılır.

| Token | Hex | Kullanım |
|---|---|---|
| desk | `#13100C` | Ekran zemini |
| leather / leather2 | `#2A1F17` / `#3A2B20` | Üst bar, nav |
| paper | `#EFE6D1` | Sayfa |
| card | `#F7F1E3` | Kart |
| manila | `#DCC391` | Klasör, oyuncu başlığı |
| ink / ink2 | `#1F1C17` / `#6A6150` | Metin |
| brass / brass-hi | `#D4A84B` / `#F0C96A` | CTA, aktif nav, odak |
| stamp red | `#C0352B` | Mühür, uyarı, rapor |
| ink blue | `#2350A0` | El notu, bilgi |
| good | `#2F7D40` | Olumlu |
| highlight | `#F3D65B` | Seçili (fosforlu kalem) |

- **Tipografi (OFL, Türkçe tam):** Barlow Condensed 700/800 (başlık ve sayı), Barlow 500/600 (gövde), IBM Plex Mono 500/600 (etiket ve form kodu; Courier Prime'ın yerine geçer), Caveat 700 (yalnızca el notları). **Oswald, Courier Prime ve Special Elite kaldırılır.** Mühürler IBM Plex Mono 600 + harf aralığı ile yazılır. Sonuç: 9 dosyadan 6 dosyaya iner.
- **Bileşenler:** Kâğıt kart (6 px köşe, sıcak gölge, üstte kulüp rengi şerit), klasör sekmesi (aktif olan 8 px yükselir ve kırmızı çizgi soldan çizilir), pirinç CTA (dikey gradyan, iç parlaklık ve 3 sn'de bir ışık süpürmesi), mühür (çift çerçeve ve mürekkep boşlukları), çizgili not kartı, gazete kupürü (yırtık kenar).
- **Hareket:** Kâğıt kayar (sekme yönünden 2° eğik giriş, eski sayfa %14 geri çekilip kararır, 380 ms ease-out). Kartlar 70 ms arayla dağıtılır. Sayılar 0'dan sayar. Mühür 2.4 kattan vurulur ve titreşim verir. Nav kapsülü yaylanır.
- **Fanteziye katkısı:** Oyuncu bir scout'un masasında oturuyor. Her eylemin fiziksel bir karşılığı var: not yazılır, dosya açılır, rapor mühürlenir. Whimsy planındaki “Tahmin tuttu” mühürü ve “Defterin haklı çıktı” anları bu dile doğrudan oturur.

### Seçenek B — “Projektör” (gece maçı analiz odası)
Stadyum ışığında bir veri odası. Kesik köşeli cam paneller, lime vurgu, camgöbeği veri rengi.

| Token | Hex | Kullanım |
|---|---|---|
| bg | `#060A09` | Zemin |
| panel | `#101A17` (%78) | Panel |
| text / text2 / text3 | `#E9F2EE` / `#8AA39A` / `#55695F` | Metin |
| lime | `#C6FF3D` | CTA, aktif öğe, mevcut seviye |
| cyan | `#3DDCFF` | Veri, bilgi |
| magenta | `#FF4D8D` | Alarm, canlı |
| amber | `#FFB547` | Potansiyel |
| green | `#36E08A` | Olumlu |

- **Tipografi (OFL, Türkçe tam):** Saira Condensed 700/800, Inter 500/700, JetBrains Mono 700. El yazısı ve daktilo yok.
- **Bileşenler:** 16 px kesik köşeli panel ve parlayan sol vurgu çizgisi, segment sekme (lime kapsül), paralelkenar CTA, 20 parçalı özellik ölçeği, bilgi halkası, “basılı tut” ile gönderme.
- **Hareket:** Tarama (lime ışık çizgisi ve içeriğin o yönden açılması, 340 ms), kapsülün iki aşamada gerilip oturması, panellerin 60 ms arayla yükselmesi, glow.
- **Fanteziye katkısı:** "Veri analisti scout" hissi verir. İlk bakışta daha çarpıcıdır, fakat el notu, mühür ve dosya gibi mevcut ritüelleri kaybeder. Tüm kitin ve popup'ların yeniden çizilmesi gerekir. Glow ve cam efekti compat renderer'da pahalıdır.

### Neden A?
1. **Risk ve efor:** `kit.gd` yardımcıları (`_card`, `_stamp`, `_polaroid`, `_tabs`) aynı kalır, değişen tema ve hareket olur. B ise 40'tan fazla ekran ve popup'ın yeniden boyanması demektir. v0.24'e sığmaz.
2. **Kimlik:** Oyunun adı ve bütün anlatı dili (dosya, mühür, defter) A ile örtüşür. Whimsy planındaki ilk 5 an, mühür ve defter üzerine kurulu.
3. **Performans:** A opak kâğıt ve StyleBox ile çalışır. B'nin cam, blur ve glow efektleri orta segment Android'de (Adreno 610 / Mali-G52) ekran kopyası ve overdraw maliyeti getirir.
4. **B'den alınacaklar:** Maç HUD'ı yayın havasında kalabilir. Buraya B'nin canlı puan, kıvılcım çizgisi (sparkline) ve olay zaman çizelgesi fikirleri A paletiyle (pirinç ve mühür kırmızısı) uygulanır. Rapor ekranındaki “adım ilerleme çubuğu” da A'ya alınabilir.

---

## 3. Godot 4.5 uygulama notları

### 3.1 Tema ve tokenlar
- Yeni `ui/theme_v24.gd` (statik sınıf) eklenir. Renk tokenları `const` olarak burada durur. `kit.gd` içindeki `C_*` sabitleri geriye uyum için bu tokenlara takma ad olur (`const C_RED := ThemeV24.STAMP` gibi). `main.gd`'ye dokunmaya gerek kalmaz.
- `_make_theme()` tek bir `Theme` üretmeye devam eder, ama **type variation** eklenir: `th.set_type_variation("BtnBrass", "Button")`, `"BtnStamp"`, `"BtnGhost"`, `"CardPaper"` (PanelContainer), `"CardMemo"`, `"LblMono"`, `"LblHand"`, `"LblDisplay"`. Böylece `_btn` içinde her seferinde `add_theme_*_override` çağrısı yerine `b.theme_type_variation = "BtnBrass"` kullanılır. Bu hem daha hızlıdır hem de tek yerden değiştirilebilir.
- İstenirse tema `res://ui/theme_v24.tres` olarak bir kez kaydedilip yüklenebilir. Ancak prosedürel kâğıt dokusu çalışma zamanında üretildiği için kod tabanlı kurulum yeterli. Önemli olan, temanın **bir kez** kurulup root `Control.theme`'e verilmesi.
- **StyleBoxFlat:**
  - Pirinç CTA: `bg_color` + `border_width_bottom = 3` (koyu pirinç, "kalınlık") + `shadow_size 6`, `shadow_offset (0,3)`. Basılı hâlde alt kenar 0 olur ve `content_margin_top` +2 (çökme hissi).
  - Klasör sekmesi: Mevcut `draw_colored_polygon` yeterli. Aktif sekmedeki kırmızı çizgi bir `float` özelliğe bağlanır ve tween'lenir.
  - Kesik köşe gerekirse `StyleBoxFlat.skew` ve `corner_detail` kullanılabilir. A'da gerekmez.
  - `anti_aliasing = true` kalır. `corner_detail` 4–5 tutulur (8 varsayılan; mobilde gereksiz köşe tepe noktası üretir).
- **Yazı tipleri:** `fonts/` klasörüne `IBMPlexMono-Medium.ttf` ve `IBMPlexMono-SemiBold.ttf` eklenir (OFL, Google Fonts). Oswald, Courier Prime ve Special Elite referansları `F_HEAD → BarlowCondensed-ExtraBold`, `F_HEADR → BarlowCondensed-SemiBold`, `F_TYPE/F_TYPEB/F_STAMP → IBM Plex Mono` olarak yeniden eşlenir. Değişken adları aynı kalır, böylece main.gd etkilenmez. İçe aktarmada `multichannel_signed_distance_field` **kapalı** kalır (compat'ta MSDF metin pahalı). Bunun yerine `oversampling` varsayılan değerde bırakılır.

### 3.2 Hareket (Tween kalıpları) — `ui/motion.gd`
Tek bir yardımcı dosya, her şey tek yerden ayarlanır ve `Game.settings.calm` (whimsy planındaki sakin mod) ile kapatılabilir.

```gdscript
# süreler: FAST 0.14, BASE 0.28, PAGE 0.38, COUNT 0.8
static func count_up(lbl: Label, to: float, fmt: Callable, dur := 0.8) -> Tween:
	var tw := lbl.create_tween()
	tw.tween_method(func(v: float): lbl.text = fmt.call(v), 0.0, to, dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw
```

- **Alt sekme geçişi (A, “dosya üstüne dosya”):** `_sheet` sayfası bir `Control` sarmalayıcı (`page_holder`, `clip_contents = true`) içine alınır. Değişimde eski `PanelContainer` silinmez, `top_level` olmadan yerinde bırakılır. Yenisi yanına eklenir, `position.x = dir * width`, `rotation = dir * deg_to_rad(2)` değerleriyle başlar. `set_parallel()` ile yeni sayfa için `position.x → 0` ve `rotation → 0` (0.38 sn, `TRANS_CUBIC/EASE_OUT`), eski sayfa için `position.x → -dir*0.14*w`, `modulate → Color(0.72,0.72,0.72)`, `scale → 0.96` uygulanır. Sonra `queue_free` çağrılır. Yön (`dir`), sekme indeksi farkından hesaplanır.
  - **Önemli:** Sarmalayıcı bir *Container olmamalıdır*. Aksi hâlde konum ve dönüş her sıralamada ezilir. Sayfanın genişliği `holder.size.x`'e elle eşitlenir (`resized` sinyali ile).
  - `_refresh_soft` bu sarmalayıcı üzerinden çalışacak şekilde refactor ekibiyle koordine edilmelidir. main.gd'ye ben dokunmuyorum.
- **Kart dağıtma:** Konteyner çocuğunun `position` değeri ezildiği için kartın **içindeki** tek çocuk anime edilir. Alternatif olarak kart `pivot_offset` ile `scale`/`rotation`'dan girer (konteyner bunları ezmez): `scale 0.97 → 1`, `rotation 1.4° → 0`, `modulate.a 0 → 1`, gecikme `0.07 * i`, en fazla 8 kart. Bu, bugünkü `_animate_in` döngüsünün genişletilmiş hâlidir.
- **Nav göstergesi:** Mevcut `nav_pill` tween'i korunur. Ek olarak aktif ikon `scale 1 → 1.08` ve `position.y -2` alır (`TRANS_BACK`, 0.3 sn).
- **Sayılar:** Üst bar pill'leri (itibar, para), bilgi yüzdesi, maç puanı ve hafta sonucu özeti `count_up` ile gelir. Değer aynıysa animasyon atlanır (yalnızca değişimde oynar, her `_refresh_topbar`'da değil). Değişen pill bir an `modulate` ile parlar.
- **Mühür:** Mevcut `_stamp_slam` korunur, `%70`'te `scale 0.94` ezilmesi eklenir (`tween.chain()`).
- **CTA ışık süpürmesi:** `modulate > 1` nabzı kaldırılır. Yerine CTA'nın içinde dar, eğik ve yarı saydam beyaz bir `ColorRect` 3 sn'de bir `position.x` ile soldan sağa geçer (CTA `clip_contents = true`). Shader gerekmez.
- **Kurallar:** Sonsuz döngülü tween ekranda en fazla 2 tane olmalı (CTA ve canlı rozet). Ekrandan çıkan düğümün tween'i düğüme bağlı oluşturulmalı (`node.create_tween()`), böylece `queue_free` ile birlikte ölür. Kök `create_tween()` sızıntı yapar. Sakin modda tüm süreler 0 olur, sayaçlar doğrudan sonuç değerini yazar.

### 3.3 Performans (orta segment Android, compat renderer)
- **Cam (`glass.gd`):** A'da kullanılmaz. Gerekirse (maç HUD'ı) blur yerine düz `StyleBoxFlat` + %85 opaklık kullanılır. `hint_screen_texture` her örnekte ekran kopyası tetikler. Kullanılacaksa ekranda tek bir `BackBufferCopy` olmalı.
- **Kâğıt dokusu:** Prosedürel doku zaten `_tex_cache`'te tutuluyor. Yeni renkler (paper/card/manila) için en fazla 4 doku olmalı, boyut ≤ 256 px, 9 parça.
- **Gölge:** `StyleBoxFlat.shadow_size` compat'ta ucuzdur, ama kartlarda 8 px'i geçmemeli. Liste satırlarında (arama sonuçları, tablolar) gölge kapatılır.
- **Yeniden kurma:** Sekme geçişinde iki sayfa aynı anda yaşar. Bu nedenle uzun listelerde (arama, tablo, haberler) yeni sayfanın yalnızca ilk ekranı kurulur, kalanı `call_deferred` ile parça parça eklenir (8–10 satır/kare).
- **Hedef:** Arayüz geçişlerinde 60 fps, 3D hub açıkken 30 fps tabanı (teknik sanat bütçesiyle uyumlu). Ek SubViewport yok.
- **Ölçüm:** `Performance.get_monitor(Performance.TIME_PROCESS)` değeri sekme geçişi sırasında Watch log'una yazılır. Kabul eşiği: tek kare < 33 ms.
- `quality == "low"` iken kart dağıtma ve ışık süpürmesi kapalıdır. Sayfa kayması 0.2 sn'ye iner.

### 3.4 Erişilebilirlik
- Kâğıt (`#F7F1E3`) üzerinde `ink #1F1C17` yaklaşık 15:1, `ink2 #6A6150` yaklaşık 5.4:1 kontrast verir; ikisi de AA'yı geçer. Pirinç üzerinde koyu metin (`#2A1F17`) yaklaşık 7:1. Deri üzerinde `cream2 #B8A888` yaklaşık 6.9:1.
- Dokunma hedefi en az 88 tuval pikseli olmalı (720 tuvalde ≈ 48 dp). Mevcut `min` 58 değerleri küçük düğmeler için 72'ye çıkarılmalı.
- Renk tek başına anlam taşımamalı: form çiplerinde harf (G/B/M) kalır, özellik çubuklarında sayı aralığı yazılır.

---

## 4. v0.24 ekran ekran yayılım sırası

| # | İş | Dosya(lar) | Efor | Not |
|---|---|---|---|---|
| 1 | Tokenlar, type variation'lar, font eşlemesi (Special Elite, Oswald ve Courier çıkar, Plex Mono gelir) | `ui/theme_v24.gd` (yeni), `ui/kit.gd`, `fonts/` | S (1 gün) | Her şeyin temeli. main.gd'ye dokunmaz. Türkçe karakter testi: “GÖNDERİLDİ, TAKİPTE, ŞIĞ”. |
| 2 | `ui/motion.gd`: count_up, deal_in, page_slide, shine. Sakin mod bayrağı | `ui/motion.gd` (yeni) | S (0.5–1 gün) | Whimsy altyapısı (`settings.calm`) ile ortak. |
| 3 | **Alt sekme geçişi + nav ikon hareketi** (Atakan'ın asıl isteği) | `kit.gd::_tabs`, `_sheet`, `_refresh_soft` sarmalayıcısı | M (1.5–2 gün) | Refactor ekibiyle koordine edilmeli. Tüm ekranlara bir anda yayılır. |
| 4 | Pirinç CTA, mühür ve düğme stilleri; CTA nabzının ışık süpürmesiyle değişmesi | `kit.gd::_btn_styles`, `_stamp` | S (1 gün) | |
| 5 | Ana ekran özeti: kulüp kartı, “Sıradaki adım” hiyerarşisi, sayaçlı üst bar, masadaki dosyalar | `_home_summary`, `_refresh_topbar` | M (1–1.5 gün) | Mockup A1. |
| 6 | Oyuncu dosyası: başlık (polaroid + mühürler vurulur), bilgi çubuğu sayacı, daha kalın radar, kritik özellikler | `_player_header`, `_player_file`, `radar.gd`, `range_bar.gd` | M (1.5 gün) | Mockup A2. Radar: çizgi 2.5→3 px, nokta 4→5, değer etiketi Barlow Condensed. |
| 7 | Scout raporu: numaralı bölümler, özel kaydırıcı (mühür mumu tutamak), etiket çemberi, tavsiye mühürleri, “Mühürle ve gönder” ritüeli | `_scr_report`, `kit.gd` HSlider teması | M (1.5 gün) | Mockup A3. Whimsy #2 “Tahmin tuttu” mührü buraya bağlanır. |
| 8 | Hafta sonucu: üstte doruk anı özeti (bilgi +%, yeni keşif, en iyi puan sayarak gelir ve “GÖZLENDİ” mührü vurulur), ardından kartlar | `_scr_result`, `_obs_card` | M (1 gün) | Mockup A4'ün alt kısmı. |
| 9 | Maç HUD'ı: A paletine geçiş (deri/pirinç skorbord), odak oyuncu canlı puan ve sparkline, “AN! Not al” kartı, zaman çizelgesi | `three/match_view.gd::_build_hud` | M (1.5 gün) | Mockup A4'ün üst kısmı. Ayrı dosya, main.gd çakışması yok. |
| — | **v0.25'e kalanlar:** Takvim, Görevler, Ekip, Dünya/tablolar, kulüp sayfası, olay popup'ları, başlık ve yeni oyun ekranları | | | 1–3 tamamlanınca bu ekranlar tema ve geçişi zaten otomatik alır. Kalan iş ince ayar. |

**Toplam v0.24:** yaklaşık 10–12 geliştirici günü. Zaman daralırsa **1–4 + 7** (temel, geçiş, düğmeler ve rapor ritüeli) tek başına “his” farkını yaratır.

### Kabul kriterleri
- Alt sekme değişiminde içerik yönlü kayar ve kare süresi 33 ms'yi aşmaz (orta segment cihaz veya `quality=medium` emülasyonu).
- Türkçe karakterler hiçbir yazı tipinde fallback'e düşmez (mühürler dahil).
- Sakin mod ve `quality=low` iken animasyonlar kapanır ya da kısalır, işlev değişmez.
- Ekran görüntüsü karşılaştırması: A1–A4 mockup'larıyla düzen ve hiyerarşi örtüşür (piksel birebir aranmaz).
