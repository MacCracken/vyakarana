# cyrius `include` directive fails on sibling-transitive graph shape

**Filed:** 2026-05-07
**Reporter:** vyakarana 1.0.2 (during pin bump from `5.6.0` → `5.9.32`).
**vyakarana version observed:** 1.0.2 (last patched 2026-04-23 against cyrius 5.6.0)
**cyrius version active at filing:** 5.9.32 (also reproduces on 5.9.33 in-flight)
**Severity:** HIGH for vyakarana (build red on 5.9.x with the
historical include graph; downstream consumers blocked from
picking up new vyakarana tags until either the language is fixed
or the graph is flattened).

## Status timeline

| cyrius | `cyrius build src/main.cyr build/vyk` |
|---|---|
| 5.6.0 (last green per `HANDOFF.md`) | green (per `HANDOFF.md`; not re-validated locally — `cyriusly` does not have 5.6.x installed; earliest available is 5.7.35) |
| 5.9.32 | **FAIL** at `src/tokenize.cyr:16` — `expected '=', got string` |
| 5.9.33 (in-flight, uncommitted in `cyrius/`) | **FAIL** identical |

`cyriusly list` on the dev box shows every patch from 5.7.35
through 5.9.33 installed; 5.6.x is not present, so the regression
window is at least "≤ 5.7.35." Bisecting that window is left for
the language agent (it likely needs only `cyriusly use <ver>` and
running `bisect.sh`).

## Summary

Vyakarana's source layout, unchanged since 1.0.0, has each
non-entry module re-include its dependencies at the top — the
canonical pattern from the design spec / agnosys / sandhi:

```
src/main.cyr            includes token, grammar, tokenize
src/tokenize.cyr        includes token, grammar, shell, default_scanner
src/grammar.cyr         includes token
src/grammars/shell.cyr  includes token
src/grammars/default_scanner.cyr  includes token, grammar
```

On cyrius 5.9.32 this fails:

```
compile src/main.cyr -> build/vyk [x86_64] error:src/tokenize.cyr:16: expected '=', got string
  at fail: fn=398/4096 ident=10260/131072 var=245/8192 fixup=712/32768
FAIL
```

Line 16 of `tokenize.cyr` is `include "src/token.cyr"` — a
syntactically valid top-of-file directive. The error
`expected '=', got string` indicates the parser consumed `include`
as an identifier and expected `= <expr>;`, so the directive lost
its directive status by the time the parser reached it.

## Reproduction

The full reproduction lives at
[`/tmp/cyrius-nested-include-broken/`](/tmp/cyrius-nested-include-broken/)
— self-contained, ~3 KB. Contents:

```
README.md             ← full diagnostic + bisect table + ruled-out hypotheses
bisect.sh             ← runs the seven probes against vyakarana's real sources
leaf.cyr              ← used by failed minimal repros
middle.cyr            ← single-chain nested include (fails to repro)
main_nested.cyr       ← repro 1 — single nested chain (passes; rules out "nested include")
main_flat.cyr         ← control — every dep at top level (passes, returns 42)
main_dup.cyr          ← repro 2 — duplicate include (passes; rules out "duplicate include")
sibling_a.cyr / sibling_b.cyr / main_two_siblings.cyr
                      ← repro 3 — sibling-transitive, fn-only leaf (passes)
leaf_with_vars.cyr / sibling_a_v.cyr / sibling_b_v.cyr / main_two_siblings_v.cyr
                      ← repro 4 — sibling-transitive with var-bearing leaf (passes)
has_fn_then_include.cyr / main_post_fn_include.cyr
                      ← test for "include after first fn def" (passes)
```

To reproduce against vyakarana's real sources:

```sh
cyriusly use 5.9.32
cd /home/macro/Repos/vyakarana
cyrius build src/main.cyr build/vyk        # → FAIL at src/tokenize.cyr:16
/tmp/cyrius-nested-include-broken/bisect.sh
```

## Bisect (smallest failing graph)

The bisect (in `bisect.sh`) confirms the smallest failing top-level
include set in vyakarana's tree:

| probe | top-level includes | result |
|---|---|---|
| 1 | `src/token.cyr` | OK |
| 2 | `src/token.cyr`, `src/grammar.cyr` | OK |
| 3 | `src/token.cyr`, `src/grammar.cyr`, `src/grammars/shell.cyr` | **FAIL** at `shell.cyr:27` |
| 4 | `src/token.cyr`, `src/grammars/shell.cyr` | OK |
| 5 | `src/grammar.cyr`, `src/grammars/shell.cyr` | **FAIL** at `shell.cyr:27` |
| 6 | `src/grammar.cyr` | OK |
| 7 | `src/grammars/shell.cyr` | OK |

Both `grammar.cyr` and `shell.cyr` themselves do `include
"src/token.cyr"` near the top.

The pattern: probe 5 is two top-level includes whose targets each
*transitively* re-include the same leaf, with no top-level include
of that leaf. When the leaf IS top-level (probe 4), shell's
nested second include of token is fine — even though it is the
second overall include of `token.cyr`. So "duplicate include"
alone is not the trigger.

## Failed minimal-repro attempts (ruled out)

Three structural extractions were tried (all in
`/tmp/cyrius-nested-include-broken/`); none reproduce on cyrius
5.9.32:

1. **Single nested chain** (`main → middle → leaf`) — builds OK.
   Rules out: "any nested include errors."
2. **Duplicate include** (main includes leaf directly AND middle
   which also includes leaf) — builds OK. Rules out: "any
   duplicate include errors."
3. **Sibling-transitive shape** (main → sibling_a → leaf, main →
   sibling_b → leaf — no top-level leaf), with leaf either
   fn-only or carrying module-level `var` declarations — builds
   OK. Rules out: "structural shape alone" and "var redeclaration
   in the leaf."

The trigger evidently involves something about file size,
accumulated parser/preprocessor state, or specific syntactic
content beyond the structural shape. At the failure site:
`fn=398/4096 ident=9983/131072 var=245/8192 fixup=707/32768` —
large but well below limits.

## Best-guess root cause

`expected '=', got string` at the position of `include "..."`
means the parser consumed `include` as an identifier and then
expected an assignment expression. So `include` lost its
directive status by the time the parser reached it. Two
candidate failure modes:

a) **Preprocessor / include resolver state bug** — under specific
   accumulated state, the directive isn't recognized at this file
   offset and the tokens leak through to the parser. Each
   constituent file passes `cyrius check` on its own, so they
   are individually well-formed; it is the combination that
   breaks.
b) **Parser-mode bug** — the parser entered a context where
   directives aren't valid (e.g. an unclosed block) and
   `include` is just an identifier. Earlier content corrupted
   parser state.

The bisect favours (a): each file is individually clean.

## What's needed upstream

1. **Identify the regression window.** `cyriusly` has every patch
   from 5.7.35 through 5.9.33 installed locally; running
   `bisect.sh` against successive `cyriusly use` invocations
   should bracket the introducing version in a few minutes.
2. **Fix or document the include-resolver behaviour.** Either
   restore the prior tolerance (preferred — the canonical
   "modules declare their own deps" pattern is widely used) OR
   document the new constraint as a hard rule and provide a
   migration path for existing consumers (vyakarana, agnosys,
   sandhi, etc.).
3. **Improve the diagnostic.** `expected '=', got string` at an
   `include "..."` line is a misleading error. If the parser is
   meant to reject `include` past some boundary, the error should
   name the boundary explicitly. If `include` was meant to be
   honoured, the message points at the wrong place.

## What vyakarana is doing in the meantime

- **Pin bumped** in `cyrius.cyml`: `cyrius = "5.6.0"` →
  `cyrius = "5.9.32"`. Uncommitted (per CLAUDE.md the user
  handles git).
- **Build remains red on 5.9.32.** `HANDOFF.md`'s "Gates are
  green" line refers to the 5.6.0 era and is now stale; will be
  refreshed once the upstream fix lands or after a graph
  flattening port (see Workaround below).
- **No 1.0.0 cut yet** — the 1.0.0 closeout pass needs gates
  green against the pinned toolchain.

## Workaround at the consumer (not yet applied)

Vyakarana could flatten its include graph: have `src/main.cyr`
include `token.cyr`, `grammar.cyr`, `shell.cyr`,
`default_scanner.cyr`, `tokenize.cyr` directly in dependency
order, and remove `include "src/..."` lines from non-entry
files. This matches the `cyrius/programs/*.cyr` single-file
pattern and avoids the failing graph shape — but loses the
property that each module declares its own deps explicitly,
which is the convention sandhi / agnosys / yukti also use.
**Preferred order is upstream fix.**

## References

- `/tmp/cyrius-nested-include-broken/README.md` — full
  reproducer with diagnostic, ruled-out hypotheses, and bisect
- `/tmp/cyrius-nested-include-broken/bisect.sh` — bisect script
- `vyakarana/cyrius.cyml` — pin `cyrius = "5.9.32"`
- `vyakarana/HANDOFF.md` — claims 5.6.0-era green gates (stale)
- `vyakarana/src/{token,grammar,tokenize,grammars/{shell,default_scanner}}.cyr`
  — the include graph in question
- `cyrius/programs/*.cyr` — canonical single-file include pattern
  the workaround would adopt
