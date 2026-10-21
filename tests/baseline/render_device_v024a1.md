# Cihaz perf ölçümü — v0.24-a1 (Atakan'ın telefonu, 21 Ekim 2026)
Gizli perf satırı (sol üst 5 dokunuş). Telefon 120 Hz ekranlı, üst-orta/üst segment.

| Görünüm | draw call | üçgen | obj | tex | vram | proc | fps |
|---|---|---|---|---|---|---|---|
| Büyük stadyum, yakın kamera ("Oyuncu") | 192 | 61k | 414 | 97 MB | 154 MB | 8.2 ms | 120 |
| Büyük stadyum, yayın kamerası ("Yayın") | 330 | 199k | 538 | 97 MB | 154 MB | 7.4 ms | 120 |
| U19 küçük saha (ağaçlar/binalar), tribün kamerası | 378 | 234k | 619 | 98 MB | 151 MB | 8.9 ms | 120 |

Notlar:
- Bu telefonda sorun yok (120 fps, proc < 9 ms). Orta segment Android hedefi dc ≤ 300 — yayın kamerası (330) ve özellikle U19/küçük saha (378) üstünde.
- En ağır sahne küçük saha: ağaç/bina dekorları büyük stadyumdan pahalı → Dalga 5B (atmosfer) öncesi dekor birleştirme/MultiMesh adayı.
- tex ~97 MB: masaüstü ölçümü (~39 MB) ile farklı; mobil sıkıştırma/mipmap farkı — Faz 0 bütçe tablosuna bu cihaz değerleri referans alınmalı.
- Atakan görsel bozulma bildirmedi (yüz/dudak/kaş maskeleri dahil).
