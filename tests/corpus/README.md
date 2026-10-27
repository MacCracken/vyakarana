# vyakarana test corpus

Canonical test corpus for bundled grammars.

## Source of truth

`/home/macro/Repos/vidya/content/lexing_and_parsing/*` — vidya ships
hand-written reference samples for 12 languages (cyrius, rust, c,
python, go, typescript, zig, shell, toml, x86_64 asm, aarch64 asm,
openqasm). Three snapshots come from elsewhere in `vidya/content/`:
`shell_modules.sh` (`module_systems/shell.sh`), `dependencies.cyml`
(`cyrius/`) and `phase_d.cyml` (`cyrius/field_notes/mabda_v3_gpu/`).

A grammar "passes" when:

1. Tokenizing the vidya sample produces zero `error` tokens
2. Concatenating every token's bytes reproduces the sample exactly
3. A hand-audited ~30 tokens per grammar show the expected kinds

## Sync policy

**Checked-in snapshot** (option 1 of the four choices listed in
ADR 0001), decided 2026-04-23.
See [ADR 0001](../../docs/adr/0001-corpus-sync-policy.md) for the
reasoning and when to revisit.

Re-sync manually when vidya updates a sample. From `tests/corpus/`,
this lists each snapshot against its vidya source (`cmp` silent =
current); swap `cmp -s` for `cp` to take the new one:

```sh
V=../../../vidya/content
for f in asm_aarch64.s asm_x86_64.s c.c concept.toml cyrius.cyr go.go \
         openqasm.qasm python.py rust.rs shell.sh typescript.ts zig.zig; do
    cmp -s "$V/lexing_and_parsing/$f" "$f" || echo "differs: $f"
done
cmp -s "$V/module_systems/shell.sh" shell_modules.sh                     || echo "differs: shell_modules.sh"
cmp -s "$V/cyrius/dependencies.cyml" dependencies.cyml                   || echo "differs: dependencies.cyml"
cmp -s "$V/cyrius/field_notes/mabda_v3_gpu/phase_d.cyml" phase_d.cyml    || echo "differs: phase_d.cyml"
```

After a re-sync, run the gates — the every-offset sweep
(`scripts/audit/stream-sweep.sh`) covers every corpus file. At the
2.9.12 audit only `dependencies.cyml` differed: vidya's has grown to
50.7 KB (865 lines), and the 10.6 KB, 233-line snapshot is kept on
purpose (`state.md`, Corpus).

## Status

51 corpus files across 49 bundled grammars — `cyml` carries two
(`dependencies.cyml` and `phase_d.cyml`) and so does `shell`
(`shell.sh`, plus `shell_modules.sh` since 2.6.0 — vidya's
`module_systems/shell.sh`, synced for its five heredocs, which the
`lexing_and_parsing` sample has none of), every other grammar
exactly one. (`fuzz/chunk_invariance.fcyr` also streams this
README as markdown, which is how `state.md` counts 52.) Mix of
vidya snapshots (where vidya ships a real sample — the newest is
`shell_modules.sh`, added in 2.6.0; `state.md`'s Corpus section
says how current they are) and ADR-0006 stand-ins (hand-written
`concept.<ext>` files where vidya coverage is light). Per-grammar provenance is in
[docs/architecture/overview.md](../../docs/architecture/overview.md)'s
"Bundled grammars" table.
