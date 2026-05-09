# vyakarana — performance baseline

Baseline measurements captured at each minor-release boundary so
future agents can spot regressions. Numbers are platform-
specific; treat the *trend* across releases as load-bearing, not
the absolute values.

> **How to refresh:** `cyrius bench tests/bcyr/vyakarana.bcyr`
> after a clean rebuild. Replace the table for the current
> release; keep prior releases under §History.

Hardware on which the baseline below was captured: Linux x86_64
(7.0.3-arch1-2). Local dev machine, not a controlled benchmark
host — variance ~±10% between runs.

---

## Binary size

| Artifact                    | Size (bytes) | Size (KB) | Notes                                         |
|-----------------------------|-------------:|----------:|-----------------------------------------------|
| `build/vyk` (CLI binary)    |      390,784 |     381.6 | Includes 45 inlined grammars (~204 KB of text) |
| `dist/vyakarana.cyr`        |      348,588 |     340.4 | Single-file bundle for `cyrius deps` (4007 lines) |

(Sizes captured 2026-05-08 at `2.2.1`. The 1.13.0 baseline
below was the original capture; the table here tracks current
state.)

The 1.13.0 cut formalised a **soft 300 KB target** for
`build/vyk`. Today's binary is ~82 KB over that target — the
dominant contributor is the embedded grammar blobs (45
grammars × ADR 0014 inlining). 2.1.x audit (2026-05-09) flagged
the cap revisit as a 2.x roadmap item; not a security or
correctness concern. See ADR 0014 for why inlining is the
right trade-off (downstream `cyrius deps` consumers no longer
need to vendor `grammars/`).

Cyrius DCE is on by default — the build prints 288 `dead:`
warnings, all already eliminated. Setting `CYRIUS_DCE=1`
explicitly produces a byte-identical binary.

## Tokenize / detect / load latencies (2.2.1 baseline)

Per-call wall-clock averages from
`cyrius bench tests/bcyr/vyakarana.bcyr` (8 benchmarks, each
batched 100×, totalling 100k–10M iterations). All inputs are
small (32–64 byte) snippets so the per-iteration cost is
dominated by API overhead, not buffer scan.

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

Notes on shape:

- **Path-only detect is essentially free** (~35 ns) — pure cstr
  suffix matching, fits in cache.
- **Content sniff** is ~6× slower than path (206 ns) because of
  the BOM peek + shebang interp scan, but still well under a
  microsecond.
- **Combined detect** lands at 5 µs because `_detect_asm_flavor`
  does a 4 KB byte scan with 21 `_detect_index_of` calls. ARM
  vs x86 voting is the bulk of the cost.
- **Grammar load via blob** is 34 µs because `_gp_parse` walks
  the entire CYML body, allocates char-class tables, and
  populates the grammar struct. This is a one-time cost per
  grammar — `bootstrap_grammars` runs once at startup.
- **Tokenize-row drift since 1.13.0** (~17–23 % across rows) is
  the 2.0.x streaming primitive's per-call cost: stream alloc,
  rolling-buffer feed/drain, abs-offset tracking. Worth a
  state-machine drain optimization eventually (the small-input
  rows show the constant-factor overhead most starkly), but
  none of the rows breach the 20 % regression-watch threshold
  in CLAUDE.md by more than a hair, and absolute numbers stay
  in the right order of magnitude. Filed as a candidate
  direction in `state.md`'s §Next up.

## History

### 2.2.1 — refresh after streaming-wave (2026-05-08)

See current table above. Re-captured after the 2.0.x → 2.1.x →
2.2.1 wave. Tokenize rows up ~17–23 % vs 1.13.0 baseline
(streaming primitive overhead vs the removed direct
`tokenize_source` entry); detect / load rows essentially
unchanged. None breach the 20 % regression-watch threshold by
more than a hair.

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
