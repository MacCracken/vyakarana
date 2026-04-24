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

The 1.x.x minor-version lineup — each release is a coherent,
user-visible batch. Ordered so scanner extensions land before the
languages that need them.

### 1.0.1 — Audit follow-ups (patch)

Triggered by findings in `docs/audit/2026-04-23-audit.md`. Small,
non-behavior-changing fixes.

- **FINDING-006** — `_sanitize_for_stderr` helper over
  `io_error` / `no_grammar_error` / `usage_error` in `src/main.cyr`
  to strip control bytes from echoed user args.
- Any emergent bugs observed post-1.0 that don't warrant a minor.

### 1.1.0 — Scanner extensions

Three scanner capabilities flagged during M3 as cosmetic gaps.
Each ships with its own ADR. Land before the language waves that
need them.

- **`char_literal = true` default** (ADR-0007 candidate) — 2–3
  char lookahead to tokenize `'x'` / `'\n'` as a single `string`
  instead of an op/body/op triple. Needed by C, Rust, C++, Java,
  Kotlin, Swift, Haskell, OCaml.
- **`unicode_ident = true` default** (ADR-0008 candidate) — treat
  bytes ≥ 0x80 as `ident_cont` to pass UTF-8 prose cleanly. Lets
  Markdown stand-in reclaim its `—` em-dashes and unblocks
  Unicode identifier handling for Python / Rust / Swift.
- **`block` rule type** (ADR-0009 candidate) — `/* ... */` pair
  rule spanning multiple lines. Needed by C, Rust, C++, Java, C#,
  Go, Zig, CSS, SQL, and many more.

### 1.2.0 — Vidya-backed languages (ready-to-ship tier)

Five vidya samples already sit in `content/lexing_and_parsing/`
waiting for grammars. Each is a ~30-min `.cyml` + snapshot + wire
session per the M3 recipe (HANDOFF §Where the code lives).

- `go` — C-like + goroutines, no surprises
- `zig` — C-like + comptime, similar shape to Rust
- `openqasm` — quantum circuit syntax; small grammar
- `asm_x86_64` — opcode + register + `%`/`$` sigil shape
- `asm_aarch64` — same shape as x86 with ARM opcodes

### 1.3.0 — JVM + C-family expansion

High-traffic languages not in the starter set (per Octoverse 2025 /
Stack Overflow 2025). All benefit from the 1.1.0 scanner extensions.

- `java`
- `kotlin`
- `cpp` (templates, `::`, `<>` generics, namespace syntax — may
  surface additional scanner needs)
- `csharp`

### 1.4.0 — Scripting + mobile

- `php`
- `ruby`
- `lua` (small grammar; good "canary" for the scanner)
- `swift`

### 1.5.0 — Functional tier

Distinct syntaxes; may surface new rule-type needs (e.g. `|>`,
pattern guards, algebraic-data-type shapes).

- `elixir`
- `ocaml`
- `haskell`

### 1.6.0 — Data / query / IDL

- `sql` (dialect-neutral baseline; PostgreSQL / SQLite add-ons
  as separate grammars if ever needed)
- `graphql`
- `protobuf`
- `capnp` (optional; track post-1.6)

### 1.7.0 — Markup + styling

- `html` (tag + attribute shape; sub-grammar for `<script>` /
  `<style>` contents might warrant an ADR)
- `xml`
- `css`
- `scss` / `less` (extensions of css grammar; may share a single
  `.cyml` with optional keywords)

### 1.8.0 — Dev ops + infrastructure formats

- `dockerfile`
- `makefile` (tab-sensitive; indentation-adjacent — check whether
  the scanner extension from 1.1.0 covers it)
- `ini` / `.conf`
- `nginx` (conditional — depends on user demand; track post-1.8)

### 1.9.0 — AGNOS-native formats

- `cyml` — proper grammar recognizing `---` delimiter + markdown
  body (vyakarana's own grammar files, yukti config, vidya content)
- `llvm-ir` (compiler-output inspection)

### Post-1.x backlog (parked, not batched yet)

- **Incremental retokenization** — only retokenize edited lines;
  enables cyim and other live editors
- **Regex rule type** — reopen ADR 0005 decision only if a
  compelling grammar hits the wall
- **Content-based language detection** — for files without
  extensions or shebangs (heuristic-driven)
- **Grammar composition** — Markdown fenced code blocks routing
  into the fenced language's grammar
- **Language server protocol bridge** — map external LSP semantic
  tokens onto the vyakarana palette
- **Theme export** — emit theme files in external formats (iTerm,
  VS Code) generated from vyakarana + owl palettes

### Major 2.x.x tiers (carried from pre-1.0 ROADMAP)

The pre-1.0 M4–M7 milestones become 2.x:

- **2.0.0** — Theme-palette contract with owl (M4). May be breaking
  if the palette surface tightens.
- **2.1.0** — Streaming tokenizer / iterator API (M5). Memory goes
  O(tokens-in-flight); unlocks `owl huge.log`.
- **2.2.0** — vidya reverse consumption (M6). vidya starts
  rendering its `content/lexing_and_parsing/` samples through
  vyakarana.
- **2.3.0** — Polish + RC (M7). Fuzz, stress, binary-size target,
  man page, release candidate.

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
