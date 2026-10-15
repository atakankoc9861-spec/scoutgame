#!/usr/bin/env bash
# Gözcü test kapısı: tests/check/*_check testlerini bulur, her birini Godot headless ile çalıştırır.
#
# Kullanım: tools/dev/run_tests.sh [filtre]
#   filtre        isteğe bağlı; yalnızca adında bu metin geçen testler çalışır (ör. "season")
#
# Ortam değişkenleri:
#   GODOT         Godot 4.5.1 ikilisi (varsayılan /home/claude/godot/Godot_v4.5.1-stable_linux.x86_64)
#   TEST_TIMEOUT  test başına süre sınırı, saniye (varsayılan 900)
#   CHECK_SEED    testlere geçen RNG tohumu (varsayılan testin kendi sabiti)
#   KEEP_LOGS=1   başarılı testlerin kayıtlarını da sakla
#
# Test kuralı:
#   tests/check/<ad>_check.tscn  (kök düğümü <ad>_check.gd betiğini taşır)
#   ya da sahnesi olmayan tests/check/<ad>_check.gd (extends SceneTree, -s ile çalışır)
#   Başarıda quit(0), hatada quit(1). Ayrıca çıktıda "CHECK_RESULT: PASS" aranır;
#   ikisi birden yoksa test FAIL sayılır (asılı kalma, çökme, sessiz çıkış dahil).
#
# Her test kendi geçici user:// klasöründe çalışır (XDG_DATA_HOME), geliştiricinin kaydına dokunmaz.
# Çıkış kodu: tüm testler geçtiyse 0, en az biri kaldıysa 1, test bulunamadı/ortam hatası 2.

set -u

GODOT="${GODOT:-/home/claude/godot/Godot_v4.5.1-stable_linux.x86_64}"
TEST_TIMEOUT="${TEST_TIMEOUT:-900}"
FILTER="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK_DIR="$REPO/tests/check"

if [[ ! -x "$GODOT" ]]; then
	echo "HATA: Godot bulunamadı ya da çalıştırılamıyor: $GODOT (GODOT=... ile verin)" >&2
	exit 2
fi
if [[ ! -d "$CHECK_DIR" ]]; then
	echo "HATA: $CHECK_DIR yok" >&2
	exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gozcu-tests.XXXXXX")"
cleanup() { [[ "${KEEP_LOGS:-0}" == "1" ]] || [[ "${FAILED_ANY:-0}" == "1" ]] || rm -rf "$WORK"; }
trap cleanup EXIT

# Testleri bul: önce sahneler, sonra sahnesi olmayan betikler
declare -a TESTS=()
shopt -s nullglob
for f in "$CHECK_DIR"/*_check.tscn; do
	TESTS+=("$f")
done
for f in "$CHECK_DIR"/*_check.gd; do
	[[ -f "${f%.gd}.tscn" ]] || TESTS+=("$f")
done
shopt -u nullglob

if [[ -n "$FILTER" ]]; then
	declare -a SEL=()
	for t in "${TESTS[@]}"; do
		[[ "$(basename "$t")" == *"$FILTER"* ]] && SEL+=("$t")
	done
	TESTS=("${SEL[@]+"${SEL[@]}"}")
fi
if [[ ${#TESTS[@]} -eq 0 ]]; then
	echo "HATA: tests/check altında *_check testi bulunamadı${FILTER:+ (filtre: $FILTER)}" >&2
	exit 2
fi

# İçe aktarma önbelleği yoksa bir kez oluştur (yeni worktree)
if [[ ! -d "$REPO/.godot/imported" ]]; then
	echo "-- .godot yok, proje içe aktarılıyor (bir kez)..."
	timeout 900 "$GODOT" --headless --path "$REPO" --import >"$WORK/import.log" 2>&1 || true
fi

echo "== Gözcü testleri: ${#TESTS[@]} test, zaman aşımı ${TEST_TIMEOUT}s, Godot: $GODOT"
PASS=0
FAIL=0
FAILED_ANY=0
declare -a SUMMARY=()
T_ALL=$(date +%s)

for t in "${TESTS[@]}"; do
	rel="${t#"$REPO"/}"
	name="$(basename "$t")"
	name="${name%.*}"
	log="$WORK/$name.log"
	udata="$WORK/userdata-$name"
	mkdir -p "$udata"
	t0=$(date +%s)
	if [[ "$t" == *.tscn ]]; then
		XDG_DATA_HOME="$udata" timeout --kill-after=20 "$TEST_TIMEOUT" \
			"$GODOT" --headless --path "$REPO" "res://$rel" >"$log" 2>&1
	else
		XDG_DATA_HOME="$udata" timeout --kill-after=20 "$TEST_TIMEOUT" \
			"$GODOT" --headless --path "$REPO" -s "res://$rel" >"$log" 2>&1
	fi
	rc=$?
	dt=$(( $(date +%s) - t0 ))
	reason=""
	if [[ $rc -eq 124 || $rc -eq 137 ]]; then
		reason="zaman aşımı (${TEST_TIMEOUT}s)"
	elif [[ $rc -ne 0 ]]; then
		reason="çıkış kodu $rc"
	elif ! grep -q "^CHECK_RESULT: PASS" "$log"; then
		reason="çıkış 0 ama CHECK_RESULT: PASS satırı yok"
	fi
	if [[ -z "$reason" ]]; then
		PASS=$((PASS + 1))
		line=$(printf "PASS  %-28s %5ss" "$name" "$dt")
		echo "$line"
	else
		FAIL=$((FAIL + 1))
		FAILED_ANY=1
		line=$(printf "FAIL  %-28s %5ss  %s" "$name" "$dt" "$reason")
		echo "$line"
		echo "  ---- $name çıktısı (son 40 satır, [BC] satırları hariç) ----"
		grep -v '^\[BC\]' "$log" | tail -n 40 | sed 's/^/  | /'
		echo "  ---- tam kayıt: $log"
	fi
	SUMMARY+=("$line")
done

echo "== Sonuç: $PASS geçti, $FAIL kaldı, toplam $(( $(date +%s) - T_ALL ))s"
if [[ $FAIL -ne 0 ]]; then
	echo "== Kayıtlar: $WORK"
	exit 1
fi
exit 0
