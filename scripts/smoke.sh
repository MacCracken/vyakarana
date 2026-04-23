#!/bin/sh
# vyakarana smoke test — M0 (version/help/list).
# Usage: sh scripts/smoke.sh [path/to/vyk]    (default: build/vyk)
set -eu

BIN="${1:-build/vyk}"

if [ ! -x "$BIN" ]; then
    echo "smoke: $BIN not executable — run 'cyrius build src/main.cyr build/vyk' first" >&2
    exit 1
fi

TMPDIR="${TMPDIR:-/tmp}/vyk-smoke-$$"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

fail() { echo "smoke: FAIL — $1" >&2; exit 1; }

# ============================================================
# M0 — version / help / list
# ============================================================

v_long=$("$BIN" --version) || fail "--version exited non-zero"
[ -n "$v_long" ]            || fail "--version emitted nothing"

v_short=$("$BIN" -V) || fail "-V exited non-zero"
[ "$v_long" = "$v_short" ] || fail "-V disagrees with --version"

case "$v_long" in
    "vyk "*) ;;
    *) fail "--version output does not start with 'vyk ': $v_long" ;;
esac

h_long=$("$BIN" --help) || fail "--help exited non-zero"
[ -n "$h_long" ]         || fail "--help emitted nothing"

h_short=$("$BIN" -h) || fail "-h exited non-zero"
[ "$h_long" = "$h_short" ] || fail "-h disagrees with --help"

# --list-kinds must emit the ten kinds, one per line, in palette order.
klist=$("$BIN" --list-kinds)
lines=$(printf '%s\n' "$klist" | wc -l | tr -d ' ')
[ "$lines" = "10" ] || fail "--list-kinds emitted $lines lines, expected 10"
for k in ident keyword string number comment operator punctuation whitespace preprocessor error; do
    printf '%s\n' "$klist" | grep -q "^$k\$" || fail "--list-kinds missing '$k'"
done

# --list-languages is silent in M0 (no grammars loaded).
llist=$("$BIN" --list-languages)
[ -z "$llist" ] || fail "--list-languages emitted output in v0.1.0: '$llist'"

# Unknown option → exit 2, error on stderr.
set +e
"$BIN" --frobnicate > /dev/null 2>"$TMPDIR/err"
rc=$?
set -e
[ "$rc" = "2" ] || fail "unknown-option exit: got $rc, expected 2"
grep -q "^vyk: unknown option: --frobnicate" "$TMPDIR/err" \
    || fail "unknown-option stderr format wrong: $(cat "$TMPDIR/err")"

echo "smoke: OK ($v_long) — M0 gates passing"
