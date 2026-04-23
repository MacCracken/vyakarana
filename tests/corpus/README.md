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

## Sync policy

**Checked-in snapshot** (HANDOFF option 1), decided 2026-04-23.
See [`../../DECISIONS.md`](../../DECISIONS.md) for the reasoning
and when to revisit.

Re-sync manually when vidya updates a sample:

```sh
cp ../../../vidya/content/lexing_and_parsing/shell.sh ./shell.sh
```

## Status

- `shell.sh` — snapshot of `vidya/content/lexing_and_parsing/shell.sh`,
  8524 bytes (as of M1).
