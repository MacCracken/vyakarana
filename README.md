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
# From source — the supported path today
git clone https://github.com/MacCracken/vyakarana
cd vyakarana
cyriusly use 6.7.15                 # match the pin in cyrius.cyml first
cyrius deps                         # vendors lib/ from the pinned toolchain
sh scripts/embed-grammars.sh        # inlines grammars/*.cyml; gitignored
cyrius build src/main.cyr build/vyk

# AGNOS / Cyrius native package manager — NOT yet available
# pkg install vyakarana
```

Both pre-build steps are mandatory: `lib/` and `src/grammar_blobs.cyr`
are gitignored, so a fresh checkout has neither. On an *existing*
checkout, picking up a pin bump takes `cyriusly use <pin>` and then
`rm -rf lib && cyrius deps` — `cyrius deps` treats an already-present
`lib/<mod>.cyr` as satisfied and will not refresh it.

## `vyk` — the demo CLI

```sh
vyk --version              # prints `vyk <version>`
vyk --list-kinds           # print the ten token kinds
vyk --list-languages       # list loaded grammars (46 bundled)
vyk file.rs                # NDJSON tokens for any bundled grammar
vyk --language=shell setup # explicit grammar override (extensionless)
cat x.py | vyk --language=python -   # `-` reads standard input
```

Exit codes: 0 ok · 1 the output has `error` tokens · 2 bad usage (unknown
option, missing or invalid value) · 3 I/O error reading the input or
writing the output · 4 no grammar matched. `vyk --help` and
[`docs/man/vyk.1`](docs/man/vyk.1) have the details.

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

**2.6.1** (2026-10-20) — CLI hardening: write failures (a full disk, a
closed stdout) exit 3 instead of 0, bad or empty flag values are clear
usage errors, `-` reads standard input, `--` ends options, and NDJSON
output is 3.5x faster. Tokens unchanged from 2.6.0. Next on the
[roadmap](docs/development/roadmap.md): 2.6.2 detection from grammar
data.

**2.6.0** (2026-10-20) — shell correctness. `${#arr[@]}`, `${x#p}` and
`a#b` are code, not comments; here-documents (`<<EOF`, `<<'EOF'`,
`<<-EOF`) are one string token; `\"` and `$1` are single tokens.
Streaming stays chunk-invariant for all of it. 956/956 tests. Next on
the [roadmap](docs/development/roadmap.md): 2.6.1 CLI hardening.

**2.5.2** (2026-10-20) — the 2.5.x closeout audit. `vyk --theme` no
longer passes a file's terminal escape sequences through to your
terminal; streaming is chunk-invariant at every split offset for all
41 non-compose grammars and no longer grows its heap with every byte
fed; unclosed `<style>` / code fences no longer make tokenization
quadratic; malformed grammars are rejected instead of crashing. JSON
decimals, CYML `"""` strings, PHP `===`, OCaml / Ruby `::` and `.zsh`
files all tokenize correctly now. 927/927 tests. Details in
[docs/audit/2026-10-20-2.5.x-closeout-audit.md](docs/audit/2026-10-20-2.5.x-closeout-audit.md);
what comes next is pinned in
[docs/development/roadmap.md](docs/development/roadmap.md).

**2.5.1** (2026-10-20) — toolchain pinned at `cyrius 6.7.15`.
**46** bundled grammars, 923/923 tests, 5/5 fuzz harnesses. `vyk`
is 33 KB smaller (an unused stdlib module dropped), shebang
content detection is ~14% faster with identical answers, and
`#! /bin/sh` — whitespace after `#!` — is detected again (it had
not been since 2.3.4).

**2.5.0** (2026-10-20) — toolchain pinned at `cyrius 6.7.9`,
cyrius's 6.7 language line (from 6.6.20). No source change; token
output is byte-identical to the 6.6.20 build on every corpus.
**46** bundled grammars, 909/909 tests, 5/5 fuzz harnesses.

**2.4.3** (2026-10-20) — toolchain pinned at `cyrius 6.6.20`
(from 6.6.2). No source change; token output is byte-identical to
the 6.6.2 build on every corpus.
`dist/vyakarana.deps` now lists only the four stdlib leaves the
bundle actually needs (alloc, string, vec, io).

**2.4.0–2.4.2** made chunked streaming produce the same tokens as a
whole-buffer feed for 15 of 20 corpora (2.4.0), moved the pin to
6.6.2 (2.4.1), and renamed a private helper that collided with
sankoch's in consumers vendoring both (2.4.2). See the CHANGELOG.

**2.3.5** (2026-08-20) — **46** bundled grammars, push + pull
streaming primitive, 4/4 fuzz harnesses green, 909/909 tests
passing. Toolchain pinned at `cyrius 6.5.32`. Adds the
**`openqasm`** grammar (OpenQASM 2.0 + 3.x), closing the last gap
in vidya's sample set — `openqasm.qasm` was the one vidya file
`vyk` could not tokenize — plus the documentation repairs the
2.3.4 audit turned up.

**2.3.4** was the hardening + security sweep, the first full audit
since 2.1.x. 14 defects fixed: `vyk` silently truncated any file
over 1 MiB (exit 0, 30% of a 1.5 MB file dropped); streaming a
document with an embedded `<style>`/fence block was near-cubic and
effectively hung (32 KB: 19.6 s → 89 ms); chunked streaming closed
strings on *escaped* quotes; and any shebang with an interpreter
argument (`#!/bin/bash -e`) failed detection outright. Also a
one-byte OOB read, the u32 offset wrap past 4 GiB, and
FINDING-002/003 closed after four months open. Full write-up in
[docs/audit/2026-08-20-2.3.x-hardening-audit.md](docs/audit/2026-08-20-2.3.x-hardening-audit.md).

**2.3.3** was the toolchain catch-up: the pin moved 6.5.4 →
6.5.32, four minor lines in one step, with nothing in `src/`
needing a dialect fix. Measurably inert — the same tree built with
both compilers is byte-identical. It also turned the `lint + fmt`
release gate green for the first time.

`docs/development/state.md` is the authoritative live tracker;
`CHANGELOG.md` is the per-cut log;
[`docs/development/roadmap.md`](./docs/development/roadmap.md)
holds the milestone history and parked backlog.

## License

GPL-3.0-only.
