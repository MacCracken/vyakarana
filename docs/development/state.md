# vyakarana — current state

> **Last refresh:** 2026-05-08 | **Refresh cadence:** every release
> (1.x cuts), plus any session that shifts the gates' colour or
> the active task.
>
> **Read this file before doing anything.** 1.0.0–1.6.0 are
> shipped. As of 2026-05-08 the toolchain pin is `cyrius = "5.9.36"`.
> 1.5.0 added Elixir/OCaml/Haskell; **1.6.0 adds SQL/GraphQL/
> Protobuf (data + query + IDL batch) plus a new
> `case_insensitive_keywords` scanner default ([ADR 0011](../adr/0011-case-insensitive-keywords-default.md))
> needed by SQL.** **29 grammars bundled now, 544/544 tests
> passing.** Grammar record grew 152 → 160 bytes (new
> `case_insensitive_kw` field at offset 152). Next: 1.7.0 —
> markup + styling (html/xml/css/scss) — see §Next up.
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

- **Version:** `1.6.0` in `VERSION`, `src/version_str.cyr`, and
  `dist/vyakarana.cyr`. Full 1.x tag history in the CHANGELOG.
- **What 1.6.0 added:**
  - **`case_insensitive_keywords` scanner default
    ([ADR 0011](../adr/0011-case-insensitive-keywords-default.md)).**
    `Grammar` record at offset 152, `GRAMMAR_SIZE` 152 → 160.
    `_ds_lookup_keyword` does case-folded comparison when on;
    grammars that leave the flag off pay zero new hot-path
    cost (delegates to `memeq` as before). ASCII-only fold by
    design.
  - **SQL grammar** (599 tokens, zero errors). First grammar
    to enable `case_insensitive_keywords` — `SELECT` /
    `select` / `Select` all match the canonical keyword list.
    Dialect-neutral baseline.
  - **GraphQL grammar** (623 tokens, zero errors). `$` and
    `@` in `ident_start`; `"""…"""` block strings.
  - **Protobuf grammar** (628 tokens, zero errors). Mechanical
    C-family. Primitive types as keywords.
- **Test count:** 544/544 (was 517 at 1.5.0; added 27
  assertions, including 5 SQL case-mixing probes that exercise
  ADR 0011).
- **Grammars:** 29 bundled (shell, toml, json, cyrius, rust,
  yaml, markdown, c, typescript, javascript, python, go, zig,
  asm_x86_64, asm_aarch64, java, kotlin, cpp, csharp, php,
  ruby, lua, swift, elixir, ocaml, haskell, **sql, graphql,
  protobuf**).
- **Toolchain pin:** `cyrius = "5.9.36"` in `cyrius.cyml`
  (unchanged since 1.0.3).
- **Build state: GREEN on cyrius 5.9.36.** `cyrius build`
  clean; `cyrius test tests/vyakarana.tcyr` 544/544;
  `sh scripts/smoke.sh build/vyk` reports M0+M1+M2+M3 passing
  at v1.6.0. `dist/vyakarana.cyr` regenerated.
- **Consumer pressure:** unchanged. Public `tokenize_source` /
  `tokenbuf` API is unchanged across 1.0.0 → 1.6.0.
  **Grammar record grew 152 → 160 bytes** (new
  `case_insensitive_kw` field) — same private-ABI bump as
  1.1.0 (`unicode_ident`) and 1.2.1 (`char_literal`), no
  consumer reads the in-memory `Grammar` directly.

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

## Next up — 1.7.0 (Markup + styling)

Per the [roadmap](./roadmap.md), the next batch is
**1.7.0 — markup + styling**: `html`, `xml`, `css`,
`scss` / `less`. ADR 0006 stand-ins likely (no vidya reference
samples).

Surfaces to watch:
- **HTML** has `<!-- … -->` comments (4-byte / 3-byte pair),
  `<tag attr="val">` markup, attribute values that may use
  single or double quotes, and embedded `<script>` / `<style>`
  blocks that ideally route to JavaScript / CSS grammars (a
  grammar-composition feature on the roadmap for 1.11.0). For
  1.7.0 they tokenize as plain `<` op + ident + `>` op, with
  inner content as ident / string / etc.
- **XML** is HTML's stricter cousin — `<?xml ?>` declarations,
  `<![CDATA[…]]>` blocks, namespaces. Expect mostly the same
  shape as HTML.
- **CSS** has `/* */` comments only (no line form), property:
  value declarations, `@media`/`@import`/`@keyframes` at-rules,
  `#id` and `.class` selectors, hex color literals. The `#`
  for selectors and `@` for at-rules will need either
  `ident_start` extension or operator treatment.
- **SCSS / LESS** are CSS supersets — variables (`$var` SCSS,
  `@var` LESS), nesting, `&` parent selector, mixins. SCSS
  also adds `//` line comments. SCSS most likely shares CSS's
  grammar with extra keywords / operators; LESS less so.

After 1.7.0, the roadmap continues with 1.8.0 (devops),
1.9.0 (AGNOS-native), then the pre-2.0 prep waves (1.10–1.13).
2.0.0 is the streaming-tokenizer break.

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
