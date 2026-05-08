#!/bin/sh
# vyakarana smoke test — M0 (version/help/list).
# Usage: sh scripts/smoke.sh [path/to/vyk]    (default: build/vyk)
set -eu

BIN="${1:-build/vyk}"

if [ ! -x "$BIN" ]; then
    echo "smoke: $BIN not executable — run 'cyrius build src/main.cyr build/vyk' first" >&2
    exit 1
fi

# Resolve to absolute path so the isolated-dir probe further down
# can invoke vyk after `cd`.
case "$BIN" in
    /*) ABS_BIN="$BIN" ;;
    *)  ABS_BIN="$(pwd)/$BIN" ;;
esac

TMPDIR="${TMPDIR:-/tmp}/vyk-smoke-$$"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

fail() { echo "smoke: FAIL — $1" >&2; exit 1; }

# ============================================================
# Self-contained-bundle probe (1.11.1+).
# bootstrap_grammars must succeed without grammars/*.cyml on disk
# — that's the contract for downstream `cyrius deps` consumers,
# which only vendor dist/vyakarana.cyr (not the grammars/ dir).
# Run vyk from a fresh dir where no `grammars/` is reachable.
# ============================================================
ISOLATE="$TMPDIR/isolate"
mkdir -p "$ISOLATE"
SHELL_CORPUS="$(pwd)/tests/corpus/shell.sh"
isolated_count=$(cd "$ISOLATE" && "$ABS_BIN" --list-languages | wc -l)
[ "$isolated_count" -ge 30 ] \
    || fail "isolated --list-languages got $isolated_count grammars (expected ≥30; embedded blobs missing?)"
isolated_tokens=$(cd "$ISOLATE" && "$ABS_BIN" --language=shell "$SHELL_CORPUS" | wc -l)
[ "$isolated_tokens" -gt 100 ] \
    || fail "isolated tokenize got $isolated_tokens tokens (expected >100; blob path broken?)"

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
# adding a new grammar is a one-line change here.
llist=$("$BIN" --list-languages)
for lang in shell toml json cyrius rust yaml markdown c typescript javascript python go zig asm_x86_64 asm_aarch64 java kotlin cpp csharp php ruby lua swift elixir ocaml haskell sql graphql protobuf html xml css scss dockerfile makefile ini cyml llvm_ir; do
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

# --theme=<name> renders ANSI-coloured source instead of NDJSON.
# Probe: `--theme=default` on a real grammar file emits non-empty
# stdout containing at least one ESC; `--theme=none` emits the
# original source bytes (no colour escapes); unknown name errors
# with exit 2. See docs/architecture/004-theme-palette-contract.md.
set +e
"$BIN" --theme=default --language=shell tests/corpus/shell.sh > "$TMPDIR/themed" 2> "$TMPDIR/err"
rc=$?
set -e
[ "$rc" = "0" ] || fail "--theme=default exit: got $rc, expected 0; stderr: $(cat "$TMPDIR/err")"
[ -s "$TMPDIR/themed" ] || fail "--theme=default produced empty output"
grep -q "$(printf '\033')" "$TMPDIR/themed" \
    || fail "--theme=default missing ESC bytes — colour not emitted"

set +e
"$BIN" --theme=none --language=shell tests/corpus/shell.sh > "$TMPDIR/plain" 2> "$TMPDIR/err"
rc=$?
set -e
[ "$rc" = "0" ] || fail "--theme=none exit: got $rc, expected 0; stderr: $(cat "$TMPDIR/err")"
if grep -q "$(printf '\033')" "$TMPDIR/plain"; then
    fail "--theme=none must not emit ESC bytes"
fi

set +e
"$BIN" --theme=nope --language=shell tests/corpus/shell.sh > /dev/null 2>"$TMPDIR/err"
rc=$?
set -e
[ "$rc" = "2" ] || fail "--theme=nope exit: got $rc, expected 2"

# --export-theme=<format> (1.11.1+) emits a theme file for the
# named editor format and exits. Probe: vscode JSON has the
# expected shape and dark theme differs from default.
set +e
"$BIN" --export-theme=vscode > "$TMPDIR/vscode.json" 2> "$TMPDIR/err"
rc=$?
set -e
[ "$rc" = "0" ] || fail "--export-theme=vscode exit: got $rc, expected 0"
grep -q '"name": "vyakarana-default"' "$TMPDIR/vscode.json" \
    || fail "--export-theme=vscode missing name"
grep -q '"type": "light"' "$TMPDIR/vscode.json" \
    || fail "--export-theme=vscode missing light type"
grep -q '"scope": "keyword"' "$TMPDIR/vscode.json" \
    || fail "--export-theme=vscode missing keyword scope"

set +e
"$BIN" --theme=dark --export-theme=vscode > "$TMPDIR/vscode-dark.json" 2> "$TMPDIR/err"
rc=$?
set -e
[ "$rc" = "0" ] || fail "--export-theme=vscode (dark) exit: got $rc"
grep -q '"type": "dark"' "$TMPDIR/vscode-dark.json" \
    || fail "--theme=dark --export-theme=vscode missing dark type"

set +e
"$BIN" --export-theme=helix > /dev/null 2>"$TMPDIR/err"
rc=$?
set -e
[ "$rc" = "2" ] || fail "--export-theme=helix exit: got $rc, expected 2"

# Stderr sanitizer (FINDING-006 fix, shipped 1.0.1): control bytes
# in echoed user args must not reach the terminal. A path carrying
# ANSI-escape bytes should round-trip to stderr with the ESC replaced
# by `?`. POSIX octal `\033` is portable across dash / bash / zsh;
# `\xNN` and `$'...'` are not.
ESC=$(printf '\033')
CTL=$(printf 'ansi\033[2Jpath')
set +e
"$BIN" "$CTL" > /dev/null 2>"$TMPDIR/err"
rc=$?
set -e
if grep -q "$ESC" "$TMPDIR/err"; then
    fail "stderr contains ESC byte — sanitizer not applied: $(cat -A "$TMPDIR/err")"
fi
grep -q "ansi?\[2Jpath" "$TMPDIR/err" \
    || fail "sanitizer didn't replace ESC with '?': $(cat "$TMPDIR/err")"

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
# Bundled grammars — corpus round-trip
# ============================================================
#
# Each entry is "language:corpus-path". When adding a new grammar,
# append a line and the loop does the rest.

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
python:tests/corpus/python.py
go:tests/corpus/go.go
zig:tests/corpus/zig.zig
asm_x86_64:tests/corpus/asm_x86_64.s
asm_aarch64:tests/corpus/asm_aarch64.s
java:tests/corpus/concept.java
kotlin:tests/corpus/concept.kt
cpp:tests/corpus/concept.cpp
csharp:tests/corpus/concept.cs
php:tests/corpus/concept.php
ruby:tests/corpus/concept.rb
lua:tests/corpus/concept.lua
swift:tests/corpus/concept.swift
elixir:tests/corpus/concept.ex
ocaml:tests/corpus/concept.ml
haskell:tests/corpus/concept.hs
sql:tests/corpus/concept.sql
graphql:tests/corpus/concept.graphql
protobuf:tests/corpus/concept.proto
html:tests/corpus/concept.html
xml:tests/corpus/concept.xml
css:tests/corpus/concept.css
scss:tests/corpus/concept.scss
dockerfile:tests/corpus/Dockerfile
makefile:tests/corpus/Makefile
ini:tests/corpus/concept.ini
cyml:tests/corpus/dependencies.cyml
llvm_ir:tests/corpus/concept.ll
"

for entry in $M3_CORPUS_ENTRIES; do
    lang="${entry%%:*}"
    corpus="${entry##*:}"
    [ -f "$corpus" ] || fail "M3 corpus missing: $corpus"

    # Pass --language= explicitly so the corpus round-trip test is
    # deterministic. Extension dispatch is covered by the
    # --list-languages probe earlier; here we want to verify the
    # grammar itself, especially for languages that share an
    # extension (`.s` for both asm_x86_64 and asm_aarch64).
    set +e
    "$BIN" --language="$lang" "$corpus" > "$TMPDIR/$lang.ndjson" 2> "$TMPDIR/err"
    rc=$?
    set -e
    [ "$rc" = "0" ] \
        || fail "vyk --language=$lang $corpus: exit $rc (expected 0); stderr: $(cat "$TMPDIR/err")"
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
