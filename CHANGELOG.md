# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

_No unreleased changes._

## [1.11.0] — 2026-05-08

Second pre-2.0 prep wave, first sub-cut. The 1.11.x window
splits the original "external integrations" plan into three
sequential cuts so each lands cleanly:
- **1.11.0 — LSP semantic-tokens bridge (this cut).**
- 1.11.1 — Grammar composition (embedded blocks) + theme
  export.
- 1.11.2 — Content-based language detection.

### Added

- **LSP semantic-tokens bridge.** New `src/lsp.cyr` module
  with two pure functions:
  - `lsp_kind_from_token_type(name)` — string lookup.
  - `lsp_kind_from_standard_index(idx)` — integer-index
    lookup using LSP 3.17's standard 23-entry legend.
  Maps the LSP semantic-token taxonomy onto vyakarana's 10
  TK_* kinds. Direct matches for `keyword` / `comment` /
  `string` / `number` / `operator`; `regexp` collapses to
  `TK_STRING`; `modifier` → `TK_KEYWORD`; `macro` and
  `decorator` → `TK_PREPROCESSOR`; the 14 ident-flavoured
  types (`function` / `method` / `variable` / `parameter` /
  `class` / `interface` / `struct` / `enum` / `enumMember` /
  `event` / `namespace` / `type` / `typeParameter` /
  `property`) all → `TK_IDENT`. Unknown / extended-legend
  names → `TK_IDENT` (safe default; never `TK_ERROR`).
  Lets editor consumers (cyim, VS Code clients, future
  AGNOS editors) present a unified palette regardless of
  whether vyakarana or a Language Server (rust-analyzer,
  gopls, pyright, clangd, etc.) classified the bytes.
  Theme files index by `kind_name` strings per
  [architecture note 004](docs/architecture/004-theme-palette-contract.md);
  the bridge means LSP output flows through the same name
  set without forking the theme. See [ADR
  0012](docs/adr/0012-lsp-semantic-tokens-bridge.md).
- **`src/lsp.cyr` is in `[lib] modules`** so it ships in
  `dist/vyakarana.cyr`. Downstream consumers get the bridge
  for free; there's no extra `[deps]` step beyond the
  existing `[deps.vyakarana]` block.

### Wiring

- `cyrius.cyml` — `[lib] modules` extended with
  `src/lsp.cyr`.
- `tests/vyakarana.tcyr` — 38 new probe assertions covering
  every standard LSP token type by name, the index-based
  path, and the unknown-name / out-of-range fallbacks.
  636 → 674 passing.

### Out of scope (deliberately)

- **JSON-RPC / wire-protocol decoding.** Consumers handle
  their own LSP transport; vyakarana doesn't include an LSP
  client.
- **Encoded semantic-tokens stream decoding.** LSP's
  `data: number[]` array is delta-encoded
  `[deltaLine, deltaStart, length, tokenType, modifiers]`
  per token. Consumers walk the array themselves and call
  `lsp_kind_from_standard_index` (or the name-based path
  via their legend).
- **Reverse mapping (vyakarana → LSP).** Different design
  space; not needed today.

## [1.10.0] — 2026-05-08

First **pre-2.0 prep wave**. Different shape from the
language batches (1.3 – 1.9): no new grammars, but a
substantial new CLI feature, an architecture-level contract
documented for downstream consumers, and a guide for building
on top of vyakarana. The 1.10 – 1.13 prep waves bring the
1.x line to the doorstep of 2.0.0 (the streaming-tokenizer
break).

### Added

- **`vyk --theme=<name>` flag.** Renders ANSI-coloured source
  bytes instead of NDJSON. Three bundled themes:
  - `default` — moderate-saturation palette tuned for
    light-background terminals. Reference palette for
    consumers writing their own themes.
  - `dark` — bright variants tuned for dark-background
    terminals.
  - `none` — strips colour entirely. Useful for piping or
    non-tty contexts.
  Implementation lives in new `src/theme.cyr`; rendering
  walks the tokenbuf, emits the theme's ANSI prefix per kind,
  the source bytes for that span, and a reset escape.
  `theme_resolve("name")` → integer tag; unknown names exit
  with `EXIT_USAGE`. The theme module is **not** in `[lib]
  modules` — it's CLI-only; downstream consumers build their
  own renderers per the guide below.
- **Architecture note 004 — theme-palette contract.** New
  document at
  [`docs/architecture/004-theme-palette-contract.md`](docs/architecture/004-theme-palette-contract.md).
  Codifies the kind → palette slot mapping (the 10 token
  kinds, indexed by `kind_name(k)` strings) as a stable
  contract across the 1.x line. **Renaming a `kind_name` is
  breaking** (silent fallback in consumer themes). Adding an
  eleventh kind is breaking. The 10-slot floor stays — finer
  distinctions are renderer-side, applied via secondary
  palettes that introspect token text (the pattern from
  [ADR 0004](docs/adr/0004-shell-builtins-as-ident.md) and
  [ADR 0007](docs/adr/0007-rust-dollar-in-ident-start.md)).
- **Consumer integration guide.** New document at
  [`docs/guides/consumer-integration.md`](docs/guides/consumer-integration.md).
  Audience: implementers of renderers / editors / themes /
  content pipelines that sit on top of vyakarana. Covers
  `[deps.vyakarana]` setup, the public API surface
  (`tokenize_source` / tokenbuf accessors / kind constants),
  how to render via the kind-name lookup, the zero-copy
  invariant, lazy registry loading, error handling against
  the coverage invariant, the corpus-sync boundary, and
  performance expectations through 2.0.0.

### Wiring

- `src/main.cyr` — added `--theme=<name>` parsing alongside
  `--language=<lang>`, and the rendering dispatch in
  `tokenize_file`. `--help` updated to document the new flag.
- `src/theme.cyr` — new file. Three theme functions
  (`theme_default_color`, `theme_dark_color`, `theme_color`),
  the resolver (`theme_resolve`), and a constant for the
  reset escape. ASCII-only ANSI colour codes; no UTF-8 in
  the theme module itself.
- `tests/vyakarana.tcyr` — 14 new probe assertions covering
  theme name resolution (5 cases including unknown / empty),
  per-kind colour lookup for `default` / `dark` / `none`,
  cross-theme differentiation, and the reset escape. 622 →
  636 passing.
- `scripts/smoke.sh` — three new probes covering
  `--theme=default` (non-empty output containing ESC bytes),
  `--theme=none` (no ESC bytes), and `--theme=nope`
  (`EXIT_USAGE`).
- `docs/architecture/README.md` — index extended with note
  004.

## [1.9.0] — 2026-05-08

AGNOS-native language batch. Two new grammars in one cut: CYML
and LLVM-IR. **Self-hosting payoff at this cut** — vyakarana
can now tokenize its own grammar files (`grammars/*.cyml`) with
its own grammar. The CYML corpus is the **first non-stand-in
sample for a 1.x post-M3 grammar**: vidya already ships
`content/cyrius/dependencies.cyml`, so we snapshotted that
directly. No new scanner extensions needed; the multi-byte
operator (`---`) and the now-familiar sigil-in-`ident_start`
trick (this time for `@`/`%`/`!` in LLVM-IR) cover both.

### Added

- **CYML grammar.** New `grammars/cyml.cyml` +
  `tests/corpus/dependencies.cyml` (vidya snapshot of
  `vidya/content/cyrius/dependencies.cyml`, 10644 B, 659
  tokens at zero errors). The format is a TOML-shaped header
  optionally followed by `---`-delimited markdown bodies, in
  alternation. **`---` is a 3-byte operator**; backtick spans
  `` `…` `` are pair rules emitting `TK_STRING`. Otherwise the
  grammar reuses TOML's surface (`[section]`, `[[array]]`,
  `key = value`, single + double-quoted strings, `#` line
  comments, decimal / hex / octal / binary numbers).
  **Self-hosting:** `build/vyk grammars/cyml.cyml` produces
  zero errors — vyakarana can now colour its own grammar
  files, yukti config, and vidya content samples through one
  bundled grammar. Also: `detect_language` now routes `.cyml`
  to the `cyml` grammar (previously routed to `toml` as a
  best-effort fallback per the old comment in `src/main.cyr`).
- **LLVM-IR grammar.** New `grammars/llvm_ir.cyml` +
  `tests/corpus/concept.ll` (1194 tokens, zero errors).
  ADR 0006 stand-in. **`@`, `%`, `!` in `ident_start`** so
  `@global_count`, `%struct.Token`, `!llvm.module.flags` all
  tokenize as one ident — the same pragmatic move that's
  paid forward across Java annotations (1.3.0), Zig builtins
  (1.2.0), Rust macros ([ADR 0007](docs/adr/0007-rust-dollar-in-ident-start.md)),
  Elixir module attributes (1.5.0), and PHP variables
  (1.4.0). `;` line comments. Comprehensive keyword list
  covering type literals (`i8`/`i32`/`i64`/`ptr`/`void`/
  `label`/`metadata`), the LLVM instruction set
  (terminators, unary/binary/atomic/cast/memory ops),
  function attributes, parameter attributes, calling
  conventions, comparison predicates (`eq`/`ne`/`ult`/`uge`/
  `slt`/`sge`/`ord`/`oeq`/etc.), and reserved literals
  (`null`/`undef`/`poison`/`zeroinitializer`).

### Wiring

- `src/tokenize.cyr` — both added to `bootstrap_grammars()`
  (now loads 38 grammars).
- `src/main.cyr` — `.cyml` redirected from `toml` to `cyml`;
  `.ll` added for LLVM-IR.
- `scripts/smoke.sh` — both added to `--list-languages` check
  (now 38 grammars) and the corpus round-trip loop.
- `tests/vyakarana.tcyr` — three CYML probes (`[[array]]`
  table header, `---` 3-byte operator, backtick string),
  five LLVM-IR probes (`define` keyword, `i32` type keyword,
  `@global` ident, `%struct.Token` ident, `!llvm.module.flags`
  ident, `getelementptr` keyword). 599 → 622 passing.

## [1.8.0] — 2026-05-08

DevOps + infrastructure language batch. Three new grammars in
one cut: Dockerfile, Makefile, INI. All three ship with
stand-in corpora per
[ADR 0006](docs/adr/0006-standin-corpus-policy.md). No new
scanner extensions; both case-insensitive keyword matching
(ADR 0011, originally for SQL) and the `special_vars` flag
(originally for shell) paid forward — Dockerfile reuses the
former for instruction heads, Makefile reuses the latter for
automatic variables.

### Added

- **Dockerfile grammar.** New `grammars/dockerfile.cyml` +
  `tests/corpus/Dockerfile` (284 tokens, zero errors).
  **Case-insensitive instruction heads via ADR 0011** —
  `FROM` / `from` / `From` all match the canonical UPPER
  keyword list. Filename-matched (Dockerfile uses no
  extension): `detect_language` checks suffix `Dockerfile` or
  `Containerfile`, covering `./Dockerfile`,
  `/path/to/Dockerfile`, `name.Dockerfile`. Variants like
  `Dockerfile.dev` need explicit `--language=dockerfile`.
- **Makefile grammar.** New `grammars/makefile.cyml` +
  `tests/corpus/Makefile` (671 tokens, zero errors). All four
  GNU Make assignment forms (`=`, `:=`, `?=`, `+=`, `!=`).
  Automatic variables `$@`/`$?`/`$*` work via the existing
  `special_vars` flag (built for shell, char-set is `#`/`?`/
  `@`/`!`/`*`/`$`/`-`). The remaining auto-vars `$<`/`$^`/
  `$%`/`$+`/`$|` gracefully degrade to `$` op + char op —
  documented as a deliberate trade-off (extending the shared
  helper would risk false positives in shell). Conditional /
  include / define / export directives in keyword list.
  Filename-matched: `Makefile`, `makefile`, `GNUmakefile`.
- **INI grammar.** New `grammars/ini.cyml` +
  `tests/corpus/concept.ini` (327 tokens, zero errors). Both
  `;` and `#` line-comment forms; `[section]` headers; quoted
  and unquoted values. `.` in `ident_cont` so dotted-key
  sections like `[auth.providers.github]` tokenize as one
  ident. Default extension covers `.ini`/`.conf`/`.cfg`/
  `.properties` — captures most modern .conf-file shapes
  (.gitconfig, .editorconfig, systemd unit files, php.ini,
  pip / setuptools config families). nginx-specific syntax
  deferred (curly-brace blocks aren't INI-shape; if a real
  nginx corpus surfaces, fork from this grammar).

### Wiring

- `src/tokenize.cyr` — all three added to `bootstrap_grammars()`
  (now loads 36 grammars).
- `src/main.cyr` — extension dispatch: `.ini`/`.conf`/`.cfg`/
  `.properties`. Filename-suffix dispatch for Dockerfile +
  Containerfile and Makefile + makefile + GNUmakefile.
- `scripts/smoke.sh` — all three added to `--list-languages`
  check (now 36 grammars) and the corpus round-trip loop.
- `tests/vyakarana.tcyr` — three Dockerfile probes (mixing
  UPPER / lower / Mixed instruction heads to exercise ADR
  0011), three Makefile probes (`:=` op, `$@` auto-var,
  `ifeq` keyword), four INI probes (section header, both
  comment forms, dotted-section ident). 577 → 599 passing.

## [1.7.0] — 2026-05-08

Markup + styling language batch. Four new grammars in one cut:
HTML, XML, CSS, SCSS. All four ship with stand-in corpora per
[ADR 0006](docs/adr/0006-standin-corpus-policy.md). No new
scanner extensions; the multi-byte-pair-rule shape introduced
for TOML triple-quoted strings ([ADR 0008](docs/adr/0008-toml-triple-quoted-strings.md))
handled HTML's `<!-- … -->` (4-byte / 3-byte) and XML's
`<![CDATA[ … ]]>` (10-byte / 3-byte) without further work.
LESS deferred — declining adoption, and most LESS files
tokenize OK with the css.cyml grammar anyway.

### Added

- **HTML grammar.** New `grammars/html.cyml` +
  `tests/corpus/concept.html` (249 tokens, zero errors).
  `<!-- … -->` block comments via 4-byte / 3-byte pair rule;
  single + double-quoted attribute strings; `<` / `>` / `=` /
  `/` / `&` / `!` / `?` / `#` as operators. Tag names
  tokenize as plain ident (HTML5's open element set + custom
  elements is too large for a keyword list). Embedded
  `<style>` and `<script>` blocks tokenize as plain HTML at
  this layer; grammar composition for routing them to CSS / JS
  is on the **1.11.0** roadmap.
- **XML grammar.** New `grammars/xml.cyml` +
  `tests/corpus/concept.xml` (380 tokens, zero errors). Same
  shape as HTML plus `<![CDATA[ … ]]>` data sections (kind =
  string; body uninterpreted) and `<?xml … ?>` processing
  instructions (kind = preprocessor). `-` added to operators
  so ISO-8601 date components (`2026-05-08T09:00:00Z`)
  tokenize cleanly. Default extension for `.xml` / `.xsl` /
  `.xsd` / `.svg`.
- **CSS grammar.** New `grammars/css.cyml` +
  `tests/corpus/concept.css` (689 tokens, zero errors).
  `/* */` only (no line-comment form). `@`/`#`/`-` in
  `ident_start` so `@media`, `#hero`, and `--color-bg`
  (CSS custom properties) all tokenize as a single ident; the
  words rule then promotes the standard CSS at-rules
  (`@charset`/`@import`/`@media`/`@supports`/`@keyframes`/
  `@layer`/`@container`/`@scope`/etc.) to keyword. `::`
  pseudo-element op; attribute matchers `^=`/`$=`/`*=`/`~=`/
  `|=`. Float literals (`1.5rem`) deferred — the number
  scanner stops at `.` (same gap as java.cyml; would benefit
  multiple grammars).
- **SCSS grammar.** New `grammars/scss.cyml` +
  `tests/corpus/concept.scss` (526 tokens, zero errors). CSS
  superset: `//` line comments, `$variable` syntax (`$` joins
  `@`/`#`/`-` in `ident_start`), and SCSS-specific at-rules
  (`@mixin`/`@include`/`@function`/`@return`/`@if`/`@else`/
  `@each`/`@for`/`@while`/`@use`/`@forward`/`@extend`/
  `@error`/`@warn`/`@debug`/`@content`/`@at-root`) added to
  the keyword list. Modern Sass `@use` / `@forward` module
  syntax exercised in the stand-in.

### Wiring

- `src/tokenize.cyr` — all four added to `bootstrap_grammars()`
  (now loads 33 grammars).
- `src/main.cyr` — extension dispatch: `.html`/`.htm`,
  `.xml`/`.xsl`/`.xsd`/`.svg`, `.css`, `.scss`/`.sass`.
- `scripts/smoke.sh` — all four added to `--list-languages`
  check (now 33 grammars) and the corpus round-trip loop.
- `tests/vyakarana.tcyr` — two HTML probes (block comment +
  self-closing tag), two XML probes (CDATA + processing
  instruction), four CSS probes (`@media` keyword, `#hero`
  ident, `--color-bg` ident, `::` pseudo-element op), three
  SCSS probes (`$var` ident, `@mixin` keyword, `//` line
  comment). 544 → 577 passing.

## [1.6.0] — 2026-05-08

Data / query / IDL language batch. Three new grammars + one new
scanner default in one cut: SQL, GraphQL, Protobuf, plus
`case_insensitive_keywords` ([ADR 0011](docs/adr/0011-case-insensitive-keywords-default.md))
to make the SQL grammar work without doubling its keyword list.

### Added

- **`case_insensitive_keywords` default flag.** New
  `[defaults] case_insensitive_keywords = true|false`, wired
  through `Grammar` at offset 152 (`GRAMMAR_SIZE` 152 → 160),
  CYML loader, and `_ds_lookup_keyword` in the default
  scanner. When on, the words-rule lookup folds A–Z to a–z on
  both sides of the comparison so `SELECT` / `select` /
  `Select` all match the canonical (upper-case) keyword list.
  ASCII-only fold by design — UTF-8 case folding is out of
  scope. Defaults off; enabled in `grammars/sql.cyml`. Two new
  helpers in `src/grammars/default_scanner.cyr`:
  `_ds_to_lower(b)` and `_ds_word_match(src, start, w, wlen,
  fold)` — the latter delegates to `memeq` when fold=0 so
  existing 25 grammars hit zero new hot-path cost. See [ADR
  0011](docs/adr/0011-case-insensitive-keywords-default.md).
- **SQL grammar.** New `grammars/sql.cyml` +
  `tests/corpus/concept.sql` (599 tokens, zero errors).
  Dialect-neutral baseline (ANSI SQL:1992 core surface);
  PostgreSQL / MySQL / SQLite / T-SQL extensions documented as
  fork candidates in the grammar header. `--` line + `/* */`
  block comments. Single-quoted strings; double-quoted strings
  (which are technically identifiers in standard SQL) tokenize
  as `TK_STRING` — themes can re-classify by token text.
  Operators include `<>` (ANSI not-equal), `||` (string
  concat), `::` (PostgreSQL cast). Keyword list covers DDL,
  DML, joins, CTE/window, set-op, constraints, CASE, types,
  transaction, and reserved literals.
- **GraphQL grammar.** New `grammars/graphql.cyml` +
  `tests/corpus/concept.graphql` (623 tokens, zero errors).
  `$` and `@` in `ident_start` (operation variables /
  directives — `$id`, `@deprecated` tokenize as one ident).
  `"""…"""` block strings via pair rule ahead of `"…"`. `#`
  line comments. Minimal operator set (`!`, `=`, `|`, `&`,
  `...`). Keywords cover schema-definition (`type`/`enum`/
  `union`/`scalar`/`input`/`interface`/`directive`), operation
  heads (`query`/`mutation`/`subscription`/`fragment`),
  modifiers (`implements`/`extend`/`repeatable`).
- **Protobuf grammar.** New `grammars/protobuf.cyml` +
  `tests/corpus/concept.proto` (628 tokens, zero errors).
  Mechanical C-family at the token level. Primitive types
  (`int32`/`int64`/`uint32`/`string`/`bytes`/etc.) and SDL
  heads (`message`/`enum`/`service`/`rpc`/`oneof`/`map`/
  `repeated`/`reserved`) as keywords. Both proto2 and proto3
  surface covered.

### Wiring

- `src/tokenize.cyr` — all three added to `bootstrap_grammars()`
  (now loads 29 grammars).
- `src/main.cyr` — extension dispatch: `.sql`, `.graphql`/`.gql`,
  `.proto`.
- `scripts/smoke.sh` — all three added to `--list-languages`
  check (now 29 grammars) and the corpus round-trip loop.
- `tests/vyakarana.tcyr` — five SQL probes (mixing UPPER /
  lower / Mixed case to exercise ADR 0011), four GraphQL
  probes, three Protobuf probes. 517 → 544 passing.

## [1.5.0] — 2026-05-08

Functional tier language batch. Three new grammars in one cut:
Elixir, OCaml, Haskell. All three ship with stand-in corpora per
[ADR 0006](docs/adr/0006-standin-corpus-policy.md). **No new
scanner extensions were needed**; OCaml's `'a` type variables
fall through the existing char_literal helper's lifetime-
preservation logic ([ADR 0010](docs/adr/0010-char-literal-default.md))
exactly the way Rust's lifetimes do. Three grammar-author
findings worth recording:
- **Elixir uses `%` as a struct/map literal prefix** (NOT
  modulo). Adding it to operators avoids the error fallback;
  themes can secondary-palette by token-text.
- **Haskell allows `'` as ident-continuation** (prime suffix:
  `rest'`, `f''`). Putting `'` in `ident_cont` (not
  `ident_start`) is enough; char literals still route through
  step 7b first since `char_literal` runs before ident scan
  for cursor positions starting with `'`.
- **OCaml needs `'` in operators** so its char_literal yield
  path (no closing quote at the right offset) can fall through
  to the `'a`-as-`'`-plus-ident shape — same pattern Rust has
  used since 1.2.1.

### Added

- **Elixir grammar.** New `grammars/elixir.cyml` +
  `tests/corpus/concept.ex` (1646 tokens, zero errors). `@` in
  `ident_start` (module attributes). Operators include `|>`
  (pipe), `<-` (generator/receive), `->` (anonymous fn / case
  clause), `=>` (map key/value), `::` (type spec), `<>` (string
  concat), `++`/`--` (list concat/subtract), `..` (range), `=~`
  (regex match), `&&&`/`|||` (bitwise), `===`/`!==` (strict
  equality). **`%` in operators** (struct/map literal prefix).
  `"""…"""` heredoc strings via pair rule ahead of `"…"`.
- **OCaml grammar.** New `grammars/ocaml.cyml` +
  `tests/corpus/concept.ml` (1463 tokens, zero errors).
  `(* … *)` block comments via pair rule (nestable per spec —
  same simple-greedy gap as Rust). `'a` type variables work
  via the char_literal yield path: the helper returns 0 when
  no closing quote at offset 2, leaving `'` to tokenize as
  operator on the next pass and `a` as ident. **`'` added to
  operators** to complete that fall-through. Operators
  otherwise include `|>`, `<-`, `:=`, `->`, `@@`, `<>`, `**`.
- **Haskell grammar.** New `grammars/haskell.cyml` +
  `tests/corpus/concept.hs` (1357 tokens, zero errors). `--`
  line comments + `{- … -}` block comments via pair rule
  (nestable in spec — same Rust-shared gap). **`'` in
  `ident_cont`** so prime-suffixed names like `rest'`,
  `f''`, `xs'` tokenize as a single ident; standalone `'` for
  char literals still routes through step 7b first since the
  scanner pipeline runs char_literal before checking ident.
  Operators include the monadic / applicative surface
  (`>>=`, `>>`, `=<<`, `>=>`, `<=<`, `<$>`, `<*>`, `<|>`,
  `<>`), `::` type ascription, `\` lambda head, and `` ` ``
  for infix-function syntax.

### Wiring

- `src/tokenize.cyr` — all three added to `bootstrap_grammars()`
  (now loads 26 grammars).
- `src/main.cyr` — extension dispatch: `.ex`/`.exs`,
  `.ml`/`.mli`, `.hs`/`.lhs`.
- `scripts/smoke.sh` — all three added to `--list-languages`
  check (now 26 grammars) and the corpus round-trip loop.
- `tests/vyakarana.tcyr` — three or four probe assertions per
  grammar covering load + name + grammar-specific shapes
  (`|>` pipe, `%` struct literal, `(* *)` block comment, `'a`
  type-var-as-operator, `'a'` char-literal-as-string,
  `{- -}` block comment, prime-suffixed ident, `>>=` bind).
  495 → 517 passing. One probe miss caught during the cut:
  OCaml's `'a` test originally returned `TK_ERROR` because `'`
  wasn't in the operators list — fixed by adding it, with a
  comment explaining the lifetime-preservation fall-through.

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
