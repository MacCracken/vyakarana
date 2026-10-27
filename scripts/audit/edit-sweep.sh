#!/bin/sh
# edit-sweep.sh — incremental retokenization (ADR 0033), with the audit
# harness (scripts/audit/harness.cyr, mode `edits`).
#
# Usage: sh scripts/audit/edit-sweep.sh [-s STRIDE] [-t SECS] [FILE|DIR|- ...]
#
# Each run edits a whole file at every STRIDE-th offset — a marker
# inserted, bytes deleted, or bytes replaced by a marker — through a
# `tokenize_doc` document, and holds the result to one feed of the
# edited text and the undo to the original's. `fuzz/retokenize.fcyr`
# (CI) edits every offset too, but in 1 KB windows of each corpus; this
# takes whole files, so an edit can reach as far as the text lets it.
#
# With no FILE: every corpus file at STRIDE (default 1), at the default
# checkpoint spacing and at 48 bytes. With FILEs or DIRs (real files;
# the grammar is detected as vyk does): each at STRIDE (default 97) and
# the default spacing. Each run has a limit of SECS (default 900).
#
# Exit: 0 when every edit and undo matched and none timed out.
set -eu

AUDIT_CWD=$(pwd)
cd "$(dirname "$0")/../.."
. scripts/audit/common.sh

STRIDE=""
SECS=900
while [ $# -gt 0 ]; do
    case "$1" in
        -s) STRIDE=$2; shift 2 ;;
        -t) SECS=$2; shift 2 ;;
        --) shift; break ;;
        -?*) echo "edit-sweep: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done

audit_build_harness
H=build/vyk-audit

audit_tmpdir

runs=0; bad=0

# check LANG FILE STRIDE INTERVAL — one harness run; FAIL on a non-zero
# exit (failures, read error, no grammar, crash) or a timeout.
check() {
    runs=$((runs + 1))
    _rc=0
    audit_run "$SECS" "$H" "$1" "$2" edits "$3" "$4" > "$T/out" 2>&1 || _rc=$?
    if [ "$_rc" -eq 124 ]; then
        bad=$((bad + 1)); echo "FAIL timeout (${SECS}s): $*"; return 0
    fi
    if [ "$_rc" -ne 0 ]; then
        bad=$((bad + 1)); echo "FAIL exit $_rc: $*"; head -5 "$T/out"
    fi
    return 0
}

if [ $# -eq 0 ]; then
    [ -n "$STRIDE" ] || STRIDE=1
    for f in tests/corpus/*; do
        check auto "$f" "$STRIDE" 4096
        check auto "$f" "$STRIDE" 48
    done
else
    [ -n "$STRIDE" ] || STRIDE=97
    audit_list "$T/list" "$@" || exit $?
    skipped=0
    while IFS= read -r f; do
        # Exit 4 is "no grammar": not a run, not a failure.
        rc=0
        audit_run 30 "$H" auto "$f" rand 0 0 1 > /dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 4 ]; then
            skipped=$((skipped + 1)); continue
        fi
        check auto "$f" "$STRIDE" 4096
    done < "$T/list"
    echo "edit-sweep: no grammar for $skipped file(s)"
fi

echo "edit-sweep: runs=$runs fails=$bad"
# Checked nothing — every file without a grammar — is no pass (2.9.12
# audit, reviewer D: each of these exited 0 then).
[ "$runs" -gt 0 ] || { echo "edit-sweep: nothing was run" >&2; exit 2; }
[ "$bad" -eq 0 ]
