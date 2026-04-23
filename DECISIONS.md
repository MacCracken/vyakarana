# vyakarana — Decision log

Long-form notes on choices that don't fit in `CHANGELOG.md` or
`ROADMAP.md`. Append entries; don't rewrite history.

---

## 2026-04-23 — Corpus sync policy: checked-in snapshot (HANDOFF option 1)

**Decision.** Snapshot `vidya/content/lexing_and_parsing/shell.sh` into
`tests/corpus/shell.sh` as a checked-in copy. Re-sync manually when
vidya updates the sample.

**Alternatives considered** (from HANDOFF.md §Corpus):

1. **Checked-in snapshot** — chosen.
2. Git submodule — heavy infra for one file; ties CI to submodule init.
3. Build-time pull script — network-dependent CI.
4. Path reference `../vidya/...` — assumes a monorepo layout; breaks
   in standalone CI.

**Why option 1.** We're syncing one file for one grammar in M1. A
snapshot is trivially reviewable, diffable, and CI-portable. Infra
for keeping ten files in sync is a legitimate question, but belongs
at M3 (ten grammars), not M1 (one).

**When to revisit.** M3 — when the starter set lands and
`tests/corpus/` has ~10 files. At that point, evaluate option 3
(build-time pull) against the accumulated sync debt.

---

## 2026-04-23 — Token storage: contiguous 12-byte records via `tokenbuf`

**Decision.** Tokens are stored as contiguous 12-byte records
`(kind:u8 @ 0, start:u32 @ 4, len:u32 @ 8)` in a growable byte buffer
(`tokenbuf` — see `src/token.cyr`). `tokenize_source` returns a
`tokenbuf` handle, not a `Vec<i64>`.

**Alternatives considered.**

- Per-token `alloc(12)` + `Vec<ptr>` — violates design-spec §6's "no
  allocations per token" NFR.
- Bit-packed `i64` per token (kind:8 | start:28 | len:28) — loses
  `u32` range from the spec's locked layout, and obscures the field
  shape consumers will see in M4+.
- Two `i64` slots per token in stdlib `Vec` — 16 bytes per token,
  wasteful, and off-layout vs. the documented `Token`.

**Why `tokenbuf`.** Matches design-spec §4 exactly: 12 bytes,
cache-friendly, no pointers, no per-token alloc. The consumer
contract owl M3b imports is `(kind, start, len)` accessors over a
flat byte buffer — exactly what `tokenbuf` exposes. Stdlib `Vec` is
fixed at 8-byte slots, so we write our own thin buffer.

**When to revisit.** M5 (streaming). The iterator API may warrant a
different internal shape; the `tokenbuf` accessor surface should
remain stable for consumers.

---

*End of decisions (2026-04-23).*
