# 0031 — `detect_language_registered`: routing by the registry's declarations

- **Status:** Accepted
- **Date:** 2026-10-27
- **Deciders:** 2.9.8 detection-for-consumers work (proposed) / user
  (accepted via the 2.9.8 roadmap entry)
- **Relates to:** [ADR 0015](0015-content-based-detection.md) (the
  compiled detection surface), [ADR 0025](0025-detection-declared-by-grammars.md)
  (grammars declare their routes; detection stays compiled),
  `src/detect.cyr`, `src/grammar.cyr` (the registry)

## Context

Each grammar declares what routes to it — `extensions`, `filenames`,
`shebangs` (ADR 0025) — and `detect.cyr` compiles the same routes, with
two checks holding them equal. That serves `vyk`. It does not serve a
consumer that registers its own grammars with `grammar_load` +
`registry_add` (owl's user overlay, cyim's loader): the compiled table
cannot know them, so each consumer keeps a routing table of its own —
cyim carries the 46 bundled languages' extensions in `src/lang.cyr` and
a second list of names in `src/highlight.cyr`, and they drifted once
(34 of 45 languages had no grammar loaded, cyim 1.6.2 – 1.8.2).

ADR 0025 rejected driving `detect_language` from the registry: it is
pure and must work before `bootstrap_grammars`, and a consumer grammar
should not claim `.h` without anyone choosing that. Both reasons stand
for the compiled function. Neither rules out a second, explicitly
registry-driven one the consumer chooses to call.

## Decision

Add one public function to `src/detect.cyr`, leaving the compiled three
as they are:

```
detect_language_registered(path, src, src_len)   -> grammar name, or 0
```

It reads the registry (bootstrapping the bundled grammars first, as
`has_grammar` does — a no-op for a consumer that set
`_grammars_bootstrapped` itself) and routes by declarations alone:

1. **Extensions** — the longest declared extension the path ends with,
   case-sensitive (ADR 0025's meaning).
2. **Filenames** — else a declared filename, with ADR 0025's rules: the
   path ends with the name at the start or after `/`, `.`, `-`, `_`, or
   its basename is `<name>.<letter…>` that is not a compression, patch or
   tool suffix (the compiled check's own helper).
3. **Shebangs** — else, when `src` is given (non-zero), the interpreter
   of a `#!` line — after `env` and its options, as the compiled sniff
   reads it — that starts with a declared name (prefix-matched,
   ADR 0025), the longest one.

Ties go to the **first registered** grammar, as `registry_find_by_name`
and fence-tag lookup already do: a consumer that wants its grammar to
win registers it before the bundled ones (owl's overlay does exactly
this). Among the bundled grammars that sends `.s` / `.S` to
`asm_x86_64`, the compiled path answer; the content vote between the two
asm flavours is ADR 0015's and stays in `detect_language_combined`, as
does the signature sniff (`<?xml`), which declares nothing.

The name returned is the grammar's own (`grammar_name`), valid as long
as the grammar is registered. `path` 0 or empty and `src` 0 return 0.

**Agreement.** For the bundled grammars every declared entry routes the
same through both functions — the tests run each through
`detect_language_registered` beside `detect_language` /
`detect_language_from_content`. Where they differ, by design: the
compiled sniff bounds `sh` to three bytes (`shellcheck` is not a
shell), while a declaration is a plain prefix; and the compiled
function is ~34 ns and pure, this one walks every declaration (a few
microseconds) and needs the registry. *(Amended 2.9.12: a third, since
2.9.9 — an `.asm` whose content reads as GNU as goes to the asm grammars
through `detect_language_combined`'s vote, to `nasm`, the declaration,
through this function.)*

## Consequences

### Positive

- A consumer's own grammars route by what they declare, with no table
  of its own; one that only uses the bundled grammars can drop its
  routing table too.
- The declarations already held equal to the compiled routes, so for
  the bundled grammars there is nothing new to keep in step.

### Negative

- Public surface grows by one function — additive, so a patch.
- Two detection paths that can disagree for consumer grammars, by
  design; the CHANGELOG and this ADR say which a caller gets.

### When to revisit

- A consumer needs the content vote or the signature sniff through the
  registered path: a `[grammar]` key would have to declare them first.
