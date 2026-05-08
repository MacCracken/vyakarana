# ADR 0009 — `unicode_ident` default + C block comments

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** modernization-survey agent (proposed) / user (accepted)
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md)
  (rule-type scope), `src/grammar.cyr`,
  `src/grammars/default_scanner.cyr`, `grammars/c.cyml`,
  `grammars/markdown.cyml`,
  `vidya/content/<topic>/{c.c,markdown.md}`

## Context

The default scanner's identifier-class machinery (`ident_start` /
`ident_cont` char-class tables, populated from grammar `[defaults]`
strings like `"A-Za-z_"`) is ASCII-only by construction. Any byte
≥0x80 that reaches step 6 of the scanner pipeline falls through
to step 11 (the `TK_ERROR + advance 1 byte` fallback). For source
where multi-byte UTF-8 lives only inside string-pair spans
(Python, Rust, Cyrius, JS/TS), this is fine — the pair scanner
walks the bytes greedily and the UTF-8 stays inside one
`TK_STRING` token.

Two corpus shapes broke that assumption:

1. **C `/* … */` block comments containing UTF-8 prose.**
   `vidya/content/<topic>/c.c` files lead with a header like
   `/* Vidya — Compression (LZ77-shaped) in C` where the em-dash
   is `0xE2 0x80 0x94`. The C grammar didn't have a block-comment
   rule, so the `/*` opener tokenized as two operators and the
   em-dash bytes hit the error fallback (3 errors per em-dash).
   Block comments often also contain backticks (`\``), which are
   ASCII but not in C's operator/punctuation list — those errored
   too.

2. **Markdown prose containing UTF-8.**
   Markdown bodies routinely contain em-dashes, smart quotes,
   accented characters. The markdown grammar's pair rules cover
   `` ` `` code spans and `\*\*`-style emphasis, but bare prose
   bytes ≥0x80 had no rule to catch them.

The 1.0.3 modernization survey verified an 8-error count in
`vidya/content/compression/c.c` and high error rates in markdown
prose samples. Both are cosmetic (`error` vs `ident` semantically)
but the no-`error`-tokens invariant is the project's correctness
contract per `docs/development/state.md`; we wanted it back.

## Decision

Two coupled changes:

1. **New `[defaults]` flag: `unicode_ident = true`.** When set,
   bytes ≥0x80 are accepted as both ident_start and ident_cont.
   A run of multi-byte UTF-8 (or a mix of ASCII letters and
   UTF-8) coalesces into one `TK_IDENT`. The flag is wired
   through `Grammar` (new field at offset 136, `GRAMMAR_SIZE`
   144), the CYML loader (`unicode_ident = true|false`), and the
   default scanner (step 6 entry condition + `_ds_scan_ident`
   continuation check).

   Defaulting **off**, enabled per-grammar where the corpus
   needs it. Currently set in `grammars/c.cyml` and
   `grammars/markdown.cyml`. Other grammars can flip the flag
   if a future corpus surfaces UTF-8 outside their string spans.

2. **C grammar gains a `match = "pair"` rule for `/* … */`.**
   C's block comments are non-nestable, so the same simple greedy
   match used elsewhere works. The rule is ordered after the `//`
   line rule but before the string rule. With unicode_ident on,
   any em-dash inside the comment body is now a string-internal
   byte, irrelevant to the scanner.

## Consequences

### Positive

- **Zero `error` tokens on
  `vidya/content/compression/c.c`** (was 8); zero errors across
  seven other vidya C samples spot-checked
  (linking_and_loading, error_handling, binary_formats,
  memory_management, allocators, kernel_topics, lexing_and_parsing).
- **Markdown stand-in corpus stays clean** (the ADR-0006 swap of
  `—` for `--` is no longer required for new prose; future
  markdown corpora can use real em-dashes).
- **One scanner-level mechanism, opt-in.** Languages where
  UTF-8-outside-strings is genuinely an error (e.g. JSON, where
  the spec disallows it outside strings) can leave the flag off
  and continue to flag invalid input.
- **No allocation, no per-token cost.** The check is one `>= 128`
  comparison plus a flag read, both in the inner loop's existing
  branch.

### Negative

- **Loss of "this byte is invalid" detection** in grammars where
  the flag is on. JSON deliberately stays off so that `é` outside
  a `"…"` string still tokenizes as `TK_ERROR` — the right call
  for a grammar whose spec rejects bare UTF-8.
- **Idents can now span the ASCII/UTF-8 boundary** (e.g. `naïve`
  → one ident). This is consistent with how editors highlight,
  but a strict reader of the Rust Reference's `XID_Start /
  XID_Continue` definition might object that we accept e.g. byte
  0xC3 alone (the leading byte of `é`) as ident_start without
  validating that it's followed by a legal continuation byte. The
  scanner is a tokenizer, not a UTF-8 validator; ill-formed UTF-8
  passes through as ident bytes here just as it would inside a
  string span.
- **Grammar-record ABI bumped** from 136 to 144 bytes. No
  external consumer depends on the in-memory record layout
  (`tokenize_source` returns a `tokenbuf`, not a `Grammar`), so
  this is a private change.

### When to revisit

- If a per-grammar UTF-8 audit (e.g. enforcing valid UTF-8 byte
  sequences when the flag is on) becomes worth the code, promote
  to a small validator inside `_ds_scan_ident`.
- If Rust gains a `block_comment_nestable = true` variant of the
  pair rule, the C entry can serve as the simple-case template.
