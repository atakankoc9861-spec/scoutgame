# Gözcü v0.24 — Teknik Sanat Planı (karakterler, atmosfer, mobil bütçe)

Hazırlayan: Technical Artist · Tarih: 2026-10-16 · Durum: PLAN (kod/commit yok, Godot çalıştırılmadı)
Kapsam: main @ f25ad15 (v0.23 Dalga 1 sonrası)

---

## 0. Özet (TL;DR)

1. **Karakter tabanını değiştirmeyin.** Mevcut MPFB/MakeHuman (CC0) + Quaternius UAL/UBC (CC0) + Rohr mocap hattı zaten "yarı gerçekçi" hedefe uygun ve lisansı temiz. Yeni paket aramak yerine **mevcut modelin özellik→görünüm eşlemesini düzeltmek** en ucuz ve en görünür kazanç.
2. **Fiziksel özellikler şu an zayıf yansıyor**: veride boy/kilo yok; boy pozisyon+güçten türetilip bütün modele *tek tip ölçek* olarak uygulanıyor (kafa da büyüyor, adım kayıyor); sol ayak verisi animasyona hiç bağlı değil. v0.24'te: türetilmiş boy/kilo, kafa telafisi, adım uzunluğu düzeltmesi, ayak→ayna klip, çeviklik→dönüş hızı, kondisyon→yorgunluk duruşu.
3. **Atmosfer için hazır ama kullanılmayan varlık var**: `assets/crowd/atlas.png` (8 poz × 4 kare seyirci sprite'ı, Rohr kalabalık animasyonlarından üretilmiş) hiçbir yerde kullanılmıyor. Ön sıralara tek draw call'lık MultiMesh sprite seyirci = en büyük atmosfer sıçraması.
4. **Önce ölç, sonra ekle.** Maçta tahmini ~25 oyuncu × ~7 yüzey + etiket/gölge/halka ≈ 250 draw call sadece oyunculardan; toplamın 400+ olması muhtemel. v0.21'deki boş-görünüm yangınlarından sonra her yeni görsel **bayrak arkasında, mobilde önce kapalı** gelmeli.
5. **Ready Player Me artık yok** (31 Ocak 2026'da kapandı). Mixamo hâlâ ücretsiz ama tarayıcıda elle indirme istiyor → Atakan'ın "PC'de iş yapmam" tercihine uymuyor; sadece opsiyonel.

---

## 1. Denetim (kod + varlıklar)

### 1.1 Karakter scriptleri

| Dosya | Durum | Not |
|---|---|---|
| `three/mocap_man.gd` (552 satır) | **Aktif** — maç, sahne (stage3d), hub, portre hepsi bunu kullanıyor | MPFB gövde + ayrı forma/şort/çorap/krampon/saç parçaları, 27 blend shape (16 vücut/yüz + 11 ifade), 22 kemiklik animasyon örnekleme GDScript'te elle yapılıyor (`rotation_track_interpolate`). |
| `three/human.gd` | Eski (v0.12–0.15 prosedürel loft model) | Yalnızca `tests/human_shot.gd` referans veriyor. |
| `three/footballer.gd` | Eski (kapsül/küre manken) | Yalnızca `tests/fb_shot.gd`. Silinebilir adayı (v0.24'te değil, temizlik turunda). |
| `ui/avatar.gd` | 2B prosedürel portre + büyük boyutta 3D portre isteği | 3D portre mobilde kapalı → mobilde herkes 2B çizim. |
| `autoload/Portrait.gd` | Ayrı SubViewport'ta 192px stüdyo fotoğrafı, `user://portraits` önbelleği | v0.21-b9'dan beri **mobilde varsayılan kapalı** (yeni SubViewport açılmasının boş görünümle ilişkisi şüphesi). |
| `three/post.gd` | Tek canvas_item tam ekran geçiş: renk düzenleme, vinyet, gren, yağmur/kar çizgileri | Compat-güvenli, ucuz. Düşük kalitede gren kapalı. |
| `three/stadium.gd` | Prosedürel stadyum: foto-dokulu tribün shader'ı (takım rengine boyama, heyecanla zıplama, flaşlar, doluluk), LED panolar, projektör, ışın/flare, file, bayrak, CPU konfeti, sis, ıslak/karlı çim | Işıklar: gece her direkte 1 OmniLight (tier 0'da 4, tier 2'de 6). Lamba kutuları ayrı MeshInstance'lar. |
| `three/match_view.gd` | Maç izleyici, SubViewport, `UPDATE_ALWAYS`, mobilde MSAA kapalı, ölçek 1.0, VMEM bekçisi (adım adım gölge/glow/MSAA/parçacık kapatır) | Oyuncular `lod = true` ile kuruluyor. |
| `three/stage3d.gd`, `three/hub3d.gd` | Diyalog sahneleri / ofis | **Tutarsızlık:** `stage3d.gd:64` mobilde de MSAA 2X açabiliyor (kalite "high" ise); match_view mobilde MSAA'yı kesin kapatıyor. `hub3d.gd` glow'u mobilde kapatıyor. |

### 1.2 Model: `assets/mh/player.glb` (6.4 MB, 53 kemik, 0 gömülü doku)

| Parça | Tam | `_lod` (maç) | Blend shape |
|---|---|---|---|
| Body | 17 124 tri | 4 760 tri | 27 |
| Shirt / ShirtLong | 3 484 / 4 816 | 1 061 / 1 406 | 8 |
| Shorts / Pants | 1 196 / 3 092 | 345 / 880 | 8 |
| Socks | 1 124 | 346 | 8 |
| Boots | 1 576 | **LOD yok** | 8 |
| Eyes | 280 | – | 16 |
| Saç (5 model) | 2 688 | 1 344 | 10 |

- **Maçta oyuncu başına:** ~9.7k tri, 6–7 yüzey (= 6–7 draw call) + Label3D sırt numarası + gölge quad + seçim halkası.
- **22 oyuncu + 3 hakem:** ~243k tri, ~175 karakter draw call'ı (etiket/gölge hariç).
- Sahne/hub/portre tam modeli kullanıyor: ~26k tri/kişi (yakın plan için makul).

### 1.3 Dokular (bellek)

| Doku | Boyut | İçe aktarma | VRAM tahmini | Sorun |
|---|---|---|---|---|
| `mh/skin_detail.png`, `skin_detail2.png` | 1024² RGBA | **Kayıpsız, mipmap yok** | 2 × 4 MB | Uzakta titreme (aliasing) + gereksiz bellek. v0.21-b4'teki "VRAM sıkıştırma + mipmap" turundan kaçmış. |
| `ads/atlas.png` | 1024×1792 RGB | **Kayıpsız, mipmap yok** | ~7 MB | Uzaktan görülen pano → mipmap şart. |
| `crowd/atlas.png` | 512×768 RGBA | Kayıpsız, mipmap yok | 1.5 MB | **Kullanılmıyor.** |
| `tex/grass.jpg` vb. | 1024² | VRAM sıkıştırılmış + mipmap | iyi | – |
| `tex/crowd.jpg` | 2048×512 | (kontrol edilmeli) | – | – |
| `tex/sky_day.jpg` | 2048×1024 | (kontrol edilmeli) | – | – |

Not: `assets/ads/src/` içinde `.gdignore` var (doğru), ama eski `.import` dosyaları duruyor — zararsız, temizlik adayı. `assets/ads/src/ad_house_*.png` toplam ~18 MB repo'da ama APK'ya girmiyor.

### 1.4 Animasyon hattı

- `tools/mh/bake2.gd`: Rohr (UE5 Manny iskeleti) FBX + Quaternius UAL klipleri → hedef iskelete yön hizalamalı retarget → tek `assets/mh/anims.res` (817 KB). Kalabalık pozları ayrı `crowd_anims_mh.res` → `tests/crowd_atlas.gd` ile sprite atlasına çevrilmiş.
- `tools/mh/build_player.py`: Blender 5.x + MPFB eklentisi, headless; makro varyantlarını (muscle/lean/heavy/thin/young/old/african/asian) ve yüz hedeflerini blend shape olarak, LOD'ları kopya+azaltma ile üretiyor.
- **Kritik bulgu:** Bu hattın kaynakları (`res://src/…`, `/home/claude/mh/…`, Blender + MPFB kurulumu) bu makinede **yok**. Yani `player.glb`'yi yeniden üretmek (yeni morph, yeni LOD, birleşik mesh) için önce ajan ortamında Blender + MPFB kurulumu ve CC0 kaynakların yeniden indirilmesi gerekir. Rohr FBX'leri Atakan'ın Fab hesabından gelir → **animasyonları yeniden pişirmek v0.24'te kapsam dışı**; `anims.res` olduğu gibi kalmalı.
- Çalışma zamanı: her oyuncu her karede 22 kemik × (loco 2 klip + aksiyon + overlay) GDScript interpolasyonu → 25 oyuncuda ~1.5–2k çağrı/kare. Orta segment Android'de CPU tarafı için belirgin maliyet (ölçülmeli).

### 1.5 Render ayarları (mobil)

- `gl_compatibility` hem masaüstü hem mobil; ETC2/ASTC aktif.
- Compat renderer gerçekleri (Godot 4.5 dokümanı): mesh başına en fazla 8 Omni + 8 Spot; **gölgeli ışıklar çok geçişli (multi-pass)**; Glow ve MSAA 3D destekli; FXAA/TAA/FSR yok; SSAO/SSR yok; hacimsel sis yok; derinlik/yükseklik sisi var.
- v0.21 kısıtları (git geçmişi): `24ed515` maçta buzlu cam paneller kaldırıldı (Adreno doku sızıntısı + siyah ekran), mobil maç MSAA kapalı · `9cd31cd` arka planda render hedefleri donduruluyor · `6a87b54` VRAM sıkıştırma + mipmap · `62c7029` cihazda boş görünüm teşhisi · `2949e13` mobilde portre kapalı, maç/sahne öncesi taze görünüm öz-testi · `865cda0` mobilde 3D ölçek tamponu ve glow yok · `d693b4c` ıslak çimde projektör yansıması kapatıldı.
- **Çıkarım:** Sorunlar Adreno sürücüsünde *SubViewport yaşam döngüsü + ara tamponlar* etrafında yoğunlaşıyor. Yeni görsel özellikler **yeni SubViewport, yeni render hedefi, ekran-alanı efekti eklememeli**; mevcut dünyaya geometri/shader olarak girmeli.

---

## 2. Değerlendirme

### 2.1 Fiziksel özellik → görünüm (şu an)

`mocap_man.gd: look_for()`:

| Veri | Görsel | Değerlendirme |
|---|---|---|
| strength | `muscle`, `lean`, `heavy` morph + boy +%0.4/puan | İyi temel; maç LOD'unda siluet farkı küçük (omuz genişliği morph'u yok). |
| pace | `thin` morph | Zayıf ilişki; hız asıl olarak motorun `vmax`'ı ile görünüyor (iyi). |
| age | `young`/`old` morph, gençte sakal azaltma | İyi. Yaşlıda saç çizgisi/beyazlama yok. |
| pos | GK/CB +%3.5 boy, kanat/AM −%2.5 | Makul ama **veride gerçek boy yok**; aynı pozisyondaki herkes ±%4 aralığında. |
| skin / nat | Ten rengi + `african`/`asian` morph | İyi. |
| seed | Yüz morph'ları, saç, sakal | İyi. |
| **foot (L/R)** | **Hiç kullanılmıyor** — pas/şut ayna klibi `mirror_seed % n` ile rastgele | Düzeltilmesi en ucuz ve en "scout gözüyle" anlamlı detay. |
| agility, stamina | Görselde yok | Dönüş hızı ve geç dakika yorgunluğu ile gösterilebilir. |

**Teknik sorunlar:**
- Boy, `_inst.scale` ile **tek tip ölçek** → uzun oyuncu = büyütülmüş kopya (kafa, el, ayak da büyüyor). Gerçekte boy farkı ağırlıklı bacak + gövdeden gelir.
- Ölçek yürüyüş döngü süresine yansımıyor (`tick()` içindeki `cyc`) → uzun oyuncuda ayak kayması, kısa oyuncuda "patinaj".
- Sırt numarası Label3D ölçeğe göre büyüyor (küçük kusur).

### 2.2 Animasyon/retarget
Sağlam ve oyun içi kaliteli. Risk: kaynak dosyalar repoda değil, yeniden üretilemez. v0.24 bu dosyalara **dokunmadan** ilerlemeli. UAL2 (CC0, Haziran 2026) aynı iskelet ailesinden; ileride ofis/kenar çizgisi davranışları (ısınma, bekleme, emote) için iyi kaynak.

### 2.3 Performans riskleri (öncelik sırasıyla)
1. **Draw call** (Compat'ta 3D toplu çizim yok): oyuncu parçaları ~175 + etiket 22 + gölge 25 + halka 22 + stadyumda tek tek lamba kutuları (tier 0: ~48 kutu + 4 kafa + 4 direk) + panolar + bayraklar. Toplam büyük ihtimalle 400+.
2. **Gölgeli ışık**: Compat'ta çok geçiş. Maçta gölge mobilde zaten kapalıya yakın; sahne/hub'da `quality=="high"` ise spot gölgeleri açık → mobil "high" kullanıcıları için risk.
3. **CPU animasyon örnekleme** (GDScript) — 25 karakter her kare.
4. **Doku belleği**: kayıpsız/mipmap'siz 3 doku ~15 MB ve titreme.
5. **Blend shape'li 25 örnek**: her örnek kendi deforme tamponunu taşır; sabit ağırlıklar için gereksiz. (Ölçmeden karar verilmemeli.)

---

## 3. v0.24 Yol Haritası

### 3.1 Karakter yaklaşımı — seçenekler ve lisans

| Seçenek | Lisans (doğrulandı, Ekim 2026) | Uygunluk | Karar |
|---|---|---|---|
| **MPFB / MakeHuman** (mevcut) | Taban mesh, hedefler, deriler **CC0**; eklenti kodu GPL ama çıktıya geçmez; kapalı kaynak oyunda kullanılabilir | Yarı gerçekçi, morph tabanlı vücut tipleri → "özelliklerin görünmesi" için ideal | **Devam (ana yol)** |
| **Quaternius Universal Base Characters** | **CC0**; "fiyatını sen belirle"; Standard'da 2 taban model + 5 saç ücretsiz; Source (≥19.99 $) 20 saç + rig'li .blend + Godot projesi; ~13k tri; son güncelleme 16 Eyl 2026 | Saç/aksesuar kaynağı olarak zaten hatta (`bake2.gd` `src/ubc/` saçlarını okuyor). Source paketi daha fazla saç çeşidi demek. | **Opsiyonel satın alma (~20 $), PC işi yok** — ajanlar indirip işler |
| **Quaternius Universal Animation Library 2** | **CC0**; 42 klip ücretsiz, 110+ Source (≥14.99 $); v2.0 16 Haz 2026 | Futbol klibi yok; davranış/emote/bekleme için iyi, aynı iskelet ailesi | v0.25+ sahne/hub canlılığı için aday |
| **Anderson Rohr mocap** (mevcut) | Fab/Unreal Marketplace satıcı içeriği: Epic yapımı olmayan ürünler, aksi belirtilmedikçe başka motorlarda kullanılabilir; ham dosya dağıtılamaz | Futbol aksiyonlarının ana kaynağı | Değişmiyor. **Repo özel kalmalı**; açık kaynağa çıkarılırsa `anims.res` ve `crowd/atlas.png` çıkarılmalı. |
| **Mixamo** | Ücretsiz Adobe ID ile; ticari oyunda telifsiz; ham dosya yeniden dağıtılamaz; 2026'da durum değişikliği raporu yok | Ek futbol klipleri var ama her klip tarayıcıda elle seçilip indirilmeli | **Önerilmez** (Atakan'ın elle iş yapmama tercihi). Gerekirse tek seferlik, net klip listesiyle. |
| **Ready Player Me** | **31 Ocak 2026'da kapandı** (Netflix teknolojiyi aldı); API/SDK çalışmıyor | – | **Seçenek değil** |
| **Kenney Animated Characters / KayKit / Polygonal Mind 100 Avatars** | CC0 | Bloklu/stilize; yarı gerçekçi hedefle uyumsuz | Kullanma (ancak çok uzak LOD/figüran için bile stil kırılır) |

**Sonuç:** Yeni karakter tabanı yok. Para harcanacaksa tek mantıklı kalem UBC Source (~20 $) → daha fazla saç çeşidi.

### 3.2 Görünür özellikler — nasıl sürülecek

**A. Türetilmiş fiziksel veri (kayıt göçü yok):**
`Game.phys(p)` → `{h_cm, kg}` tohum + pozisyon + güç + yaştan deterministik türetilir, kayda yazılmaz (eski kayıtlar bozulmaz). Örnek dağılım: GK 186±5, CB 186±4, ST 182±6, CM 178±5, kanat/AM 174±5; güç ±, 18 yaş altı −2..−6 cm. Profilde "Boy 1.87 m" gösterilebilir (oyun tasarımcısıyla netleşmeli; scout oyununda bu bilgi değerli).

**B. Boy → iskelet (yeniden model üretmeden):**
- `_inst.scale = h_cm / 180` (0.92–1.10 aralığı).
- **Kafa telafisi:** `head` kemiğine `set_bone_pose_scale(1/s^0.6)` — uzun oyuncunun kafası orantısız büyümesin. Animasyon yalnızca dönüş + pelvis konumu yazdığı için kemik ölçeği kalıcı kalır (`_apply` ölçek yazmıyor).
- **Adım düzeltmesi:** `tick()` içinde `cyc *= s` → uzun oyuncu aynı hızda daha az adım atar; ayak kayması biter.
- Sırt numarası Label3D'ye `1/s` ölçek.

**C. Yapı → morph (mevcut 8 vücut morph'u):**
Kilo (kg) ve boydan BMI benzeri bir "yapı" değeri; güçle birlikte `muscle/heavy/thin/lean` ağırlıkları. Maç uzaklığında siluet farkı için ağırlıkları **daha cesur** kullan (şu an çoğu 0–0.6). Test: 5 profil yan yana ekran görüntüsü (bkz. §3.6).

**D. Hareket karakteri (tamamen GDScript, model gerektirmez):**
- `foot == "L"` → `kick/shot` için `_m` (ayna) klibi seçilsin (`mirror_seed` yerine).
- `agility` → maçta `rotation.y` lerp hızı (çevik oyuncu daha keskin döner).
- `pace` → sprint/jog karışım eşiği hafif kayar (hızlı oyuncu daha erken "sprint" duruşuna geçer).
- `stamina` → 70'+ sonra düşük kondisyonlu oyuncuda ölü topta "eller dizde/kalçada" overlay'i (mevcut `overlay` mekanizması; uygun klip yoksa `crouch`/`idle` karışımı) ve hafif öne eğilme.
- Yaş: 31+ için saçta `hair_col.lerp(gri, 0.15–0.4)` (yalnız materyal parametresi; önbellek anahtarına girer).

**E. Yeniden model gerektirenler (Faz 5, ancak Blender+MPFB ajan ortamına kurulursa):**
- Yeni morph'lar: `shoulders_broad` (torso/torso-scale-horiz), `neck_thick`, `legs_long` — MPFB hedefleri mevcut, `build_player.py` VARS sözlüğüne ekleme.
- `Boots_lod`, kaleci eldiveni parçası.
- **Maç için tek yüzeyli birleşik LOD** (gövde+forma+şort+çorap+krampon tek mesh, bölge kimliği COLOR'da, tek "uber" shader) → oyuncu başına 6–7 draw call'dan 1–2'ye.

### 3.3 Kalabalık ve stadyum atmosferi

Öncelik sırası (maliyet/etki):

1. **Ön sıra sprite seyirci (MultiMesh)** — `assets/crowd/atlas.png` zaten hazır.
   - Her tribün için **1 MultiMeshInstance3D** (= 1 draw call), quad billboard (Y ekseni), `alpha_scissor` (alfa harmanlama değil → sıralama/overdraw yok), unshaded.
   - Kare/poz seçimi `INSTANCE_CUSTOM` + `TIME` ile shader'da; takım rengi atkı/forma tonlaması mevcut `recolor` mantığıyla.
   - Yalnız TV kamerasına bakan uzun kenar + ilk 3–5 sıra. Arka sıralar mevcut foto-shader'da kalır.
   - Adet: high 1500 / medium 800 / low 0. `excite` uniform'u ile gol anında poz değişimi (sarı-kırmızı flaşlar zaten var).
   - Atlas: mipmap aç, VRAM sıkıştır.
2. **Tifo/koreografi (shader)** — derbi/final/büyük maç girişinde tribün shader'ında UV bloklarıyla kulüp renklerinde desen/şerit; ek geometri yok, maliyet ~0.
3. **Bayrak/atkı dalgası** — mevcut `FLAG_SHADER`'ı tribün kenarlarında birkaç büyük pankarta genişlet (az sayıda quad).
4. **Hava** (zaten var: post-shader yağmur/kar, ıslak/karlı çim, sis):
   - Gece yağmurda projektör ışınlarında yağmur çizgisi yoğunlaşması (beam shader'ına `rain` uniform'u).
   - Topun ıslak zeminde küçük sıçrama halkası (tek quad, tween) — CPU parçacık yok.
   - Karda top turuncu zaten var; çim çizgilerinde kar birikimi var. Ek gerek yok.
5. **Projektör kafaları**: lamba kutularını direk başına tek mesh'e birleştir (SurfaceTool ile, çalışma zamanında bir kez) → tier 0'da ~48 draw call kazanç. Görsel değişiklik yok.
6. **Ses** (audio-designer ile): tezahürat katmanları zaten `Sfx.crowd_level`; sprite seyirci heyecanı ile aynı `excite` sinyaline bağlanmalı.

**Yapılmayacaklar:** GPU parçacıkları (Adreno riski), hacimsel sis (Compat'ta yok), ekran-alanı efektleri, yeni SubViewport, gerçek zamanlı gölgeli ek ışık.

### 3.4 Portreler (mobilde kapalı olan 3D vesikalık)

Çalışma zamanı SubViewport yerine **ön-pişirilmiş "yüz kiti" atlası**: geliştirme sırasında (ajan, headless değil — GPU'lu ortam gerekir; yoksa masaüstü test turunda) ten 5 × saç 6 × yüz tipi ~6 = 180 baş, 128 px, şeffaf zemin, tek atlas (~2048², ASTC). Çalışma zamanında `avatar.gd` atlas hücresini çizer, forma rengini 2B olarak ekler. Sonuç: mobilde de 3D görünümlü portre, **sıfır yeni render hedefi**. Mevcut `Portrait.gd` masaüstünde aynen kalır.

### 3.5 Mobil performans bütçesi (orta segment Android)

Referans: Adreno 610/618 veya Mali-G52/G57, 4 GB RAM, 1080p ekran, hedef **30 fps sabit** (33 ms; GPU ≤ 22 ms, CPU ana iş parçacığı ≤ 20 ms).

| Kalem | Maç (mobil) bütçe | Mevcut tahmin | Not |
|---|---|---|---|
| Toplam draw call | **≤ 300** | 400+ (ölçülecek) | Compat'ta 3D toplu çizim yok |
| Karakter draw call | ≤ 120 | ~175 (+69 etiket/gölge/halka) | Faz 5 birleşik LOD ile ~50 |
| Seyirci sprite | 1–4 (tribün başına 1) | 0 | MultiMesh |
| Görünür üçgen | **≤ 350k** | ~243k oyuncu + stadyum | Sprite seyirci: 1500 × 2 tri = 3k |
| Doku VRAM (3D) | **≤ 96 MB** | ölçülecek; ~15 MB kayıpsız israf | Hepsi ETC2/ASTC + mipmap |
| Dinamik ışık | 1 directional (gölgesiz) + ≤ 6 omni (gölgesiz, specular 0) | gece 4–6 omni | Gölgeli ışık mobilde yok |
| Parçacık | CPU, ≤ 200 aktif, yalnız gol anı | konfeti 2 × 90 | Değişmiyor |
| Şeffaf/additive overdraw | ≤ 3 katman | flare + ışın + post | Işınlar mobil "medium"da kapalı kalsın |
| Animasyon CPU | ≤ 3 ms / kare | ölçülecek | Uzak oyuncular 15 Hz güncelleme |
| Ek SubViewport | **0 yeni** | – | v0.21 dersi |

### 3.6 Fazlar — stabilite önce

Her faz ayrı beta; her özellik `Game.settings` bayrağıyla, `safe3d == true` ise otomatik kapalı.

**Faz 0 — Ölçüm (beta1, görsel değişiklik yok)**
- `Watch` teşhis satırına maç sırasında her 10 sn: `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, `RENDER_TEXTURE_MEM_USED`, `TIME_PROCESS`, fps.
- Ayarlarda gizli "perf göster" anahtarı → Atakan sadece telefonda açıp ekran görüntüsü atar (PC yok).
- Başlangıç değerleri `tests/baseline/` yanına `render_baseline.json` olarak kaydedilir.

**Faz 1 — Görselsiz kazanımlar (beta1)**
- `skin_detail*.png`, `ads/atlas.png`, `crowd/atlas.png`: VRAM sıkıştırma + mipmap.
- Projektör lamba kutularını direk başına birleştir.
- Uzak oyuncular için animasyon güncelleme seyreltme (kameradan > 35 m → 2 karede 1).
- `stage3d.gd` MSAA'yı mobilde match_view ile aynı kurala çek.

**Faz 2 — Görünür özellikler (beta2)**
- §3.2 A–D: `Game.phys`, boy ölçek + kafa telafisi + adım düzeltmesi, ayak→ayna klip, çeviklik dönüşü, yorgunluk duruşu, yaşa göre kır saç, daha cesur morph eşlemesi.
- Bayrak: `traits3d` (varsayılan açık; yalnız GDScript + mevcut morph'lar).

**Faz 3 — Atmosfer (beta3)**
- Sprite seyirci MultiMesh (bayrak `crowd_sprites`: masaüstü açık, **mobil beta3'te kapalı → telemetri temizse beta4'te açık**), tifo shader'ı, yağmurda ışın yoğunluğu, ıslak sıçrama halkası.

**Faz 4 — Mobil portre kiti (beta4)**
- Atlas üretimi (GPU'lu ortam), `avatar.gd` atlas yolu; mobilde 3D SubViewport portresi kapalı kalır.

**Faz 5 — Model yeniden üretimi (yalnız ön koşul sağlanırsa; v0.24 için opsiyonel, aksi halde v0.25)**
- Ön koşul: ajan ortamında Blender 5.x + MPFB kurulumu, CC0 kaynakların yeniden indirilip `tools/mh/README` ile belgelenmesi.
- Yeni morph'lar, `Boots_lod`, eldiven, maç için birleşik tek yüzey LOD.

### 3.7 Test planı

**Otomatik (headless, `tools/dev/run_tests.sh` kapısı):**
- `tests/check/char_traits_check` (yeni): 50 rastgele oyuncu için `Game.phys` aralıkları; `look_for` ağırlıkları [0,1]; ölçek [0.92,1.10]; sol ayaklı oyuncuda `play("kick")` → `_m` klibi; tohum aynıyken sonuç deterministik.
- `tests/check/render_budget_check` (yeni, sayım tabanlı — headless'ta GPU sayacı yok): maç dünyasını kur, görünür `MeshInstance3D` yüzey sayısı + `MultiMeshInstance3D` sayısı + Label3D sayısını say → bütçe tablosuna göre "vekil draw call" ≤ 300; kayıpsız/mipmap'siz 3D doku import'u yok (`.import` dosyalarını tara).
- Mevcutlar korunur: `career_check`, `season_check`, `tests/baseline/*` (maç istatistikleri görsel değişiklikten etkilenmemeli).

**Yarı otomatik (GPU'lu masaüstü, ajan):**
- `tests/mocap_t`, `tests/face_t`, `tests/portrait_t`, `tests/stad_t`, `tests/goal_shots`, `tests/view_shots`, `tests/mid_shots` → önce/sonra ekran görüntüsü.
- Yeni `tests/traits_t`: 5 profil yan yana (kısa-çevik kanat, uzun stoper, kilolu forvet, 17 yaş, 34 yaş) tam model + maç LOD'u.
- `tests/vmem_t`, `tests/mem_t`, `tests/leak_t`: 3 maç art arda doku belleği artışı < 50 MB.
- `tests/selftest_t`, `tests/close_t`, `tests/bg_t`, `tests/diag_t`: v0.21 boş görünüm senaryoları regresyonu.

**Cihazda (Atakan, sadece APK kur + ekran görüntüsü):**
- En az 2 cihaz (Atakan'ın telefonu + bir alt-orta Adreno).
- Senaryo: Ofis → maç (gece, yağmur) → ofis → diyalog sahnesi → maç (gündüz) → arka plana al/geri dön; 5 tekrar.
- Kontrol: boş/siyah görünüm yok, `OZTEST` satırları OK, perf satırı bütçede, 30 fps altına düşüş < %5 süre.
- Her beta sonunda teşhis kaydı (mevcut `Watch` kaydı) paylaşılır.

### 3.8 Geri dönüş

Her yeni görsel bayrak arkasında; `Watch.check_vp` boş görünüm yakalarsa mevcut fallback'e ek olarak `crowd_sprites` ve `traits3d` kapatılsın. Faz 5 mesh değişikliği eski `player.glb`'yi `player_v23.glb` olarak tutarak tek satırla geri alınabilir olmalı.

---

## 4. Riskler

| Risk | Olasılık | Etki | Önlem |
|---|---|---|---|
| Yeni geometri/shader Adreno'da boş görünüm tetikler | Orta | Yüksek | Yeni SubViewport yok; bayrak + mobilde gecikmeli açma; öz-test |
| Karakter kaynak hattı yeniden kurulamaz (Blender/MPFB/src yok) | Yüksek | Orta | v0.24'ün Faz 0–4'ü mevcut `player.glb` ile yapılabilir; Faz 5 opsiyonel |
| Rohr kaynakları gerekirse Atakan'ın Fab'dan indirmesi gerekir | Düşük (v0.24'te gerek yok) | Orta | Animasyonlara dokunma |
| Kemik ölçeği + ayna klip birleşiminde ayak/zemin teması bozulur | Orta | Düşük | `traits_t` görüntü testi, ölçek aralığını dar tut |
| Sprite seyirci yakın planda "karton" görünür | Orta | Düşük | Sadece TV kamerasına uzak mesafede; yakın kamera açılarında görünürlük aralığı (`visibility_range`) ile gizle |
| Repo açık kaynağa çıkarsa Rohr türevleri dağıtılmış olur | Düşük | Yüksek (lisans) | README'ye uyarı; özel repo |

---

## 5. Kaynaklar

- Quaternius Universal Base Characters (CC0, ~13k tri, Godot projesi): https://quaternius.itch.io/universal-base-characters
- Quaternius Universal Animation Library 2 (CC0, v2.0 Haz 2026): https://quaternius.itch.io/universal-animation-library-2
- Quaternius UAL (v1): https://quaternius.com/packs/universalanimationlibrary.html
- MPFB kapalı kaynak oyunda kullanım / CC0 varlıklar: https://static.makehumancommunity.org/mpfb/faq/use_in_closed_source.html
- Ready Player Me kapanışı (31 Ocak 2026): https://genies.com/blog/ready-player-me-shutdown
- Mixamo ve alternatifleri (2026): https://app.cinevva.com/guides/free-character-animations-rigging
- Ücretsiz rig'li karakterler (Kenney, KayKit, 100 Avatars lisansları): https://app.cinevva.com/guides/free-rigged-3d-character-models
- Mixamo SSS (Adobe topluluk): https://community.adobe.com/t5/mixamo-discussions/mixamo-faq-licensing-royalties-ownership-eula-and-tos/m-p/13234775
- Marketplace varlıklarının başka motorda kullanımı: https://gamefromscratch.com/using-asset-store-assets-in-other-engines-is-it-legal/
- Godot 4.5 renderer karşılaştırması (Compat: 8 omni/mesh, glow, MSAA 3D, FXAA yok): https://docs.godotengine.org/en/4.5/tutorials/rendering/renderers.html
- Godot ışık ve gölgeler (Compat'ta gölgeler çok geçişli): https://docs.godotengine.org/en/4.5/tutorials/3d/lights_and_shadows.html
