# ADR 0010 — `char_literal` default

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** roadmap follow-through (proposed) / user (accepted)
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md)
  (rule-type scope), [architecture note
  002](../architecture/002-scanner-pipeline-priority.md) (scanner
  pipeline order), `src/grammar.cyr`,
  `src/grammars/default_scanner.cyr`, `grammars/{c,rust,go,zig}.cyml`,
  `vidya/content/error_handling/{rust.rs,go.go,zig.zig}`

## Context

Through 1.2.0, vyakarana tokenized character literals like `'a'`,
`'+'`, `'\n'`, and `'\xff'` as a sequence of three or more
operator / ident / operator tokens. The leading `'` matched the
operator step; the body matched ident / operator / number; the
closing `'` matched operator again. Coverage and the no-error
invariant held for *plain ASCII bodies*, but **byte-character
literals with a backslash escape** (`'\n'`, `'\0'`, `'\xff'`)
emitted a `TK_ERROR` for the backslash because `\` was in none of
the operator, ident_start, or punctuation lists for C / Rust /
Go / Zig.

The 1.1.0 modernization survey logged this as the
"byte-char-literal-with-escape" gap, and pre-emptive scoping
(`grammars/rust.cyml`, `grammars/c.cyml` headers) noted that a
`char_literal = true` default with 2–3 char lookahead was the
likely fix. Independent counts confirmed it on the 1.2.0 corpus
sweep: one `'\n'` error each in
`vidya/content/binary_formats/rust.rs`,
`vidya/content/error_handling/go.go`, and
`vidya/content/error_handling/zig.zig` — three corpora out of
the C / Rust / Go / Zig spot-check pool of ~30.

The shapes that needed to coalesce into one `TK_STRING`:

| Shape       | Bytes | Examples                    |
|-------------|------:|-----------------------------|
| `'C'`       |     3 | `'a'`, `'+'`, `'0'`         |
| `'\C'`      |     4 | `'\n'`, `'\0'`, `'\\'`, `'\''` |
| `'\xHH'`    |     6 | `'\xff'`, `'\x1b'`, `'\xc3'` |
| UTF-8 body  |   4–6 | `'é'` (Rust)                |

The constraint that made this non-trivial: **Rust lifetimes**
(`'a`, `'static`, `'_`) share the same opening `'` but have *no
closing `'` at the right offset*. Any rule that greedily eats
the `'` would break Rust's lifetime tokenization. Three vidya
samples in the canonical `rust.rs` use lifetimes; they had to
keep working.

## Decision

**Add a new `[defaults]` flag `char_literal = true|false` and a
new step 7b in the scanner pipeline, between Number and
Operator.** The step:

1. Returns 0 immediately if the flag is off, the cursor is not
   at `'`, or there isn't room for at least 3 bytes.
2. Tries the four shapes in order: 6-byte `'\xHH'`, 4-byte
   `'\C'`, 3-byte `'C'`, and 4/5/6-byte UTF-8 bodies based on
   leading-byte ranges per RFC 3629.
3. Returns 0 (let the `'` fall through to the operator step) if
   no closing `'` lands at the right offset. **This is what
   keeps Rust lifetimes working** — `'a` has no closing quote at
   `cursor + 2`, so step 7b returns 0, the operator step takes
   the `'` as a 1-byte operator, and the next iteration of the
   main loop tokenizes `a` as an ident.
4. On match, emits a single `TK_STRING` token of the matched
   length.

The step lives entirely in `src/grammars/default_scanner.cyr`
(new helper `_ds_try_char_literal`); the flag is wired through
`Grammar` (new field at offset 144; `GRAMMAR_SIZE` 144 → 152)
and the CYML loader (`char_literal = true|false`).

Defaulting **off**, enabled per-grammar in `grammars/c.cyml`,
`grammars/rust.cyml`, `grammars/go.cyml`, and `grammars/zig.cyml`.

## Consequences

### Positive

- **Closes the only known cosmetic gap that was producing
  `TK_ERROR` tokens.** The 1.2.0 spot-check pool drops from "27
  of 28 clean, 1 with a `\` error" to "28 of 28 clean" for C,
  Rust, Go, Zig combined.
- **Pipeline cost is one branch.** The hot path for non-`'`
  bytes hits `if (load8(src + i) != 39) { return 0; }` and
  exits in two instructions. The flag check is one load + one
  compare; turning the flag off restores 1.2.0 behaviour
  bit-for-bit.
- **Themes can highlight char literals as one token.** A theme
  that wanted to colour `'\n'` as a single string accent can
  now do so without re-scanning the text.
- **Hex escapes don't validate the digits.** The matcher trusts
  the closing `'`. This is deliberate: validating `[0-9a-fA-F]`
  on the two body bytes adds branches without value — an
  invalid hex literal isn't *valid C/Rust/Go either*, and the
  scanner is a tokenizer, not a validator.

### Negative

- **No support for `'\u{H...}'` Rust unicode escapes yet.** Not
  in the vidya corpus; if a future Rust sample needs them, the
  helper grows a fourth case. Until then, `'\u{1F600}'` would
  fail the closing-quote check and fall through to the operator
  step, producing `'` + `\u{1F600}'` (which itself would
  fragment further). Documented limit; not encountered in
  practice.
- **Empty `''` is rejected** (`b1 == 39` check in the helper).
  This is correct for C/Rust/Go/Zig — `''` is invalid in all
  four languages — but if a hypothetical future grammar wanted
  empty char literals, the check would need a flag.
- **Grammar-record ABI bumped** from 144 to 152 bytes. Same
  story as ADR 0009: no consumer reads the in-memory `Grammar`,
  only the public `tokenize_source` / `tokenbuf` API.

### When to revisit

- If `'\u{H...}'` shows up in any sampled corpus, extend the
  helper's backslash branch.
- If a Python ADR ever wants `b'x'` byte-char literals to also
  collapse, the same matcher works after a Python-specific
  prefix-byte check (or the Python grammar gets its own
  `byte_char_literal` flag).
- If the scanner ever moves to a length-indexed dispatch for
  performance (the M5 streaming work), step 7b stays an explicit
  branch — its lookahead is non-prefix-keyed.
