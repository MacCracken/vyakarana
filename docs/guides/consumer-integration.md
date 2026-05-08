# Consumer integration guide

How to integrate vyakarana into a downstream Cyrius project
(owl, cyim, agnoshi, vidya, or anything else that needs to
tokenize source code).

> **Last updated:** 2026-05-08 (2.0.0)
>
> Audience: implementers writing the *renderer*, *editor*,
> *theme*, or *content pipeline* that sits on top of vyakarana.
> If you're authoring a new grammar, see
> [docs/architecture/overview.md](../architecture/overview.md)
> instead.

---

## What you depend on

vyakarana ships a single concatenated distfile,
`dist/vyakarana.cyr`, that bundles the public API **and the 38
grammars themselves** (inlined as Cyrius string literals — see
[ADR 0014](../adr/0014-embedded-grammar-blobs.md)). Add to your
project's `cyrius.cyml`:

```toml
[deps.vyakarana]
git     = "https://github.com/MacCracken/vyakarana.git"
tag     = "2.0.0"
modules = ["dist/vyakarana.cyr"]
```

`cyrius deps` will fetch the tag and copy the bundle into your
`lib/`. Pin to a tag, not a branch — the bundle changes per
release.

> **1.11.0 and earlier are broken.** Through 1.11.0 the bundle
> tried to read `grammars/<name>.cyml` from disk at runtime, but
> `cyrius deps` only vendors the bundle file. Pin **1.11.1 or
> later** for a working integration. Older tags will silently
> register zero grammars and return empty tokenbufs.
>
> **1.x → 2.x is a breaking change.** The synchronous
> `tokenize_source(src, lang)` entry was removed in 2.0.0 in
> favor of the streaming primitive. See
> [ADR 0017](../adr/0017-streaming-api.md) for the design and
> migration recipe. 1.x consumers can stay pinned to 1.13.3
> indefinitely; 2.x consumers update one function call.

## What you get

Once the dep resolves, your project has access to:

### Public API surface

```cyrius
# Streaming tokenizer (2.0+). Push chunks of bytes; drain
# tokens. Replaces the 1.x `tokenize_source` synchronous entry.
# See ADR 0017 for the design and migration recipe.
fn tokenize_stream_new(lang)            -> stream_handle  # 0 if grammar unknown
fn tokenize_stream_feed(s, chunk, n)    -> i64            # VYK_OK / VYK_ERR_*
fn tokenize_stream_drain(s, out_tb)     -> i64            # tokens appended this call
fn tokenize_stream_finish(s, out_tb)    -> i64            # final drain
fn tokenize_stream_free(s)

fn has_grammar(name) -> i64                # 1 if known, 0 otherwise
fn list_languages_into(out_vec) -> i64     # populates a vec of cstr names

# Language detection (1.11.2+). All three return a language
# name (cstr) suitable for tokenize_stream_new, or 0 if no match.
fn detect_language(path) -> cstr                    # extension + basename suffix match
fn detect_language_from_content(src, src_len) -> cstr   # BOM/shebang/signature sniff
fn detect_language_combined(path, src, src_len) -> cstr # path first, content fallback + asm flavour vote

# LSP semantic-tokens bridge (1.11.0+). Maps LSP's standard
# token-type taxonomy onto vyakarana's 10 TK_* kinds.
fn lsp_kind_from_token_type(name) -> i64       # by name (one of LSP's 23 standard types)
fn lsp_kind_from_standard_index(idx) -> i64    # by integer index in LSP 3.17 legend
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

Drive the streaming primitive (push bytes, drain tokens), then
walk the resulting tokenbuf. For each token, slice
`src[start..start+len]` and apply your renderer's mapping for
that kind. Pseudocode:

```cyrius
var s = tokenize_stream_new("rust");
if (s == 0) { /* unknown grammar */ return; }
var tb = tokenbuf_new();
tokenize_stream_feed(s, src, strlen(src));
tokenize_stream_finish(s, tb);
tokenize_stream_free(s);

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

Grammars are loaded the first time `tokenize_stream_new` /
`has_grammar` is called for any language. If your renderer
wants to pre-load the registry at startup (e.g., to validate
that `--language=foo` will work later), call:

```cyrius
bootstrap_grammars();        # loads all 38 bundled grammars
```

Then `has_grammar("foo")` and `list_languages_into(vec)` give
you the registry contents.

## Error handling

`tokenize_stream_new` returns `0` if the language name doesn't
match any registered grammar. Check before feeding.

```cyrius
var s = tokenize_stream_new("unknown-lang");
if (s == 0) {
    # No grammar matched. Render `src` as plain text.
    your_renderer_write_plain(src, strlen(src));
    return;
}
```

`tokenize_stream_feed` returns:
- `VYK_OK` (0) — bytes accepted.
- `VYK_ERR_OVERFLOW` (-1) — buffer cap (`VYK_STREAM_CAP`,
  1 MB in 2.0.0) would be exceeded. 2.0.1+ removes this with
  rolling-buffer streaming.
- `VYK_ERR_FINISHED` (-2) — `tokenize_stream_finish` already
  ran on this stream; create a fresh one for new input.

Per the **coverage invariant** ([architecture note
001](../architecture/001-coverage-invariant.md)),
`tokenize_stream_finish` produces a tokenbuf where every byte
fed into the stream is accounted for in exactly one token.
There is no partial-tokenization state to worry about. `error`
tokens (`TK_ERROR`) cover bytes the
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
