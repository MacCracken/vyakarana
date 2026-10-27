# 0033 — Incremental retokenization: documents that restart their stream

- **Status:** Accepted (amended 2.9.12: checkpoint thinning, the hold-bound fallback)
- **Date:** 2026-10-27
- **Deciders:** 2.9.11 edit-API work (proposed) / user (accepted via the
  2.9.11 roadmap entry)
- **Relates to:** [ADR 0017](0017-streaming-api.md) (the streaming API,
  unchanged), [ADR 0028](0028-streaming-holds-watches-groups.md) (what a
  drain commits is settled; chunk invariance),
  [ADR 0032](0032-resumable-compose-regions.md) (region mode, part of a
  stream's state), `src/tokenize_doc.cyr`, `src/tokenize.cyr`

## Context

An editor that changes a few bytes wants the text's tokens again
without tokenizing all of it; cyim tokenizes its whole buffer on every
change. The roadmap asked for an edit API that re-tokenizes from the
first token an edit can affect to the first point where the old and
new token streams agree again, with the result always equal to
tokenizing the edited text from scratch.

Neither end of that range is local. Tokens **before** an edit can
change: a terminator line appended to a shell script turns the code
after a `<<EOF` far above into a heredoc body. Tokens after it can
change to the end of the text (an opened quote or comment), or not at
all. And a token boundary is not a place to restart: inside a heredoc
or compose body, or after a token whose end depends on what follows,
the scanner started there reads something else. The scanner keeps no
resumable state. The one thing that knows which boundaries are settled
is the streaming drain: what it commits is final for any bytes that
follow (ADR 0028), and its state at that moment is all it needs to go
on.

## Decision

1. **A document object**, additive public API:
   `tokenize_doc_new(lang)`, `tokenize_doc_set(d, src, n)`,
   `tokenize_doc_edit(d, src, n, at, removed, inserted)`,
   `tokenize_doc_tokens(d)`, `tokenize_doc_changed_first` / `_old` /
   `_new(d)`, `tokenize_doc_free(d)`. An edit passes the whole edited
   text, in which `[at, at + inserted)` replaced the last text's
   `[at, at + removed)`; a description the lengths cannot match
   tokenizes the text whole. The changed range is the re-scanned
   tokens less the ends that match the old ones, for an editor to
   repaint.
2. **Checkpoints.** A set feeds the text through a stream in
   `VYK_DOC_INTERVAL` (4096) byte chunks and, after each drain, saves
   the stream's state: the record's fields +72 … +272 (208 bytes), how
   much it had been fed, its commit point and the tokens committed — 232
   bytes a checkpoint, about 6 % of the text. A state that keeps a
   string in the stream's copy buffer (a rewritten heredoc delimiter,
   an unterminated inline literal's closer) is not saved; a missing
   checkpoint only means restarting further back. *(Amended 2.9.12: an
   edit saved one at each drain, including the drain a few bytes before
   the next old checkpoint moved by an insert, and nothing thinned them:
   25,000 inserts into a 161 KB file took 40 checkpoints to 23,063 and
   an edit from 0.9 ms to 2.4 ms (the 2.9.12 audit, reviewer C). An edit
   now drains at the next moved old checkpoint when it lies within half
   an interval past the grid point, and saves none within half an
   interval of the last: 40 stay 40.)*
3. **Restart.** An edit restores the last checkpoint fed no further
   than the edit's start. That stream had seen only bytes the edit left
   alone, so what it had committed is final in the edited text too, and
   its fields plus its buffer (those same bytes, from its commit point)
   are the stream itself. It is fed the edited text from there, drained
   every interval and at each old checkpoint's offset moved by the
   edit.
4. **Resynchronisation.** At an old checkpoint past the edit — its
   commit point at or after the edit's end, the new stream's at the
   same place moved by the edit, both past 0 or both at it — whose
   state equals the new stream's, it stops. The same state with the
   same bytes ahead (everything past that checkpoint is unedited) makes
   the same tokens, so the old tokens from that checkpoint's count on
   are kept, moved by the edit, and so are the old checkpoints from it
   on. Otherwise it runs to the end and finishes. The state comparison
   covers every field a drain reads: the look-behind always; the
   pending pair, the watch, the run watch and the region only while
   each is on; a region's committed-body count only as zero or not.
5. **Past a hold's bound.** *(Added 2.9.12.)* A stream fed in chunks
   gives up a compose or heredoc hold at its bound (`VYK_*_HOLD_MAX`,
   ADR 0028) and commits those bytes as the drain read them; one feed
   does not. A stream's caller can feed at once, a document's cannot —
   it always streams. So a stream records when a hold passed its bound
   (record +280), and a set or edit that saw one tokenizes the text in
   one feed instead, keeping only the first checkpoint. Through 2.9.11 a
   1.17 MB heredoc gave 540,011 tokens against one feed's 11 (reviewer C).
   One feed holds `VYK_STREAM_CAP` (16 MiB) at most; past that, the
   streamed tokens stand.
6. **Why the result is a single feed's.** By construction an edit's
   tokens are those the restored stream gives for the edited text fed
   in those chunks — the old tokens it keeps are what the same stream
   would have produced from an equal state — and a stream fed in chunks
   equals one feed: ADR 0028's chunk invariance, gated since 2.8.0.

## Consequences

### Positive

- A one-byte edit re-scans about one interval of text either side of
  it. On real files: a 164 KB Rust file, 25 ms to tokenize, 0.72 ms an
  edit on average (1.4 ms at most); a 774 KB markdown file, 99 ms and
  0.78 ms; a 937 KB C file (610,187 tokens), 226 ms and 1.6 ms (2.5 ms at
  most). An edit whose effect runs far re-scans as far as it runs. A
  document's memory does not grow with the edits made to it. *(Amended
  2.9.12: that was measured with edits and their undos; inserts that
  were never undone grew the checkpoints until the thinning in point 2.)*
- Gated. `fuzz/retokenize.fcyr` edits every offset of every corpus, in
  1 KB windows each a document of its own with checkpoints every 48
  bytes, and every 61st offset of each whole file at 4096 and at 48 —
  inserting a marker, deleting bytes or replacing them — and holds each
  result to a from-scratch tokenization and each undo to the original:
  273,306 edits. `scripts/audit/edit-sweep.sh` does every offset of
  whole files and real files.
- Shown to fail. Of nine broken resyncs and restarts, six fail the fuzz.
  Dropping the look-behind comparison fails a unit test: a grammar
  where `#` is a comment after a blank but a preprocessor line after `!`,
  so the byte before the commit point is the only difference. Dropping
  the pending-pair or the watch comparison fails nothing. Those fields
  never change a token (ADR 0028, point 4); they are compared so that
  resynchronisation rests on plain state equality, not on that claim.
  *(Amended 2.9.12: reviewer C found two more holes — restoring the
  look-behind and comparing its second byte were checked by nothing — and
  the fuzz checked the changed range only for soundness. The fuzz now
  also edits 16 short texts that lean on the bytes before a token at
  every checkpoint spacing from 1 to 12, on fresh and chained documents,
  and holds every edit's and undo's changed range to its exact minimum;
  unit tests pin both look-behind bytes. 319,986 edits.)*

### Negative

- Public surface grows by eight functions. That is additive, so a patch.
- A document trusts its caller's description of the edit. The lengths
  are checked; whether the bytes outside the edit are really unchanged
  is not, and an untrue description gives the tokens of a text it never
  saw.
- Moving the tokens after an edit is linear in their number: typing at
  the start of the 937 KB C file costs 4.9 ms.
- `fuzz/retokenize.fcyr` adds about a minute to `cyrius fuzz`.

### When to revisit

- A consumer whose files make moving the tokens after an edit too slow:
  keep the tokens in blocks with relative offsets.
- A consumer whose text is not contiguous (a gap buffer, a rope): feed
  the edit by ranges instead of one pointer.
