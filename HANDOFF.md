# vyakarana — Agent handoff

> **Read this file before doing anything.** Landing pad from M3
> (all 11 bundled grammars shipped) into the first hardening pass
> + security audit + 1.0.0 cut. Design context lives in
> [vyakarana-design-spec.md](./vyakarana-design-spec.md); milestone
> detail lives in [docs/development/roadmap.md](./docs/development/roadmap.md); architecture decisions
> live as ADRs under [docs/adrs/](./docs/adrs/).

---

## Where we are

- **Version:** 0.1.0 in `VERSION` (M1 + M2 + M3 additions all under
  `[Unreleased]` in CHANGELOG; user cuts tags).
- **Status:** M0 + M1 + M2 + M3 complete (2026-04-23). All 11
  bundled grammars ship: `shell`, `toml`, `json`, `cyrius`, `rust`,
  `yaml`, `markdown`, `c`, `typescript`, `javascript`, `python`.
  Each tokenizes its corpus (vidya sample or ADR-0006 stand-in)
  with zero `error` kinds and a satisfied coverage invariant.
- **Consumer pressure:** owl's M3b unblocked at M1 and stayed
  unblocked through M2/M3 (the public `tokenize_source` signature
  and `tokenbuf` accessors haven't changed).
- **Release path:** per the user's 1.0.0 plan (saved in memory and
  `docs/adrs/` continues to accept new entries), the next phase is
  a single consolidation:
  1. **Hardening step** (per CLAUDE.md §Hardening step)
  2. **Security audit** — byte-level input-handling review; file
     findings in `docs/audit/YYYY-MM-DD-audit.md`
  3. **Closeout pass** (per CLAUDE.md §Closeout pass)
  4. User cuts `1.0.0`. `VERSION` / `cyrius.cyml` / git tag move
     together.

Gates are green: `cyrius build`, `cyrius lint src/*.cyr`,
`cyrius test` (399 assertions), and `sh scripts/smoke.sh` (11
corpora round-trip cleanly) all pass. Re-run them on session entry
before trusting this line.

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
`docs/adrs/` explaining the forcing function, and don't break the
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

All architectural choices are ADRs under [docs/adrs/](./docs/adrs/);
read them before overriding any:

- [ADR 0001 — Corpus sync: checked-in snapshot](./docs/adrs/0001-corpus-sync-policy.md).
- [ADR 0002 — Token storage: contiguous 12-byte `tokenbuf`](./docs/adrs/0002-token-storage-layout.md).
- [ADR 0003 — Shell string expansions are flat in M1](./docs/adrs/0003-string-expansion-not-retokenized.md).
- [ADR 0004 — Shell built-ins emit as `ident`, not `keyword`](./docs/adrs/0004-shell-builtins-as-ident.md).
- [ADR 0005 — M2 rule-type scope: narrow rules + configured scanner](./docs/adrs/0005-m2-rule-type-scope.md).
- [ADR 0006 — Stand-in corpus when vidya doesn't cover a language](./docs/adrs/0006-standin-corpus-policy.md).

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
  §5, [ADR 0005](./docs/adrs/0005-m2-rule-type-scope.md)). If a
  language needs lookahead, propose a new rule type in a new ADR —
  don't reach for regex.
- **Zero-copy invariant.** Tokens reference into the caller's buffer
  as `(kind, start, len)`. `tokenbuf` is the only allocation and
  grows by doubling, not per-token (see
  [ADR 0002](./docs/adrs/0002-token-storage-layout.md)).
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
  [ADR 0005](./docs/adrs/0005-m2-rule-type-scope.md).
- `src/grammars/shell.cyr` — hand-coded M1 tokenizer, retained as
  a regression oracle. Wired into `vyk --handcoded` and the smoke
  diff check. Candidate for removal during hardening if kept green
  through M3 provides enough confidence.
- `src/tokenize.cyr` — dispatch. `tokenize_source(src, lang)` loads
  bundled grammars lazily, looks up `lang` in the registry, calls
  the default scanner. `bootstrap_grammars()` is the explicit-load
  hook for callers that bypass `tokenize_source`.
- `src/token.cyr` — palette, `Token` layout, `tokenbuf` (see
  [ADR 0002](./docs/adrs/0002-token-storage-layout.md)). Accessors
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

## Next up — hardening + 1.0.0

Per the user's 1.0.0 plan (see §Where we are):

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
- **cyrius** (`/home/macro/Repos/cyrius`) — toolchain. Currently
  v5.6.x (see `/home/macro/Repos/cyrius/VERSION`). If you find a
  compiler bug, file it upstream; don't work around it in vyakarana.

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
  write a note (or an ADR under `docs/adrs/` if the decision is
  load-bearing), and defer.

---

*Handoff first written 2026-04-23 (M0 shipped). Updated through
M1, M2, and M3 the same day. Refreshed at the start of the
hardening / 1.0.0 pass. Update this file after the hardening +
security audit ship and again when 1.0.0 is tagged.*
