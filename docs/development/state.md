# vyakarana — current state

> **Last refresh:** 2026-05-08 | **Refresh cadence:** every release
> (1.x cuts), plus any session that shifts the gates' colour or
> the active task.
>
> **Read this file before doing anything.** 1.0.0–1.2.3 are
> shipped. As of 2026-05-08 the toolchain pin is `cyrius = "5.9.36"`.
> 1.2.x history: 1.2.0 added Go and Zig; 1.2.1 shipped
> `[defaults] char_literal` (ADR 0010); 1.2.2 shipped
> `asm_x86_64` (Intel syntax); **1.2.3 ships `asm_aarch64`** —
> same tokenizer with ARM-specific tuning (`//` line comments,
> `#` immediate-prefix as operator, `.` in both ident_start and
> ident_cont so `b.eq`/`b.ne` are one ident). All 7 vidya
> `asm_aarch64.s` spot-checks come back clean. Three gates green
> at 1.2.3. **One cut left in 1.2.x: 1.2.4 closeout / P(-1)
> hardening** — see §Next up.
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

- **Version:** `1.2.3` in `VERSION`, `src/version_str.cyr`, and
  `dist/vyakarana.cyr`. Tagged predecessors:
  `1.0.0` / `1.0.1` (ANSI-escape sanitizer) /
  `1.0.2` (distlib bundle) / `1.0.3` (cyrius 5.9.36 pin) /
  `1.1.0` (Rust `$`-macros, TOML triple-quoted, `unicode_ident`
  + C block comments) / `1.2.0` (Go + Zig) /
  `1.2.1` (`char_literal` flag — ADR 0010) /
  `1.2.2` (`asm_x86_64`).
- **What 1.2.3 added:** `asm_aarch64` grammar
  (`grammars/asm_aarch64.cyml` + `tests/corpus/asm_aarch64.s`,
  1367 tokens, zero errors). Same data-driven tokenizer as
  `asm_x86_64` with ARM-specific tuning: `//` line comments
  instead of `#`, `#` as operator (immediate prefix), `!` as
  operator (write-back addressing), and **`.` in both
  `ident_start` and `ident_cont`** so conditional branches
  (`b.eq` / `b.ne` / `b.lt` / `b.hi`) tokenize as a single
  ident. ARM-specific GAS directives (`.arch`, `.cpu`, `.fpu`,
  `.arm`, `.thumb`) join the keyword list. **All 7 vidya
  `asm_aarch64.s` spot-checks come back at zero errors** —
  cleaner than `asm_x86_64`'s 6/7 because ARM doesn't have the
  AT&T-vs-Intel split. Wired into `bootstrap_grammars`, smoke
  loop (now 15 grammars), and five probe assertions. Test
  count: 439 (was 431 at 1.2.2).
- **Roadmap restructured (also in 1.2.3):** `2.x.x` is now
  reserved for **breaking changes only**. The carried-over
  M4–M7 work moves to pre-2.0 1.x.x cuts: theme-palette
  contract + vidya reverse consumption → 1.10.0, external
  integrations → 1.11.0, fuzz/stress harness → 1.12.0, RC
  polish → 1.13.0. **2.0.0 is now the streaming-tokenizer
  return-type change alone.**
- **Dispatch:** `.s` and `.S` continue to default to
  `asm_x86_64`. ARM users pass `--language=asm_aarch64`. A
  content-based fallback (sniff `.arch` / `.cpu` directives or
  ARM register names) is on the books for 1.11.0.
- **Grammar record:** unchanged at 152 bytes since 1.2.1.
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

## Next up — finish the 1.2.x line

- **1.2.4 — closeout / P(-1) hardening.** The last cut in 1.2.x.
  Per CLAUDE.md §Closeout pass:
  - Full test suite passes (439+/439+).
  - Full smoke script — every language corpus round-trips.
  - Dead-code audit (`cyrius build` "dead:" output).
  - Stale-comment sweep — old version refs, outdated TODO(M?)
    markers, ADR pointers to moved files.
  - Doc sync — CHANGELOG `[Unreleased]` collapses cleanly,
    state.md matches reality, roadmap is current.
  - Clean build — `rm -rf build && cyrius deps && cyrius build`
    from scratch.
  - Downstream check — owl still builds against the new tag.

After 1.2.4, the 1.x line continues per the
[restructured roadmap](./roadmap.md): 1.3.0 is JVM + C-family
languages.

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
(1.2.3 cut + `asm_aarch64` + roadmap restructure). Next refresh:
when 1.2.4 (closeout) ships.*
