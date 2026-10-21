# vyakarana — Roadmap

A phased plan for building vyakarana from scaffold to polished release.
Each milestone is independently shippable and adds a coherent layer.
The goal is to have something a consumer can actually use at the end
of every phase.

---

## Guiding principles for the roadmap

- **Lock types first, implement runtime second.** M0 ships the
  palette + Token/Span layout, even though the tokenizer is a stub.
  Downstream consumers (owl M3b) can start importing and compiling
  against a stable type before a grammar exists.
- **One grammar at a time.** M1 ships one working grammar (shell).
  M2 re-expresses it as data. M3 adds the other nine. No batch-of-ten
  all-or-nothing milestone.
- **Every milestone is testable against a real corpus.** vidya's
  `content/lexing_and_parsing/*` is the corpus from day one. A
  grammar passes when it tokenizes its vidya sample cleanly.
- **Defer what you can.** Regex rules, content-based detection,
  incremental retokenization, language servers — all post-v1.

---

## Milestone 0 — Scaffold (this release, v0.1.0)

**Goal:** the repo exists, compiles, has locked types, passes a
trivial test.

- Project structure and build system
- `vyk --version`, `vyk --help`, `vyk --list-kinds`, `vyk --list-languages`
- `Token` struct layout frozen (pre-1.0 caveat — field changes must
  be CHANGELOG-flagged)
- Ten token kinds defined as constants
- Tokenize runtime stub (returns an empty list) — real tokenization
  lands in M1
- Grammar record struct stub — real loader lands in M2
- CI builds, tests pass, smoke script runs

**Done when:** a consumer (owl) can add a `[deps.vyakarana]` block
and start importing `Token` / `Kind` constants, even though calling
`tokenize_source` returns nothing yet.

---

## Milestone 1 — Shell, hand-coded

**Goal:** one working grammar end-to-end. Proves the runtime shape.

- Hand-coded shell tokenizer in `src/grammars/shell.cyr` — not yet
  driven by a grammar file, just a direct recognizer
- `vyk file.sh` prints NDJSON of `(kind, start, len)` tokens
- `vyk --language=shell <file>` overrides detection
- Coverage invariant: token byte concat reproduces source
- Test against `vidya/content/lexing_and_parsing/shell.sh` — zero
  `error` tokens, coverage passes
- owl M3b can now import `tokenize_source(src, "shell")` and get
  real tokens

**Done when:** you can syntax-highlight a shell script end-to-end
through owl.

---

## Milestone 2 — CYML grammar loader

**Goal:** grammars become data. Re-express the shell grammar as a
CYML file; the runtime loads it instead of calling hand-coded code.

- Grammar loader reads `grammars/<lang>.cyml`
- Rule types: `line`, `pair`, `words`
- Shell grammar moves from `src/grammars/shell.cyr` (hand-coded) to
  `grammars/shell.cyml` (data)
- Identical token output before/after the move (regression guard)
- `vyk --list-languages` now reflects loaded grammars

**Done when:** adding a new language to vyakarana is a new `.cyml`
file with zero Cyrius code.

---

## Milestone 3 — Starter set (eleven grammars)

**Goal:** the eleven bundled grammars ship.

- shell (carried from M2)
- python
- javascript
- typescript
- rust
- c
- cyrius
- toml
- json
- yaml
- markdown

- Each grammar tested against its `vidya/content/lexing_and_parsing/`
  sample
- Coverage + zero-error-token invariants hold
- Hand-audited ~30 tokens per grammar look right

**Done when:** `vyk --list-languages` prints all eleven and each
tokenizes its vidya sample (or an ADR-0006 stand-in) cleanly.

---

## Milestone 4 — Theme-palette contract with owl

**Goal:** owl's theme system and vyakarana's token kinds meet in a
stable contract.

- Document the kind → palette slot mapping in the design spec
- owl's theme files reference the ten kinds by name
- Add `vyk --theme <name>` to the demo CLI for diagnostic rendering
  (reuses owl's palette logic via a shared include or a small
  tokens-to-ANSI helper that vyakarana owns)

**Done when:** owl M3b is feature-complete and a grammar-author can
preview a grammar via `vyk --theme dark file.py` without running
owl.

---

## Milestone 5 — Streaming tokenizer

**Goal:** tokens yield line-by-line without buffering the full file.

- Tokenizer API returns an iterator, not a Vec
- Memory footprint O(tokens-in-flight), not O(input)
- Benchmark: 50 MB/s on a 1 MB Rust file on target hardware
- owl integration: `owl huge.log` renders the first screen before
  tokenizing the full file

**Done when:** `owl /path/to/100MB.log` is visually interactive in
under a second.

---

## Milestone 6 — vidya reverse consumption

**Goal:** vidya starts using vyakarana to render its code samples.

- vidya adds `[deps.vyakarana]` block
- A vidya reference page that shows code now routes it through
  vyakarana + a renderer
- Corpus files in `content/lexing_and_parsing/` are now
  double-purposed: reference samples for humans, test corpus for
  vyakarana

**Done when:** vidya's reference library visibly uses vyakarana for
at least three languages.

---

## Milestone 7 — Polish & release candidate

**Goal:** ready for broad use.

- Fuzz + stress tests on malformed input (unterminated strings,
  huge single-line files, BOMs, mixed encodings)
- Binary size under target (300KB for `vyk` with ten grammars
  embedded)
- Startup benchmarks verified
- Error messages reviewed for clarity
- Man page, README finalized, examples in help output
- AGNOS / Cyrius packaging
- v1.0.0 cut

**Done when:** you'd recommend it to someone without caveats.

---

## Post-1.0 release batches

**Versioning rule (revised in flight).** The original rule
reserved 2.x.x for the streaming-tokenizer break and parked
everything else in 1.x.x. That mapping shipped: 2.0.0 cut the
streaming API, and the 2.1.x through 2.3.x lines have absorbed
follow-on grammar batches, audit-driven correctness work, and
toolchain catch-up without further breaking changes. Toolchain
moves have never settled on one level: 2.2.0 took a minor
purely to flag that the `cyriusly use` line had moved, 2.2.2
and 2.2.3 shipped the two pin hops after it as patches, and
2.3.0 earned its minor because the bump needed source changes,
not because the pin moved. Future minors stay additive unless
a real consumer-driven contract change forces a 3.0.0.

### Released

`CHANGELOG.md` is the authoritative log — every cut from
1.0.0 through the current tag is dated, summarized, and
cross-linked there. The roadmap no longer mirrors it (it
drifted, then stayed drifted). Brief shape:

- **1.0.x** — Initial stable release + audit-driven follow-ups
  (ANSI sanitizer, distlib bundle, toolchain-pin refresh).
- **1.1.x – 1.9.x** — Language-batch waves expanding from the
  eleven starter grammars to the full set. Modernization
  fixes (Rust `$`-macros, TOML triple-strings, `unicode_ident`,
  `char_literal`), JVM / C-family / scripting / functional /
  data / markup / devops / AGNOS-native batches.
- **1.10.x – 1.13.x** — Pre-2.0 prep. Theme-palette contract,
  vidya reverse consumption, external integrations (LSP
  bridge, theme export, content-based detection, grammar
  composition + fenced-markdown routing), fuzz / stress
  harness, RC polish (size + startup benchmarks, man page,
  packaging), markdown fence-routing follow-up.
- **2.0.x** — Streaming tokenizer. Push API
  (`tokenize_stream_new` / `_feed` / `_drain` / `_finish`),
  rolling-buffer per-feed drainage, pull adapter, pending
  pair-rule fast path, closeout audit.
- **2.1.x** — Grammar batch wave + streaming opts.
  PowerShell, Crystal, Julia, Vue, Svelte, Nix, Terraform
  (38 → 45 grammars). Discardable pull-adapter staging.
  Random-split fuzz harness. Trailing-complete heuristic
  fix (FINDING-010). 2.1.5 closeout audit (0 findings).
- **2.2.x** — Audit-queue wrap-up + a three-step toolchain
  march. cyrius `5.10.0` → `5.10.5` (2.2.0) → `6.0.3`
  (2.2.2) → `6.1.24` (2.2.3). FINDING-011 compose-rule
  prefix buffering fix; defensive `staging == 0` guard;
  HTML / Vue / Markdown random-split fuzz cases re-enabled
  (2.2.1). Vendored `lib/` gitignored
  ([ADR 0018](../adr/0018-vendored-stdlib-gitignored.md))
  and the `--list-languages` dispatch fixed for 6.0's
  annotated `vec_get: i64` (2.2.2).
- **2.3.x** — Toolchain catch-up. cyrius `6.1.24` → `6.5.4`,
  four minor lines in one step. Minor rather than patch
  because the bump needed source changes: it cleared two
  **pre-existing** gate failures that reproduce identically
  at the outgoing pin — `[deps] stdlib` listed `cyml`, which
  6.1.24 folded into the `bayan` bundle, leaving no standalone
  `lib/cyml.cyr` to resolve, so `cyrius deps` exited 1 on any
  fresh checkout from 2.2.3 on (vestigial entry either way —
  the grammar loader scans `.cyml` itself in `src/grammar.cyr`);
  and eleven `var` names re-declared inside the test suite's
  single 3,100-line `fn main()` failed to compile, meaning
  2.2.3 shipped with a red test gate. Vendored `lib/` re-cut
  from the 6.5.4 snapshot — it was 6.0.x-vintage, because
  `cyrius deps` treats an existing `lib/<mod>.cyr` as
  satisfied and never refreshes it, so the pin had been
  silently ignored at build time since 2.2.2. 45 grammars,
  840/840 tests, no benchmark regression, `build/vyk` down
  390,784 → 371,472 bytes.
- **2.4.x** — Streaming correctness, then toolchain. 2.4.0 made
  chunked feeding produce whole-buffer tokens for 15 of 20
  corpora (was 7) and added `fuzz/chunk_invariance.fcyr`; the
  five compose grammars stay divergent by design. 2.4.1 / 2.4.3
  moved the pin `6.5.32` → `6.6.2` → `6.6.20` with no source
  change; 2.4.2 renamed `_stream_grow`, which collided with
  sankoch's in consumers vendoring both. From 2.4.3 the bundle
  carries a compile-verified `# Requires` block and a 4-leaf
  `.deps` sidecar, and `cyrius.lock` is tracked.
- **2.5.x** — Onto cyrius's 6.7 language line: `6.6.20` →
  `6.7.9` (2.5.0). A minor to mark the language-minor crossing,
  not because source changed — none did, and output is
  byte-identical to the 6.6.20 build. 2.5.1: pin → `6.7.15`,
  stdlib footprint trimmed (`hashmap` dropped, `assert` to
  `[test]`; `vyk` −33 KB), the `detect/content-python` drift
  bisected to 2.3.4's shebang fix and mostly recovered, `#! /bin/sh`
  detecting again, and the lint gate made to fail on warnings.
  2.5.2: the full closeout audit — 5 P1 / 10 P2 / 12 P3 fixed
  (terminal-escape injection through `--theme`, three streaming
  correctness bugs and unbounded streaming heap, quadratic compose
  scans, malformed-grammar crashes), every non-compose grammar
  chunk-invariant at every split offset, two fuzz harnesses
  strengthened until they fail on 2.5.1.
- **2.6.x** — The pinned train begins. 2.6.0: shell correctness — `#`
  opens a comment only at word start (`start_after`, ADR 0022),
  here-documents as one string token (`heredoc` rule type, ADR 0023),
  backslash escapes and `$0`–`$9` as single tokens; chunk-invariant
  through a drain hold and a terminator watch.
  2.6.1: CLI hardening — checked buffered stdout (write failures exit
  3), validated flag values, `--export-theme` order-independent, `-`
  stdin and `--`.

### Forward plan — pinned releases (2.6.x – 2.x.x)

**Re-planned 2026-10-20, at the 2.5.2 closeout audit.** The roadmap
used to hold "nothing scheduled; the next cut waits on a forcing
function". The audit turned that queue into concrete, scoped work, so
the remaining work and the backlog are now pinned to releases. The
rule that retired the old 1.3.x – 1.13.x pre-schedule still applies to
*content*: each release below is defined by defects and gaps already
found and reproduced, not by guesses at future demand. Sources are the
[2.5.2 audit](../audit/2026-10-20-2.5.x-closeout-audit.md) §Scheduled
and `state.md` §Next up.

**Versioning, as practiced.** A minor when token boundaries change for
some input (a consumer can see the difference) or a feature is added;
a patch otherwise. Every minor closes with the CLAUDE.md hardening
step as its `.y.last` closeout patch, as 2.5.2 did for 2.5.x.
Toolchain catch-ups stay user-directed patch releases at any point in
the train (pin → re-vendor → gates → byte-identical output A/B, the
2.4.3 – 2.5.1 protocol); they never carry other work.

#### 2.6.0 — Shell correctness *(minor: shell token boundaries change)* — **shipped 2026-10-20**

*Done as planned, with one scope note: the M1 oracle follows the `#`,
escape and `$N` changes (so the identity check holds) but not heredocs —
its identity corpus has none, the same standing as backticks.*

- **`#` starts a comment only at word start.** `${#arr[@]}`, `${x#p}`,
  `${x##*/}` and `a#b` comment out the rest of the line today — in the
  shipped corpus. Needs a line-rule boundary option (ADR 0022) applied
  in `grammars/shell.cyml`, with `src/grammars/shell.cyr` (the M1
  oracle) changed in lockstep so the smoke M1/M2 byte-identical diff
  keeps holding.
- **Heredoc bodies** (`<<EOF`, `<<-EOF`, `<<'EOF'`): an apostrophe in a
  body opens a string that runs to EOF. A new rule shape (ADR 0023).
- `\"` outside quotes (becomes a `\` operator, then a string to EOF);
  `$0`–`$9` as special variables.
- Exit: a vidya-synced corpus addition per shape; every shell file in
  the real-file sweep zero-error.

#### 2.6.1 — CLI hardening *(patch)* — **shipped 2026-10-20**

*Done as planned, plus `--` (end of options) and a buffered writer that
made NDJSON output 3.5x faster.*

- Write failures exit non-zero: `vyk a.sh > /dev/full`, a closed
  stdout and `--export-theme > /dev/full` all exit 0 today (stdlib
  `print` ignores short writes) — a checked writer, exit 3.
- Clear errors: empty `--language=` / `--theme=` / `--export-theme=`
  report "unknown option"; `--language=bogus` exits 4 "no grammar
  matched" instead of 2 "bad value".
- `--export-theme` independent of flag order (`--export-theme=vscode
  --theme=dark` exports `default`); refuse a stray FILE with it.
- `-` / stdin input.

#### 2.6.2 — Detection from grammar data *(patch, ADR)*

- Every grammar's `extensions` array is documentation only — detection
  is hard-coded in `src/detect.cyr`, and `.asm`, `.hh`, `.csx`,
  `.properties`, `.phtml`, `Dockerfile.*` are listed but never routed.
  Either drive detection from the arrays or prune them; decide in an
  ADR. Close with the 2.6.x closeout audit.

#### 2.7.0 — Number literals *(minor: token boundaries change)*

- **`[defaults] number_float`** — fraction and exponent as one number
  token (ADR). Today `0.1` is `0` `.` `1` everywhere (JSON's `.` was a
  `TK_ERROR` until 2.5.2) and `1e5` is `1` + ident `e5`. Opt in json,
  python, javascript, typescript, rust, go, c, cpp, java, kotlin,
  csharp, swift, zig, lua, julia, css / scss, protobuf, graphql,
  openqasm (`OPENQASM 2.0;` is three tokens). TOML floats and
  datetimes (scoped out by ADR 0008).
- Per-grammar digit separators (`1_000`) where the language has them.

#### 2.7.1 — Grammar polish *(patch)*

From the 2.5.2 header cross-check and the out-of-scope list:

- PHP 8 `#[attr]` (swallowed by the `#` comment rule); ruby / crystal
  `@@x` class variables; makefile `$<` `$^` `$%` `$+` `$|`; css `-`
  unreachable as an operator; harmless duplicates (haskell `/=`, llvm
  `uwtable`, swift words).
- Rust byte chars `b'\n'`; Python f / r / b string prefixes; Cyrius
  `#ifdef` / `#define` lines as preprocessor, not comments.
- Close with the 2.7.x closeout audit.

#### 2.8.0 — Streaming engine *(minor)*

- **Long non-pair tokens are re-scanned on every drain.** Only pair
  rules have the pending fast path; a 512 KB line comment in 64-byte
  chunks takes 4 s, a 512 KB identifier 10 s. Generalise the fast path
  to line rules, identifiers, whitespace and numbers — or replace the
  rescan-and-commit drain with a state machine that scans only new
  bytes (the long-standing "scanner state-machine optimization").
- **Compose-grammar chunk invariance** — markdown, html, vue, svelte,
  cyml. Needs prefix-hold restructured so it stops reading the commit
  list as state (three patch attempts in 2.4.0 regressed). Fixes the
  residual O(N^1.6) compose drains with it.
- Exit: `fuzz/chunk_invariance.fcyr` covers all 46 corpora; the
  every-offset split is clean on all 46.

#### 2.9.0 — Size and tooling *(minor)*

- Binary size: the default `vyk` is 444,032 B, the DCE build (what
  releases ship) 353,920 B, against 1.13.0's 300 KB soft cap. The
  cheapest lever: strip comments when embedding — the blobs carry each
  `.cyml` verbatim and most of their ~231 KB is comment text (2.5.2's
  header fixes alone added 8.4 KB). Then revisit the cap or the blob
  encoding (ADR 0014).
- Replace `scripts/embed-grammars.sh` — its escaping is gawk-only
  (`gsub` backslash doubling is a no-op under POSIX awk) — with
  cyrius's `[embed]` manifest section (6.6.19) or a POSIX rewrite.
- Real-corpus mutation fuzz over vidya snapshots (recommended since the
  2026-05-09 audit); fold the 2.5.2 audit's sweep scripts (real-file
  coverage sweep, poison A/B) into `scripts/` so the next audit reruns
  them instead of rebuilding them.
- Script the loaded-host latency protocol 2.5.2 used by hand (short
  runs, alternating versions, best-of-10 + paired ratios —
  `performance.md` §2.5.2) so every refresh uses it.

#### 2.x — Consumer-driven, no fixed slot

Taken only when a consumer asks; each becomes a pinned minor when it
does.

- **Incremental retokenization** (`retokenize_range`) for live editors
  (cyim). Additive → a 2.x minor; breaking → 3.0.0.
- **New grammars** — MDX, Lean 4, shell variants beyond
  bash / zsh / sh / dash, Zig macros, whatever a consumer needs.
- **Regex rule type** — reopens
  [ADR 0005](../adr/0005-m2-rule-type-scope.md) only if a grammar
  genuinely cannot be expressed with the current rule set. None of the
  46 has hit that wall.

#### 3.0.0

Only for a consumer-driven contract break (token kinds, `Token`
layout, the streaming API). None is planned.

**Consumers, not owned here.** As of 2.5.2 the consumers pin `owl` →
`2.4.2` (cyrius `6.6.2`), `cyim` → `2.4.0` (`6.7.9`), `vidya` → `2.4.0`
(`6.6.2`), and all three build and pass their tests against the 2.5.2
bundle at those pins. 2.5.2 changes what they render — fixed operator
splits, chunk-invariant streaming, JSON decimals, CYML `"""` strings —
with no API change; whether to take the tag is their call. vidya in
particular gains its seven field-note documents (they emitted error
tokens through 2.5.1).

---

## Decision log

| Date       | Question                              | Decision        | Rationale                                                |
|------------|---------------------------------------|-----------------|----------------------------------------------------------|
| 2026-04-23 | Grammar format: TextMate/tree-sitter/own? | CYML (own) | Keep the toolchain consistent; refuse incumbent baggage   |
| 2026-04-23 | Palette size?                          | 10 kinds        | Survey of ten starter languages shows no need for more   |
| 2026-04-23 | Include regex rules in M2?             | No              | Performance cliffs, debugging tax; add only if forced    |
| 2026-04-23 | Library-first or binary-first?         | Library-first   | Consumers (owl, cyim) drive shape; `vyk` is diagnostic   |
| 2026-04-23 | Corpus source?                         | `vidya/content/lexing_and_parsing/*` | Already exists, curated, and creates reciprocal relationship |
| 2026-10-20 | Keep "nothing scheduled" after 2.5.x? | No — pinned releases 2.6.0 – 2.9.0 | The 2.5.2 audit produced a reproduced, scoped queue; pinning it beats re-deriving it each session. Content stays evidence-driven. |

---

## Risk & mitigation

| Risk                                                 | Mitigation                                                                  |
|------------------------------------------------------|-----------------------------------------------------------------------------|
| Palette turns out too small for a real grammar       | Defer adding a kind; check whether theme can distinguish via token text     |
| CYML format can't express a real grammar efficiently | Hand-code the first grammar (M1) before committing to the format (M2)       |
| Streaming API awkward from Cyrius                    | Prototype streaming shape in M1 alongside shell; don't wait until M5        |
| vidya samples are thin for some languages            | M3 grammars each get a supplemental test file when vidya coverage is light  |
| Scope creep from consumers wanting parsing           | Point them at a dedicated parser library; vyakarana stops at tokens         |

---

*End of roadmap.*
