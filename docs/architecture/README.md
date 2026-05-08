# Architecture

How vyakarana is put together — durable invariants and shape that
hold across releases. Decisions and their rationale live in
[`../adr/`](../adr/); live status (current version, build colour,
in-flight task) lives in
[`../development/state.md`](../development/state.md).

If a claim here would change with a normal release, it belongs in
`state.md`, not here.

## Index

- **[overview.md](overview.md)** — system-level module map,
  frozen public contracts, the bundled-grammar set, and the
  durable invariants that carry across releases.

## Architecture notes

Numbered notes capture invariants and constraints that a reader
**cannot derive from the code alone**. Naming convention:
`NNN-kebab-case-title.md`, zero-padded to three digits, never
renumbered. Each note documents reality (not a decision — that's
an ADR; not a how-to — that's a guide).

| #   | Title                                                                  | Affects                          |
|-----|------------------------------------------------------------------------|----------------------------------|
| 001 | [Coverage invariant](001-coverage-invariant.md)                        | scanner correctness contract     |
| 002 | [Scanner pipeline priority order](002-scanner-pipeline-priority.md)    | every grammar's token output     |
| 003 | [Pair-rule ordering: longer prefixes first](003-pair-rule-ordering.md) | every grammar with multiple-quote shapes |
| 004 | [Theme-palette contract](004-theme-palette-contract.md)                | every consumer rendering vyakarana tokens |
