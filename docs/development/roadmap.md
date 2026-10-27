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
  [2.9.x](../audit/2026-10-21-2.9.x-closeout-audit.md)) are the main
  source.
- **Versioning.** The 2.9.x arc ships the former backlog as patches, as
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

## The 2.9.x arc

The backlog, scheduled (decided 2026-10-21). Smallest and most
data-only first; the two API additions last, as they reopen the most;
a closeout audit at the end. Each entry ships only when the gates are
green and, where it adds a gate, that gate is shown to fail on the
release before.

### 2.9.11 — Incremental retokenization *(patch)*

- An edit API for live editors (`retokenize_range` or an edit-feed
  form): re-tokenize from the first token an edit can affect to the
  first point where the old and new token streams agree again. cyim
  tokenizes whole buffers today, and notes that the streaming fixes
  since 2.4.0 reach it only through this.
- Contract: the result equals tokenizing the edited text from scratch.
  A new gate holds it — every edit at every offset of the corpora —
  shown to fail on a deliberately broken resync. Additive public API —
  an ADR first; breaking would be 3.0.0.

### 2.9.12 — Closeout audit *(patch)*

- The CLAUDE.md hardening step over the arc, with the sweeps from
  `scripts/audit/` over the whole library (their README holds 2.9.1's
  clean numbers) and independent reviewers per area, as the 2.9.x
  audit did.

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
| Streaming complexity keeps concentrating in the drain (holds, watches, groups, the marker window) | Every drain decision reads scanner-reported state (ADR 0028); every drain change is gated by the every-offset split over all 49 corpora |
| Gates that pass on inputs too narrow to fail — the recurring theme of the 2.3.4, 2.5.2, 2.6.x and 2.9.x audits | Every new gate is shown to fail against the previous release before it ships |
| The arc adds public API in patches (2.9.8, 2.9.11) | Additive only, each behind an ADR; a contract break is 3.0.0, not a 2.9.x |
| Resumable regions and incremental retokenization reopen the streaming engine the 2.9.x audit just closed | Last in the arc; each brings its own invariance gate, and the closeout audit follows directly |
