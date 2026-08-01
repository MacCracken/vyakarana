# vyakarana — performance baseline

Baseline measurements captured at each minor-release boundary so
future agents can spot regressions. Numbers are platform-
specific; treat the *trend* across releases as load-bearing, not
the absolute values.

> **How to refresh:** `cyrius bench tests/bcyr/vyakarana.bcyr`
> after a clean rebuild. Replace the table for the current
> release; keep prior releases under §History.

Hardware on which the baseline below was captured: Linux x86_64
(7.1.5-arch1-1). Local dev machine, not a controlled benchmark
host — variance ~±10% between runs.

---

## Binary size

| Artifact                    | Size (bytes) | Size (KB) | Notes                                         |
|-----------------------------|-------------:|----------:|-----------------------------------------------|
| `build/vyk` (CLI binary)    |      371,472 |     362.8 | Includes 45 inlined grammars (~199 KB of text) |
| `dist/vyakarana.cyr`        |      348,582 |     340.4 | Single-file bundle for `cyrius deps` (4,030 lines) |

(Sizes captured 2026-07-31 at `2.3.0`, on the 6.5.4 toolchain.
The previous capture is 2.2.1 under §History — the 1.13.0 entry
never recorded artifact sizes — and this table tracks current
state. `cyrius distlib` reports the bundle as 4002 lines and
`wc -l` says 4,030 — trust `wc -l`.)

`build/vyk` **shrank 19,312 bytes** across this cut — 390,784 at
the 2.2.1 capture, 371,472 now — but the credit does not go to
codegen. Dropping the vestigial `cyml` entry from `[deps]
stdlib` stopped a whole stdlib module from being prepended into
the compilation unit, and since DCE is off by default those
bytes were really being emitted: restoring `cyml` and rebuilding
on 6.5.4 gives 383,784, so that one removal is 12,312 of the
19,312. (That counterfactual is measured against today's tree —
read it as what the module costs now, not as the exact byte
count 2.2.3 carried.) The remaining ~7 KB is spread across
everything else between the two captures — 2.2.1 was the last
release whose binary was measured, and it pinned `5.10.5`, so
the window is three pin bumps wide, not just `6.1.24` → `6.5.4`.
No grammar was dropped either way (45, same as 2.2.1).

The 1.13.0 cut formalised a **soft 300 KB target** for
`build/vyk`. Today's binary is ~63 KB over that target, down
from ~82 KB at 2.2.1 — this cut closed roughly a quarter of the
overage without touching the dominant contributor, the embedded
grammar blobs (45 grammars × ADR 0014 inlining). 2.1.x audit
(2026-05-09) flagged the cap revisit as a 2.x roadmap item; not
a security or correctness concern. See ADR 0014 for why inlining
is the right trade-off (downstream `cyrius deps` consumers no
longer need to vendor `grammars/`).

Cyrius DCE is opt-in, not on by default — a plain `cyrius build`
reports 342 unreachable fns (58,238 bytes) and emits them anyway.
`CYRIUS_DCE=1` NOPs those bytes rather than dropping them, so the
binary is 371,472 either way; the two builds differ in content,
not in size. (Re-checked 2026-07-31 on 6.5.4: the shipped
`build/vyk` is byte-identical to the default build, not to the
`CYRIUS_DCE=1` one.)

## Tokenize / detect / load latencies (2.3.0 baseline, 2026-07-31)

Per-call wall-clock averages from
`cyrius bench tests/bcyr/vyakarana.bcyr` (8 benchmarks, each
batched 100×, totalling 100k–10M iterations). All inputs are
small (32–64 byte) snippets so the per-iteration cost is
dominated by API overhead, not buffer scan.

| Benchmark                  |       Avg |       Min |       Max | Iterations |
|----------------------------|----------:|----------:|----------:|-----------:|
| tokenize/shell-small       | 20.343 µs | 20.049 µs | 20.831 µs |  1,000,000 |
| tokenize/rust-small        | 28.956 µs | 28.334 µs | 30.580 µs |  1,000,000 |
| tokenize/json-small        |  6.057 µs |  5.787 µs |  6.374 µs |  1,000,000 |
| tokenize/html-compose      | 11.548 µs | 11.183 µs | 12.053 µs |  1,000,000 |
| detect/path-shell          |     33 ns |     32 ns |     34 ns | 10,000,000 |
| detect/content-python      |    194 ns |    188 ns |    200 ns | 10,000,000 |
| detect/combined-asm-arm    |  5.401 µs |  5.275 µs |  5.574 µs |  1,000,000 |
| blob/grammar-load-shell    | 33.211 µs | 32.340 µs | 35.073 µs |    100,000 |

**No row regressed.** Every one is flat or faster than the 2.2.1
baseline once that table's whole-microsecond rounding is allowed
for, and the clear win is rust-small at −6.6 %. Three rows read
fractionally higher against the rounded figures (json-small
+1 %, html-compose +5 %, combined-asm-arm +8 %) — all inside
this host's ±10 % run-to-run variance and nowhere near the 20 %
regression-watch threshold in CLAUDE.md.

Notes on shape:

- **Path-only detect is essentially free** (~33 ns) — pure cstr
  suffix matching, fits in cache.
- **Content sniff** is ~6× slower than path (194 ns) because of
  the BOM peek + shebang interp scan, but still well under a
  microsecond.
- **Combined detect** lands at 5.4 µs because `_detect_asm_flavor`
  does a 4 KB byte scan with 21 `_detect_index_of` calls. ARM
  vs x86 voting is the bulk of the cost.
- **Grammar load via blob** is 33 µs because `_gp_parse` walks
  the entire CYML body, allocates char-class tables, and
  populates the grammar struct. This is a one-time cost per
  grammar — `bootstrap_grammars` runs once at startup.
- **Tokenize rows are still above the 1.13.0 baseline** — that
  gap is the 2.0.x streaming primitive's per-call cost (stream
  alloc, rolling-buffer feed/drain, abs-offset tracking), not
  anything this cut introduced. The 2.2.1 → 2.3.0 span handed a
  little of it back: shell-small 21 → 20.3 µs, rust-small
  31 → 29.0 µs, content-python 206 → 194 ns. A state-machine
  drain optimization is still the obvious lever — the
  small-input rows show the constant factor most starkly — and
  remains a candidate direction in `state.md`'s §Next up.

## History

### 2.2.1 — refresh after streaming-wave (2026-05-08)

Re-captured after the 2.0.x → 2.1.x → 2.2.1 wave, on Linux
x86_64 (7.0.3-arch1-2), toolchain pin `5.10.5`. Tokenize rows up
vs the 1.13.0 baseline (streaming primitive overhead vs the
removed direct `tokenize_source` entry) — json-small doubled,
3 → 6 µs, and html-compose went 8 → 11 µs; detect / load rows
essentially unchanged. Artifacts at this capture: `build/vyk`
390,784 bytes, `dist/vyakarana.cyr` 348,588 bytes / 4,007 lines.

| Benchmark                  | Avg     | Min     | Max     | Iterations |
|----------------------------|--------:|--------:|--------:|-----------:|
| tokenize/shell-small       |   21 µs |   21 µs |   23 µs |  1,000,000 |
| tokenize/rust-small        |   31 µs |   30 µs |   32 µs |  1,000,000 |
| tokenize/json-small        |    6 µs |    6 µs |    7 µs |  1,000,000 |
| tokenize/html-compose      |   11 µs |   11 µs |   12 µs |  1,000,000 |
| detect/path-shell          |   35 ns |   33 ns |   42 ns | 10,000,000 |
| detect/content-python      |  206 ns |  196 ns |  214 ns | 10,000,000 |
| detect/combined-asm-arm    |    5 µs |    5 µs |    5 µs |  1,000,000 |
| blob/grammar-load-shell    |   34 µs |   32 µs |   36 µs |    100,000 |

### 1.13.0 — initial baseline (2026-05-08)

First captured. Reference point that today's table is compared
against.

| Benchmark                  | Avg (1.13.0) |
|----------------------------|-------------:|
| tokenize/shell-small       |        18 µs |
| tokenize/rust-small        |        26 µs |
| tokenize/json-small        |         3 µs |
| tokenize/html-compose      |         8 µs |
| detect/path-shell          |        30 ns |
| detect/content-python      |       184 ns |
| detect/combined-asm-arm    |         5 µs |
| blob/grammar-load-shell    |        32 µs |
