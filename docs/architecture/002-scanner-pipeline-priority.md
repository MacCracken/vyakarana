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
| H  | Queued heredoc bodies — at the first byte after a top-level line break that follows their opener(s); body + terminator line = one token each | `[[rules]] match = "heredoc"` ([ADR 0023](../adr/0023-heredoc-rule.md), shell, 2.6.0; ruby and php, 2.9.5, [ADR 0030](../adr/0030-heredoc-computed-closers.md)) |
| 0a | Compose rules (recursive — push start marker, inner-grammar body, end marker) | `[[rules]] match = "compose"` (HTML → CSS / JS) |
| 0b | Compose-fenced rules (info-string picks the inner grammar) | `[[rules]] match = "compose_fenced"` ([ADR 0016](../adr/0016-compose-fenced-rule.md), markdown ``` fences) |
| 0c | Compose-region rules (open-ended region from `start` — optionally only after a `start_after` byte, with `start_inner` keeping the marker in the body, 2.9.9 — up to an optional `end_before` lookahead or, with `end_blank`, a blank line (2.9.12), else to EOF) | `[[rules]] match = "compose_region"` ([ADR 0019](../adr/0019-compose-region-rule.md), CYML markdown bodies) |
| 1  | Shebang (`#!…\n` at file start)              | `[defaults] shebang = true`                         |
| 1b | Inline heredoc — a raw literal through the closer its opener computes (`r#"…"#`, `[==[…]==]`, `R"d(…)d"`) | `[[rules]] match = "heredoc"`, `body = "inline"` ([ADR 0030](../adr/0030-heredoc-computed-closers.md), 2.9.5) |
| 2  | Line rules — optionally only after a `start_after` byte, and only when the next byte is in `followed_by` / not in `not_followed_by` | `[[rules]] match = "line"` (e.g. `#`, `//`); `start_after` [ADR 0022](../adr/0022-line-rule-start-after.md) (shell `#` at word start, 2.6.0); next-byte keys [ADR 0027](../adr/0027-prefixes-lead-bytes-next-byte-rules.md) (2.7.1) |
| 3  | Pair rules                                   | `[[rules]] match = "pair"` (strings, block comments)|
| 4  | Special var `$X` (2-byte; X in `#?@!*$-` or `0`-`9`) | `[defaults] special_vars = true` (shell; digits since 2.6.0; makefile through 2.7.0) |
| 5  | Lone `$` operator (1-byte, shell-only)       | falls out of step 4                                 |
| 6  | Identifier / keyword — an `ident_lead` byte starts one only before an ident byte; a declared string prefix and the string after it are one `string` | `[defaults] ident_start` / `ident_cont` / `ident_lead` + `[[rules]] match="words"`; `string_prefixes` / `raw_string_prefixes` ([ADR 0027](../adr/0027-prefixes-lead-bytes-next-byte-rules.md), 2.7.1) |
| 6b | Symbol-shaped string prefix + string — C#'s `@"…"` (raw), `$"…"` | `[defaults] string_prefixes` / `raw_string_prefixes` entries that are not identifiers ([ADR 0027](../adr/0027-prefixes-lead-bytes-next-byte-rules.md), amended 2.9.6) |
| 7  | Number                                       | `[defaults] number_decimal/0x/0b/0o`; `number_float` / `number_separator` / `number_datetime` ([ADR 0026](../adr/0026-number-literal-shapes.md), 2.7.0); `number_tuple_index` (2.9.3); `number_lead_dot` (from a `.`) / `number_trail_dot` / `number_suffixes` (2.9.7) |
| 7b | Char literal `'C'` / `'\…'` (≤ 12 bytes) / UTF-8 | `[defaults] char_literal = true` ([ADR 0010](../adr/0010-char-literal-default.md), escape forms [ADR 0024](../adr/0024-char-literal-escape-forms.md)) |
| 7c | Heredoc opener — queues a body, consumes nothing | `[[rules]] match = "heredoc"` ([ADR 0023](../adr/0023-heredoc-rule.md)) |
| 8  | Operator — FIRST entry that matches, in list order (list longest-first; a test enforces it since 2.5.2) | `[defaults] operators = […]` |
| 9  | Punctuation — same first-match rule          | `[defaults] punctuation = […]`                      |
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
  share a first-match dispatch (`_ds_try_exact_list`), and the
  operator list is tried first: an entry in both lists comes back
  as an operator. A grammar decides whether `,` is an operator or
  punctuation by which list it puts it in — a deliberate choice,
  not a tiebreak.
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
