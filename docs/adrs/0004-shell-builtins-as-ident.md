# ADR 0004 — Shell built-ins emit as `ident`, not `keyword`

- **Status:** Accepted
- **Date:** 2026-04-23
- **Deciders:** M1 agent (proposed) / user (accepted)
- **Relates to:** [vyakarana-design-spec.md](../../vyakarana-design-spec.md)
  §3 (Token Kinds), [ROADMAP.md](../../ROADMAP.md) M4

## Context

Bash distinguishes two categories of special words:

- **Reserved words** (`if`, `then`, `else`, `fi`, `for`, `while`,
  `until`, `do`, `done`, `case`, `esac`, `in`, `function`,
  `return`, `break`, `continue`, `select`, `time`). Parsed
  specially by bash — you cannot alias or override them.
- **Built-in commands** (`local`, `declare`, `readonly`, `export`,
  `unset`, `set`, `eval`, `source`, `.`, `true`, `false`, `echo`,
  `printf`, `test`, `[`, `cd`, etc.). Parsed as ordinary command
  invocations — shadowable, aliasable, redefinable.

The vyakarana palette (design-spec §3) defines `keyword` as
"language-reserved words (`if`, `fn`, `return`, ...)." The two
options for handling the built-ins:

1. Emit built-ins as `keyword` — matches what many terminal
   highlighters do by default.
2. Emit built-ins as `ident` — matches the design-spec's strict
   definition of `keyword`.

## Decision

**Emit built-ins as `ident`.** Only reserved words hit the
`is_shell_keyword` lookup in `src/grammars/shell.cyr`. `local`,
`declare`, `export`, `set`, `eval`, `true`, `false`, and similar
are `ident`.

This preserves the palette semantics: a `keyword` token means the
grammar cannot legally replace it with another word and have the
program mean the same thing. A built-in fails that test — you can
`local() { : ; }` and redefine `local`.

## Consequences

### Positive

- **Palette has a consistent meaning across languages.** When M3
  adds Python, Rust, C, etc., "`keyword` means reserved" holds
  uniformly. A theme author who learns the palette by reading one
  grammar's tokens understands every grammar's tokens.
- **Grammars are smaller.** The keyword list is a finite, well-known
  set; built-in lists are open-ended (every shell adds its own).
  We don't inherit the maintenance burden of tracking bash / zsh /
  dash / busybox sh built-in drift.
- **Error-kind discipline.** A passing grammar has zero `error`
  tokens and a bounded `keyword` count. If `local` later becomes
  a reserved word in some shell dialect, that's a keyword-list
  edit, not a semantic shift.

### Negative

- **Terminal highlighter convention mismatch.** Many editors color
  `local` / `declare` / `export` like keywords out of the box.
  vyakarana users who want that look will need to do it at the
  theme layer (see below).

### How theme authors get the "look"

M4 is explicitly the theme-palette contract work between vyakarana
and owl. That contract includes room for **secondary palettes**:
after the primary palette slot is chosen by token `kind`, a theme
can introspect token text and apply a secondary color — e.g., "if
kind is `ident` and text is one of `local|declare|export|readonly`,
use the `builtin` accent." This is how themes add distinctions
finer than the 10-slot floor, without forcing vyakarana to grow
the palette.

Design-spec §3.1 already anticipates this:

> Finer distinctions are a theme concern. If a user wants
> keyword-control colored differently from keyword-declaration, the
> theme layer can introspect token text and apply a secondary
> palette.

This ADR is the same argument applied to built-ins.

### When to revisit

**M4** (theme-palette contract). If owl's palette layer can't
cleanly surface built-ins via token-text rules, reconsider. Until
then, `ident` is the correct kind.
