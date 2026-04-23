# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
