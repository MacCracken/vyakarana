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
| `build/vyk` (CLI binary)    |      333,672 |     325.9 | Includes 38 inlined grammars (~170KB of text) |
| `dist/vyakarana.cyr`        |      269,647 |     263.3 | Single-file bundle for `cyrius deps`          |

The 1.13.0 cut formalises a **soft 300 KB target** for
`build/vyk` per the 1.13.x roadmap entry. Today's binary is
~26 KB over that target. The dominant contributor is the
embedded grammar blobs; see ADR 0014 for why inlining is the
right trade-off (downstream `cyrius deps` consumers no longer
need to vendor `grammars/`). The 300 KB number predates ADR
0014; revisiting it before 2.0 is open.

Cyrius DCE is on by default — the build prints 288 `dead:`
warnings, all already eliminated. Setting `CYRIUS_DCE=1`
explicitly produces a byte-identical binary.

## Tokenize / detect / load latencies (1.13.0 baseline)

Per-call wall-clock averages from
`cyrius bench tests/bcyr/vyakarana.bcyr` (8 benchmarks, each
batched 100×, totalling 100k–10M iterations). All inputs are
small (32–64 byte) snippets so the per-iteration cost is
dominated by API overhead, not buffer scan.

| Benchmark                  | Avg     | Min     | Max     | Iterations |
|----------------------------|--------:|--------:|--------:|-----------:|
| tokenize/shell-small       |   18 µs |   17 µs |   19 µs |  1,000,000 |
| tokenize/rust-small        |   26 µs |   26 µs |   27 µs |  1,000,000 |
| tokenize/json-small        |    3 µs |    3 µs |    3 µs |  1,000,000 |
| tokenize/html-compose      |    8 µs |    8 µs |    9 µs |  1,000,000 |
| detect/path-shell          |   30 ns |   29 ns |   33 ns | 10,000,000 |
| detect/content-python      |  184 ns |  180 ns |  198 ns | 10,000,000 |
| detect/combined-asm-arm    |    5 µs |    5 µs |    5 µs |  1,000,000 |
| blob/grammar-load-shell    |   32 µs |   31 µs |   41 µs |    100,000 |

Notes on shape:

- **Path-only detect is essentially free** (~30 ns) — pure cstr
  suffix matching, fits in cache.
- **Content sniff** is ~6× slower than path (184 ns) because of
  the BOM peek + shebang interp scan, but still well under a
  microsecond.
- **Combined detect** lands at 5 µs because `_detect_asm_flavor`
  does a 4 KB byte scan with 21 `_detect_index_of` calls. ARM
  vs x86 voting is the bulk of the cost.
- **Grammar load via blob** is 32 µs because `_gp_parse` walks
  the entire CYML body, allocates char-class tables, and
  populates the grammar struct. This is a one-time cost per
  grammar — `bootstrap_grammars` runs once at startup.

## History

### 1.13.0 — initial baseline (2026-05-08)

First captured. See table above. Establishes the reference
point for future comparison.
