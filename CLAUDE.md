# vyakarana — agent working rules

> **Picking this repo up?** Read
> [docs/development/state.md](./docs/development/state.md) first
> for where we are and what's next. Architecture decisions are ADRs
> under [docs/adr/](./docs/adr/); design context is in
> [docs/development/vyakarana-design-spec.md](./docs/development/vyakarana-design-spec.md); milestone
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
cyrius deps
sh scripts/embed-grammars.sh
cyrius build src/main.cyr build/vyk
sh scripts/lint-fmt.sh                 # lint + fmt --check, src/ + scripts/audit/
cyrius test tests/vyakarana.tcyr
sh scripts/smoke.sh build/vyk
sh scripts/check-size.sh               # shipped (DCE) binary's size, reported
cyrius build scripts/audit/harness.cyr build/vyk-audit \
    && build/vyk-audit auto tests/corpus/openqasm.qasm every \
    && for f in scripts/audit/*.sh scripts/bench-paired.sh; do sh -n "$f"; done
cyrius fuzz                            # the fuzz/*.fcyr harnesses
cyrius distlib --check                 # dist/vyakarana.cyr current; exit 1 if stale
```

These are CI's steps (`.github/workflows/ci.yml`), in CI's order, so
a green run here is a green CI run — through 2.9.1 this list left out
the last three, and through 2.9.12 the harness's one run. Run them all
on session entry. Don't take `docs/development/state.md` / `README.md`
claims of "green" at face value until you've seen the commands pass. Use `cyrius build`,
never the raw compiler (`cycc`).

**`cyrius deps` used not to refresh a `lib/` that already existed.**
Through the 6.5.x pins it treated a present `lib/<mod>.cyr` as
satisfied, so the vendored stdlib silently stayed at whatever
snapshot first populated it — between 2.2.2 and 2.3.0 `lib/` sat at
a 6.0.x vintage across two pin bumps. Since 6.6.20 a plain `cyrius
deps` refreshes it (CHANGELOG 2.4.3; re-checked at 6.7.18 on 2026-10-23).
**After any pin change, `rm -rf lib && cyrius deps` anyway** — it
costs nothing, and an older pin may not refresh.

Confirm with a *whole-tree* diff, not one file — `str.cyr` is
unchanged across many pins and will pass while everything else
is stale:

```sh
for f in lib/*.cyr; do
    diff -q "$f" ~/.cyrius/versions/<pin>/lib/"$(basename "$f")" \
        || echo "STALE: $f"
done
```

**What a stale `lib/` does and does not break.** As of 6.5.32,
`cycc` resolves stdlib from `~/.cyrius/versions/<pin>/lib` — the
**pin** decides what is compiled, and the project `lib/` is inert
at build time. Verified in 2.3.3 by appending garbage to
`lib/str.cyr` and rebuilding: still `OK`. So a stale `lib/` does
**not** silently build you against the wrong stdlib; it makes the
tree *describe* a version it isn't on and misleads anyone reading
it — silently: at 6.7.18 garbage appended to `lib/str.cyr` builds
byte-identical with no warning (re-checked in 2.10.0; the driver
carries a "shadows version-pinned" warning that does not fire on
`build`, `test` or `distlib`), so only the whole-tree diff above
catches it. (This paragraph used to
claim the opposite — that a stale `lib/` made the pin ignored.
That was wrong; the reverse is true.) Keep them in sync anyway:
CI populates `lib/` fresh on every checkout, so a mismatch means
local and CI are compiling different snapshots.

**Lint + fmt are mandatory pre-release.** CI runs them; failing
either blocks the tag. The wrapper at `scripts/lint-fmt.sh`
iterates every `src/*.cyr`, `src/grammars/*.cyr` and
`scripts/audit/*.cyr` (skipping
`src/grammar_blobs.cyr` — generated, long string-literal lines
are intentional). One stop for both checks; non-zero exit on any
warning or formatting drift.

`scripts/embed-grammars.sh` regenerates `src/grammar_blobs.cyr`
(gitignored — every fresh checkout needs this step before the
first build). Inlines `grammars/*.cyml` into Cyrius string
literals so `dist/vyakarana.cyr` is self-contained for `cyrius
deps` consumers — compacted since 2.9.0 (comments and blanks
outside strings dropped; a test proves each blob parses to its
source file's grammar record, so a stale blob fails `cyrius
test`). **Required before `cyrius distlib`** — since
6.2.52 distlib exits 1 on a missing `[lib] modules` entry rather
than quietly emitting a truncated bundle. See ADRs 0014 and 0029.

## Work loop (continuous)

For every non-trivial change:

1. Read `docs/development/state.md` and the relevant ADRs — know what was intended.
2. Work phase — grammar, scanner tweak, test, docs fix.
3. Build + test: `cyrius build` then `cyrius test`.
4. Internal review — correctness, coverage invariant, zero-error
   bar on any corpus the change affects.
5. Smoke check — `sh scripts/smoke.sh build/vyk` after changes
   that touch runtime or grammar surface.
6. Documentation — update CHANGELOG `[Unreleased]`, `docs/development/state.md` if
   the status shifted, ROADMAP only on milestone boundaries.
7. Version check — `VERSION` is the source. `scripts/version-bump.sh`
   regenerates `src/version_str.cyr` and adds the CHANGELOG header;
   `cyrius.cyml` reads `VERSION`; the `.TH` line of `docs/man/vyk.1`
   and `dist/vyakarana.cyr` (`cyrius distlib`) are by hand. All of them
   agree (state.md's Version line names them).
8. Return to step 1.

## Hardening step (before starting a new milestone or feature batch)

Between work cycles, before diving into the next milestone, run a
consolidation pass. This is the "slow down and take stock" step —
catch drift before it compounds.

1. Read `docs/development/state.md`, ROADMAP, CHANGELOG, and any open `TODO(M?)`
   markers — know what was intended.
2. Cleanliness check: every command in §Gates — all green.
3. Benchmark baseline:
   `sh scripts/bench-paired.sh <last tag>` (the paired protocol —
   ratios hold on a loaded host; absolute numbers only from a
   quiet one). Compare against
   the table in `docs/development/performance.md`; refresh the
   doc at each minor-release boundary (1.13.0+ has the
   baseline). Watch for >20% regressions on the tokenize and
   detect rows — those are the hot paths consumers depend on.
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
   still matter. File findings in `docs/audit/YYYY-MM-DD-audit.md`.
   The empirical sweeps are scripted in `scripts/audit/` (its
   README): real-file coverage, poison A/B, streaming invariance,
   mutation fuzz over vidya — rerun them; don't rebuild them.
7. Additional tests / corpus entries from findings — any new shape
   worth locking with an assertion or a stand-in probe.
8. Post-review gate run — prove the hardening didn't regress
   anything: §Gates green again.
9. Documentation audit — `docs/development/state.md` / ROADMAP / ADRs / grammar
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
3. **Lint + fmt — `sh scripts/lint-fmt.sh` exits 0.** Both
   `cyrius lint` (zero warnings) and `cyrius fmt --check` (no
   drift) across every hand-edited `src/*.cyr`,
   `src/grammars/*.cyr` and `scripts/audit/*.cyr`. CI gates the
   same; failing either blocks the tag.
4. Dead-code audit — check for unused functions with the
   compiler's "dead:" output; remove anything stale.
5. Stale comment sweep — grep for old version refs, outdated
   `TODO(M?)` markers, ADR pointers to files that moved.
6. Doc sync — CHANGELOG `[Unreleased]` collapses into the new
   version header; `docs/development/state.md`'s "Current status"
   matches reality; ROADMAP updated if the milestone boundary
   shifted.
7. Clean build — `rm -rf build && cyrius deps && sh
   scripts/embed-grammars.sh && cyrius build src/main.cyr build/vyk`
   passes from scratch (a bare `cyrius build` writes `./vyk`).
8. Downstream check — `owl` (and any other consumer that has
   picked up `[deps.vyakarana]`) still builds against the new tag.

## Cyrius dialect gotchas

These are the dialect traps we've hit or verified from working
Cyrius code. When dialect is unclear, read `cyrius/programs/*.cyr`
— that's the authoritative working reference.

- `if (cond) {` / `while (cond) {` — parens required around the
  condition.
- `var buf[N]` **inside a function** is N bytes, not N elements.
  A bare **top-level** `var X[N]` is `N × 8` bytes as of 6.4.10
  (it was under-sized before that). vyakarana declares no arrays
  at either scope — keep it that way and use `alloc(N)`.
- `&&` / `||` short-circuit. `&&` binds tighter than `||` as of
  6.3.36 (they were equal precedence before, so `a || b && c`
  mis-parsed). Keep writing the parens anyway — `a && (b || c)`
  reads the same at every pin. Better yet, nest `if` blocks.
- No closures — use named functions.
- `break` inside a `while` with `var` declarations is unreliable;
  use a flag + `continue` pattern instead.
- Write `return 0;` (or the real value), never a bare `return;`,
  and `(0 - N)`, never `-N`. Older pins rejected both; at 6.7.18 both
  compile and evaluate right (re-checked in 2.10.0), but the house
  style reads the same at every pin.
- `var` is **block-scoped**. Re-declaring a name already bound in
  the *same* block is a `duplicate variable` error; shadowing an
  enclosing block or reusing a name in a sibling block is legal;
  a block-local does not survive its closing brace. This is what
  kept `tests/vyakarana.tcyr` from compiling until 2.3.0 — its
  3,100-line `fn main()` had eleven names re-declared in the one
  top-level block.
  **The compiler under-reports it.** Error recovery swallows the
  statement after each duplicate, so a run surfaces roughly half
  the sites and can emit a bogus `undefined variable` cascade on
  top. Enumerate the duplicates statically and fix them in one
  pass; do not iterate against compiler output.
- Never name a function `X_str`, `X_int`, or `X_cstr` unless it
  really is the same-arity type variant of a sibling `X`. Those
  are reserved overload-dispatch suffixes — the compiler rewrites
  `X(a, …)` to the suffixed name when arg 1 matches, so a
  lookalike silently hijacks calls to its base and binds the
  missing arguments to garbage.
- Top-level args pattern: `args_init(); var ac = argc(); var a =
  argv(i);` (not `fn main(argc, argv)` — `argc`/`argv` are
  functions).
- `cyrius.cyml [deps] stdlib = [names]` auto-prepends the listed
  modules — only the ones named, not all of stdlib. Add what you
  need to the list; don't re-`include "lib/..."` for modules
  already in it. For single-file programs outside a project (e.g.
  `cyrius/programs/*.cyr`), explicit `include "lib/..."` at the
  top is the pattern. See `yukti/cyrius.cyml` for the canonical
  `[deps] stdlib` and `[lib] modules = [...]` distlib shapes, and
  `owl/cyrius.cyml`'s `[deps.vyakarana]` (or distribution.md §1) for
  a `[deps.<name>]` git dep.
- Heap-allocate large buffers with `alloc(N)` — `var buf[256000]`
  bloats the binary by 256KB.
- Enum values for constants — don't consume `gvar_toks` slots.
  The initialized-global cap per compilation unit is **4096** as
  of 6.3.41 (it was 1024, and this file long carried a stale 256).
  Only non-literal top-level initializers take a slot, so the
  ceiling is distant — but enums still read better for constants.
- Test exit pattern: `syscall(60, assert_summary())`.

## Do not

- **Do not commit or push** — the user handles all git operations.
- **Do not use `gh` CLI** — if GitHub-API calls are needed, use
  `curl` against the REST API.
- Do not modify files in `lib/` — vendored stdlib. Re-vendor with
  `rm -rf lib && cyrius deps` (a plain `cyrius deps` refreshes an
  existing tree since 6.6.20, but not on older pins).
- Do not depend on `owl` or any other consumer — vyakarana is
  upstream of all of them.
- Do not add a token kind, change the `Token` layout, or change
  the public streaming API — `tokenize_stream_new` / `_feed` /
  `_drain` / `_finish` / `_free`, plus `has_grammar`,
  `list_languages_into`, `bootstrap_grammars` and the rest of the
  list in `src/tokenize.cyr`'s header (pull adapter, registry,
  detection, documents, tokens), which is authoritative — without an ADR
  under `docs/adr/` and a CHANGELOG entry. This rule used to name
  `tokenize_source`, which 2.0.0 **removed** with no compat shim
  ([ADR 0017](./docs/adr/0017-streaming-api.md)); the only
  surviving `tokenize_source*` symbol is
  `tokenize_source_handcoded`, a `--handcoded` diagnostics oracle
  that is explicitly **not** public surface and is not covered by
  this rule.
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
  that way?"), open an ADR: `docs/adr/NNNN-short-kebab-title.md`.
  Format: see [docs/adr/README.md](./docs/adr/README.md).
- Small implementation notes (recognizer ordering, scope notes)
  go in the relevant source file's header comment, not an ADR.
- CHANGELOG captures the *what*; ADRs capture the *why*;
  `docs/development/state.md` captures the current transition —
  don't duplicate across them.
