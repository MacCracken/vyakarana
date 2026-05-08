# vyakarana — current state

> **Last refresh:** 2026-05-08 | **Refresh cadence:** every release
> (1.x cuts), plus any session that shifts the gates' colour or
> the active task.
>
> **Read this file before doing anything.** 1.0.0–1.2.4 are
> shipped. As of 2026-05-08 the toolchain pin is `cyrius = "5.9.36"`.
> 1.2.x history: 1.2.0 added Go and Zig; 1.2.1 shipped
> `[defaults] char_literal` (ADR 0010); 1.2.2 shipped
> `asm_x86_64` (Intel syntax); 1.2.3 shipped `asm_aarch64`
> (with ARM-specific tuning); **1.2.4 closes out the line** —
> dead-code cleanup, stale-comment sweep, fresh security audit
> ([docs/audit/2026-05-08-1.2.x-closeout-audit.md](../audit/2026-05-08-1.2.x-closeout-audit.md):
> 0 CRITICAL/HIGH/MEDIUM, 0 new LOWs). All three gates green
> at 1.2.4. Next: 1.3.0 — JVM + C-family languages — see §Next
> up.
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

- **Version:** `1.2.4` in `VERSION`, `src/version_str.cyr`, and
  `dist/vyakarana.cyr`. Tagged predecessors:
  `1.0.0` / `1.0.1` (ANSI-escape sanitizer) /
  `1.0.2` (distlib bundle) / `1.0.3` (cyrius 5.9.36 pin) /
  `1.1.0` (Rust `$`-macros, TOML triple-quoted, `unicode_ident`
  + C block comments) / `1.2.0` (Go + Zig) /
  `1.2.1` (`char_literal` flag — ADR 0010) /
  `1.2.2` (`asm_x86_64`) / `1.2.3` (`asm_aarch64` + roadmap
  restructure).
- **What 1.2.4 added (closeout, no behavioural change):**
  - **Dead-code removal.** Four vyakarana-owned functions the
    compiler had been flagging as dead — `registry_get`,
    `registry_count`, `grammar_count`, `_g_cstr_copy` — removed.
    None had callers; none were documented public API.
    `kind_is_valid` retained (exported via `[lib] modules`,
    exercised by 5 test assertions; comment updated to explain
    why the binary build flags it dead).
  - **Stale comment sweep.** Six source-comment references to
    pre-shipped milestones rewritten to point at current reality
    (architecture/overview, roadmap pointers, etc.).
  - **Security audit refresh.** First full audit pass since the
    2026-04-23 baseline. Filed at
    [`../audit/2026-05-08-1.2.x-closeout-audit.md`](../audit/2026-05-08-1.2.x-closeout-audit.md).
    Reviews every scanner change since 2026-04-23
    (`unicode_ident`, `char_literal`, the four new grammar
    files, the 1.2.4 cleanup). 0 CRITICAL / 0 HIGH / 0 MEDIUM /
    0 new LOW. The 2026-04-23 baseline findings carry forward
    unchanged.
- **Toolchain pin:** `cyrius = "5.9.36"` in `cyrius.cyml`
  (unchanged since 1.0.3).
- **Test count:** 439/439 (unchanged across 1.2.4 — closeout
  doesn't add tests).
- **Grammars:** 15 bundled (shell, toml, json, cyrius, rust,
  yaml, markdown, c, typescript, javascript, python, go, zig,
  asm_x86_64, asm_aarch64).
- **Build state: GREEN on cyrius 5.9.36, full clean rebuild.**
  `rm -rf build lib && cyrius deps && cyrius build` clean;
  `cyrius test tests/vyakarana.tcyr` 439/439;
  `sh scripts/smoke.sh build/vyk` reports M0+M1+M2+M3 passing
  at v1.2.4. `dist/vyakarana.cyr` regenerated.
- **Consumer pressure:** unchanged. owl pins `1.2.0`; can bump
  to 1.2.4 to pick up four new grammars + char_literal + the
  audit. Public `tokenize_source` / `tokenbuf` API is
  unchanged across 1.0.0 → 1.2.4. Grammar record stayed at
  152 bytes since 1.2.1.
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

## Next up — 1.3.0 (JVM + C-family)

The 1.2.x line is closed. Per the
[restructured roadmap](./roadmap.md), the next minor cut is
**1.3.0 — JVM + C-family languages**: `java`, `kotlin`, `cpp`,
`csharp`. All four benefit from the 1.1.0 scanner-extension
trio (unicode_ident + block comments + `$` in ident_start) and
1.2.1's char_literal flag. `cpp` is the most likely to surface
new scanner needs (templates, `::`, `<>` generics, namespace
syntax) — track what shapes appear in vidya's `cpp.cpp`
samples first; if a real shape forces an additive default, it
rolls into 1.3.0 with its own ADR.

After 1.3.0, the language line continues 1.4.0–1.9.0 per the
roadmap, then the pre-2.0 prep waves (1.10–1.13). 2.0.0 is
the streaming-tokenizer break and the only release scheduled
in the 2.x line under the current versioning rule.

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
1.2.x audit). Next refresh: when 1.3.0 (JVM + C-family) ships.*
