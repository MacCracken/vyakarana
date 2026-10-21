#!/bin/sh
# check-size.sh — the shipped binary's size budget (ADR 0029).
#
# Releases ship the dead-code-eliminated build (CYRIUS_DCE=1,
# .github/workflows/release.yml). This checks that binary against the
# design spec's 300 KB target. From 1.13.0 to 2.8.0 the target was
# "soft" and nothing measured it; the shipped binary drifted to
# 408,680 bytes, mostly grammar comments embedded verbatim.
#
# Usage: sh scripts/check-size.sh [path/to/vyk]
#   With no argument, builds src/main.cyr with CYRIUS_DCE=1 into a
#   temporary file (src/grammar_blobs.cyr must exist — run
#   scripts/embed-grammars.sh first). With a path, checks that binary
#   as built (release.yml passes its DCE build).
set -eu

cd "$(dirname "$0")/.."

BUDGET=307200   # 300 KiB

BIN="${1:-}"
if [ -z "$BIN" ]; then
    BIN="${TMPDIR:-/tmp}/vyk-size-$$"
    LOG="$BIN.log"
    trap 'rm -f "$BIN" "$LOG"' EXIT INT TERM
    if ! CYRIUS_DCE=1 cyrius build src/main.cyr "$BIN" > "$LOG" 2>&1; then
        cat "$LOG" >&2
        echo "check-size: FAIL — the DCE build failed" >&2
        exit 1
    fi
fi

if [ ! -f "$BIN" ]; then
    echo "check-size: $BIN not found" >&2
    exit 1
fi

n=$(wc -c < "$BIN" | tr -d ' ')
if [ "$n" -gt "$BUDGET" ]; then
    echo "check-size: FAIL — $n bytes, over the $BUDGET-byte budget by $((n - BUDGET))" >&2
    exit 1
fi
echo "check-size: OK — $n bytes, $((BUDGET - n)) under the $BUDGET-byte budget"
