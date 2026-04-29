# ADR 0002 — Token storage: contiguous 12-byte records via `tokenbuf`

- **Status:** Accepted
- **Date:** 2026-04-23
- **Deciders:** M1 agent (proposed) / user (accepted)
- **Relates to:** [vyakarana-design-spec.md](../../vyakarana-design-spec.md)
  §4 (Span Type), §6 (Streaming Tokenizer)

## Context

Design-spec §4 locks the `Token` layout as
`(kind:u8, start:u32, len:u32)` — 12 bytes, cache-friendly, no
pointers. Design-spec §6 adds a non-functional requirement: "no
allocations per token."

M1 needed a concrete storage shape for the result of
`tokenize_source(src, lang)`. The stdlib `Vec` stores 8-byte slots
(`i64`) and grows by doubling its element buffer — it does not
natively hold 12-byte records.

Alternatives considered:

1. **Per-token `alloc(12)` + stdlib `Vec<ptr>`.** A Vec of Token
   pointers; each Token is a separate heap allocation. Natural-fit
   for stdlib primitives.
2. **Bit-packed `i64` per token** (`kind:8 | start:28 | len:28`).
   One slot per token in the stdlib Vec; `tokenize_source` returns
   a `Vec` directly.
3. **Two `i64` slots per token in the stdlib Vec.** Wasteful (16
   bytes instead of 12) but keeps the stdlib vec API.
4. **Purpose-built `tokenbuf`** — a contiguous byte buffer of 12-byte
   records with its own growth policy. New data structure.

## Decision

Adopt **option 4 — `tokenbuf`**. Implemented in `src/token.cyr`:

```
# Handle layout: (data_ptr: i64, count: i64, byte_cap: i64) — 24 bytes
# Record layout: (kind: u8 @ 0, start: u32 @ 4, len: u32 @ 8) — 12 bytes
fn tokenbuf_new()                 # allocate with initial cap
fn tokenbuf_push(tb, k, s, l)     # append; doubles cap when full
fn tokenbuf_count(tb)             # number of records
fn tokenbuf_kind(tb, i)           # u8 accessor
fn tokenbuf_start(tb, i)          # u32 accessor
fn tokenbuf_len(tb, i)            # u32 accessor
```

`tokenize_source(src, "shell")` returns a `tokenbuf` handle (opaque
pointer); callers read tokens via the accessors. Handle is `0` when
no grammar matches.

## Consequences

### Positive

- **Matches the design-spec layout exactly.** 12 bytes per record,
  flat buffer, no pointer fields inside a Token. The consumer-facing
  shape is the same shape the design spec advertises.
- **Honors §6's "no allocations per token" NFR.** Growth is
  amortized O(1) by buffer doubling; individual `tokenbuf_push`
  calls allocate zero times in the hot path.
- **Cache-friendly.** A tokenbuf of N tokens is N×12 contiguous
  bytes — sequential scans hit the prefetcher cleanly.
- **Stable consumer surface.** owl M3b and later consumers import
  the accessors; `tokenbuf`'s internal layout can evolve without
  breaking them.

### Negative

- **Custom data structure.** We own the growth, the bounds-checking,
  and any future features (clear / reset / iterator shape). Stdlib
  improvements to `Vec` don't flow to `tokenbuf` automatically.
- **Non-uniform with the rest of the codebase.** Other places use
  stdlib `Vec`; `tokenbuf` is bespoke. New contributors have one
  more thing to learn.

### Why not the alternatives

- **(1) per-token alloc** violates §6 explicitly and adds a pointer
  chase per access. Rejected.
- **(2) bit-packed i64** loses the `u32` range from the locked
  layout (at best 28 bits for `start`, capping source files at
  256 MB, and even less for `len`). The design-spec §4 layout is
  part of the consumer contract; silently narrowing it is a breaking
  change in disguise.
- **(3) two i64 slots** wastes 33% of memory relative to the spec
  and still requires a custom accessor layer to hide the (slot0,
  slot1) split from callers. Weaker version of `tokenbuf` with no
  upside.

### When to revisit

**M5** (streaming tokenizer). The iterator API may want a different
internal shape — e.g. producing tokens incrementally without ever
materializing a full buffer. The `tokenbuf` accessor surface
(`count` / `kind` / `start` / `len` by index) should remain stable
for Vec-mode consumers even if a new streaming-mode API lands
alongside it.
