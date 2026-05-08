# Security policy — vyakarana

## Reporting a vulnerability

Email **cyriusmaccken@gmail.com** with subject prefix
`[vyakarana security]`. Or open a private security advisory
through GitHub's Security tab.

Please don't open public issues for vulnerabilities until a fix
ships. A response acknowledging receipt typically lands within a
few days. vyakarana is a single-maintainer project; we'll work
with you on disclosure timing.

## Threat model

vyakarana is a **library that tokenizes arbitrary source bytes**.
It has no network surface, no syscalls beyond `mmap`/`read` for
the optional file-reading entry points, and no privileged
operations. The tokenizer's correctness contract is the
**coverage invariant**: every input byte is accounted for in
exactly one output token, with `error` kinds emitted (not
silently dropped) when no other rule matches.

Trust boundary:

- **Source bytes** (the `src` argument to `tokenize_source`) are
  **untrusted**. Bounds checks on every `load8 / store8 / alloc(N)`
  derived from input length are the contract — see
  `tests/vyakarana.tcyr` and the `docs/audit/` reports.
- **Grammar files** (`grammars/*.cyml`, parsed by `src/grammar.cyr`)
  ship in the repo and are part of the library's trusted
  surface. A consumer that loads its own `.cyml` from an
  attacker-controlled path is responsible for that path's
  trust — the parser still bounds-checks, but the surface there
  is "library trusts the caller's choice of grammar."
- **`vyk` CLI** reads files up to `VYK_SRC_CAP` (1 MB at 1.1.0)
  via `file_read_all`. Larger files are rejected; the cap
  changes when M5's streaming tokenizer lands.

## What's in scope

- Memory safety: out-of-bounds reads/writes in the scanner,
  `tokenbuf`, or grammar loader.
- Integer overflow in length / offset / token-count math.
- Coverage-invariant violations: input bytes that produce zero
  tokens, or token spans that overlap / leave gaps.
- Unbounded allocation traceable to attacker-controlled input
  (input size, token count, grammar shape).
- ANSI-escape injection through CLI error messages — sanitised
  in 1.0.1 (FINDING-006); regressions in scope.
- Adversarial `.cyml` grammar files crashing or hanging the
  loader.
- Public-API misuse that produces undefined behaviour rather
  than an error return — e.g. `tokenize_source` with a NULL or
  negative length.

## What's out of scope (file as feature requests instead)

- Cosmetic tokenization gaps where coverage holds and no `error`
  tokens are emitted (char-literal splitting, INDENT/DEDENT in
  Python, etc.) — see `docs/development/state.md` "Known cosmetic gaps."
- Performance regressions without a security angle — file a perf
  issue, reference the bench CSV when one exists.
- Tokenizing invalid source code "wrong" — vyakarana is a
  tokenizer, not a validator. A real parser will reject
  malformed input for its own reasons.

## Past audits

- [2026-04-23 — Pre-1.0 security audit](docs/audit/2026-04-23-audit.md)
  — 0 CRITICAL, 0 HIGH, 1 MEDIUM (per-ident `alloc(8)` removed
  in-pass), 5 LOW. Known-CVE review covered ReDoS, unbounded
  recursion, deserialization-RCE, modeline-escape, and
  buffer-overflow-in-parser classes — vyakarana is immune by
  design to all of them. FINDING-006 (ANSI-escape on echoed
  argv, LOW) was fixed in 1.0.1.
- [2026-05-08 — 1.2.x closeout audit](docs/audit/2026-05-08-1.2.x-closeout-audit.md)
  — covers everything since the 2026-04-23 baseline:
  `unicode_ident` (1.1.0), `char_literal` (1.2.1), and four new
  grammar files (Go, Zig, asm_x86_64, asm_aarch64). 0 CRITICAL,
  0 HIGH, 0 MEDIUM, 0 new LOW. Bounds checks on every new
  `load8` / `alloc` reviewed and confirmed.

State at v1.2.4: 0 CRITICAL, 0 HIGH, 0 MEDIUM. The 2026-04-23
baseline findings carry forward unchanged. Next scheduled audit
is the 1.13.0 RC-polish closeout, or sooner if 1.10.x / 1.11.x
adds public-API surface.
