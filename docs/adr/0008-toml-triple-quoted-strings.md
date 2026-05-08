# ADR 0008 — TOML grammar handles triple-quoted strings

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** modernization-survey agent (proposed) / user (accepted)
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md)
  (rule-type scope), `grammars/toml.cyml`,
  `vidya/content/<topic>/concept.toml`

## Context

The TOML 1.0 spec defines four string forms:

- Basic single-line `"..."` — escapes via `\`.
- Literal single-line `'...'` — no escapes.
- **Basic multi-line `"""..."""`** — escapes via `\`, allows
  embedded newlines, treats a trailing `\` at end-of-line as a
  line-continuation.
- **Literal multi-line `'''...'''`** — no escapes, allows
  embedded newlines.

The original `grammars/toml.cyml` only covered the two single-line
forms. The header note marked the multi-line forms "out of scope
for the first pass (not in the vidya corpus)" with a deferred
ADR. The 1.0.3 modernization survey ran `vyk --language=toml`
against `vidya/content/compression/concept.toml` and found
**188 `error` tokens**, all of them content bytes inside a
`content = '''…multi-line prose…'''` block — vidya's content files
embed long prose with `'''` literal multi-line strings as the
preferred form. Every `concept.toml` in the corpus uses them.

## Decision

**Add two `match = "pair"` rules to `grammars/toml.cyml`, ordered
before the existing single-quoted rules:**

```toml
[[rules]]
kind = "string"
match = "pair"
start = "\"\"\""
end = "\"\"\""
escape = "\\"

[[rules]]
kind = "string"
match = "pair"
start = "'''"
end = "'''"
```

The pair-matcher (`_ds_try_pair_rules` in
`src/grammars/default_scanner.cyr`) walks rules in declaration
order and takes the first whose `start` prefix matches the cursor.
Triple-quoted starts must precede single-quoted starts so that
`"""` doesn't first match the `"…"` rule and emit the empty
string `""` followed by an error.

The basic form (`"""…"""`) keeps the `\\` escape so that an
escaped `\"` inside the body doesn't prematurely end the string.
The literal form (`'''…'''`) takes no escape — TOML's literal
strings are uninterpreted.

## Consequences

### Positive

- **Zero `error` tokens on `vidya/content/compression/concept.toml`**
  (was 188). Seven other vidya `concept.toml` samples also come
  back at zero. The coverage / no-error invariant holds for the
  bulk of the TOML corpus.
- **No scanner-code change required.** This decision lives entirely
  in the grammar file, demonstrating the M2 promise: "new
  language-level shape = new `[[rules]]` entry, not new Cyrius
  code."
- **Simple greedy match.** The first occurrence of `"""` (or
  `'''`) closes the string. TOML allows up to two consecutive
  quotes inside a multi-line literal, but never three, so this
  simple rule matches the spec.

### Negative

- **No special handling for the line-continuation backslash
  (`\` at end-of-line in a basic multi-line string).** That escape
  collapses the newline at parse time but is invisible at the
  tokenizer level — the scanner already covers the `\` + next-byte
  pair via the `escape = "\\"` setting, so the `\\\n` sequence
  passes through inside the string span. A grammar consumer that
  wants the source-level shape sees the raw bytes; one that wants
  the parsed value re-runs the body through TOML's own escape
  rules.
- **No nesting awareness for the rare 4-or-5-quote run that TOML
  permits at the *end* of a basic multi-line string** (e.g.
  `"""ends with two quotes""""""`). The greedy match closes at the
  first `"""`, leaving the trailing `""` outside the string. Not
  observed in the vidya corpus; if a real file hits it, the fix
  is in the matcher (recognise up-to-two-trailing-quotes), not
  the grammar.

### When to revisit

If a future TOML corpus surfaces line-continuation escapes that a
consumer needs to see at the token level, or the trailing-quotes
edge case actually appears, extend the pair-rule semantics. Until
then, the simple matcher is correct enough for the corpus and the
spec's common case.
