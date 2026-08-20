# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

_No unreleased changes._

## [2.4.0] — 2026-08-20

**Streaming correctness.** Minor rather than patch because token
boundaries change: a consumer feeding in chunks now gets the same
tokens a whole-buffer consumer gets. That was supposed to be true
already — `fuzz/streaming.fcyr` has asserted it since 2.1.4 — but
the 2.3.4 audit found it violated on **13 of 20 real corpus files**.
The harness passed because its inputs were short synthetic strings.

**15 of 20 corpora are now chunk-invariant at every chunk size
tested** (1, 2, 3, 5, 7, 64, 512, 4096), up from 7. Newly clean:
**python, rust, go, css, toml, sql, xml, ruby**. The five that
remain — markdown, html, vue, svelte, cyml — are the compose
grammars, deliberately scoped out below.

909/909 tests, smoke OK, lint+fmt exit 0, fuzz **5/5**.

### Fixed — five independent root causes

Each was found by bisecting a real corpus file down to the exact
token, not by reading code:

- **The LF fallback committed block comments early.** A trailing
  `TK_COMMENT` / `TK_STRING` / `TK_PREPROCESSOR` ending in a newline
  was treated as complete — meant for *line* comments, where LF is
  the terminator, but it fired for any pair token containing a
  newline at the boundary. `tests/corpus/concept.css` at chunk=3
  opens with `/*\n`: the pair test correctly declined (3 bytes <
  `slen+elen`), then this committed a 3-byte "comment" and the
  remaining 341 bytes of the header comment were re-tokenized as
  CSS — 838 tokens instead of 724. Now only taken when the token
  starts with a line rule's marker. Fixes **css, sql**.

- **Longest-match operator tables merged across the boundary.** The
  commit rule was "token ends strictly before `buf_len`, so it is
  settled" — false for tables matched longest-first. With the buffer
  holding `|--`, markdown scans `|`, `-`, `-` (because `--` is not
  an operator but `---` is); both `-` tokens end before the tail and
  were committed, so a third `-` became a fourth token. One 3-byte
  `---` came back as three 1-byte operators. Tokens within
  `_stream_max_marker` of the tail are now held. Fixes **rust, go**.

- **Rule START markers needed the same window.** A pair opener one
  byte short scans as ordinary operators: `tests/corpus/concept.xml`
  at chunk=3 held `<!-` while `<!--` is 4 bytes, so the 287-byte
  `<!-- … -->` comment became `<`, `!`, `-`, … and was
  unrecoverable — 451 tokens became 689. `_stream_max_marker` now
  spans operator and punctuation tables *plus* pair start/end, line
  start, and all three compose start markers.

- **A short pair rule vouched for a long rule's token.**
  `_stream_is_trailing_complete` checked every same-kind rule and
  returned complete on the first match. Python declares its
  triple-quote rule ahead of its single-quote rule; a docstring
  arriving as its bare 3-byte opener failed the triple-quote test
  (`3 >= 6` false) and then *passed* the single-quote test —
  `3 >= 1+1`, and the opener's last byte is that rule's close
  marker. Now the rule that actually **opened** the token decides,
  and `_stream_pair_provisional` additionally suppresses a verdict
  while a longer same-kind opener could still claim the bytes.

- **Pending was set on an already-closed token.** The real cause of
  the python docstring split, found by tracing rather than reading:
  `_stream_find_pair_rule` only considers rules whose start marker
  *fits inside* the partial token, so a lone trailing quote matched
  python's 1-byte rule even when the true opener was the
  triple-quote. The next drain took the pending fast path and closed
  it one byte later. The same path bit ruby: `=begin` makes its
  longest marker 6 bytes, so a **complete** `'+'` sitting within 6
  bytes of the tail was held from the commit list, the pending logic
  read it as a partial *open*, and `scan_resume` jumped past its own
  closing quote — the string ran on 45 bytes to the next `'`,
  swallowing `then @pos += 1; return Token.new(PLUS,   `. Fixes
  **python, ruby**, and **xml** via the marker window.

### Fixed — the stream cap is a live-window bound again

`VYK_STREAM_CAP` (16 MiB) documents a bound on the *live unconsumed
window*, with total input free to exceed it. An unresolved compose
opener broke that: with nothing committable the rolling buffer never
compacted, so the window grew to the whole stream and feed
eventually returned `VYK_ERR_OVERFLOW` **permanently**.

Holding the body is semantically required — the scanner refuses to
half-consume a compose rule whose end marker has not arrived — so
the hold is now *bounded* by `VYK_COMPOSE_HOLD_MAX` (8 MiB) instead
of removed. Past that, compose routing for that opener is abandoned
and the bytes tokenize with the outer grammar; coverage and the
zero-error bar still hold. Measured, same bytes, the only difference
being an unterminated `<style>` fed first:

| case | before | after |
|------|--------|-------|
| no opener | 26 MB accepted, buffer compacts to 1 | unchanged |
| unterminated `<style>` | grows to 16 MiB, then `VYK_ERR_OVERFLOW` forever | **26 MB accepted, buffer compacts to 1** |

### Added

- **`fuzz/chunk_invariance.fcyr`** — runs `tests/corpus/` through
  eight chunk sizes and asserts per-token `(kind, start, len)`
  equality against a single-shot feed, for the 15 grammars that hold
  it. Verified to have teeth: against the 2.3.5 tokenizer it fails
  loudly on python, rust and the rest. `cyrius fuzz` auto-discovers
  it, so CI needed no new step.

  The five known-divergent compose grammars are listed **explicitly**
  in that file rather than silently omitted, so the debt is recorded
  where someone will see it.

- **[ADR 0021](docs/adr/0021-token-span-width-ceiling.md)** — the
  decision the 2.3.4 audit asked for: `Token.start` / `Token.len`
  stay u32, and 4 GiB-per-stream becomes a documented, enforced
  contract rather than an accident. Widening to a 24-byte record was
  rejected (doubles per-token memory for every consumer to lift a
  limit almost none reach); so was stealing the record's 3 padding
  bytes for 40-bit fields (free in memory, but it makes ADR 0002's
  *published* layout disagree with the accessors past 4 GiB —
  trading a loud failure for a quiet one, which is exactly how this
  finding stayed invisible for four minor lines).

### Notes

- **The marker window is scoped to grammars with no compose rules,
  and that is why markdown / html / vue / svelte / cyml still
  diverge.** Holding a token back is safe on its own, but the
  compose machinery reads the commit list as state: the 2.2.1
  `skip_prefix_hold` guard asks "was the last **committed** token a
  compose close marker?" to stop prefix-hold mistaking a
  just-emitted fence close for the prefix of a fresh opener. Hold it
  back and the guard misses, prefix-hold drops the close token, and
  `fuzz/streaming.fcyr`'s markdown/fence-rust case loses a token.
  Three attempts to reconcile the two — exempting compose markers
  from the window, keying the guard to a pre-window commit
  boundary — each broke something else, so per CLAUDE.md
  §Refactoring policy it is scoped rather than forced. Reconciling
  them properly is the top item in `docs/development/state.md`
  §Next up.

- **No public-API signature changed.** `_stream_is_trailing_complete`
  gained a `buf_len` parameter but is internal (underscore-prefixed,
  not in `src/tokenize.cyr`'s public list).

## [2.3.5] — 2026-08-20

**The `openqasm` grammar, plus the documentation repairs 2.3.4's
audit turned up.** 46 bundled grammars (was 45), 909/909 tests (was
898). No token kind, no `Token` layout change, no public-API
signature change, no scanner change.

### Added

- **`grammars/openqasm.cyml` — OpenQASM 2.0 + 3.x.** This was the
  one sample in `vidya/content/lexing_and_parsing/` that vyakarana
  could not tokenize: `vyk openqasm.qasm` exited 4, "no grammar
  matched", while the other 11 round-tripped clean. vidya renders
  those samples *through* vyakarana, so it was a live consumer gap —
  surfaced by the 2.3.4 audit and closed here.

  The corpus is a **sync, not a stand-in**: vidya ships the file, so
  `tests/corpus/openqasm.qasm` follows
  [ADR 0001](docs/adr/0001-corpus-sync-policy.md) rather than
  [ADR 0006](docs/adr/0006-standin-corpus-policy.md). It tokenizes
  with **zero error tokens** and the coverage invariant exact
  (775/775 bytes).

  Shape notes:
  - The keyword set spans **both language versions** — 2.0's
    `qreg`/`creg`/`gate`/`opaque`/`U`/`CX` and 3.x's typed
    declarations (`qubit`, `bit`, `angle`, `complex`, `duration`),
    classical control flow, subroutine heads (`def`, `defcal`,
    `extern`, `cal`) and gate modifiers (`ctrl`, `negctrl`, `inv`,
    `pow`). Costs nothing at the token level and stops a 3.x file
    coming back as a wall of idents. Verified: a 3.x sample
    tokenizes with zero errors.
  - **Standard-library gate names stay `ident`, not `keyword`.**
    `h`, `cx`, `rz`, `ccx` come from `qelib1.inc` and are
    redefinable via `gate` — they are not reserved words. Same call
    as [ADR 0004](docs/adr/0004-shell-builtins-as-ident.md) for
    shell built-ins. `pi` *is* a keyword: built-in and not
    redefinable.
  - `->` is ordered ahead of `-` so `measure q -> c;` yields one
    2-byte operator.

  Registered in `bootstrap_grammars`, `_detect_5plus` (`.qasm`),
  the smoke suite's language list and corpus round-trip loop, and
  `fuzz/grammar_load.fcyr`'s blob-count assertion (45 → 46). Eleven
  new assertions in `tests/vyakarana.tcyr`.

### Fixed — documentation drift from the 2.3.4 audit

The audit found more doc drift than 2.3.4 had room for. Cleared here.
Historical references (CHANGELOG entries, ADR 0020's account of the
2.3.2 sweep) were deliberately **left alone** — only present-tense
claims about current state were touched.

- **`src/tokenize.cyr`'s public-symbol list was wrong in two ways**,
  which matters more than usual because 2.3.4 pointed CLAUDE.md's
  frozen-API rule at it. It listed `tokenize_source_handcoded` under
  "Removed in 2.0.0" — that function is *live*, defined in the same
  file, called by `src/main.cyr`, and shipped in the bundle; only
  `tokenize_source` was removed. And it omitted the entire pull
  adapter (`tokenize_stream_next` / `_kind` / `_start` / `_len` /
  `_discard_consumed`) while a comment above still said the pull
  adapter "is queued for 2.0.2" — it shipped *in* 2.0.2.

- **Grammar counts.** `45` → `46` in README, `docs/architecture/overview.md`,
  `docs/development/{performance,distribution,roadmap,state}.md` and
  `docs/guides/consumer-integration.md`. Architecture note 003 said
  the pipeline order "holds across all **23** bundled grammars" —
  off by 23. `tests/corpus/README.md` claimed "45 corpus files (one
  per bundled grammar)"; there are **47 across 46 grammars**, because
  `cyml` carries two.

- **Architecture note 002's normative pipeline table** listed only
  `match = "compose"` at step 0, missing `compose_fenced`
  ([ADR 0016](docs/adr/0016-compose-fenced-rule.md), markdown
  fences) and `compose_region`
  ([ADR 0019](docs/adr/0019-compose-region-rule.md), CYML bodies).
  Now 0a/0b/0c in the order the scanner actually tries them.

- **`overview.md`'s Decision index stopped at ADR 0009.** ADRs
  0010–0020 exist; all eleven added.

- **`agnoshi` was still listed as a downstream consumer** in
  `overview.md` (prose and diagram) and
  `004-theme-palette-contract.md`. `state.md` recorded it as "not a
  consumer and never was" back in 2.2.x; the architecture docs never
  got the memo.

- **`overview.md`'s bundled-grammar table** still said AT&T syntax
  was "deferred" for `asm_x86_64` (ADR 0020 landed it in 2.3.2) and
  told `asm_aarch64` users to pass `--language` explicitly
  (`_detect_asm_flavor` has routed it automatically since 1.11.2).

- **`SECURITY.md`'s trust boundary** described `tokenize_source`'s
  arguments — a removed function. Now names
  `tokenize_stream_feed` / `tokenize_with_grammar`, and the
  API-misuse bullet records what 2.3.4 hardened. The same stale name
  appeared in a CI comment.

- **`state.md`'s "waiting on a future ADR" list** asked for "a
  `char_literal = true` default with 2-3 char lookahead" — that is
  ADR 0010, shipped in **1.2.1**, and set in seven grammars today.
  Removed, with a note. Python INDENT/DEDENT was filed in the same
  list while its own bullet said it was unnecessary; moved to an
  explicit "out of scope, not deferred" heading. **M4** was left
  unmarked while M5 and M6 beside it read "Landed" — M4 landed as
  `004-theme-palette-contract.md` plus `--theme=` / `--export-theme=`.

- **Grammar headers filing shipped work under "Known gaps"**:
  `lua.cyml` listed integer division `//` and the 5.3+ bitwise
  operators as gaps and then said both "IS in operators below";
  `elixir.cyml` listed heredocs as a gap ending in "Added below".
  Both now sit under explicit not-a-gap headings. `graphql.cyml`'s
  float bullet was *kept* — it is a real gap — but reworded to say
  what it actually is (the scanner-wide float limitation, not a
  graphql decision).

- **`html.cyml` proposed "a regex-y attribute tolerance"** for
  `<script type="module">`. The design spec rules regex out of
  grammar files deliberately ("performance cliffs and grammar
  authors debugging regex engines"), so that pointed a future
  maintainer at a decision already made. Reworded toward the shape
  that fits — a prefix-plus-scan-to-`>` compose start.

- **README's Install block led with `pkg install vyakarana`**, a
  command that does not exist. From-source now leads; the package
  manager is a commented-out "NOT yet available" line.

### Notes

- **Floats are the one visible rough edge in the new grammar.**
  `OPENQASM 2.0;` — the header every file opens with — tokenizes as
  `number(2)` + `punctuation(.)` + `number(0)`. That is not an
  openqasm decision: the scanner has no float support at all
  (`src/grammar.cyr` understands `number_decimal`, `number_0x`,
  `number_0b`, `number_0o` and nothing else), so css, scss,
  protobuf, java and graphql carry the identical gap. Coverage and
  the zero-error bar hold. Removing `.` from punctuation would make
  it *worse* — the `.` would become `TK_ERROR`. A `number_float`
  default touches all 46 grammars and wants its own ADR; it is now
  tracked in `state.md`'s cosmetic-only list rather than buried in
  one grammar header.

- **The 2.3.4 audit's three deferred code items are unchanged and
  still open**: streaming chunk-invariance (9 of 14 corpora), the
  unbounded compose hold that turns `VYK_STREAM_CAP` into a
  total-input ceiling, and the `Token.start`/`len` u32 width
  decision. All three are ADR-and-minor-bump work; see
  `docs/development/state.md` §Next up.

## [2.3.4] — 2026-08-20

**Hardening + security sweep.** First full audit since 2.1.x — all of
2.2.x and 2.3.x had shipped without one. 14 defects fixed across
memory safety, silent truncation, streaming correctness, and language
detection; full write-up with reproductions in
[docs/audit/2026-08-20-2.3.x-hardening-audit.md](docs/audit/2026-08-20-2.3.x-hardening-audit.md).
No token kind, no `Token` layout change, no public-API signature
change. 898/898 tests, smoke OK, lint+fmt exit 0, fuzz 4/4.

Two themes ran through nearly every finding, and both are worth
carrying forward:

- **Silent degradation was the default failure mode.** Oversize
  source, oversize grammars, failed allocations and >4 GiB stream
  offsets all produced *plausible wrong output with exit 0*. Four
  fixes below turn silence into a loud error.
- **The gates asserted the right things on inputs too narrow to
  exercise them.** `fuzz/streaming.fcyr` has asserted chunk-
  invariance since 2.1.4 and passes — while 9 of 14 real corpora
  violate it. Same root cause the 2.3.2 `TK_ERROR` audit named, now
  hit twice.

### Fixed

- **`vyk` silently truncated any file over 1 MiB.** `file_read_all`
  stops at `maxlen` and nothing checked for it, so a larger file was
  tokenized to its prefix and reported success. Measured: a
  1,500,027-byte script exited 0 with an empty stderr and ~450 KB —
  30% of the file — discarded; the coverage invariant stopped holding
  at the cut point with no signal. Now a hard error (exit 3) naming
  the limit. Largest accepted file is 1,048,574 bytes, because a read
  of exactly `maxlen` cannot be distinguished from a truncated one.
  Closes **FINDING-003**, open since 2026-04-23.

- **Streaming a document with an embedded block hung.**
  `_stream_compose_prefix_hold` ran an O(`n_temp`) "is this byte
  already emitted" scan for *every byte position* and then the cheap
  `memeq` start-marker test — both conditions must hold, so the
  ordering was pure cost — and the whole function was called **twice
  per drain with identical arguments**. Valid HTML with one inline
  `<style>` block, fed in 4 KB chunks: 16 KB took 1,893 ms and 32 KB
  took 19,644 ms, growing ~O(N^2.3–2.9); a 128 KB stylesheet
  extrapolated to ~30 minutes. Now 32 ms and 89 ms — **59× and
  221×** — with growth ~O(N^1.6). The unterminated-`<style>` case
  went from 28,399 ms to 100 ms at 32 KB (**284×**) and from
  "did not finish in 90 s" to 310 ms at 64 KB. Both changes are
  semantically neutral: the chunk-invariance sweep returns
  byte-identical results before and after. Affects html, markdown,
  vue, svelte and cyml — i.e. what `owl` and `vidya` stream.

- **Chunked streaming closed strings on escaped quotes.** The
  pending-pair `scan_resume` back-off subtracts `elen - 1`, which is
  **zero** for the single-byte close markers JSON and most string
  rules use. A buffer ending on `\` resumed past it, so the next
  feed's `"` was read without its escape. On
  `tests/corpus/concept.json` at chunk=3, `"Scanning until '\"' —
  breaks on escaped quotes"` came back as a 19-byte token instead of
  50, and everything after it was mis-tokenized. Now backs off over
  the trailing *run* of escape bytes — the run start always begins a
  fresh pair, so this is sound where a one-byte back-off would
  mis-pair `\\`. JSON is now chunk-invariant at every tested chunk
  size.

- **Shebangs with interpreter arguments failed detection entirely.**
  `_detect_shebang` scanned the whole line for the last `/` or space,
  so any argument captured the interpreter word: `#!/bin/bash -e`
  resolved to `-e`. `#!/bin/bash -e`, `#!/bin/sh -eu`,
  `#!/usr/bin/python3 -u` and `#!/usr/bin/env -S python3 -u` all
  exited 4, "no grammar matched" — `-e` and `-eu` are ordinary, so
  extensionless shell and python files were rejected wholesale. Now
  takes the basename of the first word and steps over `env`'s own
  options. Seven regression cases added to `scripts/smoke.sh`.

- **One-byte out-of-bounds read in `_ds_scan_tag`.** The first `if`
  incremented `p`, the second re-read `load8(src + p)` at the new
  position **without re-testing `p < src_len`**, so a fence tag
  running to the end of the buffer read `src[src_len]`. Value-neutral
  — the function returns `src_len` either way — but a genuine OOB
  read that faults when `src_len` ends on a page boundary. `vyk` hid
  it by NUL-terminating at `buf[n]`; `tokenize_with_grammar` is
  public surface and an exactly-sized caller buffer is exposed.
  (`_ds_scan_to_lf` looks like the same shape but is safe: it
  increments last.)

- **Stream offsets past 4 GiB wrapped silently.** `Token.start` /
  `len` are u32 (ADR 0002) but `abs_offset` is an i64 accumulating
  over every byte fed. Verified: pushing start `4294967301` reads
  back as `5`. Past 2³² every offset wraps and consumers index
  unrelated bytes with no error. `tokenize_stream_feed` now returns
  `VYK_ERR_OVERFLOW` instead. Widening `Token` needs an ADR and a
  minor bump, so this is the patch-safe half — refuse the input
  rather than corrupt the output. See §Notes for how this finding
  went untracked for four minor lines.

- **Oversize grammars were parsed truncated.** The blob path clamped
  to `GRAMMAR_FILE_CAP - 1` (FINDING-007's fix — memory-safe, but it
  then parsed a grammar cut mid-rule as if complete) and the file
  path had no check at all. A truncated grammar yields a tokenizer
  that is subtly wrong, which is worse than one that is absent. Both
  paths now refuse. Unreachable today — largest bundled grammar is
  6,722 B against a 32,768 B cap — so this is defence for the day one
  grows. All 45 still register.

- **`alloc()` return values were unchecked** at four sites; `alloc`
  returns 0 on OOM, on a negative size, and past `ALLOC_MAX` (2 GiB),
  so a failed grow stored a NULL data pointer and the next push wrote
  through it. Guarded in `tokenbuf_new`, `_tokenbuf_grow`,
  `_stream_grow` and the `tokenbuf_push` path. Closes
  **FINDING-002**, open since 2026-04-23. `tokenbuf_push` **keeps its
  always-`0` return** — it ships in `dist/vyakarana.cyr`, so a status
  return would silently change meaning for consumers that test it; on
  failure it drops the token rather than corrupting the heap.

- **Integer overflow in `tokenize_stream_feed`.** `len + n + 1` wraps
  i64 negative for an absurd `n`, making `_stream_grow`'s
  `cap >= needed` trivially true — it returned success without
  growing and the copy ran off the end of the buffer.

- **`tokenize_stream_drain` over-reported `emitted`**, counting
  tokens that `tokenbuf_push` dropped. `emitted` is what callers use
  to decide whether more tokens are available; now counted from
  `tokenbuf_count` across the loop.

- **`tokenize_stream_free` poisoned `pending_idx` to `0`**, but the
  "none" sentinel is `-1` and `0` is a valid pair-rule index. `free`
  zeroes every field deliberately and two sites rely on that, so this
  one field broke the poison contract. Currently unreachable —
  drain's `buf_len == 0` return and `_stream_grow`'s `cap <= 0` guard
  both fire first — but relaxing either would expose
  `vec_get(pair_rules, 0)` on a NULL grammar.

- **Pull-adapter accessors** `_kind` / `_start` / `_len` lacked the
  `s == 0` and `staging == 0` guards `_next` and `_discard_consumed`
  already have, and indexed `idx = -1` before the first `_next` — a
  12-byte read *before* the tokenbuf allocation. They return 0 now,
  which cannot affect a correct consumer.

### Changed — stale text removed or corrected

The maintainer asked for a deferral-language audit specifically:
every "for now" / "not yet" / "TODO" / "known gap" / "future ADR"
across `src/**`, `grammars/*.cyml`, `docs/**` and the root docs was
classified real-pending, stale, or misphrased.

**Mostly legitimate.** "Known gaps" appears in 39 grammar files and
"stand-in" in 34 — ADR-0006 scope documentation, left alone. All 22
"vidya doesn't ship an X reference sample yet" claims were checked
against `vidya/content/lexing_and_parsing/` and **all 22 are still
accurate**.

**Stale — removed**, each verified against the same file's own rules:

- `c.cyml`, `rust.cyml`, `zig.cyml`, `go.cyml` all still described
  char/rune literals as splitting into three operator tokens and
  proposed a `char_literal` ADR as future work. ADR 0010 shipped and
  `char_literal = true` is set in every one of them.
- `go.cyml` called the backtick raw-string rule a "trivial follow-on"
  — the rule is at `go.cyml:133`. `zig.cyml` said `\\` multi-line
  strings "would need a new line-rule shape" — it is at
  `zig.cyml:145`. `kotlin.cyml` (rule at :145), `sql.cyml` (:196) and
  `ocaml.cyml` said the same about backtick identifiers and
  polymorphic variants. `scss.cyml` said `%placeholder` "would need
  `%` in ident_start or operators"; `%` is in operators.
- `asm_x86_64.cyml` said AT&T operand sigils were "punted to a future
  ADR" — ADR 0020 landed them in 2.3.2. `asm_aarch64.cyml` told ARM
  users to always pass `--language` and called content-based
  detection a "future pass (1.13.0)"; it landed in 1.11.2.

**Misphrased — reworded** so they stop advertising pending work:
`src/theme.cyr` predicted a theme-file format "likely in 1.11.0"
(export shipped in 1.12.1/1.13.0; import does not exist and nothing
has asked for it); `src/main.cyr` said "M5's streaming tokenizer will
remove this ceiling" and `default_scanner.cyr` anchored an
optimization to "M5 benchmark time" — M5 landed in 2.0.0–2.0.2;
`rust.cyml`'s "Good enough for now"; `c.cyml`'s "ADR-worthy later".

`cyrlint` reports **0 untracked deferrals** across every hand-edited
source file. Removing the stale text shrank the embedded grammar blob
from 217,790 to 215,902 bytes.

- **Four present-tense references to `tokenize_source`** — removed in
  2.0.0 — corrected in `src/token.cyr`, `src/main.cyr` and
  `src/grammar.cyr` (×2). Historical references that say "was
  removed" were left as they are.

- **`CLAUDE.md`'s frozen-API rule named `tokenize_source`**, so the
  actual 2.x contract was unguarded. It now names the
  `tokenize_stream_*` surface and notes that
  `tokenize_source_handcoded` is a diagnostics oracle outside the
  rule.

- **`docs/development/state.md`'s cross-repo section** said the 2.3.0
  bundle was "byte-identical apart from its version header, so
  bumping [consumers] buys nothing". True when written — 2.2.3 →
  2.3.0 is literally 2 changed lines — but 2.3.1 and 2.3.2 landed
  real grammar fixes after it. Measured: **2.2.3 → 2.3.3 is 241
  changed lines, +19,565 bytes**. Corrected, with the measurement.

### Added

- **`scripts/smoke.sh`** gained two regression groups: oversize input
  must exit 3 with a diagnostic and emit nothing (and the largest
  accepted size must still tokenize with the coverage invariant
  intact), and seven shebang forms with interpreter arguments must
  route to the right grammar. Both groups were confirmed to **fail
  against the pre-fix binary** — they have teeth.

- **`docs/audit/2026-08-20-2.3.x-hardening-audit.md`** — full audit
  with reproductions, the chunk-invariance baseline table, the
  clean-check list, and prioritized follow-ups.

### Notes

- **The audit ledger lost a finding, and it was the one that
  mattered.** `2026-04-23-audit.md` defines **FINDING-005** as
  "`Token.start` / `Token.len` are u32". Both the 1.13 and 2.1.x
  carryover tables instead record FINDING-005 as
  "`_sanitize_for_stderr` truncates at first control byte". That
  description is *also* wrong about the code — the sanitizer replaces
  control bytes with `?` and does not truncate; verified:
  `--bo<ESC>[31mgus<BEL>TAIL` echoes as `--bo?[31mgus?TAIL`, full
  string preserved, ANSI defanged. So the ledger carried a phantom
  open finding for two audits while the real FINDING-005 fell out of
  tracking. Its LOW rating rested on "practical file sizes don't
  approach this" — true when the only entry point was capped at
  1 MiB, invalidated the moment 2.0.0 shipped a streaming API whose
  header advertises "Total input can exceed this freely". Nobody
  re-rated it because its ID was occupied. **Rule going forward:** a
  carryover table copies the finding's *title* verbatim, never a
  re-description, and an architectural rewrite re-rates the findings
  whose preconditions it changes.

- **Streaming is not chunk-invariant, and that is a documented
  contract.** `fuzz/streaming.fcyr` states it plainly: "any chunking
  strategy produces the same (kind, start, len) tokens as a
  single-shot feed". A differential probe over the real corpora — one
  feed vs 7 chunk sizes, comparing every token — finds it violated in
  9 of 14 grammars: cyml 7/7 chunk sizes differing, markdown 5/7,
  html 5/7, python 5/7, rust 4/7, go 4/7, vue 3/7, css 1/7, toml 1/7;
  json, shell, yaml, typescript, javascript and cyrius are clean. The
  **coverage invariant holds throughout** — no bytes are lost — but
  token boundaries shift with chunk size, so a streaming consumer
  gets a different tokenization from a whole-buffer one. The escape
  fix above closed json; at least two causes remain
  (`_stream_is_trailing_complete` matching *any* same-kind pair
  rule's end marker, and compose-region routing not surviving chunk
  boundaries — which is why cyml, the grammar 2.3.1 was written for,
  is the worst row). Not fixed here: three interacting causes in the
  drain path, and changing token boundaries is observable behaviour,
  i.e. ADR-and-minor-bump territory. Measured identically against the
  pre-audit tree, so this is long-standing, not a 2.3.4 regression.

- **A held compose opener turns `VYK_STREAM_CAP` into a total-input
  ceiling**, contradicting `src/tokenize.cyr`'s "Total input can
  exceed this freely". Isolated directly: with no compose opener, the
  same grammar and bytes accept **32,768,000 bytes** — 2× the cap —
  with `live_buf_len` compacting to 1; with an unterminated `<style>`
  fed first, the buffer grows monotonically until feed returns
  `VYK_ERR_OVERFLOW` permanently. Holding the body is semantically
  required (the scanner refuses to half-consume a compose rule whose
  end marker is absent), so the fix is to *bound* the hold and fall
  back to emitting the body as `TK_STRING` — an observable-behaviour
  decision that needs an ADR.

- **No `openqasm` grammar.** `vidya` ships
  `content/lexing_and_parsing/openqasm.qasm` and renders its samples
  through vyakarana; 11 of its 12 tokenize cleanly and that one exits
  4. Adding a grammar is feature-sized (corpus, registration, and the
  hardcoded `45` in `fuzz/grammar_load.fcyr`), so it is not folded
  into a hardening patch.

- **Clean checks, no findings:** `load8` zero-extends (verified:
  `0xFF → 255`), so the 256-byte char-class table is in-bounds for
  every input byte, and no grammar feeds a high byte into a
  char-class spec (all non-ASCII in `.cyml` files is in comments);
  the CYML escape decoder's sizing and writing loops advance
  identically; `detect.cyr` is bounds-clean apart from the shebang
  logic error; there is **no dead code** (all eight functions
  unreachable from the CLI are live library surface, test-suite or
  fuzz entry points); no command-injection or path-traversal vector.

## [2.3.3] — 2026-08-20

**Toolchain catch-up: pin `6.5.4` → `6.5.32`, and the first cut
whose `lint + fmt` gate is actually green.** No source-behaviour
change — no token kind, no `Token` layout change, no public-API
change, no grammar edit. 898/898 tests, smoke OK, all 45 grammars
unchanged.

The bump is measurably inert. Building the *same* tree with
`6.5.4`'s and `6.5.32`'s `cycc` produces **byte-identical**
binaries (396,888 both), and `cyrius bench` under the two
compilers agrees within run-to-run noise on all eight rows. The
only size movement is the stdlib snapshot itself: 392,472 →
396,888 bytes (+4,416, +1.1%), 343 → 367 unreachable fns, because
`6.5.32`'s stdlib is slightly larger than `6.5.4`'s. Nothing in
`src/` needed a dialect fix to cross four minor lines.

### Changed

- **Toolchain pin `6.5.4` → `6.5.32`** in `cyrius.cyml`. CI reads
  the pin as its single source of truth, so no workflow edit is
  needed.

- **Vendored `lib/` re-cut at the new pin.** `rm -rf lib &&
  cyrius deps`, per CLAUDE.md §Gates — a plain `cyrius deps`
  treats a present `lib/<mod>.cyr` as satisfied and would have
  left the tree at its `6.5.4` vintage. All 27 vendored modules
  are byte-identical to
  `~/.cyrius/versions/6.5.32/lib`; 17 of them changed content:
  `alloc`, `args`, `assert`, `atomic`, `fmt`, `fnptr`, `fs`,
  `io`, `result`, `string`, and all seven `syscalls*` variants.

- **New downstream artifact: `dist/vyakarana.deps`.** `cyrius
  distlib` at 6.5.32 emits a sidecar next to the bundle listing
  the 11 stdlib leaves the fold needs in scope; 6.5.4's `distlib`
  did not produce one. Its own header says it is *consumed by
  `cyrius deps`*, so it must ship alongside `dist/vyakarana.cyr`
  — a consumer pulling `[deps.vyakarana] modules =
  ["dist/vyakarana.cyr"]` gets the bundle without its stdlib
  manifest otherwise. Tracked in git for the same reason the
  bundle is, and deliberately **not** added to `.gitignore`.

### Fixed

- **`sh scripts/lint-fmt.sh` exits 0.** It exited **1** at
  `2.3.2` and at each of the six commits before it — back through
  `09111d0` — with `src/grammar.cyr`, `src/tokenize.cyr` and
  `src/grammars/default_scanner.cyr` all failing `fmt --check`.
  The drift reproduces under the *outgoing* `6.5.4` formatter, so
  it was not a `6.5.32` regression; it was a red release gate
  that CLAUDE.md §Closeout calls mandatory and that CI gates.
  Purely whitespace — `fmt` re-indents wrapped call arguments to
  a 2-space hanging indent (26 lines across the three files). No
  token stream changes.

- **`cyrlint` is fully quiet.** `src/theme.cyr:24` carried an
  untracked `for now` deferral. It was never a deferral: the
  `i64` theme handle is a permanent choice, and the very next
  sentence already gives the reason (Cyrius enums consume
  `gvar_toks` slots). Reworded rather than `#skip-lint`-ed, so
  the comment stops advertising work that was never pending.
  Pre-existing under both pins; `cyrius lint` reports it without
  failing, so `lint-fmt.sh` never caught it.

### Notes

- **The project `lib/` is inert at build time on `6.5.32`.**
  `cycc` resolves stdlib from `~/.cyrius/versions/<pin>/lib`, so
  the pin — not the vendored tree — decides what gets compiled.
  Verified directly: appending garbage to `lib/str.cyr` and
  rebuilding still exits `OK`, while changing only the pin moves
  the binary by 4,416 bytes. Keeping `lib/` synced still matters
  (it silences the `shadow lib` warning, and CI populates it on a
  fresh checkout), but it is no longer the thing under test.
  CLAUDE.md's §Gates note claimed the inverse — that a stale
  `lib/` makes the pin ignored — and has been corrected.

## [2.3.2] — 2026-07-31

**37 grammars stop erroring on valid syntax.** A sweep of every
printable ASCII byte (0x20–0x7E) through all 45 bundled grammars
found 44 emitting `TK_ERROR` for at least one character. Not all
of those were bugs — a backtick really is invalid in C — so each
character was adjudicated per language against that language's
actual syntax. [ADR 0020](docs/adr/0020-tk-error-adjudication.md)
records the rule used. Patch rather than minor, on the same
reasoning as 2.3.1: no token kind, no `Token` layout change, no
public-API change, no new rule type — incorrect output made
correct.

Measured on real source from `/usr/lib`, `/usr/share`,
`/usr/include` and the cargo registry rather than hand-written
samples. Files with at least one error token, before → after:
html 38/40 → 0, javascript 11/40 → 0, typescript 9/40 → 0,
yaml 8/40 → 0, shell 7/40 → 0, zig 5/40 → 0, xml 5/39 → 0,
go 4/40 → 1 (binary testdata carrying a `.go` suffix),
cpp 2/40 → 0, css 1/40 → 0.
`/usr/lib/go/src/runtime/race_amd64.s` went 91 → 0.

### Fixed

- **Backtick-delimited regions.** `shell` and `ruby` backtick
  command substitution — ``PROGNAME=`basename $0` `` — is
  ordinary, extremely common syntax and emitted two error tokens
  per use. Also `crystal` and `php` (both inherit the form),
  `makefile` and `dockerfile` (recipe and `RUN` bodies are
  shell), `go` **raw string literals** (every struct tag,
  `` `json:"name"` ``, was a run of error tokens), `kotlin` and
  `swift` backtick-escaped identifiers, `sql` MySQL quoted
  identifiers, and `ocaml` polymorphic-variant tags (`` `Foo ``).
  Delimited regions use rules, not bare operators; command
  substitution follows the `kind = "string"` precedent
  `grammars/julia.cyml` already set.

- **Assembly, both targets.** `asm_x86_64` rejected `$`, which
  prefixes **every AT&T-syntax immediate** (`movq $60, %rax`) and
  every Plan 9 frame size (`TEXT f(SB), $0-8`); `@`, which
  suffixes relocations (`call printf@PLT`, `sym@GOTPCREL`); and
  `\`, which references a `.macro` parameter. `asm_aarch64` had
  the same `@` and `\` holes (`_setjmp@GOTPAGE`). None of it was
  caught because `tests/corpus/asm_x86_64.s` is `.intel_syntax
  noprefix` — a dialect that uses no `$` at all. `asm_x86_64`
  also gained the `//` and `/* */` comment rules its aarch64
  sibling already had: it claims the `.S` extension, which means
  "C-preprocessed", and real `.S` files use `//` freely.

- **Operators that were simply missing.** `haskell` `$` (the
  function-application operator, one of the most-used in the
  language); `rust` `@` pattern bindings and `macro_rules!`
  internal-rule sigils; `julia` `'` postfix adjoint (`A'`);
  `javascript` / `typescript` `#` private class fields and `@`
  decorators; `csharp` `#` preprocessor directives (`#if DEBUG`,
  `#region`, `#nullable`); `swift` `#` directives (`#if os(iOS)`,
  `#available`, `#Preview`) and `\` key paths (`\Person.name`);
  `scss` `%` — both the placeholder-selector sigil and the
  percent unit, the same fix `css` got at 2.1.1 and scss missed;
  `css` / `scss` `\` selector escapes (`.w-1\/2`); `nix` `~`
  home-relative paths; `powershell` `\` in bare Windows paths;
  `graphql` `.`, `+` and `-` for negative ints and signed
  exponents; `elixir` single-quoted charlists; `zig` `\\`
  multiline string literals (275 error tokens across a 40-file
  sample); `llvm_ir` `$` comdat names; `toml` `:` in RFC 3339
  datetimes; `dockerfile` `%`.

- **Char-literal escape fallbacks.** Where `'` opens a char
  literal rather than a string, `'` and `\` are now operator
  fallbacks in `cpp`, `crystal`, `csharp`, `java`, `kotlin`,
  `swift` and both asm grammars. [ADR 0010](docs/adr/0010-char-literal-default.md)'s
  scanner models `'C'`, `'\C'` and `'\xHH'`; the four-hex form
  `'A'` — valid Java, C# and Kotlin — fragmented into three
  error tokens without them. `grammars/c.cyml` already carried
  both entries; the rest had diverged from it. `cpp` also needed
  `'` for C++14 digit separators (`1'000'000`) and `\` for the
  line continuations every multi-line macro relies on.

- **Free-text formats.** `html`, `xml`, `vue`, `svelte`, `yaml`
  and `ini` rejected characters that are ordinary content:
  `<p>50% off &mdash; $5 &amp; more! a|b ~ c</p>` produced five
  error tokens. Element content, attribute values, template text,
  YAML plain scalars and INI values are arbitrary characters.
  `$HOME` in CI YAML — 29 hits in a 40-file sample — was the
  single most common instance.

- **Non-ASCII identifiers and scalars.** Nine grammars never set
  `unicode_ident`, so every byte of a non-ASCII identifier became
  its own error token: `const café = 1` (valid JavaScript),
  `café = 1` (valid Python 3, PEP 3131) and `let café = 1` (valid
  Rust since 1.53) each produced two. Flag added to
  `javascript`, `typescript`, `python`, `rust`, `shell` and
  `yaml`. This is the non-ASCII half of the same bug class and
  sits outside the printable-ASCII sweep that found the rest;
  `json`, `toml` and `cyrius` were left alone, since non-ASCII
  outside a string genuinely is invalid there.

### Unchanged — deliberately

- `c`, `cyml`, `cyrius`, `json`, `lua`, `protobuf` and
  `terraform` came through the audit untouched: every byte they
  reject really is invalid in those languages, and they tokenize
  real-world samples with zero errors today. `python` is a
  half-case — its printable-ASCII rejections (`!`, `$`, `?`,
  `` ` ``) are all correct and stand; the file was edited only
  for `unicode_ident`. `markdown` was fixed in 2.3.1.
  Negative probes assert `$` still errors in `json` and `lua`,
  and backtick still errors in `c`, `python` and `cyrius`, so a
  later blanket "add every byte" change cannot pass the gates.

### Added

- **48 probes** in `tests/vyakarana.tcyr` (test group "2.3.2
  `TK_ERROR` holes"), 850 → **898 passing**. Each is the smallest
  piece of genuine source the pre-2.3.2 grammar rejected, plus a
  `tb_error_count(tb)` helper and the negative probes above.
- **Corpus coverage for 29 ADR-0006 stand-ins.** `smoke.sh`
  enforces a zero-error bar per corpus, so these are a second
  independent gate — verified load-bearing by reverting
  `grammars/ruby.cyml` and confirming smoke fails on
  `tests/corpus/concept.rb`. The vidya-backed corpora (shell, go,
  rust, python, zig, typescript, both asm) are left alone per
  [ADR 0001](docs/adr/0001-corpus-sync-policy.md) — they re-sync
  by `cp` — so those grammars are covered by probes only.
- [ADR 0020](docs/adr/0020-tk-error-adjudication.md) — the rule
  for when `TK_ERROR` is correct and when it is a hole, the
  three-tier fix preference, and what was deliberately left
  erroring.

## [2.3.1] — 2026-07-31

**CYML finally parses as CYML.** The grammar for vyakarana's own
native format merged TOML and markdown into one rule set instead
of routing each half, which mis-typed exactly the things a CYML
body exists to hold. Patch rather than minor: no token kind, no
`Token` layout change, no public-API change — incorrect output
made correct.

### Fixed

- **CYML markdown bodies are routed to the markdown grammar**
  ([ADR 0019](docs/adr/0019-compose-region-rule.md)). Through
  2.3.0 a body's `# Heading` matched the TOML `#` line-comment
  rule and came back as one `comment` token spanning the line,
  and a ` ``` ` fence met the backtick pair rule — the third
  backtick opened a span that swallowed the whole code block into
  a single `string`, info string and all. A ` ```cyrius ` block
  inside a CYML body now routes two composition levels deep and
  yields real `fn` / `return` keywords.

  `grammars/cyml.cyml` had named composition as the proper fix
  since 1.9.0 and called the union rule set a stopgap.
  Composition shipped in 1.11.0; cyml was never migrated. Twelve
  minor releases, on the format this repo's own 45 grammar files
  are written in.

- **`markdown` no longer emits error tokens for ordinary prose.**
  `"`, `'` and `$` were in neither the operator nor the
  punctuation list, so they fell through to `TK_ERROR`. Any
  markdown containing a quotation mark, an apostrophe (`It's`) or
  a dollar sign made `vyk` exit 1 — this repo's own `README.md`
  tripped it 8 times, `CONTRIBUTING.md` 21. Quotes and
  apostrophes join `,` `;` `.` as punctuation, `$` joins `@ % ^ &`
  as an operator. Pre-existing and independent of the CYML work;
  found because routing CYML bodies to markdown surfaced it.

### Added

- **`match = "compose_region"` rule type**
  ([ADR 0019](docs/adr/0019-compose-region-rule.md)) — routes an
  open-ended region through a named inner grammar. Two properties
  ADR 0013's `compose` cannot provide, both of which CYML needs:
  `end_before` is a **lookahead** terminator left unconsumed for
  the outer grammar (so the `[[entries]]` that ends a body still
  tokenizes as TOML), and reaching **EOF** without the terminator
  is a normal ending rather than a failure (so a file's last body,
  always EOF-terminated, is routed at all). `compose` consumes its
  `end` and emits nothing when the marker is absent.

- `tests/corpus/phase_d.cyml` — a byte-for-byte vidya snapshot
  ([ADR 0001](docs/adr/0001-corpus-sync-policy.md)) of
  `cyrius/field_notes/mabda_v3_gpu/phase_d.cyml`, 229 lines
  carrying real fenced blocks. The existing
  `tests/corpus/dependencies.cyml` has neither a body heading nor
  a fence, which is the entire reason this survived: every gate
  was green because nothing in the corpus exercised the gap. Ten
  new `tcyr` probes lock the heading, terminator, EOF and fenced
  cases directly.

### Changed

- **`---` in a CYML file is now `punctuation`, was `operator`.**
  It is the start marker of a compose region, so it takes the
  same kind `compose` gives `<style>`. This is the cut's one
  visible token-output change.
- `GRAMMAR_SIZE` 176 → 184 bytes for the new
  `compose_region_rules` vec. Internal to `src/grammar.cyr`, not
  part of any published contract.

### Known gaps

- A CYML body line beginning with `[` at column 0 ends the region
  early — `end_before` is a literal `\n[`, not a line-anchored
  TOML-header match, so a markdown link-reference definition
  (`[1]: https://…`) hands the rest of the body back to the header
  rules. Indented or inline `[` is unaffected. Same class of
  documented literal-prefix limit as `<script>` vs
  `<script type="module">` (ADR 0013).
- A sweep of every printable ASCII byte through all 45 grammars
  found 44 with at least one character that yields `TK_ERROR`.
  Many are correct — a backtick genuinely is invalid in C — but
  some are not: backtick command substitution is standard in both
  `shell` and `ruby` and currently errors. Only the `markdown`
  holes are fixed here; the rest need per-grammar judgment against
  each language's real syntax and are left for their own pass.

## [2.3.0] — 2026-07-31

**Toolchain catch-up.** Moves the pin `6.1.24` → `6.5.4`, four
minor lines in one step. Minor rather than patch because the bump
required source changes: the test suite did not compile, and
`cyrius deps` did not resolve, at *either* pin. No public-API,
token-layout, or grammar changes; 45 grammars and 4/4 fuzz
harnesses unchanged, and the test suite is green at 840/840 for
the first time since the defects below were introduced.

### Changed

- **Toolchain pin `6.1.24` → `6.5.4`** in `cyrius.cyml`. Local
  devs run `cyriusly use 6.5.4`. Every remaining declared stdlib
  module (`syscalls`, `alloc`, `fmt`, `io`, `fs`, `str`,
  `string`, `vec`, `args`, `hashmap`, `assert`) resolves in
  6.5.4; all five gates plus `cyrius fuzz` and `cyrius bench`
  are green.
- **Vendored `lib/` re-cut from the 6.5.4 snapshot.** The tree on
  disk was a 6.0.x-vintage snapshot that predated both the 6.1.24
  pin and this one — `cyrius deps` treats an already-present
  `lib/<mod>.cyr` as satisfied and never refreshes it, so the
  pinned stdlib had been silently ignored at build time since
  2.2.2. A fresh checkout is now required to re-vendor: `rm -rf
  lib && cyrius deps`.
- Dropped `agnoshi` from the downstream-consumer list in
  `cyrius.cyml`'s `[lib]` comment. The actual consumers declaring
  `[deps.vyakarana]` are `owl`, `cyim`, and `vidya`; agnoshi has
  no vyakarana reference and has not had one.

### Fixed

- **`cyrius deps` failed on a fresh checkout** because `[deps]
  stdlib` listed `"cyml"`. The module was not deleted — it was
  **folded into the `bayan` bundle at 6.1.24**, where its 17
  `cyml_*` symbols live today; what disappeared is the
  standalone `lib/cyml.cyr` the deps list resolves against
  (present through 6.1.23, gone at 6.1.24). So 2.2.3's own pin
  move is what broke it: from that cut on, CI's "Resolve
  dependencies" step could not have passed on a clean checkout,
  and the local build only worked because the stale `lib/` held
  the last surviving copy of `cyml.cyr`.

  Removed rather than re-pointed at `bayan`, because the entry
  was vestigial either way — the grammar loader parses
  `grammars/*.cyml` with a purpose-built scanner in
  `src/grammar.cyr` (deliberately "not a general CYML/TOML
  implementation", per its header) and has never called a
  `cyml_*` symbol. Declaring `bayan` would vendor an unused
  module. Adopting bayan's parser in place of the hand-rolled
  one is a live design question, but it changes the grammar
  loader's behaviour and belongs in an ADR, not a pin bump.
- **`cyrius test` failed to compile** with `duplicate variable`
  errors. Cyrius rejects a second `var NAME` bound in the same
  lexical block, and `tests/vyakarana.tcyr` is one 3,100-line
  `fn main()` in which eleven names were re-declared across test
  sections. Renamed the later declarations to section-scoped
  names (`tb_css1-3` / `src_css1-3` for the CSS block, `gc_st`
  for the stress block, `tb_sr1-3` for the streaming block,
  `saw_tf_arrow` for the Terraform block). Pure renames — no
  assertion, input, or expected value changed.

  These predate this release. They reproduce identically under
  the outgoing 6.1.24 pin *and* under 6.0.3, so both 2.2.3 and
  2.2.2 shipped with a red test gate — long enough that
  `docs/development/state.md`'s "840/840 tests passing" claim had
  gone stale without anyone re-running the gate. The
  compiler under-reports them — error recovery swallows the
  statement after each duplicate, so only 4 of the 11 surfaced
  in any single run, along with a spurious `undefined variable
  'gc'` cascade. Do not drive this class of fix from compiler
  output alone.

### Verified rather than assumed

- **Zero stdlib removals** across the declared module set between
  the 6.1.24 and 6.5.4 snapshots. The only signature changes are
  added `: Str` annotations on `lib/fs.cyr` path/extension
  helpers, none of which vyakarana calls.
- **`dist/vyakarana.cyr` is byte-identical** to the 2.2.3 bundle
  apart from its version header — no downstream churn for `owl`,
  `cyim`, or `vidya`, all three of which still pin `tag =
  "2.2.3"`.
- **No benchmark regression.** All 8 rows in
  `tests/bcyr/vyakarana.bcyr` are flat or faster than the 2.2.1
  baseline, well inside the 20% watch threshold. `build/vyk` fell
  390,784 → 371,472 bytes.
- Byte-level input handling (`load8`/`store8` over `src + i`,
  `alloc` sizing, `file_read_all` capping) re-read against the
  6.5.4 stdlib; the coverage invariant holds on every corpus.

## [2.2.3] — 2026-06-10

**Toolchain pin bump.** Moves the pin `6.0.3` → `6.1.24`. No
public-API, token-layout, or grammar changes; 45 grammars,
840/840 tests, 4/4 fuzz harnesses unchanged.

### Changed

- **Toolchain pin `6.0.3` → `6.1.24`** in `cyrius.cyml`. Local
  devs run `cyriusly use 6.1.24`. All declared stdlib modules
  (`syscalls`, `alloc`, `fmt`, `io`, `fs`, `str`, `string`,
  `vec`, `args`, `hashmap`, `assert`, `cyml`) resolve in 6.1.24;
  all five gates (build, test, smoke, lint, fmt) green.

## [2.2.2] — 2026-05-27

**Modernization cut.** Bumps the toolchain pin 5.10.5 → 6.0.3 and
moves the vendored stdlib to the `cyrius deps` model used by the
sibling first-party libraries (`patra`, `sigil`). No public-API,
token-layout, or grammar changes; 45 grammars, 840/840 tests, 4/4
fuzz harnesses unchanged.

### Changed

- **Toolchain pin `5.10.5` → `6.0.3`** in `cyrius.cyml`. Local
  devs run `cyriusly use 6.0.3`. All declared stdlib modules
  (`syscalls`, `alloc`, `fmt`, `io`, `fs`, `str`, `string`,
  `vec`, `args`, `hashmap`, `assert`, `cyml`) resolve in 6.0.3.
- **Vendored `lib/` is now gitignored** ([ADR 0018](docs/adr/0018-vendored-stdlib-gitignored.md)).
  Previously 20 stdlib files were committed at the 5.10.5
  vintage; a checked-in `./lib/` shadows the version-matched
  toolchain snapshot, so the pin was effectively ignored at
  build time. `cyrius deps` now repopulates `lib/` from the
  pinned snapshot on each checkout. Untrack with `git rm -r
  --cached lib`.
- **CI / release install via the upstream `cyrius` installer.**
  `.github/workflows/{ci,release}.yml` previously did a manual
  `curl + tar + cp` that dropped the stdlib in a flat
  `~/.cyrius/lib`. 6.0.x reads the version-matched snapshot from
  `~/.cyrius/versions/<pin>/lib`, which only the upstream
  `install.sh` lays out — so `cyrius deps` can repopulate the
  now-gitignored `lib/`. The manual copy was harmless while
  `lib/` was committed; it would have broken the build on a
  fresh checkout once it wasn't. Pin still read from
  `cyrius.cyml` (no hardcoded version). Dropped a dead
  `matrix.installer` field. Matches `patra` / `sigil`.

### Fixed

- **`vyk --list-languages` printed pointer addresses on 6.0.x.**
  Cyrius 6.0 annotates `vec_get(v, idx): i64`, so the
  unannotated `println(vec_get(...))` in `print_list_languages`
  dispatched to the `println_int` overload. Bind the result
  through a `var name: cstring` local to land on the string
  overload. The bug was masked pre-2.2.2 by the committed 5.10.5
  `lib/` (untyped `vec_get`); surfaced once the 6.0.3 snapshot
  took over per ADR 0018.

### Docs

- ADR index (`docs/adr/README.md`) backfilled with the 0014–0017
  entries that were missing, plus the new 0018.
- Consumer-integration guide dep example bumped to `tag =
  "2.2.2"` and the stale "38 grammars" count corrected to 45.

## [2.2.1] — 2026-05-08

**Wrap-up cut for the 2.1.5 audit queue.** Resolves
FINDING-011 (compose-rule prefix buffering across chunks)
and lands the defensive `staging == 0` guard the audit
called for. Re-enables the random-split fuzz cases that
were skipped in 2.1.4 pending this fix. No public-API
changes; pure streaming-correctness work.

### Added

- **Compose-rule prefix buffering.**
  `_stream_compose_prefix_hold(g, buf, buf_len, temp_tb,
  n_temp)` walks every compose / compose_fenced rule's
  start marker and returns the count of trailing bytes
  that must be held back from commit. Two cases covered:
  (a) trailing bytes that match a *prefix* of a start
  marker (e.g., last 2 bytes of buf are `` `` ``, prefix of
  `` ``` ``); (b) full start matched mid-buffer with no end
  yet. Drain drops trailing temp_tb tokens whose extent
  overlaps the held region — they re-tokenize cleanly on
  the next feed once the rest of the marker arrives.
  Helper takes `temp_tb` so case (b) can skip positions
  that are *already* the start of an emitted compose
  TK_PUNCTUATION (e.g., markdown's emitted close marker is
  a complete `` ``` `` that would otherwise look like a
  fresh opener with no following close).
- **Defensive `staging == 0` guard in
  `tokenize_stream_discard_consumed`.** Filed in the
  2.1.5 audit; previously a use-after-free where `_free`
  zeroed staging would crash on
  `tokenbuf_drop_front(0, …)`'s `load64(tb + 8)`. One-line
  null check matching the rest of the streaming primitive.
- **Pair-pending guard against compose-prefix overlap.**
  When drain leaves a trailing partial pair-rule (string
  / block comment), it caches `(rule_idx, scan_resume)`
  for the fast path. 2.2.1 skips that caching when the
  partial overlaps the prefix-hold region — otherwise the
  pair fast path would race compose_fenced on the next
  feed, matching the nearest backtick instead of waiting
  for the full `` ``` `` open marker.
- **Skip-prefix-hold guard for committed compose ends.**
  The drain commit logic skips prefix-hold case (a) when
  the *last already-committed* token is a TK_PUNCTUATION
  matching a compose end marker — those bytes are claimed
  by the just-emitted compose pair and should not be
  re-interpreted as a partial upcoming opener.

### Changed

- **Streaming fuzz coverage re-enabled.**
  `fuzz/streaming.fcyr` now exercises HTML
  (`<style>` / `<script>` compose), Vue SFC, and Markdown
  (` ``` ` fenced) random-split cases. Pre-2.2.1 these
  were skipped because compose-rule START markers split
  across chunk boundaries lost the route. With the
  prefix-hold fix the byte-equivalence invariant holds
  across all 5 split shapes (2 / 4 / 8 / 16 / 32 chunks).

### Fixed

- **FINDING-011 (compose-rule prefix buffering).**
  Surfaced by 2.1.4's streaming fuzz; deferred from the
  2.1.5 audit. A chunk that ended mid-marker
  (`<sty` of `<style>`, ` `` ` of `` ``` ``) used to commit
  spurious tokens (a single `<` operator + `sty` ident,
  or a 2-byte inline-code TK_STRING) instead of waiting
  for the rest of the marker. The held-bytes pattern
  ensures the next drain re-scans those bytes against the
  full grammar instead.

## [2.2.0] — 2026-05-08

**Toolchain pin bump cyrius `5.10.0` → `5.10.5`.**
User-driven version refresh; pure pin change with no
vyakarana code modifications. All gates clean against the
new toolchain (836/836 tests, 4/4 fuzz harnesses, smoke +
lint OK, distlib regenerated). Cut as a minor (2.1.x →
2.2.0) because consumers pinning vyakarana need to know the
toolchain expectation moved.

### Changed

- **`cyrius.cyml`** — `cyrius = "5.10.5"` (was `"5.10.0"`).
  CI's release-tarball install will pull 5.10.5's complete
  bundle (binary + stdlib together) on every PR. Local
  developers should run `cyriusly use 5.10.5` to match the
  pin (per the captured agent-memory rule: pin is
  authoritative, local conforms — never the reverse).

### Stdlib drift inherited

The 5.10.0 → 5.10.5 cyrius release window includes stdlib
shape changes that vyakarana inherits via `cyrius deps`:

- `lib/string.cyr` `strlen` gained an explicit `: i64`
  return-type annotation and a word-at-a-time SWAR
  implementation (replaces 5.10.0's byte-at-a-time loop).
  Functionally equivalent.
- `lib/string.cyr` adds `println_int(n: i64)` as an
  overload-dispatch target for `println(strlen(...))`-style
  callers. vyakarana doesn't use it directly.
- `lib/str.cyr` `str_from`, `str_new`, `str_from_a`,
  `str_new_a` gained `: Str` return-type annotations.
  Behaviour unchanged; vyakarana doesn't use these.

None of these affect vyakarana's runtime behaviour — the
gates verify identical token output across both versions.

### Status

- **No code changes** in `src/`, `grammars/`, `tests/`, or
  `fuzz/`. Pure infrastructure cut.
- **Bundled grammars: 45** (unchanged from 2.1.5).
- **Tests: 836/836 passing** on 5.10.5. **Fuzz: 4/4 passing.**
- Open items from 2.1.5 audit (FINDING-011 compose-prefix
  streaming, defensive `staging == 0` guard, binary-size
  cap revisit) carry forward unchanged.

## [2.1.5] — 2026-05-08

Closes the 2.1.x window with the **post-2.1 security audit**.
0 new findings; FINDING-010 (fixed in 2.1.4) and FINDING-011
(deferred — compose-rule prefix streaming gap) recorded in
the carryover table. No code changes — pure audit.

### Added

- **`docs/audit/2026-05-09-2.1.x-closeout-audit.md`** —
  full surface review of every 2.1.x change. Per-function
  bounds analysis on `tokenbuf_drop_front`,
  `tokenize_stream_discard_consumed`, the
  `_stream_is_trailing_complete` tightening, the
  `detect_language` length-bucket refactor, and each of
  the seven new grammars. Buffer-cap semantics confirmed
  unchanged from the 2.0.x close. Streaming fuzz harness
  (2.1.4) called out as the most rigorous correctness
  check in the suite — already caught two bugs on its
  first run.
  **0 CRITICAL / 0 HIGH / 0 MEDIUM / 0 LOW (no new
  findings).**

### Status

- **2.1.x is closed.** Seven grammars added (PowerShell,
  Crystal, Julia, Vue, Svelte, Nix, Terraform); discardable
  pull-adapter staging; streaming-aware fuzz; trailing-
  complete heuristic tightened; closeout audit. Bundled
  grammar count: 38 → 45 across the window.
- Carryover findings table updated. FINDING-010 fixed in
  2.1.4 in-pass. **FINDING-011 (compose-rule prefix
  streaming gap) is the only deferred item** — picked up
  in the next streaming-opt cut.

### Recommendations carried forward

- **Defensive `staging == 0` check in
  `tokenize_stream_discard_consumed`** — one-line guard;
  matches the pattern used elsewhere; out of scope for
  2.1.5 but should land in the next opt cut alongside
  FINDING-011's fix.
- **Compose-rule prefix buffering** — required for
  FINDING-011; same opt cut.
- **Revisit the 1.13.0 binary-size soft cap** (300 KB).
  Predates ADR 0014's embedded-grammar design; binary now
  ~376 KB and rising with each grammar batch. Not a
  security concern; flagged for 2.x roadmap.
- **Toolchain pin discipline** — `feedback_cyrius_pin_authority.md`
  in agent memory now captures the rule (use `cyriusly use
  <pin>`; never bump `cyrius.cyml` to chase local).

## [2.1.4] — 2026-05-08

Streaming optimization + fuzz cut. **Discardable pull-adapter
staging** caps memory for long-running iteration; **streaming-
aware fuzz harness** verifies byte-equivalence between
random-split and single-shot feeds. The harness caught two
real correctness gaps; one fixed in-pass, one filed for the
next opt cut.

### Added

- **`tokenize_stream_discard_consumed(s)`** — drops tokens
  already iterated past via `_next` from the pull-adapter's
  internal staging tokenbuf. Caller invokes periodically
  (e.g., after every N iterated tokens) to bound memory in
  long-running streams. Returns count dropped; no-op when
  nothing iterated yet; null-safe.
- **`tokenbuf_drop_front(tb, n)`** — internal primitive in
  `src/token.cyr`. Shifts records [n, count) to [0,
  count - n) via forward byte copy (overlap-safe), updates
  count. Bounds-clamps when `n >= count`.
- **`fuzz/streaming.fcyr`** — random-split fuzz harness.
  For each (source, language) pair, splits at 2/4/8/16/32
  random offsets and verifies the resulting tokenbuf is
  byte-equivalent to a single-shot tokenize. xorshift-
  seeded; deterministic; failures reproduce. Covers shell
  (line+pair+special_vars), rust (multi-byte ops, generics,
  ranges), C (block comments straddling chunks — the 2.0.3
  case), Python (indented blocks). 4 fuzz harnesses now;
  3 → 4.
- **6 new tcyr probes** in the `2.1.4 pull-adapter discard +
  streaming heuristic fix` group: discard returns dropped
  count, _next continues post-discard, no-op on empty,
  null-safety, split-after-opening-quote produces baseline
  count. 830 → 836 passing.

### Fixed

- **Trailing-complete heuristic over-eager on same-byte
  pair markers.** Pre-2.1.4, a chunk ending right after an
  opening `"` (or `'`, `` ` ``, etc.) had its trailing
  TK_STRING (length 1) wrongly marked complete because the
  closing-marker check `memeq(buf + tail - elen, endp,
  elen)` matches the open quote against itself. Streaming
  would commit the open quote as a 1-byte string; the
  actual close on the next feed then opened a SECOND
  string. Caught by the new `streaming.fcyr`
  `c/string-with-escape` random-split case. Fixed by
  requiring `t_len >= slen + elen` (minimum complete
  length) before applying the closing-marker check.

### Notes

- **Compose-rule start markers split across chunks lose
  the route.** `<style>`, `<script>`, `<template>`,
  ` ```rust ` etc. — when a chunk boundary lands inside
  the start marker, the leading byte (`<` or `` ` ``)
  commits as a 1-byte token before the rest of the marker
  arrives, so the compose rule never matches. The fix
  needs compose-aware prefix buffering — scanner has to
  hold trailing bytes that match a prefix of any
  compose-rule start marker. **Filed for the next
  streaming-opt cut**; HTML / Vue / Svelte / Markdown
  cases are skipped in `streaming.fcyr` until then.
  Single-shot tests in `tests/vyakarana.tcyr` continue to
  cover compose correctness for whole-buffer inputs.
- **Bench unchanged** — the discard primitive is opt-in;
  callers that don't use the pull adapter (or don't call
  `_discard_consumed`) see no behavioural change. The
  trailing-complete fix is a tightening that could
  marginally delay some commits, but `tokenize/*` bench
  numbers are within noise.

## [2.1.3] — 2026-05-08

Final grammar batch of the 2.1.x window. **Terraform / HCL**
(`.tf`, `.tfvars`, `.hcl`) — the HashiCorp Configuration
Language Terraform / Packer / Vault / Nomad / Consul all
consume. Bundled grammar count: 44 → 45. Closes the
2.1.x grammar-batch wave.

### Added

- **`grammars/terraform.cyml`** + `tests/corpus/concept.tf`.
  Named `terraform` because that's what most users will
  search for, but the underlying language is HCL — same
  grammar covers any HCL-consuming HashiCorp tool. Surface:
  - **Both `#` and `//` line comments** + `/* … */` block
    comments. The 2-byte `//` marker doesn't collide with
    `/*` (line scanner checks the full marker length).
  - **`=>` for-expression operator** (longest-match before
    `=`), **`...` variadic / spread** as 3-byte op.
  - **Kebab-case idents** via `-` in `ident_cont` —
    `aws_s3_bucket`, `azurerm_role_assignment`, `my-bucket`.
  - **Block syntax** `resource "type" "name" { ... }`
    tokenizes naturally — ident + string + string + brace.
    No special block-header token kind needed.
  - Standard arithmetic / equality / comparison / logical /
    ternary operators.
- **5 new tcyr probes** — resource ident, kebab-case ident,
  both comment markers (`#` + `//`), `=>` for-expression
  operator, `...` spread. 822 → 830 passing.
- **1 new M3 corpus** — Terraform config exercising
  resource blocks, variables, locals, outputs, dynamic
  blocks, `for` expressions, `for_each`, conditionals, both
  comment forms, attribute/block distinction. Round-trips
  with zero error tokens.
- **Detection wired** — `.tf` (3-byte) → `_detect_short`,
  `.hcl` (4-byte) → `_detect_4byte`, `.tfvars` (7-byte) →
  `_detect_5plus`. All map to `terraform`.

### Documented gaps

- **Heredocs** `<<EOT … EOT` / `<<-EOT … EOT` — variable
  terminator. Same scanner-shape gap as Lua / Ruby / PHP /
  Crystal heredocs.
- **String interpolation** `${expr}` — body tokenizes as
  part of the surrounding string.
- **Splat shorthand** `aws_instance.web.*.id` — `*`
  tokenizes as a 1-byte op amidst dotted access; theme can
  re-pair.

### Status

- **2.1.x grammar wave is closed.** PowerShell / Crystal /
  Julia (2.1.0); Vue / Svelte SFC (2.1.1); Nix (2.1.2);
  Terraform / HCL (2.1.3). 38 → 45 bundled grammars in the
  2.1.x window — 7 new in four cuts.

## [2.1.2] — 2026-05-08

Third grammar batch of the 2.1.x window. **Nix** language
(`.nix`) — the functional, lazy-evaluated configuration
language behind NixOS, home-manager, and the Nix package
ecosystem. Bundled grammar count: 43 → 44.

### Added

- **`grammars/nix.cyml`** + `tests/corpus/concept.nix`.
  Nix-specific quirks handled:
  - **`//` is set merge / update**, NOT a line comment.
    Listed first in operators (longest-match) so `a // b`
    tokenizes as ident + 2-byte op + ident, not as a line
    comment of the rest of file.
  - **`++` list concatenation** — Haskell-style; 2-byte op.
  - **`->` implication**, **`?` has-attribute test**, **`@`**
    "as" pattern in function args (`{ pkgs, ... }@args:`).
  - **Idents accept `'` and `-`** — Haskell-prime (`iter'`,
    `prev'`) and kebab-case (`home-manager`,
    `nixpkgs-unstable`). Both in `ident_cont`.
  - **`''…''` indented multi-line strings** — 2-byte pair
    rule. Greedy match closes at first plain `''`.
    Documented limitation: doubled `'''` (escape sequence)
    inside a body would close early.
  - **`/* … */` block + `#` line comments.**
- **6 new tcyr probes** covering let-keyword, `//` set
  merge, `++` list concat, prime-suffix idents,
  kebab-case idents, indented strings. 811 → 822 passing.
- **1 new M3 corpus** — round-trips with zero error tokens,
  coverage invariant satisfied (2633 bytes / 596 tokens).

### Documented gaps (corpus doesn't trigger)

- String interpolation `${expr}` — body tokenizes as part of
  the surrounding string. Same trade-off as Vue / JS template
  literals.
- Path literals (`./foo`, `~/cfg`, `<nixpkgs>`) — split into
  separate punct + ident pieces; theme can re-pair on token
  adjacency.
- Indented-string escapes (`''$`, `'''`, `''\n`) — pathological
  cases would close the pair early. Not in real-world corpora.

## [2.1.1] — 2026-05-08

Second grammar batch of the 2.1.x window. **Vue** and
**Svelte** single-file components — both prime
`compose`-rule consumers, routing `<script>` bodies through
JavaScript and `<style>` bodies through CSS. Bundled
grammar count: 41 → 43.

### Added

- **`grammars/vue.cyml`** + `tests/corpus/concept.vue`.
  HTML-shaped outer tokenizer with Vue-shorthand prefixes
  (`@` v-on, `#` v-slot) in operators. `<script>` →
  javascript and `<style>` → css via compose rules.
  `<template>` deliberately NOT a compose rule — routing
  through html would drop Vue's own `@`/`#` operators on
  the template content, so the outer Vue tokenizer handles
  template bytes directly. Documented gaps: Vue directives
  (`v-if`, `v-for`), `{{ … }}` mustache interpolation,
  attribute-bearing block tags (`<script lang="ts">`).
- **`grammars/svelte.cyml`** + `tests/corpus/concept.svelte`.
  Same shape as Vue but no `<template>` block — Svelte's
  template content lives at the top level of the file.
  `$` in operators for reactive declarations (`$:`).
  Documented gaps: logic blocks (`{#if}`, `{#each}`),
  single-brace interpolation, reactive `$:` semantics,
  bind/on/class/use directives.
- **9 new tcyr probes** in the `2.1.1 Vue / Svelte SFC
  grammars` group — Vue script routes to JS keyword, Vue
  style routes to CSS hex-ident, Vue `@click` tokenizes via
  outer grammar (not html-routed), Svelte script routes to
  JS, Svelte `bind:value` tokenizes as ident-punct-ident.
  799 → 811 passing.
- **2 new M3 corpora** added to the smoke list — both
  round-trip with zero error tokens, coverage invariant
  satisfied.

### Fixed

- **CSS missing `%` operator.** Surfaced when adding Vue's
  `concept.vue` corpus — `width: 100%;` in the `<style>`
  block emitted a TK_ERROR for `%`. Added to css.cyml's
  operator list. Same fix benefits any CSS / SCSS corpus
  that uses percentage units.

### Notes

- The compose rules use literal start markers (`<script>`,
  `<style>`); attribute-bearing forms (`<script lang="ts">`,
  `<style scoped>`) fall back to plain outer-grammar
  tokenization. Same documented limitation as ADR 0013
  §When to revisit, now with one more consumer pushing on
  it. A future cut could add captured-attribute composition
  (similar to compose_fenced's tag capture) so
  `<script lang="ts">` routes through TypeScript.

## [2.1.0] — 2026-05-08

First grammar batch of the 2.1.x window. **PowerShell**,
**Crystal**, and **Julia** grammars added — three new
general-purpose languages, no breaking changes. Bundled
grammar count: 38 → 41.

### Added

- **`grammars/powershell.cyml`** + `tests/corpus/concept.ps1`.
  Verb-Noun cmdlets tokenize as one ident (`-` in
  `ident_cont`); alphabetic operators (`-eq` / `-and` /
  `-match` / etc.) longest-match before bare `-`. Variables
  via `$` in `ident_start`. Block + line comments. Both
  string forms (single literal, double interpolated). Case-
  insensitive keywords. Extensions: `.ps1` / `.psm1` /
  `.psd1`. Shebangs: `pwsh`, `powershell`. Documented
  limitations: here-strings (`@'…'@`), string interpolation
  body, cmdlet-parameter context.
- **`grammars/crystal.cyml`** + `tests/corpus/concept.cr`.
  Ruby-shaped tokenizer with `?` and `!` in `ident_cont`
  (predicate-style and mutating-method names — `empty?`,
  `push!`, `is_a?`). `@` in `ident_start` for instance
  vars. `<=>`, `===`, `=~`, range `..`/`...`, splat `**`
  operators. Documented limitations: heredocs, string
  interpolation, macro markers (`{% %}` / `{{ }}`).
- **`grammars/julia.cyml`** + `tests/corpus/concept.jl`.
  `@` in `ident_start` for macros (`@show`, `@time`,
  `@inbounds`). `!` in `ident_cont` for mutating-method
  names (`push!`, `sort!`). `::` type annotations. Triple-
  quoted strings (`"""..."""`) and backtick command
  literals. Block comments (`#=...=#`) and line comments
  (`#`) — both expressed as pair rules so the longer `#=`
  wins over `#`, mirroring the Lua `--`/`--[[` pair-vs-line
  collision pattern (architecture note 003). Documented
  limitations: nested block comments (greedy match closes
  at first `=#`), Unicode operators (tokenize as ident).
- **15 new tcyr probes** in three groups: PowerShell
  basic shapes (cmdlet ident, alphabetic operator,
  variable-as-ident, block comment); Crystal basic shapes
  (predicate ident with `?`, instance var with `@`);
  Julia basic shapes (function keyword, type annotation,
  macro and mutating idents, triple-quoted string).
  778 → 799 passing.
- **3 new smoke corpora** added to the M3 list: clean-tokenize
  with zero error tokens, coverage invariant satisfied
  (corpus byte count == sum of token lengths).

### Changed

- **`detect_language` refactored into length-bucket helpers.**
  Cyrius caps return statements per function at 64; the
  growing extension list pushed past that. Split into
  `_detect_short` / `_detect_4byte` / `_detect_5plus` /
  `_detect_basename` helpers, each well under the cap.
  `detect_language` becomes a 4-call dispatcher preserving
  first-match-wins ordering.
- **`fuzz/grammar_load.fcyr` blob-count assertion updated**
  from 38 → 41 to match the new bundled count.
- **Bundle size** (`dist/vyakarana.cyr`): grew with the three
  inlined grammars per ADR 0014.

### Notes

- PowerShell's `special_vars` flag is **off** (unlike shell):
  the shell-pipeline lone-`$` step at scanner stage 5 emits
  `$` as a 1-byte operator before stage-6 ident scan can fire,
  splitting `$args` into `$` op + `args` ident. With
  `special_vars = false` and `$` in `ident_start`, `$args`
  tokenizes as one 5-byte ident. Trade-off: `$?` / `$$`
  no longer get the shell-style 2-byte operator emission and
  split as `$` ident + `?` op (theme can re-pair).

## [2.0.4] — 2026-05-08

Closes the 2.0.x streaming wave with the **post-2.0
security audit** (triggered by the 2026-05-09 1.13-closeout
audit's recommendation to revisit buffer-bound semantics
after streaming lands). Two LOW findings, both fixed in the
audit pass. No public API change.

### Fixed

- **FINDING-008 (LOW, audit pass).** `_stream_grow` would
  infinite-loop on a stream whose buffer cap was zero —
  e.g., a freed stream whose pointer was reused (every
  field zeroed by `_free`). The doubling loop
  `new_cap = new_cap * 2` makes no progress when
  `new_cap == 0`. Fix: explicit `if (cap <= 0) { return 0; }`
  before the doubling. Use-after-free is clearly caller
  error, but defending in depth is cheap.
- **FINDING-009 (LOW, audit pass).**
  `_stream_scan_close` would vacuously match at `from` if
  the pair rule's end marker was empty (`elen == 0`),
  emitting a zero-length token that violates the coverage
  invariant. Cause: `memeq(buf + j, endp, 0)` returns 1
  for any pointer pair. Fix: explicit
  `if (elen <= 0) { return (0 - 1); }` short-circuit. The
  CYML loader doesn't currently reject empty `end = ""`
  markers — the runtime guard makes this a defense-in-depth
  safety net rather than a load-time validation.

### Added

- **`docs/audit/2026-05-09-2.0.x-closeout-audit.md`** — full
  surface review of every 2.0.x change. Per-function
  bounds analysis on `_stream_grow`, `_stream_scan_close`,
  `_stream_find_pair_rule`, `_stream_is_trailing_complete`,
  the rolling-buffer drain, the pull adapter, and the
  pending pair-rule fast path. Buffer-cap semantics
  documented (`VYK_STREAM_CAP` caps live buffer, not total
  input — design intent of streaming).
  **0 CRITICAL / 0 HIGH / 0 MEDIUM / 2 LOW (both fixed
  in-pass).**

### Recommendations carried forward (not addressed in 2.0.4)

- **CYML loader hardening.** Reject pair rules with empty
  `start` / `end` markers at load time. Today the runtime
  guard from FINDING-009 catches this; load-time rejection
  is cleaner. Flagged for 2.1.x or sooner if a grammar
  author trips it.
- **Streaming-aware fuzz harness.** Random feed sequences
  (varying chunk sizes, random splits across multi-byte
  tokens) would catch pending-pair edge cases the current
  corpus-based fuzz misses. Flagged for 2.1.x.
- **Discardable pull-adapter staging.** For very long
  streams the staging tokenbuf grows monotonically (~12 MB
  per million tokens). Memory pressure, not security
  finding; flagged in state.md.

### Status

- **2.0.x is closed.** Streaming-API surface (2.0.0),
  rolling buffer (2.0.1), pull adapter (2.0.2), pending-pair
  fast path (2.0.3), closeout audit (2.0.4). Ready for
  the 2.1.x grammar-batch wave.
- **Next: 2.1.0 — PowerShell / Crystal / Julia grammars.**

## [2.0.3] — 2026-05-08

Streaming optimization cut. **Pending pair-rule tracking**
drops O(N²) → O(N) for the pathological "long open span
across many chunks" case. No public API change.

### Added

- **Pending pair-rule fast path in `tokenize_stream_drain`.**
  When a drain detects an uncommitted trailing pair-rule
  partial (open string / block comment / preprocessor
  directive), the stream saves `(rule_idx, scan_resume)`.
  Subsequent drains skip the full scanner and look directly
  for the close marker, advancing `scan_resume` so body
  bytes already proven not to contain the close are never
  re-scanned. Drops total work for an N-byte open span
  spread across K chunks from O(N×K) to O(N).
- **Two new helper functions in `src/tokenize.cyr`:**
  - `_stream_find_pair_rule(g, buf, start, len, kind)` —
    matches a partial token's leading bytes against the
    grammar's pair rules to find which one was open.
  - `_stream_scan_close(buf, buf_len, from, endp, elen, escape)`
    — bounded close-marker scan honouring the rule's
    escape byte.
- **Stream record: 72 → 88 bytes.** New fields
  `pending_idx` (offset 72; -1 = no pending) and
  `scan_resume` (offset 80; bytes already known not to
  contain the close).
- **9 new tcyr probes** in the `2.0.3 streaming
  optimization — pending pair-rule fast path` group:
  - 100 chunks of 10 bytes each fed inside an open block
    comment; after the close arrives, drain emits one
    TK_COMMENT spanning all 1006 bytes.
  - Close marker straddling two feeds (`*` then `/`); the
    `elen - 1` back-off in `scan_resume` ensures it's
    found.
  - Pending state clears after the close — post-comment
    idents tokenize normally.
  769 → 778 passing.

### Changed

- **No public-API change.** `tokenize_stream_*` and
  `tokenize_stream_next` semantics preserved exactly.
  Optimization is purely internal — same tokens emitted
  for the same input bytes.
- **`tokenize_stream_free` clears the new fields** on
  release.

### Performance

- **Single-shot bench unchanged** — the pending-pair
  branch doesn't fire when finish() runs over a fully-
  buffered source. Shell 21 µs / rust 30 µs / json 6 µs /
  html-compose 11 µs (matching 2.0.2 within bench noise).
- **Streaming pathological case dramatically improved**
  but not in the bench suite yet (no streaming-style
  benches today; flagged for a future cut). The 1006-byte
  100-chunk probe completes immediately rather than
  taking 100× longer than a single-shot equivalent.

### Status

- **2.0.x closeout audit (2.0.4) is queued next.** Per the
  2026-05-09 1.13-closeout audit's recommendation, a
  dedicated audit is triggered by buffer-bound semantic
  changes from streaming. 2.0.4 will cover 2.0.0 / 2.0.1 /
  2.0.2 / 2.0.3 surfaces in one pass.
- After 2.0.4, the **2.1.x grammar batches** open: 2.1.0
  PowerShell / Crystal / Julia; 2.1.1 Vue / Svelte SFC
  (compose_fenced consumers); 2.1.2 Nix; 2.1.3 Terraform /
  HCL.

## [2.0.2] — 2026-05-08

Closes the 2.0.x streaming-prep wave with the **pull adapter**
— iterator-style API over the 2.0.1 push primitive. Closes
the followup queued from the original 2.0.0 cut.

### Added

- **`tokenize_stream_next(s)`** — advances the internal
  cursor, returning 1 if a token is now current or 0 if
  exhausted. Refills the stream's staging tokenbuf via
  `_drain` automatically when the staging is empty.
- **`tokenize_stream_kind(s)`** / **`_start(s)`** /
  **`_len(s)`** — read the kind, absolute start, and length
  of the *current* token (the one most recently returned by
  `_next == 1`). Behaviour is undefined if called before the
  first successful `_next`.
- **drain / finish accept `out_tb = 0`** — routes the drain
  into the stream's internal staging tokenbuf instead of a
  caller-supplied one. Lets the iterator pattern work without
  the caller fishing the staging out:
  ```
  tokenize_stream_finish(s, 0);
  while (tokenize_stream_next(s) == 1) {
      var k = tokenize_stream_kind(s);
      ...
  }
  ```
- **11 new tcyr probes** in the `2.0.2 pull adapter` group:
  pull-iteration matches push-baseline counts and per-token
  (kind, start, len); interleaved feed + iterate; empty
  stream returns 0 before and after finish; null-stream
  safety; absolute starts after compaction.
  758 → 769 passing.

### Changed

- **Stream record: 56 → 72 bytes.** Two new fields:
  `staging_tb` (offset 56) holds the pull-adapter's internal
  tokenbuf; `next_idx` (offset 64) tracks the iteration
  cursor. `tokenize_stream_new` allocates the staging at
  init; `_free` clears both.
- **`_drain` and `_finish` semantics extended (additive).**
  Existing callers that pass a real out_tb keep working
  exactly as before. Passing 0 is the new contract for
  iterator-style consumers — no breakage.

### Documentation

- **Consumer integration guide** gains a pull-style render
  example alongside the push-style baseline. Both produce
  identical output; choice is consumer ergonomics.

### Status

- **2.0.x prep wave is complete.** Streaming API surface
  (2.0.0), per-feed drainage (2.0.1), pull adapter (2.0.2).
  Next minor (2.1.x or whatever the user prioritizes) opens
  the post-streaming queue: scanner state-machine
  optimizations, additional consumer-driven features, etc.

## [2.0.1] — 2026-05-08

First sub-cut of the 2.0.x window. **Rolling-buffer
streaming** lands — `drain()` actually drains tokens
incrementally as they're committed, the buffer compacts
after each commit so memory is bounded by the longest
in-progress span instead of the total input size, and the
1 MB cap on total input is gone.

### Added

- **Rolling-buffer scanner via rescan-and-commit.** Each
  `tokenize_stream_drain(s, out_tb)` re-runs the existing
  scanner over the current buffer, commits every token
  whose extent is fully present, and compacts the buffer by
  sliding unconsumed bytes to offset 0. `abs_offset`
  tracks the absolute byte position of `buf_ptr[0]` so
  token starts emit absolute (cumulative bytes since
  stream creation), not buffer-relative.
- **Trailing-complete heuristic** (`_stream_is_trailing_complete`).
  A token whose end == buf_len is dropped in feed mode by
  default — its bytes might extend with subsequent feeds,
  changing the token's kind or length. Exception: pair-rule
  tokens (TK_STRING / TK_COMMENT / TK_PREPROCESSOR) whose
  trailing bytes match the rule's end marker are
  definitively complete and commit early. Same for line-rule
  tokens ending in LF. Operators / punctuation /
  identifiers / keywords / numbers / whitespace are treated
  conservatively as potentially-extending — they wait for
  finish().
- **12 new tcyr probes** in the `2.0.1 rolling-buffer
  streaming — per-feed drainage` group:
  - feed → drain → feed → finish; verifies absolute starts
    after compaction.
  - Block comment crossing a feed boundary; verifies the
    comment commits as one TK_COMMENT spanning both
    chunks.
  - Byte-at-a-time stream (each byte in its own feed); the
    final tokenbuf is byte-equivalent to a single-shot
    feed of the same source.
  746 → 758 passing.

### Changed

- **`VYK_STREAM_CAP`: 1 MB → 16 MB** (live-buffer cap, not
  total input). The cap now bounds the longest in-progress
  span — block comments, multi-line strings, fence bodies —
  rather than the cumulative byte count. A 100 MB log file
  with normal line-comment density streams comfortably
  under 4 KB live buffer.
- **Stream record: 48 → 56 bytes.** Replaced the 2.0.0
  `drained` flag (offset 40) with `cursor`. Added
  `abs_offset` at offset 48 — total bytes committed prior
  to current buffer.
- **`tokenize_stream_drain` semantics.** 2.0.0 returned 0
  until finish; 2.0.1 returns the count appended by this
  call. Drains can run between feeds; tokens land
  incrementally.
- **2.0.0 streaming probe updated** — the assertion that
  drain-before-finish returns 0 was removed (was testing
  the deferred 2.0.0 implementation). Replaced with checks
  that drain emits some tokens early but holds the
  trailing partial.
- **Bench overhead per call:** ~10% regression on top of
  2.0.0 (shell 19 → 21 µs, rust 28 → 30 µs, json 5 → 6 µs,
  html-compose 10 → 11 µs). Cost of the per-drain rescan;
  amortized away in true streaming use cases where drain
  runs once per chunk rather than per token.

### Status of 2.0.x followups

- **2.0.2 — Pull adapter (`tokenize_stream_next`).** Now
  meaningful because drain actually streams. Trivial
  wrapper over the push primitive once it lands.

## [2.0.0] — 2026-05-08

🎉 **First major version bump.** The 1.x line shipped 14
versions across the bundled-grammar growth (1.0.0–1.9.0) and
the pre-2.0 prep wave (1.10.x–1.13.x). 2.0.0 delivers the
**streaming tokenizer** that's been spec'd since M0 — the only
scheduled API break in the entire roadmap.

### BREAKING

- **`tokenize_source(src, lang)` removed.** Replaced by the
  push-based streaming primitive (see Added). Migration is
  mechanical; the 1.x → 2.0 recipe is in
  [ADR 0017](docs/adr/0017-streaming-api.md). Consumers that
  can't migrate yet should pin `1.13.3` indefinitely — that
  cut closed the 1.x line cleanly with 0 audit findings.

### Added

- **Streaming tokenizer API
  ([ADR 0017](docs/adr/0017-streaming-api.md)).** Push-based
  primitive, five entries:
  - `tokenize_stream_new(lang)` — returns an opaque stream
    handle, or 0 if the grammar isn't registered.
  - `tokenize_stream_feed(s, chunk, n)` — appends `n` bytes
    from `chunk` to the stream's internal buffer. Returns
    `VYK_OK` (0), `VYK_ERR_OVERFLOW` (-1) on cap exceeded,
    `VYK_ERR_FINISHED` (-2) after finish has run.
  - `tokenize_stream_drain(s, out_tb)` — emits tokens for
    completed spans into `out_tb`. Returns count appended.
    **2.0.0 implementation:** scanner runs at finish, so
    drain returns 0 until then. 2.0.1+ delivers per-feed
    drainage.
  - `tokenize_stream_finish(s, out_tb)` — marks done; runs
    the scanner; emits every remaining token.
  - `tokenize_stream_free(s)` — releases the stream handle.
  Multi-chunk feed is byte-equivalent to single-chunk feed —
  any chunking strategy produces the same `(kind, start, len)`
  tokens. Verified by 8 new tcyr probes.
- **15 new tcyr probes** in the 2.0.0 streaming-primitive
  group: single-chunk feed, multi-chunk feed, unknown
  grammar, empty grammar name, feed-after-finish error,
  empty input, drain-after-finish idempotency, split-feed
  byte-equivalence with one-shot feed. 731 → 746 passing.

### Changed

- **Sub-cut scope: API surface only.** 2.0.0 ships the new
  contract; the internal scanner is unchanged. feed() buffers
  chunks into a contiguous source; finish() runs the
  existing `tokenize_with_grammar`. Real per-token-resume
  streaming (rolling buffer, scanner state machine) lands in
  2.0.1+. The public API is stable across that internal
  refactor — consumers wire up the right shape today and
  pick up the speedup automatically.
- **Pull adapter (`tokenize_stream_next`) deferred to 2.0.1+.**
  Useful for iteration-style consumers; trivial wrapper over
  the push primitive once the per-token-resume scanner is in
  place.
- **`src/main.cyr`** — `tokenize_buf` now drives the streaming
  API for the non-`--handcoded` path. CLI behaviour is
  identical to 1.13.3 because the CLI always has the full
  source available; the stream just buffers it once.
- **`src/tokenize.cyr`** — full rewrite. Public symbols:
  `tokenize_stream_*`, `has_grammar`, `bootstrap_grammars`,
  `tokenize_source_handcoded` (internal regression oracle).
  Removed: `tokenize_source`.
- **Test harness** uses a `_t_tokenize(src, lang)` wrapper
  that performs the new/feed/finish/free dance. Test bodies
  stay readable while exercising the new API end-to-end.
- **Fuzz harnesses + bench file** migrated. Bench numbers
  regress modestly due to per-call alloc overhead:
  shell 18 → 19 µs, rust 26 → 28 µs, json 3 → 5 µs,
  html-compose 8 → 10 µs. The streaming benefit (memory
  bound by per-token state) waits for 2.0.1+; 2.0.0
  effectively still buffers everything.
- **Architecture overview + consumer guide** updated to
  describe the new entry shape. "Frozen public contracts"
  list restated for 2.x.

### Migration

```cyrius
# 1.x
var tb = tokenize_source(src, "rust");

# 2.0
var s = tokenize_stream_new("rust");
var tb = tokenbuf_new();
tokenize_stream_feed(s, src, strlen(src));
tokenize_stream_finish(s, tb);
tokenize_stream_free(s);
```

Five lines instead of one. Detection (`detect_language*`),
LSP bridge (`lsp_kind_*`), kind constants, tokenbuf accessors,
theme export, grammar load, and registry helpers are all
unchanged across 1.x → 2.x.

## [1.13.3] — 2026-05-08

Final 1.13.x sub-cut and the **last release before 2.0.0**.
Documents the actual distribution paths (after confirming
`cyrius package` is still upstream-stubware) and ships the
post-1.12 + 1.13.x security audit. No code changes — pure
RC-polish housekeeping.

### Added

- **`docs/development/distribution.md`** — describes the two
  distribution paths in current use:
  1. `dist/vyakarana.cyr` (the single-file source bundle for
     `cyrius deps` consumers; ADR 0014).
  2. The GitHub release tarball
     (`vyakarana-<VERSION>-x86_64-linux.tar.gz`) built by
     `release.yml` on every semver tag push.
  Includes a chooser table for downstream consumers, the
  release procedure for the operator, and a `cyrius package
  status` section noting the upstream stub. Verified locally:
  walked through the `release.yml` package step against the
  built `vyk` 1.13.2 binary, extracted the tarball, ran
  `vyk --version` from the extracted location.
- **`docs/audit/2026-05-09-1.13-closeout-audit.md`** — covers
  every surface added in 1.12.0 / 1.12.1 / 1.13.0 / 1.13.1 /
  1.13.2. **0 CRITICAL / 0 HIGH / 0 MEDIUM / 0 LOW (no new
  findings).** Carryover table from the 2026-04-23 pre-1.0
  audit + 2026-05-09 1.11-closeout audit. Per-surface review:
  Helix + iTerm theme emitters; bench artifact; CLI error-
  message split; man page; `match = "compose_fenced"` with
  detailed bounds analysis; toolchain pin bump.
  Recommendation: dedicated audit when 2.0.0's streaming
  tokenizer lands (changes the buffer-bound semantics that
  the existing FINDING-002/003/004 mitigations are designed
  for).

### Changed

- **state.md `## Past audits`** — adds the 1.13-closeout
  audit. Next scheduled audit moves to 2.0.0 first cut.

### Status

- `cyrius package` remains stubware upstream — produces a
  binary that SIGILLs at runtime due to unresolved stdlib
  symbols. No `.ark` format spec yet. Documented in
  `distribution.md` §`cyrius package` status; revisit when
  upstream lands the ark work.
- 731/731 tests passing, 3/3 fuzz harnesses passing, all six
  gates green from clean rebuild. **Ready for 2.0.0.**

## [1.13.2] — 2026-05-08

Third sub-cut of the 1.13.x RC-polish window. **Markdown
fence routing** — pulls the followup deferred from ADR 0013.
New `match = "compose_fenced"` rule type captures the
language tag from the fence info-string and routes the body
through the named inner grammar. Toolchain pin bumped to
match the local stdlib expectations.

### Added

- **`match = "compose_fenced"` rule type
  ([ADR 0016](docs/adr/0016-compose-fenced-rule.md)).** Same
  shape as ADR 0013's compose rule, but the inner grammar is
  captured per-fence-instance from the input bytes between
  `start` and the next LF (the CommonMark "info string"). New
  `Grammar` field `compose_fenced_rules` at offset 168
  (`GRAMMAR_SIZE` 168 → 176). New scanner step **0b** in
  `tokenize_with_grammar` — runs after compose (step 0) and
  before pair / line / words steps so the ` ``` ` start marker
  isn't eaten as inline code. Tag character class is
  `[A-Za-z0-9_+-]+` — covers all bundled grammar names plus
  common variants (`c++`, `python3`).
- **Markdown adopts compose_fenced** for triple-backtick
  fences. Verified: ` ```rust ` body now produces TK_KEYWORD
  for `fn` / `let` via the Rust grammar; ` ```python ` body
  produces TK_KEYWORD for `def`. Coverage invariant holds in
  every fence shape (with tag, without, unknown tag,
  unclosed).
- **13 new tcyr probes** in the 1.13.2 markdown-fence-routing
  group — Rust routing, Python routing, unknown-tag fallback,
  empty-tag fallback, unclosed-fence fall-through, `c++` tag
  accepts. 717 → 731 passing.
- **2 new smoke probes** (CLI-level): `vyk file.md` with a
  Rust fence surfaces the `fn` keyword; bogus tag falls back
  to TK_STRING.

### Changed

- **Toolchain pin: `cyrius = "5.10.0"`** (was `5.9.36`).
  Local cyrius and stdlib drift made 5.9.36 unbuildable on
  systems with the newer toolchain — the `cyrius deps` resync
  pulled stdlib that the older compiler couldn't validate.
  Bumping the pin matches the active toolchain. CI's
  install-toolchain step pulls 5.10.0's release tarball
  automatically.
- **`grammars/markdown.cyml`** — fence rule swapped from
  `match = "pair"` (kind = "string", whole fence as one
  TK_STRING) to `match = "compose_fenced"` (open marker as
  TK_PUNCTUATION, inner-grammar tokens, close marker as
  TK_PUNCTUATION). Existing markdown tests in
  `tests/vyakarana.tcyr` updated to the new shape (≥3 tokens
  per fence; coverage check unchanged).

### Wiring

- `src/grammar.cyr` — `compose_fenced_rules` field,
  `compose_fenced_rule_*` accessors, `_gp_close_rule`
  handles `mt = 5`.
- `src/grammars/default_scanner.cyr` —
  `_ds_try_compose_fenced_rules` helper plus four small
  scanner utilities (`_ds_is_tag_byte`, `_ds_scan_tag`,
  `_ds_scan_to_lf`, `_ds_find_fenced_close`). Wired as step
  0b in `tokenize_with_grammar`.
- `grammars/markdown.cyml` — fence rule type swap.
- `tests/vyakarana.tcyr` — 1.13.2 group + M3 markdown probe
  refreshed for the new shape.
- `scripts/smoke.sh` — 2 fence probes (rust routing,
  bogus-tag fallback).

## [1.13.1] — 2026-05-08

Second sub-cut of the 1.13.x RC-polish window. **Error
messages get useful**, `vyk --help` gets Exit-codes and
Examples sections, and a real **man page** ships under
`docs/man/vyk.1`. Every CLI failure class now produces a
specific, actionable message + the documented exit code.

### Added

- **`docs/man/vyk.1` — groff man page.** Mirrors `vyk --help`
  with NAME / SYNOPSIS / DESCRIPTION / OPTIONS / EXIT STATUS
  / EXAMPLES / OUTPUT / FILES / SEE ALSO sections. Render
  with `groff -man -Tutf8 docs/man/vyk.1`. Update procedure
  documented in the file header — refresh whenever
  `print_help` changes.
- **`vyk --help` Exit-codes section.** Lists 0/1/2/3/4 with
  one-line meanings. Was implicit in spec/state.md before;
  now explicit at the CLI surface.
- **`vyk --help` Examples section.** Five canonical
  invocations: NDJSON tokenize, themed render,
  extensionless-via-language, `--export-theme=`,
  `--list-languages | grep`.
- **`--handcoded` documented.** The M1 hand-coded shell
  oracle was always present but never appeared in `--help`.
  Now listed explicitly as a regression diagnostic.

### Changed

- **Error messages split by failure class.** The single
  `usage_error` was used for four different failure shapes
  with the same misleading "unknown option" prefix. Now:
  - `unknown_option_error(flag)` — `--bogus`
  - `bad_value_error(flag, allowed)` — `--theme=nope`
    emits `vyk: invalid value for --theme=nope` and lists
    the allowed values (`default, dark, none`).
  - `extra_arg_error(arg)` — second positional FILE
    emits `vyk: extra argument: …` + `only one FILE may
    be given`.
  - `unknown_option_error` keeps the original "unknown
    option:" + "try --help" wording for genuinely unknown
    flags.
- **`io_error` adds a reason hint.** Was bare
  `vyk: cannot read FILE`; now `vyk: cannot read FILE: file
  not found or not readable`. Cyrius doesn't expose `errno`
  beyond a negative return from `file_read_all`, so the
  message is still generic — but actionable enough that a
  user knows whether to check the path or the permissions.
- **`no_grammar_error` drops the misleading hint.** Old
  message ended in `(try --language=shell)` — telling users
  to override with shell when their file is something else
  entirely. New message points to `--language=<name>` and
  `--list-languages`.

### Wiring

- `src/main.cyr` — three new error functions; four call
  sites migrated from the catch-all `usage_error` to the
  specific variants. `usage_error` removed (was a shim per
  CLAUDE.md "no backwards-compat hacks"; nothing else in
  the codebase referenced it).
- `scripts/smoke.sh` — 9 new error-message probes covering
  every failure class + the new `--help` sections.
- No new tcyr probes — error messages are CLI-surface only.
- No ADR — error UX changes don't change the documented
  contract; just refines the wording within the same
  exit-code mapping.

## [1.13.0] — 2026-05-08

First sub-cut of the 1.13.x RC-polish window. Establishes the
performance baseline ahead of 2.0.0. No public API change; no
new ADRs. Adds `tests/bcyr/vyakarana.bcyr` and
`docs/development/performance.md` so future agents have a
reference number to diff against.

### Added

- **`tests/bcyr/vyakarana.bcyr` — eight-benchmark suite.**
  Tokenize hot paths (`tokenize/shell-small`, `rust-small`,
  `json-small`, `html-compose`); detection paths
  (`detect/path-shell`, `content-python`, `combined-asm-arm`);
  blob-load path (`blob/grammar-load-shell`). Run with
  `cyrius bench tests/bcyr/vyakarana.bcyr`. `setup()` warms the
  grammar registry so the per-iteration cost reflects the
  steady-state path, not bootstrap.
- **`docs/development/performance.md` — release-boundary
  baseline.** Captures binary size + per-call latency table for
  1.13.0 (Linux x86_64). Future cuts append a §History entry
  and refresh the table.

### Measured (1.13.0 baseline, Linux x86_64)

- **Binary size:** `build/vyk` is **325.9 KB**, ~26 KB over the
  300 KB soft target from the 1.13.x roadmap entry. The
  dominant contributor is the embedded grammar blobs (~170 KB
  of inlined CYML text per ADR 0014). 300 KB target predates
  ADR 0014; revisiting it before 2.0 is open. `dist/vyakarana.cyr`
  is 263.3 KB.
- **Tokenize latencies (small inputs):** shell 18 µs / rust
  26 µs / json 3 µs / html-with-compose 8 µs.
- **Detection latencies:** path-only 30 ns / content sniff
  184 ns / combined asm-flavour vote 5 µs.
- **Grammar load (blob path):** 32 µs per `grammar_load` call
  — one-time cost per grammar at bootstrap.

### Changed

- **CLAUDE.md §Hardening step item 3** — bench step now
  references the concrete `tests/bcyr/vyakarana.bcyr` and
  `docs/development/performance.md`. Watch for >20%
  regressions on tokenize and detect rows.

## [1.12.1] — 2026-05-08

Pulls the deferred theme-export formats from 1.11.1's
"deferred until a real consumer asks" list. Two new
emitters; CLI surface unchanged beyond accepting two more
`--export-theme=` values. No new ADR (extends 1.11.1's
design).

### Added

- **`vyk --export-theme=helix`.** Emits a Helix `theme.toml`
  for the chosen palette (pair with `--theme=<name>`). Maps
  vyakarana kinds to Helix's TextMate-adjacent scope
  vocabulary: `keyword`, `string`, `constant.numeric`,
  `comment`, `operator` (no `keyword.` prefix), `punctuation`,
  `keyword.directive` (Helix's name for preprocessor /
  `#include` style directives), `error` (not `invalid`),
  `variable`. Header comment describes the `config.toml`
  pairing pattern.
- **`vyk --export-theme=iterm`.** Emits an iTerm
  `.itermcolors` plist (Apple property list / XML) with the
  16 ANSI colours plus `Background Color`,
  `Foreground Color`, `Cursor Color`, and `Selection Color`.
  Float channel values precomputed for each canonical byte
  value in the palette (Cyrius has no float runtime; switch
  on the byte value, return a literal float-string). Default
  theme uses a light background; dark theme inverts to black
  background + light foreground.

### Changed

- **`src/theme_export.cyr`** — header comment updated to list
  three formats; emitters added below the existing
  `theme_export_vscode`. The `_te_*_hex(theme, kind)` lookups
  are unchanged (Helix shares the kind→hex mapping with VS
  Code; iTerm uses a separate fixed 16-colour palette).
- **`src/main.cyr`** — `--export-theme=` dispatch grew from
  one format to three. Unknown formats still exit 2 via
  `usage_error`.
- **`--help`** — lists `vscode`, `helix`, `iterm` under
  `--export-theme=<format>`.

### Wiring

- `scripts/smoke.sh` — 6 new probes (helix default + dark
  with brightness check, iterm default with Ansi 0/15/
  Background Color presence, iterm dark with `0.0` channel
  value verifying the inverted background, unknown-format
  rejection).
- No new tcyr probes — emitters are pure stdout writers; the
  smoke layer covers the full output shape.

## [1.12.0] — 2026-05-08

First cut of the 1.12.x window — **fuzz + stress harness**
plus the post-1.11 **security audit**. Lays the M7 prep
groundwork: every public entry now has a fuzz harness; every
known pathological-input class has a stress probe; one LOW
finding fixed in the audit pass.

### Added

- **Fuzz harnesses (`fuzz/*.fcyr`).** Three per public-API
  entry point, runnable via `cyrius fuzz`:
  - `fuzz/tokenize.fcyr` — empty buffer, 1-byte sweep across
    256 byte values × 3 grammars, pseudorandom buffers (3
    sizes × 16 iterations × 6 grammars), adversarial inputs
    (compose nesting, comment soup, escape jumble). Asserts
    the four documented invariants: non-null tokenbuf,
    positive lens, non-decreasing starts, coverage = strlen.
  - `fuzz/detect.fcyr` — pathological paths, random byte
    buffers (3 sizes × 16 iters), BOM-only inputs, NUL-
    truncated shebangs, truncated `<?xml` / `<!DOCTYPE`
    prefixes, combined dispatch with `.s` × random content.
    Asserts every non-zero return is a registered grammar
    name.
  - `fuzz/grammar_load.fcyr` — 8 known blob round-trips,
    printable-random CYML through `_gp_parse` (3 sizes × 8
    iters), pathological CYML (empty headers, runaway
    open-quote). Asserts no crash; null-or-valid handle.
  All three pass deterministically (xorshift seeded from
  fixed constants). CI runs them via a new `cyrius fuzz`
  step after the smoke test.
- **Stress probes** in `tests/vyakarana.tcyr` 1.12.0 group:
  runaway block comment, runaway string, block-comment soup,
  broken UTF-8 mid-ident, unclosed `<style>` compose,
  6× adjacent compose blocks, 4KB ident run. Coverage
  invariant holds in every case. 707 → 717 passing.
- **Audit doc** `docs/audit/2026-05-09-1.11-closeout-audit.md`
  — covers every surface added in 1.11.0 / 1.11.1 / 1.11.2.
  0 CRITICAL / 0 HIGH / 0 MEDIUM / 1 LOW (FINDING-007, fixed
  in-pass). Carryover findings table from the 2026-04-23
  pre-1.0 audit.

### Fixed

- **FINDING-007 (LOW, audit pass).** `grammar_load`'s blob
  path didn't clamp the copy loop against `GRAMMAR_FILE_CAP -
  1`. Defense-in-depth — today's largest grammar is 6.7KB vs
  a 32KB cap, but a future grammar past 32KB would overflow
  the alloc'd buffer. One-line clamp added before the copy.

### Changed

- **CI runs `cyrius fuzz` on every PR.** New step in
  `.github/workflows/ci.yml` after the smoke test. Failing
  any harness invariant blocks the merge.

## [1.11.2] — 2026-05-08

Third (and final) sub-cut of the 1.11.x window. **Content-based
language detection** — resolves the `.s` / `.S` asm flavour
ambiguity carried since 1.2.3, plus shebang and signature
sniffing for extensionless files. New ADR (0015), one new
public module, no new grammars.

### Added

- **`src/detect.cyr` module ([ADR 0015](docs/adr/0015-content-based-detection.md)).**
  Three public entries:
  - `detect_language(path)` — extension/basename suffix match
    (moved from `src/main.cyr`; same shape).
  - `detect_language_from_content(src, src_len)` — pure byte
    sniff. Strips UTF-8 BOM, then tries shebang interp lookup
    (`bash` / `zsh` / `dash` / `sh` → `shell`; `python*` →
    `python`; `node*` → `javascript`; `ruby*` → `ruby`; `lua*`
    → `lua`; `php*` → `php`) and signature peek (`<?xml` →
    `xml`; `<!DOCTYPE html` / `<!doctype html` / `<html` →
    `html`; other `<!DOCTYPE …` → `xml`). Returns 0 when
    nothing matches.
  - `detect_language_combined(path, src, src_len)` — path
    first; if path returns `asm_x86_64` the asm flavour is
    rescored from content (see below); if path returns 0
    falls through to the content sniff.
- **Asm flavour scoring.** First 4KB scan, weighted hits for
  ARM signals (`.arch armv8` / `.arch armv7` / `b.eq` / `b.ne`
  / `ldp ` / `stp ` / ` x0,` / ` x1,` / ` w0,` / ` w1,` /
  `xzr` / `wzr`) vs x86 signals (`.intel_syntax` /
  `.att_syntax` / ` rax` / ` rdi` / ` rsi` / ` rsp` / ` rbp` /
  `syscall` / `xmm0`). Higher score wins; tie / no-signal
  defaults to `asm_x86_64`. Verified: both
  `tests/corpus/asm_x86_64.s` and `tests/corpus/asm_aarch64.s`
  auto-route to the correct grammar with zero `TK_ERROR`
  tokens — closes the long-standing `.s` extension dispatch
  hack.

### Changed

- **`vyk` reads the source file before detection.** Previously
  the file read happened inside `tokenize_file`; the function
  was renamed `tokenize_buf` and now takes a pre-read buffer +
  length. Detection runs against the same buffer, no second
  read. Net behaviour: identical for path-known extensions;
  vyk now succeeds for shebang-led extensionless files and
  picks the right asm flavour automatically.
- **`src/detect.cyr` joins `[lib] modules`** so consumers
  pulling `dist/vyakarana.cyr` via `cyrius deps` get the
  three detection entries alongside `tokenize_source` and
  `lsp_kind_*`. ADR 0001's "frozen public contracts" set
  grows by three names; documented in the consumer guide.

### Wiring

- `src/detect.cyr` — new module (≈220 lines).
- `src/main.cyr` — removed inline `detect_language` (≈120
  lines), replaced with `detect_language_combined` call;
  `tokenize_file` → `tokenize_buf`.
- `cyrius.cyml [lib] modules` — added `src/detect.cyr` after
  `src/tokenize.cyr`, before `src/lsp.cyr`.
- `tests/vyakarana.tcyr` — 25 new probes (path, content
  shebang for 6 interps, signature for 5 patterns, BOM strip,
  combined dispatch including asm flavour). 682 → 707
  passing.
- `scripts/smoke.sh` — 4 new content-detect probes
  (auto-detect both asm corpora with zero error tokens,
  shebang-routed python file with `def` keyword check, `<?xml`
  signature on extensionless file).

## [1.11.1] — 2026-05-08

Second sub-cut of the 1.11.x window. **Grammar composition**
(embedded-block routing through inner grammars), **theme
export** (emit external editor theme files from the bundled
themes), and a **self-contained dist bundle** (grammars
inlined as Cyrius string literals so downstream `cyrius deps`
consumers no longer need to vendor `grammars/`). Two new ADRs
(0013, 0014) and one new public CLI flag.

### Fixed

- **`dist/vyakarana.cyr` is now actually self-contained
  ([ADR 0014](docs/adr/0014-embedded-grammar-blobs.md)).**
  Through 1.11.0 the bundle's `bootstrap_grammars()` called
  `file_read_all("grammars/<name>.cyml")` 38 times — but
  `cyrius deps` only vendors the bundle file, not the
  `grammars/` dir. A consumer following the documented
  integration path got a tokenizer that loaded zero
  grammars and silently returned empty tokenbufs from
  `tokenize_source`. Fixed by inlining each grammar as a
  Cyrius string literal.
  - New `scripts/embed-grammars.sh` — reads every
    `grammars/*.cyml`, escapes content, writes
    `src/grammar_blobs.cyr` (gitignored). Run before
    `cyrius build` / `cyrius distlib`.
  - New module `src/grammar_blobs.cyr` (generated; in
    `[lib] modules` of `cyrius.cyml` so `cyrius distlib`
    pulls it into the bundle).
  - `grammar_load(path)` consults the blob registry first;
    falls back to `file_read_all` for the grammar-author
    dev workflow (`vyk path/to/foo.cyml`).
  - New smoke probe runs `vyk` from a temp dir with no
    `grammars/` reachable: 38 languages list, shell corpus
    tokenizes to 1560 NDJSON lines. Locks the
    self-contained guarantee against future regression.
  - **Bundle size grew from 82KB to 253KB.** Acceptable
    cost for a working integration path; the alternative
    (downstream consumers maintain a `grammars/` mirror)
    leaks vyakarana internals into every consumer's tree.

### Added

- **`match = "compose"` rule type ([ADR 0013](docs/adr/0013-grammar-composition-rule.md)).**
  Routes the body bytes between `start` and `end` markers
  through a *different* grammar named in the new `inner`
  field. New `Grammar` field `compose_rules` at offset 160
  (`GRAMMAR_SIZE` 160 → 168). New scanner step **0** in
  `tokenize_with_grammar` — runs before every other step
  because outer-grammar tokenization would eat the start
  markers byte-by-byte. New helper `_ds_try_compose_rules`
  in `src/grammars/default_scanner.cyr`. Markers emit as
  `TK_PUNCTUATION`; body tokens are recursively produced via
  the inner grammar with offsets shifted into the outer
  source's coordinate system. Graceful degradation when the
  inner grammar isn't loaded — body becomes one
  `TK_STRING`.
- **HTML grammar uses compose rules** for `<style>` → `css`
  and `<script>` → `javascript`. Closes the 1.7.0 "embedded
  blocks tokenize as plain HTML" gap. Verified: `#FF6600`
  inside a `<style>` block now tokenizes as a single
  `TK_IDENT` (CSS grammar's `#`-in-`ident_start` shape) and
  `const` / `function` / `return` inside `<script>` tokenize
  as `TK_KEYWORD` (JS grammar). Literal-prefix start match
  doesn't cover attribute-bearing forms like
  `<style type="module">`; documented limitation with a
  "when to revisit" note in the ADR.
- **`vyk --export-theme=<format>` flag.** Emits a theme file
  for the named editor format and exits. **`vscode`** is
  shipped (the most universal target — VS Code, Cursor,
  Codium, and other forks consume the same `theme.json`
  format). `helix` and `iterm` deferred until a real consumer
  asks. Pair with `--theme=<name>` to pick the source palette
  (default: `default`). New module `src/theme_export.cyr`
  holds the kind → TextMate-scope mapping plus the canonical
  hex equivalents of the ANSI codes used by the bundled
  themes.

### Changed

- **`grammars/html.cyml`** — added two compose rules ahead of
  the existing pair / line / words entries. Token count for
  `tests/corpus/concept.html` shifts 249 → 243 because the
  `<style>` block previously tokenized as several HTML tokens
  and now wraps as compose markers + inner CSS tokens.
- **Architecture note 002** — pipeline-priority table extends
  with the new step 0; "Why this order is normative" gains a
  bullet for compose-before-everything-else.
- **`src/main.cyr` --help** updated with `--export-theme=`.

### Wiring

- `src/grammar.cyr` — `compose_rules` field, `compose_rule_*`
  accessors, CYML loader handles `match = "compose"` +
  `inner` field.
- `src/grammars/default_scanner.cyr` — `_ds_try_compose_rules`
  helper, step 0 in main loop.
- `src/theme_export.cyr` — new module, only wired through
  `src/main.cyr`'s `--export-theme=` flag (CLI-only; not in
  `[lib] modules`).
- `tests/vyakarana.tcyr` — 8 new compose probes
  (CSS body keyword detection, JS body keyword detection,
  marker tokens, coverage invariant). 674 → 682 passing.
- `scripts/smoke.sh` — 4 new theme-export probes
  (`--export-theme=vscode`, dark variant, unknown format
  rejection).

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
