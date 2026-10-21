# 0024 — Char-literal escape forms beyond `'\C'` / `'\xHH'`

- **Status:** Accepted (amends [ADR 0010](0010-char-literal-default.md))
- **Date:** 2026-10-20
- **Deciders:** 2.5.2 closeout audit (proposed and shipped in 2.5.2) /
  user (accepted with 2.5.2); recorded here in 2.6.0
- **Relates to:** [ADR 0010](0010-char-literal-default.md),
  `src/grammars/default_scanner.cyr` (`_ds_try_char_literal`,
  `DS_CHAR_LITERAL_MAX`), `src/tokenize.cyr` (`_stream_max_marker`),
  [2.5.2 audit](../audit/2026-10-20-2.5.x-closeout-audit.md) P1-2 / P3

## Context

ADR 0010 made `char_literal = true` recognise four shapes: `'C'`,
`'\C'`, `'\xHH'`, and a quoted UTF-8 character. Real code has more:

- C's octal escapes — `'\033'` (ESC, in every ANSI-colour helper),
  `'\0'` is fine but `'\177'` is not;
- Java / Kotlin `'\u0041'`, C / C++ `'\U0001F600'`;
- Rust `'\u{2026}'` (the 2.5.2 real-file sweep found it emitting
  `TK_ERROR`, making `vyk` exit 1).

Each fell through to the `'` operator and split the literal. 2.5.2
widened the escape branch and said "ADR 0010 amended" in its CHANGELOG
and in the scanner — but ADR 0010 was never edited, and the ADR index
forbids editing an Accepted ADR in place. This ADR is that record.

## Decision

For `'\…'`: the byte after `\` is always part of the escape (so `'\''`
and `'\\'` still close at 4 bytes); from there the literal closes at
the first `'` within `DS_CHAR_LITERAL_MAX` = 12 bytes total — enough
for `'\u{10FFFF}'` and `'\U0001F600'`. A newline, CR or a second `\`
before the quote means "not a char literal" and the `'` falls through
as before. Escape digits are not validated. The other three ADR 0010
shapes are unchanged. Rust lifetimes are unaffected — they never start
with `'\`.

`DS_CHAR_LITERAL_MAX` is also the streaming hold-back minimum for any
char-literal grammar (`_stream_max_marker`), so a literal split by a
chunk boundary is never committed half-seen — the 2.5.2 P1-2 fix
depends on the two staying equal, which is why the constant lives
beside the scanner.

## Consequences

### Positive

- `'\033'`, `'\u0041'`, `'\U0001F600'`, `'\u{2026}'` are one string
  token in every char-literal grammar (c, cpp, java, kotlin, rust, go,
  zig, ocaml, julia, crystal, csharp, swift, cyrius, asm).
  *(Amended 2.9.2: `'\u0041'` here and in the Context read `'A'` —
  the escape had been decoded.)*

### Negative

- A `'\` followed within 12 bytes by a stray `'` on the same line now
  reads as one literal even if the language would reject it. Same
  "trust the closing quote" stance ADR 0010 took for `'\xHH'`.

### When to revisit

- A language with a legal char-literal escape longer than 12 bytes.
