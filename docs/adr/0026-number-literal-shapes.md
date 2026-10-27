# 0026 — Number literal shapes: floats, digit separators, datetimes

- **Status:** Accepted
- **Date:** 2026-10-20
- **Deciders:** 2.7.0 number-literal work (proposed) / user (accepted
  via the pinned 2.7.0 roadmap entry)
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md) (rule types
  and `[defaults]`), [ADR 0008](0008-toml-triple-quoted-strings.md)
  (TOML scope), [ADR 0017](0017-streaming-api.md) (streaming),
  `src/grammars/default_scanner.cyr` (`_ds_scan_number`),
  `src/tokenize.cyr` (`_stream_num_lookahead`), `src/grammar.cyr`

## Context

Through 2.6.2 the number step knew four things — `number_decimal`
(a digit run) and the `0x` / `0b` / `0o` prefixes. Everything else
split: `0.1` was `0` `.` `1` in every grammar, `1e5` was `1` + ident
`e5`, `1_000` was `1` + ident `_000` (the README's token table has
listed `1_000` as a number since 1.0), `OPENQASM 2.0;` was three
tokens, a TOML datetime was eight. Nothing errored — 2.5.2 gave JSON
a `.` operator for exactly that — but a theme coloured half a float.

## Decision

Three opt-in `[defaults]` keys, all applied inside the number step
(no new rule type, no new token kind — a float, a separated integer
and a datetime are all `number`):

- **`number_float = true`** — a decimal run may continue with a
  fraction (`.` **followed by a digit**) and then an exponent (`e` /
  `E`, an optional sign, **then a digit**). The required digit is what
  keeps `1..2` (ranges in rust, ruby, elixir, kotlin, haskell, lua
  concatenation), `1.max()`, `x.0.y` and `1e` split. Out of scope, so
  still split: a trailing-dot `1.`, a leading-dot `.5` (it would need
  the punctuation step to look ahead, and `.` starts CSS selectors),
  hex floats, and every suffix (`1.5f`, `2j`, `1u32`, `100ns`) — the
  suffix is the ident after the number, as before.
- **`number_separator = "_"`** (or `"'"`) — one non-digit byte that
  joins a digit run, in every base, **only when a digit follows it**:
  `1_000`, `0xFF_FF`, `1_000.000_1` are one number; `1_u32` and
  `2.5_f64` are number + suffix; `1__0` is `1` + `__0`. C++'s `'` is
  the same rule — a `'` before a digit continues the number, so
  `1'000'000` is one token and `'a'` is still a char literal. Any
  other value rejects the grammar.
- **`number_datetime = true`** — RFC 3339 / TOML dates and times as
  one number: `1979-05-27`, with `T` / `t` / space and `HH:MM`
  (`:SS`, `.fraction`, `Z` / `±HH:MM` optional), or a local time
  `HH:MM:SS…` on its own. A standalone time needs its seconds, so
  prose like `10:30` in YAML is not a time.
- *(Amended 2.9.3: a fourth key.)* **`number_tuple_index = true`** —
  a number right after a lone `.` takes no fraction, so Swift's
  `t.0.1` is `t . 0 . 1`, as Swift's own lexer reads it
  (`Lexer::lexNumber`: "x.0.1 is sub-tuple access, not
  x.float_literal" — an integer ends at a `.` when the previous token
  is a period). A byte check stands in for the token check: the byte
  before is `.` and the one before that is not, so `0.0...1.5` keeps
  both floats. The exponent is unchanged (`t.0.1e5` is `0` `.` `1e5`,
  as in Swift). The drain now carries the last two committed bytes,
  not one (stream record 224 bytes). Without `number_float` the key
  would do nothing, so the grammar is rejected. Opted in: swift. Not
  rust — rustc lexes `0.1` whole, and a test holds it — nor terraform:
  HCL's scanner does too, and its parser rejects the chained legacy
  index ("Invalid legacy index syntax").

Opted in: **float** — json, python, javascript, typescript, rust,
go, c, cpp, java, kotlin, csharp, swift, zig, lua, julia, css, scss,
protobuf, graphql, openqasm, toml, yaml, cyml, ruby, crystal,
elixir, haskell, ocaml, php, sql, powershell, terraform, llvm_ir,
cyrius (34; Cyrius has `digits.digits` literals and `_`). **`_`
separator** — rust, python, java, kotlin, csharp, swift, javascript,
typescript, go, zig, julia, ruby, crystal, elixir, ocaml, haskell,
php, toml, cyrius; **`'`** — cpp. **Datetime** — toml, yaml, cyml.
Not opted in: shell, makefile, dockerfile, ini (values are text), the
two asm grammars, nix, and the markup / compose grammars (their
embedded languages bring their own settings). *(Amended 2.9.1: nix is
opted in for floats, which makes 35 — it has them, its own grammar
header said so, and nothing recorded why it was left out.)*

**Streaming.** A number can now grow from bytes *after* its end —
`1` + `.5`, `1_` + `000`, `1979` + `-05-27` — while the drain treated
any token ending before the buffer's end as settled. A number token
therefore commits only once `_stream_num_lookahead(g)` more bytes
have arrived: 2 with a separator, 3 with floats (`e`, sign, digit), 6
with datetimes (`-MM-DD`, `THH:MM`, `+HH:MM`). Zero for a grammar with
none of the three, so their drains are unchanged.

## Consequences

### Positive

- One token per literal in 34 grammars. Over 4,500 real files, 773
  change — 7,451 fractions, 434 separated integers, 176 exponents, no
  exit-code change. Every new token is exactly the union of the tokens
  it replaced, with two exceptions, each an old ident that now splits
  into the number's tail and what follows: a separated hex literal
  with a suffix (`0xFF_FF_00_00u32` — `_FF_00_00u32` becomes the
  tail + `u32`), and an exponent with a suffix (`1e5f` — `e5f`
  becomes `e5` + `f`; also a hex-looking run such as a git SHA in
  YAML, `34e114876b0b…`). *(Amended 2.9.1: this said "one exception";
  the audit's reviewer A found the second in 8 local C / C++ / Rust
  files.)*
- The every-offset two-feed split stays clean on all 42 non-compose
  corpora; `fuzz/chunk_invariance.fcyr`'s six number shapes fail at 58
  offsets with the lookahead disabled.

### Negative

- Token boundaries change for every consumer of those grammars — a
  minor release.
- Each grammar's opt-in is a judgement about its language; a float
  shape a language does not have (an exponent in Cyrius) is still
  read as one, which is harmless but not exact.
- Number tokens near a feed's end commit up to six bytes later.

### When to revisit

- Leading-dot floats (`.5`) or trailing-dot floats (`1.`) if a
  consumer needs them — the punctuation step would have to defer to
  the number step.
- Numeric suffixes as part of the number, if a theme wants `1.5f`
  coloured as one literal: a per-grammar suffix set, not a regex.

## Amendment 2.9.7 — dots and type suffixes

The "out of scope, so still split" shapes of the Decision, as three more
keys:

- **`number_lead_dot = true`** — `.5`, `.5e3`: a `.` a digit follows
  starts a number unless the byte before it could end an operand — a
  letter, digit, `_`, non-ASCII identifier byte, identifier-start byte
  (less `ident_lead` ones, so CSS's `-.5em` is a sign and a number), `.`,
  closing bracket or quote. `x.5`, `a..5`, `t[0].5` stay split; one byte
  back, as streaming already keeps.
- **`number_trail_dot = true`** — `1.`, `1.e5`, C's `1.f`: the `.` after a
  decimal run joins it unless the next byte is a `.` (`1..2`), a digit (a
  fraction) or an identifier that is neither an exponent nor a declared
  suffix (`1.max`).
- **`number_suffixes = [...]`** — identifiers that join the literal right
  after it, in any base, after one digit separator at most: `10UL`,
  `1.5f`, `1e5f`, `0xFFu8`, `1_u32`, `2j`, `10n`. Only an exact entry
  joins (`10px`, `1usizex` stay split); an entry must be an identifier.

The keys need `number_float` (the dots) or `number_decimal` (suffixes),
else the grammar is rejected. Opted in — lead: c, cpp, csharp, java,
javascript, typescript, python, kotlin, go, php, lua, julia, sql, css,
scss, powershell; trail: c, cpp, java, javascript, typescript, python,
go, php, lua, ocaml, rust, sql; suffixes: c, cpp, csharp, java, kotlin,
javascript, typescript, python, rust, go, ruby, crystal, ocaml. A number
now commits after up to four bytes for `.e+5`, or the longest suffix plus
two (its separator and the byte that ends it). Not done: hex floats, CSS
units, C++ user-defined literals, PowerShell multipliers (`10kb`), and a
trailing dot before another `.` — `1..__add__` reads `1` `.` `.`, as it
must for a range.
