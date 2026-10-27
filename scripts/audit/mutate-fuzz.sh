#!/bin/sh
# mutate-fuzz.sh — mutation fuzz over real code: vidya's samples by
# default.
#
# Usage: sh scripts/audit/mutate-fuzz.sh [-s SEED] [-i ITERS] [FILE|DIR|- ...]
#   -s SEED   first seed (default 1); file k gets SEED + k
#   -i ITERS  mutants per file (default 50)
#
# With no FILE: vidya's content/ — $VIDYA/content, or ../vidya/content
# beside this repo — the per-topic samples in every language the AGNOS
# stack documents itself with (1,020 files at vidya 2026-10). The
# vidya commit is printed, so a run names the snapshot it used.
#
# Each file with a grammar gets ITERS mutants (harness `mutate`):
# bytes overwritten, the markers that open and close strings, comments,
# heredocs and compose regions inserted, ranges deleted or duplicated.
# Every mutant must tile its bytes and match one feed under random
# chunking and a random two-feed split. A failing mutant is written to
# build/audit/mutants/<path, `/` as `_`>-<iter>, ready for the
# harness's other modes.
#
# Exit: 0 when every mutant passed.
set -eu

AUDIT_CWD=$(pwd)
cd "$(dirname "$0")/../.."
. scripts/audit/common.sh

SEED=1
ITERS=50
while [ $# -gt 0 ]; do
    case "$1" in
        -s) SEED=$2; shift 2 ;;
        -i) ITERS=$2; shift 2 ;;
        --) shift; break ;;
        -?*) echo "mutate-fuzz: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
if [ $# -eq 0 ]; then
    V="${VIDYA:-$(pwd)/../vidya}"
    case "$V" in /*) ;; *) V="$AUDIT_CWD/$V" ;; esac
    if [ ! -d "$V/content" ]; then
        echo "mutate-fuzz: no FILE given and no vidya checkout at $V (set VIDYA=...)" >&2
        exit 2
    fi
    rev=$(git -C "$V" rev-parse --short HEAD 2>/dev/null || echo "not a git checkout")
    echo "mutate-fuzz: vidya $V @ $rev"
    set -- "$V/content"
fi

audit_build_harness
H=build/vyk-audit
mkdir -p build/audit/mutants

audit_tmpdir

audit_list "$T/list" "$@" || exit $?

n=0; tried=0; bad=0; k=0
while IFS= read -r f; do
    n=$((n + 1))
    k=$((k + 1))
    out="build/audit/mutants/$(printf '%s' "$f" | tr '/' '_')"
    rc=0
    audit_run 300 "$H" auto "$f" mutate $((SEED + k)) "$ITERS" "$out" > "$T/out" 2>&1 || rc=$?
    case $rc in
        0) tried=$((tried + 1)) ;;
        4) ;;
        124) tried=$((tried + 1)); bad=$((bad + 1)); echo "FAIL timeout: $f (seed $((SEED + k)))" ;;
        *) tried=$((tried + 1)); bad=$((bad + 1)); echo "FAIL exit $rc: $f (seed $((SEED + k)))"; head -5 "$T/out" ;;
    esac
done < "$T/list"

echo "mutate-fuzz: files=$n fuzzed=$tried mutants=$((tried * ITERS)) failing-files=$bad"
# Checked nothing — every file without a grammar — is no pass (2.9.12
# audit, reviewer D: each of these exited 0 then).
[ "$tried" -gt 0 ] || { echo "mutate-fuzz: nothing was fuzzed" >&2; exit 2; }
[ "$bad" -eq 0 ]
