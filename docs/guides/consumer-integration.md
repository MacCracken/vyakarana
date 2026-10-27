# Consumer integration guide

How to integrate vyakarana into a downstream Cyrius project
(owl, cyim, vidya, or anything else that needs to tokenize
source code).

> **Last updated:** 2026-10-21 (2.9.1)
>
> Audience: implementers writing the *renderer*, *editor*,
> *theme*, or *content pipeline* that sits on top of vyakarana.
> If you're authoring a new grammar, see
> [docs/architecture/overview.md](../architecture/overview.md)
> instead.

---

## What you depend on

vyakarana ships a single concatenated distfile,
`dist/vyakarana.cyr`, that bundles the public API **and the 49
grammars themselves** (inlined as Cyrius string literals — see
[ADR 0014](../adr/0014-embedded-grammar-blobs.md)). Add to your
project's `cyrius.cyml`:

```toml
[deps.vyakarana]
git     = "https://github.com/MacCracken/vyakarana.git"
tag     = "2.9.10"
modules = ["dist/vyakarana.cyr"]
```

`cyrius deps` will fetch the tag and copy the bundle in as
`lib/vyakarana.cyr`. The bundle `include`s the four stdlib modules
it needs (`alloc`, `string`, `vec`, `io`), which the
`dist/vyakarana.deps` sidecar names for `cyrius deps`. Pin to a
tag, not a branch — the bundle changes per release. Moving a 2.x
pin up changes what your renderer shows (tokenization fixes), not
the API; [state.md](../development/state.md)'s Consumers section
records each consumer's pinned tag and whether it builds against
the current bundle.

One adjacent trap, surfaced while cutting 2.3.0 (cyrius 6.5.4):
`cyrius deps` unlinks and re-copies *dep* modules like `lib/vyakarana.cyr` on
every run, but it treated an already-present *stdlib* module of
the same size as satisfied and never refreshed it. So bumping
the vyakarana tag did pick up the new bundle, while bumping
your own `cyrius = "X.Y.Z"` pin silently left `lib/alloc.cyr`
and friends at their old vintage — vyakarana's own tree ran on
a 6.0.x-vintage `lib/` from 2.2.2 until that cut caught it.
By cyrius 6.6.20 a plain `cyrius deps` refreshes a stale `lib/`
(CHANGELOG 2.4.3; re-checked at 6.7.18). On an older pin,
re-vendor with `rm -rf lib && cyrius deps`.

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

# Pull adapter (2.0.2+). Iterator over the same stream;
# pass 0 as out_tb to drain/finish to route into the
# stream's internal staging tokenbuf, then walk it via
# tokenize_stream_next. On long-running streams call
# _discard_consumed periodically — the staging grows
# monotonically otherwise.
fn tokenize_stream_next(s)              -> i64            # 1 advanced, 0 exhausted
fn tokenize_stream_kind(s)              -> i64            # current token's kind
fn tokenize_stream_start(s)             -> i64            # current token's start
fn tokenize_stream_len(s)               -> i64            # current token's len
fn tokenize_stream_discard_consumed(s)  -> i64            # 2.1.4+; tokens dropped

fn has_grammar(name) -> i64                # 1 if known, 0 otherwise
fn list_languages_into(out_vec) -> i64     # populates a vec of cstr names
fn bootstrap_grammars()                    # explicit load (see Lazy loading)

# Language detection (1.11.2+). All four return a language
# name (cstr) suitable for tokenize_stream_new, or 0 if no match.
fn detect_language(path) -> cstr                    # extension + basename suffix match
fn detect_language_from_content(src, src_len) -> cstr   # BOM/shebang/signature sniff
fn detect_language_combined(path, src, src_len) -> cstr # path first, content fallback + asm flavour vote
# 2.9.8+: routes by the REGISTRY's declared extensions / filenames /
# shebangs, so grammars you registered route too; src may be 0.
fn detect_language_registered(path, src, src_len) -> cstr

# LSP semantic-tokens bridge (1.11.0+). Maps LSP's standard
# token-type taxonomy onto vyakarana's 10 TK_* kinds.
fn lsp_kind_from_token_type(name) -> i64       # by name (one of LSP's 23 standard types)
fn lsp_kind_from_standard_index(idx) -> i64    # by integer index in LSP 3.17 legend
```

These are the **stable** entry points. Their names and arg
order do not change across the 2.x line — see
[docs/architecture/overview.md](../architecture/overview.md)
"Frozen public contracts." The header of `src/tokenize.cyr` is
the authoritative list of the stream and registry symbols.

### Routing your own grammars

A grammar you load and register — `registry_add(grammar_load(path))`,
as owl's user overlay and cyim's loader do — declares its routes in its
`[grammar]` table: `extensions = [".foo"]`, `filenames = ["Foofile"]`,
`shebangs = ["foo"]` (ADR 0025). `detect_language_registered(path, src,
src_len)` routes by those declarations across the whole registry, so you
need no routing table of your own ([ADR 0031](../adr/0031-detect-language-registered.md)):

- the longest declared extension the path ends with, case-sensitive;
- else a declared filename (`Foofile`, `ci/app.Foofile`, `Foofile.dev`);
- else, when `src` is given, the `#!` line's interpreter (after `env`
  and its options), prefix-matched against declared shebangs.

Ties go to the **first registered** grammar, as name lookup does — so
register yours before calling `bootstrap_grammars()` (or set
`_grammars_bootstrapped` and load the bundled ones after yours) if they
should win a route a bundled grammar also declares. The function
bootstraps the bundled grammars itself, as `has_grammar` does.

The compiled three stay pure and know only the bundled grammars; they
also carry what declarations cannot say — the `.s` / `.S` content vote
and the `<?xml` signature sniff (`detect_language_combined`). For the
bundled grammars the two paths agree on every declared route; the one
designed difference is a declared shebang being a plain prefix
(`#!/usr/bin/shellcheck` routes to shell), where the compiled sniff
bounds `sh` to three bytes.

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
all stable across 1.x and 2.x — the 2.0.0 break was the entry
point only, and the palette hasn't moved since. See
[architecture note 004](../architecture/004-theme-palette-contract.md).

## How to render

Drive the streaming primitive (push bytes, drain tokens), then
walk the resulting tokenbuf. For each token, slice
`src[start..start+len]` and apply your renderer's mapping for
that kind. Pseudocode:

```cyrius
var s = tokenize_stream_new("rust");
if (s == 0) { return 0; }      # unknown grammar
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

Or with the **pull adapter** (2.0.2+) — same end result, no
intermediate tokenbuf to manage:

```cyrius
var s = tokenize_stream_new("rust");
if (s == 0) { return 0; }      # unknown grammar
tokenize_stream_feed(s, src, strlen(src));
tokenize_stream_finish(s, 0);   # 0 = drain into internal staging

while (tokenize_stream_next(s) == 1) {
    var k = tokenize_stream_kind(s);
    var p = tokenize_stream_start(s);
    var l = tokenize_stream_len(s);

    var style = your_theme_lookup(kind_name(k));
    your_renderer_write_styled(style, src + p, l);
}
tokenize_stream_free(s);
```

For interleaved feed + iterate (the actual streaming use case),
call `_next` in a loop between feeds — drain refills the
staging incrementally, `_next` returns 0 when no more tokens
are available right now, and you continue feeding.

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

The `(start, len)` pair indexes into the **caller's** source —
offsets from the first byte fed to the stream. `tokenize_stream_feed`
copies each chunk into the stream's own rolling buffer to scan it
([ADR 0017](../adr/0017-streaming-api.md)), but no token points
there: slice your own bytes to render, and don't free `src` until
you're done reading the tokens.

## Lazy loading

Grammars are loaded the first time `tokenize_stream_new` /
`has_grammar` is called for any language. If your renderer
wants to pre-load the registry at startup (e.g., to validate
that `--language=foo` will work later), call:

```cyrius
bootstrap_grammars();        # loads all 49 bundled grammars
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
    return 0;
}
```

`tokenize_stream_feed` returns:
- `VYK_OK` (0) — bytes accepted.
- `VYK_ERR_OVERFLOW` (-1) — buffer cap (`VYK_STREAM_CAP`,
  16 MiB) would be exceeded. Since 2.0.1's rolling buffer
  compacts after every drain, this bounds the longest
  *in-progress* span — one block comment, string, or fence
  body — not the total bytes you feed. Total input is capped at
  4 GiB per stream (`VYK_OFFSET_CAP`, 2.3.4,
  [ADR 0021](../adr/0021-token-span-width-ceiling.md)): past it
  `feed` returns this code rather than wrap token offsets. A
  still-open heredoc group is held for at most
  `VYK_HEREDOC_HOLD_MAX` (1 MiB) before its bytes commit
  ([ADR 0028](../adr/0028-streaming-holds-watches-groups.md);
  state.md has the exact bounds). A still-open compose region whose
  body has an inner grammar is not held: its body streams as that
  grammar's own, so its live buffer is the inner grammar's (2.9.10,
  [ADR 0032](../adr/0032-resumable-compose-regions.md)); one whose body
  is a single token (an untagged fence) holds for at most
  `VYK_COMPOSE_HOLD_MAX` (8 MiB).
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

- Whole-buffer tokenization is linear in input bytes. *(Through
  2.5.1 this line said "No O(n²) paths" without qualification. It
  was false: a compose opener with no closer — `<style>` with no
  `</style>`, a stray fence — re-scanned to EOF per opener, and 1 MiB
  of them ran past 300 s. 2.5.2 makes those paths linear.)* The
  **streaming** drain's quadratic cases — a very long comment,
  identifier, whitespace or digit run, or a long fence or `<style>`
  body, fed in small chunks — are linear since 2.8.0
  ([ADR 0028](../adr/0028-streaming-holds-watches-groups.md)). Since
  2.9.10 a long, still-open compose region streams too: a fence,
  `<style>`, `<script>` or cyml body commits as its inner grammar
  settles it, before its end marker arrives
  ([ADR 0032](../adr/0032-resumable-compose-regions.md)). An untagged
  fence's body, one token, still waits for its closer (state.md, Known
  limits).
- `tokenbuf` allocates by doubling, not per-token (ADR 0002).
  For an N-byte input expect ≤ log₂(N) allocations.
- Public API has no syscalls beyond what your project's stdlib
  already pulls in.
- The streaming API shipped in **2.0.0**, the rolling buffer
  and per-feed drainage in 2.0.1, the pull adapter in 2.0.2 —
  nothing has to materialize the whole file eagerly any more.
  Feed in chunks, drain as you go, and the *source-side*
  footprint tracks your chunk size plus the longest
  in-progress span rather than the input size.
- The *token* side is yours to bound. A caller-owned tokenbuf
  keeps every token ever drained into it, and the pull
  adapter's staging grows monotonically until you call
  `tokenize_stream_discard_consumed(s)` (2.1.4+). On a 100 MB
  input that's O(total tokens) of live memory unless you
  iterate with the pull adapter and discard periodically — do
  that and 100 MB+ files are a loop, not a problem.

## Cross-repo coordination

If you're building a renderer in tandem with vyakarana
development, the project tracks consumer-side coordination in
[docs/development/state.md](../development/state.md)'s
"Consumers" section. The consumers that actually declare
`[deps.vyakarana]` are owl, cyim, and vidya; they should expect
their pinned tag to be valid for the entire 2.x line — public
API doesn't break across minors.

## Reporting issues

Bugs that affect the public API (wrong token kinds, coverage
violations, segfaults on adversarial input): file a security
advisory per `SECURITY.md`. Bugs in a specific grammar's
tokenization: file via the project's normal issue tracker. The
distinction matters because the API contract is much more
load-bearing than any one grammar's classification choices.
