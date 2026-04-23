# vyakarana

> **Picking this repo up?** Read [HANDOFF.md](./HANDOFF.md) first.
> It's the landing pad between M0 (scaffold) and M1 (first working
> grammar) with explicit exit criteria, locked invariants, and
> pending decisions.

Written in [Cyrius](https://github.com/MacCracken/cyrius).

Source-code grammar / tokenizer library. Consumers: **owl** (M3b), **cyim**
(planned editor), **vidya** (reference-library rendering + corpus supplier),
potentially **agnoshi** and **muharrir** downstreams.

**vidya relationship is reciprocal:** vidya supplies test corpus
(`content/lexing_and_parsing/*`), vyakarana consumes it. Don't break
this — a grammar that can't round-trip its vidya sample cleanly isn't
a passing grammar.

## Build

```sh
cyrius deps && cyrius build src/main.cyr build/vyk
cyrius test tests/vyakarana.tcyr
sh scripts/smoke.sh build/vyk
```

## Key Facts

- Library-first. `src/main.cyr` is a thin demo (`vyk`); real consumers
  include the modules in `src/` via their Cyrius `[deps.vyakarana]` block.
- Source in `src/`, tests in `tests/`, stdlib in `lib/` (vendored, do not edit).
- Dependencies declared in `cyrius.cyml`.
- Toolchain pinned in `cyrius.cyml [package].cyrius`.
- Grammar format: Cyrius-native CYML. No TextMate, no tree-sitter.
- Token-kind palette is a small stable enum (10 kinds). Do not grow it
  without a design review — grammar authors and theme palettes both
  depend on stability.
- Token / Span layout is load-bearing for downstream consumers. Changing
  field order or width is a breaking change; bump minor accordingly.

## Language Notes

- `var buf[N]` is N bytes, not elements
- `&&`/`||` short-circuit; mixed requires parens: `a && (b || c)`
- No closures — use named functions
- Test exit pattern: `syscall(60, assert_summary())`

## Do Not

- Do not commit or push without user approval
- Do not modify files in `lib/`
- Do not depend on `owl` or any consumer — vyakarana is upstream of all of them
