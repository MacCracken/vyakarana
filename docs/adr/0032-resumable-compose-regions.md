# 0032 — Unclosed compose bodies run to the end; open regions stream

- **Status:** Accepted
- **Date:** 2026-10-27
- **Deciders:** 2.9.10 streaming work (proposed) / user (accepted via
  the 2.9.10 roadmap entry)
- **Relates to:** [ADR 0013](0013-grammar-composition-rule.md),
  [0016](0016-compose-fenced-rule.md), [0019](0019-compose-region-rule.md)
  (the compose rules), [ADR 0028](0028-streaming-holds-watches-groups.md)
  (holds, watches, groups — this is its "when to revisit"),
  [ADR 0017](0017-streaming-api.md) (the API, unchanged),
  `src/tokenize.cyr`, `src/grammars/default_scanner.cyr`

## Context

ADR 0028 left one cost: a compose region still open at the buffer's
end gives no incremental output until it closes. A 425 KB python fence
fed in 4 KB chunks kept all 425 KB live and committed nothing past its
opener until the closing fence arrived; a cyml file's last body — a
`compose_region`, which always runs to the end — committed nothing
after its `---` until finish. Two things kept it that way:

1. **The opener's meaning depended on input not yet seen.** A
   `compose` or `compose_fenced` start with no end marker anywhere
   after it was not a region at all (ADRs 0013, 0016): the opener and
   everything after it went to the outer grammar. Until the marker
   arrived, no byte of the body could commit, because the input might
   end without one.
2. **The drain re-scans with one grammar from its buffer's start.**
   Once the opener committed, the next scan would read the body with
   the outer grammar.

## Decision

1. **A body with no end marker runs to the end of the input**, read by
   its inner grammar — as CommonMark reads an unclosed fence and HTML
   an unclosed `<style>` or `<script>`. The opener is its punctuation
   token; there is no end token. `compose_region` already behaved so
   (ADR 0019); an untagged or unknown fence's body is still one string.
   The opener's meaning no longer depends on input that has not
   arrived, which is what makes point 2 possible.
2. **An open region streams with its inner grammar.** When a drain's
   scan reports its compose hold as a region still open at the
   buffer's end whose body has an inner grammar, everything before the
   opener has committed, and the opener is final (the marker window,
   and the lookaheads of the tokens before it, are satisfied), the
   drain commits through the opener and enters **region mode**: the
   stream keeps the inner grammar, the end marker, where its search
   resumes and, for a fence, whether a closer may start there (record
   +224 … +272, 280 bytes). Each later drain:
   - searches the **new** bytes for the end marker the way the scanner
     does — anywhere for `compose` and `compose_region`, at a line start
     or after `end_indent` bytes for a fence;
   - **found:** the body commits as the inner grammar's finish over it,
     then the marker (a `compose_region`'s `end_before` stays for the
     outer grammar); region mode ends and the rest drains with the outer
     grammar in the same call;
   - **not found:** drains the body with the inner grammar — the whole
     drain, its holds, watches and fast paths — but no further than the
     earliest tail of the buffer that could still begin the end marker:
     those bytes are not known to be body;
   - **at finish:** the inner grammar's finish over all of it.

   The body's first scan starts as a file start (no look-behind; a
   shebang counts), as a single feed's nested scan of the body does,
   and the nesting cap (`DS_MAX_DEPTH`) counts one level up, so it cuts
   where a single feed's does. The tokens equal a single feed's because
   what region mode drains is always a prefix of the body that feed's
   nested scan sees, so the inner grammar's own chunk invariance
   (ADR 0028) carries over; the end-marker search decides as the
   scanner does; and the opener cannot change once entered.
3. **One level.** A region opened inside a region's body — a fence in
   a cyml body, a `<style>` in an html fence — is held as before, with
   its end-marker watch, inside the outer region's stream. Untagged
   fences and regions whose inner grammar is not loaded hold as before
   too: their body is one token.

## Consequences

### Positive

- A long open region's live buffer and per-feed work are the inner
  grammar's own. Fed in 4 KB chunks: a 425 KB python fence, 425,963 →
  6 bytes live; a 372 KB `<style>`, 372,725 → 7; a 467 KB `<script>`,
  466,933 → 10; a 540 KB cyml body, 542,674 → 7; a 536 KB mdx import
  block, 536,577 → 6. Tokens commit as they settle; total time is
  unchanged (0.2 – 0.3 s each).
- Chunk invariance holds as before: every compose corpus at every
  split offset, and the new region shapes at every offset, every pair
  of offsets and in 1 – 3 byte chunks. Each of nine mutants of region
  mode fails a CI gate (the test suite or `fuzz/chunk_invariance.fcyr`).
- Single feeds change only where a body has no end marker: 21 of a
  5,000-file sample of compose-grammar files, all markdown — 9 with an
  odd fence count (genuinely unclosed), 12 whose fences an earlier
  construct had already misaligned (an inline code span running into a
  fence) — and 2 of 18 real MDX files, both of the second kind, with no
  change in error tokens; 0 of the 7,527-file general sample.

### Negative

- Token boundaries change after an unclosed opener: the inner grammar's
  tokens (or one string, for an untagged fence) where the outer
  grammar's were. ADRs 0013 and 0016 described the old reading as
  graceful degradation; they carry amendments.
- An unmatched `{` in MDX prose now runs as JavaScript to the end (MDX
  itself rejects it).
- The drain is now `_stream_drain_g` — grammar, scan limit and finish
  as parameters — under a region driver; the stream record is 280 bytes
  (internal).
- A region open inside an open region still holds.

### When to revisit

- A consumer needs a region open inside an open region to stream (a
  long fence still open in a cyml body): a stack of region states, every
  level's end marker searched, the shortest limit applied.
