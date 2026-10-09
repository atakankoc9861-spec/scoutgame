## Gerçekçi futbolcu üretici (MPFB / MakeHuman CC0 verisi)
import sys, bpy, importlib, bmesh, json, math
import addon_utils
from mathutils import Vector
argv = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
cfg = json.loads(argv[0]) if argv else {}
out = cfg.get("out", "/home/claude/mh/out/p0.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
P = "bl_ext.user_default.mpfb"
HumanService = importlib.import_module(P + ".services.humanservice").HumanService
TargetService = importlib.import_module(P + ".services.targetservice").TargetService
HOP = importlib.import_module(P + ".entities.objectproperties").HumanObjectProperties

h = HumanService.create_human()
macro = {"gender": 1.0, "age": 0.5, "muscle": 0.8, "weight": 0.45, "height": 0.6, "proportions": 0.8,
         "caucasian": 1.0, "african": 0.0, "asian": 0.0}
macro.update(cfg.get("macro", {}))
for k, v in macro.items():
    HOP.set_value(k, v, entity_reference=h)
TargetService.reapply_macro_details(h)
rig = HumanService.add_builtin_rig(h, "game_engine")

def bake_keys(o):
    if o.data.shape_keys:
        o.shape_key_add(name="mix", from_mix=True)
        for kb in list(o.data.shape_keys.key_blocks):
            if kb.name != "mix":
                o.shape_key_remove(kb)
        o.shape_key_remove(o.data.shape_keys.key_blocks["mix"])
bake_keys(h)
import numpy as np
from mathutils import kdtree
BASE_P = np.array([v.co[:] for v in h.data.vertices], dtype=np.float64)
# varyasyon şekilleri: makro farkları + yüz hedefleri (aynı köşe sırası)
VARS = cfg.get("variants", {
    "muscle": {"macro": {"muscle": 1.0}}, "lean": {"macro": {"muscle": 0.5}},
    "heavy": {"macro": {"weight": 0.85}}, "thin": {"macro": {"weight": 0.12}},
    "young": {"macro": {"age": 0.36}}, "old": {"macro": {"age": 0.72}},
    "african": {"macro": {"caucasian": 0.0, "african": 1.0}}, "asian": {"macro": {"caucasian": 0.0, "asian": 1.0}},
    "nose_wide": {"t": {"nose/nose-scale-horiz-incr": 1.0, "nose/nose-flaring-incr": 0.6}},
    "nose_long": {"t": {"nose/nose-scale-vert-incr": 1.0, "nose/nose-hump-incr": 0.8}},
    "chin": {"t": {"chin/chin-prominent-incr": 1.0, "chin/chin-width-incr": 0.6}},
    "jaw": {"t": {"head/head-square": 1.0}},
    "oval": {"t": {"head/head-oval": 1.0}},
    "cheeks": {"t": {"cheek/l-cheek-bones-incr": 1.0, "cheek/r-cheek-bones-incr": 1.0}},
    "mouth": {"t": {"mouth/mouth-scale-horiz-incr": 1.0, "mouth/mouth-lowerlip-volume-incr": 0.7}},
    "brow": {"t": {"eyebrows/eyebrows-trans-down": 1.0, "eyebrows/eyebrows-angle-down": 0.5}},
})
FACE_ONLY = {"nose_wide", "nose_long", "chin", "jaw", "oval", "cheeks", "mouth", "brow"}
DELTA = {}
for vname, spec in VARS.items():
    hv = HumanService.create_human()
    mm = dict(macro); mm.update(spec.get("macro", {}))
    for k, v in mm.items():
        HOP.set_value(k, v, entity_reference=hv)
    TargetService.reapply_macro_details(hv)
    for tn, w in spec.get("t", {}).items():
        import os as _os
        fp = _os.path.join("/root/.config/blender/5.2/extensions/user_default/mpfb/data/targets", tn + ".target.gz")
        TargetService.load_target(hv, fp, weight=w, name=tn.split("/")[-1])
    bake_keys(hv)
    P = np.array([v.co[:] for v in hv.data.vertices], dtype=np.float64)
    # boy farkını çıkar (iskelet sabit): ayak tabanına göre düzgün ölçekle normalize et
    sc = (BASE_P[:, 2].max() - BASE_P[:, 2].min()) / max(1e-6, (P[:, 2].max() - P[:, 2].min()))
    zmin = P[:, 2].min()
    P = P * sc
    P[:, 2] += BASE_P[:, 2].min() - zmin * sc
    DELTA[vname] = P - BASE_P
    print("variant", vname, "max delta", float(np.abs(DELTA[vname]).max()))
    bpy.data.objects.remove(hv)
for m in list(h.modifiers):
    if m.type != "ARMATURE":
        h.modifiers.remove(m)

gidx = {g.index: g.name for g in h.vertex_groups}
bones = {b.name: b for b in rig.data.bones}
def bone_seg(n):
    b = bones[n]
    return (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local)

# --- yardımcı geometriyi ayıkla (gözler ayrı nesne)
def split_by_groups(src, keep_groups, name):
    o = src.copy(); o.data = src.data.copy(); o.name = name
    bpy.context.collection.objects.link(o)
    bm = bmesh.new(); bm.from_mesh(o.data)
    dl = bm.verts.layers.deform.active
    kill = [v for v in bm.verts if not ({gidx[i] for i in v[dl].keys()} & keep_groups)]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(o.data); bm.free()
    return o
_keep_idx = [v.index for v in h.data.vertices if {gidx[g.group] for g in v.groups} & {"body", "helper-l-eye", "helper-r-eye"}]
KD = kdtree.KDTree(len(_keep_idx))
for i in _keep_idx:
    KD.insert(BASE_P[i], i)
KD.balance()
eyes = split_by_groups(h, {"helper-l-eye", "helper-r-eye"}, "Eyes")
EYE_C = sum((eyes.matrix_world @ v.co for v in eyes.data.vertices), Vector()) / max(1, len(eyes.data.vertices))
print("eye center", EYE_C)
body = split_by_groups(h, {"body"}, "Body")
bpy.data.objects.remove(h)

def clean_groups(o):
    for g in list(o.vertex_groups):
        if g.name not in bones:
            o.vertex_groups.remove(g)
for o in (eyes, body):
    clean_groups(o)

# --- bölgeler: baskın kemik + kemik ekseni üzerindeki konum
def dominant(o, v):
    best, bw = "", -1.0
    for g in v.groups:
        if g.weight > bw:
            bw = g.weight; best = o.vertex_groups[g.group].name
    return best
def along(p, seg):
    a, b = seg
    ab = b - a
    return (p - a).dot(ab) / max(1e-6, ab.length_squared)

H = max(v.co.z for v in body.data.vertices)
segs = {n: bone_seg(n) for n in bones}
sleeve = cfg.get("sleeve", 0.42)   # üst kol oranı (kısa kol)
def region(o, v):
    p = o.matrix_world @ v.co
    d = dominant(o, v)
    side = d[-2:] if d.endswith(("_l", "_r")) else ""
    if d in ("spine_01", "spine_02", "spine_03"):
        return "shirt"
    if d == "clavicle" + side and side:
        return "shirt"
    if d == "neck_01":
        return "skin" if p.z > segs["neck_01"][0].z - 0.005 else "shirt"
    if d == "upperarm" + side and side:
        return "shirt" if along(p, segs["upperarm" + side]) < sleeve else "skin"
    if d == "pelvis":
        return "shorts"
    if d == "thigh" + side and side:
        return "shorts" if along(p, segs["thigh" + side]) < 0.5 else "skin"
    if d == "calf" + side and side:
        return "socks" if along(p, segs["calf" + side]) > 0.12 else "skin"
    if d in ("foot" + side, "ball" + side) and side:
        # bileği çorap örter; krampon ayak tabanından bilek altına kadar
        if p.z > segs["foot" + side][0].z - 0.03:
            return "socks"
        return "boots"
    return "skin"

reg = [region(body, v) for v in body.data.vertices]
# kol altı / bel: gömlek pelvisin üst kısmını da örtsün
pel_top = segs["spine_01"][0].z
for i, v in enumerate(body.data.vertices):
    p = body.matrix_world @ v.co
    if reg[i] == "shorts" and p.z > pel_top - 0.015:
        reg[i] = "shirt"

# yüz bölgesi: köşe bölgelerinin çoğunluğu (sınırda delik kalmasın)
PRI = {"boots": 4, "socks": 3, "shorts": 2, "shirt": 1, "skin": 0}
face_reg = []
for f in body.data.polygons:
    cnt = {}
    for vi in f.vertices:
        cnt[reg[vi]] = cnt.get(reg[vi], 0) + 1
    best = max(cnt.items(), key=lambda kv: (kv[1], PRI[kv[0]]))[0]
    face_reg.append(best)

THICK = {"shirt": 0.014, "shorts": 0.018, "socks": 0.005, "boots": 0.010}
SMOOTH = {"shirt": 6, "shorts": 4, "socks": 1, "boots": 4}
def lap_smooth(bm, verts, iters, keep_boundary=True, fac=0.5):
    for _ in range(iters):
        newp = {}
        for v in verts:
            if keep_boundary and v.is_boundary:
                continue
            nb = [e.other_vert(v) for e in v.link_edges]
            if not nb:
                continue
            avg = sum((n.co for n in nb), Vector()) / len(nb)
            newp[v] = v.co.lerp(avg, fac)
        for v, p in newp.items():
            v.co = p

def build_boots():
    ## Parametrik krampon: ayak dilimlerinden süperelips kesitli yeni, temiz bir kabuk (ayağa göre ölçekli)
    o_mesh = bpy.data.meshes.new("Boots")
    o = bpy.data.objects.new("Boots", o_mesh)
    bpy.context.collection.objects.link(o)
    bm = bmesh.new()
    groups = {}
    allw = []   # (vert, {group: w})
    NB, NS = 18, 22
    for side, sfx in ((1, "_l"), (-1, "_r")):
        vs = [v for i, v in enumerate(body.data.vertices) if reg[i] == "boots" and v.co.x * side > 0]
        if not vs:
            continue
        heel = max(v.co.y for v in vs)
        toe = min(v.co.y for v in vs)
        z0 = min(v.co.z for v in vs)
        ank = segs["foot" + sfx][0].z
        L = heel - toe
        rows = []
        prof = []
        for bi in range(NB):
            t0 = bi / (NB - 1)
            ys = heel - t0 * L
            band = [v for v in vs if abs(v.co.y - ys) < L / NB * 1.2 and v.co.z < ank - 0.01] or vs
            cx = sum(v.co.x for v in band) / len(band)
            hw = max(abs(v.co.x - cx) for v in band)
            top = max(v.co.z for v in band)
            prof.append([cx, hw, top])
        # profili yumuşat
        for _ in range(3):
            prof = [prof[0]] + [[(prof[i-1][k] + 2 * prof[i][k] + prof[i+1][k]) / 4 for k in range(3)] for i in range(1, NB - 1)] + [prof[-1]]
        for bi in range(NB):
            t0 = bi / (NB - 1)
            ys = heel - t0 * L - 0.006 * (1 if t0 > 0.99 else 0)
            cx, hw, top = prof[bi]
            hw += 0.006
            top = min(top + 0.006, ank + 0.005)
            if t0 > 0.6:
                top = min(top, z0 + 0.07 - (t0 - 0.6) * 0.06)
            # uçlar yuvarlak
            endk = min(1.0, math.sin(math.pi * min(t0, 1.0 - t0) * 2.2 + 0.25) * 1.1) if (t0 < 0.12 or t0 > 0.88) else 1.0
            endk = max(0.25, endk)
            zb = z0 - 0.004
            zc = (zb + top) * 0.5
            hh = (top - zb) * 0.5
            ring = []
            for si in range(NS):
                a = 2 * math.pi * si / NS
                c, sn = math.cos(a), math.sin(a)
                nx = math.copysign(abs(c) ** 0.75, c)
                nz = math.copysign(abs(sn) ** (0.8 if sn > 0 else 0.3), sn)
                x = cx + hw * nx * endk
                z = zc + hh * nz * (endk if sn > 0 else 1.0)
                v = bm.verts.new((x, ys, z))
                sball = min(1.0, max(0.0, (t0 - 0.55) / 0.2))
                allw.append((v, {"foot" + sfx: 1.0 - sball, "ball" + sfx: sball}))
                ring.append(v)
            rows.append(ring)
        for bi in range(NB - 1):
            for si in range(NS):
                a, b = rows[bi][si], rows[bi][(si + 1) % NS]
                c2, d2 = rows[bi + 1][(si + 1) % NS], rows[bi + 1][si]
                bm.faces.new((a, b, c2, d2))
        # kapaklar
        bm.faces.new(list(reversed(rows[0])))
        bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.verts.index_update()
    bm.to_mesh(o_mesh)
    vidx = {v: v.index for v, _ in allw}
    bm.free()
    for _, w in allw:
        for g in w:
            if g not in o.vertex_groups:
                o.vertex_groups.new(name=g)
    for i, (_, w) in enumerate(allw):
        for g, val in w.items():
            if val > 0.0:
                o.vertex_groups[g].add([i], val, "REPLACE")
    for p in o.data.polygons:
        p.use_smooth = True
    rest_color(o)
    o.data.uv_layers.new(name="UVMap")
    m = bpy.data.materials.new("kit_boots")
    o.data.materials.append(m)
    return o

def rest_color(o):
    ## dinlenme konumu vertex rengine (Godot ekseni): desenler kumaşla birlikte hareket etsin
    ca = o.data.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(o.data.vertices):
        p = o.matrix_world @ v.co
        ca.data[i].color = ((p.x + 1.0) * 0.5, p.z * 0.5, (1.0 - p.y) * 0.5, 1.0)
    o.data.color_attributes.active_color = ca

def make_garment(kind, mat_name, freg=None, oname=None, tkind=None):
    freg = freg if freg is not None else face_reg
    o = body.copy(); o.data = body.data.copy(); o.name = oname or kind.capitalize()
    tkind = tkind or kind
    bpy.context.collection.objects.link(o)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    kill = [f for f in bm.faces if freg[f.index] != kind]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()
    base = {v: v.co.copy() for v in bm.verts}
    nrm = {v: v.normal.copy() for v in bm.verts}
    t = THICK[tkind]
    for v in bm.verts:
        tt = t
        if tkind == "shirt":
            # bel ve karın: forma bedene yapışmaz, biraz sarkar
            tt += 0.012 * max(0.0, min(1.0, (pel_top + 0.28 - base[v].z) / 0.3))
            if v.is_boundary and abs(base[v].x) > 0.15 and base[v].z > pel_top + 0.2:
                tt += 0.006
        v.co = base[v] + nrm[v] * tt
    # kenar çizgisini düzle (yaka, kol ağzı, etek): sınır köşelerini sınır komşularının ortalamasına çek
    for _ in range(6):
        newp = {}
        for v in bm.verts:
            if not v.is_boundary:
                continue
            nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(nb) == 2:
                newp[v] = v.co.lerp((nb[0].co + nb[1].co) * 0.5, 0.6)
        for v, p in newp.items():
            v.co = p
    # kumaş: kas detayını yumuşat
    lap_smooth(bm, list(bm.verts), SMOOTH[tkind], keep_boundary=True, fac=0.5)
    # yumuşatma vücudun içine itmesin: en az t/2 dışarıda kalsın
    if kind == "boots":
        # krampon: parmakları yok et, düzgün bir kabuk; sonra yeni normaller boyunca şişir
        bm.normal_update()
        for v in bm.verts:
            v.co += v.normal * 0.012
    else:
        for v in bm.verts:
            d = (v.co - base[v]).dot(nrm[v])
            if d < t * 0.6:
                v.co += nrm[v] * (t * 0.6 - d)
    # kenarları düz çizgiye oturt (etek, paça, kol ağzı, yaka)
    for v in bm.verts:
        if not v.is_boundary:
            continue
        p = v.co
        if kind == "shirt":
            if p.z < pel_top + 0.12 and abs(p.x) < 0.22:
                p.z = hem_z
            elif p.z > neck_z - 0.04 and abs(p.x) < 0.09:
                pass
        if kind == "shorts" and p.z < pel_top - 0.1:
            p += nrm[v] * 0.012
        if kind == "socks" and p.z > knee_z - 0.12:
            pass
    if kind == "shirt":
        neck_edges = [e for e in bm.edges if e.is_boundary and all(v.co.z > neck_z - 0.06 and abs(v.co.x) < 0.11 for v in e.verts)]
        if neck_edges:
            ret = bmesh.ops.extrude_edge_only(bm, edges=neck_edges)
            nv = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
            cx = sum(v.co.x for v in nv) / len(nv)
            cy = sum(v.co.y for v in nv) / len(nv)
            for v in nv:
                v.co.z += 0.005
                v.co.x += (cx - v.co.x) * 0.1
                v.co.y += (cy - v.co.y) * 0.1
    bm.to_mesh(o.data); bm.free()
    rest_color(o)
    m = bpy.data.materials.new(mat_name)
    o.data.materials.clear(); o.data.materials.append(m)
    return o
neck_z = segs["neck_01"][0].z
knee_z = segs["calf_l"][0].z
hem_z = pel_top - 0.07

def region_outfit(o, v):
    p = o.matrix_world @ v.co
    d = dominant(o, v)
    side = d[-2:] if d.endswith(("_l", "_r")) else ""
    if d in ("spine_01", "spine_02", "spine_03") or (side and d == "clavicle" + side):
        return "shirt" if p.z > pel_top - 0.015 else "pants"
    if d == "neck_01":
        return "skin" if p.z > segs["neck_01"][0].z - 0.005 else "shirt"
    if side and d == "upperarm" + side:
        return "shirt"
    if side and d == "lowerarm" + side:
        return "shirt" if along(p, segs["lowerarm" + side]) < 0.93 else "skin"
    if d == "pelvis" or (side and d in ("thigh" + side, "calf" + side)):
        return "pants"
    if side and d in ("foot" + side, "ball" + side):
        return "pants" if p.z > segs["foot" + side][0].z - 0.02 else "skin"
    return "skin"
reg_o = [region_outfit(body, v) for v in body.data.vertices]
face_reg_o = []
for f in body.data.polygons:
    cnt = {}
    for vi in f.vertices:
        cnt[reg_o[vi]] = cnt.get(reg_o[vi], 0) + 1
    face_reg_o.append(max(cnt.items(), key=lambda kv: (kv[1], {"pants": 2, "shirt": 1, "skin": 0}[kv[0]]))[0])
THICK["pants"] = 0.016
SMOOTH["pants"] = 5
garments = [make_garment("shirt", "kit_shirt"), make_garment("shorts", "kit_shorts"),
            make_garment("socks", "kit_socks"), build_boots(),
            make_garment("shirt", "out_shirt", face_reg_o, "ShirtLong"), make_garment("pants", "out_pants", face_reg_o, "Pants")]

# --- saç: kafa derisi bölgesi
head_seg = segs["head"]
hz0 = head_seg[0].z
def scalp_w(p):
    ## saçlı bölge: göz merkezine göre yön bağımlı eşik (önde alın çizgisi, arkada ense)
    c = Vector((0.0, EYE_C.y + 0.085, EYE_C.z))   # kafa merkezi (gözlerin arkası)
    d = p - c
    hor = Vector((d.x, d.y, 0.0))
    if hor.length < 1e-4:
        return 1.0
    hor.normalize()
    front = -hor.y          # +1 ön, -1 arka
    side = abs(hor.x)
    thr = EYE_C.z + 0.04 * max(0.0, front) - 0.075 * max(0.0, -front) + 0.012 * side * (1.0 - abs(front))
    # kulaklar: yanlarda göz hizasının biraz üstüne kadar hariç
    if side > 0.8 and p.z < EYE_C.z + 0.03 and abs(d.x) > 0.06:
        return 0.0
    if p.z > thr + 0.008:
        return 1.0
    if p.z > thr - 0.008:
        return (p.z - (thr - 0.008)) / 0.016
    return 0.0

# saç stilleri: [tepe uzunluğu, yan uzunluğu, ön kabarma]
HSTYLE = {"crop": [0.009, 0.004, 0.004], "fade": [0.013, 0.0012, 0.004], "quiff": [0.016, 0.003, 0.02],
          "afro": [0.034, 0.026, 0.0], "curly": [0.02, 0.012, 0.0], "long": [0.016, 0.012, 0.006]}
def make_hair(name, style):
    o = body.copy(); o.data = body.data.copy(); o.name = name
    bpy.context.collection.objects.link(o)
    bm = bmesh.new(); bm.from_mesh(o.data)
    dl = bm.verts.layers.deform.active
    wv = {}
    for v in bm.verts:
        p = o.matrix_world @ v.co
        d = max(v[dl].items(), key=lambda kv: kv[1])[0] if v[dl] else -1
        nm = gidx_body[d] if d in gidx_body else ""
        wv[v] = scalp_w(p) if nm in ("head", "neck_01") else 0.0
    print("hair verts", sum(1 for x in wv.values() if x >= 0.5))
    kill = [f for f in bm.faces if sum(wv[v] for v in f.verts) / len(f.verts) < 0.5]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # daha yuvarlak saç: bir kez böl ve yumuşat
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=1, use_grid_fill=True, smooth=1.0)
    bm.normal_update()
    top = max((o.matrix_world @ v.co).z for v in bm.verts) if bm.verts else H
    # sınırdan uzaklık (kenar halkası sayısı): kalınlık kenarda sıfıra insin, saç çizgisi yumuşak olsun
    ring = {v: (0 if v.is_boundary else 99) for v in bm.verts}
    for it in range(1, 4):
        for v in bm.verts:
            if ring[v] == 99 and any(ring[e.other_vert(v)] == it - 1 for e in v.link_edges):
                ring[v] = it
    for _ in range(4):
        newp = {}
        for v in bm.verts:
            if v.is_boundary:
                nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
                if len(nb) == 2:
                    newp[v] = v.co.lerp((nb[0].co + nb[1].co) * 0.5, 0.6)
        for v, p in newp.items():
            v.co = p
    bm.normal_update()
    for v in bm.verts:
        p = o.matrix_world @ v.co
        k = clamp01((p.z - hz0) / max(0.01, top - hz0))
        nz = v.normal.z            # 1 tepe, 0 yanlar
        fwd = clamp01((head_seg[0].y - p.y) * 9.0)
        topk = clamp01((nz - 0.25) / 0.6)
        S = HSTYLE[style]
        off = S[1] + (S[0] - S[1]) * topk + S[2] * fwd * topk
        taper = min(1.0, (ring[v] + 0.15) / 3.0)
        v.co += v.normal * (0.0015 + off * taper)
    ringv = {v.index: min(1.0, ring[v] / 2.5) for v in bm.verts}
    bm.to_mesh(o.data); bm.free()
    ca = o.data.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i in range(len(o.data.vertices)):
        r = ringv.get(i, 1.0)
        ca.data[i].color = (r, r, r, 1.0)
    o.data.color_attributes.active_color = ca
    m = bpy.data.materials.new("hair")
    o.data.materials.clear(); o.data.materials.append(m)
    return o
def clamp01(x): return max(0.0, min(1.0, x))
gidx_body = {g.index: g.name for g in body.vertex_groups}
hairs = [make_hair("HairCrop", "crop"), make_hair("HairFade", "fade"), make_hair("HairQuiff", "quiff"), make_hair("HairAfro", "afro"), make_hair("HairCurly", "curly")]

# --- gövdeden örtülen yüzleri sil (çorap/kramponun altı, gömlek/şort altı)
bm = bmesh.new(); bm.from_mesh(body.data)
bm.verts.ensure_lookup_table()
bm.faces.ensure_lookup_table()
kill = [f for f in bm.faces if face_reg[f.index] != "skin"]
bmesh.ops.delete(bm, geom=kill, context="FACES")
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
bm.to_mesh(body.data); bm.free()
mb = bpy.data.materials.new("skin")
body.data.materials.clear(); body.data.materials.append(mb)
me = bpy.data.materials.new("eye")
eyes.data.materials.clear(); eyes.data.materials.append(me)

# --- dışa aktar
for o in [body, eyes] + garments + hairs:
    o.parent = rig
    if not any(m.type == "ARMATURE" for m in o.modifiers):
        mo = o.modifiers.new("Armature", "ARMATURE"); mo.object = rig
def add_shapes(o, face=True, keep_face=()):
    o.shape_key_add(name="Basis", from_mix=False)
    co = [v.co.copy() for v in o.data.vertices]
    near = [KD.find(c)[1] for c in co]
    for vname, D in DELTA.items():
        if vname in FACE_ONLY and not face and vname not in keep_face:
            continue
        kb = o.shape_key_add(name=vname, from_mix=False)
        for i, c in enumerate(co):
            d = D[near[i]]
            kb.data[i].co = (c.x + d[0], c.y + d[1], c.z + d[2])
for o in [body, eyes] + garments + hairs:
    add_shapes(o, face=(o in (body, eyes)), keep_face=(("oval", "jaw") if o in hairs else ()))
lods = []
if cfg.get("lod", True):
    for o in [body] + garments[:3] + garments[4:] + hairs:
        lo = o.copy(); lo.data = o.data.copy(); lo.name = o.name + "_lod"
        bpy.context.collection.objects.link(lo)
        bm = bmesh.new(); bm.from_mesh(lo.data)
        bmesh.ops.unsubdivide(bm, verts=list(bm.verts), iterations=2 if not o.name.startswith("Hair") else 1)
        bm.to_mesh(lo.data); bm.free()
        lods.append(lo)
    hairs_all = hairs
garments_all = garments + lods
print("tris:", {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in [body, eyes] + garments + hairs + lods})
bpy.ops.object.select_all(action="DESELECT")
for o in [rig, body, eyes] + garments + hairs + lods:
    o.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format="GLB", export_skins=True,
    export_animations=False, export_morph=True, export_morph_normal=False, export_yup=True, export_apply=False, export_vertex_color="ACTIVE")
print("wrote", out)

# --- doku üretimi için gövde verisi (konum + uv + üçgenler)
import numpy as np
if cfg.get("dump", True):
    me = body.data
    me.calc_loop_triangles()
    uvl = me.uv_layers.active.data
    P3 = np.array([v.co[:] for v in me.vertices], dtype=np.float32)
    tris = []
    for lt in me.loop_triangles:
        tris.append([list(P3[lt.vertices[k]]) + list(uvl[lt.loops[k]].uv) for k in range(3)])
    np.savez_compressed("/home/claude/mh/out/body_tris.npz", tris=np.array(tris, dtype=np.float32),
        eye=np.array(EYE_C[:], dtype=np.float32), H=np.float32(H))
    em = eyes.data
    uve = em.uv_layers.active.data
    best = {}
    for lp in em.loops:
        v = em.vertices[lp.vertex_index]
        side = "l" if v.co.x > 0 else "r"
        if side not in best or v.co.y < best[side][0]:
            best[side] = (v.co.y, uve[lp.index].uv[:], v.co[:])
    ys = [v.co.y for v in em.vertices]
    print("eye front uv", best, "eye depth", min(ys), max(ys))
if cfg.get("dump", True):
    import math as _m
    rows = []
    for lp in em.loops:
        v = em.vertices[lp.vertex_index]
        side = "l" if v.co.x > 0 else "r"
        c = Vector((0.029943 if side == "l" else -0.029943, -0.1366, 1.7561))
        d = (v.co - c).normalized()
        th = _m.degrees(_m.acos(max(-1, min(1, d.dot(Vector((0, -1, 0)))))))
        uv = uve[lp.index].uv
        fu = best[side][1]
        rows.append((side, round(th, 1), round(((uv[0]-fu[0])**2 + (uv[1]-fu[1])**2) ** 0.5, 4)))
    rows.sort(key=lambda r: r[1])
    print("eye th/uvdist", [r for r in rows if r[0] == "l"][:40:3])
