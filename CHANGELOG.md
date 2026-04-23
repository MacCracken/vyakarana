# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added (M3, in progress)
- `grammars/toml.cyml` + `tests/corpus/concept.toml` — TOML grammar
  as data. Tokenizes the vidya reference sample with zero `error`
  kinds (471 tokens, coverage 10341/10341).
- `grammars/json.cyml` + `tests/corpus/concept.json` — JSON grammar.
  Tokenizes a hand-rolled stand-in corpus (see
  [ADR 0006](docs/adrs/0006-standin-corpus-policy.md) for why:
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
- `detect_language` maps `.sh`/`.bash` → shell, `.toml` → toml,
  `.json` → json, `.cyr` → cyrius, `.cyml` → toml (the CYML format
  is TOML-shaped; see `detect_language` comment), `.rs` → rust.
- `--list-languages` emits `shell`, `toml`, `json`, `cyrius`, `rust`.
- `scripts/smoke.sh` M3 section: generic corpus-round-trip loop
  (one line per `lang:corpus` pair) checking exit 0, zero error
  tokens, and coverage invariant.
- 40 new tcyr assertions (17 toml + 17 json + 6 supporting)
  covering grammar load, dashed-ident behavior, signed numbers,
  keywords, and JSON structural tokens (307 total).
- [ADR 0006](docs/adrs/0006-standin-corpus-policy.md) —
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
  [ADR 0005](docs/adrs/0005-m2-rule-type-scope.md).
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
  (per [ADR 0005](docs/adrs/0005-m2-rule-type-scope.md)); will be
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
  token." See [ADR 0002](docs/adrs/0002-token-storage-layout.md)
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
