# 0019 — `match = "compose_region"` rule type for open-ended regions

- **Status:** Accepted
- **Date:** 2026-07-31
- **Deciders:** RM (2.3.1 cut)
- **Relates to:** [ADR 0013](0013-grammar-composition-rule.md)
  (compose rules for HTML `<style>` / `<script>`),
  [ADR 0016](0016-compose-fenced-rule.md) (captured-tag fences),
  [ADR 0005](0005-m2-rule-type-scope.md) (rule-type scope),
  `src/grammar.cyr`, `src/grammars/default_scanner.cyr`,
  `grammars/cyml.cyml`, `tests/vyakarana.tcyr` 2.3.1 group

## Context

CYML is a TOML-shaped header followed by `---`-delimited markdown
bodies, repeating. It is the format vyakarana's own grammar files
use, plus `yukti.cyml` and vidya's content corpus:

```
[[entries]]
name = "x"
---
Free-form markdown, with `inline code`, **bold**,
# headings, and fenced code blocks.
[[entries]]
name = "y"
---
…
```

The obvious move is ADR 0013's `match = "compose"`, routing body
bytes to the markdown grammar. It cannot express this shape, for
two independent reasons — both verified against the 6.5.4 scanner
rather than inferred:

1. **`compose` consumes its `end` marker.** A CYML body has no
   closing delimiter. It ends where the *next* header begins, and
   those bytes belong to that header — `[[entries]]` must tokenize
   as TOML punctuation + ident + punctuation, not be eaten as a
   terminator.
2. **`compose` treats a missing end marker as failure.** When the
   marker is absent it emits nothing and falls through to the
   outer grammar (confirmed: an unterminated `<style>` tokenizes
   as plain HTML). Every CYML file's final body runs to EOF, so
   under `compose` the last body — often the largest — would never
   be routed at all.

What shipped instead, from 1.9.0 through 2.3.0, was a single rule
set tuned for the union of TOML and markdown. `grammars/cyml.cyml`
documented this as a stopgap and named composition as the real
fix; composition arrived in 1.11.0 and cyml was never migrated.
The union set mis-typed exactly what a body is for:

- A body's `# Heading` matched the TOML `#` line-comment rule and
  came back as one TK_COMMENT spanning the whole line.
- A ```` ``` ```` fence met the backtick pair rule: the first two
  backticks closed an empty inline-code span and the third opened
  one that swallowed the entire code block into a single
  TK_STRING, info string and all.

The bundled corpus, `tests/corpus/dependencies.cyml`, contains
neither a body heading nor a fence, so every gate stayed green for
twelve minor releases. That is the same corpus blindness that hid
the `cyml` stdlib-dependency break repaired in 2.3.0.

## Decision

**Add a rule type `match = "compose_region"` that routes an
open-ended region through a named inner grammar, terminating at an
unconsumed lookahead marker or at EOF.**

```
[[rules]]
match = "compose_region"
start = "---"
end_before = "\n["
inner = "markdown"
```

Semantics, and how each differs from `compose`:

- `start` — literal opening marker, emitted as TK_PUNCTUATION.
  Same as `compose`.
- `end_before` — a **lookahead** terminator. The region ends
  immediately before it and the marker bytes are left at the
  cursor for the outer grammar. No end token is emitted, because
  the terminator was never the region's to consume. An empty or
  absent `end_before` means "always run to EOF".
- `inner` — grammar name, resolved through the registry exactly as
  `compose` does, with the same graceful degrade to a single
  TK_STRING when the grammar is missing.
- Reaching EOF without seeing the terminator is a **normal
  ending**, not a failure.

It runs at scanner step 0c, after `compose` and `compose_fenced`,
ahead of every other step. Ordering matters: the `#` line rule
sits at step 2, so a body heading only survives as markdown
because the region claimed those bytes first.

Bodies route to the markdown grammar, which means fences inside a
body reach ADR 0016's `compose_fenced` and route on to the tagged
grammar. A ```` ```cyrius ```` block inside a CYML body now yields
real `fn` / `return` keywords, two composition levels deep.

## Consequences

**`---` in a CYML file changes kind.** It was TK_OPERATOR through
2.3.0; it is now TK_PUNCTUATION, matching the kind `compose` gives
`<style>`. This is the visible token-output change of the 2.3.1
cut. No token kind was added and the `Token` layout is untouched.

**`GRAMMAR_SIZE` grows 176 → 184 bytes** for the new
`compose_region_rules` vec. Internal to `src/grammar.cyr`; not
part of any published contract.

**`end_before` shares slot 24 with `end`** in the staging rule
record. A rule declares one or the other and `mt` disambiguates,
the same overlay trick `inner` already uses with `words` at slot
40. Cheap, and consistent with what is there.

**A body line beginning with `[` ends the region early.**
`end_before` is a literal `\n[`, not a line-anchored TOML-header
match, so a markdown link-reference definition (`[1]: https://…`)
at column 0 hands the rest of the body back to the header rules.
Indented or inline `[` is unaffected. This is the same class of
documented literal-prefix limit as `<script>` vs
`<script type="module">` in ADR 0013 §When to revisit.

## Alternatives considered

**Extend `compose` with an optional non-consuming mode.** Rejected:
`compose`'s contract is a matched delimiter pair that both get
emitted, and ADR 0013's HTML/Vue/Svelte users depend on the end
marker being consumed. Overloading it with a flag that silently
changes whether a token is emitted would make the existing rules
harder to read for no gain.

**`end = "\n[["` on a plain `compose` rule.** Rejected: it mangles
the header it stops at — the `\n[[` is consumed, so `entries]]`
follows with no opening bracket — and it still leaves the final
EOF-terminated body unrouted.

**Leave the union rule set and document the gap.** Rejected. The
gap is not cosmetic: on real vidya content a fenced code block is
flattened into one string token, and rendering those code samples
is precisely what the downstream consumer exists to do.

## When to revisit

- If a real corpus surfaces a markdown link-reference definition
  at column 0 inside a CYML body, `end_before` needs to become
  line-anchored, or gain a "must be followed by a TOML header
  shape" predicate.
- If a second format wants the same open-ended routing but with a
  terminator that is a *class* of bytes rather than a literal, the
  rule type should grow a char-class terminator rather than
  another bespoke rule type.
