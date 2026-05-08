# vyakarana — current state

> **Last refresh:** 2026-05-08 | **Refresh cadence:** every release
> (1.x cuts), plus any session that shifts the gates' colour or
> the active task.
>
> **Read this file before doing anything.** 1.0.0–1.3.0 are
> shipped. As of 2026-05-08 the toolchain pin is `cyrius = "5.9.36"`.
> The 1.2.x line closed at 1.2.4 (closeout audit clean).
> **1.3.0 ships the JVM + C-family batch — Java, Kotlin, C++,
> C# — all with ADR 0006 stand-in corpora since vidya doesn't
> yet have reference samples for these languages.** Notably, no
> new scanner extensions were needed: cpp (the most likely to
> surface ADR work) was handled by the existing operator and
> identifier machinery. 19 grammars bundled now, 463/463 tests
> passing. Next: 1.4.0 — scripting + mobile (php/ruby/lua/swift)
> — see §Next up.
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

- **Version:** `1.3.0` in `VERSION`, `src/version_str.cyr`, and
  `dist/vyakarana.cyr`. Full 1.x tag history through 1.2.4 in
  the CHANGELOG.
- **What 1.3.0 added:** four JVM + C-family grammars in one cut
  — **Java, Kotlin, C++, C#**. All four ship with hand-rolled
  stand-in corpora per
  [ADR 0006](../adr/0006-standin-corpus-policy.md) since vidya
  doesn't yet ship reference samples for these languages.
  Token counts: java 1705, kotlin 1320, cpp 1686, csharp 1399
  — all zero errors on canonical samples. **No new scanner
  extensions were needed**: cpp handled templates / `::` /
  generics / namespaces with existing operator + identifier
  machinery. The 1.1.0 / 1.2.1 work (`unicode_ident`,
  `char_literal`, block-comment pair rule) covered everything.
- **Test count:** 463/463 (was 439 at 1.2.4 — added 24
  assertions: 3 probes per grammar × 4 grammars = 12, plus
  some auxiliary checks).
- **Grammars:** 19 bundled (shell, toml, json, cyrius, rust,
  yaml, markdown, c, typescript, javascript, python, go, zig,
  asm_x86_64, asm_aarch64, **java, kotlin, cpp, csharp**).
- **Toolchain pin:** `cyrius = "5.9.36"` in `cyrius.cyml`
  (unchanged since 1.0.3).
- **Build state: GREEN on cyrius 5.9.36.** `cyrius build`
  clean; `cyrius test tests/vyakarana.tcyr` 463/463;
  `sh scripts/smoke.sh build/vyk` reports M0+M1+M2+M3 passing
  at v1.3.0. `dist/vyakarana.cyr` regenerated.
- **Consumer pressure:** unchanged. Public `tokenize_source` /
  `tokenbuf` API is unchanged across 1.0.0 → 1.3.0. Grammar
  record stayed at 152 bytes since 1.2.1. owl can bump its pin
  to 1.3.0 to pick up the four new grammars.

### Stand-in corpora — replace when vidya ships

Per [ADR 0006](../adr/0006-standin-corpus-policy.md), the four
1.3.0 grammars use hand-rolled `tests/corpus/concept.<ext>`
samples. They're intentionally short (~150 lines each) and follow
the lexer+parser theme that vidya's `lexing_and_parsing/`
samples use. When vidya adds reference samples for any of these
four languages, swap the stand-in for the vidya snapshot and
update the corpus README.
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

## Next up — 1.4.0 (Scripting + mobile)

Per the [roadmap](./roadmap.md), the next batch is
**1.4.0 — scripting + mobile**: `php`, `ruby`,
`lua`, `swift`. Same recipe as 1.3.0 — vidya likely doesn't
have reference samples for these either, so plan on ADR 0006
stand-ins.

Surfaces to watch:
- **Ruby** has `=begin`/`=end` block comments (different shape
  from `/* */`), `<<~HEREDOC` heredocs (variable-length), and
  string interpolation `#{expr}`. May surface scanner ADR work.
- **Lua** has `--[[` long-comment markers and `[[…]]` long
  strings — both with optional `=` padding for nested forms
  (`[==[…]==]`). Variable-length-delimiter pair rules don't
  exist in the scanner today. Possible ADR.
- **Swift** has multi-line `"""…"""` strings (same shape as
  TOML's [ADR 0008](../adr/0008-toml-triple-quoted-strings.md))
  and string interpolation `\(expr)`.
- **PHP** is mostly C-family at the token level; should be
  the most mechanical of the four.

After 1.4.0, the roadmap continues with 1.5.0 (functional —
elixir, ocaml, haskell), 1.6.0 (data/query/IDL), 1.7.0 (markup),
1.8.0 (devops), 1.9.0 (AGNOS-native), then the pre-2.0 prep
waves (1.10–1.13). 2.0.0 is the streaming-tokenizer break and
the only release scheduled in the 2.x line.

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
