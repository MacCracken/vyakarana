# vyakarana — Agent handoff

> **Read this file before doing anything.** As of 2026-05-07 the
> 1.0.0 cut is **blocked by an upstream cyrius regression** — see
> §Current status. Design context lives in
> [vyakarana-design-spec.md](./vyakarana-design-spec.md); milestone
> detail lives in [docs/development/roadmap.md](./docs/development/roadmap.md); architecture decisions
> live as ADRs under [docs/adr/](./docs/adr/).

---

## Current status (2026-05-07)

- **Version:** `1.0.2` in `VERSION` (last patched 2026-04-23 against
  cyrius `5.6.0`).
- **Toolchain pin:** `cyrius = "5.9.32"` in `cyrius.cyml` —
  bumped 2026-05-07 from `5.6.0`. **Uncommitted** (per CLAUDE.md
  the user handles git).
- **Build state: RED on cyrius 5.9.32.**
  `cyrius build src/main.cyr build/vyk` fails at
  `src/tokenize.cyr:16` with `expected '=', got string`. The
  failure is in the cyrius compiler's `include` directive
  handling, **not** in vyakarana's sources — each constituent
  file passes `cyrius check` on its own. Issue filed at
  [`docs/development/issues/2026-05-07-cyrius-include-graph-regression.md`](./docs/development/issues/2026-05-07-cyrius-include-graph-regression.md);
  reproduction at `/tmp/cyrius-nested-include-broken/`
  (README + bisect.sh + ruled-out minimal repros).
- **Gates not validated against 5.9.32** — `cyrius test` and
  `scripts/smoke.sh` cannot run because there is no `build/vyk`
  to test. Last green gate run was 2026-04-23 against cyrius
  5.6.0 (399 test assertions, 11 corpora round-trip clean).
- **Consumer pressure:** unchanged — owl's M3b stays unblocked;
  the public `tokenize_source` signature and `tokenbuf`
  accessors are not affected by the upstream regression.
- **Release path on hold:** the 1.0.0 cut (Hardening → Security
  audit → Closeout → tag) cannot proceed until either (a) the
  upstream cyrius `include` regression is fixed and the build
  goes green again, or (b) vyakarana flattens its include graph
  as a workaround (see §Workaround options below).

## What the language agent is here to do (2026-05-07 session)

The user is starting a **cyrius language agent** to investigate
the upstream regression. **Do not modify vyakarana sources** in
this session — the bug is upstream and vyakarana's role is
reporter, not patcher. The reproduction and bisect data are
self-contained:

- [`docs/development/issues/2026-05-07-cyrius-include-graph-regression.md`](./docs/development/issues/2026-05-07-cyrius-include-graph-regression.md)
  — full diagnostic, status timeline, what's needed upstream
- `/tmp/cyrius-nested-include-broken/README.md` — full
  repro write-up with three ruled-out hypotheses
- `/tmp/cyrius-nested-include-broken/bisect.sh` — runs the seven
  probes from inside the vyakarana repo root

Quickest path for the agent:

```sh
cyriusly use 5.9.32       # already active on this machine
cd /home/macro/Repos/vyakarana
cyrius build src/main.cyr build/vyk      # → reproduces the failure
/tmp/cyrius-nested-include-broken/bisect.sh   # narrows to grammar+shell
```

`cyriusly list` has every patch from 5.7.35 → 5.9.33 installed
locally; `cyriusly use <ver>` + a re-run of `bisect.sh` will
bracket the regression window in a few minutes.

## Workaround options (consumer-side, deferred)

If upstream fix slips, vyakarana can flatten its include graph
— have `src/main.cyr` include `token.cyr`, `grammar.cyr`,
`shell.cyr`, `default_scanner.cyr`, `tokenize.cyr` directly in
dependency order, and remove the `include "src/..."` lines from
the non-entry files. This matches the `cyrius/programs/*.cyr`
single-file pattern and avoids the failing graph shape, but
loses the property that each module declares its own deps
explicitly (the convention sandhi / agnosys / yukti also use).
**Not yet applied.** Preferred order is upstream fix; the
workaround is escape hatch only.

---

## What is frozen (do not break)

1. **Ten token kinds in `src/token.cyr`.** The palette is a stable
   contract. Adding a new kind requires a design review and a
   CHANGELOG entry. Assume it's not your call in M1–M6.
2. **Token layout.** `(kind: u8, start: u32, len: u32)` — 12 bytes,
   no pointers. If you discover M1 needs more fields, add a
   CHANGELOG `### Changed` note and bump 0.1.0 → 0.2.0.
3. **Entry-point signature.** `tokenize_source(src, lang)` is what
   owl imports. The return type can evolve (Vec now, iterator in M5),
   but the name and arg order do not change.
4. **`vyk` CLI surface.** `--version`, `--help`, `--list-kinds`,
   `--list-languages` are covered by the smoke test. Additions are
   fine; renames/removals are breaking.

If you think you need to break any of these, **open an ADR in
`docs/adr/` explaining the forcing function, and don't break the
contract until the user ACKs.**

---

## What shipped (M1 + M2 + M3)

**M1 (met):** shell files tokenize end-to-end via a hand-coded
recognizer. Proved the runtime shape + the Token / tokenbuf contract.

**M2 (met):** grammars are data. `grammars/shell.cyml` + CYML
loader + configured default scanner produce byte-identical tokens
to the M1 hand-coded path, enforced by `scripts/smoke.sh`'s diff
check. Adding a new language became a new `.cyml` file plus
whatever `[defaults]` / `[[rules]]` fields its grammar needs.

**M3 (met):** all 11 bundled grammars land. Per-grammar details:

| Grammar     | Corpus                              | Tokens | Notes |
|-------------|-------------------------------------|-------:|-------|
| shell       | vidya `shell.sh` (8524B)            | 1560 | M1 hand-coded, M2 data-driven. |
| toml        | vidya `concept.toml` (10341B)       |  471 | |
| json        | stand-in `concept.json` (3380B)     |  376 | ADR 0006. |
| cyrius      | vidya `cyrius.cyr` (9233B)          | 2508 | |
| rust        | vidya `rust.rs` (9473B)             | 2219 | char-lit split (cosmetic). |
| yaml        | stand-in `concept.yaml` (1863B)     |  354 | ADR 0006. |
| markdown    | stand-in `concept.md` (1733B)       |  472 | ADR 0006; em-dash swap. |
| c           | vidya `c.c` (9429B)                 | 2451 | char-lit split (cosmetic). |
| typescript  | vidya `typescript.ts` (8473B)       | 2009 | template literals captured. |
| javascript  | stand-in `concept.js` (4827B)       | 1275 | ADR 0006; TS-subset. |
| python      | vidya `python.py` (8528B)           | 1790 | triple-quoted + walrus. |

### Decisions recorded during M1 / M2 / M3

All architectural choices are ADRs under [docs/adr/](./docs/adr/);
read them before overriding any:

- [ADR 0001 — Corpus sync: checked-in snapshot](./docs/adr/0001-corpus-sync-policy.md).
- [ADR 0002 — Token storage: contiguous 12-byte `tokenbuf`](./docs/adr/0002-token-storage-layout.md).
- [ADR 0003 — Shell string expansions are flat in M1](./docs/adr/0003-string-expansion-not-retokenized.md).
- [ADR 0004 — Shell built-ins emit as `ident`, not `keyword`](./docs/adr/0004-shell-builtins-as-ident.md).
- [ADR 0005 — M2 rule-type scope: narrow rules + configured scanner](./docs/adr/0005-m2-rule-type-scope.md).
- [ADR 0006 — Stand-in corpus when vidya doesn't cover a language](./docs/adr/0006-standin-corpus-policy.md).

### Hardening / audit (2026-04-23)

Full report: [docs/audit/2026-04-23-audit.md](./docs/audit/2026-04-23-audit.md).

- 5 LOW findings, 1 MEDIUM fixed in-pass (per-ident `alloc(8)`
  removed; ADR 0002 NFR restored).
- 0 HIGH, 0 CRITICAL.
- Known-CVE review: immune by design to ReDoS, unbounded
  recursion, deserialization-RCE, modeline-escape, and
  buffer-overflow-in-parser classes. Partial exposure (LOW,
  self-attack only) on ANSI-escape via echoed argv — FINDING-006,
  deferred post-1.0.
- Nothing blocks the 1.0.0 cut. FINDINGs 002–006 carry forward as
  post-1.0 defense-in-depth / follow-ups.

### Known cosmetic gaps (coverage holds; no `error` tokens)

Candidates for a scanner extension + ADR during the hardening pass
or post-1.0:

- **Char literals** (`'x'`, `'\0'`): Rust + C both split into
  op/body/op triples. Needs a `char_literal = true` default with
  2-3 char lookahead.
- **UTF-8 bytes outside strings**: Markdown stand-in swapped `—`
  for `--` to sidestep. Needs `unicode_ident = true` default
  treating bytes ≥ 0x80 as ident_cont.
- **F-string prefix**: `f"..."` → `ident(f) + string("...")` in
  Python. Same for r/b/rb/fr prefixes.
- **Block comments** (`/* ... */`): no language in the current set
  has forced it, but C/Rust/JS/TS real-world will.
- **Python INDENT/DEDENT**: structural tokens Python parsers want
  aren't emitted. Not needed for the tokenizer's correctness bar.

### Invariants that carry into hardening + 1.0.0

- **No regex rules.** Explicitly out of the rule set (design-spec
  §5, [ADR 0005](./docs/adr/0005-m2-rule-type-scope.md)). If a
  language needs lookahead, propose a new rule type in a new ADR —
  don't reach for regex.
- **Zero-copy invariant.** Tokens reference into the caller's buffer
  as `(kind, start, len)`. `tokenbuf` is the only allocation and
  grows by doubling, not per-token (see
  [ADR 0002](./docs/adr/0002-token-storage-layout.md)).
- **Data-driven by default.** New grammars are new `.cyml` files.
  If a grammar needs behavior the default scanner doesn't support,
  extend the scanner (and record via an ADR); don't add per-language
  Cyrius paths.
- **Regression oracle retained.** `src/grammars/shell.cyr`
  (hand-coded) is still on disk so smoke.sh's diff check works.
  Delete in the hardening/closeout pass if and only if all M3
  grammars have stayed green for long enough to trust the
  data-driven path without the oracle.

---

## Where the code lives

- `grammars/*.cyml` — 11 grammar files. Each is a `[grammar]`
  header, a `[defaults]` table for built-in scanner stages, and
  `[[rules]]` entries for line / pair / words. `grammars/shell.cyml`
  is the canonical template.
- `src/grammar.cyr` — `Grammar` record, rule sub-records,
  char-class tables, CYML parser (minimal TOML dialect), and the
  in-memory registry.
- `src/grammars/default_scanner.cyr` — `tokenize_with_grammar(g,
  src, src_len, tb)`. The data-driven scanner that every grammar
  runs through. Scanner priority is documented inline and in
  [ADR 0005](./docs/adr/0005-m2-rule-type-scope.md).
- `src/grammars/shell.cyr` — hand-coded M1 tokenizer, retained as
  a regression oracle. Wired into `vyk --handcoded` and the smoke
  diff check. Candidate for removal during hardening if kept green
  through M3 provides enough confidence.
- `src/tokenize.cyr` — dispatch. `tokenize_source(src, lang)` loads
  bundled grammars lazily, looks up `lang` in the registry, calls
  the default scanner. `bootstrap_grammars()` is the explicit-load
  hook for callers that bypass `tokenize_source`.
- `src/token.cyr` — palette, `Token` layout, `tokenbuf` (see
  [ADR 0002](./docs/adr/0002-token-storage-layout.md)). Accessors
  `tokenbuf_count/kind/start/len` are the consumer contract.
- `src/main.cyr` — `vyk` CLI. `emit_ndjson`, `tokenize_file`, and
  the hidden `--handcoded` flag used by the regression diff.
- `tests/corpus/*` — 11 corpus files (vidya snapshots + ADR-0006
  stand-ins).
- `tests/vyakarana.tcyr` — 399 assertions covering palette,
  tokenbuf, hand-coded known offsets, grammar loader, char-class,
  cross-tokenizer equality, and per-grammar probes.
- `scripts/smoke.sh` — M0 flags + M1 shell round-trip + M2
  hand-vs-data-driven diff + M3 corpus round-trip loop (one line
  per `lang:corpus` pair).

---

## Next up — unblock the toolchain, then hardening + 1.0.0

Per the user's 1.0.0 plan, in order:

0. **Unblock the toolchain (current).** Either upstream cyrius
   fixes the `include` regression (preferred — see linked issue)
   or vyakarana flattens its include graph as a workaround. Until
   one of these lands, the rest of the path is on hold.
1. **Hardening step** — see CLAUDE.md §Hardening step. Cleanliness
   baseline, doc drift sweep, internal review, external research,
   tests / docs touchup, post-review gate run.
2. **Security audit** — byte-level input handling: every
   `load8`/`store8` on `src + i` where `i` depends on input,
   every `alloc(N)` where N derives from input, `file_read_all`
   caps. File findings in `docs/audit/YYYY-MM-DD-audit.md`.
3. **Closeout pass** — CLAUDE.md §Closeout pass. Full test + smoke
   + lint + clean build from scratch. `VERSION` / `cyrius.cyml` /
   git tag aligned.
4. **User cuts 1.0.0.**

Post-1.0 roadmap ([docs/development/roadmap.md](./docs/development/roadmap.md) has the detail):

- **M4** — Theme-palette contract with owl. Shared palette header
  is the likely shape.
- **M5** — Streaming tokenizer (iterator API). Memory goes
  O(tokens in flight); enables `owl huge.log`.
- **M6** — vidya reverse consumption (vidya starts rendering its
  `content/lexing_and_parsing/` samples through vyakarana).
- **M7** — Polish + release candidate.

---

## Cross-repo coordination

- **owl** (`/home/macro/Repos/owl`) — its M3b was blocked on M1 and
  can now add `[deps.vyakarana]` at the tag the user cuts. Do **not**
  sidestep with a path hack — see `feedback_real_deps_only.md` in
  the genesis memory.
- **vidya** (`/home/macro/Repos/vidya`) — read before making corpus
  decisions. M6 will bring vidya on as a consumer; don't pre-negotiate
  that now.
- **cyrius** (`/home/macro/Repos/cyrius`) — toolchain. Pinned at
  `5.9.32`; system `VERSION` shows `5.9.33` (in-flight bump,
  uncommitted). The active include-graph regression filed against
  5.9.32 is in
  [`docs/development/issues/2026-05-07-cyrius-include-graph-regression.md`](./docs/development/issues/2026-05-07-cyrius-include-graph-regression.md).
  If you find another compiler bug, file it upstream; don't work
  around it in vyakarana.

---

## Process reminders

Full process lives in [CLAUDE.md](./CLAUDE.md). In short:

- **Do not commit or push.** The user handles all git operations.
- Use `cyrius build`, never raw `cc3`/`cc5`.
- Study `cyrius/programs/*.cyr`, `yukti/`, and `cyrius-doom/` for
  working Cyrius examples before writing new code.
- Read `vidya/content/cyrius/field_notes.toml` before writing
  non-trivial Cyrius.
- Test after every change. One change at a time.
- If you hit three failed attempts at the same problem, stop,
  write a note (or an ADR under `docs/adr/` if the decision is
  load-bearing), and defer.

---

*Handoff first written 2026-04-23 (M0 shipped). Updated through
M1, M2, and M3 the same day. Refreshed at the start of the
hardening / 1.0.0 pass. Refreshed 2026-05-07: VERSION corrected
to 1.0.2, cyrius pin bumped to 5.9.32, build flagged red pending
the upstream `include`-graph regression. Update this file when
the regression resolves, after the hardening + security audit
ship, and again when 1.0.0 is tagged.*
