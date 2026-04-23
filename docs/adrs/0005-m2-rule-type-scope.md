# ADR 0005 — M2 rule-type scope: narrow spec rules + configured default scanner

- **Status:** Accepted
- **Date:** 2026-04-23
- **Deciders:** M2 agent (proposed) / user (accepted)
- **Relates to:** [vyakarana-design-spec.md](../../vyakarana-design-spec.md)
  §5 (Grammar Format), [ROADMAP.md](../../ROADMAP.md) M2, M3

## Context

Design-spec §5 locks the M2 rule-type set to `line`, `pair`, `words`
(no regex). ROADMAP M2's "Done when" bar is that adding a new
language is a new `.cyml` file with zero Cyrius code.

M1 shipped the hand-coded shell tokenizer. The recognizer needed to
tokenize the vidya sample also produces: identifiers (char-class
runs), numbers (digits with `0x`/`0b`/`0o` prefixes), multi-char
operators and punctuation (longest-match lists), whitespace runs,
and shebang (column-0-of-line-0 only). None of those fit cleanly
into `line` / `pair` / `words`. There's no way to re-express shell
in CYML with only those three rule types and still produce
byte-identical tokens to the hand-coded M1 output.

Three directions were on the table:

- **(A) Narrow rule types + configured default scanner.** CYML
  exposes `line` / `pair` / `words` as `[[rules]]` entries, plus a
  `[defaults]` table that parameterizes a shared Cyrius "default
  scanner" (ident rule, number rule, operator list, punctuation
  list, whitespace, shebang). The scanner is Cyrius code; each
  grammar just picks which defaults are on and supplies the lists.
- **(B) Expand the rule-type set.** Add `chars` (char-class run),
  `exact` (fixed-sequence list with longest match), `shebang`
  (column-0-line-0 variant of `line`) so CYML literally expresses
  every token category. Amends design-spec §5.
- **(C) Narrow strictly per spec.** CYML handles only comments +
  strings + keyword lists; everything else still hand-coded.
  Regresses vs. M1 output — not a real M2.

## Decision

Adopt **option A**: narrow rule types plus a configured default
scanner.

### Concrete rule-type set for M2

CYML surface:

```cyml
[grammar]
name = "shell"
extensions = [".sh", ".bash"]
shebangs = ["sh", "bash", "zsh", "dash"]

[defaults]
shebang           = true        # emit `#!`-on-line-0 as preprocessor
whitespace        = true        # runs of space/tab/\n/\r
ident_start       = "A-Za-z_"   # char class, first byte
ident_cont        = "A-Za-z0-9_"
number_decimal    = true
number_0x         = true
number_0b         = true
number_0o         = true
special_vars      = true        # $# $? $@ $! $* $$ $-
operators         = [ ... longest-match ordered list ... ]
punctuation       = [ ... longest-match ordered list ... ]

[[rules]]
kind  = "comment"
match = "line"
start = "#"

[[rules]]
kind  = "string"
match = "pair"
start = "\""
end   = "\""
escape = "\\"

[[rules]]
kind  = "keyword"
match = "words"
words = [ "if", "then", "else", ... ]
```

### Scanner priority (applied each byte)

1. `[[rules]]` with `match = "line"` (for shebang via the `shebang`
   default, at column 0 of line 0 only)
2. `[[rules]]` with `match = "line"` (non-shebang)
3. `[[rules]]` with `match = "pair"` (strings)
4. `defaults.special_vars` (`$X` 2-char operator)
5. `defaults.ident_start`+`ident_cont` — with `[[rules]] match="words"`
   keyword lookup over the consumed run
6. `defaults.number_*` rules
7. `defaults.operators` (longest match)
8. `defaults.punctuation` (longest match)
9. `defaults.whitespace`
10. Fallback → `TK_ERROR`, length 1

Every step is data-driven by the grammar struct parsed from CYML.
A grammar that sets `ident_start = ""` simply skips the ident stage.

## Consequences

### Positive

- **Hits the ROADMAP bar.** A new language IS a new `.cyml` file
  with zero Cyrius code — the default scanner covers the shape every
  non-whitespace-sensitive language needs.
- **Preserves M1 regression guarantee.** The data-driven scanner
  will produce byte-identical tokens to `tokenize_shell` on the
  vidya sample; M2 ships green when the regression diff is empty.
- **Staged cost.** We're not designing a full rule-type algebra
  today. M2 proves the loader + configured scanner; if M3 reveals a
  language that needs something else (Markdown fenced blocks,
  Python indent/dedent), we add a new rule type at that point.

### Negative

- **Not all "data-driven."** `[defaults]` fields encode a fixed
  scanner shape. Languages that need a fundamentally different
  scanner (indentation, stateful lexers) can't be expressed without
  new rule types — which is fine because M3 hasn't hit that yet,
  but it's a limit to be aware of.
- **Amends design-spec §5 implicitly.** The spec lists only three
  rule types. `[defaults]` is a new surface that wasn't there. This
  ADR is the amendment; the next edit to the design spec should
  fold `[defaults]` in.
- **Test-corpus reach.** Default-scanner bugs surface on whatever
  language first needs them. M2 tests only against shell, so the
  scanner is only as general as shell demands. We'll find gaps in
  M3.

### Regression guard during M2

- Keep `src/grammars/shell.cyr` (hand-coded M1) on disk during M2
  development.
- Add a diff check to `scripts/smoke.sh` M2 section: run both
  `tokenize_shell` (hand-coded) and the data-driven scanner against
  `tests/corpus/shell.sh`; the token streams must be byte-identical.
- Delete `src/grammars/shell.cyr` in a follow-up after M2 ships,
  or leave it as a compile-checked oracle until M3 finishes.

### When to revisit

- **M3** — when adding Python / JS / Rust / etc. If a grammar
  can't be expressed with current `[defaults]` + `[[rules]]`, open
  an ADR extending the set.
- **M5** — streaming tokenizer may want to inline the
  default-scanner dispatch differently; the surface doesn't change.

### Design-spec update

This ADR supersedes the M2 portion of design-spec §5. A future spec
edit should replace "M2 rule types are line/pair/words" with a
pointer to this ADR, then enumerate the `[defaults]` surface.
