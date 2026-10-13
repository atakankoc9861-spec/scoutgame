"""Gemini/Grok çıktılarını oyun dokularına çevirir. Girdi: /home/claude/scout_assets_in"""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
SRC = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/scout_assets_in"
DST = sys.argv[2] if len(sys.argv) > 2 else "/home/claude/scout/assets/tex"
FONT = "/home/claude/scout/fonts/BarlowCondensed-ExtraBold.ttf"

def save(im, name, q=88):
    im.save(f"{DST}/{name}", quality=q)

# çim: 1024 (8 biçme şeridi = 42 m)
save(Image.open(f"{SRC}/pitch_grass.jpg").convert("RGB"), "grass.jpg")
# seyirci: 2048x512
c = Image.open(f"{SRC}/crowd_strip.jpg").convert("RGB")
c = c.crop((0, int(c.height * 0.2), c.width, c.height))   # üstteki korkuluk/pankart kısmını at
save(c.resize((2048, 512), Image.LANCZOS), "crowd.jpg")
# gökyüzü: 2048x512 (yalnız üst yarıküre)
s = Image.open(f"{SRC}/sky_day.jpg").convert("RGB")
save(s.resize((2048, 1024), Image.LANCZOS), "sky_day.jpg")
# gece şehri: pencere çerçevelerini at (orta-sağ cam)
n = Image.open(f"{SRC}/city_night.jpg").convert("RGB")
W, H = n.size
save(n.crop((int(W * 0.31), int(H * 0.03), int(W * 0.632), int(H * 0.88))).resize((768, 744), Image.LANCZOS), "city_night.jpg")
# kâğıt/deri/mantar: arayüz ve masa
for f, o, sz in [("paper_cream.jpg", "paper.jpg", (1024, 560)), ("paper_manila.jpg", "manila.jpg", (768, 768)),
                 ("cork_board.jpg", "cork.jpg", (768, 768)), ("leather_dark.jpg", "leather.jpg", (768, 768))]:
    save(Image.open(f"{SRC}/{f}").convert("RGB").resize(sz, Image.LANCZOS), o, 85)
# key art: yükleme ekranı (dikey kırpım + yatay)
k = Image.open(f"{SRC}/key_art.jpg").convert("RGB")
save(k, "key_art.jpg", 90)
# ikon: iç çerçeveyi at
i = Image.open(f"{SRC}/icon.webp").convert("RGB")
w, h = i.size
m = int(w * 0.085)
i = i.crop((m, m, w - m, h - m)).resize((512, 512), Image.LANCZOS)
i.save("/home/claude/scout/icon.png")
i.resize((192, 192), Image.LANCZOS).save(f"{DST}/icon_192.png")

# LED reklam şeridi: kurgusal sponsorlar
SP = [("KUZEY ENERJİ", "#0b3d91", "#ffd400"), ("SAFİR SU", "#0aa1dd", "#ffffff"), ("ATLAS BANK", "#101820", "#f2aa4c"),
      ("TURBO GSM", "#e4002b", "#ffffff"), ("DEMİR OTO", "#2b2b2b", "#e8e8e8"), ("PİKSEL", "#7a1fa2", "#ffffff"),
      ("MAVİ HAVAYOLU", "#003b6f", "#7fd3ff"), ("YILDIZ ÇAY", "#a4161a", "#ffe066")]
PW, PH = 512, 64
img = Image.new("RGB", (PW * len(SP), PH))
d = ImageDraw.Draw(img)
fnt = ImageFont.truetype(FONT, 50)
for k2, (t, bg, fg) in enumerate(SP):
    x0 = k2 * PW
    d.rectangle([x0, 0, x0 + PW, PH], fill=bg)
    tw = d.textlength(t, font=fnt)
    d.text((x0 + (PW - tw) / 2, 4), t, font=fnt, fill=fg)
img.save(f"{DST}/ads.png")
print("ok")
