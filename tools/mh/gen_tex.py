## Cilt detay dokusu: R dudak, G kaş, B sakal, A saç dibi (kafa derisi)
import numpy as np
from PIL import Image, ImageFilter
N = 1024
d = np.load("/home/claude/mh/out/body_tris.npz")
tris = d["tris"]; EYE = d["eye"]; H = float(d["H"])
ex, ey, ez = EYE
rng = np.random.default_rng(7)
def noise(scale, seed):
    r = np.random.default_rng(seed)
    a = r.random((N // scale + 2, N // scale + 2)).astype(np.float32)
    im = Image.fromarray((a * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32) / 255.0
def strokes(seed, horiz=True):
    ## kıl dokusu: yönlü ince çizgiler
    r = np.random.default_rng(seed)
    a = r.random((N, N)).astype(np.float32)
    im = Image.fromarray((a * 255).astype(np.uint8))
    im = im.filter(ImageFilter.GaussianBlur(0.6))
    k = ImageFilter.BoxBlur(0)
    arr = np.asarray(im, dtype=np.float32) / 255.0
    # yatay bulanıklık = kıl yönü
    from numpy.lib.stride_tricks import sliding_window_view
    pad = np.pad(arr, ((0, 0), (3, 3)), mode="wrap") if horiz else np.pad(arr, ((3, 3), (0, 0)), mode="wrap")
    w = sliding_window_view(pad, 7, axis=1 if horiz else 0).mean(-1)
    w = (w - w.mean()) / (w.std() + 1e-6)
    return np.clip(0.5 + w * 0.35, 0, 1)

def smooth01(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

def masks(P):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    ax = np.abs(x)
    front = y < ey + 0.03
    # kaş: göz merkezinin üstünde, iç uçtan dış uca kalınlaşan/incelen bant
    bx = (ax - 0.012) / 0.05           # 0 iç uç, 1 dış uç
    bz = z - (ez + 0.024 + 0.006 * np.sin(np.clip(bx, 0, 1) * 3.14) - 0.004 * bx)
    thick = 0.0058 * (1.15 - 0.55 * np.clip(bx, 0, 1))
    brow = smooth01(-np.abs(bz), -thick, -thick * 0.35) * smooth01(bx, -0.05, 0.08) * (1 - smooth01(bx, 0.85, 1.05)) * front * (y < ey - 0.005)
    # sakal: çene, yanak altı, bıyık
    chin_z = ez - 0.125
    jaw = smooth01(z, chin_z - 0.035, chin_z - 0.01) * (1 - smooth01(z, ez - 0.06, ez - 0.04))
    cheek_cut = 1 - smooth01(ax, 0.055, 0.075) * smooth01(z, ez - 0.075, ez - 0.05)
    mustache = smooth01(z, ez - 0.085, ez - 0.078) * (1 - smooth01(z, ez - 0.066, ez - 0.06)) * (1 - smooth01(ax, 0.022, 0.03))
    beard = np.clip(jaw * cheek_cut + mustache, 0, 1) * (y < ey + 0.075)
    beard *= 1 - smooth01(ax, 0.07, 0.085) * (z > ez - 0.1)
    # boyun altı: sakal boyna hafif iner
    neck = smooth01(z, chin_z - 0.06, chin_z - 0.03) * (1 - smooth01(z, chin_z - 0.01, chin_z + 0.005)) * (y < ey + 0.05) * 0.6
    beard = np.maximum(beard, neck)
    # kafa derisi (kısa saç dibi)
    c = np.array([0.0, ey + 0.085, ez])
    dx, dy = x - c[0], y - c[1]
    hl = np.sqrt(dx * dx + dy * dy) + 1e-6
    fr = -dy / hl
    sd = np.abs(dx) / hl
    thr = ez + 0.05 * np.maximum(0, fr) - 0.075 * np.maximum(0, -fr) + 0.012 * sd * (1 - np.abs(fr))
    ear = (sd > 0.8) & (z < ez + 0.03) & (np.abs(dx) > 0.06)
    scalp = smooth01(z, thr - 0.006, thr + 0.006) * (~ear) * (z > ez - 0.12)
    return brow, beard, scalp

img = np.zeros((N, N, 4), dtype=np.float32)
cnt = 0
for t in tris:
    P = t[:, :3]; UV = t[:, 3:5]
    if P[:, 2].max() < ez - 0.2:
        continue
    px = UV[:, 0] * N
    py = (1 - UV[:, 1]) * N
    x0, x1 = int(np.floor(px.min())), int(np.ceil(px.max()))
    y0, y1 = int(np.floor(py.min())), int(np.ceil(py.max()))
    x0, y0 = max(0, x0 - 1), max(0, y0 - 1)
    x1, y1 = min(N - 1, x1 + 1), min(N - 1, y1 + 1)
    if x1 < x0 or y1 < y0:
        continue
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    (ax_, ay), (bx_, by), (cx_, cy) = (px[0], py[0]), (px[1], py[1]), (px[2], py[2])
    den = (by - cy) * (ax_ - cx_) + (cx_ - bx_) * (ay - cy)
    if abs(den) < 1e-9:
        continue
    w0 = ((by - cy) * (gx - cx_) + (cx_ - bx_) * (gy - cy)) / den
    w1 = ((cy - ay) * (gx - cx_) + (ax_ - cx_) * (gy - cy)) / den
    w2 = 1 - w0 - w1
    eps = -0.04
    inside = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
    if not inside.any():
        continue
    Pp = w0[..., None] * P[0] + w1[..., None] * P[1] + w2[..., None] * P[2]
    br, bd, sc = masks(Pp)
    sl = (slice(y0, y1 + 1), slice(x0, x1 + 1))
    for ch, val in ((1, br), (2, bd), (3, sc)):
        cur = img[sl][..., ch]
        img[sl][..., ch] = np.where(inside, np.maximum(cur, val), cur)
    cnt += 1
print("tris rasterized", cnt)
# kıl dokusu
fine0 = np.random.default_rng(12).random((N, N)).astype(np.float32)
img[..., 1] = np.asarray(Image.fromarray((img[..., 1] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), dtype=np.float32) / 255.0
img[..., 1] *= np.clip(0.7 + (strokes(3, True) - 0.5) * 0.25 + (fine0 - 0.5) * 0.35, 0, 1)
fine = np.random.default_rng(11).random((N, N)).astype(np.float32)
img[..., 2] = np.asarray(Image.fromarray((img[..., 2] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.0)), dtype=np.float32) / 255.0
img[..., 2] *= np.clip(0.35 + fine * 0.65, 0, 1)
img[..., 3] = np.asarray(Image.fromarray((img[..., 3] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), dtype=np.float32) / 255.0
img[..., 3] *= np.clip(0.6 + fine * 0.4, 0, 1)
# dudak: MPFB maskesi
lips = np.asarray(Image.open("/tmp/claude-0/mpfb2/src/mpfb/data/textures/mpfb_lips.jpg").convert("L").resize((N, N), Image.BILINEAR), dtype=np.float32) / 255.0
img[..., 0] = lips
out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA")
out.save("/home/claude/mh/out/skin_detail.png")
# ikinci doku: R göz kapağı gölgesi, G kulak, B tırnak, A gözenek/lekeler
lid = np.asarray(Image.open("/tmp/claude-0/mpfb2/src/mpfb/data/textures/mpfb_eyelids.jpg").convert("L").resize((N, N)), dtype=np.float32) / 255.0
ear = np.asarray(Image.open("/tmp/claude-0/mpfb2/src/mpfb/data/textures/mpfb_ears.jpg").convert("L").resize((N, N)), dtype=np.float32) / 255.0
nail = np.maximum(np.asarray(Image.open("/tmp/claude-0/mpfb2/src/mpfb/data/textures/mpfb_fingernails.jpg").convert("L").resize((N, N)), dtype=np.float32), np.asarray(Image.open("/tmp/claude-0/mpfb2/src/mpfb/data/textures/mpfb_toenails.jpg").convert("L").resize((N, N)), dtype=np.float32)) / 255.0
pores = np.clip(0.5 + (noise(2, 9) - 0.5) * 0.35 + (noise(24, 10) - 0.5) * 0.5, 0, 1)
img2 = np.stack([lid, ear, nail, pores], -1)
Image.fromarray((img2 * 255).astype(np.uint8), "RGBA").save("/home/claude/mh/out/skin_detail2.png")
print("ok")
