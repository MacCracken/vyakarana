# vyakarana — current state

> **Last refresh:** 2026-05-08 | **Refresh cadence:** every release
> (1.x cuts), plus any session that shifts the gates' colour or
> the active task.
>
> **Read this file before doing anything.** 1.0.0–2.0.4 are
> shipped. 1.x closed at 1.13.3 with 0 audit findings.
> **2.0.x is closed** — streaming API surface (2.0.0),
> rolling buffer (2.0.1), pull adapter (2.0.2), pending-pair
> fast path (2.0.3), closeout audit (2.0.4 — 2 LOW findings
> fixed in-pass). As of 2026-05-08 the toolchain pin is
> `cyrius = "5.10.0"`. 38 grammars bundled (unchanged),
> 778/778 tests passing, 3/3 fuzz harnesses passing. Next:
> 2.1.x grammar batches starting with PowerShell / Crystal /
> Julia. See §Next up.
>
> **Where to find what.** Architecture (system map, frozen
> contracts, durable invariants): [`../architecture/`](../architecture/).
> Decision rationale: [`../adr/`](../adr/). Design context:
> [`../../vyakarana-design-spec.md`](../../vyakarana-design-spec.md).
> Milestones: [`./roadmap.md`](./roadmap.md). Process and rules:
> [`../../CLAUDE.md`](../../CLAUDE.md).
>
> *(This file used to live at the repo root as `HANDOFF.md`.
> Renamed 2026-05-08 to match the AGNOS first-party docs
> standard, which puts live state in `docs/development/state.md`.
> "What is frozen", "Where the code lives", and "Invariants that
> carry forward" moved to `../architecture/overview.md` the same
> day.)*

---

## Current status (2026-05-08)

- **Version:** `2.0.4` in `VERSION`, `src/version_str.cyr`, and
  `dist/vyakarana.cyr`. Full 1.x + 2.0.0–2.0.4 tag history in
  the CHANGELOG.
- **What 2.0.4 added (closeout audit):**
  - **`docs/audit/2026-05-09-2.0.x-closeout-audit.md`** —
    full surface review of every 2.0.x change. Per-function
    bounds analysis on `_stream_grow`,
    `_stream_scan_close`, `_stream_find_pair_rule`,
    `_stream_is_trailing_complete`, drain, pull adapter,
    and pending-pair fast path. Buffer-cap semantics
    documented. **0 CRITICAL / 0 HIGH / 0 MEDIUM / 2 LOW
    (both fixed in-pass).**
  - **FINDING-008 fix.** `_stream_grow` zero-cap
    infinite-loop guard.
  - **FINDING-009 fix.** `_stream_scan_close` zero-elen
    vacuous match guard.
- **What 2.0.3 added (streaming optimization):**
  - **Pending pair-rule fast path.** When drain detects a
    trailing partial pair-rule open (string / block
    comment / preprocessor directive crossing chunk
    boundaries), the stream caches `(rule_idx, scan_resume)`
    and subsequent drains skip the full scanner — looking
    only for the close marker, advancing `scan_resume`
    past already-checked body bytes. Pathological case
    (1 MB string in 1 KB chunks) drops O(N×K) → O(N).
  - Stream record: 72 → 88 bytes (`pending_idx` + `scan_resume`).
  - 9 new probes: 100×10-byte chunks inside an open block
    comment; close marker straddling two feeds; pending
    state clears after close.
- **What 2.0.2 added (pull adapter):**
  - **`tokenize_stream_next(s)`** — iterator-style cursor;
    advances and returns 1, or 0 when exhausted. Refills
    via `_drain` automatically.
  - **`tokenize_stream_kind(s)` / `_start(s)` / `_len(s)`**
    — read the current token (the one just advanced to).
  - **drain / finish accept `out_tb = 0`** to route into
    the stream's internal staging tokenbuf — lets the
    iterator pattern work without managing a tokenbuf
    externally.
  - 11 new tcyr probes covering iteration vs push baseline,
    interleaved feed + iterate, empty-stream EOF, null
    safety. Stream record: 56 → 72 bytes (added staging_tb
    + next_idx).
  - Closes the followup queued from 2.0.0.
- **What 2.0.1 added (rolling-buffer streaming):**
  - **Per-feed drainage.** `tokenize_stream_drain(s, tb)`
    re-runs the scanner over the current buffer, commits
    every token whose extent is fully present, and
    compacts unconsumed bytes to offset 0. `abs_offset`
    keeps token starts absolute across compaction.
  - **Trailing-complete heuristic** lets pair-rule tokens
    (TK_STRING / TK_COMMENT / TK_PREPROCESSOR) commit
    early when their close marker is at the tail. Other
    kinds (operators, idents, numbers, whitespace) wait
    for finish.
  - **`VYK_STREAM_CAP` raised 1 MB → 16 MB** — and now
    bounds the *live buffer* (longest in-progress span),
    not the total input. 100 MB-class files stream
    comfortably.
  - 12 new tcyr probes including a byte-at-a-time stream
    that's byte-equivalent to single-shot tokenize.
- **What 2.0.0 added (streaming tokenizer):**
  - **Push-based streaming primitive
    ([ADR 0017](../adr/0017-streaming-api.md)).** Five
    public entries: `tokenize_stream_new` / `_feed` /
    `_drain` / `_finish` / `_free`. Replaces the 1.x
    `tokenize_source(src, lang)` synchronous entry (which
    was removed entirely; no compat shim). Migration is
    mechanical — five lines instead of one.
  - **2.0.0 sub-cut scope: API surface only.** Internal
    scanner unchanged; feed() buffers, finish() runs
    `tokenize_with_grammar` over the buffered bytes. The
    public contract is stable across the upcoming 2.0.1+
    scanner refactor.
  - **15 new tcyr probes** locking the streaming contract:
    multi-chunk feed byte-equivalent to single-chunk;
    feed-after-finish errors with `VYK_ERR_FINISHED`;
    drain-after-finish is idempotent.
  - Bench overhead: ~5–25% per-call regression from the
    extra alloc + buffer copy. Acceptable for the API-
    surface cut; 2.0.1+ removes it.
- **What 1.13.3 added (RC closeout):**
  - **`docs/development/distribution.md`** — the two
    distribution paths in current use (the
    `dist/vyakarana.cyr` source bundle for `cyrius deps`
    consumers, and the GitHub release tarball). Chooser
    table for consumers, release-procedure walkthrough for
    the operator, and a `cyrius package` status note
    (still upstream-stubware; revisit when ark work
    lands).
  - **`docs/audit/2026-05-09-1.13-closeout-audit.md`** —
    covers every surface added in 1.12.0–1.13.2. **0
    CRITICAL / 0 HIGH / 0 MEDIUM / 0 LOW.** Per-surface
    review with detailed bounds analysis on the
    `compose_fenced` step. Recommendation: dedicated audit
    when 2.0.0 streaming lands.
  - No code changes.
- **What 1.13.2 added (markdown fence routing):**
  - **`match = "compose_fenced"` rule type
    ([ADR 0016](../adr/0016-compose-fenced-rule.md)).**
    Captures language tag from fence info-string
    (`[A-Za-z0-9_+-]+`); routes body through the named
    inner grammar. New scanner step 0b ahead of pair / line
    / words. Falls back to TK_STRING on unknown tag, empty
    tag, or unloaded grammar.
  - **Markdown adopts it** — `` ```rust `` body produces
    TK_KEYWORD for `fn`/`let`; `` ```python `` produces
    TK_KEYWORD for `def`.
  - **Toolchain pin bumped** to `cyrius = "5.10.0"` to
    match local stdlib expectations.
- **What 1.13.1 added (CLI polish cut):**
  - **Error messages split by failure class.**
    `unknown_option_error` / `bad_value_error` /
    `extra_arg_error` / `io_error` / `no_grammar_error` —
    each names the problem and points to the next step
    (allowed values, `--list-languages`, `--help`).
    `usage_error` removed.
  - **`vyk --help` Exit-codes + Examples sections.**
    Documents exits 0–4 explicitly; five canonical
    invocations.
  - **`docs/man/vyk.1`** — groff man page mirroring
    `--help`. Render with `groff -man -Tutf8 …` or `man
    -l`.
  - 9 new smoke probes covering every failure class.
- **What 1.13.0 added (performance baseline cut):**
  - **`tests/bcyr/vyakarana.bcyr`** — 8-benchmark suite
    covering tokenize (shell / rust / json / html-compose),
    detect (path / content / combined), and blob-load.
  - **`docs/development/performance.md`** — binary size +
    per-call latency baseline. Future agents diff against
    this at each minor.
  - Binary size measured: `build/vyk` = 325.9 KB (~26 KB
    over the 300 KB roadmap target — dominated by embedded
    grammar blobs per ADR 0014; soft cap, no fix this cut).
  - Tokenize: 3–26 µs for small inputs. Detect: 30 ns
    (path) / 184 ns (content) / 5 µs (combined asm vote).
    Grammar load: 32 µs.
- **What 1.12.1 added:**
  - **`vyk --export-theme=helix`** — Helix `theme.toml`
    output (`"<scope>" = "<hex>"` per kind). Pairs with
    `--theme=<name>` for palette selection.
  - **`vyk --export-theme=iterm`** — iTerm `.itermcolors`
    plist with the 16 ANSI colours plus background /
    foreground / cursor / selection. Dark variant inverts
    background + foreground.
  - Closes the "deferred until a real consumer asks"
    followup from 1.11.1's CHANGELOG.
- **What 1.12.0 added (M7-prep groundwork):**
  - **Fuzz harnesses** (`fuzz/*.fcyr`) — one per public API
    entry: `tokenize.fcyr`, `detect.fcyr`,
    `grammar_load.fcyr`. Each passes deterministically
    against random / adversarial inputs. CI runs them on
    every PR via a new `cyrius fuzz` step.
  - **Stress probes** in `tests/vyakarana.tcyr` 1.12.0 group
    — runaway pair openers, comment soup, broken UTF-8
    mid-ident, unclosed compose, 6× nested compose, 4KB
    ident run. Coverage invariant holds in every case.
    707 → 717 passing.
  - **Security audit doc**
    `docs/audit/2026-05-09-1.11-closeout-audit.md` — surface
    inventory, per-module review of 1.11.x additions,
    fuzz/stress coverage summary. **0 CRITICAL / 0 HIGH /
    0 MEDIUM / 1 LOW (FINDING-007 — fixed in pass).** Carryover
    table from the 2026-04-23 pre-1.0 audit.
  - **FINDING-007 fix.** `grammar_load` blob copy now clamps
    against `GRAMMAR_FILE_CAP - 1`. Defense-in-depth.
- **What 1.11.2 added (third and final sub-cut of the
  external-integrations wave):**
  - **Content-based language detection** (`src/detect.cyr` +
    ADR 0015). Three public entries:
    `detect_language(path)` (extension/basename, moved from
    main.cyr), `detect_language_from_content(src, len)` (BOM
    strip + shebang interp lookup + signature peek for
    `<?xml` / `<!DOCTYPE html>`), and
    `detect_language_combined(path, src, len)` (path first,
    then asm flavour rescore for `.s` / `.S`, content
    fall-through for extensionless files).
  - **Asm flavour resolution.** `tests/corpus/asm_x86_64.s`
    and `tests/corpus/asm_aarch64.s` now auto-detect
    correctly via weighted-signal scoring on the first 4KB.
    Closes the `.s` ambiguity carried since 1.2.3.
  - **`vyk` flow change.** Source file read happens in
    `main()` before detection, so the same buffer feeds
    detection and tokenization (no second read). The old
    `tokenize_file` is now `tokenize_buf(buf, n, …)`.
  - **`src/detect.cyr` joins `[lib] modules`** so consumers
    pulling `dist/vyakarana.cyr` get the byte API alongside
    `tokenize_source` and `lsp_kind_*`.
- **What 1.11.1 added (second sub-cut of the external-integrations
  wave):**
  - **Grammar composition** (`match = "compose"` rule type +
    ADR 0013). New scanner pipeline step 0 — runs before
    everything else so outer-grammar tokenization doesn't eat
    the start markers. Routes the body bytes between `start`
    and `end` markers through a different grammar named in
    the new `inner` field. Markers emit as `TK_PUNCTUATION`;
    body tokens are recursively produced via the inner
    grammar with offsets shifted into the outer source's
    coordinate system. Graceful degradation when the inner
    grammar isn't loaded (body becomes one `TK_STRING`).
  - **HTML uses compose rules** for `<style>` → `css` and
    `<script>` → `javascript` — closes the 1.7.0 "embedded
    blocks tokenize as plain HTML" gap.
  - **Theme export** (`vyk --export-theme=<format>` flag +
    `src/theme_export.cyr`). VS Code `theme.json` is shipped
    (universal target — VS Code, Cursor, Codium and other
    forks). Pair with `--theme=<name>` to pick the source
    palette. Helix / iTerm formats deferred until a real
    consumer asks.
  - **Self-contained dist bundle** (ADR 0014). Through
    1.11.0 `dist/vyakarana.cyr` called `file_read_all` on
    `grammars/<name>.cyml` at runtime — but `cyrius deps`
    only vendors the bundle file. Consumers following the
    documented integration path got an empty tokenizer with
    no diagnostic. Fixed by inlining every grammar as a
    Cyrius string literal via the new
    `scripts/embed-grammars.sh` (writes
    `src/grammar_blobs.cyr`, gitignored, regenerated on each
    gate run). `grammar_load` consults the blob registry
    first; file-load fallback retained for grammar-author
    dev workflow. Bundle grew 82KB → 253KB.
- **Test count:** 731/731 (was 717 at 1.13.1; 13 new 1.13.2
  probes covering Rust + Python fence routing, unknown-tag
  fallback, empty-tag fallback, unclosed-fence fall-through,
  `c++` tag accepts; M3 markdown probe refreshed for the new
  fence shape). 3 fuzz harnesses pass.
- **No new grammars** — 38 bundled, unchanged.

### 1.10.0 deliverables (recap)

- `vyk --theme=<name>` flag (three bundled themes).
- Architecture note 004 — theme-palette contract.
- Consumer integration guide at
  `docs/guides/consumer-integration.md`.

### Vidya integration — ready, not yet started

Per the 1.10.0 cut, vidya can adopt vyakarana as its code
renderer whenever vidya plans a renderer rewrite. The
integration is documented in vidya's own roadmap (under
"Renderer integration — vyakarana") and points to the
consumer guide here. No vyakarana cut needed.
- **What 1.9.0 added:** two AGNOS-native grammars —
  **CYML and LLVM-IR**. Token counts: cyml 659, llvm_ir 1194 —
  zero errors on canonical samples. **No new scanner
  extensions needed.**
- **Self-hosting closed.** `build/vyk grammars/cyml.cyml`
  produces zero errors. The grammar file format vyakarana
  uses for its own definitions is now bundled as one of the
  bundled grammars. yukti config (`yukti.cyml`) and vidya
  content samples (`content/<topic>/*.cyml`) all benefit too.
- **First non-stand-in post-M3 corpus.** CYML's
  `tests/corpus/dependencies.cyml` is a real vidya snapshot
  (`content/cyrius/dependencies.cyml`, 233 lines) — not a
  hand-rolled `concept.<ext>` per ADR 0006. Demonstrates the
  reciprocal relationship that ADR 0001 set up: vidya
  becomes a corpus supplier when it has the matching content.
- **Sigil-in-`ident_start` pattern logged** — used 7 times now
  across the bundled set, all with the same shape:
  - `$` — Rust macros (1.1.0, ADR 0007), Zig builtins (1.2.0
    via `@`), PHP variables (1.4.0), Java/Kotlin/Swift
    compiler-generated names (1.3.0/1.3.0/1.4.0), GraphQL
    operation variables (1.6.0).
  - `@` — Java/Kotlin annotations (1.3.0), Zig builtins
    (1.2.0), Elixir module attributes (1.5.0), CSS at-rules
    (1.7.0), GraphQL directives (1.6.0).
  - `%` — Elixir struct/map literals (1.5.0), LLVM-IR locals
    (1.9.0).
  - `!` — LLVM-IR metadata refs (1.9.0).
  - `#` — CSS id selectors / hex colors (1.7.0).
  - `-` — CSS custom properties (`--var`, 1.7.0).
  - `.` — asm directives / labels (1.2.2 / 1.2.3).
  Each grammar adds the byte to `ident_start` (sometimes
  `ident_cont` too), then optionally adds a words-rule entry
  to promote the resulting ident to keyword when the name is
  reserved. Pattern is robust enough to plan around.
- **Test count:** 622/622 (was 599 at 1.8.0; added 23
  assertions across 2 new grammars).
- **Grammars:** 38 bundled (shell, toml, json, cyrius, rust,
  yaml, markdown, c, typescript, javascript, python, go, zig,
  asm_x86_64, asm_aarch64, java, kotlin, cpp, csharp, php,
  ruby, lua, swift, elixir, ocaml, haskell, sql, graphql,
  protobuf, html, xml, css, scss, dockerfile, makefile, ini,
  **cyml, llvm_ir**).
- **Toolchain pin:** `cyrius = "5.10.0"` in `cyrius.cyml`
  (unchanged since 1.0.3).
- **Build state: GREEN on cyrius 5.10.0.** `cyrius build`
  clean; `cyrius test tests/vyakarana.tcyr` 622/622;
  `sh scripts/smoke.sh build/vyk` reports M0+M1+M2+M3 passing
  at v1.9.0. `dist/vyakarana.cyr` regenerated.
- **Consumer pressure:** unchanged. Public `tokenize_source` /
  `tokenbuf` API is unchanged across 1.0.0 → 1.9.0. Grammar
  record stayed at 160 bytes since 1.6.0.

### Language line closed at 1.9.0

The original 1.x roadmap targeted seven language batches
(1.3 – 1.9). With 1.9.0 shipped, **all seven have landed**:
- 1.3.0 — JVM + C-family
- 1.4.0 — Scripting + mobile
- 1.5.0 — Functional tier
- 1.6.0 — Data / query / IDL
- 1.7.0 — Markup + styling
- 1.8.0 — DevOps + infrastructure
- 1.9.0 — AGNOS-native

That's 27 grammars added across the language batches, on top
of 11 starter grammars at v1.0.0. **38 bundled, all-clean** on
their canonical samples. The 1.x line continues with the pre-
2.0 prep waves (1.10–1.13).

### Stand-in corpora — replace when vidya ships

Per [ADR 0006](../adr/0006-standin-corpus-policy.md), eight
grammars (json, yaml, markdown, javascript, java, kotlin, cpp,
csharp, php, ruby, lua, swift) use hand-rolled
`tests/corpus/concept.<ext>` samples. Each is ~150–250 lines
following the lexer+parser theme. When vidya ships reference
samples for any of them, swap the stand-in for the vidya
snapshot and update the corpus README.

### Variable-length-delimiter shapes — collective ADR pending

Four grammars currently document variable-length terminator
forms as deferred:

- **Lua** `[==[ … ]==]` long brackets with `=` padding (1.4.0).
- **Ruby** `<<~HEREDOC … HEREDOC` heredocs (1.4.0).
- **PHP** `<<<EOT … EOT;` heredocs / nowdocs (1.4.0).
- **Swift** `#"…"#`, `##"…"##` raw strings (1.4.0).

The scanner has no variable-length-delimiter pair rule today;
these all share the same scanner shape gap. If a real corpus
forces one of them, expect a collective ADR + scanner extension
that handles all four uniformly.
- **Toolchain pin:** `cyrius = "5.10.0"` in `cyrius.cyml`
  (unchanged since 1.0.3).
- **Build state: GREEN on cyrius 5.10.0.** `cyrius build` clean;
  `cyrius test tests/vyakarana.tcyr` 431/431;
  `sh scripts/smoke.sh build/vyk` reports M0+M1+M2+M3 passing
  at v1.2.2. `dist/vyakarana.cyr` regenerated.
- **Consumer pressure:** unchanged — owl's M3b stays unblocked;
  the public `tokenize_source` / `tokenbuf` API is unaffected.

---

## Known cosmetic gaps (coverage holds; no `error` tokens)

Closed in 1.1.0:

- **Rust macro metavariables** — `$tok:fragment` now tokenizes as
  one `ident`. ADR 0007. Was: 79 errors per macro-heavy sample.
- **TOML triple-quoted strings** — `"""…"""` and `'''…'''` are
  rules now. ADR 0008. Was: 188 errors per content-heavy file.
- **UTF-8 outside strings + C block comments** — `unicode_ident`
  default flag + a `/* … */` pair rule in `c.cyml`. ADR 0009.
  Was: 8 errors per typical vidya C sample.

Still cosmetic-only and waiting on a future ADR:

- **Char literals** (`'x'`, `'\0'`) and byte-char-with-escape
  (`b'\n'`): Rust + C still split into op/body/op triples.
  Needs a `char_literal = true` default with 2-3 char lookahead.
- **F-string prefix**: `f"..."` → `ident(f) + string("...")` in
  Python. Same for r/b/rb/fr prefixes.
- **Block comments in Rust** — Rust's `/* */` is *nestable*, so
  the simple pair rule used for C won't work. Needs a nesting
  variant. Not triggered by the canonical sample.
- **Python INDENT/DEDENT**: structural tokens Python parsers want
  aren't emitted. Not needed for the tokenizer's correctness bar.

---

## Past audits

- [2026-04-23 — Pre-1.0 audit](../audit/2026-04-23-audit.md):
  0 CRITICAL / 0 HIGH / 0 MEDIUM-open (one MEDIUM fixed in-pass);
  5 LOW. FINDING-006 fixed in 1.0.1.
- [2026-05-08 — 1.2.x closeout](../audit/2026-05-08-1.2.x-closeout-audit.md):
  scope was the new-language batch (asm × 2, java/kotlin/cpp/csharp/php/ruby/lua/swift/elixir/ocaml/haskell).
- [2026-05-09 — 1.11.x closeout](../audit/2026-05-09-1.11-closeout-audit.md):
  surfaces added in 1.11.0 / 1.11.1 / 1.11.2 (LSP bridge,
  composition, theme export, embedded blobs, content
  detection). 0 CRITICAL / 0 HIGH / 0 MEDIUM / 1 LOW
  (FINDING-007, fixed in-pass). Fuzz + stress coverage
  established.
- [2026-05-09 — 1.13.x closeout](../audit/2026-05-09-1.13-closeout-audit.md):
  surfaces added in 1.12.0–1.13.2 (fuzz harnesses,
  Helix/iTerm theme emitters, bench suite, error-message
  split, man page, compose_fenced rule + scanner step 0b,
  toolchain pin bump). 0 CRITICAL / 0 HIGH / 0 MEDIUM / 0
  LOW. No new findings.
- [2026-05-09 — 2.0.x closeout](../audit/2026-05-09-2.0.x-closeout-audit.md):
  streaming surfaces (push primitive, rolling buffer, pull
  adapter, pending-pair fast path). 0 CRITICAL / 0 HIGH /
  0 MEDIUM / **2 LOW (FINDING-008, FINDING-009 — both
  fixed in-pass).** Buffer-cap semantics documented;
  `VYK_STREAM_CAP` caps live buffer not total input.

See `SECURITY.md` for the living state of the audit findings.
Next scheduled audit: 2.1.x closeout (after the four grammar
batches land — surface additions are mostly declarative
`.cyml` files; the audit confirms grammar-loader hardening
didn't regress).

---

## Next up — open queue

Closed waves:

- **1.11.x — external integrations.** LSP bridge (1.11.0,
  ADR 0012); grammar composition + theme export +
  self-contained dist bundle (1.11.1, ADRs 0013–0014);
  content-based detection (1.11.2, ADR 0015).
- **1.12.x — hardening + theme export polish.** Fuzz +
  stress harness + post-1.11 audit (1.12.0); Helix + iTerm
  theme export (1.12.1).
- **1.13.x — RC polish.** Bench baseline (1.13.0), error
  messages + man page (1.13.1), markdown fence routing
  (1.13.2, ADR 0016), distribution + 1.13-closeout audit
  (1.13.3 — 0 findings).
- **2.0.x — streaming tokenizer.** API surface (2.0.0,
  ADR 0017); rolling-buffer per-feed drainage (2.0.1);
  pull adapter (2.0.2).

2.0.x is closed. Now in flight — 2.1.x grammar batches:

- **2.1.0 — PowerShell / Crystal / Julia grammars.** Three
  new general-purpose languages.
- **2.1.1 — Vue / Svelte single-file components.** Both use
  `<template>` / `<script>` / `<style>` blocks — prime
  use case for compose_fenced.
- **2.1.2 — Nix grammar.**
- **2.1.3 — Terraform / HCL grammar.** No work currently in
flight. The post-streaming queue is open — nothing forces
the next cut. Possible directions when work resumes:

- **Scanner state-machine optimization.** 2.0.1's
  rescan-and-commit drain is O(buf_len) per call. A real
  state machine would scan only the new bytes since the
  previous commit, dropping the per-feed cost from
  O(buf_len) to O(new_bytes). Worth doing if a real
  consumer surfaces a profiling complaint.
- **Discardable staging buffer.** The pull adapter's
  internal tokenbuf grows monotonically across iteration.
  For very long streams (millions of tokens) the tokenbuf
  itself becomes a memory cost. Adding a "discard tokens
  before index N" primitive would cap pull-mode memory
  too.
- **Additional grammars.** Eight categories surfaced in
  prior cuts but didn't make 2.x: shell variants,
  Terraform / HCL, Nix, Vue / Svelte single-file, MDX,
  PowerShell, Crystal, Julia.
- **Real-corpus fuzz harness** (flagged in the
  2026-05-09 1.13-closeout audit's recommendations).
  Mutates vidya snapshots instead of random bytes —
  catches shape-specific regressions.

These are all consumer-driven. No forced minor; the next
cut waits for a real ask.

Each new grammar is a `grammars/<name>.cyml` plus a
`tests/corpus/<name>.<ext>` (vidya snapshot per
[ADR 0001](../adr/0001-corpus-sync-policy.md)) plus probe
assertions in `tests/vyakarana.tcyr`. The data-driven scanner
already covers the structural shapes; expect each addition to be
mostly grammar-file work unless a language forces a new rule
type (in which case a new ADR per the M2 scope of
[ADR 0005](../adr/0005-m2-rule-type-scope.md)).

**Out-of-scope follow-ups still on the books** (capture before
starting 1.2.0 so they don't drift away):

- Rust byte-char-literal-with-escape (`b'\n'`) — pre-existing
  gap, not addressed by ADR 0007. Likely solved with the same
  `char_literal` scanner default that the C/Rust char-literal
  gap is waiting on.
- Python f-string / r-string / b-string prefixes coalescing into
  the string token. Documented gap; defer until a corpus or a
  consumer asks for it.
- Float literals + datetime literals in TOML
  ([ADR 0008](../adr/0008-toml-triple-quoted-strings.md)
  scoped them out).

Post-1.1 roadmap ([./roadmap.md](./roadmap.md) has the detail):

- **M4** — Theme-palette contract with owl. Shared palette header
  is the likely shape.
- **M5** — Streaming tokenizer (iterator API). Memory goes
  O(tokens in flight); enables `owl huge.log`.
- **M6** — vidya reverse consumption (vidya starts rendering its
  `content/lexing_and_parsing/` samples through vyakarana).
- **M7** — Polish + release candidate.

---

## Cross-repo coordination

- **owl** (`/home/macro/Repos/owl`) — its M3b was blocked on M1
  and can now add `[deps.vyakarana]` at the tag the user cuts.
  Do **not** sidestep with a path hack.
- **vidya** (`/home/macro/Repos/vidya`) — read before making
  corpus decisions. M6 will bring vidya on as a consumer; don't
  pre-negotiate that now.
- **cyrius** (`/home/macro/Repos/cyrius`) — toolchain. Pinned at
  `5.9.36` in `cyrius.cyml`. The 2026-05-07 `include`-graph
  regression filed against 5.9.32
  ([`./issues/2026-05-07-cyrius-include-graph-regression.md`](./issues/2026-05-07-cyrius-include-graph-regression.md))
  is resolved on 5.9.36. If you find another compiler bug, file
  it upstream; don't work around it in vyakarana.

---

*Live status only. Architecture / frozen contracts / module map
live in [`../architecture/`](../architecture/). Refresh history:
2026-04-23 (M0 + M1/M2/M3 same day); 2026-05-07 (cyrius pin
5.9.32 / red); 2026-05-08 (1.0.3 cut + toolchain unblock);
2026-05-08 (1.1.0 cut + modernization fixes + docs reshape per
AGNOS first-party-documentation standard); 2026-05-08 (1.2.0 cut
+ Go and Zig grammars); 2026-05-08 (1.2.1 cut + `char_literal`
flag); 2026-05-08 (1.2.2 cut + `asm_x86_64`); 2026-05-08
(1.2.3 cut + `asm_aarch64` + roadmap restructure); 2026-05-08
(1.2.4 closeout — dead-code cleanup + stale-comment sweep +
1.2.x audit); 2026-05-08 (1.3.0 cut + JVM + C-family —
java/kotlin/cpp/csharp via ADR 0006 stand-ins). Next refresh:
when 1.4.0 (scripting + mobile) ships.*
