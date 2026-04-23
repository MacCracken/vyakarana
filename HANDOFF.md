# vyakarana — Agent handoff

> **Read this file before doing anything.** Landing pad from M1
> (hand-coded shell) to M2 (CYML grammar loader). Design context
> lives in [vyakarana-design-spec.md](./vyakarana-design-spec.md);
> milestone detail lives in [ROADMAP.md](./ROADMAP.md); architecture
> decisions live as ADRs under [docs/adrs/](./docs/adrs/).

---

## Where we are

- **Version:** 0.1.0 in `VERSION` (the M1 additions are under
  `[Unreleased]` in CHANGELOG; user cuts tags)
- **Status:** M0 + M1 complete (2026-04-23). Shell grammar is
  hand-coded and round-trips the vidya sample with zero `error`
  kinds. `vyk <file.sh>` prints NDJSON tokens.
- **Consumer pressure:** owl's M3b (token highlighting) can now add
  `[deps.vyakarana]` and import `tokenize_source(src, "shell")`.
  Other consumers (cyim, vidya, agnoshi) pick up in their own
  timelines.

Gates are green against the M1 implementation: `cyrius build`,
`cyrius test` (89 assertions), and `sh scripts/smoke.sh` all pass.
Re-run them on session entry before trusting this line.

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

## M1 — what shipped

**Goal (met):** shell files tokenize end-to-end, proving the runtime.

### Concrete checklist

- [x] Hand-coded shell tokenizer in `src/grammars/shell.cyr`.
- [x] Wired `tokenize_source(src, "shell")` in `src/tokenize.cyr`.
- [x] `vyk <shell-file>` prints NDJSON tokens, one per line.
- [x] Coverage invariant holds (smoke-script check + test assertion).
- [x] `tests/corpus/shell.sh` (snapshot from vidya) tokenizes with
      zero `error` kinds.
- [x] Hand-audit: 14 distinct keywords detected; shebang is
      `preprocessor`; `[[` / `]]` / `((` / `))` / `;;` are 2-char
      `punctuation`; strings respect backslash escapes in `"..."`
      but not in `'...'`; `$#` does not start a comment.
- [x] 58 new M1 test assertions in `tests/vyakarana.tcyr`
      (known-offset + coverage-invariant + no-error-tokens).
- [x] `scripts/smoke.sh` has an M1 section that runs `vyk` on the
      corpus and enforces exit 0 + zero error tokens + coverage sum.

### Decisions made during M1

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

### Invariants that survived M1 and carry into M2+

These constraints shaped M1 and continue to hold; M2 agents should
honor them by default.

- **No CYML grammar loader in M1.** Hand-coded Cyrius first so we
  could iterate on recognizer shape without also designing the
  serialization format. M2 re-expresses the shell grammar as data.
- **One grammar only.** Python / Rust / etc. land in M3 after M2
  proves the loader.
- **No regex rules.** Explicitly out of the M2 rule set (design-spec
  §5). If a shell construct seems to need lookahead, write a
  dedicated rule helper — don't reach for regex.
- **Zero-copy invariant.** Tokens reference into the caller's buffer
  as `(kind, start, len)`. `tokenbuf` is the only allocation and
  grows by doubling, not per-token (see
  [ADR 0002](./docs/adrs/0002-token-storage-layout.md)).

---

## Where M1 landed

Pointers for M2 and later agents:

- `src/grammars/shell.cyr` — hand-coded shell tokenizer. Entry:
  `tokenize_shell(src, src_len, tb)`. Scanner helpers (`_scan_*`)
  are module-local.
- `src/tokenize.cyr` — dispatch. `tokenize_source(src, lang)` returns
  a `tokenbuf` handle, or `0` when `lang` isn't loaded.
- `src/token.cyr` — palette, `Token` layout notes, and `tokenbuf`
  (contiguous 12-byte records; see
  [ADR 0002](./docs/adrs/0002-token-storage-layout.md)). Accessors:
  `tokenbuf_count/kind/start/len` are the consumer contract.
- `src/main.cyr` — `vyk` CLI. NDJSON emitter in `emit_ndjson`;
  file read + tokenize in `tokenize_file`.
- `tests/corpus/shell.sh` — snapshot of the vidya sample. Re-sync
  manually when vidya updates (see
  [ADR 0001](./docs/adrs/0001-corpus-sync-policy.md)).
- `tests/vyakarana.tcyr` — 89 assertions total, with an M1 section
  covering known-offset, coverage-invariant, and no-error-tokens.
- `scripts/smoke.sh` — M0 flags + an M1 section that round-trips the
  corpus and enforces the coverage invariant.

---

## Next up — M2

- **M2** — CYML grammar loader. Re-express shell as data; ship the
  format that all future grammars use. See design-spec §5 for the
  rule-type set. The hand-coded `tokenize_shell` stays on disk as a
  regression reference until the CYML-driven version produces
  byte-identical output.
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

*Handoff first written 2026-04-23 (M0 shipped). Rewritten 2026-04-23
after M1 landed. Update this file when M2 completes.*
