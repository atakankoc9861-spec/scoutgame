"""Saha kenarı reklam panoları.
1) Kurgusal sponsorlar + "buraya reklam verin" tasarımları üretir (assets/ads/src/*.png, 1024x128)
2) assets/ads/src içindeki tüm görselleri (Gemini ad_house_*.png dahil) tek atlasta toplar: assets/ads/atlas.png
Gerçek bir reklamveren gelirse: 8:1 görselini assets/ads/src/ içine koy ve bu betiği çalıştır."""
import glob, math, os, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter
ROOT = "/home/claude/scout"
SRC = f"{ROOT}/assets/ads/src"
W, H = 1024, 128
F = lambda n, s: ImageFont.truetype(f"{ROOT}/fonts/{n}.ttf", s)

def grad(c1, c2, horiz=True):
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    n = W if horiz else H
    for i in range(n):
        t = i / (n - 1)
        c = tuple(int(c1[k] + (c2[k] - c1[k]) * t) for k in range(3))
        if horiz:
            d.line([(i, 0), (i, H)], fill=c)
        else:
            d.line([(0, i), (W, i)], fill=c)
    return im

def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def text_c(d, xy, t, font, fill, anchor="mm", shadow=None):
    if shadow:
        d.text((xy[0] + 3, xy[1] + 3), t, font=font, fill=shadow, anchor=anchor)
    d.text(xy, t, font=font, fill=fill, anchor=anchor)

def stripes(im, color, n=6, w=26, alpha=60, x0=0):
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for i in range(n):
        x = x0 + i * w * 2
        d.polygon([(x, H), (x + w, H), (x + w + 60, 0), (x + 60, 0)], fill=color + (alpha,))
    return Image.alpha_composite(im.convert("RGBA"), ov).convert("RGB")

def sponsor(name, sub, c1, c2, fg, mark, style):
    im = grad(hexc(c1), hexc(c2))
    if style == "stripes":
        im = stripes(im, (255, 255, 255), 5, 22, 28, 640)
    d = ImageDraw.Draw(im)
    fg = hexc(fg)
    # logo işareti
    cx, cy = 90, 64
    if mark == "bolt":
        d.polygon([(cx - 10, 18), (cx + 26, 18), (cx + 4, 58), (cx + 30, 58), (cx - 20, 112), (cx - 4, 70), (cx - 28, 70)], fill=fg)
    elif mark == "drop":
        d.ellipse([cx - 28, 46, cx + 28, 104], fill=fg)
        d.polygon([(cx, 14), (cx - 26, 66), (cx + 26, 66)], fill=fg)
    elif mark == "ring":
        d.ellipse([cx - 38, 26, cx + 38, 102], outline=fg, width=10)
        d.ellipse([cx - 12, 52, cx + 12, 76], fill=fg)
    elif mark == "wave":
        for k in range(3):
            pts = [(cx - 44 + i * 4, 40 + k * 22 + 8 * math.sin(i * 0.5)) for i in range(23)]
            d.line(pts, fill=fg, width=7)
    elif mark == "star":
        pts = []
        for i in range(10):
            r = 40 if i % 2 == 0 else 17
            a = -math.pi / 2 + i * math.pi / 5
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        d.polygon(pts, fill=fg)
    elif mark == "leaf":
        d.ellipse([cx - 40, 30, cx + 20, 100], fill=fg)
        d.line([(cx - 30, 92), (cx + 30, 26)], fill=hexc(c1), width=5)
    elif mark == "plane":
        d.polygon([(cx - 44, 70), (cx + 40, 54), (cx + 48, 60), (cx - 30, 80)], fill=fg)
        d.polygon([(cx - 4, 62), (cx + 16, 26), (cx + 26, 28), (cx + 14, 60)], fill=fg)
        d.polygon([(cx - 4, 70), (cx + 10, 104), (cx + 20, 102), (cx + 12, 72)], fill=fg)
    elif mark == "cup":
        d.rectangle([cx - 26, 36, cx + 22, 92], fill=fg)
        d.arc([cx + 8, 46, cx + 44, 80], -90, 90, fill=fg, width=8)
        for k in range(3):
            d.arc([cx - 18 + k * 14, 8, cx - 6 + k * 14, 34], 180, 360, fill=fg, width=4)
    d.line([(170, 22), (170, 106)], fill=fg + (0,), width=3)
    text_c(d, (590, 50), name, F("BarlowCondensed-ExtraBold", 76), fg, shadow=tuple(max(0, v - 70) for v in hexc(c1)))
    text_c(d, (590, 108), sub.upper(), F("Barlow-SemiBold", 18), fg)
    return im

def house(kind):
    if kind == 0:
        im = grad((10, 22, 48), (22, 40, 80))
        d = ImageDraw.Draw(im)
        d.rectangle([6, 6, W - 7, H - 7], outline=(201, 162, 74), width=3)
        text_c(d, (W // 2, 54), "MARKANIZ BURADA", F("Oswald-Bold", 64), (241, 230, 207))
        text_c(d, (W // 2, 104), "BU ALANDA REKLAM VEREBİLİRSİNİZ", F("Barlow-SemiBold", 22), (201, 162, 74))
        g = Image.new("RGB", (W, H))
        gd = ImageDraw.Draw(g)
        gd.ellipse([-60, -80, 160, 140], fill=(255, 240, 200))
        im = Image.blend(im, Image.composite(g, im, g.convert("L").filter(ImageFilter.GaussianBlur(30))), 0.35)
    elif kind == 1:
        im = Image.new("RGB", (W, H), (18, 120, 70))
        im = stripes(im, (255, 255, 255), 9, 30, 50, 380)
        d = ImageDraw.Draw(im)
        text_c(d, (430, 64), "BURAYA REKLAM VERİN", F("BarlowCondensed-ExtraBold", 74), (255, 255, 255), shadow=(8, 60, 30))
        d.ellipse([880, 18, 972, 110], fill=(255, 255, 255))
        for a in range(5):
            ang = a * 2 * math.pi / 5 - math.pi / 2
            px, py = 926 + 28 * math.cos(ang), 64 + 28 * math.sin(ang)
            d.ellipse([px - 11, py - 11, px + 11, py + 11], fill=(20, 20, 20))
    elif kind == 2:
        pap = Image.open(f"{ROOT}/assets/tex/paper.jpg").convert("RGB").resize((W, H))
        im = pap
        d = ImageDraw.Draw(im)
        st = Image.new("RGBA", (520, 110), (0, 0, 0, 0))
        sd = ImageDraw.Draw(st)
        sd.rectangle([4, 4, 515, 105], outline=(179, 38, 30, 230), width=6)
        sd.rectangle([16, 16, 503, 93], outline=(179, 38, 30, 200), width=2)
        sd.text((260, 56), "REKLAM ALANI", font=F("SpecialElite", 60), fill=(179, 38, 30, 230), anchor="mm")
        st = st.rotate(-4, expand=True)
        im.paste(st, (250, 2), st)
        d.text((80, 64), "Gözcü", font=F("Caveat-Bold", 54), fill=(31, 78, 140), anchor="mm")
        d.text((880, 64), "sponsor ol!", font=F("Caveat-Bold", 44), fill=(31, 78, 140), anchor="mm")
    elif kind == 3:
        im = grad((40, 8, 70), (14, 4, 30))
        d = ImageDraw.Draw(im)
        for x in range(0, W, 64):
            d.line([(x, 0), (x, H)], fill=(60, 20, 100))
        glow = Image.new("RGB", (W, H))
        gd = ImageDraw.Draw(glow)
        gd.text((W // 2, 62), "YOUR BRAND HERE", font=F("Oswald-Bold", 70), fill=(80, 240, 255), anchor="mm")
        im = Image.composite(Image.new("RGB", (W, H), (80, 240, 255)), im, glow.convert("L").filter(ImageFilter.GaussianBlur(8)).point(lambda v: min(255, v * 2)))
        d = ImageDraw.Draw(im)
        d.text((W // 2, 62), "YOUR BRAND HERE", font=F("Oswald-Bold", 70), fill=(225, 255, 255), anchor="mm")
    elif kind == 4:
        im = Image.new("RGB", (W, H))
        d = ImageDraw.Draw(im)
        cols = [(255, 200, 60), (255, 140, 40), (230, 70, 50), (150, 30, 60)]
        for i, c in enumerate(cols):
            d.rectangle([0, i * H // 4, W, (i + 1) * H // 4], fill=c)
        for x in range(0, W, 14):
            for y in range(0, H, 14):
                r = 3 if (x // 14 + y // 14) % 2 else 2
                d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 235, 200))
        text_c(d, (W // 2, 64), "SPONSOR OL", F("BarlowCondensed-ExtraBold", 96), (40, 20, 40), shadow=(255, 240, 220))
    else:
        im = Image.new("RGB", (W, H), (16, 16, 18))
        d = ImageDraw.Draw(im)
        for x in range(0, W, 6):
            for y in range(0, H, 6):
                if (x // 6 + y // 6) % 2 == 0:
                    d.rectangle([x, y, x + 2, y + 2], fill=(30, 30, 34))
        sweep = Image.new("L", (W, H), 0)
        sd = ImageDraw.Draw(sweep)
        sd.polygon([(560, 0), (640, 0), (520, H), (440, H)], fill=60)
        im = Image.composite(Image.new("RGB", (W, H), (255, 255, 255)), im, sweep.filter(ImageFilter.GaussianBlur(10)))
        d = ImageDraw.Draw(im)
        text_c(d, (W // 2 + 30, 64), "PREMIUM REKLAM ALANI", F("Oswald-Bold", 58), (210, 212, 218))
        d.polygon([(110, 86), (110, 46), (130, 64), (150, 40), (170, 64), (190, 46), (190, 86)], fill=(201, 162, 74))
    return im

SPONSORS = [
    ("KUZEY ENERJİ", "geleceğe güç", "#0b3d91", "#1565c0", "#ffd400", "bolt", "stripes"),
    ("SAFİR SU", "doğal kaynak", "#0a78b4", "#18b4e6", "#ffffff", "drop", "plain"),
    ("ATLAS BANK", "güvenin adresi", "#0e1620", "#23384d", "#f2aa4c", "ring", "plain"),
    ("TURBO GSM", "her yerde çeker", "#a8001f", "#e4002b", "#ffffff", "wave", "stripes"),
    ("YILDIZ ÇAY", "demi yerinde", "#7a0e12", "#b81e22", "#ffe066", "cup", "plain"),
    ("MAVİ HAVAYOLU", "dünyaya kanat", "#00264a", "#0a4c8a", "#7fd3ff", "plane", "stripes"),
    ("PİKSEL", "oyunun içinde", "#4a0f6a", "#8a2bb4", "#ffffff", "star", "plain"),
    ("YEŞİL VADİ", "tarladan sofraya", "#1b4d1f", "#3c8a3a", "#f4f1d0", "leaf", "plain"),
]

def build():
    os.makedirs(SRC, exist_ok=True)
    for i, s in enumerate(SPONSORS):
        sponsor(*s).save(f"{SRC}/sp_{i:02d}.png")
    for k in range(6):
        house(k).save(f"{SRC}/house_{k:02d}.png")

def atlas():
    files = sorted(glob.glob(f"{SRC}/*.png") + glob.glob(f"{SRC}/*.jpg"))
    # Gemini görseli aynı türün yerini alır (ad_house_N -> house_N-1)
    gem = {os.path.basename(f) for f in files if os.path.basename(f).startswith("ad_house_")}
    out = []
    for f in files:
        b = os.path.basename(f)
        if b.startswith("house_") and f"ad_house_{int(b[6:8]) + 1}.png" in gem:
            continue
        out.append(f)
    A = Image.new("RGB", (W, H * len(out)))
    for i, f in enumerate(out):
        A.paste(Image.open(f).convert("RGB").resize((W, H), Image.LANCZOS), (0, i * H))
    A.save(f"{ROOT}/assets/ads/atlas.png")
    with open(f"{ROOT}/assets/ads/count.txt", "w") as fh:
        fh.write(str(len(out)))
    print("atlas", len(out), "designs")

if __name__ == "__main__":
    build()
    atlas()
