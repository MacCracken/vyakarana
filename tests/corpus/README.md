# vyakarana test corpus

Canonical test corpus for bundled grammars.

## Source of truth

`/home/macro/Repos/vidya/content/lexing_and_parsing/*` — vidya ships
hand-written reference samples for 11 languages (cyrius, rust, c,
python, go, typescript, zig, shell, x86_64 asm, aarch64 asm, openqasm).

A grammar "passes" when:

1. Tokenizing the vidya sample produces zero `error` tokens
2. Concatenating every token's bytes reproduces the sample exactly
3. A hand-audited ~30 tokens per grammar show the expected kinds

## Sync policy (undecided)

See [`HANDOFF.md`](../../HANDOFF.md) §Corpus for four options. M1
agent picks one and records the choice in `../../DECISIONS.md`.

**Recommended for M1:** checked-in snapshot (option 1). Copy
`shell.sh` here when you start M1. Revisit sync automation at M3
when there are ten files to keep aligned.

## Status

Empty at M0 — populate at M1 start.
