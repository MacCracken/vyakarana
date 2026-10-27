# 0030 — Heredoc rule: computed closers and Ruby / PHP terminators

- **Status:** Accepted
- **Date:** 2026-10-27
- **Deciders:** 2.9.5 variable-length-delimiter work (proposed) / user
  (accepted via the 2.9.5 roadmap entry)
- **Relates to:** [ADR 0023](0023-heredoc-rule.md) (the heredoc rule,
  whose "When to revisit" this answers), [ADR 0027](0027-prefixes-lead-bytes-next-byte-rules.md)
  (raw-string prefixes, which left `r#"…"#` and `R"d(…)d"` out),
  [ADR 0028](0028-streaming-holds-watches-groups.md) (holds and
  watches), `src/grammar.cyr`, `src/grammars/default_scanner.cyr`,
  `src/tokenize.cyr`

## Context

Six literal shapes end at a closer that depends on the opener, so no
pair rule (a fixed `start` / `end`) can express them:

- **Counted runs:** Rust `r#"…"#` / `br##"…"##`, Swift `#"…"#` /
  `#"""…"""#`, Lua `[==[…]==]` and `--[==[…]==]` — the closer repeats the
  opener's run of `#` or `=`.
- **A captured tag:** C++ `R"d(…)d"` (and `u8R`, `uR`, `UR`, `LR`).
- **Line terminators with other rules than shell's:** Ruby `<<EOS`,
  `<<-EOS`, `<<~EOS` (an indented terminator may follow spaces) and PHP
  `<<<EOT` / `<<<'EOT'` (since PHP 7.3 the terminator may be indented
  and followed by code: `EOT;`).

Through 2.9.4 each came back as operators, identifiers and strings; a
Rust raw string holding quotes surfaced `error` tokens (2 of 5,166
sampled real files at the 2.9.x audit). ADR 0023 said to extend the
heredoc rule's options rather than add a second mechanism, and ADR 0027
pointed raw strings here.

## Decision

`match = "heredoc"` gains a second body form and options for the first.
No new rule type, no new token kind.

**`body = "line"`** (the default: ADR 0023's here-document — the body is
the lines after the opener, up to a terminator line). New keys, each
off by default so shell is unchanged:

- `indent` may list several marker bytes (`"-~"`); any one of them after
  `start` allows an indented terminator.
- `indent_by = "blanks"` — an indented terminator may follow spaces and
  tabs (default `"tabs"`, shell's `<<-`).
- `indent_always = true` — the terminator may be indented with no marker.
- `term_rest = true` — the terminator line may go on after the delimiter
  *(2.9.12: only with `indent_by = "blanks"` and `delim = "ident"`, the
  only combination it worked in; and an inline rule whose `repeat` byte
  is its `open`'s first is refused — it never matched)*
  at a byte that cannot continue an identifier (`EOT;`, `EOT)`); the
  token ends after the delimiter and the rest of the line is code.
- `delim = "ident"` — the delimiter is a bare identifier
  (`[A-Za-z_][A-Za-z0-9_]*`, and bytes 0x80 and above, as Ruby and PHP
  take them — *amended 2.9.12*, the code always did) or the bytes
  between a matching `'`, `"` or
  `` ` `` on the opener line, not a bash word with quote removal — so
  `<<~EOS.strip` is the delimiter `EOS`, then `.strip`.
- `blanks = false` — the delimiter must follow `start` (and a marker)
  directly: Ruby's `x << y` and `class << self` stay operators.

Opted in: ruby (`<<`; markers `-~`, by blanks; ident; no blanks), php
(`<<<`; always indentable by blanks; `term_rest`; ident). The
terminator lookup's line index has two more keys beside exact and
tab-stripped — blank-stripped, and the blank-stripped leading
identifier for `term_rest` — each built on its first lookup, as the two
halves are since 2.9.4; the drain's terminator watch (mode 1) compares
the same four.

**`body = "inline"`** — the token runs from the opener to a closer
computed from it, on the same line or a later one, with no escapes:

- `repeat = "#"` — after `start`, a run of one to 255 of that byte, then
  `open`; the closer is `close`, the same run, then `close_end`. `start`
  may be omitted, the run then being the opener's first bytes.
- `tag = true` — after `start`, a tag of up to 16 bytes other than
  blanks, `(`, `)`, `\` and control bytes, then `open`; the closer is
  `close`, the tag, then `close_end`.

Opted in: rust `r#"…"#` (and `br`, `cr`), swift `#"…"#` and
`#"""…"""#`, lua `[=[…]=]` and `--[=[…]=]`, cpp `R"d(…)d"` (and `u8R`,
`uR`, `UR`, `LR`). The zero-run forms — `r"…"`, `"…"`, `[[…]]` — keep
their raw prefixes and pair rules. Inline rules run at step 1b, after
the shebang and before line rules, so `--[==[` beats Lua's `--` comment
and `u8R"` beats the identifier step. An inline literal with no closer
runs to the end of the input, as an unterminated pair does.

**Streaming.** An inline opener cut by the buffer's end (`r##` with the
quote still to come) holds from its first byte with no watch: the next
drain re-scans only those bytes. An unterminated one holds with a
mode-3 watch for its closer — copied into the stream, since the
scanner's copy is scratch another stream's scan may overwrite — under
`VYK_COMPOSE_HOLD_MAX`. Line heredocs keep ADR 0023's hold and the
mode-1 / mode-2 watches.

**Out of scope.** Swift's `\#"` escape inside `#"…"#` (`#"\#"#"#` closes
at the first `"#`); Ruby `<<~` indentation removal and PHP
interpolation (the body is one string, as ADR 0003); Perl and Crystal
heredocs.

## Consequences

### Positive

- One string (or comment) token per raw literal and per Ruby / PHP
  heredoc body, in six grammars, with no change to shell.
- The streaming invariants hold for the new shapes at every split
  (`fuzz/chunk_invariance.fcyr`).

### Negative

- Token boundaries change for rust, swift, lua, cpp, ruby and php inside
  these literals — shipped in a patch, like ADR 0027's.
- The heredoc rule now has two meanings for `body`, and the line form
  six more options; `src/grammar.cyr`'s validation rejects the
  combinations that would do nothing.

### When to revisit

- Perl (`<<"EOT"`, `<<~EOT`) or Crystal heredocs, with the line options
  above.
- Swift's `\#` escapes, if a consumer's raw strings close early.
