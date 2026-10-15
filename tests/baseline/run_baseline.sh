#!/usr/bin/env bash
# Gözcü ölçüm temeli: canlı motor + Poisson sezon + hafta süresi -> baseline.json
# Kullanım: tests/baseline/run_baseline.sh [çıkış_klasörü]
# Süre (2 çekirdek): canlı 200 maç ~8-9 dk, plansız sezon ~15 sn, planlı sezon ~1.5 dk.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}"
OUT="${1:-$REPO/tests/baseline/out}"
mkdir -p "$OUT"
run() { # $1=log, geri kalanı env
	local log="$1"; shift
	env "$@" timeout 1800 "$GODOT" --headless --path "$REPO" "$SCENE" >"$OUT/$log" 2>&1
	echo "$log exit=$?"
	grep -a "SCRIPT ERROR" -A4 "$OUT/$log" | head -8
}
SCENE=res://tests/baseline/live_stats.tscn   run live.log    N=200 LGS=SL,EN1,ES1,IT1,DE1 SEED=2301
SCENE=res://tests/baseline/season_stats.tscn run season0.log PLAN=0 SEED=2301
SCENE=res://tests/baseline/season_stats.tscn run season1.log PLAN=1 SEED=2301
python3 "$REPO/tests/baseline/make_baseline.py" "$OUT/live.log" "$OUT/season0.log" "$OUT/season1.log" "$OUT/baseline.json"
