#!/usr/bin/env bash
# v0.23 3b — Hibrit yol ölçümü (Dalga 3 kapısı, kesin eşikler, ≥5 seed × 2000 maç/yol).
# Kullanım: tests/baseline/hybrid_run.sh [çıkış_klasörü]
#   SEEDS="2301 4711 9001 1234 5678"  N_FAST=2000  N_LIVE=60  N_ENGINE=2000  SEASONS_MAX=8
#   MODE=ref COMMIT=<hash>  -> Dalga 3 ÖNCESİ commit'te kayıt boyutu referansı (tests/baseline/hybrid_ref.json)
# Çıkış: 0 = PASS ya da SKIP (quick_engine / yönlendirme yok), 1 = FAIL. Sonuç: <çıkış>/hybrid_report.json,
# hybrid_criteria.csv (kriter,sonuc,mesaj), hybrid_paths.csv (yol başına metrikler; test-lab panosu için).
# Süre (tahmini, seed başına): hızlı yol sezonda ~306 maç + shortlist → ~7 sezon ~3 dk,
# izlenen 60 maç ~3 dk, motor 2000 maç ≤10 sn; 5 seed toplam ~30 dk.
# Kendi user:// klasörünü kullanır (XDG_DATA_HOME); yine de başka Godot ölçümüyle aynı anda koşturmayın.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}"
OUT="${1:-$REPO/tests/baseline/out}"
mkdir -p "$OUT"
UD="$(mktemp -d "${TMPDIR:-/tmp}/gozcu-hybrid.XXXXXX")"
trap 'rm -rf "$UD"' EXIT
LOG="$OUT/hybrid_${MODE:-full}.log"
XDG_DATA_HOME="$UD" OUT="$OUT" timeout "${HYBRID_TIMEOUT:-7200}" "$GODOT" --headless --path "$REPO" res://tests/baseline/hybrid_stats.tscn >"$LOG" 2>&1
rc=$?
grep -v '^\[BC\]' "$LOG" | grep -E "^(OK|FAIL|BILGI|SKIP|HATA|ref |seed |çıktı|HYBRID_RESULT)" | cut -c1-220
if grep -qE "SCRIPT ERROR|Parse Error" "$LOG"; then
	echo "HATA: betik hatası, kayıt: $LOG"
	exit 1
fi
grep -q "^HYBRID_RESULT: \(PASS\|SKIP\)" "$LOG" && [[ $rc -eq 0 ]] && exit 0
exit 1
