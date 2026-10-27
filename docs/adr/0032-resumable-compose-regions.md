# 0032 — Unclosed compose bodies run to the end; open regions stream

- **Status:** Accepted — extends [ADR 0028](0028-streaming-holds-watches-groups.md);
  amends [0013](0013-grammar-composition-rule.md), [0016](0016-compose-fenced-rule.md);
  fences excluded since 2.9.12 (point 1, amended)
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
   *(Amended 2.9.12: not for `compose_fenced`. A fence with no closer is
   no fence again, as through 2.9.9, and is held for a closer that may
   still arrive. CommonMark does run an unclosed fence to the end, but
   only one CommonMark itself opens; vyakarana opens fences CommonMark
   does not — a mid-line "```", a list item's or a blockquote's fence it
   cannot see the end of, a pairing an inline code span crossing blocks
   has shifted. 52 of one machine's 5,768 markdown files had a fence
   2.9.11 ran to the end where CommonMark (micromark) closes it, with no
   error token to show it — one CHANGELOG's largest token 29 KB → 300 KB
   (the 2.9.12 audit, reviewer A). Region mode keeps kinds 1, 3, 4 and
   the new 5 (`end_blank`, ADR 0019); `<style>` and `<script>` run to the
   end as HTML reads them. Also from that audit (reviewer B): the
   fence-only line-start state the region search kept was not carried
   over bytes the inner drain committed past the search point, so a
   closer after a Lua `--` comment was missed in a stream — gone with
   fence regions; and a region's first body commit no longer inherits
   the opener's bytes as look-behind.)*
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

   *(Amended 2.10.0: since 2.9.12 no fence enters region mode, so the
   fence half of this point is history. The stream keeps no line-start
   state — +248 and +264, a fence's `end_indent` and line state, are
   unused — and the record is 296 bytes. The search is for the end
   marker anywhere (`compose`, `compose_region` with `end_before`), for
   a line break a blank line follows (kind 5, `end_blank`), or none
   (kind 4, a body to the end of the input).)*

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
   *(Amended 2.10.0: since 2.9.12 a fence is never the outer region —
   one whose closer has not arrived is held as outer text, tagged or
   not (point 1's amendment), so there is no html fence for a `<style>`
   to open inside. A fence in a cyml body still holds inside that
   body's stream until its closer arrives, and a region whose inner
   grammar is not loaded still holds as one token.)*

## Consequences

### Positive

- A long open region's live buffer and per-feed work are the inner
  grammar's own. Fed in 4 KB chunks: a 425 KB python fence, 425,963 →
  6 bytes live; a 372 KB `<style>`, 372,725 → 7; a 467 KB `<script>`,
  466,933 → 10; a 540 KB cyml body, 542,674 → 7; a 536 KB mdx import
  block, 536,577 → 6. Tokens commit as they settle; total time is
  unchanged (0.2 – 0.3 s each). *(Amended 2.10.0: not the fence since
  2.9.12 — a fence holds, its bytes live, until its closer arrives; the
  other four stand.)*
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
  graceful degradation; they carry amendments. *(Amended 2.10.0: since
  2.9.12 only after a `compose` opener — a fence with no closer reads
  as through 2.9.9 again, which also undoes the single-feed changes
  counted under Positive, all of them fences.)*
- An unmatched `{` in MDX prose now runs as JavaScript to the end (MDX
  itself rejects it).
- The drain is now `_stream_drain_g` — grammar, scan limit and finish
  as parameters — under a region driver; the stream record is 280 bytes
  (internal). *(Amended 2.10.0: 296 since 2.9.12; the fence fields,
  +248 and +264, are unused.)*
- A region open inside an open region still holds.

### When to revisit

- A consumer needs a region open inside an open region to stream (a
  long fence still open in a cyml body): a stack of region states, every
  level's end marker searched, the shortest limit applied.
- Fences open the way CommonMark opens them — at a line start, inside
  containers it tracks: then an unclosed fence can run to the end again
  and stream (amendment to point 1).
