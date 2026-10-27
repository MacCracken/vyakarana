#!/bin/sh
# ab-sweep.sh — what a change does to single-feed output: two `vyk`
# binaries over the same real files, side by side.
#
# Usage: sh scripts/audit/ab-sweep.sh [-t SECS] OLD NEW FILE|DIR|- ...
#   OLD, NEW   two vyk binaries (a release's and the tree's)
#
# Prints one line for every file whose output or exit differs:
#   DIFF rc A->B err A->B big A->B FILE
# with the exit codes, the error-token counts and the largest token's
# length of each. Read the largest token, not only the error count: the
# 2.9.10 change that ran unclosed markdown fences to the end of a file
# grew one CHANGELOG's largest token from 29 KB to 300 KB without a
# single error token, and an error-count A/B passed it (2.9.12 audit,
# reviewer A, G-A1).
#
# Exit: 0 when both binaries ran on every file (differences are for the
# reader to judge), 1 when either one crashed (a signal) or timed out,
# 2 when nothing was compared.
set -eu

AUDIT_CWD=$(pwd)
cd "$(dirname "$0")/../.."
. scripts/audit/common.sh

SECS=60
while [ $# -gt 0 ]; do
    case "$1" in
        -t) SECS=$2; shift 2 ;;
        --) shift; break ;;
        -?*) echo "ab-sweep: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
if [ $# -lt 3 ]; then
    echo "usage: sh scripts/audit/ab-sweep.sh [-t SECS] OLD NEW FILE|DIR|- ..." >&2
    exit 2
fi
OLD=$1; NEW=$2; shift 2
case "$OLD" in /*) ;; *) OLD=$AUDIT_CWD/$OLD ;; esac
case "$NEW" in /*) ;; *) NEW=$AUDIT_CWD/$NEW ;; esac
for b in "$OLD" "$NEW"; do
    [ -x "$b" ] || { echo "ab-sweep: not an executable: $b" >&2; exit 2; }
done

audit_tmpdir
audit_list "$T/list" "$@" || exit $?

# stats FILE — "ERRORS LARGEST" of an NDJSON token file.
stats() {
    awk -F'"' '
        { if ($4 == "error") e++
          if (match($0, /"len":[0-9]+/)) { l = substr($0, RSTART + 6, RLENGTH - 6) + 0; if (l > big) big = l } }
        END { printf "%d %d", e, big }' "$1"
}

n=0; d=0; bad=0
while IFS= read -r f; do
    n=$((n + 1))
    ra=0; rb=0
    audit_run "$SECS" "$OLD" -- "$f" > "$T/a" 2> /dev/null || ra=$?
    audit_run "$SECS" "$NEW" -- "$f" > "$T/b" 2> /dev/null || rb=$?
    if [ "$ra" -ge 124 ] || [ "$rb" -ge 124 ]; then
        bad=$((bad + 1)); echo "FAIL (exit $ra/$rb): $f"; continue
    fi
    if [ "$ra" -ne "$rb" ] || ! cmp -s "$T/a" "$T/b"; then
        d=$((d + 1))
        sa=$(stats "$T/a"); sb=$(stats "$T/b")
        echo "DIFF rc $ra->$rb err ${sa% *}->${sb% *} big ${sa#* }->${sb#* } $f"
    fi
done < "$T/list"

echo "ab-sweep: files=$n diffs=$d failed=$bad"
[ "$n" -gt 0 ] || { echo "ab-sweep: nothing was compared" >&2; exit 2; }
[ "$bad" -eq 0 ]
