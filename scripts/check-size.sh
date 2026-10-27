#!/bin/sh
# check-size.sh — report the shipped binary's size (ADR 0029).
#
# Releases ship the dead-code-eliminated build (CYRIUS_DCE=1,
# .github/workflows/release.yml). This builds or reads that binary and
# prints its size, so CI logs and release notes carry it. It is a report,
# not a limit: from 2.9.0 to 2.9.7 it failed above 307,200 bytes (the
# design spec's 300 KB target); since 2.9.8 there is no hard limit on the
# binary (ADR 0029, amended). It still fails when the DCE build fails or
# the binary cannot be read.
#
# Usage: sh scripts/check-size.sh [path/to/vyk]
#   With no argument, builds src/main.cyr with CYRIUS_DCE=1 into a
#   temporary file (src/grammar_blobs.cyr must exist — run
#   scripts/embed-grammars.sh first). With a path, measures that binary
#   as built (release.yml passes its DCE build).
set -eu

CALLER=$(pwd)
cd "$(dirname "$0")/.."

BIN="${1:-}"
if [ -z "$BIN" ]; then
    BIN="${TMPDIR:-/tmp}/vyk-size-$$"
    LOG="$BIN.log"
    trap 'rm -f "$BIN" "$LOG"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if ! CYRIUS_DCE=1 cyrius build src/main.cyr "$BIN" > "$LOG" 2>&1; then
        cat "$LOG" >&2
        echo "check-size: FAIL — the DCE build failed" >&2
        exit 1
    fi
fi

case "$BIN" in /*) ;; *) BIN="$CALLER/$BIN" ;; esac
if [ ! -f "$BIN" ] || [ ! -r "$BIN" ]; then
    echo "check-size: $BIN is not a readable file" >&2
    exit 1
fi

n=$(wc -c < "$BIN" | tr -d ' ')
case "$n" in
    ''|*[!0-9]*) echo "check-size: cannot measure $BIN" >&2; exit 1 ;;
esac
echo "check-size: $n bytes (the shipped CYRIUS_DCE=1 build; reported, not limited)"
