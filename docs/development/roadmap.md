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
streaming API, and the 2.1.x / 2.2.x lines have absorbed
follow-on grammar batches and audit-driven correctness work
without further breaking changes. Future minors stay additive
unless a real consumer-driven contract change forces a 3.0.0.

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
- **2.2.x** — Toolchain pin refresh + audit-queue wrap-up.
  cyrius `5.10.0` → `5.10.5`. FINDING-011 compose-rule
  prefix buffering fix; defensive `staging == 0` guard;
  HTML / Vue / Markdown random-split fuzz cases re-enabled.

### Forward plan

**Empty / TBD.** The 2.1.5 audit queue is fully drained as
of 2.2.1; no minor or patch cut is currently scheduled.

The next cut waits on a forcing function — a real consumer
asking for a grammar, a profiler complaining about a hot
path, an upstream toolchain refresh, or an audit finding.
No speculative batches; the previous cycle of pre-scheduling
1.3.x – 1.13.x ahead of consumer demand drifted out of
sync with reality and was cut.

`docs/development/state.md` has a §Next up section listing
candidate directions if work resumes (state-machine drain
optimization, real-corpus fuzz harness, more grammars,
binary-size cap revisit). None are committed; the live state
file is the right place for that conversation, not this
roadmap.

### Backlog (parked, no forcing function yet)

- **Incremental retokenization** — only retokenize edited
  lines; enables cyim and other live editors. Likely additive
  (a `retokenize_range` API alongside the streaming one), in
  which case it slots into a 2.x cut. May be breaking, in
  which case 3.0.0. Reopen when a real editor pushes for it.
- **Regex rule type** — reopens
  [ADR 0005](../adr/0005-m2-rule-type-scope.md) only if a
  grammar genuinely cannot be expressed via the current rule
  set. None of the 45 bundled grammars have hit that wall.

---

## Decision log

| Date       | Question                              | Decision        | Rationale                                                |
|------------|---------------------------------------|-----------------|----------------------------------------------------------|
| 2026-04-23 | Grammar format: TextMate/tree-sitter/own? | CYML (own) | Keep the toolchain consistent; refuse incumbent baggage   |
| 2026-04-23 | Palette size?                          | 10 kinds        | Survey of ten starter languages shows no need for more   |
| 2026-04-23 | Include regex rules in M2?             | No              | Performance cliffs, debugging tax; add only if forced    |
| 2026-04-23 | Library-first or binary-first?         | Library-first   | Consumers (owl, cyim) drive shape; `vyk` is diagnostic   |
| 2026-04-23 | Corpus source?                         | `vidya/content/lexing_and_parsing/*` | Already exists, curated, and creates reciprocal relationship |

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
