# ADR 0012 — LSP semantic-tokens bridge mapping

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** 1.11.0 LSP-bridge work / user (accepted)
- **Relates to:** [ADR 0004](0004-shell-builtins-as-ident.md)
  (built-ins-as-ident pattern), [architecture note 004](../architecture/004-theme-palette-contract.md)
  (theme-palette contract), `src/lsp.cyr`,
  the LSP 3.17 semantic-tokens spec.

## Context

vyakarana has 38 grammars covering most popular languages. But
modern editors increasingly source their colour information from
**Language Servers** rather than client-side tokenizers —
rust-analyzer, gopls, pyright, clangd, the TypeScript LSP, and
many others all ship `textDocument/semanticTokens` providers
that report a richer classification (function vs variable vs
parameter, declaration vs reference, etc.) than any pure
tokenizer can.

For a consumer like cyim that wants to use vyakarana as its
default classifier but **fall back to LSP output when one is
available** — or vice versa, prefer LSP when it's there and use
vyakarana as the offline classifier — the two outputs need to
land in the same palette. The 10 vyakarana token kinds
(`docs/architecture/004-theme-palette-contract.md`) are the
target; LSP's semantic-token taxonomy is the source.

LSP 3.17 defines **23 standard token types**:

```
namespace, type, class, enum, interface, struct,
typeParameter, parameter, variable, property, enumMember,
event, function, method, modifier, macro, decorator,
keyword, comment, string, regexp, number, operator
```

Plus servers can extend the legend with custom types beyond the
standard list. And **modifiers** (`declaration`, `definition`,
`readonly`, `static`, `deprecated`, `abstract`, `async`,
`modification`, `documentation`, `defaultLibrary`) decorate the
type but don't change the *kind* in the vyakarana sense.

## Decision

**Add a one-way mapping from LSP token-type names (and standard
indices) to vyakarana TK_* kinds**, exposed as two functions in
a new `src/lsp.cyr` module:

```cyrius
fn lsp_kind_from_token_type(name: cstr) -> i64    # name → TK_*
fn lsp_kind_from_standard_index(idx: i64) -> i64  # 0..22 → TK_*
```

Both return one of the 10 `TK_*` constants. Unknown / extended
names → `TK_IDENT` (the safe default, since LSP servers can ship
custom legends and we don't want to fall to error). The module
is added to `[lib] modules` so it ships in `dist/vyakarana.cyr`
and downstream consumers get it for free.

### The mapping

The interesting decisions, with a one-line rationale each:

| LSP type      | vyakarana kind     | Why                                                                 |
|---------------|--------------------|---------------------------------------------------------------------|
| keyword       | `TK_KEYWORD`       | Direct match.                                                       |
| comment       | `TK_COMMENT`       | Direct match.                                                       |
| string        | `TK_STRING`        | Direct match.                                                       |
| number        | `TK_NUMBER`        | Direct match.                                                       |
| operator      | `TK_OPERATOR`      | Direct match.                                                       |
| regexp        | `TK_STRING`        | vyakarana has no separate regex kind; theme can split on text.      |
| modifier      | `TK_KEYWORD`       | `pub`/`static`/`async` etc. are reserved storage-class words.       |
| macro         | `TK_PREPROCESSOR`  | Closest fit — macros are pre-compilation expansion.                 |
| decorator     | `TK_PREPROCESSOR`  | Annotations like `@override`, `@deprecated`. `@` already → preproc. |
| function      | `TK_IDENT`         | Function names are identifiers. Theme can colour by name pattern.   |
| method        | `TK_IDENT`         | Same as function.                                                   |
| variable      | `TK_IDENT`         | Same.                                                               |
| parameter     | `TK_IDENT`         | Same.                                                               |
| property      | `TK_IDENT`         | Same.                                                               |
| class         | `TK_IDENT`         | Type names are identifiers in vyakarana's palette.                  |
| interface     | `TK_IDENT`         | Same.                                                               |
| struct        | `TK_IDENT`         | Same.                                                               |
| enum          | `TK_IDENT`         | Same.                                                               |
| enumMember    | `TK_IDENT`         | Same.                                                               |
| event         | `TK_IDENT`         | Same.                                                               |
| typeParameter | `TK_IDENT`         | Same.                                                               |
| namespace     | `TK_IDENT`         | Same.                                                               |
| type          | `TK_IDENT`         | Same.                                                               |
| (unknown)     | `TK_IDENT`         | Safe default — never fall to `TK_ERROR`.                            |

### What we don't do

- **Modifiers are dropped at the kind level.** A `keyword` with
  `declaration` modifier is still `TK_KEYWORD`. The modifier
  string can be passed through alongside the kind for renderers
  that want it; the bridge doesn't surface it through the kind
  channel.
- **No reverse mapping** (vyakarana → LSP). vyakarana is a
  classifier, not an LSP server; renderers that need to expose
  vyakarana's output via the LSP wire protocol can write that
  serializer themselves, but it's not part of the bridge.
- **No JSON-RPC, no semantic-tokens-stream decoding.** LSP's
  `data: number[]` array is delta-encoded
  `[deltaLine, deltaStart, length, tokenType, modifiers]` per
  token. Decoding that, computing absolute byte offsets, and
  building a tokenbuf is a consumer concern — it touches LSP
  protocol details (legends, server capabilities, etc.) that
  don't belong in vyakarana. The bridge stops at name → kind.

## Consequences

### Positive

- **Editors can present a unified palette** regardless of who
  classified the bytes. cyim users see the same `keyword`
  colour whether vyakarana or rust-analyzer reported it.
- **Theme files don't fork per source.** Per
  [architecture note 004](../architecture/004-theme-palette-contract.md),
  themes index by `kind_name(k)` strings. The bridge means LSP
  output flows through the same name set. One theme file, two
  upstream classifiers.
- **The mapping is documented, testable, and stable.** Future
  LSP-spec additions (the spec has been gaining types
  conservatively over major versions) get an ADR amendment;
  consumers don't have to reverse-engineer.
- **The `[lib] modules` add is lightweight.** ~150 lines in the
  distlib bundle. Everyone gets it; nobody pays much for it.

### Negative

- **Information loss.** `function` and `variable` both collapse
  to `TK_IDENT`. Theme that wanted to colour functions
  differently from variables can't do so via the kind channel
  — they need the LSP type name passed through alongside.
  Documented as the same secondary-palette pattern from ADRs
  0004 / 0007.
- **The bridge encodes our 10-kind palette into LSP-shaped
  consumer code.** If the palette ever grows (it shouldn't —
  see architecture note 004), the bridge mapping changes and
  consumers must rebuild. Mitigation: the mapping is stable
  precisely because the palette is stable.
- **The "reserved" slot quirk in the LSP standard index.** The
  spec's standard-legend numeric ordering has shifted across
  3.16 → 3.17 (decorator was added, the indices renumbered).
  We hardcode the **3.17** order. Servers using older spec
  versions should resolve by name, not by index.

### When to revisit

- If the LSP spec adds new standard token types, amend the
  mapping table here and update `lsp_kind_from_token_type` /
  `lsp_kind_from_standard_index`.
- If a real consumer (cyim, VS Code) reports that the
  ident-collapse loses too much signal in practice, revisit
  the secondary-palette pattern. The current call is "themes
  pass through the LSP type name alongside the kind"; a
  future `lsp_secondary_palette(name) -> tag` helper is
  conceivable, but adds public surface and shouldn't ship
  speculatively.
- If reverse mapping (vyakarana → LSP) becomes load-bearing
  (e.g., vyakarana grows an LSP-server mode), promote it to
  its own ADR — different design space.
