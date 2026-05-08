# 0017 — Streaming tokenizer API (2.0)

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** RM (2.0.0 cut)
- **Relates to:** Milestone 5 (the original M5 carryover);
  `vyakarana-design-spec.md` §6 "Streaming Tokenizer";
  `src/tokenize.cyr`; the entire 1.x line that ran on the
  synchronous `tokenize_source` API; `docs/architecture/overview.md`
  "Frozen public contracts" (now invalidated for the 1.x →
  2.x boundary)

## Context

Through 1.13.3 the public tokenizer entry was synchronous:

```cyrius
fn tokenize_source(src, lang) -> tokenbuf
```

The caller hands over a complete cstr buffer; the function
returns a fully-populated tokenbuf. This is fine for files
under `VYK_SRC_CAP` (1 MB), but the design spec §6 promised
streaming since M0 and the 2.0.0 boundary is the only
scheduled API break. Hard cap on file size, no support for
network / pipe / progressive consumption — all friction the
spec said we'd address.

The break is significant enough that we treated it as the M5
carryover and reserved it for the major-version bump.

## Decision

**Replace `tokenize_source` with a push-based streaming
primitive.** Five functions; no compat shim.

```cyrius
fn tokenize_stream_new(lang) -> stream_handle
fn tokenize_stream_feed(s, chunk, n) -> i64
fn tokenize_stream_drain(s, out_tb) -> i64
fn tokenize_stream_finish(s, out_tb) -> i64
fn tokenize_stream_free(s)
```

- `tokenize_stream_new(lang)` — allocates a stream tied to the
  named grammar. Returns 0 if the grammar isn't registered.
- `tokenize_stream_feed(s, chunk, n)` — appends `n` bytes from
  `chunk` to the stream's internal buffer. Returns `VYK_OK`
  (0) on success, `VYK_ERR_OVERFLOW` (-1) if the buffer cap
  would be exceeded, `VYK_ERR_FINISHED` (-2) if `finish()`
  already ran.
- `tokenize_stream_drain(s, out_tb)` — emits any tokens whose
  spans are now complete into `out_tb`. Returns the number of
  tokens this call appended. **2.0.0 implementation note:** the
  scanner runs at finish() time, so drain() returns 0 until
  finish() has been called once. 2.0.1+ will emit tokens for
  completed prefixes after each feed.
- `tokenize_stream_finish(s, out_tb)` — marks the stream done;
  emits every remaining token. After finish, feed returns
  `VYK_ERR_FINISHED` and drain becomes a no-op.
- `tokenize_stream_free(s)` — releases the stream's handle.
  Caller-owned tokenbuf is NOT freed.

Choice rationale (see the question/answer trail in the cut log):

- **Push, not pull.** Caller owns the byte source — file read,
  network read, pipe — and pushes chunks. Maps naturally to
  `read(fd, buf, n)` loops without forcing vyakarana to know
  about the source. Pull adapter (`tokenize_stream_next`) is
  queued for 2.0.1+ as a thin wrapper.
- **Sub-cut by API and internals.** 2.0.0 ships only the new
  surface; the internal scanner is unchanged. feed() buffers
  chunks into a single contiguous source; finish() runs the
  existing `tokenize_with_grammar` over the buffered bytes.
  Real per-token-resume streaming (rolling buffer, scanner
  state machine) lands in 2.0.1+. The public API contract
  doesn't change across that internal refactor.
- **No compat shim.** `tokenize_source` is removed in 2.0.0.
  Consumers must migrate. The migration is mechanical (see
  Migration recipe below) and the gain — being able to call
  the library at all from a streaming context — is the whole
  point of the major-version bump.

The `Grammar` registry, kind constants, tokenbuf accessors,
detection functions (`detect_language*`), LSP bridge, and theme
export functions are all unchanged across the 1.x → 2.x
boundary.

## Migration recipe

Old (1.x):
```cyrius
var tb = tokenize_source(src, "rust");
if (tb == 0) { /* unknown grammar */ }
# walk tb...
```

New (2.0):
```cyrius
var s = tokenize_stream_new("rust");
if (s == 0) { /* unknown grammar */ }
var tb = tokenbuf_new();
tokenize_stream_feed(s, src, strlen(src));
tokenize_stream_finish(s, tb);
tokenize_stream_free(s);
# walk tb...
```

Five lines instead of one. The expanded shape is the cost of
making the API streaming-capable; consumers that want a
one-liner can wrap the dance in their own helper:

```cyrius
fn my_tokenize(src, lang) {
    var s = tokenize_stream_new(lang);
    if (s == 0) { return 0; }
    var tb = tokenbuf_new();
    tokenize_stream_feed(s, src, strlen(src));
    tokenize_stream_finish(s, tb);
    tokenize_stream_free(s);
    return tb;
}
```

The vyakarana test harness uses exactly this wrapper
(`_t_tokenize` in `tests/vyakarana.tcyr`). The CLI's pre-read
flow follows the same shape inside `tokenize_buf` in
`src/main.cyr`.

## Consequences

### Positive

- **Streaming consumers work.** Callers reading from a pipe,
  socket, or chunked file can feed bytes as they arrive. 2.0.0
  buffers the lot before scanning, so the *useful* streaming
  benefit (memory bound by per-token state, not by total
  input size) waits for 2.0.1+. But the API surface is
  stable — consumers wire up the right shape today and pick
  up the internal speedup automatically.
- **Multi-chunk feed is byte-equivalent to one-shot feed.**
  `tests/vyakarana.tcyr` 2.0.0 group locks the contract: any
  chunking strategy produces the same `(kind, start, len)`
  tokens as a single `feed` call.
- **Error codes are explicit.** `VYK_OK` / `VYK_ERR_OVERFLOW`
  / `VYK_ERR_FINISHED` are documented constants; callers can
  branch on them instead of guessing.
- **The break is contained.** Only `tokenize_source` was
  removed. Every other public symbol — kind constants,
  tokenbuf accessors, detection, LSP, theme export, grammar
  load — survives unchanged. Consumers update one function;
  the rest of the integration recipe is identical.

### Negative

- **Per-call overhead grows.** The 2.0.0 implementation does
  one extra alloc (the stream record) plus one byte-copy
  (chunk → internal buffer) per feed. Bench numbers regress
  ~5–25% on small inputs (shell 18 µs → 19 µs; rust 26 µs →
  28 µs; json 3 µs → 5 µs; html-compose 8 µs → 10 µs). For
  the large-file streaming use case the overhead is amortized
  trivially; for the small-buffer case (e.g. cyim's per-line
  tokenize) the overhead is real and worth optimizing in
  2.0.1+.
- **Five-call dance per use.** Every call site that used to be
  `tokenize_source(src, lang)` is now five lines. Verbose. We
  considered keeping a one-liner wrapper but the user
  preferred the clean break — adding our own wrapper would
  re-introduce the synchronous shape and dilute the streaming
  story.
- **Buffer cap is the same as 1.x.** 2.0.0 still caps at 1 MB
  (`VYK_STREAM_CAP`) because it buffers everything before
  scanning. The streaming benefit (memory ≪ input) only
  arrives in 2.0.1+ when scanner state can pause/resume.
  Documented in the module header.
- **Drain is currently a tease.** 2.0.0's drain returns 0
  until finish has been called; consumers writing
  `while (drain() > 0) { … }` loops won't see anything until
  finish runs. The contract doesn't *require* per-feed
  drainage today; 2.0.1+ delivers it.

### When to revisit

- **2.0.1+ scanner refactor.** The natural next move. Rolling
  buffer, scanner state encoded as a struct, drain emits
  tokens per feed. Bench should improve as the
  alloc-then-copy buffer-up-everything pattern goes away.
- **Pull adapter** (`tokenize_stream_next(s, out_token)`).
  Wraps the push primitive; useful for consumers who prefer
  iteration. Trivial once the per-token-resume scanner lands.
- **Cap raised / removed.** When the rolling-buffer scanner
  is in place, `VYK_STREAM_CAP` becomes max-token-len rather
  than max-source-len. We can either remove it or repurpose
  it.
- **Async / coroutine API.** If Cyrius gains coroutines, the
  pull adapter could become a real generator. Not on any
  near-term roadmap.
