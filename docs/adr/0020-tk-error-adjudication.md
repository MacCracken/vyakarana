# 0020 — When `TK_ERROR` is correct and when it is a grammar hole

- **Status:** Accepted
- **Date:** 2026-07-31
- **Deciders:** proposed and accepted during the 2.3.2 error-hole audit
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md) (rule-type
  scope), [ADR 0009](0009-unicode-ident-default.md)
  (`unicode_ident`), [ADR 0010](0010-char-literal-default.md)
  (`char_literal`), [ADR 0006](0006-standin-corpus-policy.md)
  (stand-in corpora), `grammars/*.cyml`, `tests/vyakarana.tcyr`
  test group "2.3.2 TK_ERROR holes"

## Context

A sweep of every printable ASCII byte (0x20–0x7E) through all 45
bundled grammars found **44 emitting `TK_ERROR` for at least one
character**. The probe was `a <char> b`, one file per byte per
grammar.

`TK_ERROR` is a legitimate token kind, not a failure mode: it is
how the scanner reports a byte with no meaning in the language.
So "44 of 45 grammars emit it" is not by itself a bug report —
a backtick really is invalid in C. The audit needed a rule for
telling the two apart, applied per grammar and per character,
because the answer differs *within* a single character:
backtick is a raw string in Go, a command literal in Ruby, an
escaped identifier in Kotlin, a quoted identifier in MySQL, a
polymorphic-variant tag in OCaml, and genuinely invalid in C,
Lua, Python 3 and Rust.

Two things made this worth writing down rather than fixing
silently:

1. **The corpora hid all of it.** Each grammar has exactly one
   canonical sample. A shape a sample happens not to contain is a
   shape that twelve minor releases of green gates proved nothing
   about. `tests/corpus/asm_x86_64.s` is `.intel_syntax noprefix`
   and contains **zero** `$` characters — so AT&T immediates
   (`movq $60, %rax`), the dominant real-world x86-64 dialect,
   were never tokenized once. Real GNU as from `/usr/lib`
   produced 91 error tokens in a single file.
2. **The obvious over-correction is worse than the bug.** Adding
   every printable byte to every grammar's operator list would
   turn the sweep green and destroy the kind's meaning.

## Decision

**A character earns a place in a grammar when it appears in valid
source of that language in code position. Otherwise `TK_ERROR`
stays.** Comments and strings are already claimed by rules, so
"code position" is the whole question.

Applied in three tiers, in order of preference:

1. **A rule**, when the character opens a delimited region whose
   contents are not outer-grammar code — Go raw strings, Kotlin /
   Swift / MySQL backtick identifiers, Elixir charlists, Zig `\\`
   multiline strings, shell / Ruby / Crystal / PHP command
   substitution. Command substitution follows the precedent
   `grammars/julia.cyml` already set: `kind = "string"`, because
   the delimited bytes are a command, not code the outer scanner
   should re-tokenize. Identifier delimiters use `kind = "ident"`.
2. **An operator or punctuation entry**, when the character is a
   free-standing token — Haskell `$`, Rust `@` pattern bindings,
   OCaml `` ` `` variant tags, TOML `:` in RFC 3339 datetimes,
   JavaScript / TypeScript `#` and `@`.
3. **Nothing**, when the byte has no syntax in the language.

Two corollaries that fell out of the audit:

- **Where `'` opens a char literal rather than a string, `'` and
  `\` are operator fallbacks.** ADR 0010's scanner models `'C'`,
  `'\C'` and `'\xHH'`; every such language has at least one
  escape form outside that set (`'A'`, `'\u{1F600}'`), and
  without the fallback those fragment into `TK_ERROR`.
  `grammars/c.cyml` already did this; the rest had diverged.
- **Free-text formats have almost no invalid printable bytes.**
  HTML/XML element content, Vue/Svelte template text, YAML plain
  scalars and INI values are arbitrary characters. `<p>50% off —
  $5</p>` is not a markup error.

**Scope:** grammar files, one test-suite count assertion, and
corpus additions. No scanner change, no new rule type, no token
kind, no `Token` layout change, no public-API change.

**Explicitly not changed:** `c`, `cyml`, `cyrius`, `json`, `lua`,
`protobuf` and `terraform` came through the audit untouched —
every byte they reject really is invalid in those languages.
`python` is a half-case: its printable-ASCII rejections (`!`,
`$`, `?`, `` ` ``) are all correct and stand, and the file was
edited only for `unicode_ident`. `markdown` was fixed separately
in 2.3.1. Negative probes in `tests/vyakarana.tcyr` assert these
still error, so a later "just add every byte" change cannot
quietly pass the gates.

## Consequences

### Positive

- Measured against real source from `/usr/lib`, `/usr/share`,
  `/usr/include` and the cargo registry — not hand-written
  samples. Files with at least one error token, before → after:
  html 38/40 → 0, shell 7/40 → 0, zig 5/40 → 0, typescript
  9/40 → 0, javascript 11/40 → 0, yaml 8/40 → 0, go 4/40 → 1
  (the remaining file is binary testdata with a `.go` suffix),
  xml 5/39 → 0, css 1/40 → 0, cpp 2/40 → 0.
  `/usr/lib/go/src/runtime/race_amd64.s` went 91 → 0.
- The tier rule is mechanical enough to apply to a new grammar
  without re-litigating it, and the negative probes pin the
  half of the decision that is easy to erode.

### Negative

- A genuinely malformed byte in a free-text format no longer
  reports as an error — `vyk` will not exit 1 on a corrupt HTML
  or YAML file the way it did. That is correct for those
  formats, but it does mean `TK_ERROR` carries less signal there
  than in, say, `json`, which was deliberately left strict.
- Dialect soup is now resolved by inclusion rather than by
  choice. `sql` accepts MySQL backtick identifiers, `#`
  comments, PostgreSQL `$1` and `~` all at once, so it will not
  flag a genuine cross-dialect mistake. `#` is listed as a plain
  operator rather than a line-comment rule precisely so neither
  reading corrupts the other — a T-SQL `#temp` table must not
  become a comment.
- 37 of 45 grammars changed in one cut. Any consumer that pattern-matched
  on the old error tokens sees different output.

### When to revisit

- A consumer that needs strict validation rather than tolerant
  highlighting — that wants a real "is this valid?" answer —
  needs a separate mode, not a re-tightening of these grammars.
- If `sql` dialect blending causes a real complaint, split it
  into `mysql` / `postgres` / `tsql` rather than narrowing the
  shared grammar.
- The remaining known holes are *not* operator-list gaps and are
  out of this ADR's scope: Rust's nestable `/* */` block comments
  (backticks in doc comments still error), and variable-length
  delimiters (Lua `[==[`, Ruby/PHP heredocs, Swift raw strings)
  which `docs/development/state.md` already tracks for a
  collective ADR.
