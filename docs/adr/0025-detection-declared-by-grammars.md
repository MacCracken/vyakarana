# 0025 — Grammars declare their detection routes; `detect.cyr` stays compiled

- **Status:** Accepted
- **Date:** 2026-10-20
- **Deciders:** 2.6.2 detection work (proposed) / user (accepted via
  the pinned 2.6.2 roadmap entry, which asked for this decision)
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md) (grammar
  format), [ADR 0015](0015-content-based-detection.md) (content
  sniff, asm vote), `src/detect.cyr`, `src/grammar.cyr`,
  `scripts/check-detect.sh`, `tests/vyakarana.tcyr` ("2.6.2 detection
  matches grammar declarations")

## Context

Every grammar's `[grammar]` table carries `extensions = [...]` and
some carry `shebangs = [...]`. The loader parses both; nothing reads
them except two tests. Detection is a compiled table in
`src/detect.cyr`. Nothing linked the two, and by 2.6.1 they had
drifted:

- **Declared, never routed:** `.hh` (cpp), `.csx` (csharp), `.phtml`
  (php), `.properties` (ini), `.asm` (both asm grammars), `.cyml` in
  *cyrius* (routed to cyml), and powershell's `pwsh` / `powershell`
  interpreters.
- **Routed, never declared:** `.zsh`, `Dockerfile`, `Containerfile`,
  `Makefile`, `makefile`, `GNUmakefile`, and the python / php / node
  / ruby / lua interpreters.
- **Routed into a grammar that rejects it:** `#!/usr/bin/env node`
  detects as javascript, whose `shebang = false` turned the line
  into `#` `!` `/` `usr` … tokens; php read its shebang as a `#`
  comment.

The roadmap asked for one of two fixes: drive detection from the
arrays, or prune them.

## Decision

**Detection stays compiled. The arrays become its declaration, and
two checks hold them equal.**

Driving detection from the loaded registry was rejected:

- `detect_language(path)` is pure today — no state, no allocation,
  ~34 ns, usable before `bootstrap_grammars()` (ADR 0015's public
  surface). Reading the registry would make a call before bootstrap
  return 0 without any error, and turn the first call into a
  bootstrap of all 46 grammars (~2 ms: `vyk --list-languages` vs
  `vyk --version`).
- The arrays cannot express what detection does: the `.s` / `.S`
  content vote, basenames, `sh` matching only up to 3 bytes so
  `shellcheck` is not a shell. Each would need new keys or
  exceptions in code anyway.
- The only caller is `vyk`. owl and cyim route paths through their
  own tables and config overrides, and load their own grammars with
  `grammar_load`; routing by registry order would let a consumer
  grammar claim `.h` without anyone choosing that.

Generating the table from the arrays at embed time was rejected too:
it puts routing order and ambiguity rules in the gawk embed script
that 2.9.0 replaces, and the generated file is gitignored, so the
routing table would no longer be reviewable in the tree.

What the declarations mean:

- `extensions` — case-sensitive path suffixes. First match in
  `detect.cyr` order wins. An extension that two grammars list must
  be resolved in code (only `.s` / `.S`, by ADR 0015's vote).
- `filenames` (**new key**, `[grammar]`, string array, Grammar
  +192, `grammar_filenames(g)`) — a path ending in the name matches
  (`Dockerfile`, `ci/app.Dockerfile`), and so does a basename
  `<name>.<anything>` (`Dockerfile.dev`, `Makefile.am`) when no
  extension matched first. *(Amended 2.9.1: the ending must start
  the path or follow `/`, `.`, `-` or `_` — `notaMakefile` was a
  makefile; and the `<anything>` must start with a letter and its
  last dot component must not be a compression, patch or tool suffix
  — `gz bz2 xz zst lz lz4 lzma z br zip 7z tar tgz rej patch diff
  dockerignore cmake`. On one machine that changed 2 of 239 matching
  files, the man page and CMake's file below; the 237 others,
  `Makefile.in.in` and `Makefile.orig` included, route as before.)*
- `shebangs` — interpreter basenames, prefix-matched (`python3`,
  `bash5`). A grammar that lists any must have `shebang = true`, so
  the line it was detected by is one token.

The checks:

- `tests/vyakarana.tcyr`: every entry of every loaded grammar routes
  to that grammar (extensions in a dotted directory; filenames bare,
  in a directory, as a suffix and as `<name>.dev`; interpreters in
  `env`, absolute-path and versioned form), and `shebang = true`
  wherever `shebangs` is non-empty.
- `scripts/check-detect.sh`, run by smoke: every path and interpreter
  route anywhere in `detect.cyr` is declared by its target grammar,
  every `memeq` length equals its literal's length and is guarded
  (`n >=` / `wlen >=`), and any other line that could be a route — a
  `return "…"` outside the content sniff, a route-like call that
  returns a variable — fails as unrecognised. The content sniff
  (`_detect_signature`, the asm vote; ADR 0015) declares nothing and
  is not checked.

The 2.6.1 drift was resolved one entry at a time, using 1,014 files
on the dev host with the affected names:

- **Routed:** `.hh`, `.csx`, `.phtml`, `.properties` (722 files, 0
  error tokens), `.mk` (125, 0), `Dockerfile.*` / `Makefile.*` (80,
  0 bar one gzip), `pwsh` / `powershell`, `julia` (julia already had
  `shebang = true`).
- **Pruned:** `.asm` from both asm grammars — it is NASM / MASM /
  armasm. Forced through asm_x86_64, all 1,611 `;` comment lines in
  81 real files came out as code. *cyrius*'s `.cyml`.
- **Declared:** `.zsh`, the five filenames, and the five unlisted
  interpreters.
- **Fixed:** javascript and php get `shebang = true` — on 190 real
  scripts with a shebang, line 1 becomes one token and every later
  token is unchanged.

Over 4,860 real files, the detection change altered exactly the 925
that newly route (exit 4 → 0, or → 1 for two) — nothing that routed
before.

## Consequences

### Positive

- A declared route that does not work, or a working route nobody
  declared, now fails a gate instead of drifting. Both checks were
  run against the 2.6.1 sources: 19 misroutes, and every undeclared
  route, reported by name.
- `grammar_extensions` / `grammar_filenames` / `grammar_shebangs`
  are now accurate, so a consumer can build its own table from them.
- Detection stays pure and fast; the bench rows are unaffected (the
  new routes sit after the benchmarked ones).

### Negative

- Adding a route is still two edits — the grammar and `detect.cyr`.
  The checks make forgetting one a test failure, not a silent gap.
- `check-detect.sh` reads source text. A route written in a new
  shape is reported as unrecognised, so it fails loudly rather than
  being missed — but the script has to learn the shape. A route that
  returns a variable through a helper it does not know (`streq` on a
  basename, say) would still get past it; the tcyr direction catches
  it only if the route is declared.
- The `<name>.<anything>` rule has false positives, the same trade
  editors make with a `Dockerfile.*` pattern: `Dockerfile.5.gz` (a
  binary) tokenizes as Dockerfile with error tokens, and CMake's
  `Makefile.cmake` and source-highlight's `makefile.lang` tokenize
  cleanly but wrongly as makefile. 2.6.1 refused all three (exit 4).
  *(2.9.1: the first two are refused again; `makefile.lang` is still
  routed — `.lang` is one program's convention, and a list of every
  such suffix has no end.)*

### When to revisit

- A consumer asks vyakarana to route its own grammars: add a
  separate, additive `detect_language_registered(path)` that walks
  the registry, rather than changing `detect_language`.
- A NASM grammar lands: it takes `.asm`.
