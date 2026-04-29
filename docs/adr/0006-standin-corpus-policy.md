# ADR 0006 — Stand-in corpus when vidya doesn't cover a bundled language

- **Status:** Accepted
- **Date:** 2026-04-23
- **Deciders:** M3 agent (proposed) / user (accepted)
- **Relates to:** [ADR 0001](0001-corpus-sync-policy.md),
  [vyakarana-design-spec.md](../../vyakarana-design-spec.md) §7,
  [roadmap](../development/roadmap.md) M3

## Context

ADR 0001 pegs vyakarana's test corpus to vidya's
`content/lexing_and_parsing/*` via checked-in snapshot. Design-spec
§7 locks the "a grammar passes when it tokenizes its vidya sample
cleanly" bar.

ROADMAP M3's ten-grammar set includes languages vidya doesn't
currently ship reference samples for: json, yaml, markdown,
javascript. Waiting for vidya to add each one before shipping
vyakarana's grammar creates a cross-repo dependency that blocks
M3 indefinitely.

Three paths:

- **(A) Skip unbacked languages from M3.** Ship shell / toml /
  python / typescript / rust / c / cyrius (7 grammars) and defer
  json / yaml / markdown / javascript until vidya covers them.
  Moves the deadline to vidya's timeline.
- **(B) Hand-roll stand-in corpora.** Write a `tests/corpus/concept.<ext>`
  for each unbacked language, modeled on vidya's concept-document
  style. Mark as stand-in. Submit upstream to vidya separately;
  re-sync per ADR 0001 when vidya accepts.
- **(C) Use arbitrary sample files from the internet / existing repos.**
  Smallest-effort but loses the "curated, aligned-with-vidya" property
  that motivated the ADR 0001 choice.

## Decision

Adopt **option B**: hand-rolled stand-in corpora for M3 languages
vidya doesn't yet cover.

Stand-in files live at `tests/corpus/concept.<ext>` (same naming
convention as vidya's `concept.toml`) and are modeled on vidya's
concept-document aesthetic — metadata-rich content describing
lexing/parsing concepts in the target language. Each stand-in carries
a single-line comment (or its closest idiomatic equivalent) marking
it as a vyakarana stand-in:

```
// vyakarana stand-in — not from vidya. See docs/adr/0006.
```

When vidya later adds a reference sample for the language, re-sync
the corpus per ADR 0001 (overwrite the stand-in with the vidya
file) and remove the stand-in marker.

## Consequences

### Positive

- **Unblocks M3.** We can ship all ten grammars at the quality bar
  (zero error kinds + coverage invariant) without waiting for vidya.
- **Aligns with vidya's aesthetic.** Stand-ins are written in the
  same style vidya's samples use, so when vidya eventually adds the
  real sample the transition is small.
- **Upstreamable.** Each stand-in is a candidate PR to vidya. If
  vidya accepts, the cross-repo alignment tightens without any
  vyakarana change beyond the re-sync.

### Negative

- **Two classes of test corpus.** `tests/corpus/` now mixes vidya
  snapshots and stand-ins. Readers need to know which is which —
  the stand-in marker addresses this.
- **Drift risk doubles.** ADR 0001 already flagged drift between
  our snapshot and vidya; stand-ins add the risk that our stand-in
  diverges from an eventual vidya sample.
- **No external validation.** vidya samples are reviewed by vidya's
  curator; stand-ins are self-reviewed. A grammar that tokenizes
  a stand-in cleanly may trip on a real-world sample — but the same
  is true of the vidya samples, so this is a matter of degree.

### How to tell them apart

- Vidya-sourced: `tests/corpus/<name>.<ext>` where `<name>` matches
  vidya's filename (e.g. `shell.sh`, `concept.toml`).
- Stand-ins: same path shape but file contents begin with the
  marker comment cited above. `git log` on the file will show a
  vyakarana-side creation commit (no vidya upstream).

### When to revisit

- **When vidya adds a sample for a stand-in language.** Re-sync,
  remove marker, done.
- **M7 (RC / v1.0).** If any stand-in is still live at RC, the
  polish pass should either upstream the file to vidya or note the
  stand-in status in the release notes.
