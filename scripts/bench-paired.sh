#!/bin/sh
# bench-paired.sh — the paired latency protocol (docs/development/performance.md).
#
# Usage: sh scripts/bench-paired.sh [-r ROUNDS] [-d DIV] OLD [NEW]
#   OLD, NEW   a git ref (a tag such as 2.8.0, a commit) or a directory
#              holding a vyakarana tree. NEW defaults to this working
#              tree as it is, uncommitted changes included.
#   -r ROUNDS  rounds (default 10)
#   -d DIV     divide every bench's iteration count by DIV (default 10)
#
# Both trees are copied to a scratch directory and prepared as the gates
# do (embed, deps). Both then run the SAME bench — NEW's
# tests/bcyr/vyakarana.bcyr with each bench_run_batch iteration count
# divided by DIV — alternately, OLD then NEW, ROUNDS times. For each
# benchmark it prints the median of the per-round NEW/OLD ratios, their
# interquartile range, and each side's best average.
#
# Why paired: a pair run back to back sees the same host load, so the
# ratio holds where absolute numbers do not — 2.8.0's two runs at load
# 7–12 agreed within noise while their absolutes ran 6–27 % high. Host
# load is printed before and after. Refresh the absolute table in
# performance.md only from a quiet host.
set -eu

cd "$(dirname "$0")/.."
ROOT=$(pwd)

ROUNDS=10
DIV=10
while [ $# -gt 0 ]; do
    case "$1" in
        -r) ROUNDS=$2; shift 2 ;;
        -d) DIV=$2; shift 2 ;;
        --) shift; break ;;
        -?*) echo "bench-paired: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: sh scripts/bench-paired.sh [-r ROUNDS] [-d DIV] OLD [NEW]" >&2
    exit 2
fi
for v in "$ROUNDS" "$DIV"; do
    case "$v" in
        ''|*[!0-9]*|0) echo "bench-paired: -r and -d take a positive integer, not '$v'" >&2; exit 2 ;;
    esac
done
OLD=$1
NEW=${2:-$ROOT}

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# tree SRC DST — a copy of SRC (a directory, or a git ref of this repo)
# at DST, without build/ or .git/.
tree() {
    mkdir -p "$2"
    if [ -d "$1" ]; then
        cp -R "$1/." "$2"
        rm -rf "$2/build" "$2/.git"
    elif git -C "$ROOT" rev-parse --verify --quiet "$1^{commit}" > /dev/null; then
        git -C "$ROOT" archive --format=tar "$1" | (cd "$2" && tar -xf -)
    else
        echo "bench-paired: $1 is neither a directory nor a git ref" >&2
        exit 2
    fi
    if ! (cd "$2" && sh scripts/embed-grammars.sh > /dev/null && cyrius deps > /dev/null 2>&1); then
        echo "bench-paired: preparing $1 failed" >&2
        exit 1
    fi
}

tree "$OLD" "$T/old"
tree "$NEW" "$T/new"

# The short bench, from NEW, into both trees.
sed 's/\(bench_run_batch(b, &[A-Za-z_0-9]*, [0-9]*\),/\1 \/ '"$DIV"',/' \
    "$T/new/tests/bcyr/vyakarana.bcyr" > "$T/paired.bcyr"
if ! grep -q "/ $DIV," "$T/paired.bcyr"; then
    echo "bench-paired: no bench_run_batch(b, &fn, N, ...) line to scale" >&2
    exit 1
fi
# A divisor past the smallest iteration count would leave a bench with
# none (2.9.1 audit).
least=$(sed -n 's/.*bench_run_batch(b, &[A-Za-z_0-9]*, \([0-9]*\),.*/\1/p' \
    "$T/new/tests/bcyr/vyakarana.bcyr" | sort -n | head -n 1)
if [ -n "$least" ] && [ "$DIV" -gt "$least" ]; then
    echo "bench-paired: -d $DIV leaves a bench with no iterations (the smallest count is $least)" >&2
    exit 2
fi
cp "$T/paired.bcyr" "$T/old/tests/bcyr/paired.bcyr"
cp "$T/paired.bcyr" "$T/new/tests/bcyr/paired.bcyr"

load() {
    if [ -r /proc/loadavg ]; then cut -d' ' -f1-3 /proc/loadavg; else uptime | sed 's/.*load average[s]*: //'; fi
}

echo "bench-paired: OLD=$OLD NEW=$NEW rounds=$ROUNDS iterations/$DIV"
echo "load before: $(load)"
i=1
while [ "$i" -le "$ROUNDS" ]; do
    for side in old new; do
        if ! (cd "$T/$side" && cyrius bench tests/bcyr/paired.bcyr) > "$T/$side-$i.log" 2>&1; then
            cat "$T/$side-$i.log" >&2
            echo "bench-paired: the $side bench failed in round $i" >&2
            exit 1
        fi
    done
    i=$((i + 1))
done
echo "load after:  $(load)"

# Lines like `  tokenize/shell-small: 12.683us avg (min=12.258us ...`.
for side in old new; do
    i=1
    while [ "$i" -le "$ROUNDS" ]; do
        LC_ALL=C awk -v r="$i" -v side="$side" '
            $2 ~ /^[0-9.]+(ns|us|ms|s)$/ && $3 == "avg" && $1 ~ /:$/ {
                name = substr($1, 1, length($1) - 1)
                v = $2; u = v; sub(/^[0-9.]+/, "", u); sub(/[a-z]+$/, "", v)
                f = 1
                if (u == "ns") f = 0.001
                if (u == "ms") f = 1000
                if (u == "s") f = 1000000
                print side, r, name, v * f
            }' "$T/$side-$i.log"
        i=$((i + 1))
    done
done > "$T/samples"

LC_ALL=C awk -v rounds="$ROUNDS" '
    function sort(a, n,    i, j, t) {
        for (i = 2; i <= n; i++) {
            t = a[i]
            for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]
            a[j + 1] = t
        }
    }
    { v[$1, $2, $3] = $4; names[$3] = 1 }
    END {
        printf "%-26s %15s %19s %13s %13s %7s\n", "bench", "median new/old", "IQR", "best old", "best new", "rounds"
        for (nm in names) {
            k = 0; bo = -1; bn = -1
            for (r = 1; r <= rounds; r++) {
                if (!((("old", r, nm) in v) && (("new", r, nm) in v))) continue
                o = v["old", r, nm]; n = v["new", r, nm]
                if (o <= 0) continue
                k++; q[k] = n / o
                if (bo < 0 || o < bo) bo = o
                if (bn < 0 || n < bn) bn = n
            }
            if (k == 0) continue
            sort(q, k)
            if (k % 2) med = q[(k + 1) / 2]; else med = (q[k / 2] + q[k / 2 + 1]) / 2
            # the quartile picks paired.py used through 2.8.0, so IQRs compare
            q1 = q[int(k / 4) + 1]; q3 = q[int(3 * k / 4) + 1]
            printf "%-26s %+14.1f%% [%+6.1f%%,%+6.1f%%] %11.3fus %11.3fus %7d\n", nm, (med - 1) * 100, (q1 - 1) * 100, (q3 - 1) * 100, bo, bn, k
        }
    }' "$T/samples" | { IFS= read -r head; echo "$head"; LC_ALL=C sort; }
