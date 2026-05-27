# 0018 — Vendored stdlib snapshot is gitignored, not committed

- **Status:** Accepted
- **Date:** 2026-05-27
- **Deciders:** proposed + accepted in the 2.2.2 modernization cut
- **Relates to:** [ADR 0014](0014-embedded-grammar-blobs.md) (the
  other "regenerate on checkout" artifact), `.gitignore`,
  `cyrius.cyml` `[package].cyrius` pin, `src/main.cyr`
  (`print_list_languages`), sibling repos `patra` / `sigil`.

## Context

Through 2.2.1 vyakarana committed a 20-file `lib/` snapshot of the
Cyrius stdlib (`alloc.cyr`, `vec.cyr`, `string.cyr`, …) at the
5.10.5 vintage. Because the working directory's `./lib/` shadows
the toolchain's version-matched snapshot
(`~/.cyrius/versions/<pin>/lib/`), the committed copy *was* the
stdlib every build compiled against — regardless of the
`cyrius = "X.Y.Z"` pin.

That masked a real incompatibility. The 2.2.2 cut bumps the pin
5.10.5 → 6.0.3. Building against the 6.0.3 snapshot surfaced a
dispatch regression: 6.0.x annotates `fn vec_get(v, idx): i64`,
so `println(vec_get(...))` now resolves to the `println_int`
overload and `vyk --list-languages` printed raw pointer addresses
instead of grammar names. The committed 5.10.5 `lib/` (untyped
`vec_get`) hid this — the smoke gate only caught it once `./lib/`
was removed and the matched snapshot took over.

The sibling first-party libraries — `patra`, `sigil` — both
**gitignore `/lib`** and track zero files there. `cyrius deps`
populates `lib/` fresh from the matched snapshot on each checkout,
so it can never drift from the pin.

## Decision

Stop committing the stdlib snapshot. Add `/lib/` to `.gitignore`
and untrack the 20 files (`git rm -r --cached lib`). `cyrius deps`
repopulates `lib/` from the toolchain snapshot named by the
`cyrius` pin; every fresh checkout runs `cyrius deps` before its
first build (already a documented gate step).

Scope: repo-hygiene + build-flow only. The one code change this
forces is in `src/main.cyr` — `print_list_languages` binds the
`vec_get` result through a `var name: cstring` local so `println`
lands on the string overload rather than `println_int`. No public
API, token layout, or grammar change.

## Consequences

### Positive

- The pin in `cyrius.cyml` becomes the single source of truth for
  the stdlib version — no shadow copy to fall out of sync. The
  `cwd ./lib/ shadows version-pinned …` cycc warning is gone.
- Pin bumps now actually exercise the new stdlib at build time, so
  dispatch/ABI drift (like the `vec_get: i64` case) is caught by
  the gates instead of hiding behind a stale vendored copy.
- Matches the `patra` / `sigil` first-party layout — one mental
  model across the AGNOS libraries.
- Smaller tree; no 20-file diff noise on every toolchain bump.

### Negative

- A fresh checkout cannot build until `cyrius deps` has run (it
  fetches the matched snapshot into `lib/`). This is already the
  first documented gate step, but offline/air-gapped builds must
  ensure the toolchain version is installed locally first.
- Loses the "exact bytes we built against" provenance that a
  committed `lib/` gave. The `cyrius` pin + `cyriusly use <pin>`
  reconstructs it deterministically, so this is acceptable.

### When to revisit

If Cyrius ever stops shipping a version-matched stdlib snapshot
with the toolchain (so `cyrius deps` has nothing to copy), or if a
consumer needs a fully self-contained checkout with no `cyrius
deps` step, reconsider vendoring — but vendor at the pinned
version and gate against drift, don't freeze an arbitrary vintage.
