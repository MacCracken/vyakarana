# Consumer integration guide

How to integrate vyakarana into a downstream Cyrius project
(owl, cyim, agnoshi, vidya, or anything else that needs to
tokenize source code).

> **Last updated:** 2026-05-08 (1.10.0)
>
> Audience: implementers writing the *renderer*, *editor*,
> *theme*, or *content pipeline* that sits on top of vyakarana.
> If you're authoring a new grammar, see
> [docs/architecture/overview.md](../architecture/overview.md)
> instead.

---

## What you depend on

vyakarana ships a single concatenated distfile,
`dist/vyakarana.cyr`, that bundles the public API and all 38
grammars. Add to your project's `cyrius.cyml`:

```toml
[deps.vyakarana]
git     = "https://github.com/MacCracken/vyakarana.git"
tag     = "1.10.0"
modules = ["dist/vyakarana.cyr"]
```

`cyrius deps` will fetch the tag and copy the bundle into your
`lib/`. Pin to a tag, not a branch — the bundle changes per
release.

## What you get

Once the dep resolves, your project has access to:

### Public API surface

```cyrius
fn tokenize_source(src, lang) -> tokenbuf
fn has_grammar(name) -> i64                # 1 if known, 0 otherwise
fn list_languages_into(out_vec) -> i64     # populates a vec of cstr names
```

These are the **stable** entry points. Their names and arg
order do not change across the 1.x line — see
[docs/architecture/overview.md](../architecture/overview.md)
"Frozen public contracts."

### Tokenbuf accessors

```cyrius
fn tokenbuf_count(tb) -> i64
fn tokenbuf_kind(tb, i)  -> i64    # one of TK_* (see src/token.cyr)
fn tokenbuf_start(tb, i) -> i64    # byte offset into your `src`
fn tokenbuf_len(tb, i)   -> i64    # byte length
```

`tokenbuf` is opaque — treat it as a handle. The accessors are
zero-allocation and inline-friendly per
[ADR 0002](../adr/0002-token-storage-layout.md).

### Token-kind constants

```cyrius
var TK_IDENT        = 0;
var TK_KEYWORD      = 1;
var TK_STRING       = 2;
var TK_NUMBER       = 3;
var TK_COMMENT      = 4;
var TK_OPERATOR     = 5;
var TK_PUNCTUATION  = 6;
var TK_WHITESPACE   = 7;
var TK_PREPROCESSOR = 8;
var TK_ERROR        = 9;
var TK_COUNT        = 10;
fn kind_name(k)     -> cstr;       # "ident" / "keyword" / ...
```

The integer values, the string names, and the count of 10 are
all stable across 1.x — see
[architecture note 004](../architecture/004-theme-palette-contract.md).

## How to render

Walk the tokenbuf in order. For each token, slice
`src[start..start+len]` and apply your renderer's mapping for
that kind. Pseudocode:

```cyrius
var tb = tokenize_source(src, "rust");
var n = tokenbuf_count(tb);
var i = 0;
while (i < n) {
    var k = tokenbuf_kind(tb, i);
    var s = tokenbuf_start(tb, i);
    var l = tokenbuf_len(tb, i);

    # Look up the colour / style for this kind name.
    var style = your_theme_lookup(kind_name(k));

    # Emit the styled bytes.
    your_renderer_write_styled(style, src + s, l);

    i = i + 1;
}
```

### The theme contract

Themes index the palette by **kind name string** (the value of
`kind_name(k)`), not by integer. This is a deliberate
indirection: it means a theme that's been written and tested
against one project's vyakarana version will keep working when
the integer values shuffle (they won't, but the indirection
removes the temptation).

The contract is documented in
[architecture note 004](../architecture/004-theme-palette-contract.md).

The reference reader is `src/theme.cyr` in vyakarana itself —
the bundled `vyk --theme=default` mode is the canonical
implementation.

### Zero-copy

The `(start, len)` pair indexes into the **caller's** source
buffer. You own the buffer; vyakarana never copies bytes out of
it. Don't free `src` until you're done reading the tokens.

## Lazy loading

Grammars are loaded the first time `tokenize_source` is called
for a given language. If your renderer wants to pre-load the
registry at startup (e.g., to validate that `--language=foo`
will work later), call:

```cyrius
bootstrap_grammars();        # loads all 38 bundled grammars
```

Then `has_grammar("foo")` and `list_languages_into(vec)` give
you the registry contents.

## Error handling

`tokenize_source` returns `0` if the language name doesn't
match any registered grammar. Otherwise it returns a non-zero
tokenbuf handle. Check before reading.

```cyrius
var tb = tokenize_source(src, "unknown-lang");
if (tb == 0) {
    # No grammar matched. Render `src` as plain text.
    your_renderer_write_plain(src, strlen(src));
    return;
}
```

Per the **coverage invariant** ([architecture note
001](../architecture/001-coverage-invariant.md)),
`tokenize_source` always either returns 0 (unknown language) or
returns a tokenbuf where every byte of `src` is accounted for
in exactly one token. There is no partial-tokenization state to
worry about. `error` tokens (`TK_ERROR`) cover bytes the
grammar couldn't classify but the buffer is still complete.

## Corpus / sample sync

If you're shipping reference samples that vyakarana might want
to use as test corpora, see
[ADR 0001](../adr/0001-corpus-sync-policy.md) (snapshot policy)
and [ADR 0006](../adr/0006-standin-corpus-policy.md) (stand-in
policy). The short version: vyakarana's `tests/corpus/` holds
checked-in snapshots of vidya samples (where vidya has them)
and hand-rolled stand-ins (where vidya doesn't yet). Adding a
sample to vidya doesn't auto-flow into vyakarana — there's a
manual re-sync step.

## Performance expectations

- Tokenization is linear in input bytes. No O(n²) paths.
- `tokenbuf` allocates by doubling, not per-token (ADR 0002).
  For an N-byte input expect ≤ log₂(N) allocations.
- Public API has no syscalls beyond what your project's stdlib
  already pulls in.
- Streaming-tokenizer (iterator API) is scheduled for **2.0.0**
  per the roadmap. Until then, `tokenize_source` materializes
  the full tokenbuf eagerly. For files in the 1 MB range this
  is fine; for 100 MB+ files, wait for 2.0.0 or buffer
  yourself.

## Cross-repo coordination

If you're building a renderer in tandem with vyakarana
development, the project tracks consumer-side coordination in
[docs/development/state.md](../development/state.md)'s
"Consumer pressure" line. Prominent consumers (owl, cyim,
agnoshi, vidya) should expect their pinned tag to be valid for
the entire 1.x line — public API doesn't break across minors.

## Reporting issues

Bugs that affect the public API (wrong token kinds, coverage
violations, segfaults on adversarial input): file a security
advisory per `SECURITY.md`. Bugs in a specific grammar's
tokenization: file via the project's normal issue tracker. The
distinction matters because the API contract is much more
load-bearing than any one grammar's classification choices.
