# ADR 0013 — Grammar composition rule

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** 1.11.1 grammar-composition work / user (accepted)
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md)
  (rule-type scope), [architecture note 002](../architecture/002-scanner-pipeline-priority.md)
  (scanner pipeline), [architecture note 003](../architecture/003-pair-rule-ordering.md)
  (pair-rule ordering), `src/grammar.cyr`,
  `src/grammars/default_scanner.cyr`, `grammars/html.cyml`.

## Context

Real-world source files routinely embed one language inside
another. The most common case is HTML, where `<style>...</style>`
contains CSS and `<script>...</script>` contains JavaScript.
Markdown does the same with fenced code blocks
(`` ```rust\n…\n``` ``). Vue / Svelte / JSX have similar
patterns.

Through 1.11.0, vyakarana tokenized embedded blocks **using
the outer grammar's rules**. So the body of a `<style>` block
in HTML went through HTML's tokenizer — yielding plain HTML
tokens for what the reader thinks of as CSS. Coverage held
(every byte produced a token), but the semantic distinctions
were lost: a CSS keyword like `@media` inside a `<style>` block
showed up as `@` op + `media` ident under HTML's surface, not
as a `TK_KEYWORD` under CSS's surface.

The 1.7.0 HTML grammar header documented this as a deferred
issue:

> Embedded `<style>` and `<script>` blocks tokenize as plain
> HTML at this layer. **Grammar composition** for routing
> inner content through CSS / JS grammars is on the **1.11.0**
> roadmap.

The roadmap split 1.11 into three sub-cuts; composition lands
in 1.11.1.

## Decision

**Add a new `match = "compose"` rule type with `start`, `end`,
and `inner` fields.** When the scanner matches a compose rule
at the cursor, it:

1. Emits the `start` bytes as one `TK_PUNCTUATION` token.
2. Locates the `end` marker (greedy, first match).
3. Tokenizes the body bytes (between start and end) by
   recursively calling `tokenize_with_grammar` with the
   grammar named in `inner`.
4. Pushes the inner tokens to the outer tokenbuf, **shifting
   each token's `start` offset by the body's start position
   in the outer source.**
5. Emits the `end` bytes as one `TK_PUNCTUATION` token.
6. Returns the total bytes consumed; the outer main loop
   advances by that amount and continues.

Pipeline placement: **step 0**, before every other step. The
outer scanner would otherwise eat the start marker
byte-by-byte (`<style>` becoming `<` op + `style` ident +
`>` op) before any pair / line / words rule could see it. See
[architecture note 002](../architecture/002-scanner-pipeline-priority.md)
"Why this order is normative" — the same reasoning applies.

CYML syntax:

```toml
[[rules]]
match = "compose"
start = "<style>"
end   = "</style>"
inner = "css"
```

Bundled use (1.11.1):

- `grammars/html.cyml` — `<style>` → css, `<script>` → javascript.

### Graceful degradation

If `inner` names a grammar that isn't loaded (e.g. consumer
hasn't called `bootstrap_grammars`, or the named grammar was
removed), the body falls back to a single `TK_STRING` span
covering the whole body. Coverage holds; downstream renderers
that wanted the inner-grammar shape see a string instead and
can decide what to do. **Never falls to `TK_ERROR`** — the
compose rule is opt-in and missing inner grammars shouldn't
break the outer tokenization.

### Recursion

`tokenize_with_grammar` is the recursion target, and step 0
of `tokenize_with_grammar` is the compose check. So embedded
grammars that themselves have compose rules nest correctly.
Real-world recursion depth ≤ 2 (HTML → CSS, HTML → JS;
JS-template-literal-containing-HTML is theoretically possible
but the JS grammar doesn't have compose rules today). No
explicit depth cap — Cyrius's stack handles it.

## Consequences

### Positive

- **CSS / JS bodies in HTML now tokenize with their native
  grammars.** A `@media` query inside `<style>` shows up as
  CSS's `TK_KEYWORD`, not HTML's `@` op + ident. Same for
  `function` / `const` / `return` inside `<script>`.
- **One scanner-level change covers every embedded-grammar
  case.** Rule type, not consumer-side post-processing.
  Future grammars (markdown, Vue, JSX) add `[[rules]] match
  = "compose"` entries and inherit the behaviour.
- **The pair-rule machinery wasn't disturbed.** Pair rules
  still run at step 3 unchanged. Compose is its own step,
  its own rule type, its own vec on the Grammar record.
- **Inner-grammar lookup happens at scan time, not load
  time.** No grammar-load-order dependencies; if `css` and
  `html` are both registered, composition works regardless
  of which loaded first.

### Negative

- **Recursive tokenize_with_grammar allocates a fresh
  tokenbuf per compose match,** then copies tokens out with
  shifted offsets. Two allocations per compose-rule firing
  (the temp tokenbuf, plus the doubling growth on the outer
  tokenbuf). For a typical HTML page with one `<style>` and
  one `<script>` block that's negligible. For a markdown
  file with hundreds of fenced code blocks (when 1.11.x adds
  fence routing, see "When to revisit"), a future
  optimisation would tokenize directly into the outer
  tokenbuf with an offset parameter. Not yet warranted.
- **Start markers are matched literally.** `<style>` matches
  the literal string; `<style type="module">` doesn't, so its
  body falls back to outer-grammar HTML tokenization. Common
  in real HTML; documented as a limitation in
  `grammars/html.cyml`'s header. A future extension could
  match a fixed prefix and tolerate trailing attributes —
  that needs its own ADR.
- **Start / end markers tokenize as `TK_PUNCTUATION` regardless
  of their content.** `<style>` literally is `<` + tag + `>`
  in HTML, but the compose rule emits it as a single
  `TK_PUNCTUATION` of length 7. Themes that want the multi-
  token shape can post-process by token text. The
  alternative (running outer tokenization on the markers and
  THEN switching grammars) is messier and was deliberately
  rejected.
- **Grammar-record ABI bumped** from 160 to 168 bytes (new
  `compose_rules` slot at offset 160). Same private-ABI
  pattern as ADRs 0009 / 0010 / 0011; no consumer reads the
  in-memory `Grammar` directly.

### When to revisit

- **Markdown fence routing.** The static `inner = "css"`
  shape doesn't fit the dynamic markdown case where the
  inner grammar is determined by the fence info string
  (`` ```rust `` vs `` ```python ``). A future
  extension — likely `inner = "@fence"` or a special
  match-type `match = "compose-dynamic"` — should land as
  its own ADR. Until then, fenced code blocks tokenize as
  plain markdown content.
- **Attribute-bearing HTML tags.** `<style type="module">`
  bypasses the literal-prefix match. Future ADR could allow
  `start = "<style"` (no closing `>`) with an "anything
  through `>`" zone. Tracked for a 1.11.x or 1.12.x cut.
- **Shifted-offset writes.** If allocating one inner tokenbuf
  per compose match becomes a hot path (markdown with
  hundreds of fences), introduce
  `tokenize_with_grammar_offset(g, src, src_len, tb,
  offset)` that pushes tokens directly to `tb` with `start +
  offset`. Pure perf optimization; no behavioral change.
