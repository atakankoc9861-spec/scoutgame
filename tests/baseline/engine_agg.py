#!/usr/bin/env python3
"""engine_stats.tscn çıktılarını (RESULT_JSON satırları) birleştirir.

Kullanım: engine_agg.py <log>...   (her log bir seed; live ya da quick)
Çıktı: metrik başına seed ortalaması ± seed'ler arası sd, birleşik değer, birleşik %95 aralık
(oranlar için Wilson, ortalamalar için seed'ler arası t yaklaşımı yerine normal yaklaşımı) ve hedef.
"""
import json
import math
import sys

TARGETS = {
    "goals_per_match": (2.5, 3.1),
    "home_win_pct": (41, 48),
    "draw_pct": (22, 29),
    "away_win_pct": (27, 33),
    "nil_nil_pct": (4, 9),
    "big_margin_pct": (0, 6),
    "home_away_goal_ratio": (1.15, 1.35),
    "shots_per_match": (22, 28),
    "sot_per_match": (7, 10),
    "pass_accuracy_pct": (78, 86),
    "fouls_per_match": (19, 26),
    "corners_per_match": (8, 11),
    "yellow_per_match": (3, 5),
    "red_per_match": (0.08, 0.2),
}
COUNTS = {"home_win_pct": "hw", "draw_pct": "dr", "away_win_pct": "aw", "nil_nil_pct": "nil", "big_margin_pct": "big"}


def wilson(k, n, z=1.96):
    if n == 0:
        return (0, 0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (100 * (c - h), 100 * (c + h))


def main():
    rows = []
    for path in sys.argv[1:]:
        for line in open(path, encoding="utf-8"):
            if line.startswith("RESULT_JSON "):
                rows.append(json.loads(line[len("RESULT_JSON "):]))
                break
    if not rows:
        print("RESULT_JSON bulunamadı")
        return 1
    n = sum(r["matches"] for r in rows)
    eng = rows[0]["engine"]
    print(f"motor={eng} seed={[r['seed'] for r in rows]} maç={n}")
    print(f"{'metrik':24} {'ort ± sd (seed)':>18} {'birleşik':>9} {'%95 aralık':>16} {'hedef':>12}  hüküm")
    for k in list(TARGETS) + ["stronger_win_pct", "rating_mean", "rating_sd", "assisted_pct", "ms_median", "ms_p99", "ms_max"]:
        vals = [r[k] for r in rows if k in r]
        if not vals:
            continue
        m = sum(vals) / len(vals)
        sd = math.sqrt(sum((v - m) ** 2 for v in vals) / max(1, len(vals) - 1)) if len(vals) > 1 else 0.0
        comb = m
        lo = hi = None
        if k in COUNTS:
            kk = sum(r[COUNTS[k]] for r in rows)
            comb = 100 * kk / n
            lo, hi = wilson(kk, n)
        elif k == "goals_per_match":
            comb = sum(r["goals"] for r in rows) / n
            se = sd / math.sqrt(len(vals)) if len(vals) > 1 else 0
            lo, hi = comb - 1.96 * se, comb + 1.96 * se
        elif k == "home_away_goal_ratio":
            comb = sum(r["gh"] for r in rows) / max(1, sum(r["ga"] for r in rows))
            se = sd / math.sqrt(len(vals)) if len(vals) > 1 else 0
            lo, hi = comb - 1.96 * se, comb + 1.96 * se
        elif k.startswith("ms_"):
            comb = max(vals) if k != "ms_median" else sorted(vals)[len(vals) // 2]
        tgt = TARGETS.get(k)
        verdict = ""
        if tgt and lo is not None:
            if lo >= tgt[0] and hi <= tgt[1]:
                verdict = "hedefte"
            elif hi < tgt[0] or lo > tgt[1]:
                verdict = "HEDEF DIŞI"
            else:
                verdict = "sınırda (aralık örtüşüyor)"
        elif tgt:
            verdict = "hedefte" if tgt[0] <= comb <= tgt[1] else "hedef dışı (yumuşak)"
        rng = f"{lo:.2f}–{hi:.2f}" if lo is not None else ""
        ts = f"{tgt[0]}–{tgt[1]}" if tgt else ""
        print(f"{k:24} {m:9.2f} ± {sd:5.2f} {comb:9.2f} {rng:>16} {ts:>12}  {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
