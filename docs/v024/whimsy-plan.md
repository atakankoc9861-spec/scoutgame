# Gözcü v0.24 — "Vay be" anları planı (Whimsy Injector)

Sadece tasarım. Kod değişmedi. Kaynak: main @ f25ad15 (v0.23 Dalga 1).

## 0. Mevcut durum (ne zaten var, ne eksik)

| Var olan an | Nerede | Not |
|---|---|---|
| Kıvılcım "ŞİMDİ! / YAKALADIN! / kaçtı…" + `spark`/`catch` sesi + 60 ms titreşim | `ui/main.gd` `_spark_pop`, `_observe_phase` | **Hata:** `Input.vibrate_handheld(60)` doğrudan çağrılıyor, `kit.gd::_haptic` içindeki `settings.haptic` kapısını atlıyor. v0.24'te ilk düzeltilecek şey. |
| Efsane cevher kutlaması (dönen altın ışınlar) | `_legend_celebrate`, `Game.legend_seen` | Güçlü an, ama sesi yok. Sadece görsel. |
| Söylenti ipuçları (4 kademe) | `Game._v22_week`, `legend_clue_text` | Haber olarak düşüyor. Bunu "toplama" duygusuna çeviren bir yüzey yok. |
| Okuma serisi 5/10/20 | `Game.eye_streak` | Sadece haber + itibar. Ekranda bir an yok. |
| Çizgi roman hikâye panelleri (5 adet) | `_story`, `assets/story/*.jpg` | first_job / first_signing / first_headline / promoted / fired. Tek seferlik, iyi çalışıyor. |
| Manşetler (star/transfer/callup) + "ago" alanı | `Game._headline` | "X sezon önce gördün" verisi duruyor ama hiç gösterilmiyor. |
| Evlatlarım akışı (debut, ilk gol, 10 gol, transfer, teşekkür, vs) | `_kids_week`, `_kid_feed` | Metin akışı. Ritüel yok. |
| Kaçanlar Müzesi | `_museum_check` | Hüzünlü ve iyi. Görselleştirmesi zayıf. |
| Rozetler (uzmanlık, Güvenilir Kalem, Abartıcı) | `scout_badges`, `_check_badges` | Kazanıldığı an sessiz. |
| Toast (yaylanarak giren) | `_toast` | Tek tip. Ton yok. |
| Ses havuzu | `Sfx.FILES` | 17 dosya: crowd, roar, ooh, whistle, net, ring, pen, blip, spark, catch, stamp, page, cafe, field… Hepsi zaten var. Çoğu fikir yeni ses dosyası istemiyor. |

**Sonuç:** Oyunda "an" üretecek veri zaten var: `disc_log` keşfin hangi sezonda, kaç yaşında, kaç OVR'de yapıldığını tutuyor; `hl_log.ago` var; `kids_state` var; rapor geçmişi var. Eksik olan bir şey: **geçmişteki kararını bugüne bağlayan sahne.** Scout fantezisinin kalbi "ben demiştim". v0.24 bunu sahneye koymalı.

## 1. Ton kuralları

- **Ses:** Türkçe önce. Eski toprak bir scout'un defter dili kullanılır: kısa, kuru, hafif buruk, arada esprili. Ünlem azdır. Büyük anlar sessizlikle kurulur.
  - İyi: "Defterin haklı çıktı." / "Kimse bakmıyordu. Sen baktın."
  - Kötü: "TEBRİKLER!!! 🎉 Harika iş!"
- **Fiziksel nesne dili:** defter, kalem, mühür, kahve lekesi, gazete küpürü, bilet koçanı. Kıvılcım dışında neon ya da parıltı yok.
- **Seyreklik bütçesi:** Bir oyun haftasında en fazla **1 büyük an** (tam ekran) ve en fazla **2 küçük an** (toast/mikro animasyon). Büyük anlar sıraya alınır (`_check_popups` zaten bir kuyruk gibi çalışıyor) ve aynı hafta ikincisi gelirse bir sonraki haftaya kayar.
- **Her büyük an dokunarak geçilir.** Ayarlara tek bir anahtar eklenir: `settings.calm`. "Sakin mod" açıkken tam ekran anlar kart boyutuna iner, titreşim ve ışın animasyonu kapanır (azaltılmış hareket).
- **Gerçek isim yok.** Tüm metinler `pname()` ve `club().name` üzerinden gelir. Easter egg'ler gerçek oyunculara ya da kulüplere gönderme yapmaz.
- **Para:** Hiçbir an IAP ya da reklamla açılmaz, hızlanmaz ve güçlenmez. Kozmetik "hatıra" kanalı (aşağıda ♦ ile işaretli) en fazla bir kez, kutlama bittikten sonra ve kapatılabilir şekilde gösterilir.

## 2. Aday liste (22 an, öncelik sırasıyla)

Efor: S = en fazla yarım gün, M = 1–2 gün, L = 3 gün ve üzeri. Rahatsızlık riski: Düşük / Orta / Yüksek.

### A. Keşif anları (fantezinin çekirdeği)

**1. "Defterin haklı çıktı" — ilk patlama sahnesi** · M · Risk: Düşük
- **Görülen:** Ekran kararır. Eski defter sayfası kayarak gelir: senin el yazınla ilk raporun, tarih damgası ("2. sezon, 14. hafta — 16 yaşında, OVR 47") ve o gün yazdığın tek satır not. `page` sesi duyulur. Ardından sayfanın üstüne bugünün gazete küpürü yapışır ("…milli takıma çağrıldı" / "OVR 71"). `stamp` sesiyle kırmızı mühür basılır: **"HAKLI ÇIKTIN"**. Kısa titreşim. Altta kuru bir kapanış satırı: "Kimse bakmıyordu. Sen baktın."
- **Tetik:** Bir `_headline` (star/callup/transfer) çağrısında oyuncu `disc_log`'da varsa ve `ago >= 1` ise. Her oyuncu için yalnızca **ilk** manşette çalışır (`hl_log` buna bakılarak kontrol edilir).
- **Seyreklik:** Doğası gereği seyrek: sezonda birkaç tane. Aynı haftada ikinci bir tane gelirse küçük karta iner. Mevcut `story_first_headline` paneli kariyerdeki ilk sefer için kalır, bu sahne onun ardından her oyuncu için çalışır.

**2. "Tahmin tuttu" mühür animasyonu** · S · Risk: Düşük
- **Görülen:** Oyuncu dosyasındaki rapor kartında, verdiğin potansiyel aralığı gerçekleşince kart üstüne eğik bir mühür iner: `stamp` sesi, küçük bir sarsıntı ve "İSABET" yazısı. Iska olursa mühür basılmaz, aralık sessizce grileşir. Ceza animasyonu yok.
- **Tetik:** `acc` (isabet) hesabı yapılırken, raporlanan oyuncunun gerçekleşen OVR'si raporlanan aralığın içine düştüğünde.
- **Seyreklik:** Sadece oyuncu dosyası açıldığında oynar. Her rapor için bir kez (`seen` bayrağı tutulur).

**3. Efsane kutlamasına ses ve "ipucu panosu"** · M · Risk: Düşük
- **Görülen:** Duvarda mantar pano durur. Her söylenti ipucu bir post-it olarak iğnelenir (ülke → mevki/ayak → yaş/imza özellik → şehir/kulüp). Dört ipucu tamamlandığında post-it'ler arasına kırmızı ip çekilir. Efsane bulunduğunda mevcut altın ışınlara bir `roar` dalgası ve ardından `whistle` eklenir.
- **Tetik:** `_v22_week` ipucu ekledikçe pano güncellenir. Kutlama `legend_pop` üzerinden gelir.
- **Seyreklik:** Pano pasif bir ekran, sadece bakmak isteyen açar. Kutlama kariyer başına en fazla 6 kez olur.

**4. "Kaçan balık" müze anı (hüzünlü ama tatlı)** · S · Risk: Düşük
- **Görülen:** Sezon sonu özetinde müzeye giren oyuncu, fotoğraf köşeli bir vitrin kartıyla gösterilir: "Onu 2. sezonda, 15 yaşında gördün. Şimdi OVR 78." `page` sesi çalar. Kartın altında küçük not: "Bir dahaki sefere."
- **Tetik:** `_museum_check` çıktısı (`summ.museum`).
- **Seyreklik:** Sezonda en fazla 3 oyuncu (kod zaten sınırlıyor). Hepsi tek kartta toplanır, tek dokunuşla geçilir.

**5. İlk maç / ilk gol bildirimi: "Evladın sahada"** · S · Risk: Orta
- **Görülen:** `kf_debut` ve `kf_first_goal` olaylarında toast yerine küçük bir "bilet koçanı" kartı yukarı kayar. Uzak bir tribün sesi (`crowd_hi`, kısık) duyulur. Kartta "İlk golü! Sen onu 16'sında gördün." yazar.
- **Tetik:** `_kid_feed` ile key ∈ {kf_debut, kf_first_goal}.
- **Seyreklik:** Haftada en fazla 1 kart. Fazlası "Evlatlarım"a sessizce düşer. Ayarlarda "Evlat bildirimleri: hepsi / önemliler / kapalı" seçimi olur.

**6. Kendi keşfine karşı maç izlemek ("kf_vs" sahnesi)** · M · Risk: Düşük
- **Görülen:** İzlediğin maçta karşı takımda senin keşfettiğin bir oyuncu varsa, maç başlarken kadro listesinde adının yanında küçük bir kalem ikonu belirir. O oyuncu gol atarsa ya da kurtarış yaparsa ekrana tek satır düşer: "Bu sendin." Kuru, buruk bir ton.
- **Tetik:** Maç verisinin kadrosu `disc_log` ile kesişiyorsa ve oyuncu artık senin kulübünde değilse.
- **Seyreklik:** Maç başına en fazla 1 satır.

**7. "Gizli cevher" ilk sezgi anı** · S · Risk: Orta
- **Görülen:** Alt ligde ya da U19 maçında bir oyuncuya ilk kez odaklandığında, bilinen potansiyel aralığının üst ucu bilinen OVR'sinin +20 üstündeyse, oyuncu satırında defter kenarına kurşun kalemle bir yıldız karalanır (`pen` sesi). Yanında "Bir şeyi var." notu belirir (mevcut `kid_any` metni kullanılır).
- **Tetik:** `observe()` sonrası `pa_range` hi − `ovr` ≥ 20 ve tier ≥ 2 ya da youth koşulu sağlanıyorsa. Oyuncu başına bir kez.
- **Seyreklik:** Kalem karalaması küçük ve sessiz bir an. Tam ekran olmaz.

### B. Mikro animasyon ve his

**8. Okuma serisi: kalem ısınıyor** · S · Risk: Düşük
- **Görülen:** Seri 3'ü geçince kıvılcım sayacının (`✦ n`) yanındaki kalem ikonu turuncuya döner. 5, 10 ve 20'de sayaç bir kez zıplar ve `blip` sesi perdeyi yükselterek çalar (`play()` içindeki `_pitch` parametresi şu an kullanılmıyor, açılması gerekir). Seri kırılınca kalem sessizce soğur. "Seri kırıldı!" gibi bir ceza mesajı çıkmaz.
- **Tetik:** `eye_streak` dönüşü.
- **Seyreklik:** Sadece gözlem fazında görülür.

**9. Rapor gönderme ritüeli** · S · Risk: Düşük
- **Görülen:** "Gönder" butonuna basınca rapor kâğıdı katlanır, zarfa girer ve zarfa mühür basılır (`page` → `stamp`). Toplam 0,6 saniye sürer ve dokunarak atlanabilir.
- **Tetik:** `submit_report`.
- **Seyreklik:** Her gönderimde oynar ama çok kısa. Sakin modda sadece mühür sesi kalır.

**10. Rozet kazanma: dikiş işlenir** · S · Risk: Düşük
- **Görülen:** Yeni rozet kazanıldığında kimlik kartında (`_id_badge`) rozet ilmek ilmek dikilerek belirir. Mevcut deri/dikiş stili (`_stitch`) kullanılır. `pen` sesi çalar, ardından şu toast gelir: "Yeni rozet: Güvenilir Kalem."
- **Tetik:** `_check_badges` yeni bir id döndürdüğünde. "Abartıcı" için ayrı bir hal: rozet dikilmez, kırmızı kalemle karalanır. Hafif öz-ironi.
- **Seyreklik:** Doğal olarak seyrek.

**11. Hava durumuna duyarlı defter** · S · Risk: Düşük
- **Görülen:** Yağmurlu maçtan sonra yazılan raporun kenarında hafif bir su lekesi, karlı maçta soğuk mavi bir ton belirir. Defterde gezinirken o maçı hatırlatır.
- **Tetik:** `data.cond` (mevcut `pick_cond`) rapor kaydına yazılır.
- **Seyreklik:** Tamamen pasif bir süs, rahatsız etme riski yok.

**12. Titreşim dili (haptic sözlüğü)** · S · Risk: Düşük
- **Görülen ve hissedilen:** Üç desen tanımlanır: *tık* (12 ms, buton), *yakaladın* (60 ms), *büyük an* (40 ms + 80 ms boşluk + 90 ms). Hepsi `kit._haptic` üzerinden geçer, böylece ayar kapısı herkes için çalışır.
- **Tetik:** Kıvılcım, mühür ve efsane anlarında.
- **Seyreklik:** Ayarla tamamen kapatılabilir. Mevcut kapı atlama hatası da bu işle düzeltilir.

### C. Sürpriz olaylar ve nadir anlatı

**13. Eski hoca telefonu** · M · Risk: Orta
- **Görülen:** Telefon çalar (`ring`). Arayan, yıllar önce senin bulduğun bir oyuncunun ilk antrenörü (kurgu NPC). Konuşma 2–3 satır sürer: "O çocuğu ilk sen fark etmiştin. Şimdi elimde bir tane daha var… gel bir bak." Sonunda bir U19 oyuncusu için 1 ipucu verir. Ödül küçük ama hikâye değeri yüksek.
- **Tetik:** Keşfettiğin bir oyuncu için `n_hl_star` ya da `n_hl_callup` sonrasında, %25 şansla, en erken 4 hafta sonra.
- **Seyreklik:** Sezonda en fazla 1. Reddedilebilir ("Şu an olmaz").

**14. Yağmurda boş tribün** · S · Risk: Düşük
- **Görülen:** Kötü havada bir U19 ya da 4. lig maçında tribün neredeyse boş. Maç başında tek satır: "Tribünde sen, bir köpek ve iki veli." `field` ambiyansı ve uzaktan bir havlama duyulur (havlama yeni ses dosyası ister, istenmezse sadece metin). Bu maçta kıvılcım şansı +1 olur: kimse bakmazken bakan kazanır.
- **Tetik:** Youth ya da tier ≥ 4 maç, `cond` yağmur/kar ve %30 şans.
- **Seyreklik:** Doğal olarak seyrek, sadece bir metin satırı.

**15. Sezonun "en eski not" anı** · S · Risk: Düşük
- **Görülen:** Sezon sonu özetine bir defter sayfası eklenir: bu sezon en çok yükselen keşfin ve onun hakkında ilk yazdığın not birebir alıntılanır. Başlık: "Bu sezonun cümlesi."
- **Tetik:** `_season_end`, `disc_log` içinde en büyük OVR artışı.
- **Seyreklik:** Sezonda 1.

**16. Menajerin kıskanç mesajı** · S · Risk: Orta
- **Görülen:** Rakip kulübün scout'u, kaçırdığı oyuncunu senin kaptığını öğrenir ve kısa, esprili bir SMS atar: "Bu sefer senindi. Bir dahakine kahveler benden." Rakip ilişkisine ufak bir tat katar.
- **Tetik:** `rush_report` ile rakibin önüne geçip imza alındığında (`first_signing` sonrası, rakipli transferlerde).
- **Seyreklik:** Sezonda en fazla 2.

**17. 100. rapor / 1000. dakika kilometre taşları** · S · Risk: Düşük
- **Görülen:** Defterin ilk sayfası kapak olarak kısa süre gösterilir: kahve lekeleri ve yıpranma, rapor sayısıyla artar (görsel aşınma 25/100/250 eşiklerinde). Altta: "100 rapor. Kalem eskidi, göz keskinleşti."
- **Tetik:** Toplam rapor sayısı eşikleri.
- **Seyreklik:** Kariyer boyunca 4–5 kez.

### D. Koleksiyon ve ritüel

**18. Bilet koçanı albümü** · M · Risk: Düşük
- **Görülen:** İzlenen her maç için bir bilet koçanı saklanır: tarih, stad adı (kurgu), hava ikonu ve o maçta yakalanan kıvılcım sayısı. Bir efsane ya da büyük keşif o maçta yapıldıysa koçan altın kenarlı olur. Albüm "Arşiv" altında, kaydırılarak gezilir.
- **Tetik:** `finish_live` ve `finish_video`.
- **Seyreklik:** Pasif bir koleksiyon, rahatsız etme riski yok.
- ♦ **Hatıra hook (isteğe bağlı):** Albümde kozmetik "koçan çerçeve" stilleri olabilir. Mevcut tema modeli (reklam izle ya da `supporter`) burada da kullanılır. Hiçbir oynanış avantajı vermez.

**19. "İlk 11'im" hatıra kartı** · M · Risk: Düşük
- **Görülen:** `finds_xi_card` zaten var. Buna "Fotoğraf çek" butonu eklenir: kart deri çerçeveli bir görsel olarak kaydedilir ya da paylaşılır (Android share intent). Tüm isimler kurgu olduğu için paylaşmak güvenli.
- **Tetik:** Kullanıcı isteğiyle.
- **Seyreklik:** Sıfır, tamamen kullanıcı başlatır.

**20. Pazartesi kahvesi** · S · Risk: Orta
- **Görülen:** Haftanın ilk açılışında ofiste kahve fincanından buhar çıkar (`cafe` ambiyansı 2 saniye) ve fincan altlığına bu hafta bir söylenti ya da evlat haberi varsa tek satır yazılır.
- **Tetik:** `end_week_auto` sonrası ilk hub açılışı.
- **Seyreklik:** Ses kısa ve haftada bir kez. Sakin modda kapalı.

### E. Easter egg

**21. Logoya 7 dokunuş: eski kalem** · S · Risk: Düşük
- **Görülen:** Başlık ekranındaki logoya 7 kez dokununca bir dolma kalem yazı tipi açılır ("Eski Usul" not stili). Sadece kozmetik bir değişiklik. Bir kez açılır, ayarlardan kapatılabilir.
- **Tetik:** Gizli dokunuş sayacı.
- **Seyreklik:** Sadece arayan bulur.

**22. Kaleci efsanesi özel repliği** · S · Risk: Düşük
- **Görülen:** Efsane kalecisi (`sig == reflexes`) bulunduğunda kutlama metni değişir: "Kaleciyi kimse aramaz. Sen aradın." Kalecilere küçük bir saygı.
- **Tetik:** `legend_seen` ile `lg.sig == "reflexes"`.
- **Seyreklik:** Kariyer başına en fazla 1.

## 3. Yapılmaması gerekenler

- Günlük giriş ödülü, "seri kaybetme" korkusu ya da sayaçlı FOMO. Okuma serisi oyun içi bir beceri, takvim serisi değil.
- Kutlamanın ortasında reklam ya da IAP teklifi göstermek.
- Kozmetik dışında herhangi bir şeyin ücretli olması (ör. "ipucunu hemen aç").
- Her rapor sonrası konfeti. Seyreklik bu planın ana gücü.
- Gerçek futbolculara ya da kulüplere gönderme yapan easter egg'ler.

## 4. v0.24 "olmazsa olmaz" ilk 5

| # | An | Efor | Neden |
|---|---|---|---|
| 1 | **"Defterin haklı çıktı" sahnesi** (#1) | M | Scout fantezisinin özü. Geçmiş kararı bugüne bağlar. Veri hazır (`disc_log`, `hl_log.ago`). Mevcut story/headline akışına oturur. |
| 2 | **"Tahmin tuttu" mühür** (#2) | S | Raporlamaya duygusal geri bildirim verir. İsabeti (`acc`) görünür kılar, böylece oyuncu daha dikkatli rapor yazar. Ses (`stamp`) zaten var. |
| 3 | **Titreşim sözlüğü ve ayar kapısı düzeltmesi** (#12) | S | Diğer bütün anların altyapısı. `_spark_pop` içindeki doğrudan `vibrate_handheld` çağrısı ayarı yok sayıyor. Bu hem hata hem de bir güven meselesi. |
| 4 | **Efsane ipucu panosu ve kutlama sesi** (#3) | M | v0.22'nin en güçlü sistemi şu an haberlerin arasında kayboluyor. Pano, haftalık söylentileri bir toplama ritüeline çevirir ve geri dönme sebebi yaratır. |
| 5 | **Evladın sahada kartı ve bildirim seviyesi** (#5) | S | Uzun vadeli bağı canlı tutar ("benim çocuğum oynadı"). Evlatlarım akışına bir yüz verir. Bildirim seviyesi ayarı rahatsızlığı baştan çözer. |

**Ortak altyapı (ilk 5 için gerekli):** (a) Haftalık "an kuyruğu" ve seyreklik bütçesi: `_check_popups` üzerine haftada 1 büyük an sınırı. (b) `settings.calm` (sakin mod, azaltılmış hareket). (c) `Sfx.play` içinde `_pitch` parametresinin gerçekten uygulanması. (d) Tüm metinler T.gd'de TR ve EN olarak, Türkçe önce yazılır.

**Yeni ses dosyası:** İlk 5 için gerekmiyor. Hepsi mevcut `page`, `stamp`, `roar`, `whistle`, `crowd_hi`, `pen` ve `blip` ile yapılıyor.
**Toplam efor tahmini (ilk 5 + altyapı):** yaklaşık 5–7 geliştirici günü.

**Bir sonraki dalgaya önerilenler:** #18 Bilet koçanı albümü (koleksiyon ve tasteful kozmetik hook), #13 Eski hoca telefonu, #15 Bu sezonun cümlesi.
