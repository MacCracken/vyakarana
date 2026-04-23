# ADR 0001 — Corpus sync policy: checked-in snapshot

- **Status:** Accepted
- **Date:** 2026-04-23
- **Deciders:** M1 agent (proposed) / user (accepted)
- **Relates to:** [ROADMAP.md](../../ROADMAP.md) M1, M3

## Context

vidya ships hand-written reference samples for ~11 languages at
`vidya/content/lexing_and_parsing/*`. Those files are the canonical
test corpus for vyakarana's bundled grammars: a grammar "passes"
when its sample tokenizes with zero `error` kinds and holds the
coverage invariant (design-spec §3.2, §7).

vyakarana **cannot** depend on vidya at the build level (design-spec
§11 forbids the cycle — vidya may later consume vyakarana for
rendering in M6). Tests need a deterministic handle on the sample
file without introducing a dependency direction that doesn't exist
at the package level.

Four options were on the table in HANDOFF.md §Corpus:

1. **Checked-in snapshot.** Copy the file into `tests/corpus/` at
   M1 time. Drifts from vidya unless periodically synced.
2. **Git submodule.** `tests/corpus/` as a vidya submodule. Heavy
   for a test fixture; ties CI to a submodule init step.
3. **Build-time pull.** A `scripts/pull-corpus.sh` fetches from vidya
   at CI time. Flexible, but network-dependent.
4. **Path reference (monorepo assumption).** Tests resolve
   `../vidya/content/lexing_and_parsing/shell.sh` if it exists.
   Works locally, breaks in standalone CI.

## Decision

Adopt **option 1 — checked-in snapshot** for M1.

`tests/corpus/shell.sh` is a byte-for-byte copy of
`vidya/content/lexing_and_parsing/shell.sh`, committed to this repo.
Re-sync manually when vidya updates the sample:

```sh
cp ../vidya/content/lexing_and_parsing/shell.sh tests/corpus/shell.sh
```

## Consequences

### Positive

- **Trivially reviewable.** A diff shows exactly what the test corpus
  looks like at the ref being reviewed.
- **CI-portable.** No submodule init, no network, no sibling-path
  assumption.
- **Decouples release cadence.** vidya can update its sample without
  forcing a vyakarana test-output re-snapshot the same hour.

### Negative

- **Drift risk.** If vidya changes `shell.sh` and we don't re-sync,
  tests pass here but may diverge from the vidya reference. The
  mitigation is the M4 theme-palette contract work: when owl starts
  integrating themes, a re-sync check falls out naturally.
- **Doesn't scale.** At 1 file it's fine; at 10 files it's a chore
  and at 20 it's a liability.

### When to revisit

**M3**, when the starter set of ten grammars lands and
`tests/corpus/` holds ~10 files. At that point, evaluate option 3
(build-time pull via `scripts/pull-corpus.sh`) against the
accumulated sync debt. If vidya's sample churn stays low, snapshots
may still be the right answer.
