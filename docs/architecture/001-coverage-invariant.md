# 001 — Coverage invariant

> **Affects:** every grammar, every consumer, every audit pass.
> The correctness contract for the whole library.

## What it is

For any input buffer of length `N`, the tokenbuf vyakarana
produces satisfies two properties:

1. **No gaps.** The set of byte ranges covered by the emitted
   tokens, taken in order, exactly tiles `[0, N)`. Every input
   byte is inside exactly one token.
2. **No silent drops.** When no other rule matches the byte at
   the cursor, the scanner emits a `TK_ERROR` token of length 1
   and advances. `error` is an explicit token kind in the palette
   (see `src/token.cyr`); it is never a rejection or a panic.

Together: **`sum(token.len for token in tokenbuf) == src_len`**,
with each token contiguous to its predecessor. This is the
property `scripts/smoke.sh` checks per language ("coverage
N/N"); it's also the invariant the per-grammar test probes in
`tests/vyakarana.tcyr` rely on.

## Why it's not derivable from code

The fallback that makes the property hold lives at the *bottom* of
the scanner pipeline (see [architecture note 002](002-scanner-pipeline-priority.md)
step 11) — a single `kind = TK_ERROR; len = 1;` branch.
A casual reader looking at any individual rule type (line, pair,
words, ident, number, operator) sees what *succeeds*, not the
guarantee that *something* always succeeds. The 1-byte error
fallback is what closes the gap.

The property also implies a non-obvious obligation on every new
rule type: it must either consume ≥ 1 byte or yield to the next
step. A rule that returns `len = 0` and claims `kind != 0` is a
silent gap and breaks the invariant. The default scanner's
`while (i < src_len)` loop assumes monotonic progress; a rule that
violates that assumption hangs the scanner.

## Why it matters

- **Themes can render without losing bytes.** A consumer that
  re-emits source from `(kind, start, len)` triples reconstructs
  the original bytes exactly — `tokenbuf` is a complete
  partitioning, not a filtered view.
- **No-error gates on real corpora are meaningful.** The smoke
  script's "zero `error` tokens" claim per language is only
  load-bearing because the alternative to coverage isn't "we
  dropped a byte" — it's "we admitted defeat by emitting an
  `error`." Every closed gap is a verified `error → some real
  kind` transition.
- **Security audits anchor here.** "vyakarana is a library over
  arbitrary input" (per `SECURITY.md`) is only true if the
  scanner can't infinite-loop, segfault, or skip bytes. The
  coverage invariant is what those audits check.

## When it can break (and how to spot it)

- **A pair rule with `start = ""`.** `_ds_try_pair_rules` would
  match every cursor position with zero advance and the loop
  hangs. Guard at grammar-load time, not in the scanner.
- **A new `[defaults]` flag whose handler doesn't set `len`
  before exiting step 6+.** The pipeline expects `len > 0` from
  any branch that sets `kind`; a typo that leaves `len = 0` after
  setting `kind` will let later steps overwrite the kind and
  scramble the output. Tests in `tests/vyakarana.tcyr`'s
  cross-tokenizer-equality block will catch byte-count mismatches.
- **A consumer that `memcpy`s `src` into a smaller buffer before
  tokenizing.** Not vyakarana's bug, but the invariant only holds
  for the buffer that was actually scanned. Document this at the
  consumer.

## Where to verify

- `scripts/smoke.sh` prints `coverage N/N` per language pair.
  Anything other than `N/N` is a bug.
- `tests/vyakarana.tcyr` includes per-grammar probes that walk
  the tokenbuf and assert contiguous spans.
- `vyk --language=<lang> file | jq '.start + .len'` (one per
  token) should equal the cumulative offset of the next token,
  ending at `file_size`.
