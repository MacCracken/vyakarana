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

# --list-languages lists loaded grammars (see bootstrap_grammars in
# src/tokenize.cyr). Assert presence rather than exact order so that
# adding grammars in M3 is a one-line change here.
llist=$("$BIN" --list-languages)
for lang in shell toml json cyrius rust yaml markdown c typescript javascript; do
    printf '%s\n' "$llist" | grep -q "^$lang\$" \
        || fail "--list-languages missing '$lang': '$llist'"
done

# Unknown option → exit 2, error on stderr.
set +e
"$BIN" --frobnicate > /dev/null 2>"$TMPDIR/err"
rc=$?
set -e
[ "$rc" = "2" ] || fail "unknown-option exit: got $rc, expected 2"
grep -q "^vyk: unknown option: --frobnicate" "$TMPDIR/err" \
    || fail "unknown-option stderr format wrong: $(cat "$TMPDIR/err")"

# ============================================================
# M1 — shell grammar tokenizes the vidya corpus cleanly
# ============================================================

CORPUS="tests/corpus/shell.sh"
[ -f "$CORPUS" ] || fail "corpus missing: $CORPUS"

set +e
"$BIN" "$CORPUS" > "$TMPDIR/tokens.ndjson" 2> "$TMPDIR/err"
rc=$?
set -e
[ "$rc" = "0" ] || fail "vyk $CORPUS: exit $rc (expected 0); stderr: $(cat "$TMPDIR/err")"
[ -s "$TMPDIR/tokens.ndjson" ] || fail "vyk $CORPUS: empty NDJSON output"

# Zero error-kind tokens (design-spec §3.2 + §3.1).
if grep -q '"kind":"error"' "$TMPDIR/tokens.ndjson"; then
    n=$(grep -c '"kind":"error"' "$TMPDIR/tokens.ndjson")
    fail "$n error-kind tokens in NDJSON; shell grammar has a gap"
fi

# Coverage invariant: sum of all len fields == file bytes.
bytes=$(wc -c < "$CORPUS" | tr -d ' ')
sumlen=$(grep -oE '"len":[0-9]+' "$TMPDIR/tokens.ndjson" | cut -d: -f2 \
    | awk '{s+=$1} END {print s+0}')
[ "$sumlen" = "$bytes" ] \
    || fail "coverage invariant: token len sum $sumlen != file bytes $bytes"

# First token must be the shebang (preprocessor @0).
head -1 "$TMPDIR/tokens.ndjson" \
    | grep -q '^{"kind":"preprocessor","start":0' \
    || fail "first token is not shebang preprocessor @0: $(head -1 "$TMPDIR/tokens.ndjson")"

# --language override works on an extensionless path.
cp "$CORPUS" "$TMPDIR/noext"
set +e
"$BIN" --language=shell "$TMPDIR/noext" > /dev/null 2> "$TMPDIR/err"
rc=$?
set -e
[ "$rc" = "0" ] || fail "--language=shell on extensionless: rc=$rc, stderr=$(cat "$TMPDIR/err")"

# ============================================================
# M2 — CYML-driven shell grammar matches M1 hand-coded byte-for-byte
# ============================================================

GRAMMAR="grammars/shell.cyml"
[ -f "$GRAMMAR" ] || fail "grammar missing: $GRAMMAR"

# --list-languages now includes shell via the grammar registry.
printf '%s\n' "$llist" | grep -q "^shell\$" \
    || fail "--list-languages: shell not listed after M2 registry load"

# Regression: hand-coded (M1) vs data-driven (M2) token output must
# be byte-identical. --handcoded is an undocumented diagnostic flag
# wired only for this check.
"$BIN" --handcoded "$CORPUS" > "$TMPDIR/m1.ndjson" 2> "$TMPDIR/err" \
    || fail "handcoded oracle run failed: $(cat "$TMPDIR/err")"
"$BIN" "$CORPUS" > "$TMPDIR/m2.ndjson" 2> "$TMPDIR/err" \
    || fail "data-driven run failed: $(cat "$TMPDIR/err")"

if ! diff -q "$TMPDIR/m1.ndjson" "$TMPDIR/m2.ndjson" > /dev/null; then
    echo "smoke: M2 REGRESSION — data-driven differs from M1 oracle" >&2
    diff "$TMPDIR/m1.ndjson" "$TMPDIR/m2.ndjson" | head -20 >&2
    fail "CYML-driven shell grammar drifts from hand-coded reference"
fi

# ============================================================
# M3 — additional bundled grammars
# ============================================================
#
# Each entry is "language:corpus-path". When adding a new grammar
# in M3, append a line and the loop does the rest.

M3_CORPUS_ENTRIES="
toml:tests/corpus/concept.toml
json:tests/corpus/concept.json
cyrius:tests/corpus/cyrius.cyr
rust:tests/corpus/rust.rs
yaml:tests/corpus/concept.yaml
markdown:tests/corpus/concept.md
c:tests/corpus/c.c
typescript:tests/corpus/typescript.ts
javascript:tests/corpus/concept.js
"

for entry in $M3_CORPUS_ENTRIES; do
    lang="${entry%%:*}"
    corpus="${entry##*:}"
    [ -f "$corpus" ] || fail "M3 corpus missing: $corpus"

    set +e
    "$BIN" "$corpus" > "$TMPDIR/$lang.ndjson" 2> "$TMPDIR/err"
    rc=$?
    set -e
    [ "$rc" = "0" ] \
        || fail "vyk $corpus ($lang): exit $rc (expected 0); stderr: $(cat "$TMPDIR/err")"
    [ -s "$TMPDIR/$lang.ndjson" ] \
        || fail "vyk $corpus ($lang): empty NDJSON"

    if grep -q '"kind":"error"' "$TMPDIR/$lang.ndjson"; then
        n=$(grep -c '"kind":"error"' "$TMPDIR/$lang.ndjson")
        fail "$n error-kind tokens for $lang; grammar has a gap"
    fi

    bytes=$(wc -c < "$corpus" | tr -d ' ')
    sumlen=$(grep -oE '"len":[0-9]+' "$TMPDIR/$lang.ndjson" | cut -d: -f2 \
        | awk '{s+=$1} END {print s+0}')
    [ "$sumlen" = "$bytes" ] \
        || fail "$lang coverage: token len sum $sumlen != file bytes $bytes"
done

echo "smoke: OK ($v_long) — M0 + M1 + M2 + M3 gates passing"
