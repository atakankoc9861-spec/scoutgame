#!/usr/bin/env python3
"""Çok seed'li ölçüm loglarından (RESULT_JSON satırları) baseline.json üretir.
Kullanım: python3 make_baseline.py <log_klasörü> <çıkış.json> <seed> [<seed> ...]
Beklenen loglar: live_<seed>.log, season0_<seed>.log (PLAN=0), season1_<seed>.log (PLAN=1)."""
import json
import os
import statistics as st
import sys

BASE_COMMIT = "9325199"
TARGETS = {
    "goals_per_match": [2.5, 3.1], "home_win_pct": [41, 48], "draw_pct": [22, 29], "away_win_pct": [27, 33],
    "nil_nil_pct": [4, 9], "margin4plus_pct": [2, 6],
    "shots_per_match": [22, 28], "shots_on_target_per_match": [7, 10], "pass_accuracy_pct": [78, 86],
    "fouls_per_match": [19, 26], "corners_per_match": [8, 11], "yellow_per_match": [3.0, 5.0],
    "red_per_match": [0.08, 0.2],
}
SL_TARGETS = {"goals_per_match": [2.6, 3.0], "home_win_pct": [42, 50], "draw_pct": [22, 28]}
SOFT = {"shots_per_match", "shots_on_target_per_match", "pass_accuracy_pct", "fouls_per_match",
        "corners_per_match", "yellow_per_match", "red_per_match"}
RESULT_KEYS = ["goals_per_match", "home_goals_per_match", "away_goals_per_match", "home_win_pct", "draw_pct",
               "away_win_pct", "nil_nil_pct", "margin4plus_pct"]
LIVE_EXTRA = ["shots_per_match", "shots_on_target_per_match", "pass_accuracy_pct", "pass_attempts_per_match",
              "fouls_per_match", "corners_per_match", "yellow_per_match", "red_per_match",
              "cpu_ms_per_match_median", "cpu_ms_per_match_max"]


def load(path):
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("RESULT_JSON "):
            return json.loads(line[len("RESULT_JSON "):])
    sys.exit("RESULT_JSON bulunamadı: " + path)


def margin4(sd):
    n = sum(sd.values())
    return round(100 * sum(v for k, v in sd.items() if abs(int(k.split("-")[0]) - int(k.split("-")[1])) >= 4) / max(1, n), 1)


def agg(values):
    v = [float(x) for x in values]
    return {"mean": round(st.mean(v), 2), "sd": round(st.stdev(v), 2) if len(v) > 1 else 0.0,
            "min": round(min(v), 2), "max": round(max(v), 2), "per_seed": v}


def verdict(a, rng, soft=False):
    """Seed'ler arası sağlamlık: tüm seed'ler hedef dışında ve aynı yönde ise 'gerçek açık'."""
    if rng is None:
        return "hedef yok"
    lo, hi = rng
    vals = a["per_seed"]
    if all(x < lo for x in vals) or all(x > hi for x in vals):
        tag = "GERÇEK AÇIK (tüm seed'ler " + ("altında" if vals[0] < lo else "üstünde") + ")"
    elif all(lo <= x <= hi for x in vals):
        tag = "hedefte (tüm seed'ler)"
    else:
        tag = "belirsiz (seed'e göre değişiyor)"
    return tag + (" [yumuşak hedef]" if soft else "")


def score_merge(dists):
    out = {}
    for d in dists:
        for k, v in d.items():
            out[k] = out.get(k, 0) + v
    return out


def main():
    d, out_path, seeds = sys.argv[1], sys.argv[2], sys.argv[3:]
    live = [load(os.path.join(d, f"live_{s}.log")) for s in seeds]
    p0 = [load(os.path.join(d, f"season0_{s}.log")) for s in seeds]
    p1 = [load(os.path.join(d, f"season1_{s}.log")) for s in seeds]
    for L in live:
        L["margin4plus_pct"] = margin4(L["score_dist"])
    groups = ["all", "lazy", "detailed", "top5_tier1", "SL"]
    for P in p0:
        for g in groups:
            P[g]["margin4plus_pct"] = margin4(P[g]["score_dist"])

    live_agg = {}
    for k in RESULT_KEYS + LIVE_EXTRA:
        live_agg[k] = agg([L[k] for L in live])
        if k in TARGETS:
            live_agg[k]["verdict"] = verdict(live_agg[k], TARGETS[k], k in SOFT)
    live_scores = score_merge([L["score_dist"] for L in live])
    live_agg["margin4plus_pct_pooled"] = margin4(live_scores)
    # birleşik örneklem (tüm seed'ler) oranları + %95 güven aralığı (normal yaklaşım)
    n = sum(live_scores.values())
    pooled = {}
    for name, f in [("home_win_pct", lambda a, b: a > b), ("draw_pct", lambda a, b: a == b),
                    ("away_win_pct", lambda a, b: a < b), ("nil_nil_pct", lambda a, b: a + b == 0),
                    ("margin4plus_pct", lambda a, b: abs(a - b) >= 4)]:
        q = sum(v for k, v in live_scores.items() if f(*map(int, k.split("-")))) / max(1, n)
        se = (q * (1 - q) / max(1, n)) ** 0.5
        pooled[name] = {"pct": round(100 * q, 1), "ci95": [round(100 * (q - 1.96 * se), 1), round(100 * (q + 1.96 * se), 1)]}
    live_agg["pooled_ci95"] = {"matches": n, **pooled}

    pois_agg = {}
    for g in groups:
        pois_agg[g] = {}
        for k in RESULT_KEYS:
            a = agg([P[g][k] for P in p0])
            tg = SL_TARGETS.get(k, TARGETS.get(k)) if g == "SL" else TARGETS.get(k)
            if tg:
                a["verdict"] = verdict(a, tg)
            pois_agg[g][k] = a
        pois_agg[g]["matches_per_seed"] = [P[g]["matches"] for P in p0]

    def weeks(Ps):
        return {"median": agg([P["week_ms_median"] for P in Ps]), "p90": agg([P["week_ms_p90"] for P in Ps]),
                "max": agg([P["week_ms_max"] for P in Ps]), "week_ms_per_seed": [P["week_ms"] for P in Ps],
                "live_watched_per_seed": [P["live_watched"] for P in Ps]}

    w0, w1 = weeks(p0), weeks(p1)
    save_ms = agg([P["save_ms_median"] for P in p0])
    out = {
        "version": "0.22-b4 + v0.23 Dalga 1 (entegrasyon)", "base_commit": BASE_COMMIT,
        "godot": "4.5.1-stable headless, 2 çekirdek", "seeds": [int(s) for s in seeds],
        "live_matches_per_seed": [L["matches"] for L in live], "live_leagues": live[0]["leagues"],
        "live_engine": live_agg, "live_score_dist_pooled": live_scores,
        "poisson_season": pois_agg,
        "poisson_score_dist_pooled_all": score_merge([P["all"]["score_dist"] for P in p0]),
        "week_timing": {
            "unwatched": w0, "watch_one_live_per_week": w1,
            "save_ms_median": save_ms, "save_bytes_per_seed": [P["save_bytes"] for P in p0],
            "new_game_ms_per_seed": [P["new_game_ms"] for P in p0],
            "v023_budget_ms": {
                "unwatched_median_x2": round(2 * w0["median"]["mean"]),
                "unwatched_max_x2": round(2 * w0["max"]["mean"]),
                "watched_median_x2": round(2 * w1["median"]["mean"]),
                "watched_max_x2": round(2 * w1["max"]["mean"]),
                "rule": "seed'ler arası ortalama medyan/en kötü × 2"},
        },
        "targets": dict(TARGETS, SL=SL_TARGETS, soft=sorted(SOFT),
                        source_note="Top-5 Avrupa ligleri 2023-24/2024-25 + Süper Lig 2023-24; gerekçe BASELINE.md"),
        "previous_single_seed_77c0f1d": {
            "live": {"goals_per_match": 3.15, "home_win_pct": 56.0, "draw_pct": 17.0, "nil_nil_pct": 5.5,
                     "margin4plus_pct": 18.5},
            "poisson_all": {"goals_per_match": 2.62, "home_win_pct": 52.3, "draw_pct": 23.0, "nil_nil_pct": 7.9},
            "week_ms": {"unwatched_median": 286, "unwatched_max": 454, "watched_median": 2655, "watched_max": 3032}},
    }
    json.dump(out, open(out_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # kısa özet
    for k in RESULT_KEYS + LIVE_EXTRA:
        a = live_agg[k]
        print(f"live {k:28s} {a['mean']:8.2f} ±{a['sd']:6.2f}  {a['per_seed']}  {a.get('verdict', '')}")
    print("live margin4 pooled", live_agg["margin4plus_pct_pooled"])
    for g in ["all", "top5_tier1", "SL"]:
        for k in RESULT_KEYS:
            a = pois_agg[g][k]
            print(f"pois {g:10s} {k:22s} {a['mean']:7.2f} ±{a['sd']:5.2f}  {a['per_seed']}  {a.get('verdict', '')}")
    print("weeks unwatched", {k: w0[k]["per_seed"] for k in ["median", "p90", "max"]})
    print("weeks watched  ", {k: w1[k]["per_seed"] for k in ["median", "p90", "max"]})
    print("save_ms", save_ms["per_seed"], "budget", out["week_timing"]["v023_budget_ms"])


if __name__ == "__main__":
    main()
