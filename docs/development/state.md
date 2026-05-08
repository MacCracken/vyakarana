# vyakarana — current state

> **Last refresh:** 2026-05-08 | **Refresh cadence:** every release
> (1.x cuts), plus any session that shifts the gates' colour or
> the active task.
>
> **Read this file before doing anything.** 1.0.0–1.2.0 are
> shipped. As of 2026-05-08 the toolchain pin is `cyrius = "5.9.36"`,
> 1.1.0 shipped three vidya-driven modernization fixes (Rust
> `$`-macro metavars, TOML triple-quoted strings, `unicode_ident`
> + C block comments), and **1.2.0 adds Go and Zig grammars**
> (canonical samples and 7-sample spot-checks all clean modulo
> the pre-existing char-literal-with-escape gap). All three
> gates are green at 1.2.0. The 1.2.x line continues with asm
> and openqasm — see §Next up.
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

- **Version:** `1.2.0` in `VERSION`, `src/version_str.cyr`, and
  `dist/vyakarana.cyr`. Tagged predecessors: `1.0.0`, `1.0.1`
  (FINDING-006 ANSI-escape sanitizer), `1.0.2` (distlib bundle),
  `1.0.3` (cyrius `5.9.36` pin), `1.1.0` (vidya modernization
  fixes — Rust `$`-macros, TOML triple-quoted, `unicode_ident`
  + C block comments).
- **What 1.2.0 added:** two new grammars, opening the
  new-language line:
  - **Go** (`grammars/go.cyml` + `tests/corpus/go.go`). Canonical
    sample: 2151 tokens, zero errors. 6 of 7 vidya `go.go`
    spot-checks clean; the seventh hits the pre-existing
    `'\n'` char-literal-escape gap (the same one C and Rust
    have).
  - **Zig** (`grammars/zig.cyml` + `tests/corpus/zig.zig`). `@`
    in `ident_start` so `@import` / `@TypeOf` / etc. tokenize
    as one ident. Canonical sample: 2279 tokens, zero errors.
    6 of 7 vidya `zig.zig` spot-checks clean; same `'\n'` gap
    on the seventh.
  - Both are wired into `bootstrap_grammars`, `detect_language`,
    the smoke loop (12-grammar list now), and four probe
    assertions each in `tests/vyakarana.tcyr`. Test count: 417
    (was 407 at 1.1.0).
- **Toolchain pin:** `cyrius = "5.9.36"` in `cyrius.cyml`
  (unchanged since 1.0.3).
- **Build state: GREEN on cyrius 5.9.36.** `cyrius build` clean;
  `cyrius test tests/vyakarana.tcyr` 417/417;
  `sh scripts/smoke.sh build/vyk` reports M0+M1+M2+M3 passing
  at v1.2.0. `dist/vyakarana.cyr` regenerated.
- **Consumer pressure:** unchanged — owl's M3b stays unblocked.
  No grammar-record layout changes vs 1.1.0; the public
  `tokenize_source` / `tokenbuf` API is unaffected.

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

## Next up — 1.2.x: continue the new-language line

1.2.0 shipped Go and Zig. Two more candidates from
`vidya/content/lexing_and_parsing/` remain on the line:

- `asm_x86_64.s` and `asm_aarch64.s` — Assembly (two dialects;
  either one grammar with a dialect switch or two separate
  grammars). Probably 1.2.1 / 1.2.2.
- `openqasm.qasm` — OpenQASM. Domain-specific; probably 1.2.3.

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
+ Go and Zig grammars). Next refresh: when the next 1.2.x
grammar ships (asm or openqasm).*
