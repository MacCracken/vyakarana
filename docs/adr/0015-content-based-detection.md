# 0015 — Content-based language detection

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** RM (1.11.2 cut)
- **Relates to:** ADR 0001 (extension-based dispatch as the
  starting contract), `src/detect.cyr`, `src/main.cyr` `main()`,
  `tests/vyakarana.tcyr` "1.11.2 content-based language detection",
  the `.s` / `.S` ambiguity carried since 1.2.3

## Context

Through 1.11.1 the only public dispatch was `detect_language(path)`
— pure suffix matching. That covered the well-named majority but
left three classes of input wrong:

1. **Asm flavour split.** `.s` and `.S` extensions are shared
   between GAS-style x86_64 (Intel or AT&T syntax) and ARM
   AArch64. The grammar surface is similar enough that picking
   the wrong flavour produces a tokenization full of `TK_ERROR`
   spans (the wrong line-comment marker, the wrong directive
   prefix). Through 1.11.1 the only mitigation was
   `--language=asm_aarch64` on the command line — discoverable
   only by reading the asm grammar headers.
2. **Extensionless files.** `bin/install`, `scripts/deploy`,
   `bootstrap` — Unix files with shebang lines but no extension.
   The path dispatch returned 0; vyk emitted `EXIT_NO_GRAMMAR`.
3. **Format-by-magic files.** `<?xml`-led files saved without
   an extension; HTML pages saved as plain `index`. Same
   no-grammar result.

vidya hadn't asked for this yet, but the LSP bridge (1.11.0) and
theme export (1.11.1) put vyakarana on the path of being adopted
as a renderer by tools that *will* throw extensionless or
unannotated input at it. Better to fix this before consumers ship
a workaround.

## Decision

**Add a byte-pattern content sniff and an extension-vs-content
combiner alongside the path dispatch. Three entry points, all
public.**

- `detect_language(path)` — unchanged shape; suffix match,
  returns name or 0. Moved from `src/main.cyr` to
  `src/detect.cyr`.
- `detect_language_from_content(src, src_len)` — new. Strips a
  UTF-8 BOM, then runs:
  1. Shebang sniff. `#!` on the first line; the interp name
     is the last slash-separated component (with `env` skipped
     so `#!/usr/bin/env python3` resolves to `python3`).
     Matched as a prefix so version suffixes (`python3`,
     `bash5`) work. Today: `bash` / `zsh` / `dash` / `sh` →
     `shell`; `python*` → `python`; `node*` → `javascript`;
     `ruby*` → `ruby`; `lua*` → `lua`; `php*` → `php`. Other
     interps (perl, awk, etc.) return 0.
  2. Signature peek. Fixed prefixes after the BOM:
     `<?xml` → `xml`, `<!DOCTYPE html` (any case) and
     `<html` → `html`, any other `<!DOCTYPE …` → `xml`.
- `detect_language_combined(path, src, src_len)` — new. Path
  dispatch first; if the result is `asm_x86_64` (the default
  for `.s` / `.S`) the asm flavour is rescored from content
  signals. If path returns 0, falls through to the content
  sniff. This is what `vyk` calls.

Asm flavour scoring (`_detect_asm_flavor`): scan first 4KB,
count weighted hits.

- ARM signals (any → +1, except `.arch armv*` → +5,
  `b.eq`/`b.ne` → +3, `ldp`/`stp` → +2): `.arch armv8`,
  `.arch armv7`, `b.eq`, `b.ne`, `ldp `, `stp `, ` x0,`,
  ` x1,`, ` w0,`, ` w1,`, `xzr`, `wzr`.
- x86_64 signals (`.intel_syntax`/`.att_syntax` → +5, others
  → +1): `.intel_syntax`, `.att_syntax`, ` rax`, ` rdi`,
  ` rsi`, ` rsp`, ` rbp`, `syscall`, `xmm0`.

Higher score wins. Tie / no-signal defaults to `asm_x86_64`
(preserves the 1.0–1.11.1 behaviour for unannotated asm).

The `vyk` CLI now reads the file once, then calls
`detect_language_combined`. `tokenize_file` was renamed
`tokenize_buf` to take a pre-read buffer + length.

`src/detect.cyr` joins `[lib] modules` so `dist/vyakarana.cyr`
exposes the byte API to downstream consumers (along with the
existing `tokenize_source` / `lsp_kind_*` surfaces).

## Consequences

### Positive

- **Asm corpus auto-detects.** `vyk tests/corpus/asm_aarch64.s`
  no longer produces `TK_ERROR` for every `//` comment. The
  smoke script verifies both flavours auto-route correctly with
  zero error tokens.
- **Extensionless scripts work.** A file with
  `#!/usr/bin/env python3` and no extension tokenizes as
  Python. Probe in `tests/vyakarana.tcyr` covers env / direct
  / unknown shebangs across six interp families.
- **Magic-byte formats work.** `<?xml` / `<!DOCTYPE html` /
  `<html` resolve when extension isn't there.
- **Public byte API.** Consumers that already have bytes (vidya
  rendering an inline snippet, an LSP plugin handling
  `didOpen`) can call `detect_language_from_content` directly
  without inventing a path.
- **Fully back-compatible.** Path dispatch unchanged; combined
  entry only refines `asm_x86_64` and only when path returned 0
  in the first place.

### Negative

- **A second public surface to keep stable.** `detect_language`
  was already documented as the shape consumers depend on. Now
  there's `detect_language_from_content` and
  `_combined` too — three entries, three bodies of stability
  promise. Mitigated by keeping each one narrow (no
  cross-cutting state, pure functions, no global registry).
- **The asm scoring is heuristic.** A file with only `mov rax,
  1` — no syntax pragma, no other registers — gets a score of
  +1 for x86 vs 0 for ARM, picks x86_64. Defensible. But a
  file with a stray `b.eq` in an ARM-style label (rare) would
  tip the vote. Documented the score table explicitly so
  future contributors can adjust without reverse-engineering.
- **Reads happen earlier.** `vyk` used to lazy-read the file
  inside `tokenize_file`; now `main` reads up front so detect
  has bytes to work with. For a no-grammar path that wouldn't
  have tokenized anyway, that's a wasted 1MB read. Acceptable
  — `EXIT_NO_GRAMMAR` was already a hot-path-cold result and
  vyk's `VYK_SRC_CAP` allocation stayed the same.
- **Shebang interp list is closed.** Every new interp (R, Tcl,
  Julia, Crystal, …) needs a new conditional. Each is a
  one-line change and the worst failure mode is fall-through
  to 0; not a refactor pressure point.

### When to revisit

- A consumer asks for **content-based detection on path-known
  extensions** (e.g. a `.txt` that's secretly Markdown). Today
  the combined entry trusts the extension when it produces a
  non-asm result. Adding an `--detect=content` mode that always
  runs the content sniff first is a small additive change.
- A grammar arrives whose canonical files have **neither
  extension nor shebang nor magic bytes** (e.g. a domain-
  specific config without a header). Then we'd need a real
  fingerprinting pass — keyword-density vote, n-gram model,
  or a corpus-trained classifier. Out of scope for 1.x; that's
  a 2.x conversation.
- The asm flavour vote misroutes a real corpus. The fix is
  data-driven: extend the signal lists, possibly add a strong
  arch-directive override (e.g. seeing `.arch armv9-a`
  short-circuits the score). Don't rewrite the structure.
- We add a streaming API (2.0.0). Detection then has to work
  on a smaller window than the full file — the current 4KB cap
  on the asm scan is already close, but shebang and signature
  paths need explicit "first N bytes" contracts.
