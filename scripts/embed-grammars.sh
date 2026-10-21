#!/bin/sh
# embed-grammars.sh — generate src/grammar_blobs.cyr from grammars/*.cyml
#
# vyakarana ships dist/vyakarana.cyr as a self-contained bundle. The
# bundle's bootstrap_grammars() loads every bundled grammar; without
# this step it would call file_read_all("grammars/<name>.cyml") at
# runtime, but cyrius deps doesn't vendor grammars/ — only the bundle.
# Inlining the .cyml files as Cyrius string literals makes the bundle
# self-contained (ADR 0014).
#
# Output: src/grammar_blobs.cyr — gitignored. Always regenerated; never
# hand-edited. Run before cyrius build / cyrius test / cyrius distlib.
#
# How the runtime uses it: src/grammar.cyr's grammar_load(path) calls
# _grammar_blob_data(path) first; if non-zero, parses from memory; else
# falls back to file_read_all for paths that are not bundled. A bundled
# path ALWAYS resolves to its blob, so after editing grammars/foo.cyml
# re-run this script before building — the file is not re-read.
#
# Each blob is the grammar COMPACTED (ADR 0029): comments, blank lines
# and every space / tab / CR outside a string are dropped, so the blob
# carries only what the loader reads. Two thirds of the .cyml text is
# comment, and it went into every binary until 2.9.0. The compactor
# follows the loader's lexical rules (src/grammar.cyr: a string is
# "..." with `\` escaping the next byte; `#` outside a string runs to
# the end of the line; a value is a string, a string array or a bool)
# for well-formed grammar text, and refuses the malformed shapes where
# dropping a blank would change what the loader reads: a blank inside
# a word (`tr ue`, `number_ 0x`) or right after a header's `[`. (2.9.0
# claimed "exactly"; the 2.9.1 audit found those cases.) For anything
# else, tests/vyakarana.tcyr is the proof, per grammar: each blob must
# parse to the same grammar record as its source file.
#
# POSIX sh + POSIX awk + tr. Through 2.8.0 the escaping used gsub(),
# whose backslash doubling is a no-op under POSIX awk (gawk --posix,
# mawk, busybox): `\\` reached the blob as `\`. Every byte is now
# examined and escaped one at a time, which no awk reads differently.

set -eu

cd "$(dirname "$0")/.."

# Bytes, not characters, in awk and tr; a byte-order glob.
LC_ALL=C
export LC_ALL

OUT="src/grammar_blobs.cyr"
TMP="$OUT.tmp.$$"
# `exit` in the INT / TERM handlers: a handler that only cleaned up let
# the script carry on, and an interrupt could still end in "wrote …"
# with a short blob file (2.9.1 audit).
trap 'rm -f "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

COUNT=0
SRC_BYTES=0
for f in grammars/*.cyml; do
    [ -f "$f" ] || continue
    COUNT=$((COUNT + 1))
    SRC_BYTES=$((SRC_BYTES + $(wc -c < "$f")))
done
if [ "$COUNT" -eq 0 ]; then
    echo "embed-grammars.sh: no grammars/*.cyml found" >&2
    exit 1
fi

# Refuse any file with a NUL or other control byte besides TAB, LF and
# CR (or DEL). .cyml files are text — anything else means something is
# wrong upstream. `tr -d` with octal ranges is POSIX; through 2.8.0
# this used `grep -P`, a GNU extension, so elsewhere the check quietly
# passed.
for f in grammars/*.cyml; do
    all=$(wc -c < "$f")
    txt=$(tr -d '\000-\010\013\014\016-\037\177' < "$f" | wc -c)
    if [ "$all" -ne "$txt" ]; then
        echo "embed-grammars.sh: $f contains unexpected control bytes; refusing to embed" >&2
        exit 1
    fi
done

# Compact one grammar and escape it as the body of one Cyrius string
# literal (`\\`, `\"`, `\t`, `\n`; CR never survives compaction, and
# is escaped as `\r` should one sit inside a string). Exits 2 on a
# string that runs past the end of its line: the loader would continue
# it onto the next one, no grammar does that, and the compactor would
# have to keep that line's blanks — refusing is simpler and loud.
compact_one() {
    awk '
    function esc(c) {
        if (c == "\\") return "\\\\"
        if (c == "\"") return "\\\""
        if (c == "\t") return "\\t"
        if (c == "\r") return "\\r"
        return c
    }
    function word(c) { return c ~ /^[A-Za-z0-9_-]$/ }
    function refuse(why) {
        printf "embed-grammars.sh: %s:%d: %s\n", FILENAME, FNR, why > "/dev/stderr"
        exit 2
    }
    {
        out = ""
        in_str = 0
        gap = 0
        n = length($0)
        i = 1
        while (i <= n) {
            c = substr($0, i, 1)
            if (in_str) {
                if (c == "\\" && i < n) {
                    out = out esc(c) esc(substr($0, i + 1, 1))
                    i += 2
                    continue
                }
                if (c == "\\") break
                if (c == "\"") in_str = 0
                out = out esc(c)
                i++
                continue
            }
            if (c == "#") break
            if (c == " " || c == "\t" || c == "\r") { gap = 1; i++; continue }
            # The loader ends a word at a blank and reads a header from
            # its first byte: dropping the blank in `tr ue`, `number_ 0x`
            # or `[ grammar]` would change what it reads (2.9.1 audit).
            if (gap && word(c) && word(substr(out, length(out), 1))) refuse("blank inside a word")
            if (gap && (out == "[" || out == "[[")) refuse("blank after the [ of a header")
            gap = 0
            if (c == "\"") in_str = 1
            out = out esc(c)
            i++
        }
        if (in_str) {
            printf "embed-grammars.sh: %s:%d: string runs past the end of its line\n", FILENAME, FNR > "/dev/stderr"
            exit 2
        }
        if (out != "") printf "%s\\n", out
    }
    ' "$1"
}

# A Cyrius identifier for a grammar name: any non-alnum becomes `_`.
sym_of() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_' | tr -s '_'
}

# Two names that map to one symbol (`zz-a`, `zz_a`) would make one blob
# shadow the other; the compiler only warns (2.9.1 audit).
dup=$(for f in grammars/*.cyml; do sym_of "$(basename "$f" .cyml)"; echo; done | sort | uniq -d)
if [ -n "$dup" ]; then
    echo "embed-grammars.sh: grammar names collide on blob symbol(s): $dup" >&2
    exit 1
fi

{
    cat <<EOF
# vyakarana — embedded grammar blobs (auto-generated)
#
# AUTO-GENERATED by scripts/embed-grammars.sh — do not edit.
# Regenerate after editing any grammars/*.cyml file.
# Gitignored; produced fresh on each build / distlib step.
#
# Source: $COUNT grammars in grammars/*.cyml, compacted (ADR 0029) —
# comments and blanks outside strings removed; grammars/ is the
# readable copy.
# Used by src/grammar.cyr's grammar_load() — checks blob lookup first,
# falls back to file_read_all() if no blob matches the path. Lets
# dist/vyakarana.cyr be a single self-contained bundle (cyrius deps
# vendors only the bundle file, not the grammars/ dir).
#
# Uses streq() from lib/string.cyr — auto-included via cyrius.cyml's
# [deps] stdlib (\`string\`).

EOF

    # One fn per grammar. Path key matches what bootstrap_grammars
    # passes to grammar_load(): "grammars/<name>.cyml".
    for f in grammars/*.cyml; do
        name=$(basename "$f" .cyml)
        printf 'fn _grammar_blob_%s() {\n' "$(sym_of "$name")"
        printf '    return "'
        compact_one "$f"
        printf '";\n'
        printf '}\n\n'
    done

    # Lookup: linear scan, one streq per bundled grammar, init-only.
    cat <<'EOF'
# Returns pointer to the blob's content (cstr) for the given path, or
# 0 if no blob matches. Path is the same string bootstrap_grammars
# passes to grammar_load() — "grammars/<name>.cyml".
fn _grammar_blob_data(path) {
EOF
    for f in grammars/*.cyml; do
        name=$(basename "$f" .cyml)
        printf '    if (streq(path, "grammars/%s.cyml")) { return _grammar_blob_%s(); }\n' "$name" "$(sym_of "$name")"
    done
    cat <<'EOF'
    return 0;
}

# Number of embedded grammars. Mostly a self-test hook — bootstrap
# expects this to match grammars/*.cyml at build time.
fn _grammar_blob_count() {
EOF
    printf '    return %d;\n' "$COUNT"
    cat <<'EOF'
}

# The path of blob `i` (0 <= i < _grammar_blob_count()), or 0, so a test
# can walk the blobs themselves rather than the grammars that loaded.
fn _grammar_blob_path(i) {
EOF
    k=0
    for f in grammars/*.cyml; do
        printf '    if (i == %d) { return "%s"; }\n' "$k" "$f"
        k=$((k + 1))
    done
    cat <<'EOF'
    return 0;
}
EOF
} > "$TMP"

mv "$TMP" "$OUT"
trap - EXIT INT TERM

echo "embed-grammars: wrote $OUT ($COUNT grammars, $SRC_BYTES source bytes -> $(wc -c < "$OUT" | tr -d ' ') bytes)"
