# Görev Tanımı — Gözcü v0.23 (sağlamlaştırma) — ONAYLANDI (Atakan, 15 Ekim 2026)

Kararlar (müdür varsayılanları onaylandı):
1. v0.23 sadece sağlamlaştırma, yeni özellik yok.
2. v4 ve v5 kayıtlar korunur; v3 ve öncesi için mevcut "eski kayıt" notu kalır.
3. Karma model: oyuncunun ligi, U19 ve shortlist'teki oyuncuların maçları hızlı motorla; kalanlar motora kalibre Poisson. Hafta süresi bütçesi: Dalga 1-D'de ölçülen sürenin en fazla 2 katı.

Temel: 0.22-b4 (code 43), tek dal main.

Genel kurallar:
- Her dalga, önceki dalga birleştikten sonra güncel main'den dal açar.
- Bir dalgada aynı dosyaya iki ajan dokunmaz.
- v0.23 boyunca kimse dokunmaz: autoload/T.gd (yeni çeviri anahtarı yok), project.godot, scenes/main.tscn, three/*, assets/*, audio/*, .claude/*.
- export_presets.cfg sadece Dalga 4'te değişir.
- Test kuralı (Dalga 1'de kurulur): testler tests/check/*_check.gd (+ .tscn gerekirse) olarak adlandırılır, başarıda quit(0), hatada quit(1). Runner (tools/dev/run_tests.sh) bu dosyaları kendisi bulur; sonraki dalgalar runner'a dokunmadan test ekler. Testler APK'ya girmez (exclude_filter="tests/*, tools/*").

Ortam notları (tüm ajanlar):
- Godot 4.5.1 headless: /home/claude/godot/Godot_v4.5.1-stable_linux.x86_64 (kullan: <bin> --headless --path <repo> <sahne.tscn>). Proje import edilmiş durumda ama her worktree'de bir kez `--headless --path . --import` gerekebilir.
- Dikkat: tests/quick.tscn headless olarak 300 sn içinde bitmedi (çıktı yok, timeout). Yeni dünya üretimi ağır olabilir, autoload/Watch.gd (donma bekçisi) headless'ta engel olabilir veya print'ler tamponlanıyor olabilir — test yazan/ölçen ajan bunu teşhis etmeli, uzun timeout ve gerekirse küçültülmüş senaryo kullanmalı.

## Dalga 1 — Zemin (4 iş paralel)

A. Test kapısı — godot-gameplay-scripter — branch v023/test-kapisi
- Dokunur: tests/check/ (yeni), tools/dev/run_tests.sh (yeni)
- Dokunmaz: autoload/*, ui/*, sim/*, data/*, tests/baseline/, mevcut tests/*.gd
- İş: quick.gd, season_t.gd, v22_t.gd senaryoları assert'li testlere dönüşür: sezon tamamlanıyor mu; para ve itibarda NaN/eksi var mı; kaydet → yükle → kaydet sonrası durum aynı mı. Testler belirli oyuncu isimlerine bakmaz (B isimleri değiştiriyor).

B. Gerçek isim temizliği — gozcu-dunya-veritabani — branch v023/isim-temizligi
- Dokunur: tools/world/names.py, tools/world/gen_world.py, data/world.json, autoload/Data.gd (sadece isim listeleri ve name_pair()), tools/world/blacklist.txt (yeni)
- Dokunmaz: autoload/Game.gd, ui/*, tests/*
- Sorunlar: names.py'de gerçek soyadlar (Hamšík, Škriniar, Lobotka, Brozović, Lewandowski, Finnbogason...); Data.gd TR listeleri birleşince gerçek isimler ("Arda"+"Güler", "Kenan"+"Yıldız").
- İş: soyadları temizle; name_pair()'e ad+soyad kara liste kontrolü; world.json aynı seed ile yeniden üret, sadece isimler değişsin.

C. addkeys.py yol düzeltmesi — engineering-minimal-change-engineer — branch v023/addkeys-yol
- Dokunur: sadece tools/dev/addkeys.py. Yol sabit /home/claude/scout; script'in kendi konumuna göre hesaplansın.

D. Ölçüm temeli — gozcu-playtest-analisti (+ gozcu-scout-gercekcilik okuyucu, dosya yazmaz) — branch v023/olcum-temeli
- Dokunur: sadece tests/baseline/ (yeni)
- İş: ai_stats.gd ile 200 canlı motor maçı (gol/maç, ev sahibi galibiyet %, 0-0 oranı); season_t.gd ile Poisson tarafı; quick.gd ile hafta süresi (ms). Scout-gerçekçilik ajanı hedef aralıkları yazılı verir.

Birleştirme: C → B → A → D (D, B birleştikten sonra ölçümü bir kez tekrar çalıştırıp birleşir).

Dalga 1 kapısı (Reality Checker):
1. main üzerinde run_tests.sh 0 ile çıkıyor.
2. Bilerek bozulan kopyada (ör. para = NaN) aynı runner 1 ile çıkıyor; iki çıktı kaydı gösteriliyor.
3. Kara liste taraması sıfır eşleşme: world.json + 3 yeni oyun (TR, EN, bir başka başlangıç ülkesi) içindeki tüm oyuncular.
4. addkeys.py geçici kopyada çalışıyor, T.gd TR/EN 1170/1170 eşitliği bozulmuyor.
5. tests/baseline/ içinde sayılar ve hedef aralıklar mevcut.

## Dalga 2 — Ağır işler (sonra)
E. Kayıt göçü (godot-gameplay-scripter, Game.gd load_game/_fix_ints/_migrate_*), F. Hızlı motor (gozcu-mac-motoru, sim/), G. main.gd bölme 1. adım (minimal-change, ui/main.gd + ui/screens/). Birleştirme E → G → F.
## Dalga 3 — Hızlı motoru oyuna bağlama (gozcu-mac-motoru, Game.gd sim_match/play_day)
## Dalga 4 — Sürüm 0.23 code 44 + 3 sezon bot playtest + cihaz kapısı

---
# EK — Dalga 2 başlangıcı (16 Ekim 2026, Atakan onayladı)

Durum: Dalga 1 main'de (61a2331). Test kapısı: `GODOT=/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64 bash tools/dev/run_tests.sh` (career_check ~35 sn, season_check ~15 sn). Ölçüm temeli: tests/baseline/BASELINE.md + baseline.json (3 seed, base 9325199).

Ölçüm sonucu (Durum A): Gerçek açıklar seed'den bağımsız: canlı motorda 4+ farklı maç %14 (hedef ≤%6); Poisson'da ev sahibi galibiyet %53 / deplasman %24, ev/dep gol oranı ~1.78 (hedef ~1.25, sebep `sh += 2.0` ve 1.3/1.05); top-5'te beraberlik %20 (hedef 22-29). Canlı motorda ev sahibi %50.7±2.8 → kanıtlanmış sorun değil.
Hafta bütçesi: izlenmeyen hafta medyan ≤563 ms, en kötü ≤1004 ms (~%75'i save_game ~212 ms).

Atakan kararları (Dalga 3):
1. U19 hızlı motora GİRMEZ (izlenmeyen U19 maçları zaten simüle edilmiyor; genç istatistikleri v0.24).
2. Haftada en fazla 12 shortlist maçı hızlı motora.
3. Kalibrasyon hedefi GERÇEK FUTBOL (BASELINE §3), bugünkü motorun hissi değil.

## Dalga 2 görevleri (paralel; aynı dosyaya iki ajan dokunmaz)

E. Kayıt göçü — godot-gameplay-scripter — branch v023/kayit-gocu
- Dokunur: autoload/Game.gd (sadece load_game(), _fix_ints(), yeni _migrate_* fonksiyonları, ve EK işler için gereken en küçük değişiklikler aşağıda), tests/check/save_* , tests/fixtures/ (yeni)
- Dokunmaz: ui/*, sim/*, Game.gd'de sim_match/finish_live/play_day/finish_week (Dalga 3'ün alanı), data/*, T.gd
- İş: SAVE_VERSION eşitliği yerine sürüm sürüm göç zinciri; v4 ve v5 örnek kayıtları eski commit'lerden üretilip test edilir (SAVE_VERSION := 5, v0.19 b6fe736'dan beri). v3 ve öncesi: mevcut "eski kayıt" notu kalır.
- EK işler:
  (a) s.sim_seed alanı: new_game'de üretilsin; göç zincirinde yoksa has() ile üretilsin (Dalga 3 deterministik maç seed'i için).
  (b) load_game() içindeki fill_squad() ilk yüklemede kaydı değiştiriyor (kadrosu asgarinin altına düşen kulüplere oyuncu ekliyor) → kök sebebi bul: ya kayıttan önce kadro tamamlansın ya da onarım göç/kayıt aşamasında bir kez yapılsın; sonuç: kaydet→yükle→kaydet ilk turda da birebir aynı (CHECK_STRICT_SAVE=1 ile yeşil).
  (c) NaN koruması: para/itibar/bütçe NaN veya inf olursa kayıt bozulmasın (kaydetmeden önce tespit + güvenli değere çek + log), yükleme bozuk kaydı reddetmek yerine onarsın.
  (d) İtibarın otomatik oynanan sezonda 0'a düşüp scout'un kovulması: SADECE teşhis et ve raporla (denge değişikliği v0.24, kod değiştirme).
- Kapı: v4 ve v5 örnek kayıtları açılıyor; para/itibar/hafta/oyuncu sayısı yükleme öncesi=sonrası; 1 hafta hatasız ilerliyor; CHECK_STRICT_SAVE=1 yeşil; NaN testleri yeşil.

F. Hızlı motor — gozcu-mac-motoru — branch v023/hizli-motor
- Dokunur: sim/live_engine.gd, sim/quick_engine.gd (yeni), tests/check/engine_* 
- Dokunmaz: autoload/Game.gd (bağlama Dalga 3'te), ui/*, three/*
- Hedef GERÇEK FUTBOL aralıkları (BASELINE §3), "baseline ±%10" değil: gol/maç 2.5–3.1; ev sahibi galibiyet %41–48; beraberlik %22–29; 4+ fark ≤%6; ev/dep gol oranı 1.15–1.35. Canlı motorda (izlenen maçlar) 4+ fark açığı da düzeltilsin; canlı motor davranışı izlenen maçta korunur ama dağılımı hedefe çekilir. Canlı motordaki ev sahibi +0.55 bonusu F'nin sorumluluğunda (hedefe göre ayarla).
- Arayüz (Müdür, Dalga 3 için ZORUNLU):
  # sim/quick_engine.gd (RefCounted)
  static func simulate(g, m: Dictionary, youth: bool, seed_v: int) -> Dictionary
  - Saf: m, g.s ve g.rng'ye dokunmaz. m.xi_h ve m.xi_a önceden dolu gelir; motor ilk 11 seçmez.
  - Deterministik: aynı seed_v + aynı m + aynı oyuncular → bit bit aynı sonuç; çağrı sırasından bağımsız.
  - Dönüş: {gh:int, ga:int, ev:[{t:"g", pid, as, side:"h"|"a", min:int 1..90}] (goal_events() ile aynı), rt:{pid: float 0.1 adım} (live ratings(false) ile aynı ölçek), cards:{pid:{yc,rc}} (kaydedilmez), team:{h:{sh,sot,fouls,corners,poss}, a:{...}} (sadece kalibrasyon/test)}
  - Hız: maç başına medyan ≤3 ms, en kötü ≤10 ms.
  - Tercih: LiveEngine'in karar kodunu paylaşan "animasyonsuz büyük adım" modu (izlenen/izlenmeyen ayrışmasın).
  - LiveEngine.setup(seed_v): seed_v=0 → rastgele seed davranışı korunur; izlenen maç akışı bozulmaz.
- Kapı: ≥5 seed × 2000 maç (hızlı) ve ≥3 seed × 300 maç (canlı) ile dağılım hedefleri (birleşik %95 aralığa göre); aynı seed aynı skor; hız hedefi; testler yeşil.

G. main.gd bölme 1. adım — engineering-minimal-change-engineer — branch v023/main-bolme
- Dokunur: ui/main.gd, ui/screens/ (yeni)
- Dokunmaz: autoload/*, T.gd, scenes/main.tscn
- Not: Dalga 1'de main.gd'ye gazeteci adı için 4 satır eklendi (~4146); korunmalı.
- İş: Dükkân (_shop, _rewarded), tutorial (_tut_card…) ve antrenman ekranları ayrı dosyalara; davranış değişmez.
- Kapı: testler yeşil; ui_shots/v22ui_t ekran görüntüleri değişmemiş (önce/sonra karşılaştır); main.gd en az 800 satır kısalmış (şu an ~6080).

3b (Dalga 3'ten öne çekildi). Hibrit testleri — gozcu-playtest-analisti — branch v023/hibrit-test
- Dokunur: tests/check/hybrid_check.gd/.tscn (yeni), tests/baseline/ (yeni ölçüm betiği)
- Dokunmaz: autoload/*, sim/*, data/*
- İş: Dalga 3 kapısının (Müdür planı §4) ölçülebilir kriterlerini test/ölçüm olarak hazırla: determinizm hash'i, iki yol dağılım farkı, reyting ortalaması/sd, gol dakikası kovaları, gol sayısı tutarlılığı (ev gol sayısı = gh/ga, oyuncu st.g toplamı = tablo gf), golcü ilk 11'de, sakatlık oranı üç yolda, kayıtta tl/cards yok, kayıt boyutu ≤%105. Hızlı motor ve bağlama henüz yok → testler, hızlı yol yokken açıkça SKIP etsin (runner'da kırmızı yapmasın, "SKIP: quick_engine yok" yazsın), yol gelince otomatik devreye girsin.

Birleştirme: E → G → F → 3b. Her biri birleşmeden önce güncel main'e rebase + run_tests.sh yeşil.

Ortam kuralı: Godot çalıştıran ajanlar user:// kayıt dosyasını paylaşır. run_tests.sh her teste ayrı kayıt klasörü veriyor; kendi betiklerinde de ayrı user dir kullanın (ör. --user-data-dir veya run_tests.sh'nin yaptığı gibi XDG_DATA_HOME). tests/baseline/run_baseline.sh başka Godot işiyle aynı anda çalıştırılmamalı.

## Not (3b sonucu, Dalga 3c için)
- hybrid_check (v023/hibrit-test 770e679): motor/yönlendirme yokken SKIP; gelince otomatik açılır. Gerçek kapı: tests/baseline/hybrid_run.sh (~30 dk).
- Determinizm: ilk 11 Game.rng ile seçilirse bozuluyor → Dalga 3c'de hızlı yoldaki maçların ilk 11 seçimi (best_xi noise) maç seed'inden (hash([sim_seed, season, week, lg, idx])) türetilmeli.
- finish_live sakatlık vermiyor → Dalga 3c'de _post_match_injuries izlenen yola da bağlanmazsa kriter 6 FAIL.

---
# EK — Dalga 3 (20 Ekim 2026). Dalga 2 main'de (efb2203). Müdür planı, Atakan onaylı.

Kararlar: U19 hızlı motora GİRMEZ; haftada en fazla 12 shortlist maçı hızlı motora; kalibrasyon hedefi GERÇEK FUTBOL.
Bütçe notu: haftalık kullanım limiti sıkı → tek ajan, sıralı çalış (önce 3a, sonra 3c). Uzun ölçümü (tests/baseline/hybrid_run.sh ~30 dk) yalnızca en sonda bir kez koş.

Koddan bulgular (Müdür): izlenmeyen U19 maçları simüle edilmiyor (dokunma); finish_live sakatlık üretmiyor; Poisson reytingi 6.4 tabanlı 4.5–9.8, canlı ratings() 3.5–9.8 → p.st.rs okuyan yerler (Game.gd ~2641 rapor, ~2184/~2437 transfer/form, ~3637 ödüller; main.gd ortalamaları) sapar; best_xi(noise=true) Game.rng kullanıyor; kart cezası sistemi yok (eklenmeyecek).

## 3a. Kalibrasyon
- tools/dev/calibrate.gd/.tscn (yeni) → data/sim_calib.json (yeni). Hızlı motorla ≥5 seed × 2000 maç; team_str farkına göre 8 kova.
- Çıkar: Poisson taban gol oranları (şu an 1.3/1.05), ev sahibi bonusu (şu an `sh += 2.0`), bölen (11.0), golcü pozisyon payı (_pick_scorer ağırlıkları GK/DEF/MID/ATT), asistsiz gol oranı (0.25), reyting ortalaması+sd (gol farkı kovasına göre), gol dakikası histogramı (15'erlik 6 kova + 90+). Lazy maçlar (_lazy_str) aynı sabitleri kullanır.

## 3c. Bağlama — autoload/Game.gd
- Dokunur: sim_match, finish_live, yeni _use_fast, _post_match_injuries, _credit_stats, _goal_minute, _load_calib (adlar hybrid_check ile uyumlu olmalı; Game.s.sim_seed zaten var).
- Dokunmaz: ui/*, three/*, sim/* (F teslimi), load_game() ve göç fonksiyonları, T.gd, world.json.
- Yönlendirme tek yerde: sim_match başında _use_fast(m, lg)->bool. play_day/finish_week değişmez.
  - Kullanıcının ligi: s.scout.club_id != "" ve lg == my_club().league (işsizken uygulanmaz).
  - Shortlist: m.h veya m.a, s.scout.shortlist oyuncularının kulüp kümesinde (haftada bir hesapla); lig dışı en fazla 12 maç/hafta, fazlası Poisson.
  - Lazy kulüp (is_lazy) → her zaman Poisson; ensure_squad çağrılmaz.
  - U19 → kapsam dışı. İzlenen maç → değişmez (canlı + finish_live).
- Hızlı yolda ilk 11 seçimi Game.rng DEĞİL maç seed'inden: hash([sim_seed, season, week, lg, idx]); quick_engine.simulate(g, m, youth, seed) m.xi_h/xi_a dolu ister.
- Tutarlılık (iki yol ortak): gol dakikaları ri(1,90) yerine histogramdan, sıralı; golcü o tarafın ilk 11'inde, asist aynı tarafta ve golcüden farklı; _post_match_injuries tek fonksiyon — sim_match, hızlı yol VE finish_live çağırır; kartlar yalnız reytinge, kayda yazılmaz; apps/g/a/rs tek _credit_stats ile; fikstür kaydı şekli aynı (gh, ga, xi_h, xi_a, ev, rt), tl/cards kaydedilmez.
- Reyting ölçeği: Poisson yolunun reytingi kalibrasyondan (ortalama/sd) gelsin ki iki yol aynı ölçekte olsun.

## Dalga 3 kapısı (hybrid_check + hybrid_run.sh)
1 run_tests.sh yeşil (tüm testler). 2 Determinizm hash'i. 3 Dağılım (her yol ≥5 seed×2000): gol 2.5–3.1, ev %41–48, beraberlik %22–29, 4+ ≤%6, ev/dep oran 1.15–1.35; yollar arası fark oranlarda ≤3 puan, gol/maç ≤%10. 4 Reyting ort ±0.15, sd ±%15; golcü pozisyon payı ±5 puan. 5 Gol dakikası kovaları ≤3 puan. 6 Tutarlılık (gol olayı = gh/ga; st.g toplamı = tablo gf; golcü ilk 11'de). 7 Sakatlık oranı üç yolda ±%20. 8 Hafta süresi: izlenmeyen medyan ≤563 ms, en kötü ≤1004 ms. 9 Kayıt boyutu ≤%105, tl/cards yok. 10 Sezon sonu kovulma ve ödül sayıları makul (5 seed aralığı) + gozcu-scout-gercekcilik kısa yazılı onay (koordinatör ayrıca alır).
Not: iki motor arasında bilinen fark (F raporu): reyting ort 7.08 vs 7.16, sd 0.76 vs 0.94 — Poisson'u hızlı motora kalibre et; hybrid toleransları buna göre.
