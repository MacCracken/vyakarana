# vyakarana — Agent handoff

> **Read this file before doing anything.** It's the landing pad from
> M0 (scaffold) to M1 (first working grammar). Design context lives
> in [vyakarana-design-spec.md](./vyakarana-design-spec.md);
> milestone detail lives in [ROADMAP.md](./ROADMAP.md). This file is
> the pointer that says where to start.

---

## Where we are

- **Version:** 0.1.0 (M0 shipped 2026-04-23)
- **Status:** scaffold complete, types locked, tokenizer stubbed,
  no grammars loaded
- **Consumer pressure:** owl's M3b (token highlighting) is blocked on
  this repo's M1. Other consumers (cyim, vidya, agnoshi) pick up
  after that in their own timelines.

CI is green: `cyrius build`, `cyrius test`, and `sh scripts/smoke.sh`
all pass against the stub.

---

## What is frozen (do not break)

1. **Ten token kinds in `src/token.cyr`.** The palette is a stable
   contract. Adding a new kind requires a design review and a
   CHANGELOG entry. Assume it's not your call in M1–M6.
2. **Token layout.** `(kind: u8, start: u32, len: u32)` — 12 bytes,
   no pointers. If you discover M1 needs more fields, add a
   CHANGELOG `### Changed` note and bump 0.1.0 → 0.2.0.
3. **Entry-point signature.** `tokenize_source(src, lang)` is what
   owl imports. The return type can evolve (Vec now, iterator in M5),
   but the name and arg order do not change.
4. **`vyk` CLI surface.** `--version`, `--help`, `--list-kinds`,
   `--list-languages` are covered by the smoke test. Additions are
   fine; renames/removals are breaking.

If you think you need to break any of these, **write a memo in
`DECISIONS.md` (create it if absent) explaining the forcing
function, and don't break the contract until the user ACKs.**

---

## M1 — what "done" looks like

**Goal:** shell files tokenize end-to-end, proving the runtime.

### Concrete checklist

- [ ] Hand-code a shell tokenizer in `src/grammars/shell.cyr`.
      (The file already exists as a skeleton — see §Landing-pad files.)
- [ ] Wire `tokenize_source(src, "shell")` in `src/tokenize.cyr` to
      dispatch to it. (The `if streq(lang, "shell")` branch is
      already stubbed.)
- [ ] `vyk <shell-file>` prints NDJSON tokens, one per line:
      `{"kind":"keyword","start":0,"len":2}`
- [ ] Coverage invariant holds: concatenating every token's
      underlying bytes reproduces the input exactly (no gaps, no
      duplication).
- [ ] `vidya/content/lexing_and_parsing/shell.sh` tokenizes with
      **zero `error` kinds** and passes the coverage check.
- [ ] Hand-audit ~30 tokens from the vidya sample: keywords
      (`if`, `then`, `while`, `case`, `esac`, ...) are `keyword`,
      `#` lines are `comment`, quoted strings are `string`, `$((`
      expansion contents are tokenized, `[[`/`]]` are
      `punctuation`, etc.
- [ ] Add `tests/corpus/shell.sh` (snapshot of the vidya file — see
      §Corpus below for the sync policy decision).
- [ ] Add at least 10 assertions to `tests/vyakarana.tcyr` that
      lock M1 behavior — `tokenize_source("if true; then ...", "shell")`
      produces known tokens at known offsets.
- [ ] `scripts/smoke.sh` grows an M1 section that runs `vyk` on the
      corpus file and checks exit code 0.

### Exit criteria

- `cyrius build` green
- `cyrius test` green (with M1 assertions added)
- `sh scripts/smoke.sh` green (with M1 section added)
- `vyk tests/corpus/shell.sh` produces NDJSON with zero `"kind":"error"`
  lines
- owl can add `[deps.vyakarana]` at the new tag and its M3b work can
  resume against a real grammar

### Explicit M1 non-goals

- **Do not start on CYML grammar loader.** That's M2. M1 is
  hand-coded Cyrius so we can iterate on rule shapes without also
  designing the serialization format.
- **Do not add a second grammar.** One grammar end-to-end beats two
  grammars half-done. Python / Rust / etc. land in M3 after M2
  proves the loader.
- **Do not implement regex.** Regex rules are explicitly out of the
  M2 rule set (see design-spec §5). If a shell construct seems to
  need lookahead, write a dedicated rule helper — don't reach for
  regex.
- **Do not break the zero-copy invariant.** Tokens reference into
  the caller's buffer. If you find yourself allocating per token,
  stop and reconsider.

---

## Landing-pad files

These exist in the repo as skeletons with `TODO(M1)` markers:

### `src/grammars/shell.cyr`
Skeleton with function signatures and commented-out recognizer shape.
Your job is to fill it in. The shape to aim for:

```cyrius
fn tokenize_shell(src, tokens_out) {
    # walk src, push Token records into tokens_out, return count
}
```

Recognizers you'll need (in rough priority order):
1. `#` → `comment` to end of line (but not `#!` on line 0 — that's
   `preprocessor` per design-spec §3)
2. `"..."` / `'...'` → `string` (respect backslash escapes in `"..."`
   only)
3. `$(...)` / `` `...` `` / `$((...))` → recurse or treat as string+
   internal; your call — document it in the shell grammar header
4. Identifiers `[A-Za-z_][A-Za-z0-9_]*` — then keyword lookup
5. Keyword set: `if then else elif fi for while until do done case
   esac function return break continue in select time`
6. Numbers: decimal, `0x`, `0b`, `0o` (rare in shell, but don't miss)
7. Operators: `=`, `==`, `!=`, `&&`, `||`, `|`, `&`, `>`, `>>`, `<`,
   `<<`, `<<-`, `<>`
8. Punctuation: `(`, `)`, `{`, `}`, `[`, `]`, `[[`, `]]`, `;`, `;;`,
   `:`
9. Whitespace (space, tab, newline) — emit as `whitespace` to keep
   the coverage invariant

### `src/tokenize.cyr`
Already has a commented-out `if streq(lang, "shell")` dispatch
branch. Uncomment and wire it after you implement `tokenize_shell`.

### `tests/corpus/`
Empty directory with a README explaining the corpus policy (see
§Corpus).

### `tests/vyakarana.tcyr`
M0 tests pass. Add M1 tests in a new `test_group("M1 shell grammar")`
block. Don't rewrite the M0 tests.

---

## Corpus — pending decision

vidya's `content/lexing_and_parsing/shell.sh` is the source of truth
for test corpus. Four options for how vyakarana consumes it; **pick
one at M1 start and document the choice in `DECISIONS.md`**:

1. **Checked-in snapshot.** Copy the file into `tests/corpus/shell.sh`
   at M1 time. Simple; drifts from vidya unless periodically synced.
2. **Git submodule.** `tests/corpus/` as a vidya submodule. Heavy for
   a test fixture; ties CI to a submodule init step.
3. **Build-time pull.** `scripts/pull-corpus.sh` fetches from vidya
   at CI time. Flexible; network-dependent.
4. **Path reference (monorepo assumption).** Tests resolve
   `../vidya/content/lexing_and_parsing/shell.sh` if it exists. Works
   locally, breaks in standalone CI.

**Recommended:** option (1), checked-in snapshot, for M1. Switch to
(3) at M3 when there are 10 files to keep in sync. Don't over-engineer
sync infrastructure for one file.

---

## After M1 — quick forward look

- **M2** — CYML grammar loader. Re-express shell as data; ship the
  format that all future grammars use. See design-spec §5 for the
  rule-type set.
- **M3** — Nine more grammars (python, js, ts, rust, c, cyrius, toml,
  json, yaml, markdown). Each gets a vidya sample as test corpus.
- **M4** — Theme-palette contract with owl. Coordinate with whoever
  owns owl's theme module; shared palette header file is the likely
  shape.
- **M5** — Streaming tokenizer (iterator API). Memory goes O(tokens
  in flight). This is owl's `huge.log` enabler.
- **M6** — vidya reverse consumption (rendering).
- **M7** — RC / v1.0 cut.

Each milestone has its own ROADMAP section with concrete "done when"
criteria. Read it before starting the milestone.

---

## Cross-repo coordination

- **owl** (`/home/macro/Repos/owl`) — its M3b is blocked on M1. When
  M1 ships, ping the owl agent to add `[deps.vyakarana]` at the new
  tag. Do **not** sidestep with a path hack — see
  `feedback_real_deps_only.md` in the genesis memory.
- **vidya** (`/home/macro/Repos/vidya`) — read before making corpus
  decisions. M6 will bring vidya on as a consumer; don't pre-negotiate
  that now.
- **cyrius** (`/home/macro/Repos/cyrius`) — toolchain. Currently
  v5.6.x (see `/home/macro/Repos/cyrius/VERSION`). If you find a
  compiler bug, file it upstream; don't work around it in vyakarana.

---

## Process reminders

- **Do not commit or push.** The user handles all git operations.
- Use `cyrius build`, never raw `cc5`.
- Study `cyrius/programs/*.cyr` and `cyrius-doom/` for working Cyrius
  examples before writing new code.
- Read `vidya/content/cyrius/field_notes.toml` before writing non-trivial
  Cyrius.
- Test after every change. One change at a time.
- If you hit three failed attempts at the same problem, stop, write
  a note in `DECISIONS.md`, and defer.

---

*Handoff written 2026-04-23. Update this file when M1 completes.*
