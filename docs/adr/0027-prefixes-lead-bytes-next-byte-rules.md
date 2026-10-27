# 0027 — String prefixes, identifier lead bytes, next-byte line rules

- **Status:** Accepted
- **Date:** 2026-10-20
- **Deciders:** 2.7.1 grammar-polish work (proposed) / user (accepted
  via the pinned 2.7.1 roadmap entry)
- **Relates to:** [ADR 0005](0005-m2-rule-type-scope.md) (rule types
  and `[defaults]`), [ADR 0022](0022-line-rule-start-after.md)
  (`start_after`, the previous-byte half of this), [ADR 0023](0023-heredoc-rule.md)
  (heredoc delimiters), `src/grammars/default_scanner.cyr`,
  `src/grammar.cyr`

## Context

The 2.7.1 roadmap entry collected grammar gaps from the 2.5.2 header
cross-check and the 2.6.x audit. Most were data (makefile's `$<`,
ruby / crystal `@@x`, four duplicate list entries) and needed nothing
new. Three needed the scanner to look one step further than it could:

- **A prefix that belongs to the literal after it.** Python `f"{a}"`,
  `rb'\d'`, Rust `b'\n'`, `b"…"`, `r"C:\"`, C `L"wide"`, `u8"…"` came
  out as identifier + string. An identifier rule cannot know what
  follows it.
- **A byte that starts an identifier only in context.** CSS needs `-`
  in `ident_start` for `--var` and `-webkit-x`, which made the `-` in
  `calc(100% - 10px)` a one-byte identifier and `-2px` one identifier;
  SCSS's `$` did the same to `[href$=x]`.
- **A line rule that depends on the byte after its marker.** PHP 8
  `#[Route(...)]` is an attribute, not a comment; Cyrius `#ifdef` /
  `#endif` / `#derive(...)` lines are directives, `# text` a comment.
  ADR 0022 gave line rules a previous-byte condition; nothing looked
  at the next byte.

## Decision

Three grammar keys, each a narrow condition on an existing step — no
new rule type, no new token kind:

- **`[defaults] string_prefixes = [...]`** and
  **`raw_string_prefixes = [...]`** — identifiers that, when a string
  (a pair rule of kind `string`) or, for a plain prefix, a char literal
  starts **immediately** after them, become part of that one string
  token. A raw prefix scans the string with the rule's escape byte off,
  so Rust's `r"C:\"` ends at its quote. Prefixes must be
  identifier-shaped (the loader rejects anything else). Opted in:
  python (`f r b u rb br fr rf`, every case), rust (`b c`; raw `r br
  cr`), c and cpp (`L u U u8`). Out of scope: Rust's `r#"…"#` and C++'s
  `R"d(…)d"` (variable-length delimiters — ADR 0023's heredoc rule is
  where those would go), C#'s `@"…"` / `$"…"` (not identifier-shaped),
  SQL `N'…'`, Julia string macros. *(Amended 2.9.3: the last two are
  in, with Python 3.14's template strings — sql `N n`, julia `raw r b
  v` (Base's macros only), python `t` and the raw `tr` / `rt` in every
  case. All are plain prefixes: in Python and Julia a raw string's
  `\"` still escapes its quote, so the escape-on scan is what ends
  it.)*
- **`[defaults] ident_lead = "<class>"`** — bytes of `ident_start` that
  start an identifier only when the next byte can both start and
  continue one (or is non-ASCII under `unicode_ident`). Otherwise the
  byte falls through to the operator step. Opted in: css (`-`), scss
  (`-$`).
- **Line rules: `followed_by = "<class>"` / `not_followed_by =
  "<class>"`** — the marker counts only when the next byte is (is not)
  in the class. At the end of input there is no next byte:
  `followed_by` fails, `not_followed_by` holds. Opted in: php's `#`
  comment (`not_followed_by = "["`, `#[` becomes punctuation), and
  cyrius's seventeen directive / attribute words — every line-start
  `#word` in the toolchain and the local Cyrius sources: `#ifdef`,
  `#ifndef`, `#endif`, `#else`, `#if`, `#define`, `#derive`,
  `#must_use`, `#inline`, `#host_only` … — each a `preprocessor` line
  rule with `start_after = " \t\n\r"` (most are indented) and
  `not_followed_by = "A-Za-z0-9_"` (so `#if` does not claim `#iffy`).
  A first attempt — `#` followed by any lowercase letter — made a
  mid-line `x #c` comment a directive; cyim's render tests caught it.
  Line rules now compare the marker's first byte inline, so many rules
  sharing `#` cost a byte compare per token.

Two related changes ride along without new keys:

- **Heredoc delimiters are parsed as bash words** — bare, `'…'`, `"…"`
  and `\X` segments concatenated after quote removal, so `<<"E"OF` and
  `<<E\OF` mean `EOF`, `<<''` ends at an empty line, `<<!` and
  `<<END-OF-DATA` are words. A delimiter that quote removal rewrote
  lives in a per-depth scratch slot; a contiguous one still points into
  the input and keeps the drain's terminator watch.
- **Validation:** a heredoc `indent` must be exactly one byte, `escape`
  is accepted only on pair rules, `followed_by` / `not_followed_by`
  only on line rules — each was silently truncated or ignored before.

## Consequences

### Positive

- The roadmap's grammar gaps close without a regex rule or a new rule
  type; each key is a one-byte or one-identifier lookahead on a step
  that already existed.
- The every-offset two-feed split stays clean on all 42 non-compose
  corpora and on nine new 2.7.1 shapes; a prefixed string at a feed's
  end is held like any string that could still grow.

### Negative

- A prefixed string never takes the drain's pending-pair fast path
  (the helpers expect the token to start with its start marker), so a
  very long prefixed string fed in small chunks is re-scanned per drain
  — the 2.8.0 rescan cost, not a correctness issue. *(Amended 2.9.2:
  2.8.0 lifted it — pending-pair detection looks past a declared
  prefix and honours a raw prefix's lack of escapes (stream record
  +168; ADR 0028): a 512 KB `f"…"` in 64-byte chunks went 18.6 s →
  0.01 s.)*
- Token boundaries change in python, rust, c, cpp, css, scss, php,
  cyrius, makefile, ruby, crystal and shell — shipped in a patch, as
  bug fixes, like 2.5.2's.

### When to revisit

- C# verbatim / interpolated strings if a consumer asks (SQL `N'…'`
  landed in 2.9.3) —
  a non-identifier prefix would need the scanner to try it before the
  operator step.
- Rust `r#"…"#` and C++ raw strings with the heredoc-rule extension.
  *(Amended 2.9.5: done — ADR 0030's inline heredoc bodies.)*
