# ADR 0011 — `case_insensitive_keywords` default

- **Status:** Accepted
- **Date:** 2026-05-08
- **Deciders:** 1.6.0 SQL grammar work / user (accepted)
- **Relates to:** [ADR 0004](0004-shell-builtins-as-ident.md)
  (built-ins-as-ident pattern), [ADR 0009](0009-unicode-ident-default.md)
  (`unicode_ident` flag — same shape), [ADR 0010](0010-char-literal-default.md)
  (`char_literal` flag — same shape), `src/grammar.cyr`,
  `src/grammars/default_scanner.cyr`, `grammars/sql.cyml`

## Context

Through 1.5.0, `[[rules]] match = "words"` used a strict
byte-equal comparison (`memeq`) to match identifiers against the
reserved-word list. That's correct for every language we ship
where reserved words have a canonical case — `SELECT` is not
`select` in C / Rust / Go / Python / etc., and writing `If` (as a
typo for `if`) genuinely is an undefined identifier in those
languages.

SQL is the first bundled grammar where it isn't. Per ANSI SQL:1992
§5.2 (and reaffirmed in every later revision), reserved words are
**case-insensitive**: `SELECT`, `select`, `Select`, `sElEcT` are
all the same word. PostgreSQL, MySQL, SQLite, T-SQL, Oracle, and
DB2 all conform. A SQL grammar that lists only the upper-case form
would mis-tokenize `select * from users` as five idents instead
of `keyword + operator + keyword + ident`. Doubling the keyword
list to include both cases is feasible but ugly (and triples once
mixed-case starts mattering — `Select`, `selecT`, …).

Same pattern shows up in upcoming grammars:
- **HCL / Terraform** has case-sensitive idents but contextual
  case-insensitivity around some forms.
- **PL/SQL, T-SQL** are SQL dialects with the same case rule.
- **BibTeX** is also keyword-case-insensitive.

The scanner already has two `[defaults]` flags shaped exactly the
way this one needs to be: `unicode_ident` ([ADR 0009](0009-unicode-ident-default.md))
and `char_literal` ([ADR 0010](0010-char-literal-default.md)).
Both are wired through a `Grammar` field, the CYML loader, and a
single scanner-step branch. Adding a third flag follows the same
pattern with no new architectural surface.

## Decision

**Add a `[defaults] case_insensitive_keywords = true|false`
flag.** When set, the words-rule lookup folds A–Z to a–z on both
sides of the comparison.

Wiring:
- New `Grammar` field at offset 152; `GRAMMAR_SIZE` 152 → 160.
- New accessor `grammar_case_insensitive_kw(g)`.
- CYML loader handles `case_insensitive_keywords = true|false`.
- New helper `_ds_to_lower(b)` (single-byte case fold; ASCII-only
  by design — UTF-8 case folding is out of scope for the
  tokenizer).
- New helper `_ds_word_match(src, start, w, wlen, fold)`
  replaces the `memeq` call inside `_ds_lookup_keyword`. When
  `fold = 0` it delegates to `memeq` (zero new cost on the hot
  path for grammars that leave the flag off). When `fold = 1`
  it walks both sides byte-by-byte applying `_ds_to_lower`.

Scanner pipeline: unchanged. The fold happens entirely inside
step 6 (Identifier / keyword lookup). [Architecture note 002](../architecture/002-scanner-pipeline-priority.md)
stays normative.

Defaulting **off**, enabled per-grammar in `grammars/sql.cyml`.
Other grammars can flip the flag if their language spec calls
for case-insensitive reserved words.

## Consequences

### Positive

- **SQL `select` / `SELECT` / `Select` all tokenize as `TK_KEYWORD`**
  through one keyword list with the canonical (upper-case)
  spelling. No double-listing, no scanner state, no regex.
- **Zero hot-path cost when off.** Existing 25 grammars hit a
  single conditional that delegates to the same `memeq` they
  used before. Constant-time additional check (one `load64` for
  the flag, one branch).
- **Pattern matches existing flags.** Same `Grammar`-field +
  `[defaults]`-key + scanner-branch shape as `unicode_ident`
  and `char_literal`. Future readers don't need a new mental
  model.
- **ASCII-only fold is the right scope.** SQL keyword-folding
  is defined over ASCII A-Z. UTF-8 case folding (Turkish dotless
  `i`, German `ß`, etc.) is a tokenizer non-goal; SQL
  identifiers may contain UTF-8 but reserved words don't.

### Negative

- **Per-token branch in the words-rule loop when on.** Two
  loads + a compare per byte instead of `memeq`'s vectorisable
  byte-block scan. Acceptable cost — keyword lookup runs only
  on idents (already filtered by step 6), and most idents are
  short. If a future SQL benchmark surfaces this as a hot
  spot, the matcher could pre-fold the keyword list at
  grammar-load time and use `memeq` against the folded source
  span — but that requires per-grammar storage we'd rather not
  add yet.
- **Grammar-record ABI bumped** from 152 to 160 bytes. Same
  story as ADRs 0009 and 0010: no consumer reads the in-memory
  `Grammar` directly.
- **Ident-text in source remains the original bytes.** A
  consumer reconstructing source from `(start, len)` triples
  gets back exactly what was scanned, not the folded form. This
  is correct — the tokenizer's job is to identify *what* a span
  is, not to mutate it.

### When to revisit

- If a grammar needs case-insensitive matching for some words
  but case-sensitive for others (mixing dialect rules), promote
  the flag to a per-rule shape: `[[rules]] match = "words"
  case_insensitive = true`. Today it's a `[defaults]` flag
  because no SQL dialect needs the mix.
- If UTF-8 case folding ever becomes load-bearing for a
  bundled grammar, that's a much bigger ADR — and probably the
  point at which the tokenizer takes a real Unicode dependency.
  Push back hard.
