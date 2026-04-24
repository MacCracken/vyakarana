# vyakarana 📖

> Source-code grammar and tokenizer library for AGNOS / Cyrius

**Vyakarana** (Sanskrit: व्याकरण — *grammar*) is the AGNOS answer to
"how do I syntax-highlight a file?" It reads source code and yields a
stream of typed tokens. That's the whole job.

Consumers decide what to do with the tokens — `owl` colors them for
terminal display, a future editor (`cyim`) colors them in a buffer,
`agnoshi` colors fenced code blocks when an LLM returns code, and
`vidya` renders code samples in the reference library. The tokenizer
and the renderer stay on opposite sides of a small, stable contract.

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
cyrius deps
cyrius build src/main.cyr build/vyk
```

## `vyk` — the demo CLI

```sh
vyk --version              # scaffold-only in v0.1.0
vyk --list-kinds           # print the ten token kinds
vyk --list-languages       # list loaded grammars (empty in v0.1.0)
```

Once M1 lands, `vyk file.sh` will print the tokens as NDJSON so
you can eyeball grammar behavior from a shell.

---

## Using vyakarana as a library

```cyrius
# From a consumer's src, after adding a [deps.vyakarana] block:
include "vyakarana/src/tokenize.cyr"

var src = read_file("hello.sh");
var tokens = tokenize_source(src, "shell");
# tokens is a Vec<Token>; each token is (kind, start, len).
```

(Consumer-facing API solidifies in M1 alongside the first hand-coded
grammar.)

---

## Status

v0.1.0 — scaffold. Types locked; tokenizer stubbed; no grammars bundled
yet. See [docs/development/roadmap.md](./docs/development/roadmap.md) for the milestone plan.

## License

GPL-3.0-only.
