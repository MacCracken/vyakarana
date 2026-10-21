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
| `build/vyk` (CLI binary)    |      444,032 |     433.6 | Includes 46 inlined grammars (~231 KB of text) |
| `build/vyk`, `CYRIUS_DCE=1` |      353,920 |     345.6 | Same tree, dead fns compacted out — **what releases ship** |
| `dist/vyakarana.cyr`        |      429,133 |     419.1 | Single-file bundle for `cyrius deps` (5,097 lines) |

**Re-captured 2026-10-20 at `2.5.2`, 6.7.15 toolchain.** 423,480 →
444,032 (+20,552); DCE 337,464 → 353,920. The closeout audit's code —
the terminal-safe writer, grammar validation, the compose / fence /
LF watermarks, the per-depth inner tokenbuf pool, the LSP and
streaming fixes — plus **+8,384 bytes of grammar COMMENT text**: the
embedded blobs carry each `.cyml` verbatim, so the 2.5.2 header
corrections ship in the binary. Stripping comments at embed time would
save far more than that (most of the 231 KB is comments) — a 2.9.0
roadmap item.

**`2.5.1` capture (same day).**
452,544 (2.5.0) → 456,640 (+4,096) from the 6.7.15 snapshot alone,
then → **423,480 (−33,160)** from the stdlib-footprint trim:
dropping the never-called `hashmap` (and the `hashseed` / `chrono`
it pulled in) is −32,984, moving `assert` to `[test] stdlib` −176.
The `_detect_shebang` rewrite left the default build's size
unchanged (section alignment) and moved the DCE build 333,368 →
337,464.

**`2.5.0` capture (same day, 6.7.9 toolchain, host kernel
7.2.10-arch1-1)** — `build/vyk` 452,544, `CYRIUS_DCE=1` 333,760,
`dist/vyakarana.cyr` 401,171 / 4,715 lines. `build/vyk` moved
396,888 → 452,544 (+55,656) since the `2.3.3` capture:

- **+9,040 across 2.3.4 – 2.4.2** (396,888 → 405,928 at pin
  6.6.2): the 2.3.4 hardening fixes, 2.3.5's `openqasm` grammar,
  2.4.0's streaming changes and 2.4.1's 6.5.32 → 6.6.2 snapshot.
  Not attributed further — no capture was taken in between.
- **+46,600 from the 6.6.20 stdlib snapshot (2.4.3)**, measured on
  the identical tree at both pins. +42,598 of it is code the
  compiler reports unreachable (375 → 514 fns): the larger
  snapshot pulls more into the unit, and a default build emits
  dead fns.
- **+16 from 6.6.20 → 6.7.9 (2.5.0)**, measured the same way (514
  → 515 unreachable fns).

**`CYRIUS_DCE=1` now shrinks the binary.** The paragraph below
recording that DCE "NOPs those bytes rather than dropping them"
held at 6.5.4; by 6.6.20 DCE compacts — 452,528 → 333,744 at
6.6.20, 452,544 → 333,760 at 6.7.9. **Release artifacts are the
DCE build**: `.github/workflows/release.yml` has set
`CYRIUS_DCE: '1'` since 1.0.0, so the binary users download is the
DCE row; a local `cyrius build` (and CI's `build/vyk`) is the
default build. (Through 2.5.0 this paragraph said the shipped
binary was the default build — wrong for release artifacts.)
Against the soft 300 KB target at 2.5.1: the default build is
~123 KB over, the DCE build ~37 KB. `cyrius distlib` still
under-reports the bundle (4,715 lines vs `wc -l` 4,749).

**`2.3.3` capture (2026-08-20, 6.5.32 toolchain)** — `build/vyk`
396,888, `dist/vyakarana.cyr` 368,147 / 4,163 lines.
`build/vyk` moved 371,472 → 396,888 (+25,416) since the `2.3.0`
row below. Attribution, measured rather than assumed:

- **+21,000 from 2.3.1 + 2.3.2 grammar content** — the embedded
  blob set grew 206,394 → 217,790 bytes across the 37 edited
  grammars, plus the `compose_region` rule type. Those two patch
  releases landed after the `2.3.0` capture and were never
  measured, because the refresh cadence is minor boundaries.
- **+4,416 from the 6.5.32 stdlib snapshot** — building the
  identical tree at pin `6.5.4` gives 392,472 (343 unreachable
  fns) vs 396,888 at `6.5.32` (367 fns).
- **+0 from codegen.** Compiling the same tree with `6.5.4`'s and
  `6.5.32`'s `cycc` produces **byte-identical** output. The four
  minor lines between the pins changed the stdlib, not the emitted
  code for this project.

(Prior captures: `2.3.0` on 2026-07-31 at the 6.5.4 toolchain
— `build/vyk` 371,472, `dist/vyakarana.cyr` 348,582 / 4,030
lines — and 2.2.1 under §History; the 1.13.0 entry never
recorded artifact sizes. `cyrius distlib` under-reports the
bundle — it says 4,135 lines where `wc -l` says 4,163. Trust
`wc -l`; the same ~28-line gap was present at `2.3.0`.)

`build/vyk` **shrank 19,312 bytes across the 2.2.1 → 2.3.0
window** — 390,784 to 371,472 — but the credit does not go to
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
`build/vyk`. At 2.3.3 the binary was ~63 KB over that target
(~153 KB at 2.5.0 — see above), down
from ~82 KB at 2.2.1 — that cut closed roughly a quarter of the
overage without touching the dominant contributor, the embedded
grammar blobs (46 grammars × ADR 0014 inlining). 2.1.x audit
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
`CYRIUS_DCE=1` one. *2.5.1 note:* "shipped" there means the local
/ CI build — release artifacts have been `CYRIUS_DCE=1` builds
since 1.0.0; see the 2.5.1 capture above. And DCE no longer
leaves the size unchanged.)

## Bench note (2.5.0, 2026-10-20) — toolchain bumps are perf-neutral

Both 2.4.3 (`6.6.2` → `6.6.20`) and 2.5.0 (`6.6.20` → `6.7.9`)
were A/B'd on the *same* tree, three rounds alternating between
the pins (old, new, old, new, …) so each pair shares host
conditions. Averages over the three rounds, in µs:

| Benchmark                  | 6.6.2 ¹ | 6.6.20 ¹ | Δ      | 6.6.20 ² | 6.7.9 ² | Δ      |
|----------------------------|--------:|---------:|-------:|---------:|--------:|-------:|
| tokenize/shell-small       |  19.150 |   19.538 | +2.0 % |   22.265 |  20.956 | −5.9 % |
| tokenize/rust-small        |  27.646 |   27.845 | +0.7 % |   30.871 |  30.113 | −2.5 % |
| tokenize/json-small        |   4.491 |    4.249 | −5.4 % |    4.649 |   4.624 | −0.5 % |
| tokenize/html-compose      |  10.162 |    9.593 | −5.6 % |   10.352 |  10.459 | +1.0 % |
| detect/path-shell          |   0.034 |    0.031 | −6.9 % |    0.034 |   0.034 | −1.0 % |
| detect/content-python      |   0.235 |    0.251 | +6.5 % |    0.278 |   0.283 | +2.0 % |
| detect/combined-asm-arm    |   5.720 |    5.449 | −4.7 % |    6.059 |   6.110 | +0.8 % |
| blob/grammar-load-shell    |  37.260 |   36.360 | −2.4 % |   37.779 |  38.553 | +2.0 % |

¹ Captured with the host mostly idle (one round shared the CPU
with a concurrent build). ² Captured while cyrius 6.7.16 gate
suites were running on the same host (load average 3.5–7.4) —
the *deltas* hold because the rounds alternate, but the
**absolute values read 0–15 % high**, so they are not a baseline.

**No row moved by more than ±7 % on average at either step**
(min-to-min: within ±6.3 % at 6.6.20, up to +8.4 % at 6.7.9 —
the three detect rows and grammar-load read +6–8 % on their best
window under the loaded host, while their averages move ≤ 2 %);
the tokenize rows — the consumer hot path — are flat.
The one consistent mover across the 6.6.2 → 6.6.20 step is
`detect/content-python` (+6 % on average, same direction in all
three rounds); it did not move again at 6.7.9.

**`detect/content-python` had drifted ~+28 % against the `2.3.0`
table below** (194 ns → ~250 ns quiet-host), over CLAUDE.md's 20 %
watch line. **Bisected and largely recovered in 2.5.1.** A
same-tree matrix — 2.3.3's `src/detect.cyr` vs 2.5.0's, each built
on 6.6.2 and on 6.7.15, with `detect/path-shell` as an unchanged
control — put all of it on 2.3.4's `_detect_shebang` correctness
fix (+31 % at 6.6.2, +30 % at 6.7.15; the toolchain moved it ≤ 2 %).
The 2.5.0 note above guessed 2.3.4 – 2.4.2; it was 2.3.4. After the
2.5.1 single-pass rewrite (same answers, 400k-case differential),
interleaved at 6.7.15, 9 rounds, avg — host loaded (≈ 3.4), so read
the ratios:

| `detect.cyr` from          | content-python | path-shell (control) |
|----------------------------|---------------:|---------------------:|
| 2.3.3 (pre-fix, buggy)     |       196.8 ns |              32.0 ns |
| 2.5.0 (2.3.4 fix)          |       253.2 ns |              33.0 ns |
| **2.5.1**                  |   **218.7 ns** |              32.8 ns |

−13.6 % against 2.5.0; ~+13 % against the 2.3.0 table, back under
the watch line. The remaining gap is mostly the `env` branch the
correct code must take and the pre-fix code skipped for this
input. A further sentinel-loop variant was measured within noise
and not kept.

**Latency table not re-captured at 2.5.0 (nor at 2.5.1, same
host load).** The minor-boundary
refresh needs an idle host, which this cut did not get; the
`2.3.0` table below remains the absolute baseline until someone
re-runs `cyrius bench tests/bcyr/vyakarana.bcyr` on a quiet
machine and replaces it.

## Bench note (2.3.3, 2026-08-20) — toolchain bump is perf-neutral

The `6.5.4` → `6.5.32` bump was A/B'd on the *same* tree by
running `cyrius bench` under each toolchain back to back. All
eight rows agree within this host's run-to-run variance, so the
table below is **not** superseded by the pin move:

| Benchmark                  | 6.5.4     | 6.5.32    | Δ        |
|----------------------------|----------:|----------:|---------:|
| tokenize/shell-small       | 18.641 µs | 18.457 µs |  −1.0 %  |
| tokenize/rust-small        | 27.110 µs | 27.151 µs |  +0.2 %  |
| tokenize/json-small        |  4.095 µs |  4.023 µs |  −1.8 %  |
| tokenize/html-compose      |  9.129 µs |  9.003 µs |  −1.4 %  |
| detect/path-shell          |     33 ns |     32 ns |  −3.0 %  |
| detect/content-python      |    196 ns |    196 ns |   0.0 %  |
| detect/combined-asm-arm    |  5.267 µs |  5.277 µs |  +0.2 %  |
| blob/grammar-load-shell    | 34.849 µs | 34.742 µs |  −0.3 %  |

Both runs print `[timer floor ~1.34us per clock read, measured;
subtracted from every sample]`. **Do not compare these absolute
figures against the `2.3.0` table below without checking that
line** — a change in whether the floor is subtracted shifts every
microsecond-scale row by ~1.3 µs and can masquerade as a real
win. The `2.3.0` table was captured on 6.5.4, which does subtract
it. Table not refreshed: the documented cadence is minor-release
boundaries, and this is a patch.

## Tokenize / detect / load latencies (2.5.2 baseline, 2026-10-20)

**Captured on a loaded host, by a protocol that holds there.** An idle
machine is not available (cyrius release work runs alongside), and two
conventional captures this cycle were unusable: the same-code control
row (`detect/path-shell`) moved +14–37 % because load changed between
the A and B halves of a ~70 s run. So: build `tests/bcyr/vyakarana.bcyr`
with every iteration count divided by 10 (one run ≈ 9 s), run 2.5.1 and
2.5.2 alternately for 10 rounds (host load 2.7–5.2), and report each
benchmark's **best** run below. Best-of-10 short runs reproduce the
quiet-host figures seen earlier in the cycle (shell-small 19.5 µs both
ways); the per-round 2.5.2 / 2.5.1 ratios are in the 2.5.2 bench note.

| Benchmark                  |       Avg |       Min |       Max | Iterations |
|----------------------------|----------:|----------:|----------:|-----------:|
| tokenize/shell-small       | 19.477 µs | 19.051 µs | 20.265 µs | 100,000 × 10 runs |
| tokenize/rust-small        | 27.679 µs | 27.413 µs | 28.577 µs | 100,000 × 10 runs |
| tokenize/json-small        |  4.445 µs |  4.332 µs |  4.717 µs | 100,000 × 10 runs |
| tokenize/html-compose      |  9.316 µs |  9.149 µs |  9.705 µs | 100,000 × 10 runs |
| detect/path-shell          |     35 ns |     32 ns |     38 ns | 1,000,000 × 10 runs |
| detect/content-python      |    198 ns |    193 ns |    204 ns | 1,000,000 × 10 runs |
| detect/combined-asm-arm    |  5.479 µs |  5.367 µs |  5.683 µs | 100,000 × 10 runs |
| blob/grammar-load-shell    | 28.918 µs | 28.322 µs | 30.093 µs | 10,000 × 10 runs |

Against the `2.3.0` table below: every tokenize row is faster
(shell 20.3 → 19.5, rust 29.0 → 27.7, json 6.1 → 4.4, html 11.5 →
9.3 µs), grammar load 33.2 → 28.9 µs, and `detect/content-python`
is back to 198 ns from ~250 ns at 2.5.0 (2.5.1's shebang rewrite).

## Bench note (2.5.2, 2026-10-20) — the audit's fixes, A/B'd

Paired protocol above; median of the ten per-round 2.5.2 / 2.5.1
ratios, with the interquartile range:

| Benchmark                  | Median 2.5.2 / 2.5.1 | IQR            | Why                                          |
|----------------------------|---------------------:|----------------|----------------------------------------------|
| blob/grammar-load-shell    |              −14.5 % | −15.8 … −13.5 % | blobs parsed in place — no 32 KiB copy        |
| detect/content-python      |               −2.7 % | −4.8 … −2.0 %   |                                              |
| tokenize/html-compose      |               +0.4 % | −0.7 … +0.9 %   |                                              |
| tokenize/rust-small        |               +1.3 % | +0.7 … +2.7 %   | per-call scanner bookkeeping (generation, depth) |
| detect/combined-asm-arm    |               +1.4 % | +1.1 … +2.3 %   |                                              |
| tokenize/shell-small       |               +2.6 % | +2.0 … +3.0 %   | same                                         |
| tokenize/json-small        |               +6.2 % | +5.5 … +7.2 %   | `.` joined JSON's operators (the decimal fix): every punctuation byte now tries one more operator first |
| detect/path-shell          |               +9.4 % | +6.1 … +11.8 %  | one more suffix compare — `.zsh` (32 → 35 ns) |

Nothing near CLAUDE.md's 20 % watch line. Not visible here, and the
bigger wins: streaming heap no longer grows with input (8 MB fed: 195 MB
→ 105 KB), and compose openers without a closer are linear (1 MiB of
`<style>`: > 300 s → 1.7 s) — both in the audit report.

## Tokenize / detect / load latencies (2.3.0 baseline, 2026-07-31 — superseded by the 2.5.2 table above)

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
