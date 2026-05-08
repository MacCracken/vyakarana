# 002 — Scanner pipeline priority order

> **Affects:** every grammar's token output. The same `.cyml`
> file produces different results if the pipeline order shifts,
> even when no individual rule changes.

## What it is

`tokenize_with_grammar` in `src/grammars/default_scanner.cyr`
walks the source byte by byte. At each cursor position, it tries
the steps below in order. The first step that returns a non-zero
`len` wins, sets the token's `kind`, and the cursor advances by
`len`.

| #  | Step                                         | Source                                              |
|----|----------------------------------------------|-----------------------------------------------------|
| 0  | Compose rules (recursive — push start marker, inner-grammar body, end marker) | `[[rules]] match = "compose"` (HTML → CSS / JS) |
| 1  | Shebang (`#!…\n` at file start)              | `[defaults] shebang = true`                         |
| 2  | Line rules                                   | `[[rules]] match = "line"` (e.g. `#`, `//`)         |
| 3  | Pair rules                                   | `[[rules]] match = "pair"` (strings, block comments)|
| 4  | Special var `$X` (2-byte)                    | `[defaults] special_vars = true` (shell only)       |
| 5  | Lone `$` operator (1-byte, shell-only)       | falls out of step 4                                 |
| 6  | Identifier / keyword                         | `[defaults] ident_start` + `[[rules]] match="words"`|
| 7  | Number                                       | `[defaults] number_decimal/0x/0b/0o`                |
| 7b | Char literal `'C'` / `'\C'` / `'\xHH'`       | `[defaults] char_literal = true` (C/Rust/Go/Zig)    |
| 8  | Operator (longest-match)                     | `[defaults] operators = […]`                        |
| 9  | Punctuation (longest-match)                  | `[defaults] punctuation = […]`                      |
| 10 | Whitespace                                   | `[defaults] whitespace = true`                      |
| 11 | Fallback `TK_ERROR + 1 byte`                 | always present (closes the coverage invariant)      |

## Why this order is normative, not incidental

The numbering matters because step priorities resolve real
ambiguities:

- **Compose rules before everything else.** A compose rule's
  `start` marker (e.g. `<style>` for HTML → CSS) would
  otherwise be tokenized byte-by-byte by the outer grammar's
  normal pipeline (`<` op + `style` ident + `>` op). The
  compose rule needs to claim those bytes first to switch
  grammars on the body. See [ADR 0013](../adr/0013-grammar-composition-rule.md).
- **Line and pair rules before ident.** `// foo` in a C grammar
  has to be recognised as a comment-start pair *before* `f` is
  consumed as an ident-start byte. Same for `"hello"` — without
  pair rules running first, the leading `"` would fall through
  to operators (or the error fallback).
- **Pair rules before the operator list.** If `"""…"""` (TOML
  multi-line string) ran *after* operators, the `"""` start
  would partially match `"` as an operator and never find the
  pair rule's start prefix. See [ADR 0008](../adr/0008-toml-triple-quoted-strings.md)
  for why this order locked in the rule-list ordering it did.
- **Ident before number.** Otherwise `e1` (a perfectly valid
  ident in most languages) would match number-with-exponent
  rules. Numbers only enter when the cursor sits on a digit.
- **Char literal before operator.** Step 7b is the only step
  that can claim a `'` byte; the operator step would otherwise
  take it as a 1-character operator. Step 7b returns 0 (yields)
  when there's no closing `'` at the right offset, which is what
  preserves Rust's lifetime tokenization (`'a`, `'static`). See
  [ADR 0010](../adr/0010-char-literal-default.md).
- **Operator before punctuation.** Operators and punctuation
  share a longest-match dispatch (`_ds_try_exact_list`); putting
  operators first means a token like `,` (operator in some
  grammars, punctuation in others) lands as whichever the grammar
  declared first in its operator list — a deliberate choice, not
  a tiebreak.
- **Whitespace late, fallback last.** Whitespace runs collapse
  *after* every structural rule has had a turn so that a
  mid-token space (rare but possible in a future grammar) can be
  caught by the structural rule rather than fragmented. The
  fallback is dead last because by definition we got there only
  if nothing else matched.

## Why it's not derivable from code

The pipeline is a flat sequence of `if (len == 0) { … }` blocks
in one `while (i < src_len) {}` loop. A reader can see the order,
but they cannot tell from the code alone *which orderings would
break correctness* and which are arbitrary. This note is the
"why" behind the chain.

## When it can break (and how to spot it)

- **Adding a new rule type.** A new `match = "pair-prefix"` or
  similar must slot into the pipeline at the right priority. If
  it's a structural shape (string-like, comment-like), it goes
  before step 6. If it's a class extension (more idents, more
  numbers), it goes between 6 and 9.
- **Reordering by accident during a refactor.** The 11 steps look
  like a linear list and "obviously" any order would do. Break
  one of the cases above and the smoke gates catch it; break a
  case the gates don't cover and you'll ship a regression.
- **A grammar relying on punctuation-before-operator.** Today
  there are none. A future grammar that wants this needs an ADR.

## Cross-references

- [ADR 0005](../adr/0005-m2-rule-type-scope.md) — why these are
  the rule types we have, not regex.
- [ADR 0008](../adr/0008-toml-triple-quoted-strings.md) — concrete
  example of why pair rules come before operators.
- `src/grammars/default_scanner.cyr` — the inline comments
  numbering each step are kept in lock-step with this note. If
  the inline comments and this note disagree, the source wins
  *and* this note needs an update.
