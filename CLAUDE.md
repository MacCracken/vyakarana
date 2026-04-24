# vyakarana — agent working rules

> **Picking this repo up?** Read [HANDOFF.md](./HANDOFF.md) first
> for where we are and what's next. Architecture decisions are ADRs
> under [docs/adrs/](./docs/adrs/); design context is in
> [vyakarana-design-spec.md](./vyakarana-design-spec.md); milestone
> plan is [docs/development/roadmap.md](./docs/development/roadmap.md).

This file is **process, procedure, and prefs only**. Repo state
(what shipped / what's next), invariants, consumers, and
architecture live in the docs above — cross-reference, do not
duplicate.

## Goal

Source-code tokenizer for the AGNOS stack. One-sentence mission:
take source bytes → yield `(kind, start, len)` spans into the
caller's buffer, fast and without surprises.

## Gates — run before trusting status

```sh
cyrius deps && cyrius build src/main.cyr build/vyk
cyrius test tests/vyakarana.tcyr
sh scripts/smoke.sh build/vyk
```

Run all three on session entry. Don't take `HANDOFF.md` /
`README.md` claims of "green" at face value until you've seen the
commands pass. Use `cyrius build`, never raw `cc3`/`cc5`.

## Work loop (continuous)

For every non-trivial change:

1. Read HANDOFF and the relevant ADRs — know what was intended.
2. Work phase — grammar, scanner tweak, test, docs fix.
3. Build + test: `cyrius build` then `cyrius test`.
4. Internal review — correctness, coverage invariant, zero-error
   bar on any corpus the change affects.
5. Smoke check — `sh scripts/smoke.sh build/vyk` after changes
   that touch runtime or grammar surface.
6. Documentation — update CHANGELOG `[Unreleased]`, HANDOFF if
   the status shifted, ROADMAP only on milestone boundaries.
7. Version check — `VERSION`, `cyrius.cyml`, CHANGELOG header
   stay in sync.
8. Return to step 1.

## Hardening step (before starting a new milestone or feature batch)

Between work cycles, before diving into the next milestone, run a
consolidation pass. This is the "slow down and take stock" step —
catch drift before it compounds.

1. Read HANDOFF, ROADMAP, CHANGELOG, and any open `TODO(M?)`
   markers — know what was intended.
2. Cleanliness check: `cyrius build`, `cyrius lint src/*.cyr`,
   `cyrius test`, `sh scripts/smoke.sh build/vyk` — all green.
3. Benchmark baseline (once a `tests/bcyr/*.bcyr` exists):
   `cyrius bench tests/bcyr/vyakarana.bcyr`. Save the CSV for
   comparison against post-milestone runs.
4. Internal deep review — re-read the scanner, grammar loader, and
   tokenbuf for gaps, cosmetic losses, or correctness drift.
   Cross-check every grammar's `.cyml` against its corpus for
   shape gaps (char-literals splitting, UTF-8 outside strings,
   unhandled operators).
5. External research — skim `cyrius/programs/*.cyr` for any new
   stdlib idioms worth adopting; skim `vidya/content/` for fresh
   samples that should refresh our corpora.
6. **Security audit** — review all byte-level input handling.
   `load8`/`store8` on `src + i` where `i` depends on token
   length; `alloc(N)` where N derives from input; file reads
   through `file_read_all` with cap respected. vyakarana is a
   library over arbitrary input — the coverage invariant is the
   correctness contract, but boundary checks on buffer allocation
   still matter. File findings in `docs/audit/YYYY-MM-DD-audit.md`
   (create the directory when the first audit lands).
7. Additional tests / corpus entries from findings — any new shape
   worth locking with an assertion or a stand-in probe.
8. Post-review gate run — prove the hardening didn't regress
   anything: all three gates green again.
9. Documentation audit — HANDOFF / ROADMAP / ADRs / grammar
   headers reflect current reality; prune stale `TODO`s.
10. Repeat if the audit turned up a lot. Don't start the next
    milestone until the hardening pass is quiet.

## Task sizing

- **Low/medium effort**: batch freely — multiple items per work
  loop cycle.
- **Large effort**: small bites only — break into sub-tasks,
  verify each before moving on.
- **If unsure**: treat it as large.

## Refactoring policy

- Refactor when the code tells you to — duplication, unclear
  boundaries, measured bottlenecks.
- Never refactor speculatively. Wait for the third instance.
- Every refactor must pass the same test + smoke gates as new code.
- **3 failed attempts = defer and document.** Stop, open an ADR
  (if the decision is load-bearing) or a `TODO(M?)` note, and move
  on. Don't burn time in a rabbit hole.

## Closeout pass (before every minor/major tag)

Run a closeout pass before the user cuts `0.Y.0` or `1.0.0`:

1. Full test suite — all assertions pass, zero failures.
2. Full smoke script — every language corpus round-trips with
   zero error kinds and the coverage invariant holds.
3. Dead-code audit — check for unused functions with the
   compiler's "dead:" output; remove anything stale.
4. Stale comment sweep — grep for old version refs, outdated
   `TODO(M?)` markers, ADR pointers to files that moved.
5. Doc sync — CHANGELOG `[Unreleased]` collapses into the new
   version header; HANDOFF's "Where we are" matches reality;
   ROADMAP updated if the milestone boundary shifted.
6. Clean build — `rm -rf build && cyrius deps && cyrius build`
   passes from scratch.
7. Downstream check — `owl` (and any other consumer that has
   picked up `[deps.vyakarana]`) still builds against the new tag.

## Cyrius dialect gotchas

These are the dialect traps we've hit or verified from working
Cyrius code. When dialect is unclear, read `cyrius/programs/*.cyr`
— that's the authoritative working reference.

- `if (cond) {` / `while (cond) {` — parens required around the
  condition.
- `var buf[N]` is **N bytes**, not N elements.
- `&&` / `||` short-circuit; mixed requires parens:
  `a && (b || c)`. Better yet, nest `if` blocks for clarity.
- No closures — use named functions.
- `break` inside a `while` with `var` declarations is unreliable;
  use a flag + `continue` pattern instead.
- `return;` without a value is invalid — always `return 0;` (or
  the real value).
- No negative literals. Write `(0 - N)`, not `-N`.
- All `var` declarations are function-scoped — no block scoping.
- Top-level args pattern: `args_init(); var ac = argc(); var a =
  argv(i);` (not `fn main(argc, argv)` — `argc`/`argv` are
  functions).
- `cyrius.cyml [deps] stdlib = [names]` auto-prepends the listed
  modules — only the ones named, not all of stdlib. Add what you
  need to the list; don't re-`include "lib/..."` for modules
  already in it. For single-file programs outside a project (e.g.
  `cyrius/programs/*.cyr`), explicit `include "lib/..."` at the
  top is the pattern. See `yukti/cyrius.cyml` for the canonical
  `[deps] stdlib`, `[deps.<name>]` git deps, and
  `[lib] modules = [...]` distlib shapes.
- Heap-allocate large buffers with `alloc(N)` — `var buf[256000]`
  bloats the binary by 256KB.
- Enum values for constants — don't consume `gvar_toks` slots (256
  initialized-global limit per compilation unit).
- Test exit pattern: `syscall(60, assert_summary())`.

## Do not

- **Do not commit or push** — the user handles all git operations.
- **Do not use `gh` CLI** — if GitHub-API calls are needed, use
  `curl` against the REST API.
- Do not modify files in `lib/` — vendored stdlib, re-synced by
  `cyrius deps`.
- Do not depend on `owl` or any other consumer — vyakarana is
  upstream of all of them.
- Do not add a token kind, change the `Token` layout, or rename
  the public `tokenize_source` signature without an ADR under
  `docs/adrs/` and a CHANGELOG entry.
- Do not hardcode toolchain versions in CI YAML — `cyrius.cyml`'s
  `cyrius = "X.Y.Z"` is the single source of truth.
- Do not take three failed attempts at the same problem — see
  §Refactoring policy.
- Do not trust external data (file bytes, CLI args) without
  bounds checks where allocation / pointer math depends on it.
  vyakarana is a library over arbitrary input; the scanner's
  coverage invariant is the correctness contract.

## Writing decisions

- If a choice will confuse a future agent ("why did they do it
  that way?"), open an ADR: `docs/adrs/NNNN-short-kebab-title.md`.
  Format: see [docs/adrs/README.md](./docs/adrs/README.md).
- Small implementation notes (recognizer ordering, scope notes)
  go in the relevant source file's header comment, not an ADR.
- CHANGELOG captures the *what*; ADRs capture the *why*; HANDOFF
  captures the current transition — don't duplicate across them.
