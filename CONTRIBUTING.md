# Contributing to vyakarana

Thanks for wanting to help vyakarana see more grammar.

## Prerequisites

- Cyrius toolchain at the version pinned in `cyrius.cyml`'s
  `[package].cyrius` field (currently `6.5.4`; check the file —
  the pin moves faster than this sentence). Run
  `cyriusly use 6.5.4` if the active toolchain doesn't match.
  The pin is authoritative: match your toolchain to it, never
  edit it to match your toolchain. `cyrius` must be on `$PATH` —
  <https://github.com/MacCracken/cyrius>
- A POSIX-ish host (Linux primary; macOS best-effort). vyakarana targets
  AGNOS long-term, but the development shape is portable.

## Development Workflow

1. Fork and clone
2. `cyriusly use "$(sed -n 's/^cyrius = "\(.*\)"/\1/p' cyrius.cyml)"` —
   take the pin from the file, not from memory; match it before
   anything else
3. `cyrius deps` — vendors stdlib into `lib/`. If `lib/` is
   already on disk from an older pin, `rm -rf lib && cyrius deps`
   instead: an already-present `lib/<mod>.cyr` counts as
   satisfied and is never refreshed, so a stale tree survives a
   pin bump in silence. That is exactly how 2.2.3 built against a
   6.0.x-vintage stdlib while claiming 6.1.24: the tree that
   `cyrius deps` laid down at 2.2.2 (pin 6.0.3) survived the next
   bump untouched, and nothing caught it until 2.3.0.
4. `sh scripts/embed-grammars.sh` — generates the gitignored
   `src/grammar_blobs.cyr`; a fresh checkout will not build
   without it (ADR 0014)
5. Branch from `main`
6. Make your change
7. Run every gate below before opening a PR — CI runs the same
   set plus a `dist/vyakarana.cyr` drift check
8. Reference the ROADMAP milestone your change belongs to

## Bumping the version

`sh scripts/version-bump.sh <new-version>` is the only supported
way to move the version. It writes exactly three things:

- **`VERSION`** — the source of truth.
- **`src/version_str.cyr`** — regenerated unconditionally, even
  on a same-version run
  (`sh scripts/version-bump.sh "$(cat VERSION)"` is the
  documented regenerate-without-bumping path). A drifting
  `vyk --version` literal is how the 1.0.3 cut nearly shipped
  reporting 1.0.2.
- **`CHANGELOG.md`** — a `## [X.Y.Z] — <today>` header, and only
  the header.

Everything else is manual: the CHANGELOG body, the cyrius
toolchain pin in `cyrius.cyml`'s `[package].cyrius` (independent
of vyakarana's own version — the two move on separate clocks),
`docs/development/state.md` if the status shifted, and
`dist/vyakarana.cyr` via `cyrius distlib`. `cyrius.cyml`'s
`version` field needs no touch; it resolves `${file:VERSION}`.
Run `sh scripts/embed-grammars.sh` *before* `cyrius distlib` —
since 6.2.52 distlib exits 1 on a `[lib]` modules entry it can't
read, and `src/grammar_blobs.cyr` is gitignored.

**Known wart — read the CHANGELOG diff after every bump.** The
insert is an anchored `sed` append on the literal `## [Unreleased]`
line, which knows nothing about where that section ends. Whatever
`[Unreleased]` was holding — a real entry you hadn't filed yet, or
the `_No unreleased changes._` placeholder — lands *below* the new
header and is therefore misfiled under the new version:

```text
## [Unreleased]

## [2.4.0] — 2026-07-31

_No unreleased changes._      <- still belongs to [Unreleased]
```

Move it back by hand before committing.

See cyim's and cyrius's `version-bump.sh` for the canonical
pattern this script follows.

## Gates

CLAUDE.md's five gates — unrolled, since one of them chains
`cyrius deps && cyrius build` — plus `cyrius fuzz`, in the order
CI runs them. All seven must be green before a PR merges:

```sh
cyrius deps                             # vendors stdlib into lib/
sh scripts/embed-grammars.sh            # regenerates src/grammar_blobs.cyr
cyrius build src/main.cyr build/vyk
sh scripts/lint-fmt.sh                  # lint + fmt --check, all src/*
cyrius test tests/vyakarana.tcyr
sh scripts/smoke.sh build/vyk
cyrius fuzz                             # the 4 harnesses in fuzz/*.fcyr
```

Lint and fmt are not optional — CI gates both, and either one
failing blocks the tag. `lint-fmt.sh` skips only
`src/grammar_blobs.cyr`, whose long string-literal lines are
generated on purpose.

CI adds one step this list doesn't: after `cyrius fuzz` it
re-runs `cyrius distlib` and diffs the result against the
committed `dist/vyakarana.cyr`. If your change touches a module
named in `cyrius.cyml`'s `[lib]` block, run
`sh scripts/embed-grammars.sh && cyrius distlib` and commit the
regenerated bundle — otherwise every gate above passes locally
and the PR still fails.

At 2.3.0 green means 840/840 test assertions and 4/4 fuzz
harnesses. Run the gates yourself rather than trusting a doc that
says "green" — 2.2.3 shipped with a test suite that did not
compile, and nobody noticed because nobody re-ran it.

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
