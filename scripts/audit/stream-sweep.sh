#!/bin/sh
# stream-sweep.sh — chunk invariance and streaming cost (ADR 0017,
# ADR 0028), with the audit harness (scripts/audit/harness.cyr).
#
# Usage: sh scripts/audit/stream-sweep.sh [-t SECS] [FILE|DIR|- ...]
#
# With no FILE, the fixed set:
#   - every corpus file under `every`: fed in two parts split at every
#     offset, each run equal to one feed (the bar since 2.8.0);
#   - the heredoc shapes in scripts/audit/shapes/ (from the 2.6.x
#     audit) plus four CR / CRLF ones generated here, under `every`
#     and `pairs` (every pair of split offsets);
#   - generated stress inputs under `cutfirst` with a time limit of
#     SECS (default 10) each: 512 KB tokens in 64-byte chunks, compose
#     blocks in 4 KB chunks, a 1 MiB one-line heredoc body in 512-byte
#     chunks, 20,000 unterminated heredoc openers, five inputs that
#     defeated 2.9.0's watches (2.9.1 audit) and four that were quadratic
#     on 2.9.11 (2.9.12 audit). Each was quadratic (3 s to
#     over 300 s) before its fix and takes well under a second after,
#     so a timeout here is a regression.
# With FILEs or DIRs (real files; the grammar is detected as vyk
# does), each file under `chunks 2`, `rand 11 6 400` and
# `cutfirst 4096 4096`.
#
# Exit: 0 when every run matched its single feed and none timed out,
# 1 otherwise, 2 when nothing was run (no FILE had a grammar).
set -eu

AUDIT_CWD=$(pwd)
cd "$(dirname "$0")/../.."
. scripts/audit/common.sh

SECS=10
while [ $# -gt 0 ]; do
    case "$1" in
        -t) SECS=$2; shift 2 ;;
        --) shift; break ;;
        -?*) echo "stream-sweep: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done

audit_build_harness
H=build/vyk-audit

audit_tmpdir

runs=0; bad=0

# check LIMIT LANG FILE MODE ARGS... — one harness run; FAIL on a
# non-zero exit (failures, read error, no grammar, crash) or a timeout.
check() {
    _lim=$1
    shift
    runs=$((runs + 1))
    _rc=0
    audit_run "$_lim" "$H" "$@" > "$T/out" 2>&1 || _rc=$?
    if [ "$_rc" -eq 124 ]; then
        bad=$((bad + 1)); echo "FAIL timeout (${_lim}s): $*"; return 0
    fi
    if [ "$_rc" -ne 0 ]; then
        bad=$((bad + 1)); echo "FAIL exit $_rc: $*"; head -5 "$T/out"
    fi
    return 0
}

# Generated stress inputs. `rep(s, n)` is s repeated n times.
gen() {
    LC_ALL=C awk "
        function rep(s, n,    r) { r = \"\"; while (n-- > 0) r = r s; return r }
        BEGIN { $2 }" > "$T/$1"
}

if [ $# -eq 0 ]; then
    for f in tests/corpus/*; do
        check 600 auto "$f" every
    done
    printf 'cat <<EOF\r\nbody\r\nEOF\r\necho x\r\n' > "$T/h05_crlf.sh"
    printf 'cat <<EOF\nb\nEOF\r\necho\n' > "$T/h22_term_crlf_mid.sh"
    printf 'cat <<EOF\r\nx\r\nEOF\n' > "$T/h33_crlf_opener.sh"
    printf 'cat <<EOF\nx\nEOF\recho\n' > "$T/h34_cr_only.sh"
    for f in scripts/audit/shapes/*.sh "$T"/h*.sh; do
        check 60 shell "$f" every
        check 60 shell "$f" pairs
    done
    gen long_comment.py 'k = rep("x", 1024); printf "#"; for (i = 0; i < 512; i++) printf "%s", k; printf "\n"'
    gen long_ident.py   'k = rep("a", 1024); for (i = 0; i < 512; i++) printf "%s", k; printf "\n"'
    gen long_ws.py      'k = rep(" ", 1024); printf "x ="; for (i = 0; i < 512; i++) printf "%s", k; printf "1\n"'
    gen long_number.py  'k = rep("1", 1024); printf "x = "; for (i = 0; i < 512; i++) printf "%s", k; printf "\n"'
    gen long_fstr.py    'k = rep("y", 1024); printf "x = f\""; for (i = 0; i < 512; i++) printf "%s", k; printf "\"\n"'
    gen long_fstr3.py   'k = rep("y", 63); printf "x = f\"\"\"\n"; for (i = 0; i < 8192; i++) printf "%s\n", k; printf "\"\"\"\n"'
    gen long_fence.md   'printf "# t\n\n```python\n"; for (i = 0; i < 55000; i++) printf "x = 1 + 2\n"; printf "```\n"'
    gen long_style.html 'printf "<html><style>\n"; for (i = 0; i < 30000; i++) printf "a { color: red; }\n"; printf "</style></html>\n"'
    gen open_style.html 'printf "<style>\n"; for (i = 0; i < 30000; i++) printf "a { color: red; }\n"'
    gen long_region.cyml 'printf "[a]\nk = 1\n---\n"; for (i = 0; i < 30000; i++) printf "text *em* `code`\n"; printf "\n[[b]]\nz = 2\n"'
    gen heredoc_1m.sh   'k = rep("z", 1024); printf "cat <<EOF\n"; for (i = 0; i < 1024; i++) printf "%s", k; printf "\nEOF\necho end\n"'
    gen heredoc_openers.sh 'for (i = 0; i < 20000; i++) printf ": <<b%d\n", i; printf "cat <<Z\nz # in body\nZ\necho end\n"'
    # 2.9.1 audit (reviewer B): each was quadratic on 2.9.0 at 64-byte
    # chunks — a heredoc whose delimiter quote removal rewrote (no watch:
    # over 300 s), a fence body full of mid-line "```" (11.6 s), a
    # heredoc line held open by a string full of `\"` (about 60 s), a
    # blank run in a heredoc grammar (30 s), a Zig `\\` string line (13 s).
    gen heredoc_rewritten.sh 'k = rep("x", 42); printf "cat <<E\\OF\n"; for (i = 0; i < 16000; i++) printf "body line %06d %s\n", i, k; printf "EOF\necho end\n"'
    gen fence_nearmiss.md 'printf "# t\n\n```python\n"; for (i = 0; i < 5000; i++) printf "s = \"```\" + x%06d\n", i; printf "```\n"'
    gen heredoc_quote.sh 'printf "cat <<EOF \"\nEOF\n"; for (i = 0; i < 30000; i++) printf "say \\\"hi\\\"\n"; printf "\"\necho end\n"'
    gen blank_run.sh 'k = rep(" ", 63); printf "x=1"; for (i = 0; i < 16384; i++) printf "%s\n", k; printf "echo end\n"'
    gen string_line.zig 'k = rep("abcdefgh", 8); printf "const s =\n    \\\\"; for (i = 0; i < 16384; i++) printf "%s", k; printf "\n;\n"'
    # 2.9.12 audit: quadratic on 2.9.11 at 64-byte chunks — a string ending
    # in a run of `\` (28 s), a shebang line with no line break (10 s), a
    # number of `_1` separators that each feed ends inside (20 s); and a
    # heredoc delimiter whose index bucket a crowd of lines shares (29 s).
    gen escape_run.py 'k = rep("\\", 1024); printf "x = \""; for (i = 0; i < 1024; i++) printf "%s", k; printf "\n"'
    gen shebang_long.sh 'k = rep("a", 1024); printf "#!"; for (i = 0; i < 1024; i++) printf "%s", k; printf "\n"'
    gen sep_number.rs 'printf "x = 1"; for (i = 0; i < 262144; i++) printf "_1"; printf ";\n"'
    gen hd_collide.php 'printf "<?php\n"; for (i = 0; i < 40000; i++) printf "$a = <<<BAK\n"'
    for f in long_comment.py long_ident.py long_ws.py long_number.py long_fstr.py long_fstr3.py \
        heredoc_rewritten.sh fence_nearmiss.md heredoc_quote.sh blank_run.sh string_line.zig \
        escape_run.py shebang_long.sh sep_number.rs; do
        check "$SECS" auto "$T/$f" cutfirst 64 64
    done
    for f in long_fence.md long_style.html open_style.html long_region.cyml heredoc_openers.sh hd_collide.php; do
        check "$SECS" auto "$T/$f" cutfirst 4096 4096
    done
    check "$SECS" auto "$T/heredoc_1m.sh" cutfirst 512 512
else
    audit_list "$T/list" "$@" || exit $?
    skipped=0
    while IFS= read -r f; do
        # Exit 4 is "no grammar": not a run, not a failure. (Captured
        # with `|| rc=$?`: under dash a `$(…; echo $?)` inherits `set -e`
        # and dies at the 4 before the echo — 2.9.1 audit.)
        rc=0
        audit_run 30 "$H" auto "$f" rand 0 0 1 > /dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 4 ]; then
            skipped=$((skipped + 1)); continue
        fi
        check 120 auto "$f" chunks 2
        check 120 auto "$f" rand 11 6 400
        check 120 auto "$f" cutfirst 4096 4096
    done < "$T/list"
    echo "stream-sweep: no grammar for $skipped file(s)"
fi

echo "stream-sweep: runs=$runs fails=$bad"
# Checked nothing — every file without a grammar — is no pass (2.9.12
# audit, reviewer D: each of these exited 0 then).
[ "$runs" -gt 0 ] || { echo "stream-sweep: nothing was run" >&2; exit 2; }
[ "$bad" -eq 0 ]
