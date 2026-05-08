# 0016 — `match = "compose_fenced"` rule type for markdown fences

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** RM (1.13.2 cut)
- **Relates to:** [ADR 0013](0013-grammar-composition-rule.md)
  (compose rules for HTML `<style>` / `<script>`),
  `src/grammar.cyr`, `src/grammars/default_scanner.cyr`,
  `grammars/markdown.cyml`, `tests/vyakarana.tcyr` 1.13.2
  group

## Context

ADR 0013's `match = "compose"` rule type routes the body bytes
between two **literal** start / end markers through a different
grammar named at grammar-definition time. That works for HTML
(`<style>` always means CSS, `<script>` always means JavaScript)
but doesn't fit Markdown's fenced code blocks:

````
```rust
fn add(x: i64) -> i64 { x + 1 }
```
````

The triple-backtick start marker is the same for every language —
the language tag (`rust`, `python`, `bash`, `c`, …) is captured
from the bytes between the start marker and the next newline (the
"info string" in CommonMark terms). A literal-prefix match can't
bind that capture.

Through 1.13.1 the markdown grammar handled fences with a regular
`match = "pair"` rule that matched everything between two ``` ` ` `
markers as one TK_STRING. That preserved the coverage invariant
but ignored the inner language entirely. Stand-in for the real
behaviour, deferred from ADR 0013's "When to revisit".

## Decision

**Add a new rule type `match = "compose_fenced"` that captures
the language tag from the input bytes between `start` and the
next LF, and routes the body through the grammar named by that
tag.**

Layout of a recognized fence:

```
<start><tag><info-tail>\n<body>\n<end>
```

- `<start>` — literal, e.g. `` ``` ``. Matched at the cursor.
- `<tag>` — `[A-Za-z0-9_+-]+`. The first run of tag-bytes
  immediately after `<start>`. Empty tag is allowed (falls
  through to graceful-degradation; see below).
- `<info-tail>` — bytes from end of `<tag>` to first LF. Ignored
  for grammar lookup. CommonMark allows arbitrary text here
  (e.g. `` ```rust title="add"`` `` for renderer hints).
- `<body>` — bytes routed through the grammar named by `<tag>`.
- `<end>` — literal, e.g. `` ``` ``. Matched at start-of-line
  (after an LF or at body_start).

Recognition pipeline: new step **0b** in
`tokenize_with_grammar`, immediately after step 0 (compose).
Same rationale as ADR 0013 — outer-grammar tokenization would
otherwise eat the `` ``` `` markers byte-by-byte (matching
inline ``` ` ` ``` pair rules first).

When recognized, emit:
1. `<start><tag><info-tail>\n` as one TK_PUNCTUATION token (the
   open-marker span).
2. Body tokens via the inner grammar, with offsets shifted into
   the outer coordinate system.
3. `<end>` as one TK_PUNCTUATION token.

Graceful degradation:
- **Empty tag** (` ```\n`) → body emits as one TK_STRING.
- **Unknown tag** (` ```bogus\n`) → body emits as one TK_STRING.
- **Unclosed fence** (no `<end>` before EOF) → step 0b returns 0
  and the rest of the cursor falls through to the regular pair /
  line / words pipeline. The outer grammar eats the bytes; the
  coverage invariant still holds.

CYML rule shape:

```toml
[[rules]]
match = "compose_fenced"
start = "```"
end = "```"
```

No `inner` field — the inner grammar is per-fence-instance,
captured from the input bytes.

`Grammar` record gets a new field `compose_fenced_rules` at
offset 168 (`GRAMMAR_SIZE` 168 → 176). New struct
`ComposeFencedRule` (16 bytes: start, end). Loader handles
`match = "compose_fenced"` → mt = 5 in `_gp_close_rule`.

## Consequences

### Positive

- **Markdown fences route correctly.** ``` ```rust ``` ``` body
  produces TK_KEYWORD for `fn` / `let` / etc. via the Rust
  grammar; ``` ```python ``` ``` produces TK_KEYWORD for `def`.
  Verified by 1.13.2 probes in `tests/vyakarana.tcyr`.
- **Liberal info-string acceptance.** `` ```c++ ``,
  `` ```python3 ``, `` ```rust title="add" `` all work — the
  tag scanner stops at the first non-tag byte, the info-tail
  is ignored.
- **Graceful degradation matches ADR 0013.** When the inner
  grammar isn't loaded or no tag is given, the body emits as
  one TK_STRING — same shape as compose's missing-grammar
  fallback. Coverage invariant holds in every case.
- **Backward-compatible at the CYML surface.** Existing
  `match = "compose"` rules keep working unchanged. Markdown
  switches from a pair rule to compose_fenced; no other grammar
  is affected.

### Negative

- **Two compose-shaped rule types now exist.** `compose` for
  fixed inner; `compose_fenced` for captured tag. They share a
  lot of structure (start / end / body / recursion / fallback)
  but the dispatch is per-rule-type. Future generalization
  could collapse them — e.g. a `compose` with optional
  `inner_capture = true`. Not worth doing today; two rules is
  fewer than the current count of pair / line / words.
- **Tag character class is closed.** `[A-Za-z0-9_+-]` covers
  every grammar name we ship today. CommonMark technically
  allows arbitrary tag bytes up to whitespace, so an exotic
  info-string like `c#` would only see `c` as the tag (since
  `#` isn't in the class) and `#` would land in the info-tail.
  Today's grammar set has no `#`-containing names — fine. If
  a future grammar wants `c#`, extend the class.
- **`compose_fenced` is markdown-driven for now.** The CYML
  rule type is general — any grammar can use it. But
  practically only `grammars/markdown.cyml` adopts it in 1.13.2.
  Other grammars with similar constructs (org-mode source
  blocks, AsciiDoc listing blocks, RST literal blocks) would
  add corresponding grammars + rules in the future.
- **Open-marker token includes the LF.** The TK_PUNCTUATION
  span for the open marker covers `<start><tag><info-tail>\n`.
  Slightly noisier than emitting the LF as TK_WHITESPACE
  separately, but simpler — the tokenizer doesn't have to
  re-discover where the tag ends and the info-tail starts.
  Theme renderers that care can re-pair by token kind +
  position.

### When to revisit

- **Tilde fences** (`~~~rust ... ~~~`). CommonMark also accepts
  `~~~` as the fence marker. Today only `` ``` `` works because
  the rule has a literal `start = "```"`. A second
  `compose_fenced` rule with `start = "~~~"` would handle it,
  at the cost of doubling the matcher. Defer until a real
  consumer asks (not in any vidya corpus today).
- **Variable-length fences** (`````` `` … `` ``````, four or
  more backticks for nesting). CommonMark allows fences of 3+
  backticks, with the close needing ≥ as many as the open.
  Out of scope; today's matcher uses the exact literal. A
  consumer with nested-backtick markdown (rare) would need this.
- **Indented code blocks.** Markdown also recognizes
  4-space-indented code as a code block. Different recognizer
  shape; no language tag; not in scope for this ADR.
- **Generalization with `compose`.** If we add a third
  capture-shaped variant (e.g. capture from balanced
  delimiters), revisit whether the three rule types should
  merge into one with a flag.
- **Markdown fences in non-markdown grammars.** AsciiDoc and
  org-mode have similar source-block constructs. If those
  grammars land in vyakarana, they'll add their own
  `compose_fenced` rules with different start/end markers.
