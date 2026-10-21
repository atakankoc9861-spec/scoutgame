# Görev Tanımı — Gözcü v0.24 (Müdür, Atakan onayladı 21 Ekim 2026)

Taban: main @ 1d4bdea (0.23, code 45, kalıcı keystore). Kapı: tools/dev/run_tests.sh (5 test yeşil) + bot playtest (tests/baseline/bot_v023/bot_play.gd.txt).

## Kararlar (onaylı varsayılanlar)
1. İlerleme hızı: iyi scout 3. sezonda üst-orta kulübe (prestij ~70), zirveye 5. sezondan sonra.
2. "Evlatlarım": yalnız senin bulduğun oyuncular, haftalık özet; diğer kulüp hoca kovulmaları tek satır.
3. Fontlar: Oswald, Courier Prime, Special Elite çıkar; IBM Plex Mono gelir (UI planı A).
4. Telefon testi 2 kez: Dalga 3 sonrası ara APK, Dalga 6 final.

## Kapsam
Yapar: ilerleme+ekonomi dengesi, haber akışı özetleme, "Gece Dosyası" arayüzü, tech-art kod fazları 0–3, whimsy ilk 5, küçük hatalar.
Yapmaz: yeni ülke/lig, yeni 3D model (Blender kaynağı yok), reklam/IAP SDK, müzik, yayın.

## Genel kurallar
- Dalga başına ≤2 ajan; [K] = koordinatör yapar.
- Bir dalgada aynı dosyaya iki iş dokunmaz; Game.gd her dalgada tek işe aittir.
- Dal: v024/<isim>, güncel main'den.
- T.gd'ye hiçbir dal dokunmaz: yeni metinler tests/i18n/<dal>.json (TR+EN); koordinatör birleştirmede addkeys.py ile ekler, TR/EN eşit.
- SAVE_VERSION yalnız Dalga 3'te v6→v7; sonraki alanlar _migrate + has() varsayılanı.
- Kimse dokunmaz: project.godot, scenes/main.tscn, assets/man/* (Rohr), .claude/*.
- export_presets.cfg yalnız Dalga 6; data/sim_calib.json yalnız Dalga 1.
- Her iş en az bir tests/check/*_check.gd ekler.

## Dalga 1 — Hatalar ve motor
- 1K [K] Hata paketi — v024/hata-paketi. Titreşim: doğrudan Input.vibrate_handheld çağrıları kit.gd::_haptic kapısına (ui/screens/training.gd:413, three/match_view.gd:1164, :1323, :1652). Üst bar: ui/main.gd ~485–490 kökten create_tween() → l.create_tween() / pc.create_tween(). Dokunmaz: Game.gd, sim/*.
- 1A Alt lig gol/beraberlik — gozcu-mac-motoru — v024/altlig-motor. Dokunur: sim/live_engine.gd, sim/quick_engine.gd, data/sim_calib.json, tools/dev/calibrate.gd. Dokunmaz: Game.gd, ui/*, three/*. HOME_FM/LEVEL_LATE değişirse calibrate yeniden.
- 1B Tech-art Faz 0+1 — technical-artist — v024/ta-faz01. Dokunur: autoload/Watch.gd (perf satırı + gizli "perf göster"), three/stage3d.gd (mobil MSAA kuralı), three/stadium.gd (lamba birleştirme), three/mocap_man.gd (uzak oyuncu anim seyreltme), doku .import dosyaları, tests/baseline/render_baseline.json. Dokunmaz: three/match_view.gd (1K'nin), main.gd, Game.gd.
Birleştirme: 1K → 1A → 1B.
Kapı: ayar kapalıyken titreşim çağrısı 0 (sahte Input ile sayılır); alt lig (tier ≥3) gol/maç 2,4–3,0, beraberlik ≤%30; üst ligler önceki ±%5; eşikler iyi üstü %14±3, kötü altı %10±3; render_baseline.json var; draw call artmamış.

## Dalga 2 — İlerleme dengesi + tema temeli
- 2A İlerleme — game-designer (+ gozcu-scout-gercekcilik okuyucu) — v024/ilerleme. Game.gd: is_my_find, _headline, _star_headlines, _callups, görev süreleri, _season_end kovulma. Manşet yalnız rapor yazılan/ilk keşfi oyuncuya ait olandan; manşet itibarı sezonda ≤+6; görevler prestije göre ulaşılabilir; kovulma rep < max(5, rep_start-4) (satır ~2904). Dokunmaz: ui/*, sim/*.
- 2B Tema+hareket+düğmeler (UI planı 1,2,4) — godot-gameplay-scripter, mockup A referans — v024/tema. Dokunur: ui/theme_v24.gd (yeni), ui/motion.gd (yeni, settings.calm), ui/kit.gd, fonts/. Dokunmaz: main.gd, Game.gd.
Birleştirme: 2B → 2A, sonra bot koşusu 1 [K].
Kapı: iyi bot itibar 1.s 25–45, 2.s 45–70, 3.s ≤85; prestij artışı ≤+20/sezon; manşet itibarı ≤+6/sezon; düşen görev ≤3/sezon (iyi bot); tembel bot en geç 2. sezonda kovulur; 0 NaN, 9/9 kayıt turu; Türkçe karakter ekran görüntüsü (GÖNDERİLDİ, TAKİPTE, ŞIĞ); sakin modda hareket süreleri 0.

## Dalga 3 — Haber, kayıt, performans
- 3A Haber özeti + kayıt v7 — godot-gameplay-scripter — v024/haber-ozet. Game.gd (haberler, finish_week, _migrate v7), ui/main.gd (yalnız haber ekranı). kids_feed yalnız kendi buldukların, haftalık özet; diğer kulüp kovulmaları tek satır; teklif/görev haberleri sabit; eski news/disc_log budanır. Dokunmaz: kit.gd, three/*.
- 3B Tech-art Faz 2 (görünür özellikler) — technical-artist — v024/ta-faz2. three/mocap_man.gd, three/traits3d.gd (yeni), traits3d bayrağı; safe3d açıkken kapalı. Dokunmaz: Game.gd, main.gd, match_view.gd.
Birleştirme: 3A → 3B, sonra bot koşusu 2 [K] + ara APK (Atakan telefonda).
Kapı: haber ≤150/sezon; teklif haberi 8 hafta akışta; kayıt büyümesi ≤250 KB/sezon; 3. sezon play_day+finish_week medyan ≤500 ms; v6→v7 göç testi; ara APK'da donma/siyah ekran yok.

## Dalga 4 — Ekonomi + ana ekran
- 4A Ekonomi — economy-designer — v024/ekonomi. Game.gd: life_buy kademeleri, sürekli giderler, _seed_legends (her sezon; legends_seeded ~4496). Parayla güçlenme yok. Dokunmaz: ui/*.
- 4B Sekme geçişi + ana ekran + sayaçlı üst bar (UI planı 3,5) — godot-gameplay-scripter — v024/ui-ana. ui/main.gd (_sheet, _refresh_soft, _home_summary, _refresh_topbar), ui/kit.gd::_tabs. Dokunmaz: Game.gd.
Birleştirme: 4A → 4B, sonra bot koşusu 3 [K].
Kapı: iyi bot parası 3. sezonda 10–25 bin, tembel ≤15 bin; 3. sezonda söylenti ≥5; sekme geçişi 0,38 sn ve eski sayfa düğümleri silinir (leak testi); yeni kodda kökten create_tween() yok.

## Dalga 5 — Oyuncu dosyası, rapor, maç HUD'ı
- 5A Oyuncu dosyası + rapor ritüeli + hafta sonucu (UI planı 6,7,8 + whimsy #2 "İsabet" mührü) — godot-gameplay-scripter — v024/ui-dosya. ui/main.gd (_player_*, _scr_report, _scr_result), ui/radar.gd, ui/range_bar.gd. Dokunmaz: Game.gd, three/*.
- 5B Maç HUD'ı + Faz 3 atmosfer — technical-artist — v024/hud-atmosfer. three/match_view.gd::_build_hud (A paleti, odak oyuncu canlı puan + sparkline, zaman çizelgesi), three/stadium.gd, three/post.gd; crowd_sprites mobilde kapalı. Dokunmaz: ui/*, Game.gd.
Birleştirme: 5B → 5A.
Kapı: ui_shots ↔ mockup A, Atakan onayı; maç draw call ≤ Faz 0 +%5; safe3d açıkken yeni efektler kapalı.

## Dalga 6 — Whimsy + sürüm
- 6A Whimsy 1,3,4,5 + altyapı — godot-gameplay-scripter — v024/whimsy. ui/main.gd (_check_popups üstüne haftalık an kuyruğu), autoload/Sfx.gd (_pitch uygulanır), ui/kit.gd. "Defterin haklı çıktı", titreşim sözlüğü, efsane ipucu panosu, "evladın sahada" kartı; sakin mod ayarlarda. Dokunmaz: Game.gd.
- 6K [K] Sürüm: export_presets 0.24 code 46, release keystore ile imza, v0.24 etiketi.
Kapı: haftada ≤1 büyük an; sakin mod + titreşim ayarına uyulur; final APK telefonda 1 sezon + v0.23 kaydı açılır.

## Her dalga kapısı (ortak)
run_tests.sh yeşil; yeni *_check.gd yeşil; logda SCRIPT ERROR yok; TR/EN eşit.

## Ertelenenler
Faz 4 portre kiti (GPU ortamı), Faz 5 model işleri (Blender kaynağı yok), mobil sprite seyirci (v0.25 telemetriye göre), whimsy kalan 17 an, UI seçeneği B'nin kalanı, human.gd/footballer.gd temizliği, reklam/IAP SDK, müzik, yeni içerik.
Bütçe daralırsa 5B ve 6A v0.25'e kayabilir; öncelik Dalga 1–4.

---
# REVİZYON (21 Ekim 2026) — Dalga 4–7 yukarıdakinin yerine geçer
Atakan'ın a2 telefon geri bildirimi sonrası (maç süresi, Analist Gözü, top hatası, talepler, izin, bölge seçici, yüz/forma/tribün). Dalga 1–3 tamam (main d7c3ee5). 4K tamam (d3ed119).

## Kararlar
- Maç süresi: Özet ~5 dk, Anlar ~3 dk, Normal ~12 dk; devre arası "2. yarıyı izle / özetle / atla"; anlar devre başına tavanlı.
- İzinsiz ülke = sadece video (aramada "sadece video" etiketi; antrenman/maç/seyahat kilitli; do_training izin kontrolü).
- Analist Gözü (Atakan seviyor, kısılmasın, işe yarasın): maçta 4–5 (iki yarıya yayılmış, arka arkaya değil), tam durdurma yok → 0,25 ağır çekim, üstten analist kamerası (pas yolları, boş adam, baskı), doğru cevap futbol mantığından + kısa gerekçe, doğru okuma odak oyuncunun ilgili özelliğinin bilgisini artırır, yalnız odak oyuncu anlarında.
- Yüzler: v0.25'te CC0 hat; v0.24'te yalnız forma + tribün (kod).
- Talep tavanı ortak 3, "şimdi yapamam" reddi küçük bedelle; bölge seçici bayrak + europe.gd harita vurgusu + açık bölge adları.
- Yeni (Atakan onayladı): "Bu maçta öğrendiklerin" ekranı (v0.24), kayıt yedeği (v0.24), monetizasyon tasarım dokümanı (v0.24, uygulama sonra); video klip oynanışı ve gizli özellikler + sinematik görüşmeler v0.25.
- Not edilenler: haftalık oturum süresi hedefi, düşük segment Android testi, Google Play şartları (hedef API, gizlilik, veri güvenliği) yayından önce, kapsam şişmesine dikkat.

## Dalga 4 — Maç temposu ve kurallar
- 4K [K] top asılı kalma — TAMAM.
- 4A Maç temposu — godot-gameplay-scripter — v024/mac-tempo. Yalnız three/match_view.gd (_current_rate, _tick_seek, _moment_track, devre arası) + tests/check/tempo_check.gd (önce yazılır). Dokunmaz: sim/*, Game.gd, ui/*. Özet: yalnız şut/gol/büyük fırsat 1x, gerisi görüntüsüz hızlı atlanır; Anlar: devre başına ≤4 an, sona yaklaşınca 2. yarıya mutlaka geçer; devre arası seçimi; video 5 an aynen.
- 4B Talep tavanı + izin + bölge seçici — game-designer — v024/talep-izin. Game.gd (make_assignments, _organic_requests, ~2347 +1 talep, yeni assign_decline, do_training, arama), autoload/Data.gd (ZONES + bölge adları), ui/main.gd (yalnız başkan bölge seçimi, arama etiketi, talep kartı reddet), ui/europe.gd. Dokunmaz: three/*, sim/*.
Birleştirme: 4K → 4B → 4A.
Kapı: testler yeşil, SCRIPT ERROR yok, TR/EN eşit; engine_check ölü top ball_h=0; tempo_check Özet ≤6 dk, Anlar ≤4 dk, Normal ≤14 dk, 2. yarıya her modda ulaşılıyor; bot [K]: açık talep hiç >3 değil, iyi botta düşen ≤3/sezon, 0 NaN, kayıt turu temiz; izinsiz ülkede do_training "need_board_abroad", video çalışıyor; bölge ekranı görüntüsü (bayrak + vurgulu harita).

## Dalga 5 — Analist Gözü + "Öğrendiklerin"
Arayüz: 5A maç sonu verisine fe["_eye_reads"] = [{pid, attr, ok}] yazar; 5B okur.
- 5A Analist Gözü — godot-gameplay-scripter (+ gozcu-scout-gercekcilik okuyucu) — v024/analist-gozu. sim/eye_logic.gd (yeni, saf mantık), three/match_view.gd (_eye_*, analist kamerası), tests/check/eye_check.gd (önce). sim/live_engine.gd yalnız okuma (eye_preview). Dokunmaz: Game.gd, ui/*.
- 5B Öğrendiklerin + bilgi kazancı — game-designer — v024/ogrendiklerin. Game.gd (finish_live/finish_video bilgi farkı, _eye_reads → vision/decisions/passing, maç başı tavan), ui/main.gd (_scr_result), ui/range_bar.gd (daralma animasyonu). Dokunmaz: three/*, sim/*.
Birleştirme: 5B → 5A, sonra ara APK a3 [K].
Kapı: testler yeşil; eye_check elle kurulmuş pozisyonlar (boş adam + açık yol = doğru; riskli ara pası yanlış; TR/EN gerekçe); 50 maç ekransız: 4–5 soru, her yarıda ≥2, arka arkaya yok, hız hiç 0 değil; doğru okuma bilgiyi artırır, tavan aşılmaz, kayıt turu temiz; telefonda analist kamerası donma/siyah ekran yok, Özet ~5 dk, öğrendiklerin ekranı görünüyor.

## Dalga 6 — Ekonomi, görsellik, yedek
- 6A Ekonomi + docs/v024/MONETIZASYON.md — economy-designer — v024/ekonomi. Game.gd (life_buy kademeleri, sürekli giderler). Doküman: ödüllü reklam/IAP nereye (parayla güçlenme yok; örn. ek video hakkı), çevrimdışı, fiyat/sıklık.
- 6B Forma + tribün — technical-artist — v024/forma-tribun. three/mocap_man.gd (forma kumaş shader'ı, numara/isim baskısı), three/stadium.gd (sprite seyirci, telefonda bayrakla). Dokunmaz: match_view.gd, Game.gd, ui/*.
- 6K [K] Kayıt yedeği — v024/yedek. ui/screens/backup.gd (yeni), ui/main.gd (ayarlara 2 buton). Dışa aktar user://kariyer.json → seçilen konum; içe aktar → doğrula → SAVE_PATH → load_game() + göç; Game.gd değişmez; Godot yerel dosya seçici, çalışmazsa Download.
Birleştirme: 6K → 6A → 6B.
Kapı: testler yeşil; bot [K] iyi bot parası 3. sezon 10–25 bin, tembel ≤15 bin, ilerleme korunuyor; yedek dışa→içe aynı durum (test), bozuk dosya red, telefonda elle bir kez; maç dc ≤ Faz 0 +%5, telefonda fps düşmüyor, safe3d'de sprite seyirci kapalı; MONETIZASYON.md Atakan okudu.

## Dalga 7 — Ana ekran (opsiyonel) + sürüm
- 7A (OPSİYONEL) sekme geçişi + ana ekran özeti (UI planı 3,5) — godot-gameplay-scripter — v024/ui-ana. ui/main.gd (_sheet, _refresh_soft, _home_summary, _refresh_topbar), ui/kit.gd. Haftalık limit dolarsa v0.25.
- 7K [K] sürüm: 0.24, code = son ara APK + 1; release keystore; v0.24 etiketi; docs/v024/PLAY-KONTROL.md (hedef API, gizlilik politikası, veri güvenliği — not, yayın yok).
Son kapı: testler + bot yeşil; Atakan telefonda 1 sezon; mümkünse düşük segment Android'de 1 maç; v0.23 kaydı açılıyor; yedek dışa/içe.

## v0.25'e kalanlar
Video klip oynanışı; gizli özellikleri görüşmeye bağlama + sinematik görüşmeler (Data.HIDDEN zaten var, Game.gd ~1132/~1184); yüz hattı (CC0); maç HUD yeniden tasarımı; whimsy anları; monetizasyon kodu; haftalık oturum süresi hedefi.
