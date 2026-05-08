# 0014 — Embedded grammar blobs in the dist bundle

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** RM (proposed during the 1.11.1 cut after surfacing
  the integration-path bug in `lib/vyakarana.cyr`)
- **Relates to:** ADR 0001 (single dist bundle as the consumer
  contract), `dist/vyakarana.cyr`, `src/grammar.cyr` `grammar_load`,
  `src/grammar_blobs.cyr` (generated), `scripts/embed-grammars.sh`,
  `docs/guides/consumer-integration.md`

## Context

vyakarana's documented integration path is:

```toml
[deps.vyakarana]
git     = "https://github.com/MacCracken/vyakarana.git"
tag     = "1.11.x"
modules = ["dist/vyakarana.cyr"]
```

`cyrius deps` resolves that to a single file at `lib/vyakarana.cyr`
in the consumer's tree. Nothing else is vendored — `grammars/`,
`tests/`, and the rest of the repo stay upstream.

The bundle's `bootstrap_grammars()` calls `grammar_load(path)` 38
times with paths like `"grammars/shell.cyml"`. Through 1.11.0 that
function did one thing: open the path and read it. Inside the
vyakarana repo this works because `grammars/*.cyml` is reachable.
Inside a downstream consumer (cyim, owl, vidya, anything else
following the documented path), `file_read_all` returns 0 because
the directory doesn't exist. `bootstrap_grammars` silently
registers nothing, and the first `tokenize_source` call returns
an empty tokenbuf with no diagnostic.

The consumer guide claims the bundle "bundles the public API and
all 38 grammars." It didn't.

## Decision

**Inline every `grammars/*.cyml` as a Cyrius string literal in a
generated module that lives in the dist bundle.**

- `scripts/embed-grammars.sh` reads every `grammars/*.cyml`,
  escapes content (`\\`, `\"`, `\n`, `\t`, `\r`), and writes
  `src/grammar_blobs.cyr` containing one
  `fn _grammar_blob_<name>()` per grammar plus a
  `_grammar_blob_data(path)` lookup that maps the standard
  `"grammars/<name>.cyml"` path to its blob.
- `src/grammar_blobs.cyr` is **gitignored** — produced fresh on
  every gate run (the embed step is now part of the canonical gate
  sequence in CLAUDE.md). It's also listed in `[lib] modules` so
  `cyrius distlib` concatenates it into `dist/vyakarana.cyr`.
- `grammar_load(path)` consults `_grammar_blob_data(path)` first.
  When the blob is present, the bytes are copied into a writable
  buffer (the parser writes NUL terminators in place — can't hand
  it the read-only literal directly) and parsed exactly like a
  file read.
- The file-load path stays as a fallback. `vyk grammars/foo.cyml`
  on the command line — used by grammar authors to test edits
  without regenerating the blob file — still reads from disk.

Scope: **dist bundle correctness only.** This isn't a new feature;
it's the implementation that makes the existing consumer contract
true.

## Consequences

### Positive

- The bundle is genuinely self-contained. A consumer that does
  `cyrius deps` and nothing else gets a working tokenizer.
  Verified by a new smoke probe (`scripts/smoke.sh`) that runs
  `vyk` from a temp dir with no `grammars/` reachable: 38
  languages list, shell corpus tokenizes to 1560 NDJSON lines.
- The grammar-author dev loop is unchanged. Edit
  `grammars/python.cyml`, run `vyk python.cyml input.py` — the
  file-load fallback handles it, no regeneration needed.
- The blob format is opaque to the bundle consumer. A future
  optimization (pre-compiled grammar tables, gzipped blobs,
  alternate encodings) is a generator change only.

### Negative

- **Bundle size: 82KB → 253KB** (+208%). The 38 grammars are
  ~150KB of `.cyml` text; per-blob escape-encoded length is
  marginally larger. Acceptable for a "single self-contained
  file" target, but the bundle is no longer trivially diffable.
- **A new build prerequisite.** `cyrius build` against
  `src/main.cyr` now needs `src/grammar_blobs.cyr` on disk
  because `src/grammar.cyr` includes it. A fresh checkout will
  fail to build until `scripts/embed-grammars.sh` runs once.
  Mitigated by listing the embed step explicitly in CLAUDE.md's
  gate sequence.
- **Two paths in `grammar_load` to maintain.** Blob path and
  file path duplicate the buffer-copy + parse shape. The file
  path is justifiable (grammar-author workflow) but is now
  exercised only by hand, not by gates — risk of silent
  regression.
- **Generator drift.** The script encodes assumptions about
  Cyrius string-literal escapes (`\\ \" \n \t \r`). If a future
  grammar uses some control byte the script doesn't escape, the
  bundle will compile but parse incorrectly. The generator
  bails loudly on any control byte in the `0x00..0x1f` range
  outside `\t\n\r`, but this is heuristic.

### When to revisit

- A bundle-size budget gets formalised (e.g., a 200KB cap for
  the dist bundle). Then we'd need to compress blobs or move
  to a binary-encoded grammar table.
- A grammar requires a literal NUL byte or some other control
  byte the encoder doesn't handle. The script aborts in that
  case; the fix is either to escape that byte explicitly or
  switch encoding (hex-decoded blob, base64).
- The file-load fallback path is observed to be unused for a
  full milestone window. Then we can simplify `grammar_load`
  to blob-only and drop the `GRAMMAR_FILE_CAP` allocation in
  the hot path.
- A future grammar-format change moves us off `.cyml` entirely
  (the grammar-format-stability section of ADR 0005 owns this
  question). At that point the embedded format follows the new
  source format.
