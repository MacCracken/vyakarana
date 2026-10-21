# common.sh — helpers shared by the scripts in scripts/audit/ (sourced,
# not run). Each script cd's to the repo root before sourcing this.

# Files named by the arguments, one path per line: a FILE as is, a
# DIR's regular files (skipping .git/ and node_modules/), and `-` for
# paths read from stdin. Byte-sorted, so a run is repeatable.
audit_files() {
    for a in "$@"; do
        if [ "$a" = "-" ]; then
            cat
        elif [ -d "$a" ]; then
            find "$a" \( -name .git -o -name node_modules \) -prune -o -type f -print
        elif [ -f "$a" ]; then
            printf '%s\n' "$a"
        else
            echo "audit: $a: no such file or directory" >&2
        fi
    done | LC_ALL=C sort -u
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
