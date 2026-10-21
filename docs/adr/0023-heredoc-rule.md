# 0023 — `heredoc` rule type for here-documents

- **Status:** Accepted
- **Date:** 2026-10-20
- **Deciders:** 2.6.0 shell-correctness work (proposed) / user (accepted
  via the pinned 2.6.0 roadmap entry)
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md) (rule types),
  [ADR 0019](0019-compose-region-rule.md) (the last new rule type),
  [ADR 0017](0017-streaming-api.md) / [0021](0021-token-span-width-ceiling.md)
  (streaming), [ADR 0022](0022-line-rule-start-after.md),
  `src/grammars/default_scanner.cyr`, `src/tokenize.cyr`,
  `grammars/shell.cyml`, `tests/corpus/shell_modules.sh`

## Context

A here-document's body is the lines after `cmd <<WORD` up to a line
that is exactly `WORD`. Through 2.5.2 no rule type could express it,
so bodies were tokenized as shell code: comment lines became comments,
an apostrophe in prose (`it's`) opened a string that ran to the next
`'` or to EOF, and everything after was mis-lexed. vidya ships seven
shell samples with heredocs (102 openers across the 234 shell files
the 2.5.2 real-file sweep saw); `module_systems/shell.sh` has five and
is now a corpus file.

It is the first construct whose meaning is **non-local twice over**:
the body begins on the line *after* its opener (the rest of the opener
line is ordinary code — `cat <<EOF > out`, `cmd <<A <<B`), and whether
`<<` opens anything at all depends on a terminator line that may be far
ahead — `$(( a << b ))` is a shift and has none. No existing rule type
looks ahead past the current token or carries state to the next line.

## Decision

Add `match = "heredoc"` (rule type 7): `kind`, `start` (`<<`), and an
optional one-byte `indent` marker (`-`) that lets the terminator line
be indented by tabs (`<<-`).

**Opener.** At `start`, not followed by the start's last byte (`<<<`
is a here-string), and not inside an arithmetic `((`…`))` opened
earlier on the same line: skip the indent marker and blanks, an
optional `\`, then a delimiter — `'WORD'`, `"WORD"`, or a bare word
that must begin with a letter or `_` (`1 << 2` is a shift). The opener
**consumes nothing**: `<<` is still the operator step's token and the
delimiter its own, so opener lines tokenize exactly as before. If a
terminator line exists, the heredoc is queued (four per line at most).

**Body.** At the first top-level line break after the opener(s), each
queued body plus its terminator line is ONE `kind` token, in order; a
whitespace token covers the line break between consecutive bodies. A
terminator matches exactly, after leading tabs for `<<-`, ignoring one
trailing CR.

**No terminator, no heredoc.** An opener whose terminator never
appears is not a heredoc — the bytes stay code. Bash would read to EOF
with a warning; for a tokenizer, demanding the terminator is what makes
a false positive (an arithmetic shift with an identifier operand)
harmless.

**Streaming.** The drain cannot commit past an opener it cannot resolve
yet: once the `<<` commits, the next drain re-scans the body with no
memory of it. The scanner reports the lowest unresolved opener (no
terminator yet, a terminator without its line break yet, or a delimiter
cut off by the buffer end); the drain commits nothing from there —
holding a line's openers as a unit, since their bodies are sequential —
until the terminator line is complete, finish, or `VYK_HEREDOC_HOLD_MAX`
(1 MiB) is exceeded. While held for a known delimiter, later drains
search only the NEW lines for the terminator instead of re-tokenizing
the held buffer (a 900 KB heredoc fed in 4 KB chunks: 48 s → 0.02 s).

**Bounded work.** Terminator searches share a per-call budget of 4×
the input plus 64 KiB, and a failed search is cached per delimiter.
Real files spend a fraction of it; N distinct unterminated openers
would otherwise be O(N²) — past the budget they are code.

**Scope.** Shell only in 2.6.0. The hand-coded oracle does not
implement it (its identity check covers `tests/corpus/shell.sh`, which
has no heredocs) — the same standing as the backtick rule.

## Consequences

### Positive

- `tests/corpus/shell_modules.sh` (vidya): all five bodies are strings;
  `# math_lib.sh` at offset 1214 is no longer a comment (smoke asserts
  it). Every-offset two-feed splits clean on all seven vidya heredoc
  samples, on two opener-per-line shapes and on
  `fuzz/chunk_invariance.fcyr`'s cases — which fail 75 times with the
  drain's hold disabled.
- Streaming of plain or arithmetic-heavy shell is unaffected (0.39 s
  per MB in 4 KB chunks either way).

### Negative

- Shell token boundaries change inside every heredoc — a minor release.
- The scanner now carries per-line state (the queue) and a lookahead
  per opener; the drain gains a hold and a watch. Most of the 2.6.0
  streaming complexity lives here.
- A heredoc body over 1 MiB split across feeds may tokenize as code
  where a single feed sees a heredoc (documented hold bound, like
  compose's).

### When to revisit

- Ruby (`<<~EOS`, `<<-EOS`), PHP (`<<<EOT`, nowdoc), Perl, Crystal —
  same shape with different start markers and indentation rules; extend
  the rule's options (indentation by spaces, a terminator followed by
  more code) rather than adding a second mechanism.
- The 2.8.0 streaming-engine rework, which may subsume the hold and
  watch.
