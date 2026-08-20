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

**Checked-in snapshot** (option 1 from the choices captured in
`docs/development/state.md`), decided 2026-04-23.
See [ADR 0001](../../docs/adr/0001-corpus-sync-policy.md) for the
reasoning and when to revisit.

Re-sync manually when vidya updates a sample:

```sh
cp ../../../vidya/content/lexing_and_parsing/shell.sh ./shell.sh
```

## Status

47 corpus files across 46 bundled grammars — `cyml` carries two
(`dependencies.cyml` and `phase_d.cyml`), every other grammar
exactly one. Mix of vidya snapshots (where vidya ships a real
sample — `openqasm.qasm` is the newest, synced in 2.3.5) and
ADR-0006 stand-ins (hand-written `concept.<ext>` files where
vidya coverage is light). Per-grammar provenance is in
[docs/architecture/overview.md](../../docs/architecture/overview.md)'s
"Bundled grammars" table.
