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

### 2.9.6 — Non-identifier string prefixes *(patch)*

- C# verbatim and interpolated strings — `@"…"` (`""` escapes a quote),
  `$"…"`, `$@"…"` / `@$"…"`. Today `@` and `$` are operators before an
  ordinary string. The scanner has to try such a prefix before the
  operator step; an ADR 0027 amendment.

### 2.9.7 — Number shapes *(patch)*

- Leading- and trailing-dot floats (`.5`, `1.`) where the language has
  them, and type suffixes as part of the literal (`1.5f`, `10L`, `2j`,
  `1u32`, `1e5f`) — per-grammar `[defaults]` keys, an ADR 0026
  extension. Ranges (`0..10`) and member access (`1.max`) stay split.

### 2.9.8 — Detection for consumers *(patch)*

- `detect_language_registered(path)` — an additive public function that
  walks the registry's declared `extensions` / `filenames` / `shebangs`
  (ADR 0025), so a consumer that registers its own grammars can route
  them, and one that routes vyakarana's itself can stop: cyim keeps 46
  languages' routing in `src/lang.cyr` and a second name table in
  `src/highlight.cyr`. Public API — an ADR first (CLAUDE.md §Do not).

### 2.9.9 — New grammars *(patch)*

- NASM (it would retake `.asm`, which 2.6.2 stopped claiming, with ADR
  0015's content vote against GAS), MDX, Lean 4 — each with a corpus
  (vidya's sample, or an ADR 0006 stand-in) and the every-offset sweep.
  Shell variants beyond bash / zsh / sh / dash only if one is asked for.

### 2.9.10 — Tokens inside a long, still-open compose region *(patch)*

- Today a `<style>`, fence or cyml body that has not closed yields no
  tokens until it does (ADR 0028's known limit). Make the region
  resumable: the stream remembers the inner grammar and re-scans only
  the body, committing what the inner grammar settles — ADR 0028's
  "when to revisit".
- Done when chunk invariance holds at every offset for the compose
  corpora as now, and a long open region's live buffer and latency are
  bounded by the inner grammar's own, not by the region.

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
