# 0021 — `Token.start` / `Token.len` stay u32; the 4 GiB stream ceiling is deliberate

- **Status:** Accepted
- **Date:** 2026-08-20
- **Deciders:** RM (2.4.0 cut)
- **Relates to:** [ADR 0002](0002-token-storage-layout.md) (the
  12-byte record this preserves),
  [ADR 0017](0017-streaming-api.md) (the API that made the limit
  reachable),
  [2026-08-20 audit](../audit/2026-08-20-2.3.x-hardening-audit.md)
  §P2-2, `src/token.cyr`, `src/tokenize.cyr`

## Context

ADR 0002 locked the token record at `(kind:u8, start:u32, len:u32)`
— 12 bytes, cache-friendly. `Token.start` is therefore capped at
2³²−1.

That cap was uncontroversial while the only entry point was
`tokenize_source(src, lang)`, bounded by `VYK_SRC_CAP` at 1 MiB.
The 2026-04-23 audit rated it **FINDING-005, LOW (theoretical)**,
reasoning "practical file sizes don't approach this."

**2.0.0 invalidated that reasoning and nobody noticed.** The
streaming API replaced the bounded entry point with one whose own
header advertises *"Total input can exceed this freely"*, and
`abs_offset` — the absolute offset of the live buffer in the
original stream — is an i64 that accumulates over every byte ever
fed. Past 2³² the `store32` in `tokenbuf_push` wraps silently:

```
pushed start = 4294967301 (2^32 + 5)  ->  reads back as 5
pushed len   = 4294967303 (2^32 + 7)  ->  reads back as 7
```

A consumer indexing `src[start .. start+len)` then reads unrelated
bytes, and the coverage invariant — the published correctness
contract — stops holding with no error anywhere. The finding went
un-rerated for four minor lines because a carryover ledger error
had reassigned its ID (see the audit's §Ledger defect).

2.3.4 shipped the patch-safe half: `VYK_OFFSET_CAP`, and
`tokenize_stream_feed` returns `VYK_ERR_OVERFLOW` rather than
emitting wrapped offsets. **Silent corruption became a loud
refusal.** What remained was the actual decision: widen the record,
or accept the ceiling and say so.

## Decision

**Keep `u32`. Keep the 12-byte record. Treat 4 GiB-per-stream as a
documented, enforced limit rather than a bug to engineer around.**

The enforcement already exists and stays: crossing 2³² is an
explicit `VYK_ERR_OVERFLOW` from `tokenize_stream_feed`, never a
wrapped offset.

## Options considered

**1. Widen to `(kind:u8, start:i64, len:i64)` — 24-byte record.**
Rejected. It doubles per-token storage for every consumer, on every
input, to lift a limit essentially none of them reach. ADR 0002
chose 12 bytes specifically for cache behaviour and rejected
bit-packing for narrowing `start`; widening trades that away in the
other direction. It is also a breaking layout change for anything
reading records directly.

**2. Steal the padding — 40-bit fields inside the existing 12
bytes.** `kind` occupies byte 0 and bytes 1–3 are padding, so
`start` and `len` could each carry a 5th byte and reach 1 TiB with
`TOKEN_SIZE` unchanged and no memory cost. Genuinely tempting, and
rejected on two grounds. It puts a shift-and-or on `tokenbuf_start`
/ `tokenbuf_len`, which sit in the drain's inner loops and in every
consumer's iteration. More importantly it makes the *documented*
layout lie: a consumer reading `start` as a raw `u32` at offset 4 —
exactly what ADR 0002 publishes — would silently disagree with the
accessors past 4 GiB. Trading a loud failure for a quiet
disagreement is the wrong direction, and this whole finding exists
because a limit was invisible.

**3. Accept and document (chosen).** The ceiling is per-*stream*,
not per-process: a consumer that needs to tokenize more than 4 GiB
creates a new stream. For the use case that motivated streaming in
the first place — `owl huge.log` — that is a natural segment
boundary, not a workaround.

## Consequences

- `tokenize_stream_*` accepts at most **4,294,967,295 bytes of
  total input per stream**. Beyond that, `_feed` returns
  `VYK_ERR_OVERFLOW` and the stream stops accepting input. This is
  now a contract, not an accident.
- `VYK_STREAM_CAP` (16 MiB) remains a bound on the *live* window,
  and as of 2.4.0 it is genuinely that: the compose-hold bound
  (`VYK_COMPOSE_HOLD_MAX`) stopped an unresolved compose opener from
  turning it into a total-input ceiling. The two limits are
  independent and both are documented.
- Consumers that may exceed 4 GiB must segment. `tokenize_stream_new`
  is cheap; the per-stream state is 88 bytes plus the live buffer.
- If a consumer ever does hit this in practice, revisit option 1 —
  the measurement to bring is per-token memory against the workload,
  not a hypothetical.

## Revisit when

A real consumer reports the overflow, or the token record changes
for an unrelated reason (at which point widening costs nothing extra
because the layout is already moving).
