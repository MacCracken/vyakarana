# vyakarana — agent working rules

> **Picking this repo up?** Read [HANDOFF.md](./HANDOFF.md) first
> for where we are and what's next. Architecture decisions are ADRs
> under [docs/adrs/](./docs/adrs/); design context is in
> [vyakarana-design-spec.md](./vyakarana-design-spec.md); milestone
> plan is [ROADMAP.md](./ROADMAP.md).

This file is process, procedure, and prefs only. Repo context and
invariants live in the docs above.

## Gates — run before trusting status

```sh
cyrius deps && cyrius build src/main.cyr build/vyk
cyrius test tests/vyakarana.tcyr
sh scripts/smoke.sh build/vyk
```

Run all three on session entry. Don't take `HANDOFF.md` / `README.md`
claims of "green" at face value until you've seen the commands
pass. Use `cyrius build`, never raw `cc5`.

## Cyrius dialect gotchas

- `if (cond) {` / `while (cond) {` — parens required
- `var buf[N]` is N bytes, not elements
- `&&` / `||` short-circuit; mixed requires parens: `a && (b || c)`
- No closures — use named functions
- Top-level args pattern: `args_init(); var ac = argc(); var a = argv(i);`
  (not `fn main(argc, argv)`)
- `cyrius.cyml [deps] stdlib = [names]` auto-prepends the listed
  modules — only the ones named, not all of stdlib. Add what you
  need to the list; don't re-`include "lib/..."` for modules
  already in it. For single-file programs outside a project (e.g.
  `cyrius/programs/*.cyr`), explicit `include "lib/..."` at the
  top is the pattern. See yukti's `cyrius.cyml` for a fuller
  example of `[deps] stdlib`, `[deps.<name>]` git deps, and
  `[lib] modules = [...]` for distlib.
- Test exit pattern: `syscall(60, assert_summary())`
- When dialect is unclear, read `cyrius/programs/*.cyr` — that's
  the authoritative working reference

## Do not

- Do not commit or push without user approval
- Do not modify files in `lib/` (vendored stdlib; re-synced by
  `cyrius deps`)
- Do not depend on `owl` or any consumer — vyakarana is upstream
- Do not add a token kind or change the `Token` layout without an
  ADR under `docs/adrs/` and a CHANGELOG entry
- Do not take three failed attempts at the same problem — stop,
  open an ADR (if the decision is load-bearing) or a `TODO(M?)`
  note, and defer

## Writing decisions

- If a choice will confuse a future agent ("why did they do it that
  way?"), open an ADR: `docs/adrs/NNNN-short-kebab-title.md`.
  Format: see [docs/adrs/README.md](./docs/adrs/README.md).
- Small implementation notes go in the relevant source file's
  header comment, not an ADR.
