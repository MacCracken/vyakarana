#!/bin/sh
# poison-ab.sh — catch reads of memory nobody wrote, over real files.
#
# Usage: sh scripts/audit/poison-ab.sh [-t SECS] FILE|DIR|- ...
#
# Builds vyk twice with cyrius's poisoning allocators (CYRIUS_POISON=1):
# leg A fills fresh and freed memory with 0xA5, leg B (with
# `-D CYRIUS_POISON_B`) with 0x5A, and both put redzones around every
# block. Each file must give byte-identical stdout and the same exit
# code from both legs: a difference means some output depended on
# memory no one wrote. Exit 86 from either leg is the allocator
# reporting a write past a block. (`cyrius fuzz --poison=ab` does the
# same for the fuzz harnesses; this does it for vyk over real input.)
#
# Exit: 0 when no file differs and nothing was overwritten.
set -eu

AUDIT_CWD=$(pwd)
cd "$(dirname "$0")/../.."
. scripts/audit/common.sh

SECS=60
while [ $# -gt 0 ]; do
    case "$1" in
        -t) SECS=$2; shift 2 ;;
        --) shift; break ;;
        -?*) echo "poison-ab: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
if [ $# -eq 0 ]; then
    echo "usage: sh scripts/audit/poison-ab.sh [-t SECS] FILE|DIR|- ..." >&2
    exit 2
fi

mkdir -p build
sh scripts/embed-grammars.sh > /dev/null
if ! CYRIUS_POISON=1 cyrius build src/main.cyr build/vyk-poisonA > build/vyk-poison.log 2>&1 ||
   ! CYRIUS_POISON=1 cyrius build -D CYRIUS_POISON_B src/main.cyr build/vyk-poisonB >> build/vyk-poison.log 2>&1; then
    cat build/vyk-poison.log >&2
    echo "poison-ab: building the poisoned binaries failed" >&2
    exit 1
fi

audit_tmpdir

audit_list "$T/list" "$@" || exit $?

n=0; diffs=0; overwrites=0; timeouts=0
while IFS= read -r f; do
    n=$((n + 1))
    ra=0; rb=0
    audit_run "$SECS" build/vyk-poisonA -- "$f" > "$T/a" 2> "$T/ea" || ra=$?
    audit_run "$SECS" build/vyk-poisonB -- "$f" > "$T/b" 2> "$T/eb" || rb=$?
    if [ "$ra" -eq 124 ] || [ "$rb" -eq 124 ]; then
        timeouts=$((timeouts + 1)); echo "TIMEOUT ($ra/$rb): $f"; continue
    fi
    if [ "$ra" -eq 86 ] || [ "$rb" -eq 86 ]; then
        overwrites=$((overwrites + 1))
        echo "OVERWRITE (exit $ra/$rb): $f :: $(cat "$T/ea" "$T/eb" | grep 'poison:' | head -1)"
    fi
    if [ "$ra" -ne "$rb" ] || ! cmp -s "$T/a" "$T/b"; then
        diffs=$((diffs + 1)); echo "A/B DIFF (exit $ra/$rb): $f"
    fi
done < "$T/list"

echo "poison-ab: files=$n ab-diffs=$diffs overwrites=$overwrites timeouts=$timeouts"
[ "$diffs" -eq 0 ] && [ "$overwrites" -eq 0 ] && [ "$timeouts" -eq 0 ]
