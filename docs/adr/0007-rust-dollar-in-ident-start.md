# ADR 0007 — Rust grammar treats `$` as `ident_start`

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** modernization-survey agent (proposed) / user (accepted)
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md)
  (rule-type scope), `grammars/rust.cyml`,
  `vidya/content/macro_systems/rust.rs`

## Context

Rust's [Reference grammar][ref-ident] defines an identifier as
starting with `XID_Start` (or `_`) and continuing with `XID_Continue`.
`$` is not in either class. The Rust compiler does not let you
write `let $x = 1;` or call `fn $foo()` — `$` only appears in source
code inside `macro_rules!` expansions, where:

- `$ident:fragment` introduces a captured metavariable
  (`$x:expr`, `$tok:tt`, `$lit:literal`, …).
- `$ident` references one inside the macro body
  (`format!("{}", $lit)`).
- `$( … )* / $( … )+ / $( … )?` mark repetition groups.
- `$crate` is a hygiene-aware path token.

[ref-ident]: https://doc.rust-lang.org/reference/identifiers.html

The 1.0.3 modernization survey ran `vyk --language=rust` against
`vidya/content/macro_systems/rust.rs` and found **79 `error`
tokens**, all of them the bare `$` byte. The macro idiom is
ubiquitous in real Rust — `vec!`, `println!`, `format!`,
`derive`-style proc macros, and almost every domain crate uses
`macro_rules!` somewhere — so this is not a corner case.

The vyakarana scanner has no lexer state, no lookahead beyond the
multi-byte operator table, and no notion of "we are inside a
`macro_rules!` body." The two pragmatic options are:

1. **Treat `$` as a 1-byte operator.** Same shape as `'` and `?`
   today. `$tok` would tokenize as `op($) + ident(tok)`. No errors;
   coverage holds. But a theme cannot color the whole metavariable
   uniformly — it sees `$` and `tok` as unrelated tokens.
2. **Treat `$` as `ident_start` only in the Rust grammar.** `$tok`
   tokenizes as a single `ident("$tok")`. Bare `$` (the leading
   marker of `$( … )*`) becomes a 1-character ident, since `(` is
   not in `ident_cont`.

## Decision

**Add `$` to `ident_start` in `grammars/rust.cyml`** (option 2).
`ident_cont` is unchanged because real Rust source never has `$`
mid-identifier — adding it there would just be unused breadth.

## Consequences

### Positive

- **Zero `error` tokens on `vidya/content/macro_systems/rust.rs`**
  (was 79). Gates remain green and the no-error invariant holds for
  one of the most aggressively macro-using files in the corpus.
- **Themes can highlight `$tok` as one identifier.** Whether a
  downstream renderer wants to give metavariables their own accent
  is a secondary-palette decision (per ADR 0004's pattern) — it can
  introspect token text and check the `$` prefix.
- **No new scanner state.** The `[defaults]` ident-class machinery
  already exists; this is a one-character change to a string.
- **No change to other grammars.** `$` stays out of `ident_start`
  for shell (where it is the variable-expansion sigil and tokenizes
  via `special_vars = true`), Python, C, Go, etc.

### Negative

- **Diverges from the Rust Reference's identifier definition.**
  A reader who learns `ident_start` from the Reference will see `$`
  and ask why. The grammar header points to this ADR.
- **`$` outside a `macro_rules!` block — which is invalid Rust —
  tokenizes as ident, not error.** vyakarana is a tokenizer, not a
  validator; it tokenizes invalid Rust the same way it tokenizes
  invalid C, in line with the design-spec's "no errors on
  ill-formed input" stance. A real Rust parser will reject the
  program for unrelated reasons.

### When to revisit

If the scanner ever gains lexer state (e.g. a `macro_rules!`-aware
mode for proper hygiene context tracking), this rule could be
narrowed to "in macro context only." Until then, the grammar-level
character-class fix is the correct level of abstraction.
