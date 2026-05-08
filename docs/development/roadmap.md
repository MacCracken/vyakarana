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

**Versioning rule.** 2.x.x is reserved for **breaking changes
only**. Anything that doesn't change a public contract — new
languages, new scanner defaults, new ADRs, performance work,
documentation contracts, fuzz harnesses, packaging — lands in
the 1.x.x line. Today that means the **only thing scheduled for
2.0.0 is the streaming-tokenizer return-type change** (M5);
everything else from the original "M4–M7 → 2.x" mapping moves
into 1.x.x cuts that lead up to 2.0.

### Released

Authoritative list of what's actually shipped. Forecasts that
predicted otherwise have been pruned.

- **1.0.0** (2026-04-23) — First stable release. Eleven starter
  grammars (shell, toml, json, cyrius, rust, yaml, markdown, c,
  typescript, javascript, python), data-driven scanner, public
  `tokenize_source(src, lang)` → `tokenbuf` API.
- **1.0.1** (2026-04-23) — Audit follow-up. FINDING-006
  ANSI-escape sanitizer over CLI stderr (`_sanitize_for_stderr`
  in `src/main.cyr`).
- **1.0.2** (2026-04-23) — distlib bundle. `cyrius distlib` →
  `dist/vyakarana.cyr` for downstream consumers.
- **1.0.3** (2026-05-08) — Toolchain pin bump to cyrius `5.9.36`
  after the upstream `include`-graph regression resolved.
  No source changes.
- **1.1.0** (2026-05-08) — Modernization fixes from the vidya
  corpus survey. Three ADRs landed: Rust `$`-macro metavariables
  (ADR 0007), TOML triple-quoted strings (ADR 0008), and the
  `unicode_ident` default + a `match = "pair"` block-comment
  rule for C (ADR 0009 — replaces what was originally pencilled
  in as a separate "block rule type"). Plus a single-source-of-
  truth refactor for `vyk --version` (`src/version_str.cyr` +
  `scripts/version-bump.sh`).
- **1.2.0** (2026-05-08) — Go and Zig grammars.
- **1.2.1** (2026-05-08) — `char_literal` default flag (ADR
  0010). Closes the `'\n'` byte-char-literal-with-escape gap
  for C / Rust / Go / Zig in one cut.
- **1.2.2** (2026-05-08) — `asm_x86_64` grammar (Intel syntax).

### Forward plan — finishing 1.2.x

- **1.2.3 — `asm_aarch64`.** Same grammar shape as `asm_x86_64`
  with ARM opcodes / registers (`x0`–`x30`, `w0`–`w30`,
  `sp`/`pc`/`lr`); ARM-specific directives (`.arch`, `.cpu`,
  `.fpu`) join the keyword list. Opcodes/registers stay as
  `TK_IDENT` per ADR 0004.
- **1.2.4 — closeout / P(-1) hardening.** Per CLAUDE.md
  §Closeout pass: full clean rebuild, dead-code audit, stale-
  comment sweep, doc sync, and the next round of the
  documentation roadmap-vs-reality reconciliation.

### Forward plan — language batches (1.3.x – 1.9.x)

Each minor cut is a coherent ecosystem batch. All are additive —
no breaking changes.

- **1.3.0 — JVM + C-family.** `java`, `kotlin`, `cpp` (templates,
  `::`, generics — may surface scanner needs), `csharp`. All
  benefit from the 1.1.0 scanner work and 1.2.1 char_literal.
- **1.4.0 — Scripting + mobile.** `php`, `ruby`,
  `lua` (small grammar; good "canary" for the scanner), `swift`.
- **1.5.0 — Functional tier.** `elixir`, `ocaml`, `haskell`.
  May surface new rule-type needs (`|>`, pattern guards,
  algebraic-data-type shapes); each gets its own ADR if so.
- **1.6.0 — Data / query / IDL.** `sql` (dialect-neutral
  baseline), `graphql`, `protobuf`. `capnp` tracked post-1.6
  if demand emerges.
- **1.7.0 — Markup + styling.** `html` (tag + attribute shape;
  inner-`<script>` / `<style>` is grammar-composition work →
  see 1.11.0), `xml`, `css`, `scss` / `less`.
- **1.8.0 — Dev ops + infrastructure formats.** `dockerfile`,
  `makefile` (tab-sensitive — verify the scanner covers it),
  `ini` / `.conf`. `nginx` tracked post-1.8 if demand emerges.
- **1.9.0 — AGNOS-native.** `cyml` (proper `---`-delimited
  grammar + markdown body — own dogfood), `llvm-ir`.

### Forward plan — pre-2.0 prep (1.10.x – 1.13.x)

The non-breaking work that used to be slated for "2.x" and is
now staged as final 1.x cuts before the 2.0.0 streaming-tokenizer
break. Logical groupings, not a rigid schedule — slots may shift
if a real consumer forces an earlier landing.

- **1.10.0 — Theme-palette contract + vidya reverse consumption.**
  Pairs M4 (non-breaking parts) and M6: both are external-
  coordination work and benefit from the full language set being
  in place.
  - Document the kind → palette slot mapping in
    `vyakarana-design-spec.md` and the architecture overview.
  - owl's theme files reference the ten kinds by name (not by
    ad-hoc identifier).
  - Add `vyk --theme <name>` to the diagnostic CLI for
    grammar-author preview without running owl.
  - vidya adds `[deps.vyakarana]`; its
    `content/lexing_and_parsing/` samples render through
    vyakarana + a renderer. Reciprocal-relationship payoff that
    started with [ADR 0001](../adr/0001-corpus-sync-policy.md).
- **1.11.0 — External integrations.** "Make vyakarana useful
  from outside the AGNOS stack." All additive.
  - **LSP bridge** — map external `textDocument/semanticTokens`
    output onto the vyakarana palette. New module, new ADR.
  - **Theme export** — emit theme files in external formats
    (iTerm, VS Code, Helix `theme.toml`) generated from
    vyakarana + owl palettes. CLI subcommand or separate tool.
  - **Content-based language detection.** Fallback in
    `detect_language` for files without extensions or shebangs
    (heuristic-driven; e.g. shebang sniff, BOM detect).
  - **Grammar composition for fenced markdown code blocks.**
    Routes triple-backtick fenced code through the inner
    language's grammar and re-tokenizes. New ADR; the markdown
    grammar gets a hook for it.
- **1.12.0 — Fuzz + stress harness.** M7 prep. Pre-release
  hardening for 2.0.
  - Malformed-input battery: unterminated strings, huge
    single-line files, BOMs, mixed encodings, adversarial
    `.cyml` files (the grammar loader is a parser, not just
    static config).
  - Stress: 100 MB single-buffer tokenize, time + memory
    bounds.
  - File findings under `docs/audit/YYYY-MM-DD-fuzz-audit.md`.
- **1.13.0 — RC polish.** M7 finish. The doorstep of 2.0.
  - Binary-size target verified — ≤ 300 KB for `vyk` with all
    bundled grammars embedded.
  - Startup-time benchmarks captured + tracked
    (`docs/development/performance.md` if it doesn't exist
    yet).
  - Error-message review — every `usage_error` /
    `no_grammar_error` / `io_error` reads cleanly to a non-
    Cyrius user.
  - Man page, README finalized, examples in `--help`.
  - AGNOS / Cyrius packaging (zugot recipe etc.) pinned to a
    1.x tag, verified on amd64 + arm64.

### 2.0.0 — Streaming tokenizer (the only breaking change)

Carry-over of the original M5 work, and the **only release
allowed in the 2.x.x line under the current versioning rule**.

- `tokenize_source` returns an **iterator**, not a `tokenbuf`.
  Memory goes O(tokens-in-flight) instead of O(input).
- `owl /path/to/100MB.log` is visually interactive in under a
  second.
- Migration guide ships alongside. Consumers pinned to 1.x's
  return type get a clear path: either bridge through a small
  buffering helper for backward behaviour, or adopt the new
  iterator shape directly.
- ADR documenting the trade-off (working-set bound vs random-
  access loss) and the bridge-helper shape.

**Done when:** consumers (owl, cyim, vidya) have moved to the
iterator API or chosen the bridging helper, and the migration
guide has at least one consumer-side proof point.

### Post-2.0 backlog (parked)

Items that don't yet have a forcing function:

- **Incremental retokenization** — only retokenize edited
  lines; enables cyim and other live editors. May be additive
  (a separate `retokenize_range` API alongside the streaming
  one), in which case it lands in some 2.x.x or even 1.x line
  if it predates 2.0; may be breaking, in which case 3.0.0.
  Reopen when a real editor pushes for it.
- **Regex rule type** — reopens [ADR 0005](../adr/0005-m2-rule-type-scope.md)
  only if a grammar genuinely cannot be expressed via the
  current rule set. None of the 14 bundled grammars have hit
  the wall.

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
