# vyakarana — current state

> **Last refresh:** 2026-05-08 | **Refresh cadence:** every release
> (1.x cuts), plus any session that shifts the gates' colour or
> the active task.
>
> **Read this file before doing anything.** 1.0.0–1.11.2 are
> shipped. As of 2026-05-08 the toolchain pin is `cyrius = "5.9.36"`.
> 1.10.0 opened the pre-2.0 prep sequence with the theme-palette
> contract and consumer guide; **1.11.2 ships content-based
> language detection** — closes the 1.11.x external-integrations
> wave. 38 grammars bundled (unchanged), 707/707 tests passing.
> The 1.11.x window split into three sub-cuts: 1.11.0 LSP
> bridge, 1.11.1 grammar composition + theme export + self-
> contained dist bundle, 1.11.2 content-based detection
> (this cut). With 1.11.x done, next is 1.12.0 (fuzz + stress
> harness, M7 prep) — see §Next up.
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

- **Version:** `1.11.2` in `VERSION`, `src/version_str.cyr`, and
  `dist/vyakarana.cyr`. Full 1.x tag history in the CHANGELOG.
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
- **Test count:** 707/707 (was 682 at 1.11.1; 25 new detect
  probes covering path dispatch, shebang interp matching for
  six interp families, three signature patterns, BOM strip,
  combined dispatch with asm flavour vote). 4 new
  content-detect smoke probes (auto-detect both asm corpora,
  shebang-routed python file, `<?xml` signature).
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
- **Toolchain pin:** `cyrius = "5.9.36"` in `cyrius.cyml`
  (unchanged since 1.0.3).
- **Build state: GREEN on cyrius 5.9.36.** `cyrius build`
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
- **Toolchain pin:** `cyrius = "5.9.36"` in `cyrius.cyml`
  (unchanged since 1.0.3).
- **Build state: GREEN on cyrius 5.9.36.** `cyrius build` clean;
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
  5 LOW. FINDING-006 fixed in 1.0.1. See `SECURITY.md` for the
  living state of the audit findings.

Next scheduled audit: 1.2.x closeout (after the new-language
additions land).

---

## Next up — 1.12.0

The 1.11.x external-integrations wave is complete:

- **1.11.0 — LSP semantic-tokens bridge.** Shipped. ADR 0012.
- **1.11.1 — Grammar composition + theme export + self-
  contained dist bundle.** Shipped. ADRs 0013, 0014. HTML
  routes `<style>` → CSS and `<script>` → JS; bundle inlines
  every grammar so `cyrius deps` consumers no longer need
  `grammars/`.
- **1.11.2 — Content-based language detection.** Shipped
  (this cut). ADR 0015. `src/detect.cyr` exposes path,
  byte-content, and combined entries; auto-detect resolves
  the `.s` ambiguity and handles extensionless shebang /
  signature files.

Followups from the 1.11.x window that are still queued:

- **Markdown fence routing** (`` ```rust `` etc.). Current
  `match = "compose"` rule shape uses literal-prefix start —
  can't bind a captured language tag. Would need a new
  `match = "compose_fenced"`. See ADR 0013 §When to revisit.
- **Helix / iTerm theme export formats.** 1.11.1 ships the
  VS Code `theme.json` only. Add formats when a real consumer
  asks.

Now in flight:

- **1.12.0** — Fuzz + stress harness (M7 prep). Audit doc.
- **1.13.0** — RC polish: binary size, startup benchmarks,
  error messages, man page, AGNOS / Cyrius packaging.
- **2.0.0** — Streaming tokenizer (M5 carryover). The one
  scheduled break in the public API.

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
