# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

_No unreleased changes._

## [1.4.0] — 2026-05-08

Scripting + mobile language batch. Four new grammars in one cut:
PHP, Ruby, Lua, Swift. All four ship with stand-in corpora per
[ADR 0006](docs/adr/0006-standin-corpus-policy.md) — vidya
doesn't yet ship reference samples for these languages. **No
new scanner extensions were needed**; existing 1.1.0 / 1.2.1
machinery handled everything except a pipeline-priority gotcha
in Lua (now documented as architecture guidance).

### Added

- **PHP grammar.** New `grammars/php.cyml` +
  `tests/corpus/concept.php` (1604 tokens, zero errors). `$` in
  `ident_start` so `$variable`, `$source`, `$this->pos`
  tokenize as a single ident. Operators include `->` (member
  access), `=>` (array key/value, match arms), `::` (scope
  resolution), `??` / `??=` (null-coalesce), `?->` (null-safe
  member access, PHP 8), `<=>` (spaceship), `**` / `**=`
  (power). **`\` added to operators** for namespace separator
  (`Vyakarana\Concept\Foo`, `\RuntimeException`); the
  string-pair `escape = "\\"` consumes `\<C>` inside string
  spans, so `\` outside strings cleanly tokenizes as a 1-byte
  op. Both `//` and `#` line comments. Keyword set covers PHP
  8: `enum`, `readonly`, `match`, `fn`, `mixed`, `never`.
- **Ruby grammar.** New `grammars/ruby.cyml` +
  `tests/corpus/concept.rb` (1111 tokens, zero errors). `@`
  and `$` in `ident_start` (instance/class vars, globals).
  `=begin`/`=end` block comments via pair rule (caveat: spec
  requires column-0; scanner has no column-state, documented
  in grammar header). Operators include `<=>`, `===`, `=~`/
  `!~` (regex match), `..`/`...` ranges, `&.` safe-nav, `**`/
  `**=`. **`\` added to operators** for inline regex bodies
  (`=~ /\s/`) and line-continuations.
- **Lua grammar.** New `grammars/lua.cyml` +
  `tests/corpus/concept.lua` (1713 tokens, zero errors).
  Smallest grammar in the batch — 22 reserved words, `..`/
  `~=`/`//` operators. **Both comment forms expressed as pair
  rules** (`--[[…]]` long comment, `--…\n` line comment) so
  the longer prefix can win — the scanner pipeline runs line
  rules at step 2 BEFORE pair rules at step 3, so a line-rule
  `--` would otherwise eat the `--` of `--[[` greedily.
  Documented in [architecture note 003](docs/architecture/003-pair-rule-ordering.md)
  with the workaround pattern for any future grammar that has
  both line and pair forms with a shared prefix. Variable-
  padded long brackets (`[==[…]==]`) deferred — would need a
  variable-length-delimiter rule shape, tracked alongside Ruby
  heredocs / PHP heredocs / Swift raw strings as a future ADR.
- **Swift grammar.** New `grammars/swift.cyml` +
  `tests/corpus/concept.swift` (1380 tokens, zero errors).
  `@` and `$` in `ident_start` (attributes / closure shorthand
  `$0`/`$1`). Multi-line strings `"""…"""` via pair rule
  ahead of `"…"` (same shape as
  [ADR 0008](docs/adr/0008-toml-triple-quoted-strings.md) for
  TOML). Operators include `..<` (half-open range), `...`
  (closed range), `??` (nil-coalesce), `?.` (optional chain),
  `&+`/`&-`/`&*` (overflow-checked arithmetic), `===`/`!==`
  (identity).

### Changed

- **Architecture note 003 expanded.** New "Pair-vs-line-rule
  prefix collisions" section documents the Lua finding: line
  rules run at pipeline step 2, pair rules at step 3, so a
  shared prefix between the two means the line rule always
  wins regardless of declaration order in the grammar file.
  Workaround: express both as pair rules and order longer
  prefix first. The architecture note 002 pipeline order stays
  normative — this is grammar-author guidance, not a scanner
  change.

### Wiring

- `src/tokenize.cyr` — all four added to `bootstrap_grammars()`
  (now loads 23 grammars).
- `src/main.cyr` — extension dispatch: `.php`/`.phtml`, `.rb`,
  `.lua`, `.swift`.
- `scripts/smoke.sh` — all four added to `--list-languages`
  check (now 23 grammars) and the corpus round-trip loop.
- `tests/vyakarana.tcyr` — three or four probe assertions per
  grammar covering load + name + grammar-specific shapes
  (variable interpolation, namespace separator, long comments,
  long strings, half-open range, etc.). 463 → 495 passing.

## [1.3.0] — 2026-05-08

JVM + C-family language batch. Four new grammars in one cut.
All four ship with stand-in corpora per
[ADR 0006](docs/adr/0006-standin-corpus-policy.md) — vidya
doesn't yet have reference samples for these languages, so each
gets a hand-rolled `concept.<ext>` mirroring the lexer+parser
theme used by every vidya `lexing_and_parsing/` sample.
**No new scanner extensions were needed** — the 1.1.0 / 1.2.1
machinery (`unicode_ident`, `char_literal`, block-comment pair
rule) covered all four languages without an ADR.

### Added

- **Java grammar.** New `grammars/java.cyml` +
  `tests/corpus/concept.java` (1705 tokens, zero errors). `@`
  in `ident_start` so `@Override`, `@Deprecated`,
  `@SuppressWarnings` tokenize as a single ident — same call as
  Zig's `@`-builtins (1.2.0) and Rust's `$`-macros
  ([ADR 0007](docs/adr/0007-rust-dollar-in-ident-start.md)).
  `$` also in `ident_start` for compiler-generated names.
  Operators include `->` (lambdas), `::` (method ref), `>>>`
  (unsigned right shift). Keyword set covers Java 21: `record`,
  `sealed`, `permits`, `non-sealed`, `yield`, `var`, plus the
  classic reserved words.
- **Kotlin grammar.** New `grammars/kotlin.cyml` +
  `tests/corpus/concept.kt` (1320 tokens, zero errors). `@` and
  `$` in `ident_start`. Operators include `?:` (Elvis), `?.`
  (safe-call), `!!` (not-null assert), `..` (range), `===` /
  `!==` (referential equality), `->` (lambda / when arms),
  `::` (callable reference). Keyword set covers data/sealed
  classes, `suspend`, `inline`/`noinline`/`crossinline`,
  contextual `in`/`out`/`as`/`by`/`where`.
- **C++ grammar.** New `grammars/cpp.cyml` +
  `tests/corpus/concept.cpp` (1686 tokens, zero errors). The
  language most likely to surface scanner ADR work in this cut
  — in practice the existing operator and identifier machinery
  handled templates / `::` / generics / namespaces without new
  defaults. `<` and `>` already tokenize as comparison
  operators (consumers handle the template-vs-shift
  disambiguation), `::` is a 2-char operator, and `auto` /
  `template` / `typename` are plain keywords. Operators include
  `<=>` (three-way compare, C++20), `->*` and `.*` (member
  pointer), `...` (parameter packs). Keyword set covers
  C++20-era surface (concepts, modules, coroutines).
- **C# grammar.** New `grammars/csharp.cyml` +
  `tests/corpus/concept.cs` (1399 tokens, zero errors).
  Operators include `??=` / `??` (null-coalesce assign /
  value), `?.` (null-conditional), `=>` (lambda /
  expression-body / switch arms), `..` (range). `@` and `$`
  added to the operator list (verbatim / interpolated string
  prefixes — the regular `"..."` rule absorbs the body).
  Keyword set covers C# 12-era surface including `record`,
  `init`-pattern words (`when`, `with`), and LINQ contextual
  keywords.

### Wiring

- `src/tokenize.cyr` — all four added to `bootstrap_grammars()`.
- `src/main.cyr` — extension dispatch: `.java`, `.kt`/`.kts`,
  `.cpp`/`.cc`/`.cxx`/`.hpp`/`.hxx`, `.cs`/`.csx`.
- `scripts/smoke.sh` — all four added to `--list-languages`
  check (now 19 grammars) and the corpus round-trip loop.
- `tests/vyakarana.tcyr` — three probe assertions per grammar
  (load + name + grammar-specific operator/keyword check).
  439 → 463 passing. One naming collision with the existing
  TypeScript probe (`saw_arrow`) renamed to `saw_jv_arrow` for
  the Java probe — Cyrius vars are function-scoped per
  CLAUDE.md and same-name redeclaration at function-top-level
  errors as a duplicate.

## [1.2.4] — 2026-05-08

Closeout / P(-1) hardening pass for the 1.2.x line. No
behavioural changes; cleanup, audit, and doc-sync only.

### Changed

- **Dead-code removal.** The compiler's "dead:" report had been
  flagging four vyakarana-owned functions for several builds:
  `registry_get`, `registry_count`, `grammar_count`,
  `_g_cstr_copy`. None had callers anywhere in `src/` /
  `tests/` / the dist bundle, and none were documented as
  public API. All four removed. `kind_is_valid` is also
  flagged as dead by the binary build but is intentionally
  retained — it's exported via `[lib] modules` for downstream
  consumers and is exercised by 5 test assertions; the
  comment now explains why.
- **Stale comment sweep.** Six source-comment references to
  pre-shipped milestones cleaned up: `src/token.cyr` (M0 stub
  / M5 streaming work), `src/main.cyr` (M3 will revisit),
  `src/tokenize.cyr` (hardening / 1.0.0 pass — M1 path
  retention), `src/grammars/shell.cyr` (M1 sample is integers),
  `scripts/smoke.sh` ("adding grammars in M3"). Each rewritten
  to point at current reality: docs/architecture pointers for
  invariants, docs/development/roadmap.md pointers for
  forward work.

### Security

- **1.2.x closeout audit** filed at
  [docs/audit/2026-05-08-1.2.x-closeout-audit.md](docs/audit/2026-05-08-1.2.x-closeout-audit.md).
  Covers every scanner-level change since the 2026-04-23
  baseline (`unicode_ident` / `char_literal` / four new
  grammar files / 1.2.4 dead-code cleanup). 0 CRITICAL, 0
  HIGH, 0 MEDIUM, 0 new LOW. The 2026-04-23 baseline findings
  carry forward unchanged. Bounds checks on every new
  `load8` / `alloc` reviewed and confirmed; known-CVE
  checklist re-run against the new code shape.

## [1.2.3] — 2026-05-08

### Added

- **`asm_aarch64` grammar.** New `grammars/asm_aarch64.cyml` +
  `tests/corpus/asm_aarch64.s` (snapshot of
  `vidya/content/lexing_and_parsing/asm_aarch64.s`, 8037 B,
  1367 tokens at zero `error` kinds). ARM 64-bit assembly. Same
  data-driven tokenizer as `asm_x86_64` with ARM-specific tuning:
  - `//` line comments (NOT `#` — `#` is the immediate-operand
    prefix in ARM, e.g. `mov w0, #5`, and tokenizes as a 1-byte
    operator).
  - `/* … */` block comments via the standard pair rule.
  - `.` is in BOTH `ident_start` and `ident_cont` (vs.
    `asm_x86_64` where it's only in `ident_start`), so ARM
    conditional branches `b.eq` / `b.ne` / `b.lt` / `b.hi` / etc.
    tokenize as a single `ident`. Same trick captures `.global`,
    `.is_digit_yes` (local label), and bare `.` (current-address)
    uniformly.
  - Operator set adds `!` (write-back addressing mode, e.g.
    `[sp, #-16]!`).
  - Keyword list shares the GAS directive set with `asm_x86_64`
    plus ARM-specific `.arch`, `.cpu`, `.fpu`, `.arm`, `.thumb`,
    `.code`, `.thumb_func`, `.req`, `.unreq`.
  - Opcodes (`mov`, `bl`, `stp`, `ldp`, `ldrb`, `ret`, …) and
    registers (`x0`-`x30`, `w0`-`w30`, `sp`, `pc`, `lr`, …)
    stay `TK_IDENT` per [ADR 0004](docs/adr/0004-shell-builtins-as-ident.md)
    — the ARM aarch64 instruction set is too large to enumerate.
  - **All 7 vidya `asm_aarch64.s` spot-checks come back at zero
    errors** (cleaner than `asm_x86_64`'s 6/7, since ARM has more
    uniform syntax across the corpus and there's no AT&T-vs-Intel
    split). Wired into `bootstrap_grammars`, the smoke loop, and
    five probe assertions in `tests/vyakarana.tcyr` (439 total
    passing). `.s` and `.S` continue to default to `asm_x86_64`
    in `detect_language`; ARM users pass
    `--language=asm_aarch64` explicitly. Content-based dispatch
    is in scope for 1.11.0 (external integrations / detection
    upgrades) per the restructured roadmap.

### Changed

- **Roadmap restructure.** `docs/development/roadmap.md` rewritten
  to reflect the rule that **2.x.x is reserved for breaking
  changes only**. The original "M4–M7 → 2.x" mapping moves into
  pre-2.0 1.x.x cuts: theme-palette contract + vidya reverse
  consumption land in 1.10.0, external integrations (LSP bridge,
  theme export, content-based detection, grammar composition) in
  1.11.0, fuzz/stress harness in 1.12.0, RC polish in 1.13.0.
  **2.0.0 is now the streaming-tokenizer return-type change
  alone** — the one scheduled break in the public API. The old
  "Released" forecast lines for 1.0.1 / 1.1.0 / 1.2.0 (which
  predicted plans that didn't quite happen) are pruned in favour
  of a terse retrospective list of what actually shipped.

## [1.2.2] — 2026-05-08

### Added

- **`asm_x86_64` grammar.** New `grammars/asm_x86_64.cyml` +
  `tests/corpus/asm_x86_64.s` (snapshot of
  `vidya/content/lexing_and_parsing/asm_x86_64.s`, 8167 B,
  1655 tokens at zero `error` kinds). Intel-syntax assembly
  (`.intel_syntax noprefix` declared at the top of the canonical
  sample). `.` is in `ident_start` so `.intel_syntax`,
  `.global`, `.is_digit_yes` (local label), and bare `.`
  (current-address marker) all tokenize as a single ident; the
  `[[rules]] match = "words"` lookup then promotes ~50 known
  GAS directives (`.section`, `.text`, `.global`, `.ascii`,
  `.skip`, `.align`, `.byte`/`.word`/`.long`/`.quad`,
  `.macro`/`.endm`, `.cfi_*`, etc.) to `TK_KEYWORD`. Opcodes
  (`mov`, `call`, `jne`, `xor`, `syscall`, …) and registers
  (`rax`, `rdi`, `eax`, `dil`, …) deliberately stay `TK_IDENT`
  per the [ADR 0004](docs/adr/0004-shell-builtins-as-ident.md)
  pattern — the x86_64 instruction set is too large to enumerate,
  and theme renderers can secondary-palette opcodes via
  token-text rules. `unicode_ident` and `char_literal` are both
  on; line comments are GAS-style `#`. Spot-check: 6 of 7 vidya
  `asm_x86_64.s` samples come back at zero errors. The seventh
  (`binary_formats/asm_x86_64.s`) uses **AT&T syntax**
  (`mov $1, %rax`); the `$` and `%` operand sigils aren't yet
  in any rule. AT&T support is documented in the grammar header
  as a future ADR candidate. Wired into `bootstrap_grammars`,
  `detect_language` (`.s` and `.S` default to `asm_x86_64`; ARM
  users pass `--language=asm_aarch64` explicitly), the smoke
  loop, and four probe assertions in `tests/vyakarana.tcyr`.

### Changed

- **Smoke corpus loop now passes `--language=` explicitly.**
  `scripts/smoke.sh` was previously testing extension dispatch
  alongside the grammar's correctness on its corpus. Splitting
  those concerns: the existing `--list-languages` loop still
  exercises name registration; the corpus round-trip now uses
  the explicit flag so it works for languages that share an
  extension (`.s` belongs to both `asm_x86_64` and the upcoming
  `asm_aarch64`). Behaviourally equivalent for the 13 grammars
  whose extensions don't collide.

## [1.2.1] — 2026-05-08

### Added

- **`char_literal` default flag.** New `[defaults] char_literal
  = true|false` (wired through `Grammar` at offset 144;
  `GRAMMAR_SIZE` 144 → 152), CYML loader, and a new step **7b**
  in the scanner pipeline (between Number and Operator). When on,
  the scanner recognises four char-literal shapes as a single
  `TK_STRING`: `'C'` (3 bytes), `'\C'` (4 bytes simple escape),
  `'\xHH'` (6 bytes hex escape), and 4-/5-/6-byte UTF-8 bodies.
  Returns 0 (yields to the operator step) when no closing `'`
  lands at the right offset, which is what preserves Rust
  lifetimes (`'a`, `'static`, `'_`) — they have no closing quote
  and tokenize as `'` operator + ident as before. Defaults off;
  enabled per-grammar in `grammars/c.cyml`, `grammars/rust.cyml`,
  `grammars/go.cyml`, and `grammars/zig.cyml`. Closes the only
  remaining gap that was producing `TK_ERROR` tokens in the
  vidya corpus: 4 known-failing samples
  (`vidya/content/binary_formats/rust.rs`,
  `vidya/content/error_handling/{rust.rs,go.go,zig.zig}`) all
  drop to zero errors. Five new probe assertions in
  `tests/vyakarana.tcyr` (422 total passing). See [ADR
  0010](docs/adr/0010-char-literal-default.md).
- **Architecture note 002 updated** with the new step 7b row in
  the pipeline-order table and the reasoning for why char-literal
  must precede operator (the lifetime-preservation argument).

## [1.2.0] — 2026-05-08

### Added

- **Go grammar.** New `grammars/go.cyml` + `tests/corpus/go.go`
  (snapshot of `vidya/content/lexing_and_parsing/go.go`, 7402 B,
  2151 tokens at zero `error` kinds). Covers `//` line comments,
  `/* … */` block comments (non-nestable per Go spec §3.4),
  double-quoted strings, the standard C-family operator set plus
  Go-specific `:=` short-var-decl, `<-` channel send/recv, `...`
  variadic, `&^` bit-clear (and their `=`-paired forms), and the
  25 reserved words. Predeclared identifiers (`true`, `false`,
  `nil`, `iota`, `len`, `cap`, `make`, `new`, `append`, …)
  tokenize as `ident`, not `keyword`, per the
  [ADR 0004](docs/adr/0004-shell-builtins-as-ident.md) pattern.
  Spot-check: 6 of 7 vidya `go.go` samples come back at zero
  errors; the seventh (`error_handling/go.go`) hits the
  pre-existing char-literal-with-escape gap (`'\n'`) that C and
  Rust also have. Wired into `bootstrap_grammars`,
  `detect_language` (`.go`), the smoke loop, and four probe
  assertions in `tests/vyakarana.tcyr`.
- **Zig grammar.** New `grammars/zig.cyml` + `tests/corpus/zig.zig`
  (snapshot of `vidya/content/lexing_and_parsing/zig.zig`,
  2279 tokens at zero `error` kinds). `@` is in `ident_start` so
  `@import`, `@as`, `@TypeOf`, etc. tokenize as one `ident`
  (same pragmatic move as Rust's `$` in
  [ADR 0007](docs/adr/0007-rust-dollar-in-ident-start.md);
  builtins-as-ident matches
  [ADR 0004](docs/adr/0004-shell-builtins-as-ident.md)). Operator
  set covers `=>`, `**`, `++`, `..`, plus saturating `+|`/`-|`/`*|`,
  wrapping `+%`/`-%`/`*%`, and their `=`-paired forms. Word-keyword
  set includes `orelse`, `try`, `catch`, `and`, `or`, `unreachable`,
  `comptime`, `errdefer`, etc. (~50 keywords). Spot-check: 6 of 7
  vidya `zig.zig` samples come back at zero errors; the seventh
  hits the same `'\n'` char-literal-escape gap. Wired into
  `bootstrap_grammars`, `detect_language` (`.zig`), the smoke
  loop, and four probe assertions.

### Changed

- **Test suite uses `VYK_VERSION` directly.** `tests/vyakarana.tcyr`
  now `include`s `src/version_str.cyr` and asserts the *shape*
  (`strlen > 4`, `starts with "vyk "`) of the live `VYK_VERSION`
  symbol instead of a stale literal. Eliminates a source of
  drift the version-bump checklist used to miss.
- **`tests/vyakarana.tcyr` "fake-name returns 0" assertions.**
  Replaced the legacy "zig not yet loaded" / "go not yet loaded"
  assertions with `nosuchlang` / empty-string assertions, since
  zig and go are now loaded. The contract being checked
  (unknown-language returns 0) is unchanged.

## [1.1.0] — 2026-05-08

### Added

- **`unicode_ident` default + C block comments.** New
  `[defaults] unicode_ident = true|false` flag (wired through
  `Grammar` record at offset 136; `GRAMMAR_SIZE` 136 → 144),
  CYML loader, and the default scanner — when on, bytes ≥0x80
  are accepted as both `ident_start` and `ident_cont`, so
  multi-byte UTF-8 sequences (em-dashes, smart quotes, accented
  characters) coalesce into a single `TK_IDENT` instead of
  fragmenting into per-byte `TK_ERROR`. Defaults off; enabled
  per-grammar in `grammars/c.cyml` and `grammars/markdown.cyml`.
  `grammars/c.cyml` also gains a `match = "pair"` rule for
  `/* … */` block comments (non-nestable, simple greedy match).
  Verified on `vidya/content/compression/c.c` (8 errors → 0)
  plus six other vidya C samples (all 0). See [ADR
  0009](docs/adr/0009-unicode-ident-default.md).
- **TOML triple-quoted strings.** `grammars/toml.cyml` gains
  `[[rules]]` entries for `"""…"""` (basic, escape-aware) and
  `'''…'''` (literal, no escapes), ordered ahead of the
  single-quoted rules so the longer prefix wins. Verified on
  `vidya/content/compression/concept.toml` (188 `error` tokens
  → 0); seven other vidya `concept.toml` samples likewise
  come back at zero. Pure grammar-file change — no scanner code
  was modified. See [ADR
  0008](docs/adr/0008-toml-triple-quoted-strings.md).
- **Rust macro metavariable support.** `grammars/rust.cyml` now
  has `$` in `ident_start`, so `$expr`, `$tok`, `$crate`, etc.
  tokenize as a single `ident`, and the bare `$` that leads
  `$( … )*` repetition tokenizes as a length-1 ident. Verified
  on `vidya/content/macro_systems/rust.rs` (79 `error` tokens →
  0); 5 of 6 other vidya rust samples come back clean as well
  (the sixth still hits the pre-existing byte-char-literal-with-
  escape gap, unchanged by this commit). See [ADR
  0007](docs/adr/0007-rust-dollar-in-ident-start.md).

### Changed

- **Single source of truth for `vyk --version`.** The CLI version
  literal moved from a hand-edited `var VYK_VERSION = "vyk X.Y.Z"`
  in `src/main.cyr` to a new auto-generated module
  `src/version_str.cyr` that `src/main.cyr` now `include`s. A new
  `scripts/version-bump.sh` (modeled on cyim's and cyrius's)
  regenerates the file from `VERSION` and inserts a CHANGELOG
  header in one shot — same-version invocation is supported as
  the documented "regenerate without bumping" path. Eliminates
  the fourth-file drift that nearly shipped 1.0.3 with `vyk
  --version` still reporting 1.0.2. `version_str.cyr` is
  deliberately not in `[lib] modules` — downstream consumers of
  `dist/vyakarana.cyr` don't need the CLI string.

## [1.0.3] — 2026-05-08

### Changed

- **Toolchain pin bumped to cyrius `5.9.36`** (was `5.6.0` on the
  1.0.2 cut; an interim bump to `5.9.32` was filed as blocked on an
  upstream `include`-graph regression — see
  `docs/development/issues/2026-05-07-cyrius-include-graph-regression.md`).
  The regression is resolved on `5.9.36`: `cyrius build src/main.cyr
  build/vyk` is green, `cyrius test tests/vyakarana.tcyr` reports
  399/399 passing, and `scripts/smoke.sh` reports all M0+M1+M2+M3
  gates passing. No vyakarana sources changed for this cut — the
  release exists to track the new known-good toolchain pin.
- `dist/vyakarana.cyr` regenerated against 1.0.3 (no source-level
  drift; bundle stays at 1806 lines).

## [1.0.2] — 2026-04-23

### Added

- **`[lib]` block in `cyrius.cyml`** driving `cyrius distlib` →
  `dist/vyakarana.cyr`. Five modules concatenated in
  single-pass-safe dependency order: `token → grammar →
  default_scanner → shell (oracle) → tokenize`. Matches the
  pattern used by `bsp` and `yukti`.
- **`dist/vyakarana.cyr`** — single-file bundled distribution
  (~1800 lines, 60KB) committed to the repo. Consumers pull via
  `[deps.vyakarana] git = "..." tag = "1.0.2" modules =
  ["dist/vyakarana.cyr"]`. This unblocks owl's `[deps.vyakarana]`
  adoption.
- `cyrius distlib` invocation in `.github/workflows/ci.yml` with a
  drift check (fails if regenerated bundle differs from committed).
- `release.yml` packaging step now includes `dist/` in the release
  tarball.

## [1.0.1] — 2026-04-23

### Security

- **FINDING-006** (LOW) — `_sanitize_for_stderr` helper added in
  `src/main.cyr` replaces bytes < 0x20 (ASCII C0 controls including
  the 0x1B ESC that anchors every ANSI escape sequence) and 0x7F DEL
  with `?` before echoing user-supplied paths / flags on stderr.
  Wired through `io_error`, `no_grammar_error`, and `usage_error`.
  UTF-8 bytes (≥ 0x80) pass through so non-ASCII paths still echo
  legibly. Smoke script gains an ESC-in-path probe that fails if
  any raw ESC byte reaches stderr. See
  [docs/audit/2026-04-23-audit.md](docs/audit/2026-04-23-audit.md)
  for the original finding.

## [1.0.0] — 2026-04-23

First stable release. All eleven starter grammars ship; default
scanner is data-driven (grammars are CYML files); public API is
`tokenize_source(src, lang)` → `tokenbuf`. Pre-1.0 work compressed
into this header — see each sub-section for the M-by-M arc.

### Added (M3 — all 11 starter grammars shipped)
- `grammars/toml.cyml` + `tests/corpus/concept.toml` — TOML grammar
  as data. Tokenizes the vidya reference sample with zero `error`
  kinds (471 tokens, coverage 10341/10341).
- `grammars/json.cyml` + `tests/corpus/concept.json` — JSON grammar.
  Tokenizes a hand-rolled stand-in corpus (see
  [ADR 0006](docs/adr/0006-standin-corpus-policy.md) for why:
  vidya doesn't ship a JSON reference sample yet). 376 tokens,
  coverage 3380/3380.
- `grammars/cyrius.cyml` + `tests/corpus/cyrius.cyr` — Cyrius
  grammar (vidya-backed). Tokenizes the vidya reference sample
  with zero `error` kinds (2508 tokens, coverage 9233/9233). 7
  distinct keywords detected in corpus (`enum`, `fn`, `for`, `if`,
  `include`, `return`, `var`, `while`).
- `grammars/rust.cyml` + `tests/corpus/rust.rs` — Rust grammar
  (vidya-backed). 2219 tokens, zero errors, coverage 9473/9473.
  18 distinct keywords detected. Multi-char operators covered:
  `=>`, `->`, `::`, `..`, `..=`, `?`. Known gap: char literals
  (`'+'`, `'x'`) and lifetimes (`'_`) currently both tokenize with
  `'` as a standalone operator, so char-literals split into three
  tokens instead of one `string`. Coverage and zero-error bars
  hold. Likely promoted to an ADR once C ships with the same
  char-literal pattern.
- `grammars/yaml.cyml` + `tests/corpus/concept.yaml` — YAML grammar
  (hand-rolled stand-in per ADR 0006). 354 tokens, 0 errors,
  coverage 1863/1863. Keywords: `true`/`false`/`null`/`yes`/`no`/
  `on`/`off`. Anchors `&name`, aliases `*name`, merge key `<<`.
  Plain-scalar permissiveness: operators/punctuation list broadened
  to include ASCII characters that appear unquoted in YAML scalars
  (`;` `.` `(` `)` `/` `%` etc.).
- `grammars/markdown.cyml` + `tests/corpus/concept.md` — Markdown
  grammar (hand-rolled stand-in per ADR 0006). 472 tokens, 0
  errors, coverage 1733/1733. Fenced code blocks (triple-backtick
  pair) ordered before inline code (single backtick pair). ATX
  headings `#`..`######` as longest-match operators; emphasis
  `**`/`__`/`*`/`_`, strikethrough `~~`, blockquote `>`, list `-`
  all tokenize as operators. HTML comments `<!--...-->` via
  multi-byte pair rule → comment.
- **Known non-ASCII gap:** the default scanner treats bytes ≥ 0x80
  (UTF-8 multi-byte sequences) as `TK_ERROR` when they appear
  outside strings/comments. The markdown stand-in corpus swaps
  `—` for `--` to side-step. Next ADR candidate: `unicode_ident =
  true` default making high bytes valid `ident_cont`.
- `grammars/c.cyml` + `tests/corpus/c.c` — C grammar (vidya-backed).
  2451 tokens, 0 errors, coverage 9429/9429. 21 distinct keywords
  detected in corpus (break, case, char, const, default, else,
  enum, for, if, int, long, return, sizeof, static, struct,
  switch, typedef, union, unsigned, void, while). `//` line
  comments; `->`, `++` etc. as multi-char operators;
  `#include <stdio.h>` tokenizes as `#` op + ident + ... (no
  unified preprocessor kind in M3). Added `\` to operators to
  cover char-escape bytes in `'\0'`, `'\n'`, etc.
- `grammars/typescript.cyml` + `tests/corpus/typescript.ts` —
  TypeScript grammar (vidya-backed). 2009 tokens, 0 errors,
  coverage 8473/8473. `//` comments; three pair-rule string types
  (template `` ` ``, double `"`, single `'`) all with backslash
  escape; `$` as ident char; TS-specific multi-char operators
  (`=>`, `??`, `?.`, `**`, `===`, `!==`, `...`). Template
  interpolation `${expr}` stays inside the string span (not
  re-tokenized, per ADR 0003 convention).
- `grammars/javascript.cyml` + `tests/corpus/concept.js` —
  JavaScript grammar (hand-rolled stand-in per ADR 0006). 1275
  tokens, 0 errors, coverage 4827/4827. Shares defaults and three
  string types with TypeScript; keyword list is TS minus the type
  layer (`interface`, `type`, `enum`, `namespace`, visibility
  modifiers, `readonly`, `abstract`, `declare`, `implements`).
- `grammars/python.cyml` + `tests/corpus/python.py` — Python
  grammar (vidya-backed). 1790 tokens, 0 errors, coverage
  8528/8528. Triple-quoted strings via `"""` / `'''` pair rules
  ordered before single-quote pair rules; walrus `:=`, floor-div
  `//`, decorator `@` as operators (NOT `//` as comment — Python
  uses `#`). 22 distinct keywords detected in corpus including
  `match` / `case` (PEP 634 pattern matching).
- **Note on Python indentation:** the semantic INDENT / DEDENT
  tokens a full Python parser would want are NOT emitted —
  indentation tokenizes as plain `whitespace`. Coverage invariant
  and zero-error bars both hold. A consumer needing structural
  indent would post-process whitespace runs at line starts.
  Promoting to an ADR if a consumer actually wants it.
- F-string prefix cosmetic gap: `f"..."` tokenizes as `ident(f)` +
  `string("...")` rather than a unified f-string token. Same
  pattern for r/b/rb/fr prefixes. Coverage holds.
- `detect_language` maps `.sh`/`.bash` → shell, `.toml` → toml,
  `.json` → json, `.cyr` → cyrius, `.cyml` → toml, `.rs` → rust,
  `.yaml`/`.yml` → yaml, `.md`/`.markdown` → markdown, `.c`/`.h`
  → c, `.ts` → typescript, `.js`/`.mjs`/`.cjs` → javascript,
  `.py` → python.
- `--list-languages` emits **all 11 starter grammars**: `shell`,
  `toml`, `json`, `cyrius`, `rust`, `yaml`, `markdown`, `c`,
  `typescript`, `javascript`, `python`.
- `scripts/smoke.sh` M3 section: generic corpus-round-trip loop
  (one line per `lang:corpus` pair) checking exit 0, zero error
  tokens, and coverage invariant.
- 40 new tcyr assertions (17 toml + 17 json + 6 supporting)
  covering grammar load, dashed-ident behavior, signed numbers,
  keywords, and JSON structural tokens (307 total).
- [ADR 0006](docs/adr/0006-standin-corpus-policy.md) —
  stand-in corpus policy for languages vidya doesn't yet cover.

### Added (M2)
- CYML grammar loader: `grammar_load("grammars/<lang>.cyml")` parses
  a grammar file into a `Grammar` record with `[grammar]` / `[defaults]`
  / `[[rules]]` sections (minimal TOML dialect — quoted strings,
  booleans, string arrays; arrays may span lines).
- Data-driven default scanner (`src/grammars/default_scanner.cyr`)
  tokenizes any grammar's source with configured shebang / line /
  pair / words / ident / number / operator / punctuation /
  whitespace / special-var stages. Scanner dispatch follows
  [ADR 0005](docs/adr/0005-m2-rule-type-scope.md).
- `grammars/shell.cyml` — the shell grammar as data. Produces
  byte-identical NDJSON to the hand-coded `tokenize_shell` on
  `tests/corpus/shell.sh` (regression check enforced by smoke.sh).
- Grammar registry (`src/grammar.cyr`) with lazy bootstrap:
  `tokenize_source` / `has_grammar` / `print_list_languages` all
  trigger the load of bundled grammars on first use.
- `char_class_new(spec)` / `char_class_match(tbl, b)` — 256-byte
  lookup tables for ident starts/continuations, built from specs
  like `"A-Za-z_"`.
- `vyk --handcoded` — undocumented diagnostic flag routing through
  the M1 hand-coded path, used by the smoke-script regression diff.
- 178 new tcyr assertions covering the grammar loader, char-class
  helper, and a cross-tokenizer equality check on 5 probe inputs
  (267 total assertions).
- `cyml` added to `cyrius.cyml [deps] stdlib`.

### Changed (M2)
- `tokenize_source(src, "shell")` now goes through the CYML-loaded
  grammar rather than a hand-coded `if streq(lang, "shell")` branch.
- `--list-languages` enumerates from the registry (was hardcoded
  `println("shell")` in M1).
- `has_grammar(lang)` consults the registry.
- Hand-coded `tokenize_shell` retained on disk as a regression oracle
  (per [ADR 0005](docs/adr/0005-m2-rule-type-scope.md)); will be
  removed in a follow-up once M3 has additional grammars.

### Added (M1)
- Hand-coded shell tokenizer (`src/grammars/shell.cyr`) with full
  recognizers for shebang, comments, strings (single/double, escape-
  aware), keywords, identifiers, numbers (decimal / 0x / 0b / 0o),
  operators (1-char, 2-char, `<<<`), punctuation (including `[[`,
  `]]`, `((`, `))`, `;;`), and whitespace. Fallthrough to `TK_ERROR`
  preserves the coverage invariant.
- `tokenbuf` — contiguous 12-byte Token record buffer in
  `src/token.cyr`. Satisfies design-spec §6 "no allocations per
  token." See [ADR 0002](docs/adr/0002-token-storage-layout.md)
  for the storage choice.
- `vyk <file>` tokenizes a file and prints NDJSON tokens on stdout
  (`{"kind":"keyword","start":0,"len":2}`). Exit code 0 on success,
  1 if any `error` tokens, 3 on I/O error, 4 when no grammar matched.
- `vyk --language=<lang>` overrides extension-based detection.
- Extension detection: `.sh` and `.bash` → `shell`.
- `tests/corpus/shell.sh` — snapshot of vidya's shell sample;
  tokenizes with zero `error` kinds and holds the coverage invariant.
- 58 new M1 test assertions in `tests/vyakarana.tcyr` covering known
  offsets, shebang vs. comment, strings, numbers, operators, and the
  no-error-tokens contract.
- Smoke-script M1 section: round-trips the corpus, asserts zero
  error kinds, verifies coverage sum, checks `--language=shell`
  override on an extensionless file.

### Changed
- `tokenize_source(src, "shell")` now returns a `tokenbuf` handle
  instead of `0`. Calls for unknown languages still return `0`.
  (Pre-1.0 signature evolution; argument shape unchanged.)
- `has_grammar("shell")` returns 1.
- `--list-languages` prints `shell`.

## [0.1.0]

### Added
- Initial project scaffold
- Token kind palette (10 kinds: ident, keyword, string, number, comment,
  operator, punctuation, whitespace, preprocessor, error)
- Token/Span type stubs — layout locked for consumer imports (owl M3b)
- Grammar record stub (loader follows in M2)
- Tokenize runtime stub (hand-coded grammars land in M1)
- `vyk` demo binary — prints version + token-kind list
- CI workflow, smoke script, test harness
