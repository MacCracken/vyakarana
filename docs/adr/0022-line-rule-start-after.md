# 0022 — `start_after`: a line rule that only opens at a word boundary

- **Status:** Accepted
- **Date:** 2026-10-20
- **Deciders:** 2.6.0 shell-correctness work (proposed) / user (accepted
  via the pinned 2.6.0 roadmap entry)
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md) (rule types),
  [ADR 0017](0017-streaming-api.md) (streaming), `src/grammar.cyr`,
  `src/grammars/default_scanner.cyr`, `src/tokenize.cyr`,
  `src/grammars/shell.cyr`, `grammars/shell.cyml`,
  `tests/corpus/shell.sh` line 49,
  [2.5.2 audit](../audit/2026-10-20-2.5.x-closeout-audit.md) §Scheduled

## Context

A `line` rule fires wherever its start marker appears. That is right
for most comment syntaxes — `//`, `--`, `;`, and `#` in python, ruby,
toml — but not for shell. In bash a `#` begins a comment only when it
begins a word: at the start of input or right after a metacharacter
(space, tab, newline, `;` `&` `|` `(` `)` `<` `>`). Everywhere else it
is ordinary text: `${#arr[@]}` (length), `${x#p}` / `${x##*/}`
(prefix strip), `a#b`.

Through 2.5.2 shell's `#` rule fired on every `#`, so each of those
swallowed the rest of its line as a comment. The bundled corpus — a
vidya snapshot — has one (`len=${#input}`, line 49); the gates passed
because the coverage invariant holds either way and the hand-coded
oracle made the identical mistake.

`special_vars` already rescued `$#`, but only because `$#` is two bytes
the scanner reaches at the `$`. `${#` puts a `{` in between, and no
existing rule type can say "this marker counts only after these bytes".

## Decision

Add an optional `start_after` key to `match = "line"` rules: a string
of bytes. When present, the rule's start marker matches only at the
start of input or when the byte immediately before it is one of those
bytes. When absent, behaviour is unchanged. Shell uses
`start_after = " \t\n\r;&|()<>"` (bash's metacharacters plus CR), and
adds `#` to its operators so a declined `#` is a 1-byte operator, not
`TK_ERROR`.

**Streaming.** The decision reads the byte BEFORE the cursor. Inside a
buffer that is `src[i-1]`; at `i == 0` of a mid-stream buffer that
byte was committed and compacted away. The drain therefore records the
last byte it removes from the buffer (stream record `+96`, both
compaction sites) and hands it to the scanner as a one-shot
(`_ds_buf_prev`), as 2.5.2's `_ds_not_file_start` does for shebangs.
Compose bodies tokenized recursively see `-1` — their own start.

**Scope.** Line rules only; `_gp_close_rule` rejects `start_after` on
any other match type and rejects an empty value. Only shell uses it in
2.6.0. The hand-coded oracle (`src/grammars/shell.cyr`) implements the
same boundary so the smoke M1/M2 byte-identical check keeps holding.

## Consequences

### Positive

- `tests/corpus/shell.sh`: `len=${#input}` is `$` `{` `#` `input` `}`
  instead of `$` `{` + a 7-byte comment. A synthetic shapes file
  (`${#v}`, `${p##*/}`, `${y#pre}`, `a#b`, `;#c`, `(# c`, ` #c`) is
  correct and identical through M1 and M2.
- Chunk-invariant: the every-offset two-feed split is clean on the
  shapes file, `tests/corpus/shell.sh` and vidya's
  `module_systems/shell.sh`. With the drain's byte record disabled the
  same split fails at 7 offsets — the mechanism is load-bearing, and
  `fuzz/chunk_invariance.fcyr` now covers it.

### Negative

- Shell token boundaries change wherever a mid-word `#` appears — a
  minor-release change (2.6.0).
- The stream record grows 8 bytes; one more one-shot global between
  the drain and the scanner.

### When to revisit

- Another grammar whose comment marker is word-scoped (Dockerfile's
  `#` is a comment only at line start: `start_after = "\n"` would
  express it) — adopt per grammar, no scanner change needed.
- If a pair rule ever needs the same condition, extend the key to pair
  rules rather than adding a second mechanism.
