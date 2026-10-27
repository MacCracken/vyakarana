# 0028 — Streaming engine: scanner-reported holds, watches and groups

- **Status:** Accepted
- **Date:** 2026-10-20
- **Deciders:** 2.8.0 streaming-engine work (proposed) / user (accepted
  via the pinned 2.8.0 roadmap entry)
- **Relates to:** [ADR 0017](0017-streaming-api.md) (the streaming API —
  unchanged), [ADR 0013](0013-grammar-composition-rule.md),
  [0016](0016-compose-fenced-rule.md), [0019](0019-compose-region-rule.md)
  (compose rules), [ADR 0023](0023-heredoc-rule.md) (the first hold and
  watch), [ADR 0026](0026-number-literal-shapes.md),
  [ADR 0027](0027-prefixes-lead-bytes-next-byte-rules.md),
  `src/tokenize.cyr` (`tokenize_stream_drain`),
  `src/grammars/default_scanner.cyr`

## Context

`tokenize_stream_drain` re-scans its buffer from the last commit,
commits the tokens it can prove settled, and compacts. What counted as
"settled" had grown into a set of independent guards — the marker
window, the pair-provisional check, trailing-complete, the pending-pair
fast path, the 2.6.0 heredoc hold and watch — plus one guard that did
not fit: **compose prefix-hold**, which re-derived compose state from
outside the scanner (re-searching start and end markers, skipping
emitted punctuation) and read the commit list as state. Because the
marker window broke prefix-hold, the five compose grammars ran without
it. The 2.8.0 roadmap entry collected what that cost:

- **Compose grammars were not chunk-invariant:** cyml failed at 90 % of
  two-feed split offsets (its `---` body never counted as open), and
  markdown, html, vue and svelte at a handful each. Prefix-hold was
  O(buffer × rules) per drain — a 550 KB fenced block in 4 KB chunks
  ran past 300 s.
- **Long tokens re-scanned per drain:** a 512 KB comment, identifier,
  whitespace run or number fed in 64-byte chunks took 3–14 s; a
  prefixed string (`f"…"`, ADR 0027) 18.6 s, and a multi-line one was
  split at a line break — the helpers mistook it for a line comment.
- **Heredoc search had a budget that scaled with the buffer**, so a
  compacted stream gave up sooner than a single feed (2.6.x audit), and
  the terminator watch re-read the last partial line every drain.

A full state machine — a drain that resumes the scanner mid-token,
mid-rule, mid-compose-body — was considered and rejected for 2.8.0: it
would make every rule type and the compose recursion resumable, a
rewrite of the scanner rather than of the drain.

## Decision

Keep rescan-and-commit, and change who knows what:

1. **The scanner reports what it could not resolve.** Besides the
   heredoc hold (2.6.0), a depth-1 scan reports the lowest **compose
   opener** it left unresolved — a `compose` or `compose_fenced` start
   with no close in the buffer, a fence whose info line has not ended,
   a `compose_region` still running at the buffer's end — and the drain
   commits nothing from there until it resolves, the stream finishes,
   or the hold passes `VYK_COMPOSE_HOLD_MAX`.
2. **Groups commit whole.** Every finished compose region and heredoc
   group is recorded (from, to); the drain treats its tokens as final,
   even at the buffer's end, so no tail check can leave the next scan
   starting inside one.
3. **Prefix-hold is gone; the marker window applies to every grammar**,
   and trailing-complete and pending-pair detection respect it (a token
   that starts inside the window — markdown's `` `` `` before a third
   backtick — is not settled).
4. **Watches replace re-scans.** While a hold or a long tail token is
   waiting, later drains look only at new bytes and return immediately:
   mode 1 a heredoc terminator line (incremental, line by line), mode 2
   the next line break, mode 3 a marker string (a compose close, a cyml
   `\n[[`, or the close of a string keeping a heredoc's line open),
   mode 4 finish; the **run watch** waits out a long comment,
   identifier, whitespace or digit run; pending-pair detection now
   understands string prefixes (and raw prefixes' lack of escapes). A
   watch only ever delays a scan that would have committed nothing — a
   hold is always safe — so none can change a token.
   *(Amended 2.9.1. The audit's streaming reviewer confirmed that half
   structurally — every watch returns having committed nothing, or
   clears itself and falls through to a full scan — and found the
   other half, "linear", broken four ways, each quadratic on chunked
   input: a heredoc whose delimiter quote removal rewrote got no
   working watch (a garbage offset, or none); mode 3 fired on a
   fence's "```" anywhere though a fence closes only at a line
   start, and on an escaped `\"`; the run watch refused whitespace in
   heredoc grammars and line-rule tokens of kinds other than comment.
   Fixed: the stream keeps a copy of a rewritten delimiter (+192),
   mode 3 carries where its marker counts and its escape byte (+200,
   +208; record 216 bytes), the run watch classifies line-rule
   tokens by origin. The one commit made outside a full scan, the
   pending-pair fast path, did change tokens: a prefixed triple-quoted
   string whose body starts with quotes, fed a byte at a time, closed
   at its own opener — its resume point is clamped to the body start
   now.)*
5. **Heredoc terminators are looked up in a per-scan line index**
   (content hashed into buckets of line numbers, walked from a
   forward-only cursor) instead of searched under a budget: linear, and
   the same verdict however the input is chunked. *(Amended 2.9.4: a
   line's end is derived from the next line's start, and each half —
   exact content for `<<`, tab-stripped for `<<-` — is built on its
   first lookup: 16 bytes a line for `<<`, 20 for `<<-`, 32 for both; 52
   in 2.8.0, 36 from 2.9.1.)*

## Consequences

### Positive

- **Every corpus is chunk-invariant** — the every-offset two-feed split
  is clean on all 49 corpus files (the five compose grammars included),
  and `fuzz/chunk_invariance.fcyr` covers all of them.
- The quadratic cases are linear: 512 KB tokens in 64-byte chunks 3–18 s
  → 0.01–0.05 s; a 550 KB fence > 300 s → 0.26 s; a 540 KB `<style>`
  12.8 s → 0.25 s; a 1 MiB one-line heredoc body at 512 bytes 7.0 s →
  0.03 s.
- The drain's decisions read from the scanner's own state; nothing
  outside it re-derives compose structure any more.

### Negative

- **An unresolved compose region gives no incremental output** until it
  closes: a cyml body running to the end of the document, or an
  unclosed `<style>`, commits only at finish (or past 8 MiB, after which
  the held bytes commit as that drain's scan read them — for `<style>`
  the outer grammar's reading, for a cyml region the region's own tokens
  up to the buffer's end; either may differ from a single feed from
  there on — the documented bound). The
  tokens are the single feed's; only their arrival is later.
- The stream record grows to 192 bytes (internal; 216 in 2.9.1, 224 in 2.9.3); the scanner keeps a
  per-depth line index for heredoc grammars.

### When to revisit

- A consumer needs tokens from inside a long, still-open compose region
  as they arrive: make the region resumable — the stream remembers the
  inner grammar and re-scans only the body — the narrowest piece of the
  rejected state machine.
