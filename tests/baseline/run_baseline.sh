#!/usr/bin/env bash
# Gözcü ölçüm temeli (çok seed): canlı motor + Poisson sezon + hafta süresi -> baseline.json
# Kullanım: tests/baseline/run_baseline.sh [çıkış_klasörü]
#   SEEDS="2301 4711 9001"  (varsayılan) — her seed için 3 ölçüm koşar
#   N=200                   canlı motor maç sayısı / seed
# Süre (2 çekirdek, seed başına): canlı 200 maç ~8 dk, plansız sezon ~15 sn, planlı sezon ~1,5 dk.
# DİKKAT: ölçümler sırayla koşar; aynı proje kopyasında paralel Godot çalıştırma (user:// kaydı ortak).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}"
OUT="${1:-$REPO/tests/baseline/out}"
SEEDS="${SEEDS:-2301 4711 9001}"
N="${N:-200}"
mkdir -p "$OUT"
run() { # $1=sahne $2=log, geri kalanı env
	local scene="$1" log="$2"; shift 2
	env "$@" timeout 2400 "$GODOT" --headless --path "$REPO" "$scene" >"$OUT/$log" 2>&1
	local rc=$?
	echo "$(date +%T) $log exit=$rc"
	grep -a "SCRIPT ERROR" -A4 "$OUT/$log" | head -8
}
for S in $SEEDS; do
	run res://tests/baseline/season_stats.tscn "season0_$S.log" PLAN=0 SEED="$S"
	run res://tests/baseline/season_stats.tscn "season1_$S.log" PLAN=1 SEED="$S"
	run res://tests/baseline/live_stats.tscn   "live_$S.log"    N="$N" LGS=SL,EN1,ES1,IT1,DE1 SEED="$S"
done
python3 "$REPO/tests/baseline/make_baseline.py" "$OUT" "$OUT/baseline.json" $SEEDS
