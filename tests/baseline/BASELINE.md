# Gözcü ölçüm temeli: v0.22-b4 (code 43)

v0.23 Dalga 1-D. Bu belge 15 Ekim 2026'da, `77c0f1d` (main) üzerinde Godot 4.5.1 headless ile 2 çekirdekli bir Linux makinede ölçüldü.
Makine okunur sürüm: `baseline.json`. Yeniden üretmek için en alttaki adımlar yeterli.

**Kısa sonuç:** Poisson tarafı gol sayısında gerçeğe yakın, ama ev sahibi avantajı fazla güçlü. Canlı motorda ise skorlar çok açılıyor: maçların %18,5'i 4+ farkla bitiyor, gerçekte bu oran ~%4. Ev sahibi galibiyeti fazla, beraberlik az. Hafta süresi izlenen maç yoksa ~0,29 sn; bir canlı maç izlenirse ~2,7 sn.

## 1. Ölçülen sayılar (yan yana)

| Metrik | Canlı motor (200 maç) | Poisson: tüm ligler (12.974 maç) | Poisson: top-5 1. lig (1.530) | Poisson: Süper Lig (306) | **Hedef aralık** |
|---|---|---|---|---|---|
| Gol / maç | **3,15** | 2,62 | 2,65 | 2,80 | 2,5–3,1 (SL 2,6–3,0) |
| Ev sahibi gol / dep. gol | 2,03 / 1,12 | 1,67 / 0,95 | 1,67 / 0,98 | 1,86 / 0,93 | ~1,55 / ~1,25 |
| Ev sahibi galibiyet % | **56,0** | **52,3** | **50,8** | **54,2** | 41–48 (SL 42–50) |
| Beraberlik % | **17,0** | 23,0 | 23,1 | 20,9 | 22–29 (SL 22–28) |
| Deplasman galibiyet % | 27,0 | **24,7** | **26,1** | **24,8** | 27–33 |
| 0-0 % | 5,5 | 7,9 | 8,4 | 7,8 | 4–9 |
| 4+ farklı maç % | **18,5** | 8,5 | 10,8 | 12,7 | 2–6 (tahmin) |
| Şut / maç (iki takım) | **17,5** | yok | yok | yok | 22–28 |
| İsabetli şut / maç | **6,1** | yok | yok | yok | 7–10 |
| Pas isabeti % | **74,4** (669 pas denemesi) | yok | yok | yok | 78–86 |
| Faul / maç | **10,5** | yok | yok | yok | 19–26 |
| Korner / maç | **4,1** | yok | yok | yok | 8–11 |
| Sarı / kırmızı kart | **1,48** / 0,13 | yok | yok | yok | 3–5 / 0,08–0,2 |

Kalın değerler hedef aralığın dışında.

En sık skorlar:
- **Canlı:** 1-0 %11, 1-1 %9, 3-0 %7, 2-0 %6,5, 0-2 %6. 6-0, 7-0, 7-1 ve 8-0 skorları 200 maçta toplam 13 kez çıktı.
- **Poisson (tümü):** 1-0 %11,3, 1-1 %10,9, 2-0 %9,7, 0-0 %7,9, 0-1 %7,8, 2-1 %7,8.

Poisson alt kırılımları:
- **Ayrıntısız (lazy, kulüp seviyesinden) maçlar:** 11.750 maç, gol 2,61, ev sahibi galibiyeti %52,4.
- **Ayrıntılı (ilk 11 gücünden) maçlar:** 1.224 maç, gol 2,64, ev sahibi galibiyeti %51,8.
- **Ligin seviyesine göre:** 1. seviye 2,69 gol / %51,7 ev sahibi galibiyeti; 2. seviye 2,56 / %53,7; 3. seviye 2,55 / %49,2.

## 2. Hafta süresi (v0.23 bütçesinin temeli)

`Game.end_week_auto()`, 35 haftalık bir sezonun tamamında ölçüldü.

| Senaryo | Medyan | p90 | En kötü | En iyi |
|---|---|---|---|---|
| İzlenen maç yok (tüm maçlar Poisson) | **286 ms** | 366 ms | **454 ms** | 237 ms |
| Her hafta 1 canlı maç izleniyor (`PLAN=1`) | **2.655 ms** | 2.892 ms | **3.032 ms** | 284 ms (hafta 1) |

Sürenin nereye gittiği:
- `save_game()` medyan 224 ms (kayıt dosyası 2,4 MB). İzlenmeyen haftanın **~%78'i kayıt yazımı**, sim_match ise ucuz.
- Bir canlı maçın `run_to_end()` süresi medyan 2.390 ms, en kötü 3.352 ms. İzlenen haftalardaki farkın tamamı bu.
- `new_game()` (dünya üretimi) 206–256 ms sürüyor. Yavaşlığın sebebi bu değil.

**v0.23 bütçesi (en fazla 2 katı):**
- İzlenmeyen hafta: medyan ≤ **572 ms**, en kötü ≤ **908 ms**.
- Canlı maç izlenen hafta: medyan ≤ 5.310 ms, en kötü ≤ 6.064 ms.

Karma model (Dalga 3) için not: oyuncunun ligi, U19 ve shortlist maçlarının toplamı izlenmeyen hafta bütçesine (~290 ms ek pay) sığmalı. Kayıt yazımı zaten ~220 ms tutuyor. Hızlı motorun maç başına maliyeti **~1–3 ms** olmalı: Süper Lig'in bir haftası 9 maç; U19 ve shortlist maçlarıyla birkaç düzine maç olur. Mevcut canlı motor maç başına ~2,4 sn sürüyor, yani yaklaşık 1000 kat fazla.

## 3. Hedef aralıklar ve gerekçe (gozcu-scout-gercekcilik)

| Metrik | Hedef | Gerekçe |
|---|---|---|
| Gol / maç | 2,5–3,1 | 2024-25 sezonu: La Liga 2,61, Serie A 2,70, Premier Lig 2,92, Ligue 1 2,98, Bundesliga 3,22. Süper Lig 2023-24: 2,79 (1.062 gol / 380 maç). Alt ligler biraz daha düşük olabilir. |
| Ev sahibi galibiyet % | 41–48 | Top-5'te %41–47, Süper Lig 2023-24'te ~%45. Pandemi sonrası ev sahibi avantajı belirgin biçimde azaldı. |
| Beraberlik % | 22–29 | Serie A ~%29, Ligue 1 ~%22, Süper Lig ~%26. |
| Deplasman galibiyet % | 27–33 | Top-5'te %27–32, Süper Lig'de ~%28. |
| 0-0 % | 4–9 | Uzun dönem ortalaması ~%7–8. Son sezonlar daha düşük: Premier Lig ~%3–6, Bundesliga %4, La Liga %8,8, Ligue 1 %9,6. |
| 4+ farklı maç % | 2–6 | Kaynak doğrudan bir sayı vermiyor. Gerçekçi gol beklentileriyle (ev ~1,55, deplasman ~1,25) Poisson hesabı ~%3–4 çıkıyor; yıldız-küme farkı için pay bırakıldı. |
| Şut / isabetli şut | 22–28 / 7–10 | Top-5'te takım başına maçta ~11–14 şut, ~4–5 isabetli. |
| Pas isabeti | %78–86 | Lig ortalaması ~%80–84. Alt ligler daha düşük. |
| Faul / korner / sarı kart | 19–26 / 8–11 / 3–5 | Top-5'te maç başına 20–25 faul, ~10 korner, 3,5–4,5 sarı. Süper Lig sarı kartta üst sınıra yakın. |

Danışman notu:
- Oyuncu için asıl önemli olan sonuç ve skor dağılımı. Şut, faul ve korner sayıları "yumuşak" hedeflerdir.
- Gerçek scout maç raporunda 7-0 ve 8-0 skorları istisnadır. Canlı motorun ürettiği "sık sık 5+ fark", oyuncunun izlediği maçta yeteneği değil kadro farkını öne çıkarır, bu da gözlem değerini düşürür.

Kaynaklar:
- [Wikipedia: 2023–24 Süper Lig](https://en.wikipedia.org/wiki/2023%E2%80%9324_S%C3%BCper_Lig)
- [SportyTrader: büyük ligler 2024-25](https://www.sportytrader.com/us/news/stats-across-top-european-leagues-and-mls-2024-2025/)
- [The Analyst: 0-0 beraberlikler](https://theanalyst.com/articles/premier-league-changes-killing-off-0-0-draws)
- [WinDrawWin: 0-0 oranları](https://www.windrawwin.com/statistics/how-often-do-games-end-0-0/)

## 4. Açık analizi (öncelik sırasıyla)

1. **Canlı motorda skor farkı çok açık.** 4+ fark %18,5, hedef ≤%6. Gol sayısı ancak hafif yüksek (3,15), ama tek taraflı maçlar bunu şişiriyor.
   - Olası sebep: `setup()` içindeki form kayması (`fm`) tüm özelliklere doğrudan ekleniyor. Ayrıca düellolarda güç farkının doğrusal etkisi (`slope`) seviye farkını katlıyor.
   - Kalibrasyon hedefi: gol/maç ≤ 3,0, 4+ fark ≤ %6.
2. **Ev sahibi avantajı her iki motorda da fazla.** Canlı motorda %56, Poisson'da %52 (hedef 41–48). Poisson'da ev sahibi/deplasman gol oranı 1,76; gerçekte ~1,25.
   - Sebep (Poisson): `sh += 2.0` ile birlikte taban oranlar `1.3` ve `1.05`.
   - Sebep (canlı): ev sahibi oyunculara tüm özelliklerde `+0.55` form ekleniyor.
   - Öneri (Poisson): tabanı ~1.45/1.20'ye yaklaştırıp `+2.0`'yi ~+1.0'a indirmek. Bu yalnızca öneri; denge rakamlarına ekonomi/motor ajanı karar verir.
3. **Canlı motorda beraberlik az (%17, hedef 22+).** 1 numaralı maddenin doğrudan sonucu; skorlar açıldıkça beraberlik düşüyor.
4. **Canlı motorda maç içi olay sayıları yarı yarıya düşük.** Şut, faul, korner ve sarı kart hedefin yaklaşık yarısında; pas isabeti %74. Oyuncu bunları maç ekranında ve raporda görüyor, ama yumuşak hedef.
5. **Poisson tarafı gol ve 0-0'da iyi.** Gol 2,62 ve 0-0 %7,9 hedef aralıkta. Karma modelde (Dalga 3) Poisson, motora kalibre edilecek. Önce motor (madde 1–2) düzeltilmeli, sonra Poisson ona bağlanmalı. Yoksa bugünkü bozuk motor dağılımı Poisson'a kopyalanır.
6. **Performans.** Canlı motor maç başına ~2,4 sn sürüyor; hızlı motor işi (Dalga 2-F) için başlangıç noktası bu.

## 5. tests/quick.tscn neden "bitmiyordu"?

Yavaşlık değil, **çökme sonrası asılı kalma**:
- `tests/quick.gd:7`, `Game.league_clubs("BAL1")[0]` satırında `Out of bounds get index '0'` hatası veriyor. `BAL1` ligi artık `data/world.json` içinde yok; test v0.11'den kalma.
- GDScript hatası `_ready()` fonksiyonunu yarıda kesiyor ve `get_tree().quit()` hiç çağrılmıyor. Headless Godot boş bir ana döngüde sonsuza kadar bekliyor, 300 sn sonra timeout geliyor.
- Hatadan önceki `print` satırları çıktıya düşüyor; buradaki ölçümde (stdout dosyaya yönlendirilmişti) görüldü. Daha önceki denemede çıktı görülmemesi büyük ihtimalle pipe tamponlamasından.

Diğer şüpheliler elendi:
- Dünya üretimi 206–256 ms sürüyor.
- `autoload/Watch.gd` bekçi thread'i 500 ms'de bir uyanıp sadece raporluyor, `quit()`'i engellemiyor. Bu klasördeki tüm sahneler normal çıkış yaptı.

Test kapısı (Dalga 1-A) için öneri: her test sahnesine bir güvenlik zamanlayıcısı eklenmeli (ör. 120 sn sonra `quit(1)`). Runner da `timeout` ile çağırmalı ve timeout'u hata saymalı. Böylece bir script hatası "sessiz sonsuz bekleme" yerine kırmızı sonuç olarak görünür.

## 6. Yeniden çalıştırma

```bash
# bir kez (yeni worktree):
/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64 --headless --path . --import
# tam ölçüm (~11 dk, 2 çekirdek): çıktılar tests/baseline/out/ altına
tests/baseline/run_baseline.sh
```

Tek tek çalıştırma:

| Sahne | Ne ölçer | Ortam değişkenleri | Süre |
|---|---|---|---|
| `res://tests/baseline/live_stats.tscn` | Canlı motor. Gerçek fikstürden maçlar `LiveEngine.setup(..., seed)` ve `run_to_end()` ile oynatılır; tabloya yazılmaz. | `N=200`, `LGS=SL,EN1,ES1,IT1,DE1`, `SEED=2301` | ~2,4 sn/maç |
| `res://tests/baseline/season_stats.tscn` | Bir sezon `end_week_auto()` ile oynatılır; Poisson skorları ve her haftanın ms süresi ölçülür. | `PLAN=0` (izlenmeyen) veya `PLAN=1` (her cumartesi oyuncunun liginden bir maç canlı izlenir), `SEED=2301` | ~15 sn / ~1,5 dk |
| `res://tests/baseline/probe.tscn` | Teşhis: `new_game`, `take_job`, `save` ve ilk 3 hafta süreleri | yok | ~3 sn |

Her sahne sonunda tek satır `RESULT_JSON {...}` basar ve `quit(0)` ile çıkar. `make_baseline.py` bu satırlardan `baseline.json`'ı üretir.

Notlar:
- Seed sabit olsa da ms süreleri makineye bağlıdır. Karşılaştırma aynı makinede ve aynı senaryoyla yapılmalı.
- Skor istatistikleri seed'e göre küçük oynar: Poisson için ±1 puan, canlı motor için 200 maçta ±3–4 puan (örneklem hatası).
- Sahneler `user://` kayıt dosyasını ezer. Bu yüzden ölçümler aynı anda çalıştırılmamalı.
- Dalga 1-B (isim temizliği) birleştikten sonra ölçüm bir kez tekrarlanacak (görev tanımı gereği). İsim değişikliği sayıları etkilememeli.
