# vyakarana 📖

> Source-code grammar and tokenizer library for AGNOS / Cyrius

**Vyakarana** (Sanskrit: व्याकरण — *grammar*) is the AGNOS answer to
"how do I syntax-highlight a file?" It reads source code and yields a
stream of typed tokens. That's the whole job.

Consumers decide what to do with the tokens — `owl` colors them for
terminal display, the `cyim` editor colors them in a buffer, and
`vidya` renders code samples in the reference library. Those three
are the whole downstream list — they are the only repos that declare
`[deps.vyakarana]`. The tokenizer and the renderer stay on opposite
sides of a small, stable contract.

**vidya is also a corpus supplier.** Its
`content/lexing_and_parsing/` directory ships hand-written reference
samples for 11 languages (cyrius, rust, c, python, go, typescript,
zig, shell, x86_64 asm, aarch64 asm, openqasm). Those samples become
vyakarana's canonical test corpus: a bundled grammar passes when it
tokenizes the vidya sample cleanly with zero `error` kinds.

---

## Why another tokenizer?

- **Tree-sitter** is ~2 MB of C + C++ + Rust per language, with a
  C parser-generator in the build loop. Not in keeping with the
  AGNOS "no C, no LLVM, no Python" stack.
- **TextMate / Sublime grammars** are regex-over-JSON, 20 years old,
  and ship a bespoke language each. Reasonable, but not a fit for
  a stack whose configuration language is already CYML.
- **Hand-written lexers per language** is what every language already
  does inside its own compiler. Fine for one language; painful when
  you want ten.

vyakarana picks one thing: a **small, stable token-kind palette**, a
**CYML grammar format**, and a **streaming tokenizer** that reads
source once and yields `(kind, start, len)` spans into the caller's
buffer. Zero copies, zero allocations per token, zero external deps.

---

## Token kinds

vyakarana emits one of ten kinds per token. The palette is stable by
design — grammar authors and theme palettes both depend on it, so
growth requires a design review.

| Kind          | Examples                              |
|---------------|---------------------------------------|
| `ident`       | variable and function names           |
| `keyword`     | `if`, `fn`, `return`, `def`, `let`    |
| `string`      | `"hello"`, `'world'`, backtick strs   |
| `number`      | `42`, `3.14`, `0xff`, `1_000`         |
| `comment`     | line and block comments               |
| `operator`    | `+`, `==`, `->`, `&&`                 |
| `punctuation` | `{`, `}`, `,`, `;`, `(`               |
| `whitespace`  | spaces, tabs, newlines                |
| `preprocessor`| `#include`, `#define`, `use`/`import` |
| `error`       | unrecognized input (token lost)       |

Ten kinds, ten palette slots, done. Themes that want finer distinctions
(keyword-kind vs. keyword-control, string-regular vs. string-regex) can
add them behind this floor without breaking grammars that stop at the
ten.

---

## Install

```sh
# AGNOS / Cyrius native package manager (future)
pkg install vyakarana

# From source
git clone https://github.com/MacCracken/vyakarana
cd vyakarana
cyriusly use 6.5.4                  # match the pin in cyrius.cyml first
cyrius deps                         # vendors lib/ from the pinned toolchain
sh scripts/embed-grammars.sh        # inlines grammars/*.cyml; gitignored
cyrius build src/main.cyr build/vyk
```

Both pre-build steps are mandatory: `lib/` and `src/grammar_blobs.cyr`
are gitignored, so a fresh checkout has neither. On an *existing*
checkout, picking up a pin bump takes `cyriusly use <pin>` and then
`rm -rf lib && cyrius deps` — `cyrius deps` treats an already-present
`lib/<mod>.cyr` as satisfied and will not refresh it.

## `vyk` — the demo CLI

```sh
vyk --version              # prints `vyk 2.3.0`
vyk --list-kinds           # print the ten token kinds
vyk --list-languages       # list loaded grammars (45 bundled)
vyk file.rs                # NDJSON tokens for any bundled grammar
vyk --language=shell setup # explicit grammar override (extensionless)
```

`--theme=<name> file.py` previews the grammar via owl's palette
without running owl; `--handcoded file.sh` exercises the M1 hand-
coded shell oracle for regression diffs.

---

## Using vyakarana as a library

The 2.0+ public surface is a streaming primitive. Push bytes via
`_feed`, drain tokens whenever you want, finish to flush:

```cyrius
# After adding a [deps.vyakarana] block to your cyrius.cyml,
# `cyrius deps` vendors the bundle to lib/vyakarana.cyr —
# include it by that name, not by its path in this repo:
include "lib/vyakarana.cyr"

var s  = tokenize_stream_new("rust");
var tb = tokenbuf_new();
tokenize_stream_feed(s, src, src_len);
tokenize_stream_finish(s, tb);     # flushes pending state
tokenize_stream_free(s);
# tb holds (kind, start, len) tokens; iterate via tokenbuf_count /
# tokenbuf_kind / tokenbuf_start / tokenbuf_len.
```

A pull-style cursor (`tokenize_stream_next` / `_kind` / `_start` /
`_len` + `_discard_consumed`) layers on top for iterator-shaped
consumers. The 1.x synchronous `tokenize_source(src, lang)` entry
was removed in 2.0.0 (ADR 0017).

---

## Status

**2.3.0** (2026-07-31) — 45 bundled grammars, push + pull
streaming primitive, 4/4 fuzz harnesses green, 840/840 tests
passing. Toolchain pinned at `cyrius 6.5.4`. Toolchain catch-up
cut: the pin moved 6.1.24 → 6.5.4, four minor lines in one step —
minor rather than patch because it took source changes to get
there. `cyrius.cyml` shed a vestigial `cyml` stdlib entry that
made `cyrius deps` exit 1 on a fresh checkout, and eleven
duplicate variable names in `tests/vyakarana.tcyr` were renamed
so the suite compiles again. Both defects predate the bump and
reproduce at 6.1.24 — 2.2.3 shipped with a red test gate. No
public-API, token-layout, or grammar changes.

`docs/development/state.md` is the authoritative live tracker;
`CHANGELOG.md` is the per-cut log;
[`docs/development/roadmap.md`](./docs/development/roadmap.md)
holds the milestone history and parked backlog.

## License

GPL-3.0-only.
