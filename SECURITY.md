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
It has no network surface and no privileged operations; its only
syscalls are memory allocation and, in `grammar_load`, opening and
reading one grammar file (the `vyk` CLI also reads its input and
writes its output). The tokenizer's correctness contract is the
**coverage invariant**: every input byte is accounted for in
exactly one output token, with `error` kinds emitted (not
silently dropped) when no other rule matches.

Trust boundary:

- **Source bytes** are **untrusted**: the bytes handed to
  `tokenize_stream_feed`, to `tokenize_doc_set` and `tokenize_doc_edit`,
  and to `detect_language_from_content`, `_combined` and `_registered`.
  Bounds checks on every `load8 / store8 / alloc(N)` derived from input
  length are the contract — see `tests/vyakarana.tcyr` and the
  `docs/audit/` reports. An edit's description is checked only for
  its lengths: `tokenize_doc_edit` refuses an edit that does not fit
  the text, but trusts that the text it is passed is the old text with
  that edit applied (ADR 0033; `docs/development/state.md`, Known
  limits).
- **Grammar files** (`grammars/*.cyml`, parsed by `src/grammar.cyr`)
  ship in the repo and are part of the library's trusted
  surface. A consumer that loads its own `.cyml` from an
  attacker-controlled path is responsible for that path's
  trust — the parser still bounds-checks, and since 2.5.2 it
  also REJECTS (returns 0 for) a grammar whose rules are
  incomplete or inconsistent, which before then loaded and
  crashed the scanner later.
- **`vyk` CLI** reads files of up to 1,048,574 bytes (`VYK_SRC_CAP`,
  1 MiB, less two) via `file_read_all`. A larger file is refused loudly — exit 3 with
  an error on stderr — since 2.3.4 (P1-1 of that audit; through
  2.3.3 it was silently truncated, and this paragraph said that
  was "accepted"). The streaming API bounds its live buffer
  separately through `VYK_STREAM_CAP` (16 MiB), which caps the
  longest in-progress span rather than total input.
- **Terminal output.** `vyk --theme=<name>` writes source bytes to
  a terminal. Since 2.5.2 every control byte a terminal would act
  on — C0 controls other than TAB / LF, a bare CR, DEL, and C1
  controls in either encoding — is written as a visible escape
  (`^[`, `^M`, `\x9b`); through 2.5.1 a file holding
  `ESC ] 0 ; … BEL` retitled the window and `ESC [ 2 J` cleared
  the screen, under every theme including `none`. Valid UTF-8 is
  unchanged. NDJSON output never contains source bytes.

## What's in scope

- Memory safety: out-of-bounds reads/writes in the scanner,
  `tokenbuf`, or grammar loader.
- Integer overflow in length / offset / token-count math.
- Coverage-invariant violations: input bytes that produce zero
  tokens, or token spans that overlap / leave gaps.
- Unbounded allocation traceable to attacker-controlled input
  (input size, token count, grammar shape).
- Terminal-escape injection through CLI error messages
  (sanitised in 1.0.1, FINDING-006; C1 controls added in 2.5.2)
  or through `--theme` source rendering (escaped since 2.5.2);
  regressions in scope.
- Super-linear time on adversarial input — e.g. compose openers
  with no closer were quadratic until 2.5.2 (1 MiB of `<style>`
  ran past 300 s), and in the STREAMING API a long token or block
  fed in small chunks was re-scanned per drain until 2.8.0
  (ADR 0028), the cases 2.8.0 missed until 2.9.1, and four more until
  2.9.12 (a string ending in a run of `\`, a long shebang line, a
  number of `_1` separators, colliding heredoc delimiters).
  `scripts/audit/stream-sweep.sh` times each of these. One case is
  known and not scheduled: heredoc delimiters crafted to collide in
  the heredoc line index's unkeyed hash make building it quadratic
  (`docs/development/state.md`, Known limits).
- Adversarial `.cyml` grammar files crashing or hanging the
  loader.
- Public-API misuse that produces undefined behaviour rather
  than an error return — e.g. `tokenize_stream_feed` with a NULL
  chunk or a negative length. (2.3.4 hardened several of these:
  `alloc` failures, an `n` large enough to wrap the length
  arithmetic, and the pull-adapter accessors called before the
  first `_next` or after `_free`.)

## What's out of scope (file as feature requests instead)

- Cosmetic tokenization gaps where coverage holds and no `error`
  tokens are emitted (char-literal splitting, INDENT/DEDENT in
  Python, etc.) — see `docs/development/state.md` "Known limits."
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
- [2026-05-09 — 1.11.x closeout audit](docs/audit/2026-05-09-1.11-closeout-audit.md)
  — the external-integrations wave: LSP bridge, grammar
  composition, theme export, embedded grammar blobs, content
  detection. 0 CRITICAL, 0 HIGH, 0 MEDIUM, 1 LOW — FINDING-007,
  `grammar_load` copying a blob without first enforcing
  `bn < GRAMMAR_FILE_CAP - 1`. Pure defense-in-depth with the
  largest grammar at 6.7 KB, clamped in-pass. Also the pass
  that put `cyrius fuzz` in CI.
- [2026-05-09 — 1.13.x closeout audit](docs/audit/2026-05-09-1.13-closeout-audit.md)
  — 1.12.0 through 1.13.2: fuzz harnesses, Helix/iTerm theme
  emitters, the bench suite, the CLI error-message split, the
  man page, and the `compose_fenced` rule + scanner step 0b.
  0 CRITICAL, 0 HIGH, 0 MEDIUM, 0 LOW — additive surface only,
  no new unbounded `alloc`, no new file-read site.
- [2026-05-09 — 2.0.x closeout audit](docs/audit/2026-05-09-2.0.x-closeout-audit.md)
  — the streaming tokenizer: push primitive, rolling-buffer
  drain, pull adapter, pending pair-rule fast path. 0 CRITICAL,
  0 HIGH, 0 MEDIUM, 2 LOW, both fixed in-pass — FINDING-008
  (`_stream_grow` infinite-loops when `cap == 0`) and
  FINDING-009 (`_stream_scan_close` vacuously matching a
  zero-length end marker, which would emit zero-length tokens
  and break the coverage invariant). Streaming also introduced
  `VYK_STREAM_CAP` (1 MB at 2.0.0, raised to 16 MB in 2.0.1),
  which bounds the longest in-progress span rather than the
  cumulative input.
- [2026-05-09 — 2.1.x closeout audit](docs/audit/2026-05-09-2.1.x-closeout-audit.md)
  — seven new grammars (PowerShell, Crystal, Julia, Vue,
  Svelte, Nix, Terraform) plus the streaming opts: the discard
  primitive, `tokenbuf_drop_front`, the trailing-complete
  tightening, and the random-split fuzz harness. 0 CRITICAL,
  0 HIGH, 0 MEDIUM, 0 new LOW. The new harness paid for itself
  on its first run: FINDING-010 (trailing-complete over-eager
  on same-byte pair markers) was fixed in 2.1.4 in-pass, and
  FINDING-011 (compose-rule START markers split across chunks
  losing the route) was filed as a known limitation, then
  resolved in 2.2.1 by `_stream_compose_prefix_hold`.
- [2026-08-20 — 2.3.x hardening audit](docs/audit/2026-08-20-2.3.x-hardening-audit.md)
  — 2.2.x and 2.3.x, which shipped without one. 4 P1, 6 P2, 4 P3,
  all fixed in 2.3.4: `vyk` silently truncated input over 1 MiB
  (FINDING-003), a one-byte out-of-bounds read, stream offsets
  wrapped past 4 GiB, `alloc()` returns went unchecked
  (FINDING-002). Streaming was found not chunk-invariant — partly
  fixed there, whole since 2.8.0.
- [2026-10-20 — 2.5.x closeout audit](docs/audit/2026-10-20-2.5.x-closeout-audit.md)
  — 5 P1, 12 P2, 20 P3, 4 gate holes; 2.5.2 fixed the P1s, the
  gate holes, 10 P2 and 12 P3. Among them: `vyk --theme` wrote a
  file's terminal control bytes raw, the streaming heap grew
  12–24× the input, and malformed grammars loaded and crashed the
  scanner later.
- [2026-10-20 — 2.6.x closeout audit](docs/audit/2026-10-20-2.6.x-closeout-audit.md)
  — 2.6.x's heredoc and `start_after` rules, CLI and detection.
  3 P1, 9 P2, 21 P3, 3 gate holes; 2.6.2 fixed the P1s, the gate
  holes, 7 P2 and 17 P3, among them a heredoc hold bound that was
  not enforced once its watch armed.
- [2026-10-21 — 2.9.x closeout audit](docs/audit/2026-10-21-2.9.x-closeout-audit.md)
  — 2.7.0 through 2.9.0. 2 P1, 8 P2, 10 P3, 11 gate holes; 2.9.1
  fixed all but one P3 and the rest of P2-4 (the heredoc line
  index's memory), which shipped in 2.9.3 and 2.9.4. Among them: two
  consumer grammars composing into each other overflowed the stack,
  and chunked streaming was still quadratic on some inputs.
- [2026-10-27 — 2.9.12 closeout audit](docs/audit/2026-10-27-2.9.12-closeout-audit.md)
  — 2.9.2 through 2.9.11, the end of the 2.9.x arc. 4 P1, 14 P2,
  12 P3, 13 gate holes; 2.9.12 fixed all but one P2 and three P3,
  which are documented as known limits. Among them: `grammar_load`
  crashed on an unquoted `match` value, a heredoc delimiter cut off
  by the buffer's end was hashed through a pointer into an earlier
  caller's freed buffer (SIGSEGV after an unmap), an unclosed markdown fence
  swallowed the rest of real documents without an error token,
  documents differed from one feed past the heredoc hold bound, and
  chunked streaming took 10–29 s on four inputs.

State at 2.10.0 (the code of 2.9.12): 0 CRITICAL, 0 HIGH open. Every numbered finding of
the 2026-04-23 baseline and the 1.x / 2.x passes is closed —
FINDING-002 to 005 (unchecked `alloc()` returns, silent truncation at
`VYK_SRC_CAP` and `GRAMMAR_FILE_CAP`, u32 `Token.start` /
`Token.len`) in 2.3.4: allocation failures are checked, oversized
input and grammars are refused, and a stream refuses input past
`VYK_OFFSET_CAP` (2³² − 1). What stays open is the 2.9.12 audit's four
documented items (P2-A7 and P3-A9, A11, D10 — token boundaries that
differ from a reference lexer; none is a memory or time defect) and
the heredoc-collision case above.

No audit was cut for 2.2.x or 2.3.0. 2.2.1 *was* the audit queue
being drained — FINDING-011's fix plus the 2.1.5
recommendations — and 2.2.2 / 2.2.3 / 2.3.0 are infrastructure:
toolchain pin moves, the vendored-`lib/` model, a vestigial
`cyrius.cyml` dependency removed, test-suite variable renames.
None of them touched the scanner, the public API, the token
layout, or the 45-grammar set; the next audit was 2.3.4's, above.
CLAUDE.md §Hardening step 6 is the only gate that mandates a
security review — the §Closeout pass checklist has never carried
one — so audits run as hardening passes, one at the close of each
arc of releases ([roadmap](docs/development/roadmap.md)).
