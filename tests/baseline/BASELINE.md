# Gözcü ölçüm temeli: v0.23 Dalga 1 entegrasyonu (`9325199`)

v0.23 Dalga 1-D, tekrar ölçüm. 16 Ekim 2026'da `v023/dalga1-entegrasyon` @ `9325199` üzerinde ölçüldü. Bu sürümde isim temizliği, genişletilmiş kara liste ve menajer/gazeteci adı düzeltmesi var. Ortam: Godot 4.5.1 headless, 2 çekirdekli Linux.

Ölçümün kapsamı:
- 3 seed (2301, 4711, 9001)
- Canlı motor: seed başına 200 maç, toplam 600
- Poisson: seed başına tam sezon, ~13.000 maç
- Hafta süresi: seed başına 35 hafta, izlenen ve izlenmeyen olarak

Makine okunur sürüm `baseline.json` dosyasında. İlk ölçüm (77c0f1d, tek seed) en altta karşılaştırma için duruyor.

**Kısa sonuç:**
- **Seed'den bağımsız gerçek açıklar:**
  - Canlı motorda skor farkı fazla açık (4+ fark %14, hedef ≤6).
  - Poisson'da ev sahibi avantajı fazla (%53, hedef ≤48).
  - Canlı motorda maç içi olay sayıları düşük.
- **Tek seed'de "kesin" görünen ama artık belirsiz:** canlı motorda ev sahibi galibiyeti fazla, beraberlik az.
- **Hafta bütçesi:** izlenmeyen hafta için medyan ≤563 ms, en kötü ≤1.004 ms.

## 1. Sonuç metrikleri: ortalama ± seed'ler arası standart sapma

"Hüküm" sütunu:
- **GERÇEK:** 3 seed'in üçü de hedef dışında ve aynı yönde.
- **belirsiz:** seed'e göre hedefin içine ve dışına düşüyor.
- **hedefte:** 3 seed'in üçü de hedef içinde.

| Metrik | Canlı motor (3×200) | Hüküm | Poisson: tüm ligler (3×~13k) | Hüküm | Poisson: top-5 1. lig (3×1.530) | Poisson: Süper Lig (3×306) | Hedef |
|---|---|---|---|---|---|---|---|
| Gol / maç | 2,94 ± 0,10 | hedefte | 2,61 ± 0,01 | hedefte | 2,74 ± 0,05 | 2,81 ± 0,15 | 2,5–3,1 (SL 2,6–3,0) |
| Ev sahibi / dep. gol | 1,81 / 1,13 | – | 1,67 / 0,94 | – | 1,75 / 0,99 | 1,79 / 1,02 | ~1,55 / ~1,25 |
| Ev sahibi galibiyet % | 50,7 ± 2,8 (52,5 / 47,5 / 52,0) | belirsiz | **53,3 ± 0,6** | **GERÇEK ↑** | **52,8 ± 1,3** | **53,1 ± 2,5** | 41–48 (SL 42–50) |
| Beraberlik % | 19,2 ± 4,5 (19,5 / 23,5 / 14,5) | belirsiz | 22,5 ± 0,4 | hedefte (alt sınırda) | **20,4 ± 0,5 ↓** | 19,3 ± 2,7 (belirsiz) | 22–29 |
| Deplasman galibiyet % | 30,2 ± 2,9 | belirsiz | **24,2 ± 0,2** | **GERÇEK ↓** | 26,7 ± 0,8 (belirsiz) | 27,6 ± 1,5 (belirsiz) | 27–33 |
| 0-0 % | 6,2 ± 2,3 | belirsiz (hep 3,5–7,5) | 7,9 ± 0,4 | hedefte | 7,3 ± 1,2 | 6,3 ± 1,8 | 4–9 |
| 4+ farklı maç % | **14,2 ± 1,2** | **GERÇEK ↑** | **8,3 ± 0,4** | **GERÇEK ↑** | **11,0 ± 0,5** | **13,2 ± 2,2** | 2–6 |

Not: canlı motorda 0-0'ı "belirsiz" yapan tek şey seed 9001'deki %3,5; ortalama 6,2 ve %95 aralık 4,2–8,1, ikisi de hedef içinde. Bu metrik pratikte sorun değil.

**Canlı motor, birleşik 600 maç, %95 güven aralığı:**

| Metrik | Değer | %95 aralık | Hedef | Yorum |
|---|---|---|---|---|
| Ev sahibi galibiyet % | 50,7 | 46,7–54,7 | 41–48 | Aralık hedefle örtüşüyor. Fazlalık **kanıtlanmadı**. |
| Beraberlik % | 19,2 | 16,0–22,3 | 22–29 | Muhtemelen az. Aralığın üst ucu hedefin alt sınırına ancak değiyor. |
| Deplasman galibiyet % | 30,2 | 26,5–33,8 | 27–33 | Hedefte. |
| 0-0 % | 6,2 | 4,2–8,1 | 4–9 | Hedefte. |
| 4+ fark % | 14,2 | 11,4–17,0 | 2–6 | **Kesin açık.** |

En sık canlı skorlar: 1-0 %9,3, 1-1 %9,3, 0-1 %8,8, 2-0 %8,3, 0-0 %6,2, 3-0 %6,2. 600 maçta bir takımın 6+ gol attığı maç sayısı 22.

### Canlı motor: maç içi olaylar (seed'ler arası çok kararlı, hepsi GERÇEK)

| Metrik | Ölçülen | Hedef |
|---|---|---|
| Şut / maç | 17,2 ± 0,2 | 22–28 |
| İsabetli şut | 6,2 ± 0,1 | 7–10 |
| Pas isabeti % | 74,4 ± 0,0 (~671 deneme) | 78–86 |
| Faul | 10,3 ± 0,2 | 19–26 |
| Korner | 4,1 ± 0,1 | 8–11 |
| Sarı kart | 1,49 ± 0,07 | 3–5 |
| Kırmızı kart | 0,14 ± 0,04 | 0,08–0,2 (hedefte) |

Bunlar yumuşak hedefler: oyuncu maç ekranında görüyor, ama sonuç dağılımı kadar kritik değil.

## 2. Hangi sonuç seed'den bağımsız?

**Sağlam (3 seed'de de aynı yönde, örneklem hatasından büyük):**
1. **Canlı motorda skor farkı fazla açık.**
   - 4+ fark %13,5–15,5; %95 aralık 11,4–17,0; hedef ≤6.
   - Poisson'da da yüksek (%8,3), ama daha hafif.
2. **Poisson'da ev sahibi avantajı fazla.**
   - Ev sahibi galibiyeti %52,9–53,9, deplasman galibiyeti %24,0–24,3.
   - Ev/deplasman gol oranı ~1,78; gerçekte ~1,25.
   - Sebep: `sim_match` içinde `sh += 2.0` ve taban oranlar 1.3/1.05.
   - ~13.000 maçlık örneklemde bu oynamaz.
3. **Poisson top-5'te beraberlik az:** %20,0–21,0, hedef ≥22.
4. **Canlı motorda maç içi olaylar yarı yarıya düşük:** şut, faul, korner, sarı kart. Pas isabeti %74.
5. **Gol / maç her iki motorda hedefte:** canlı 2,84–3,03, Poisson 2,60–2,61.

**Sağlam değil (önceki tek seed ölçümünden çıkan ama tutmayan sonuçlar):**
- **"Canlı motorda ev sahibi galibiyeti %56, çok yüksek":** 3 seed'de %47,5–52,5, %95 aralık 46,7–54,7. Hedefin biraz üstünde olabilir, ama kanıtlanmadı.
- **"Canlı motorda beraberlik %17":** seed'e göre %14,5–23,5. Ortalama 19,2 düşük görünüyor ama sınırda. Kesin hüküm için ~1.000+ maç gerekir.
- **"Canlı motorda 4+ fark %18,5":** gerçek değer ~%14. Yön doğru, büyüklük abartılıydı.

**Neden bu kadar oynuyor?**
- 200 maçlık bir örneklemde %50 civarı bir oranın standart hatası ~3,5 puan; %95 aralık ±7 puan.
- İsim temizliği RNG akışını kaydırdığı için aynı seed artık farklı bir dünya ve farklı kadrolar üretiyor. Reality Checker'ın gördüğü %56 → %47,5 kayması büyük ölçüde örneklem gürültüsü; motor değişmedi.
- Ölçüm deterministik: aynı commit ve aynı seed iki kez çalıştırıldığında aynı skor dağılımı çıktı.

Motor kalibrasyonu (Dalga 2-F) için öneri: kabul ölçümü **en az 3 seed × 200** maç olmalı. Oran hedefleri birleşik örneklemin %95 aralığıyla değerlendirilmeli, tek seed'le değil.

## 3. Hafta süresi ve v0.23 bütçesi

`Game.end_week_auto()`, seed başına 35 hafta.

| Senaryo | Medyan (seed: 2301 / 4711 / 9001) | Ort. medyan | p90 ort. | En kötü (seed'ler) | Ort. en kötü |
|---|---|---|---|---|---|
| İzlenen maç yok (tümü Poisson) | 288 / 291 / 266 | **282 ms** | 326 ms | 506 / 499 / 501 | **502 ms** |
| Her hafta 1 canlı maç izleniyor (`PLAN=1`) | 2.724 / 2.711 / 2.647 | **2.694 ms** | 2.895 ms | 3.136 / 3.259 / 2.851 | **3.082 ms** |

Sürenin dağılımı:
- `save_game()` medyan 212 ms; kayıt dosyası ~2,4 MB. İzlenmeyen haftanın **~%75'i kayıt yazımı**.
- Canlı motor maç başına medyan 2.385 ms, en kötü 3.412 ms. İzlenen haftalardaki fark bu.
- `new_game()` ~200–250 ms.

**v0.23 hafta bütçesi (seed ortalaması × 2):**

| | Medyan ≤ | En kötü ≤ |
|---|---|---|
| İzlenmeyen hafta (karma modelin ana bütçesi) | **563 ms** | **1.004 ms** |
| Canlı maç izlenen hafta | 5.388 ms | 6.164 ms |

Karma model (Dalga 3) için hesap:
- İzlenmeyen haftada hızlı motora kalan pay medyanda ~280 ms. Bunun içine oyuncunun ligi (Süper Lig'de 9 maç), U19 ve shortlist maçları sığmalı.
- Yani hızlı motor maç başına **~5 ms veya altında** olmalı; 1–3 ms hedeflenmeli.
- Bugünkü canlı motor maç başına ~2.400 ms sürüyor, yaklaşık 500–1000 kat fazla.
- Bu süreler 2 çekirdekli test makinesine ait; telefondaki mutlak süre farklı olur. Bütçe göreli karşılaştırma içindir: aynı makinede, aynı senaryoyla.

## 4. Hedef aralıklar ve gerekçe (gozcu-scout-gercekcilik)

| Metrik | Hedef | Gerekçe |
|---|---|---|
| Gol / maç | 2,5–3,1 | 2024-25 sezonu: La Liga 2,61, Serie A 2,70, Premier Lig 2,92, Ligue 1 2,98, Bundesliga 3,22. Süper Lig 2023-24: 2,79 (1.062 gol / 380 maç). |
| Ev sahibi galibiyet % | 41–48 | Top-5'te %41–47, Süper Lig 2023-24'te ~%45. Pandemi sonrası ev sahibi avantajı azaldı. |
| Beraberlik % | 22–29 | Serie A ~%29, Ligue 1 ~%22, Süper Lig ~%26. |
| Deplasman galibiyet % | 27–33 | Top-5'te %27–32, Süper Lig'de ~%28. |
| 0-0 % | 4–9 | Uzun dönem ortalaması ~%7–8. Son sezonlar: Premier Lig ~%3–6, Bundesliga %4, La Liga %8,8, Ligue 1 %9,6. |
| 4+ farklı maç % | 2–6 | Doğrudan kaynak yok. Gerçekçi gol beklentileriyle (ev ~1,55, deplasman ~1,25) Poisson hesabı ~%3–4 veriyor; yıldız-küme farkı için pay bırakıldı. |
| Şut / isabetli şut | 22–28 / 7–10 | Top-5'te takım başına maçta ~11–14 şut, ~4–5 isabetli. |
| Pas isabeti | %78–86 | Lig ortalaması ~%80–84; alt ligler daha düşük. |
| Faul / korner / sarı kart | 19–26 / 8–11 / 3–5 | Top-5'te maç başına 20–25 faul, ~10 korner, 3,5–4,5 sarı. Süper Lig sarıda üst sınıra yakın. |

Danışman notu:
- Oyuncu için asıl önemli olan sonuç ve skor dağılımı. Şut, faul ve korner sayıları yumuşak hedeflerdir.
- Sık görülen 5+ farklı skorlar, izlenen maçta yeteneği değil kadro farkını öne çıkarır. Bu da scout gözleminin değerini düşürür.

Kaynaklar:
- [Wikipedia: 2023–24 Süper Lig](https://en.wikipedia.org/wiki/2023%E2%80%9324_S%C3%BCper_Lig)
- [SportyTrader: büyük ligler 2024-25](https://www.sportytrader.com/us/news/stats-across-top-european-leagues-and-mls-2024-2025/)
- [The Analyst: 0-0 beraberlikler](https://theanalyst.com/articles/premier-league-changes-killing-off-0-0-draws)
- [WinDrawWin: 0-0 oranları](https://www.windrawwin.com/statistics/how-often-do-games-end-0-0/)

## 5. Açık analizi (öncelik sırasıyla, yalnızca sağlam bulgular)

1. **Canlı motorda skor farkı (%14 4+ fark).**
   - Olası sebep: `setup()` içindeki form kayması (`fm`) tüm özelliklere doğrudan ekleniyor. Ayrıca düellolarda güç farkı (`slope`) seviye farkını katlıyor.
   - Kabul hedefi: 3×200 maçta 4+ fark ≤%6; gol/maç 2,5–3,1 aralığında kalmalı.
2. **Poisson'da ev sahibi avantajı.**
   - Ölçülen: %53 ev sahibi galibiyeti, %24 deplasman galibiyeti, ev/deplasman gol oranı ~1,78.
   - Öneri: taban oranları ~1.45/1.20'ye yaklaştırmak, `+2.0` güç bonusunu ~+1.0'a indirmek. Rakamlara motor/ekonomi ajanı karar verir.
   - Karma modelde Poisson motora kalibre edileceği için önce 1. madde düzelmeli, sonra Poisson ona bağlanmalı.
3. **Poisson'da ve muhtemelen canlıda beraberlik az.** Top-5 Poisson %20,4; canlı 19,2 (sınırda). Büyük ölçüde 1. ve 2. maddelerin yan etkisi; onlar düzelince yeniden ölçülmeli.
4. **Canlı motorda maç içi olaylar yarı yarıya düşük.** Yumuşak hedef.
5. **Performans.** Hızlı motor maç başına ≤5 ms olmalı (bkz. bölüm 3).

## 6. tests/quick.tscn neden "bitmiyordu"? (ilk ölçümden, hâlâ geçerli)

Yavaşlık değil, **çökme sonrası asılı kalma**:
- `tests/quick.gd:7`, `Game.league_clubs("BAL1")[0]` satırında `Out of bounds get index '0'` hatası veriyor. `BAL1` ligi `data/world.json` içinde artık yok.
- Script hatası `_ready()` fonksiyonunu kesiyor ve `get_tree().quit()` hiç çağrılmıyor. Headless Godot sonsuza kadar bekliyor.

Diğer şüpheliler elendi:
- Dünya üretimi ~200–250 ms sürüyor.
- `Watch.gd` bekçi thread'i çıkışı engellemiyor.

Ders: her test bir güvenlik zamanlayıcısı ile `quit(1)` yapmalı, runner da timeout'u hata saymalı.

## 7. Yeniden çalıştırma

```bash
# bir kez (yeni worktree/kopya):
/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64 --headless --path . --import
# tam ölçüm, 3 seed (~30 dk, 2 çekirdek). Çıktılar tests/baseline/out/ altına (git'e girmez).
tests/baseline/run_baseline.sh
# farklı seed'ler / daha çok maç:
SEEDS="11 22 33 44" N=300 tests/baseline/run_baseline.sh /tmp/olcum
```

| Sahne | Ne ölçer | Ortam değişkenleri | Süre / seed |
|---|---|---|---|
| `res://tests/baseline/live_stats.tscn` | Canlı motor. Gerçek fikstürden (SL, EN1, ES1, IT1, DE1 ilk turları) maçlar `LiveEngine.setup(..., seed)` ve `run_to_end()` ile oynatılır; tabloya yazılmaz. | `N`, `LGS`, `SEED` | ~8 dk (200 maç) |
| `res://tests/baseline/season_stats.tscn` | Bir sezon `end_week_auto()` ile oynatılır; Poisson skorları ve her haftanın ms süresi ölçülür. | `PLAN=0` veya `PLAN=1` (her cumartesi oyuncunun liginden bir maç canlı izlenir), `SEED` | ~15 sn / ~1,5 dk |
| `res://tests/baseline/probe.tscn` | Teşhis: `new_game`, `take_job`, `save` ve 3 hafta süreleri | yok | ~3 sn |

Her sahne sonunda `RESULT_JSON {...}` satırı basar ve `quit(0)` ile çıkar. `make_baseline.py <log_klasörü> <çıkış.json> <seed...>` bu satırlardan şunları üretir:
- seed'ler arası ortalama, standart sapma, en küçük/en büyük değer
- birleşik %95 güven aralığı
- hüküm (gerçek açık / belirsiz / hedefte)
- hafta bütçesi

Dikkat:
- Sahneler `user://` kayıt dosyasını ezer, ve bu dosya **tüm worktree'lerde ortak** (aynı proje adı). Ölçümler sırayla koşmalı; aynı anda başka bir Godot testi çalışmamalı.
- Aynı commit ve aynı seed ile skorlar deterministik. ms süreleri makineye bağlı.
- Dünyayı etkileyen herhangi bir değişiklik (isim listesi bile) RNG akışını kaydırır ve aynı seed'le farklı dünya üretir. Karşılaştırmalar bu yüzden tek seed'le değil, çok seed'in ortalamasıyla yapılmalı.

## Ek: ilk ölçümle karşılaştırma (77c0f1d, tek seed 2301)

| Metrik | 77c0f1d (1 seed) | 9325199 (3 seed ort.) |
|---|---|---|
| Canlı gol/maç | 3,15 | 2,94 ± 0,10 |
| Canlı ev sahibi galibiyet % | 56,0 | 50,7 ± 2,8 |
| Canlı beraberlik % | 17,0 | 19,2 ± 4,5 |
| Canlı 4+ fark % | 18,5 | 14,2 ± 1,2 |
| Poisson gol / ev sahibi galibiyet % | 2,62 / 52,3 | 2,61 / 53,3 |
| Hafta medyan / en kötü (izlenmeyen) | 286 / 454 ms | 282 / 502 ms |
| Hafta medyan / en kötü (izlenen) | 2.655 / 3.032 ms | 2.694 / 3.082 ms |

İki commit arasında `sim/` ve `sim_match` değişmedi; yalnızca isim üretimi değişti (`Data.gd` listeleri, `Game._agent_name()`). Bu değişiklik RNG akışını kaydırıyor. Canlı motordaki farklar örneklem gürültüsü ve dünya farkından kaynaklanıyor. Poisson ve hafta süreleri kararlı.
