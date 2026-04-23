# Contributing to vyakarana

Thanks for wanting to help vyakarana see more grammar.

## Prerequisites

- Cyrius toolchain 5.6.0+ (`cyrius` on `$PATH`) — <https://github.com/MacCracken/cyrius>
- A POSIX-ish host (Linux primary; macOS best-effort). vyakarana targets
  AGNOS long-term, but the development shape is portable.

## Development Workflow

1. Fork and clone
2. `cyrius deps` — vendors stdlib into `lib/`
3. Branch from `main`
4. Make your change
5. `sh scripts/smoke.sh build/vyk` and `cyrius test tests/vyakarana.tcyr` before opening a PR
6. Reference the ROADMAP milestone your change belongs to

## Build / Test / Smoke

```sh
cyrius deps
cyrius build src/main.cyr build/vyk
cyrius test  tests/vyakarana.tcyr
sh scripts/smoke.sh build/vyk
```

There is no Makefile — `cyrius <subcommand>` is the whole build system.
Never shell out to `cc5` directly.

## Token-kind palette is stable

The ten token kinds in `src/token.cyr` are load-bearing for downstream
consumers and for every grammar author. **Do not add new kinds in a
patch release.** If a grammar cannot express what it needs with the
existing ten, open an issue describing the missing distinction before
opening a PR — the answer is often "the theme renderer can distinguish
that; the tokenizer should not."

## Grammar format decisions

vyakarana grammars are CYML, not TextMate / Sublime / tree-sitter.
Design reasoning lives in `vyakarana-design-spec.md`. When adding a new
bundled grammar, start from the shell grammar shipped in M1 and copy
its shape. Don't invent a new structure ad-hoc.

## Zero-copy discipline

Tokens are `(kind, start, len)` into the caller's source buffer. No
token may own an allocated string — if your grammar needs to
normalize (lowercase keywords, strip quotes, resolve escapes) that's
the consumer's job, not vyakarana's. This is non-negotiable for
streaming tokenization.
