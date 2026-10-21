# v0.23 Dalga 4: bot playtest (main f42b2aa)

Kurulum: 3 kariyer × 3 sezon, headless. 2 "iyi oyuncu" botu (seed 101 ve 202) ile 1 "tembel" bot (seed 101) oynadı. İyi oyuncu botu her hafta şunları yaptı: canlı motorla 2 maç izledi, hedeflere odaklandı, shortlist tuttu, video ve görüşme yaptı, rapor yazdı, ekip kurdu, başkana talep götürdü, olayları çözdü ve daha iyi teklif gelince kabul etti. Kayıt turları CHECK_STRICT_SAVE=1 ile yapıldı. Ham veri: bot/sonuclar.csv.

**Durum:** v0.23 teknik olarak sağlam: 0 hata, 0 NaN, 9/9 katı kayıt turu temiz. Ama itibar ilerlemesi bozuk: iyi oynayan bot 2. sezon sonunda itibar 88'e ve prestij 92'lik kulübe çıkıyor. Bu artışı raporlar değil manşetler sağlıyor.

## Kritik (yayın engeli)
1. **İtibar patlaması (manşet enflasyonu).**
   - İtibar: A botu 15→18→40→**96**, B botu 15→36→**88**→99,5.
   - Kulüp prestiji: A botu 52→59→87→92, B botu 48→64→92.
   - Manşet sayısı sezon başına 17–46. Her manşet +1 itibar, basın ilişkisi ≥70 olunca +0,5 daha. Basın ilişkisi 100'de kilitli.
   - Sebep: `disc_log`'a her odaklı maç izlemesi (A botunda 138), her ekip keşfi (85) ve her ihbar (27) giriyor. Hepsi `is_my_find` sayıldığı için star/callup/transfer manşeti tetikliyor. A botunun 3. sezonunda 22 star, 9 callup ve 3 transfer manşeti çıktı.
   - Öneri: manşeti yalnızca rapor yazılan veya ilk keşfi oyuncuya ait olan oyunculara bağla, sezon başına itibar katkısına tavan koy (ör. +6).
   - Sorumlu: gozcu-oyun-dengesi (Game.gd `_headline`, `_star_headlines`, `_callups`).
2. **Haber akışı taşıyor.**
   - Sezon başına 441–717 haber var, liste tavanı 160. Önemli haberler (görev süresi doldu, teklif) birkaç haftada akıştan düşüyor.
   - Seed 202'nin 3. sezonunda `kf_debut`=234, `kf_first_goal`=152 (önemli işaretli). `n_sacked` her sezon 47–69, bunların çoğu oyuncunun kulübü değil.
   - Öneri: kids_feed haberlerini yalnızca rapor yazılan oyunculardan üret ya da haftalık özet olarak ver. Başka kulüpteki hoca kovulmalarını tek haberde topla.
   - Sorumlu: gozcu-ui / gozcu-oyun-dengesi.

## Önemli
3. **Görevler iyi oyuncuda bile çoğunlukla düşüyor.**
   - Görev süresi dolması sezon başına 4–10 (6 sezonda 38 kez; sezon başına ortalama yaklaşık −12,7 itibar).
   - İmza+anlaşma sezon başına 0–4. Sign raporlarının 4/15'i reddedildi.
   - Prestij 92 kulüpte uygun aday kalmayınca B botu 3. sezonda 0 sign raporu yazdı ve 7 görev düştü. İtibar yine de manşetle 99,5'e çıktı.
   - Asıl ilerleme yolu (rapor → imza) itibarı düşürüyor, yan yol (manşet) taşıyor.
   - Sorumlu: gozcu-oyun-dengesi.
4. **Tembel oyuncu itibar 0'da kovulmuyor.**
   - Tembel bot 1. sezonda kovuldu (15→4). 2. ve 3. sezonda itibarı 0 olduğu hâlde kovulmadı.
   - Sebep: `_season_end` kuralı `rep < rep_start - 4` koşulunu arıyor, itibar 0 iken bu koşul imkânsız. Geriye yalnızca %60'lık "lazy" zarı kalıyor (iki sezon üst üste kovulmama ihtimali %16).
   - Ayrıca itibar <10 iken hiç teklif gelmiyor ve oyuncu küme düşen kulüpte (L1) sıkışıyor.
   - v0.22 ile karşılaştırma: beklenen "kovulma" davranışı yalnızca ilk sezonda tutuyor.
   - Sorumlu: gozcu-oyun-dengesi.
5. **Para enflasyonu.**
   - İyi oyuncu: 2.000 → 14–15 bin → 34–37 bin → 61–64 bin.
   - Tembel: 2.000 → 53 bin (hiç harcama yapmadan).
   - Takım elbise, ev ve araba 1. sezonda alınıyor, sonra kira dışında para çıkışı yok.
   - Maaş 3. sezonda tavana yakın: 826 (prestij 92 kulüp, `90+8×prestij`).
   - Öneri: sürekli para çıkışı ekle (kurs, ekip maaşının bir kısmı, yaşam kalemi kademeleri).
   - Sorumlu: gozcu-ekonomi.
6. **Reyting eşikleri hedef yüzdeliklerden kayık.**
   - Lig genelinde ≥8 maç oynayanlar içinde: report_good (7,3) üstü ortalama **%21** (aralık 17,6–25,3), hedef %14. report_bad (6,75) altı ortalama **%14** (aralık 9,9–17,5), hedef %10.
   - Rapor değerlendirmelerinde (n=13): 7 iyi, 1 kötü.
   - Olası sebep: kalibrasyon tüm ligler ve tüm sezon üzerinden yapıldı, oyunda ise Süper Lig hızlı motorla oynanıyor.
   - Sorumlu: gozcu-mac-motoru (sim_calib.json eşiklerini hızlı motor dağılımıyla yeniden üret).
7. **Efsane/söylenti mekaniği 2. sezondan sonra ölü.**
   - Söylenti sayısı sezonlara göre 18→6→0.
   - 6 efsanenin hepsi 2027–28'de "lost" oldu. Efsaneler kariyer başına bir kez tohumlanıyor (`legends_seeded`).
   - Not: bot ipuçlarını kovalamadı. Mekaniğin bitmesi ise bottan bağımsız.
   - Sorumlu: gozcu-oyun-dengesi.
8. **Hafta süresi bütçe sınırına geldi.**
   - Ekranı donduran kısım `play_day` + `finish_week`.
   - İyi oyuncu 3. sezonda medyan yaklaşık 556–575 ms (bütçe ≤563), en kötü 848+96 ms (bütçe ≤1.004).
   - `finish_week` sezonlara göre büyüyor: 354→398→481 ms (A botu).
   - Kayıt dosyası boyutu: 3,0→3,5→3,9 MB (iyi oyuncu, sezonda +450 KB), tembel botta 2,3→2,6 MB. Her hafta yazılan kayıt 250–380 ms sürüyor.
   - 2 canlı maç (izleyicide) ~5,1 s. Bu donma sayılmaz, çünkü kareler arasında akıyor.
   - Sorumlu: gozcu-performans (disc_log, kids_state ve hl_log budaması; kayıt boyutu).

## Küçük
9. **Aynı haber tekrarlanıyor.** `n_young_star` aynı oyuncu ve aynı ortalamayla bir sezonda 4–7 kez çıkıyor (3 haftada bir, en iyi genç değişmiyor). Sorumlu: gozcu-icerik.
10. **Göz becerisi erken doluyor.** Göz becerisi 3 sezonda 20'ye (tavan) ulaştı, bundan sonra ilerleme yok. Sorumlu: gozcu-oyun-dengesi.
11. **Aile ilişkisi düşük kalıyor.** İyi oyuncuda aile ilişkisi 20'de kalıyor (<30 olunca her hafta +6 yorgunluk). "Evde kal" seçimi bile toparlamıyor. Sorumlu: gozcu-oyun-dengesi.
12. **Watch.gd headless'ta yanlış alarm veriyor.** `watch_stall.txt` her koşuda yazıldı, ama içerik "CIZIM DURDU". Bu headless'ta çizim olmamasından kaynaklanıyor. Haftalık "donma bitti" kaydı ise test döngüsünün tek karede ilerlemesinden. Gerçek UI'da senkron kısım <1 s, yani gerçek bir donma görülmedi. Öneri: headless'ta bekçiyi kapat. Sorumlu: gozcu-performans.
13. **Ekip ipucu oranı iyi.** Veri analisti ipucu (`n_staff_data`) analist varken sezonda 12–21 kez çıktı. Scout ekip raporu haberi 11–48. Makul. İzlenen maç sakatlığı (yeni özellik) çalışıyor: sezonda 9–23 yeni sakat, yaklaşık 0,2 sakatlık/maç.

## v0.22 ile karşılaştırma
- **Daha iyi:** Kayıt v6 katı tur 9/9 temiz. NaN yok. Hızlı motor bağlantısı tutarlı. İzlenen maçlarda sakatlık var. Tembel bot 1. sezonda kovuluyor.
- **Daha kötü / yeni:** Yüzdelik eşiklerle birlikte star manşetleri ve `disc_log`'un büyümesi itibarı patlatıyor. Haber hacmi 3 katına çıkıyor (115 → 441–717).

Bot betiği: repo/tests/check/bot_play.gd (yalnızca kopyada).

## Ek: v0.23 öncesiyle karşılaştırma (koordinatör, 21 Ekim 2026)
Aynı "iyi oyuncu" botu (seed 202, 3 sezon) Dalga 3 öncesi kodda (efb2203, eski sabit eşiklerle):
- İtibar: önce 15 → 51 → 100 → 100 (2. sezon sonu tavan); v0.23: 15 → 36 → 88 → 99,5.
- Manşet/sezon: önce 30 / 51 / 52; v0.23: 18 / 32 / 46.
- Haber/sezon: önce 255 / 497 / 773; v0.23: 220 / 458 / 717.
Sonuç: itibar/manşet patlaması v0.23'ten ÖNCE de vardı (v0.23 biraz yumuşattı) → v0.24 denge işi. Not: raporda geçen gozcu-oyun-dengesi / gozcu-ekonomi / gozcu-ui = game-designer / economy-designer / design-ui-designer.
Bot betiği: bot_play.gd.txt (tests/check/ altına bot_play.gd olarak kopyalanıp .tscn ile çalıştırılır).
