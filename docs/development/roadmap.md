# vyakarana — Roadmap

**Future work only.** What has shipped is in
[`CHANGELOG.md`](../../CHANGELOG.md); where the project stands now is
[`state.md`](./state.md); why things are the way they are is in the
[ADRs](../adr/README.md). When a release ships, its entry is deleted
from this file.

---

## How releases are planned

- **Evidence first.** Each release below is defined by defects and gaps
  already found and reproduced — by an audit, a real-file sweep, a
  consumer — not by guesses at future demand. The closeout audits ([2.5.x](../audit/2026-10-20-2.5.x-closeout-audit.md),
  [2.6.x](../audit/2026-10-20-2.6.x-closeout-audit.md),
  [2.9.x](../audit/2026-10-21-2.9.x-closeout-audit.md),
  [2.9.12](../audit/2026-10-27-2.9.12-closeout-audit.md)) are the main
  source.
- **Versioning.** The 2.9.x arc shipped the former backlog as patches, as
  2.5.2, 2.6.2 and 2.7.1 shipped token-boundary changes: each entry's
  CHANGELOG lists what tokens change, and new public API still needs
  an ADR. Outside an arc: a minor when token boundaries change for some
  input or a feature lands, a patch otherwise. The CLAUDE.md hardening
  step runs as a closeout patch at the end of each arc, with the sweeps
  from `scripts/audit/`.
- **Toolchain catch-ups** are user-directed patch releases at any point
  in the train (pin → re-vendor → gates → byte-identical output A/B).
  They never carry other work.
- **Standing constraints.** The ten-kind palette, the `Token` layout
  and the streaming API change only with an ADR (CLAUDE.md §Do not).
  No regex rule type unless a grammar genuinely cannot be expressed
  without one ([ADR 0005](../adr/0005-m2-rule-type-scope.md)).
  vyakarana stops at tokens; parsing belongs to a parser library.

---

## Scheduled

Nothing. The 2.9.x arc (2.9.1 – 2.9.12) is complete: what it shipped is
in [`CHANGELOG.md`](../../CHANGELOG.md), and its closing audit in
[`docs/audit/2026-10-27-2.9.12-closeout-audit.md`](../audit/2026-10-27-2.9.12-closeout-audit.md).
The known limits a next release could take on are listed in
[`state.md`](./state.md) (Known limits). An entry goes here when the user
schedules one, and each ships only when the gates are green and, where it
adds a gate, that gate is shown to fail on the release before.

---

## Not planned

- **A regex rule type** — only if a grammar genuinely cannot be
  expressed without one (ADR 0005).
- **3.0.0** — only for a consumer-driven contract break (token kinds,
  the `Token` layout, the streaming API).
- **Parsing** — vyakarana stops at tokens.

---

## Risks

| Risk | Mitigation |
|---|---|
| A grammar needs a distinction the ten kinds cannot express | Defer adding a kind; check whether a theme can distinguish by token text first |
| Consumers want parsing, not tokens | Point them at a parser library; vyakarana stops at tokens |
| Streaming complexity keeps concentrating in the drain (holds, watches, groups, the marker window) | Every drain decision reads scanner-reported state (ADR 0028); every drain change is gated by `fuzz/chunk_invariance.fcyr` (all 52 corpora at 8 chunk sizes and two-feed splits every 37 bytes, 92 shapes at every offset) and swept by `stream-sweep.sh`'s every-offset split of every corpus at each audit |
| Gates that pass on inputs too narrow to fail — the recurring theme of the 2.3.4, 2.5.2, 2.6.x, 2.9.x and 2.9.12 audits | Every new gate is shown to fail against the previous release before it ships, and against deliberately broken code |
| A change that reads a construct further than before — to the end of the input — swallows real documents without an error token (2.9.10's fences, the 2.9.12 audit) | `scripts/audit/ab-sweep.sh` over real files before it ships, read by largest token, not only by error count |
| Public API added in patches (2.9.8, 2.9.11) | Additive only, each behind an ADR; a contract break is 3.0.0 |
| A per-token cost added for one grammar's feature slows every scan of that grammar (2.9.5's inline rules, found six releases later) | `scripts/bench-paired.sh` against the arc's first tag, not only the last |
