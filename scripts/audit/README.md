# scripts/audit — the empirical sweeps

The closeout audits (2.3.4, 2.5.x, 2.6.x) each rebuilt their sweeps by
hand in a scratch directory and threw them away. These are those sweeps,
kept: run them at every closeout (CLAUDE.md §Hardening step) and after
any change to the scanner, the drain or a grammar. None is a CI gate —
they take minutes and want real files — but CI builds the harness and
syntax-checks every script so they do not rot between audits.

Run each from anywhere; each `cd`s to the repo root and builds what it
needs (the harness is always rebuilt, so a stale one cannot report
another tree's bugs). FILE arguments may be files, directories
(searched, skipping `.git/` and `node_modules/`) or `-` for a list of
paths on stdin; relative paths are taken from where you ran the
script. A path that does not exist, or an empty list, exits 2 — through
2.9.0 a mistyped path reported a clean sweep of zero files. Each exits
1 when it finds a failure. All of them run under dash, mawk and
busybox as well as bash and gawk.

| Script | Checks | Input | Clean at 2.9.12 |
|---|---|---|---|
| `coverage-sweep.sh` | `vyk FILE` over real files: every NDJSON line a token of a known kind, tokens tiling the file (the coverage invariant), exit 1 if and only if an error token, no crash, no timeout; files over the CLI's 1 MiB cap are counted, not failed (`stream-sweep.sh` takes them through the library) | real files | 13,619 files (the 2.9.12 audit's lists): 0 fails, 28 with error tokens, each invalid input or a documented limit |
| `poison-ab.sh` | two `CYRIUS_POISON` builds (fill 0xA5 / 0x5A) print the same bytes and exit for every file — no output depends on unwritten memory; exit 86 is a redzone overwrite | real files | 5,630 files: 0 diffs, 0 overwrites, 0 crashes |
| `stream-sweep.sh` | chunked feeds equal one feed (ADR 0017 / 0028). No FILE: the every-offset split over every corpus, the heredoc shapes under every offset and every pair of offsets, and twenty-one generated stress inputs under a time limit. With FILEs: `chunks`, `rand` and `cutfirst` per file | corpora + `shapes/`, or real files | fixed set 171 runs, 0 fails; 2,385 real files 7,155 runs, 0 fails |
| `ab-sweep.sh` | single-feed output of two `vyk` binaries over the same files: each file whose output or exit differs, with both error-token counts and both largest tokens (a regression with no error token shows in the largest token — 2.9.12 audit, G-A1). Informational: exits 1 only when a binary crashes or times out | real files | 2.9.11 → 2.9.12 over 13,619 files: 68 differ, each traced in the 2.9.12 audit |
| `edit-sweep.sh` | incremental retokenization (ADR 0033): at every offset of a whole file, an edit — a marker inserted, bytes deleted or replaced — through a `tokenize_doc` document, held to one feed of the edited text, and its undo to the original's. No FILE: every corpus at every offset, at the default checkpoint spacing and at 48 bytes. With FILEs: every 97th offset (`-s`) | corpora, or real files | corpora: 104 runs (529,156 edits), 0 fails; 5,454 real files at `-s 151`, 0 fails |
| `mutate-fuzz.sh` | mutants of real code (bytes overwritten; quote, comment, heredoc and compose markers inserted; ranges deleted or duplicated) tile their bytes and match one feed under random chunking | vidya's `content/` by default | 976 files, 97,600 mutants (`-i 100`), 0 fails (vidya `9f13e35`) |

`scripts/bench-paired.sh` (one level up) is the latency protocol —
`performance.md` explains it.

## Shown to fail

A sweep that cannot fail proves nothing (the 2.3.4, 2.5.2 and 2.6.x
audits each found a gate that passed on inputs too narrow to fail).
Built against the 2.7.1 tree, which had the chunking bugs 2.8.0 fixed:

- `stream-sweep.sh` (no FILE) fails 16 of the 159 runs it had at
  2.9.0: all six
  compose corpora (html, markdown, vue, svelte, both cyml) under
  `every`, and ten of the twelve stress inputs — nine on the 10 s
  limit, the cyml region on its tokens. Only the 512 KB comment (3.3 s
  on 2.7.1) and the 20,000 heredoc openers pass;
- `mutate-fuzz.sh` fails cyml mutants 99 / 100 and 100 / 100, markdown
  14 / 100, html 5 / 100.

Against 2.9.0 (2.9.1 audit): the five stress inputs added then — a
rewritten heredoc delimiter, a fence of mid-line "```", a heredoc line
held open by `\"`, a blank run in shell, a Zig `\\` string line — each
time out at 10 s; 2.9.1 takes well under one.

Against 2.9.11 (2.9.12 audit): the four stress inputs added then — a
string ending in 1 MB of `\`, a 1 MB shebang line, a number of `_1`
separators, 40,000 colliding heredoc delimiters — took 10–29 s each, over
the 10 s limit; 2.9.12 takes 0.01–0.65 s. `edit-sweep.sh` and
`fuzz/retokenize.fcyr` fail on six of nine broken resyncs (ADR 0033),
and the fuzz's short-text pass on the two look-behind mutants the corpus
passes missed.

`coverage-sweep.sh` was checked against stub binaries (a gap, an
unknown kind, exit 1 without an error token, a crash, a hang): each is
a FAIL line. Since 2.9.12 every sweep except `ab-sweep.sh` exits 2 on a
list where no file has a grammar (`ab-sweep.sh` exits 2 only on an empty
list), and `poison-ab.sh` fails a crash in either leg.

## Inputs

- **Real files.** The 2.9.12 numbers use a fresh per-grammar sample
  (up to 250 files per grammar from `~/Repos`, `/usr`, `/etc`, by each
  grammar's declared routes: 5,552 files), 2.9.4's 7,527-file sample, the
  5,000 compose-grammar files of 2.9.10 and 2.9.9's 78 downloaded MDX and
  Lean files — 13,619 unique. Three sweeps take a subset: poison A/B
  the new sample plus the MDX and Lean files (5,630); streaming 2,385
  of the new sample's files (markdown, html, vue, svelte, cyml, mdx,
  shell, python, rust, c, php, asm, lean, ruby, c#, swift, lua, cpp,
  zig); edits the 5,454 of the 5,630 that are 64 KB or less, at
  `-s 151`. Any list works; keep the one you used beside the audit
  report so the next run can repeat it.
- **vidya** (`../vidya`, or `VIDYA=…`): `mutate-fuzz.sh` prints the
  commit it ran against — that is the snapshot.
- **`shapes/`**: 45 heredoc shapes from the 2.6.x audit (quoting,
  `<<-` and tabs, unterminated bodies, terminators in strings, many
  heredocs per line). Four more with CR / CRLF bytes are generated by
  `stream-sweep.sh`, so no committed file depends on git's line-ending
  handling.

## The harness

`harness.cyr` (built as `build/vyk-audit`) runs one file through one
mode — `every`, `pairs`, `chunks`, `rand`, `cutfirst`, `mutate`, `edits` — and
is the tool for minimising a failure: rerun the failing file or the
mutant `mutate-fuzz.sh` wrote under `build/audit/mutants/` with `every`
to find the offset, then cut it down. Its header documents every mode.
