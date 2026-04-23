# `vyakarana` — Design Specification

**Source-code grammar and tokenizer library for AGNOS / Cyrius**

Version: 0.1 (draft)
Status: Design spec, scaffold-stage implementation
Audience: Implementation agent / contributors

---

## 1. Purpose & Scope

`vyakarana` reads source code and yields a stream of typed tokens. It
is the source-of-truth tokenizer for every AGNOS consumer that needs
to color, inspect, or analyze source files.

**In scope:**
- A stable, small token-kind palette (ten kinds)
- A grammar format (Cyrius-native CYML) and a loader for it
- A streaming tokenizer that reads source once and yields zero-copy
  `(kind, start, len)` spans
- Bundled grammars for a starter set of ten languages
- A demo CLI (`vyk`) for inspecting grammar behavior

**Out of scope:**
- Parsing (structural tree, AST) — vyakarana stops at the token level
- Semantic analysis (name resolution, type-checking)
- Incremental / edit-driven retokenization (post-v1)
- Language servers, formatters, linters

---

## 2. Design Principles

1. **Tokens, not trees.** Syntax highlighting and code display need
   tokens. Full parsing is an order of magnitude more work and has an
   order of magnitude more consumers; keep vyakarana on the small job.
2. **Palette stability is a contract.** The ten token kinds are an
   API. Grammar authors and theme authors both depend on the set.
   Growth requires a design review, never a patch-release change.
3. **Zero-copy spans.** Tokens carry `(kind, start, len)` into the
   caller's source buffer. No allocations per token. Normalization
   (lowercase, strip quotes, resolve escapes) is the consumer's job.
4. **Streaming by default.** A tokenizer call must be able to yield
   tokens for line N before reading line N+1. `owl huge.log` should
   render the first screen before buffering the whole file.
5. **Grammar format is data, not code.** Grammars are CYML files, not
   compiled shared objects and not regex-JSON. A new language is a
   new file, reviewable, diffable, test-corpus-backed.
6. **Refuse to mimic incumbents.** No tree-sitter, no TextMate, no
   Sublime grammars. Those solve a different problem (AST + editor
   affordances) and carry 20 years of shape vyakarana does not need.

---

## 3. Token Kinds

The palette is **ten kinds, stable by design**.

| Kind          | Purpose                                              |
|---------------|------------------------------------------------------|
| `ident`       | Identifiers (variable / function / type names)       |
| `keyword`     | Language-reserved words (`if`, `fn`, `return`, ...)  |
| `string`      | String literals including raw / multi-line / backtick|
| `number`      | Numeric literals (int, float, hex, octal, binary)    |
| `comment`     | Line and block comments, docstrings                  |
| `operator`    | Symbolic operators (`+`, `==`, `->`, `&&`, ...)      |
| `punctuation` | Structural delimiters (`{`, `}`, `,`, `;`, `(`, ...) |
| `whitespace`  | Spaces, tabs, newlines (emitted for span coverage)   |
| `preprocessor`| Directives (`#include`, `#define`, `use`, `import`)  |
| `error`       | Unrecognized input — marks a grammar coverage gap    |

### 3.1 Why ten? Why these?

- **Every grammar can express itself with them.** Survey of
  shell / Python / JS / Rust / C / Cyrius / TOML / JSON / YAML /
  Markdown shows no kind-level distinction any of them need beyond
  this palette.
- **Theme palettes scale with them.** A ten-slot palette is small
  enough that a human can design one from scratch; a fifty-slot
  palette produces diminishing returns and reviewer fatigue.
- **Finer distinctions are a theme concern.** If a user wants
  keyword-control colored differently from keyword-declaration, the
  theme layer can introspect token text and apply a secondary
  palette. vyakarana does not need to model that.
- **`error` is a grammar test.** A passing grammar produces zero
  `error` tokens on its vidya sample. `error` is not silently
  tolerated.

### 3.2 Coverage guarantee

Every byte of the input source is covered by exactly one token. This
is a round-trip invariant: concatenating every token's underlying
bytes in order reproduces the source. `whitespace` tokens exist so
that this invariant holds without a per-run "gap" fallback.

---

## 4. Span Type

```
struct Token {
    kind:  u8,    # index into the palette
    start: u32,   # byte offset into source
    len:   u32,   # byte length
}
# 12 bytes, cache-friendly, no pointers
```

Token layout is load-bearing for every consumer. Once v1.0 ships,
changing it is a breaking change. Pre-1.0, changes are allowed but
must be CHANGELOG-flagged.

---

## 5. Grammar Format (CYML)

A grammar is a CYML file at `grammars/<lang>.cyml`. Format locked in
M2; M1 proves the runtime with a hand-coded shell grammar.

Sketch:

```toml
[grammar]
name = "shell"
extensions = [".sh", ".bash"]
shebangs = ["sh", "bash", "zsh", "dash"]

[[rules]]
kind = "comment"
match = "line"
start = "#"

[[rules]]
kind = "string"
match = "pair"
start = "\""
end = "\""
escape = "\\"

[[rules]]
kind = "keyword"
words = ["if", "then", "else", "fi", "for", "while", "do", "done", "case", "esac"]
```

Rule types (M2 set):

- `line` — from marker to end-of-line
- `pair` — from start marker to unescaped end marker
- `words` — exact match from a list, word-boundary-aware
- `regex` — deliberately **not** in M2. Regex in grammar files leads
  to performance cliffs and grammar authors debugging regex engines
  instead of grammars. If a language needs lookahead, we add a
  domain-specific rule type for it.

---

## 6. Streaming Tokenizer

Tokenize yields tokens in source order. A consumer can stop reading
at any point without penalty; vyakarana does not eagerly produce the
full list.

```cyrius
var src = read_file("hello.sh");
var tokens = tokenize_source(src, "shell");
for tok in tokens {
    # tok.kind, tok.start, tok.len into src
}
```

API shape solidifies in M1. The streaming guarantee is a non-functional
requirement: token production for line N must not depend on reading
line N+k for any k > 0 (except when a token itself spans multiple
lines, e.g. a multi-line string — and then production happens at the
closing marker).

---

## 7. Bundled Grammars

Starter set (ships in M3):

- shell (M1 hand-coded, M2 re-expressed as CYML, M3 re-verified)
- python
- javascript
- typescript
- rust
- c
- cyrius
- toml
- json
- yaml
- markdown

Each grammar's test corpus is its `content/lexing_and_parsing/<lang>.*`
sample from `vidya`. A grammar passes when:

1. Tokenizing the vidya sample produces zero `error` tokens
2. Concatenating every token's bytes reproduces the vidya sample
   exactly (coverage invariant from §3.2)
3. A hand-audited sample of ~30 tokens shows the expected kinds

---

## 8. `vyk` — Demo CLI

v0.1.0:

```
vyk --version              # scaffold-only
vyk --list-kinds           # print the ten token kinds
vyk --list-languages       # list loaded grammars (empty in v0.1.0)
vyk --help
```

M1+:

```
vyk <file>                 # NDJSON: {"kind":"keyword","start":0,"len":2}
vyk --language=<lang> <f>  # override detection
vyk --stats <file>         # kind histogram, coverage check
```

`vyk` is a diagnostic tool, not a pretty-printer — it exists so a
grammar author can see what their grammar actually produces. Pretty
rendering is owl's job.

---

## 9. Exit Codes (demo CLI)

| Code | Meaning                                           |
|------|---------------------------------------------------|
| 0    | Success                                           |
| 1    | Grammar found `error` tokens in input             |
| 2    | Usage error (bad flag)                            |
| 3    | I/O error                                         |
| 4    | No grammar matched / no grammar loaded            |

---

## 10. Non-functional Requirements

- **Startup time:** `vyk --version` under 20ms on target platform.
- **Throughput:** at least 50 MB/s tokenization on a 1 MB source file
  (measure in M3 once a real grammar is loaded).
- **Memory:** O(tokens), not O(input). Streaming yields tokens as
  they are identified; no "tokenize to a Vec, then return" path.
- **Binary size:** target under 300KB for `vyk` once the ten bundled
  grammars are embedded. Grammars are compact CYML; embedding all
  ten should be under 100KB of data.

---

## 11. Relationship to vidya

Two-way:

- **vidya supplies corpus.** `content/lexing_and_parsing/*` is the
  canonical test corpus for every bundled grammar.
- **vyakarana renders vidya.** vidya's reference-library pages that
  show code samples can route through vyakarana for tokenization; a
  rendering layer (owl for terminal, a future web layer for the GUI)
  turns tokens into colored output.

This relationship means vyakarana **cannot** depend on vidya at the
build level (cycles are forbidden), but vidya content drives
vyakarana's tests. Keep the corpus in vidya; mirror it for tests via
a vendor-copy or submodule pattern once M3 lands.

---

## 12. Relationship to owl (M3b consumer)

owl's M3b is blocked on vyakarana's M1. The handoff contract:

1. vyakarana ships a stable `Token` type in M0 (v0.1.0 — this
   release).
2. vyakarana ships a working tokenizer with at least one grammar
   (shell) in M1 — owl can then import and verify end-to-end.
3. vyakarana's theme-palette kind mapping contract with owl
   solidifies in M4.

owl consumes vyakarana via `[deps.vyakarana]` git + tag block (per
AGNOS real-deps-only policy). No path hacks.

---

*End of design spec.*
