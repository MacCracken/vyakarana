# common.sh — helpers shared by the scripts in scripts/audit/ (sourced,
# not run). Each script records the caller's directory in AUDIT_CWD,
# then cd's to the repo root before sourcing this.

# audit_list OUT ARGS... — write to OUT the files named by ARGS, one
# path per line, byte-sorted so a run is repeatable: a FILE as is, a
# DIR's regular files (skipping .git/ and node_modules/), `-` for paths
# read from stdin. Relative paths are the caller's, not the repo
# root's. Returns 2 when an argument does not exist or nothing is left
# to check — a sweep over nothing is not a clean sweep (2.9.1 audit:
# a mistyped path used to report "files=0 … fails=0" and exit 0). A
# path in a stdin list that has since vanished is named and skipped.
audit_list() {
    _out=$1
    shift
    _miss=0
    : > "$_out.raw"
    for _a in "$@"; do
        if [ "$_a" = "-" ]; then
            while IFS= read -r _p; do
                [ -n "$_p" ] || continue
                case "$_p" in /*) ;; *) _p="$AUDIT_CWD/$_p" ;; esac
                if [ -f "$_p" ]; then
                    printf '%s\n' "$_p" >> "$_out.raw"
                else
                    echo "audit: skipped, not a file: $_p" >&2
                fi
            done
            continue
        fi
        case "$_a" in /*) _p=$_a ;; *) _p="$AUDIT_CWD/$_a" ;; esac
        if [ -d "$_p" ]; then
            find "$_p" \( -name .git -o -name node_modules \) -prune -o -type f -print >> "$_out.raw"
        elif [ -f "$_p" ]; then
            printf '%s\n' "$_p" >> "$_out.raw"
        else
            echo "audit: $_a: no such file or directory" >&2
            _miss=1
        fi
    done
    LC_ALL=C sort -u "$_out.raw" > "$_out"
    rm -f "$_out.raw"
    if [ "$_miss" -ne 0 ]; then return 2; fi
    if [ ! -s "$_out" ]; then
        echo "audit: no files to check" >&2
        return 2
    fi
    return 0
}

# audit_run SECS CMD... — CMD under a SECS-second limit where
# `timeout` exists (exit 124 when it fires); without it, unlimited.
audit_run() {
    _secs=$1
    shift
    if command -v timeout > /dev/null 2>&1; then
        timeout "$_secs" "$@"
    else
        "$@"
    fi
}

# Build build/vyk-audit from scripts/audit/harness.cyr. Always rebuilt:
# a harness left over from another tree reports that tree's bugs (the
# 2.8.0 work lost an afternoon to one).
audit_build_harness() {
    mkdir -p build
    if [ ! -f src/grammar_blobs.cyr ]; then
        sh scripts/embed-grammars.sh > /dev/null || return 1
    fi
    if ! cyrius build scripts/audit/harness.cyr build/vyk-audit > build/vyk-audit.log 2>&1; then
        cat build/vyk-audit.log >&2
        echo "audit: building the harness failed" >&2
        return 1
    fi
}

# Build build/vyk the way the gates do.
audit_build_vyk() {
    mkdir -p build
    sh scripts/embed-grammars.sh > /dev/null || return 1
    if ! cyrius build src/main.cyr build/vyk > build/vyk.log 2>&1; then
        cat build/vyk.log >&2
        echo "audit: building vyk failed" >&2
        return 1
    fi
}

# Temp directory cleanup, and an interrupt that stops the script: a
# trap on INT that only cleans up lets the script carry on after the
# handler (2.9.1 audit). `exit` in the INT / TERM handler runs the EXIT
# trap, which removes the directory.
audit_tmpdir() {
    T=$(mktemp -d)
    trap 'rm -rf "$T"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}
