# 0029 — Compacted grammar blobs, a POSIX generator, a checked size budget

- **Status:** Accepted
- **Date:** 2026-10-21
- **Deciders:** 2.9.0 size-and-tooling work (proposed) / user (accepted
  via the pinned 2.9.0 roadmap entry)
- **Relates to:** [ADR 0014](0014-embedded-grammar-blobs.md) (amends its
  encoding and its "when to revisit: a bundle-size budget"),
  `scripts/embed-grammars.sh`, `scripts/check-size.sh`,
  `src/grammar.cyr` (`_gp_parse`), `tests/vyakarana.tcyr`,
  `vyakarana-design-spec.md` (the 300 KB target)

## Context

The design spec sets a 300 KB target for `vyk`; 1.13.0 made it a soft
cap. Nothing measured it, and by 2.8.0 the binary releases ship (the
`CYRIUS_DCE=1` build) was 408,680 bytes. The largest single item was
ADR 0014's blobs: every `grammars/*.cyml` file inlined verbatim, 211,991
bytes, of which 141,518 are full-line comments. With trailing comments,
blank lines and alignment blanks, 156,457 bytes are text the loader
only skips; 55,534 are what it reads.

The generator had two portability defects (2.6.x audit, roadmap 2.9.0):
its escaping used `gsub()`, whose backslash doubling is a no-op under
POSIX awk — run under `gawk --posix`, the 2.8.0 script leaves every
grammar `\` undoubled and the build fails on an unknown string escape —
and its control-byte check used `grep -P`, a GNU extension, so
elsewhere the check silently passed.

The roadmap named two replacements: cyrius's `[embed]` manifest section
(6.6.19) or a POSIX rewrite.

## Decision

1. **Blobs are compacted.** `scripts/embed-grammars.sh` drops comments,
   blank lines and every space, tab and CR outside a string. It follows
   the loader's own lexical rules (`src/grammar.cyr`): a string is
   `"…"` with `\` escaping the next byte, `#` outside a string runs to
   the end of the line, and a value is a string, a string array or a
   bool, so no two bare words ever need a blank between them. A string
   that runs past the end of its line is refused (no grammar has one;
   the loader would continue it onto the next line).
2. **Compaction is proven per grammar, in the tests.** A 2.9.0 test
   group parses each blob and its `grammars/<name>.cyml` with
   `_gp_parse` and compares the two grammar records field by field —
   scalars, strings, string lists, 256-byte class tables, and every
   rule record — from specs held to each record's `*_SIZE`. It is shown
   to fail: on one-field changes inside rules, and on a stale blob (a
   grammar edited without re-running the script, which ADR 0014 listed
   as "generator drift").
3. **The generator is POSIX sh + POSIX awk + `tr`.** Every byte is
   examined and escaped one at a time, with no `gsub()`; the control-byte
   check is `tr -d` with octal ranges; the locale is `C` (byte
   semantics, byte-order glob); output is written to a temporary file
   and renamed, so a refusal leaves the previous blobs intact. Output is
   identical under gawk, `gawk --posix` and `gawk --traditional`, and
   under bash, `bash --posix` and `zsh --emulate sh`.
4. **`[embed]` is not used.** It copies a file's exact bytes, so it
   would embed the comments again — or need a generator to write
   stripped copies for it, which is more machinery than this. It also
   writes every non-printable byte as `\xHH` (each newline four bytes
   in the bundle instead of two) and needs 46 manifest entries plus a
   `[lib] embed` list kept in step with `grammars/`.
5. **The encoding stays text.** Compacted, the blobs hold 55,534 bytes;
   DEFLATE would make them 9,717 — about 46 KB more — at the cost of an
   inflater in every binary, a decode in `bootstrap_grammars`, and a
   new stdlib leaf in the bundle's `.deps` sidecar for every consumer.
   Not worth it under the budget below.
6. **The budget is checked.** `scripts/check-size.sh` fails when the
   DCE binary is over 307,200 bytes (300 KiB). CI runs it (building its
   own DCE binary) and `release.yml` runs it on the binary it packages.
   It fails on 2.8.0's binary (101,480 over) and passes on 2.9.0's.

## Consequences

### Positive

- 2.8.0 → 2.9.0: `vyk` 498,792 → 342,336 bytes, the DCE build 408,680
  → 252,224 (55 KB under budget), `dist/vyakarana.cyr` 503,205 →
  342,875. Every consumer's binary sheds the same ~156 KB, since each
  carries every blob.
- Output is byte-identical: 4,500 real files and the 49 corpora, stdout,
  stderr and exit code, against the 2.8.0 blobs.
- The grammar-load fuzz, which drops random blob lines, now drops only
  lines the loader reads.

### Negative

- A blob is no longer a readable copy of its grammar; `grammars/` is.
  (Loader errors carry no line numbers, so nothing pointed into a blob.)
- One more gate. A change that needs more than 55 KB of headroom has to
  move the budget in this ADR's successor, not quietly.

### When to revisit

- The DCE build approaches the budget: DEFLATE-encoded blobs (point 5)
  are the next lever, about 46 KB.
- A grammar needs a string that spans lines, or a value that is not a
  string, array or bool: the compactor's lexical rules (and the loader's)
  change together, and the record comparison will say whether they did.
