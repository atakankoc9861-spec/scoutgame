#!/usr/bin/env python3
"""live_stats / season_stats çıktılarından (RESULT_JSON satırları) baseline.json üretir.
Kullanım: python3 make_baseline.py <live.log> <season_plan0.log> <season_plan1.log> <çıkış.json>"""
import json
import sys


def load(path):
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("RESULT_JSON "):
            return json.loads(line[len("RESULT_JSON "):])
    sys.exit("RESULT_JSON bulunamadı: " + path)


def margin4(sd):
    n = sum(sd.values())
    return round(100 * sum(v for k, v in sd.items() if abs(int(k.split("-")[0]) - int(k.split("-")[1])) >= 4) / max(1, n), 1)


L, P0, P1 = load(sys.argv[1]), load(sys.argv[2]), load(sys.argv[3])
L["margin4plus_pct"] = margin4(L["score_dist"])
for k in ["all", "lazy", "detailed", "top5_tier1", "SL"]:
    P0[k]["margin4plus_pct"] = margin4(P0[k]["score_dist"])
for t in P0["by_tier"]:
    P0["by_tier"][t]["margin4plus_pct"] = margin4(P0["by_tier"][t]["score_dist"])


def wk(P):
    return {"week_ms": P["week_ms"], "median": P["week_ms_median"], "p90": P["week_ms_p90"],
            "max": P["week_ms_max"], "min": P["week_ms_min"], "live_watched": P["live_watched"]}


out = {
    "version": "0.22-b4 (code 43)", "measured": "2026-10-15", "godot": "4.5.1-stable headless",
    "base_commit": "77c0f1d",
    "live_engine": L,
    "poisson_season": {k: v for k, v in P0.items() if not k.startswith("week_ms")},
    "week_timing": {
        "unwatched": wk(P0),
        "watch_one_live_per_week": wk(P1),
        "save_ms_median": P0["save_ms_median"], "save_bytes": P0["save_bytes"], "new_game_ms": P0["new_game_ms"],
        "v023_budget_ms": {
            "unwatched_median_x2": 2 * P0["week_ms_median"], "unwatched_max_x2": 2 * P0["week_ms_max"],
            "watched_median_x2": 2 * P1["week_ms_median"], "watched_max_x2": 2 * P1["week_ms_max"]},
    },
    "targets": {
        "source_note": "Top-5 Avrupa ligleri 2023-24/2024-25 ortalamaları + Süper Lig 2023-24; gerekçe BASELINE.md",
        "goals_per_match": [2.5, 3.1], "home_win_pct": [41, 48], "draw_pct": [22, 29], "away_win_pct": [27, 33],
        "nil_nil_pct": [4, 9], "margin4plus_pct": [2, 6],
        "SL": {"goals_per_match": [2.6, 3.0], "home_win_pct": [42, 50], "draw_pct": [22, 28]},
        "soft_live_only": {"shots_per_match": [22, 28], "shots_on_target_per_match": [7, 10],
                           "pass_accuracy_pct": [78, 86], "fouls_per_match": [19, 26],
                           "corners_per_match": [8, 11], "yellow_per_match": [3.0, 5.0],
                           "red_per_match": [0.08, 0.2]},
    },
}
json.dump(out, open(sys.argv[4], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(json.dumps(out["week_timing"]["v023_budget_ms"]))
