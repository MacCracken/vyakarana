# vyakarana — Agent handoff

> **Read this file before doing anything.** Landing pad from M2
> (CYML loader + data-driven scanner) to M3 (ten-grammar starter
> set). Design context lives in
> [vyakarana-design-spec.md](./vyakarana-design-spec.md); milestone
> detail lives in [ROADMAP.md](./ROADMAP.md); architecture decisions
> live as ADRs under [docs/adrs/](./docs/adrs/).

---

## Where we are

- **Version:** 0.1.0 in `VERSION` (M1 + M2 additions are under
  `[Unreleased]` in CHANGELOG; user cuts tags).
- **Status:** M0 + M1 + M2 complete (2026-04-23). Shell grammar
  is data (`grammars/shell.cyml`), loaded by a CYML parser at
  runtime, and tokenized by the data-driven default scanner. Output
  is byte-identical to the hand-coded M1 tokenizer on the vidya
  sample — enforced by a diff check in `scripts/smoke.sh`.
- **Consumer pressure:** owl's M3b unblocked at M1 and stays
  unblocked through M2 (the public `tokenize_source` signature and
  `tokenbuf` accessors didn't change).

Gates are green: `cyrius build`, `cyrius test` (267 assertions),
and `sh scripts/smoke.sh` (M0 + M1 + M2 sections) all pass. Re-run
them on session entry before trusting this line.

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

## What shipped (M1 + M2)

**M1 goal (met):** shell files tokenize end-to-end via a hand-coded
recognizer. Proved the runtime shape + the Token / tokenbuf contract.

**M2 goal (met):** grammars are data. `grammars/shell.cyml` +
CYML loader + configured default scanner produce byte-identical
tokens to the M1 hand-coded path, enforced by
`scripts/smoke.sh`'s diff check. Adding a new language is now a
new `.cyml` file plus whatever `[defaults]` / `[[rules]]` fields
its grammar needs.

### Decisions recorded during M1/M2

All architectural choices are ADRs under [docs/adrs/](./docs/adrs/);
read them before overriding any:

- [ADR 0001 — Corpus sync: checked-in snapshot](./docs/adrs/0001-corpus-sync-policy.md).
  Revisit at M3.
- [ADR 0002 — Token storage: contiguous 12-byte `tokenbuf`](./docs/adrs/0002-token-storage-layout.md).
  Revisit at M5.
- [ADR 0003 — Shell string expansions are flat in M1](./docs/adrs/0003-string-expansion-not-retokenized.md).
  Revisit at M2 or M3.
- [ADR 0004 — Shell built-ins emit as `ident`, not `keyword`](./docs/adrs/0004-shell-builtins-as-ident.md).
  Revisit at M4.
- [ADR 0005 — M2 rule-type scope: narrow rules + configured scanner](./docs/adrs/0005-m2-rule-type-scope.md).
  Revisit when a language needs a rule type beyond the current set.

### Invariants that survived M1/M2 and carry into M3+

These constraints shaped M1 and M2 and continue to hold; M3 agents
should honor them by default.

- **No regex rules.** Explicitly out of the M2 rule set (design-spec
  §5, [ADR 0005](./docs/adrs/0005-m2-rule-type-scope.md)). If a
  language construct seems to need lookahead, propose a new rule
  type (`chars`, `exact`, `indent`, …) in a new ADR — don't reach
  for regex.
- **Zero-copy invariant.** Tokens reference into the caller's buffer
  as `(kind, start, len)`. `tokenbuf` is the only allocation and
  grows by doubling, not per-token (see
  [ADR 0002](./docs/adrs/0002-token-storage-layout.md)).
- **Data-driven by default.** New grammars are new `.cyml` files.
  If a grammar needs behavior the default scanner doesn't support,
  extend the scanner (and record via an ADR); don't add per-language
  Cyrius paths.
- **Regression oracle retained until M3.** `src/grammars/shell.cyr`
  (hand-coded) is on disk so smoke.sh's diff check works. Delete it
  after M3 makes a second grammar pass the same bar.

---

## Where the code lives

Pointers for M3 and later agents:

- `grammars/shell.cyml` — shell grammar as data. Template for new
  grammars: `[grammar]` header, `[defaults]` table for built-in
  scanner stages, `[[rules]]` entries for line / pair / words.
- `src/grammar.cyr` — `Grammar` record, rule sub-records, char-class
  tables, CYML parser (minimal TOML dialect), and the in-memory
  registry.
- `src/grammars/default_scanner.cyr` — `tokenize_with_grammar(g,
  src, src_len, tb)`. The data-driven scanner that every grammar
  runs through. Scanner priority is documented inline and in
  [ADR 0005](./docs/adrs/0005-m2-rule-type-scope.md).
- `src/grammars/shell.cyr` — hand-coded M1 tokenizer, retained as
  a regression oracle. Wired into `vyk --handcoded` and the smoke
  diff check. Delete in a post-M3 cleanup.
- `src/tokenize.cyr` — dispatch. `tokenize_source(src, lang)` loads
  bundled grammars lazily, looks up `lang` in the registry, calls
  the default scanner. `bootstrap_grammars()` is the explicit-load
  hook for callers that bypass `tokenize_source`.
- `src/token.cyr` — palette, `Token` layout, `tokenbuf` (see
  [ADR 0002](./docs/adrs/0002-token-storage-layout.md)). Accessors
  `tokenbuf_count/kind/start/len` are the consumer contract.
- `src/main.cyr` — `vyk` CLI. `emit_ndjson`, `tokenize_file`, and
  the hidden `--handcoded` flag used by the regression diff.
- `tests/corpus/shell.sh` — snapshot of the vidya sample.
  ([ADR 0001](./docs/adrs/0001-corpus-sync-policy.md)).
- `tests/vyakarana.tcyr` — 267 assertions covering palette,
  tokenbuf, M1 hand-coded known offsets, M2 grammar loader +
  char-class + cross-tokenizer equality.
- `scripts/smoke.sh` — M0 flags + M1 corpus round-trip + M2
  hand-vs-data-driven byte-identical diff.

---

## Next up — M3

- **M3** — nine more grammars: python, javascript, typescript,
  rust, c, cyrius, toml, json, yaml, markdown. Each gets a
  `grammars/<lang>.cyml` file and a corpus file snapshotted from
  `vidya/content/lexing_and_parsing/<lang>.*`. Pass bar (per
  ROADMAP): zero `error` tokens + coverage invariant + hand-audit
  on ~30 tokens per grammar.

### M3 entry checklist

- [ ] Pick a first language and write its `.cyml`.
- [ ] Snapshot the vidya sample into `tests/corpus/<lang>.*`.
- [ ] Wire the grammar name into `bootstrap_grammars()` in
  `src/tokenize.cyr` (a ~3-line change per grammar — or better,
  replace the hardcoded list with a directory scan of `grammars/`).
- [ ] Extend `detect_language()` in `src/main.cyr` for the new
  extensions.
- [ ] Run vyk on the corpus, audit tokens, add tests.
- [ ] Extend smoke.sh M1 block to run each corpus file.
- [ ] When a grammar hits a shape the default scanner can't
  express, stop and open an ADR before piling Cyrius around it.
- [ ] After the second grammar passes green, consider deleting
  `src/grammars/shell.cyr` (the M1 oracle) — we'll have enough
  data-driven coverage that the hand-coded reference is more
  confusing than useful.
- **M3** — Nine more grammars (python, js, ts, rust, c, cyrius, toml,
  json, yaml, markdown). Each gets a vidya sample as test corpus.
- **M4** — Theme-palette contract with owl. Coordinate with whoever
  owns owl's theme module; shared palette header file is the likely
  shape.
- **M5** — Streaming tokenizer (iterator API). Memory goes O(tokens
  in flight). This is owl's `huge.log` enabler.
- **M6** — vidya reverse consumption (rendering).
- **M7** — RC / v1.0 cut.

Each milestone has its own ROADMAP section with concrete "done when"
criteria. Read it before starting the milestone.

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

- **Do not commit or push.** The user handles all git operations.
- Use `cyrius build`, never raw `cc5`.
- Study `cyrius/programs/*.cyr` and `cyrius-doom/` for working Cyrius
  examples before writing new code.
- Read `vidya/content/cyrius/field_notes.toml` before writing non-trivial
  Cyrius.
- Test after every change. One change at a time.
- If you hit three failed attempts at the same problem, stop, write
  a note (or an ADR under `docs/adrs/` if the decision is
  load-bearing), and defer.

---

*Handoff first written 2026-04-23 (M0 shipped). Updated 2026-04-23
after M1 landed. Updated again 2026-04-23 after M2 landed.
Update this file when M3 completes.*
