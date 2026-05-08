# 003 — Pair-rule ordering: longer prefixes first

> **Affects:** every grammar that declares more than one
> `match = "pair"` rule whose `start` strings share a prefix.
> Get this wrong and the grammar tokenizes the *shorter* shape,
> silently truncating the longer one.

## What it is

`_ds_try_pair_rules` in `src/grammars/default_scanner.cyr` walks
the grammar's pair-rule list **in declaration order** and takes
the first rule whose `start` string matches the bytes at the
cursor. There is no longest-match resolution across pair rules.

Therefore: if two pair rules have `start` strings where one is a
prefix of the other (e.g. `"` and `"""`), the **longer prefix
must be declared first** in the `.cyml` file. Same holds for
`'` vs `'''`, `<` vs `<!--`, ``\``  vs ``\`\`\` ``, `/*` vs
`/**`, etc.

## Concrete examples

From `grammars/toml.cyml` (introduced in [ADR
0008](../adr/0008-toml-triple-quoted-strings.md)):

```toml
[[rules]]
kind = "string"
match = "pair"
start = "\"\"\""        # 3-byte prefix
end   = "\"\"\""
escape = "\\"

[[rules]]
kind = "string"
match = "pair"
start = "'''"           # 3-byte prefix
end   = "'''"

[[rules]]
kind = "string"
match = "pair"
start = "\""            # 1-byte prefix; declared AFTER the triple
end   = "\""
escape = "\\"

[[rules]]
kind = "string"
match = "pair"
start = "'"             # 1-byte prefix; declared AFTER the triple
end   = "'"
```

If the single-quote rules came first, `'''multi-line content'''`
would tokenize as: empty `string` `''` followed by `multi-line
content` (idents and operators) followed by another empty
`string` `''` followed by error bytes. With the triple-quote
rules first, the whole `'''…'''` span becomes one `string` token.

## Why it's not derivable from code

`_ds_try_pair_rules` uses straightforward `r_i = 0; while (r_i <
n) {…}` iteration with `memeq(src + i, start, slen)`. A reader
sees a loop with no obvious priority — it looks like *any* of the
matching rules might win. The discipline ("the first one wins, so
declare longer prefixes first") is enforced by convention in the
`.cyml` file, not by the matcher.

This is deliberate: the matcher stays simple (no length sort, no
priority field, no implicit re-ordering), and grammar authors
take responsibility for the ordering they want. But that means a
future agent editing a grammar must understand the contract.

## How it differs from operators / punctuation

`_ds_try_exact_list` (used for `[defaults] operators` and
`[defaults] punctuation`) has the same "first match wins, no
longest-match resolution" semantics. Convention there is the same:
**longest entries first** in the `operators = […]` array. Most of
the bundled grammars already do this — see the comment "Operators
in longest-match order" at the top of each grammar's operators
block.

The difference is that operators are usually reviewed as a list
in one place, while pair rules are interleaved with other
`[[rules]]` entries — making the prefix collision easier to miss
when adding a new rule mid-file.

## Pair-vs-line-rule prefix collisions

A subtler hazard: **line rules run at pipeline step 2, pair
rules at step 3.** If a grammar has both a line rule and a pair
rule whose `start` strings share a prefix, the line rule ALWAYS
wins because step 2 fires first. Even declaring the pair rule
in the grammar file before the line rule won't help — the line-
vs-pair priority is wired into the scanner pipeline, not into
the rule list.

The 1.4.0 Lua grammar hit this. Two comment forms:
- `--[[ … ]]` long comment (pair-rule shape).
- `-- … \n` line comment.

The intended fix was "declare `--[[` before `--` so the longer
prefix wins." That's correct for pair-vs-pair (per the section
above), but useless when one rule is a line rule. The line
rule's `--` matched at step 2 and consumed the leading two
bytes of every `--[[` opener, leaving `[[…]]` to fall through
as long-string + body + close-bracket fragments.

**Workaround pattern:** express both forms as pair rules,
declaring the longer prefix first:

```toml
[[rules]]
kind = "comment"
match = "pair"
start = "--[["
end = "]]"

[[rules]]
kind = "comment"
match = "pair"
start = "--"
end = "\n"        # newline as the end marker
```

This is fine — pair rules with a 1-byte end like `\n` are valid
and behave identically to a line rule, except the trailing
newline is part of the comment span rather than a separate
whitespace token. Coverage holds; theme renderers don't care.

When a future grammar has both line and pair forms with a
shared prefix, do this same dance. Don't try to "make line
rules respect pair-rule priority" — that would change the
scanner pipeline order, which is documented as normative in
[architecture note 002](002-scanner-pipeline-priority.md) and
holds across all 23 bundled grammars.

## When it can break (and how to spot it)

- **Adding a new pair rule with a multi-byte start to a grammar
  that already has the single-byte version.** The classic case is
  Rust's nestable `/* … */` block comments — when those land,
  whoever adds them must remember to put them *before* any
  single-`/` operator handling. Today the operator path is at
  step 8, after pair rules at step 3, so the issue is
  pair-vs-pair, not pair-vs-operator.
- **Reordering rules during a refactor.** A "tidy up the
  `.cyml`" pass that alphabetises rules will silently break this
  contract. The gates catch it for the corpora we have; they may
  not catch it for shapes the corpora don't exercise.
- **Adding a third-tier shape.** If a future TOML extension wants
  `""""` (4-quote) for some odd literal, that has to come before
  `"""` in the rule list — and so on for any 5-quote escape
  hatch. Linear nesting is fine; the matcher doesn't care, but
  the author has to.

## Where to verify

When adding a pair rule to a grammar:

1. Check whether the rule's `start` is a strict prefix of any
   already-declared rule's `start` (or vice versa).
2. If yes, ensure the longer prefix appears first in declaration
   order.
3. Add a corpus sample (or a stand-in) that exercises the longer
   shape, so the gates catch any future re-ordering.
4. The grammar header comment should call out the ordering with
   one line — see `grammars/toml.cyml`'s header for the pattern.
