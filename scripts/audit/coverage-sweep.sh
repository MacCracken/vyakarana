#!/bin/sh
# coverage-sweep.sh — run vyk over real files and check every output.
#
# Usage: sh scripts/audit/coverage-sweep.sh [-b VYK] [-t SECS] FILE|DIR|- ...
#   -b VYK   the binary to check (default: build/vyk, rebuilt first)
#   -t SECS  per-file limit (default 30)
#
# For each file, `vyk FILE`. Exit 4 (no grammar) and a file over the
# CLI's 1 MiB input cap (exit 3, "file too large" — the library has no
# such cap) are counted and skipped. For exits 0 and 1 the NDJSON is
# checked: every line a token
# record of one of the ten kinds, each token starting where the last
# ended, none empty, the last ending at the file's size (the coverage
# invariant); exit 1 must come with at least one error token and exit 0
# with none. Any other exit, a timeout, or a failed check is a FAIL
# line. Files with error tokens are listed (ERRTOK) but are not failures
# — real files can be invalid.
#
# Exit: 0 when nothing FAILed. (2.5.x – 2.8.0 audits ran a Python
# version of this; it skipped the checks whenever vyk exited 1.)
set -eu

AUDIT_CWD=$(pwd)
cd "$(dirname "$0")/../.."
. scripts/audit/common.sh

VYK=""
SECS=30
while [ $# -gt 0 ]; do
    case "$1" in
        -b) VYK=$2; shift 2 ;;
        -t) SECS=$2; shift 2 ;;
        --) shift; break ;;
        -?*) echo "coverage-sweep: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
if [ $# -eq 0 ]; then
    echo "usage: sh scripts/audit/coverage-sweep.sh [-b VYK] [-t SECS] FILE|DIR|- ..." >&2
    exit 2
fi
if [ -z "$VYK" ]; then
    audit_build_vyk
    VYK=build/vyk
else
    case "$VYK" in /*) ;; *) VYK="$AUDIT_CWD/$VYK" ;; esac
fi

audit_tmpdir

audit_list "$T/list" "$@" || exit $?

n=0; skipped=0; overcap=0; fails=0; errfiles=0; tokens=0
while IFS= read -r f; do
    n=$((n + 1))
    size=$(wc -c < "$f" | tr -d ' ')
    rc=0
    audit_run "$SECS" "$VYK" -- "$f" > "$T/out" 2> "$T/err" || rc=$?
    case $rc in
        4) skipped=$((skipped + 1)); continue ;;
        0|1) ;;
        3)
            if grep -q 'file too large' "$T/err"; then
                overcap=$((overcap + 1)); echo "OVERCAP ($size bytes): $f"; continue
            fi
            fails=$((fails + 1)); echo "FAIL exit 3: $f :: $(head -c 160 "$T/err")"; continue ;;
        124) fails=$((fails + 1)); echo "FAIL timeout (${SECS}s): $f"; continue ;;
        *) fails=$((fails + 1)); echo "FAIL exit $rc: $f :: $(head -c 160 "$T/err")"; continue ;;
    esac
    # One line: "<verdict> <tokens> <error tokens> <first error offset>".
    res=$(LC_ALL=C awk -v size="$size" '
        BEGIN {
            pos = 0; errs = 0; first = -1; bad = ""
            split("ident keyword string number comment operator punctuation whitespace preprocessor error", K, " ")
            for (i in K) kind[K[i]] = 1
        }
        bad != "" { next }
        {
            if ($0 !~ /^[{]"kind":"[a-z]+","start":[0-9]+,"len":[0-9]+[}]$/) {
                bad = "line " NR " is not a token record"; next
            }
            line = $0
            gsub(/[{}"]/, "", line)
            split(line, f, ",")
            split(f[1], k, ":"); split(f[2], s, ":"); split(f[3], l, ":")
            if (!(k[2] in kind)) { bad = "line " NR ": unknown kind " k[2]; next }
            if (s[2] + 0 != pos) { bad = "token " NR " starts at " s[2] ", expected " pos; next }
            if (l[2] + 0 <= 0) { bad = "token " NR " is empty"; next }
            if (k[2] == "error") { errs++; if (first < 0) first = pos }
            pos += l[2]
        }
        END {
            if (bad == "" && pos != size) bad = "tokens end at " pos ", file is " size
            if (bad == "") bad = "ok"
            gsub(/ /, "_", bad)
            print bad, NR, errs, first
        }' "$T/out")
    set -- $res
    verdict=$1
    ntok=$2
    nerr=$3
    at=$4
    tokens=$((tokens + ntok))
    if [ "$verdict" != ok ]; then
        fails=$((fails + 1)); echo "FAIL $(echo "$verdict" | tr '_' ' '): $f"; continue
    fi
    if [ "$rc" -eq 1 ] && [ "$nerr" -eq 0 ]; then
        fails=$((fails + 1)); echo "FAIL exit 1 with no error token: $f"; continue
    fi
    if [ "$rc" -eq 0 ] && [ "$nerr" -gt 0 ]; then
        fails=$((fails + 1)); echo "FAIL exit 0 with $nerr error token(s): $f"; continue
    fi
    if [ "$nerr" -gt 0 ]; then
        errfiles=$((errfiles + 1)); echo "ERRTOK $nerr (first at byte $at): $f"
    fi
done < "$T/list"

echo "coverage-sweep: files=$n tokenized=$((n - skipped - overcap)) no-grammar=$skipped over-cap=$overcap tokens=$tokens fails=$fails files-with-error-tokens=$errfiles"
[ "$fails" -eq 0 ]
