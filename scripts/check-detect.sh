#!/bin/sh
# vyakarana — every route compiled into src/detect.cyr is declared by
# its grammar (ADR 0025).
#
# Detection is compiled; each grammar's `[grammar]` table declares
# what routes to it (`extensions`, `filenames`, `shebangs`). This is
# the source-side half of the check that keeps the two equal. One awk
# pass reads the WHOLE file, tracking the enclosing `fn` and its
# `if (n >= K)` guard, and sorts every relevant line into:
#
#   - a path route `memeq(path + n - K, "LIT", K) == 1) { return "LANG"; }`:
#     K equals the literal's length (a wrong K silently never matches),
#     the enclosing `n >=` guard is at least that long (or the read
#     starts before `path`), and LIT is in grammars/LANG.cyml's
#     `extensions` (or `filenames`, for a literal without a dot);
#   - a filename route `_detect_fname(path, n, "NAME") == 1) { return "LANG"; }`:
#     NAME is in LANG's `filenames`;
#   - an interpreter route `memeq(src + word_start, "NAME", K) == 1)) { return "LANG"; }`:
#     K equals NAME's length, a name over 2 bytes has a `wlen >= K`
#     guard on the line (`_detect_shebang` returns early below 2), and
#     NAME is in LANG's `shebangs`;
#   - anything else that could be a route — a `return "…"` outside
#     the content sniff (`_detect_signature`, `_detect_asm_flavor`),
#     or a `memeq(path + n - …` / `_detect_fname(…)` /
#     `memeq(src + word_start, …` line not in the shapes above (a
#     variable return, a missing literal) — is reported as
#     unrecognised. A route in a shape this script cannot read fails
#     loudly instead of passing unchecked. (2.6.2's first version read
#     only two functions and passed a route added anywhere else; the
#     2.6.x audit caught it.)
#
# The other half — every declared entry routes to its grammar — is the
# "2.6.2 detection matches grammar declarations" group in
# tests/vyakarana.tcyr. Run from the repo root; smoke.sh calls it.
# POSIX sh + awk + grep only (CI's /bin/sh is dash, its awk mawk).
set -eu

DETECT="src/detect.cyr"
[ -f "$DETECT" ] || { echo "check-detect: run from the repo root" >&2; exit 1; }

bad=0
err() { echo "check-detect: $1" >&2; bad=$((bad + 1)); }

# The `[grammar]` array line `key = [...]` of grammar $1, or empty.
decl() {
    f="grammars/$1.cyml"
    [ -f "$f" ] || { echo ""; return 0; }
    grep -E "^$2 *=" "$f" | head -n 1 || true
}

# 1 if array line $1 contains the quoted literal $2.
has() {
    case "$1" in
        *"\"$2\""*) echo 1 ;;
        *) echo 0 ;;
    esac
}

TMP="${TMPDIR:-/tmp}/vyk-check-detect-$$"
trap 'rm -f "$TMP".*' EXIT INT TERM

# Records, tab-separated; "-" stands for an empty field (`read` would
# collapse an empty one, tab being IFS whitespace).
awk '
function num_after(s, lit,    i, r) {
    i = index(s, lit)
    if (i == 0) return "-"
    r = substr(s, i + length(lit))
    if (match(r, /^[0-9]+/) == 0) return "-"
    return substr(r, RSTART, RLENGTH)
}
/^fn [A-Za-z0-9_]+\(/ { f = $0; sub(/^fn /, "", f); sub(/\(.*/, "", f); guard = 0 }
/^    if \(n >= [0-9]+\) \{/ { guard = num_after($0, "n >= ") + 0 }
/^    \}/ { guard = 0 }
{
    line = $0
    if (line ~ /^[ \t]*#/) next
    split(line, q, "\"")
    if (line ~ /memeq\(path \+ n - [0-9]+, "[^"]*", [0-9]+\) == 1\) \{ return "[^"]*"; \}/) {
        printf "EXT\t%s\t%d\t%s\t%s\t%s\t%s\n", f, guard, num_after(line, "path + n - "), q[2], num_after(line, "\"" q[2] "\", "), q[4]
        next
    }
    if (line ~ /_detect_fname\(path, n, "[^"]*"\) == 1\) \{ return "[^"]*"; \}/) {
        printf "FNM\t%s\t%s\t%s\n", f, q[2], q[4]
        next
    }
    if (line ~ /memeq\(src \+ word_start, "[^"]*", [0-9]+\) == 1\)\) \{ return "[^"]*"; \}/) {
        printf "INT\t%s\t%s\t%s\t%s\t%s\n", f, q[2], num_after(line, "\"" q[2] "\", "), num_after(line, "wlen >= "), q[4]
        next
    }
    odd = 0
    if ((index(line, "memeq(path + n - ") > 0) && (f != "_detect_fname")) odd = 1
    if ((index(line, "_detect_fname(path, n, ") > 0) && (line !~ /^fn /)) odd = 1
    if ((index(line, "memeq(src + word_start, \"") > 0) && (q[2] != "env")) odd = 1
    if ((index(line, "return \"") > 0) && (f != "_detect_signature") && (f != "_detect_asm_flavor")) odd = 1
    if (odd == 1) printf "ODD\t%s\t%d\t%s\n", f, NR, line
}
' "$DETECT" > "$TMP.rec"

TAB=$(printf '\t')
n_ext=0; n_fn=0; n_sb=0
while IFS="$TAB" read -r tag a b c d e g; do
    case "$tag" in
    EXT)    # a=fn b=guard c=K1 d=LIT e=K2 g=LANG
        n_ext=$((n_ext + 1))
        len=${#d}
        [ "$c" = "$len" ] && [ "$e" = "$len" ] \
            || err "$d -> $g ($a): memeq length $c/$e, literal is $len bytes"
        [ "$b" -ge "$len" ] \
            || err "$d -> $g ($a): enclosing guard is n >= $b, the read needs n >= $len"
        key=extensions
        case "$d" in .*) ;; *) key=filenames ;; esac
        [ -f "grammars/$g.cyml" ] || { err "$d routes to $g, which has no grammars/$g.cyml"; continue; }
        line=$(decl "$g" "$key")
        [ "$(has "$line" "$d")" = 1 ] \
            || err "$d routes to $g but grammars/$g.cyml does not declare it in $key"
        ;;
    FNM)    # a=fn b=NAME c=LANG
        n_fn=$((n_fn + 1))
        [ -f "grammars/$c.cyml" ] || { err "$b routes to $c, which has no grammars/$c.cyml"; continue; }
        line=$(decl "$c" filenames)
        [ "$(has "$line" "$b")" = 1 ] \
            || err "$b routes to $c but grammars/$c.cyml does not declare it in filenames"
        ;;
    INT)    # a=fn b=NAME c=K d=wlen-guard e=LANG
        n_sb=$((n_sb + 1))
        len=${#b}
        [ "$c" = "$len" ] || err "shebang $b -> $e: memeq length $c, name is $len bytes"
        if [ "$len" -gt 2 ]; then
            [ "$d" = "$len" ] \
                || err "shebang $b -> $e: needs a (wlen >= $len) guard on the line (found: $d)"
        fi
        [ -f "grammars/$e.cyml" ] || { err "shebang $b routes to $e, which has no grammars/$e.cyml"; continue; }
        line=$(decl "$e" shebangs)
        [ "$(has "$line" "$b")" = 1 ] \
            || err "shebang $b routes to $e but grammars/$e.cyml does not declare it in shebangs"
        ;;
    ODD)    # a=fn b=line-number c..=text
        err "unrecognised route line $DETECT:$b (in $a): $c${d:+ $d}${e:+ $e}${g:+ $g}"
        ;;
    esac
done < "$TMP.rec"

# Guard against the shapes silently matching nothing after a
# reformat (2.6.2 counts: 76 suffix, 5 filename, 12 interpreter).
[ "$n_ext" -ge 76 ] || err "found only $n_ext path suffix routes (expected >= 76) — did the line shape change?"
[ "$n_fn" -ge 5 ]   || err "found only $n_fn filename routes (expected >= 5)"
[ "$n_sb" -ge 12 ]  || err "found only $n_sb interpreter routes (expected >= 12)"

if [ "$bad" -ne 0 ]; then
    echo "check-detect: FAIL ($bad problem(s))" >&2
    exit 1
fi
echo "check-detect: OK ($n_ext suffix, $n_fn filename, $n_sb interpreter routes, all declared)"
