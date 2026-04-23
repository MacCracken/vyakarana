# ADR 0003 — Shell string expansions are not re-tokenized in M1

- **Status:** Accepted
- **Date:** 2026-04-23
- **Deciders:** M1 agent (proposed) / user (accepted)
- **Relates to:** [vyakarana-design-spec.md](../../vyakarana-design-spec.md)
  §5 (Grammar Format), [ROADMAP.md](../../ROADMAP.md) M2

## Context

Bash strings are not inert. A double-quoted string can contain
parameter expansion (`"${x}"`), command substitution (`"$(cmd)"`),
arithmetic expansion (`"$((x + 1))"`), and plain variable references
(`"$var"`). A grammar has two reasonable ways to handle them:

1. **Flat.** The entire `"..."` run is one `string` token; whatever
   sits inside is covered by that token's bytes.
2. **Nested.** Emit a `string` token for each inert run and recurse
   into each expansion, producing ident/operator/punctuation tokens
   inside.

M1 is hand-coded Cyrius. Nested recursion means a second tokenizer
state (parsing context) stacked inside the main scanner, plus rules
for how operators behave inside expansions vs. outside, plus a
decision about whether single-quoted strings recurse (they shouldn't —
bash's `'...'` is literal).

The grammar palette has 10 kinds and a coverage invariant. Flat
handling is correct under both; nested handling is strictly more
work to get right.

## Decision

**Flat, in M1.** The whole `"..."` (or `'...'`) run is emitted as a
single `string` token. Backslash escapes are honored inside
`"..."` only; `'...'` is consumed verbatim to the next `'`.

Expansion contents (`${x}`, `$(cmd)`, `$((…))`) inside strings are
NOT re-tokenized. They're part of the enclosing string's bytes.

Expansions **outside** strings (e.g. bare `$VAR` on its own)
tokenize normally — that's handled by the `$X` / `$` operator
rules in the main scanner, not by string recursion.

## Consequences

### Positive

- **Simpler M1 recognizer.** One scanner, no parse stack, no
  context-dependent rule set. Clean match of the design-spec §5
  rule types (`line`, `pair`, `words`) — all of which M1 uses
  without regex.
- **Faster.** A string is one scan-and-emit; a nested string is a
  mini-tokenize per expansion.
- **Matches most terminal highlighters.** Shells like zsh highlight
  whole strings as one color unit; themes that want to surface
  expansions do it via post-processing on token text.

### Negative

- **Theme authors can't distinguish `"${x}"`'s `${x}` at the token
  level.** They'd need to re-parse string bytes themselves to add
  an accent color to the variable reference. This is a real
  limitation for rich theming, but not one M1 promises to solve.
- **One less pattern exercised.** We don't build a composition
  muscle in M1 that M2's CYML loader or M3's other languages (e.g.
  Markdown fenced code blocks) will eventually need.

### When to revisit

**M2 — CYML grammar loader.** If the rule type set grows a "nested
grammar" or "sub-scanner" rule (design-spec §5 does not include
one today), the shell grammar's `.cyml` re-expression can add
nested rules for `${…}` / `$(…)` / `$((…))`. The hand-coded M1
tokenizer remains on disk as a regression reference; its output
stays byte-identical to M2's CYML-driven output until we
explicitly decide to change the contract.

**M3 — Markdown.** Fenced code blocks are the other natural
motivator for sub-grammars. If M3 wants Markdown code fences to
route into the fenced language's grammar, nested-grammar support
lands then — and shell strings can ride along.
