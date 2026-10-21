# vyakarana — Roadmap

**Future work only.** What has shipped is in
[`CHANGELOG.md`](../../CHANGELOG.md); where the project stands now is
[`state.md`](./state.md); why things are the way they are is in the
[ADRs](../adr/README.md). When a release ships, its entry is deleted
from this file.

---

## How releases are planned

- **Evidence first.** Each pinned release below is defined by defects
  and gaps already found and reproduced — by an audit, a real-file
  sweep, a consumer — not by guesses at future demand. The closeout
  audits ([2.5.x](../audit/2026-10-20-2.5.x-closeout-audit.md),
  [2.6.x](../audit/2026-10-20-2.6.x-closeout-audit.md)) are the main
  source.
- **Versioning.** A minor when token boundaries change for some input
  (a consumer can see the difference) or a feature lands; a patch
  otherwise. The CLAUDE.md hardening step runs as a closeout patch —
  but not after every minor for now: the remaining pinned work (2.8.0
  – 2.9.0) ships first, and **one closeout audit, 2.9.1, covers 2.7.x
  – 2.9.x** (decided 2026-10-20).
- **Toolchain catch-ups** are user-directed patch releases at any point
  in the train (pin → re-vendor → gates → byte-identical output A/B).
  They never carry other work.
- **Standing constraints.** The ten-kind palette, the `Token` layout
  and the streaming API change only with an ADR (CLAUDE.md §Do not).
  No regex rule type unless a grammar genuinely cannot be expressed
  without one ([ADR 0005](../adr/0005-m2-rule-type-scope.md)).
  vyakarana stops at tokens; parsing belongs to a parser library.

---

## Pinned releases

### 2.8.0 — Streaming engine *(minor)*

- **Long non-pair tokens are re-scanned on every drain.** Only pair
  rules have the pending fast path; a 512 KB line comment in 64-byte
  chunks takes 4 s, a 512 KB identifier 10 s, a 400 KB token 6.5 s.
  Generalise the fast path to line rules, identifiers, whitespace and
  numbers — or replace the rescan-and-commit drain with a state machine
  that scans only new bytes.
- **Compose-grammar chunk invariance** — markdown, html, vue, svelte,
  cyml. Needs prefix-hold restructured so it stops reading the commit
  list as state (three patch attempts in 2.4.0 regressed). Fixes the
  residual O(N^1.6) compose drains with it.
- **Heredoc terminator search** (2.6.x audit): the per-call budget
  scales with the buffer, so on pathological input (hundreds of
  distinct unterminated `<<` openers, or a few multi-line arithmetic
  shifts) a stream that compacted earlier bytes away gives up sooner
  than a single feed and a later heredoc comes back as code. Index the
  buffer's lines once per scan and look terminators up instead of
  searching — no budget, so no divergence.
- **Heredoc watch costs** (2.6.x audit): a mode-2 hold (an opener
  followed by a string spanning many lines) re-scans the held bytes at
  every new line break; the terminator watch resumes at the start of a
  long partial line (a 1 MiB one-line body in 512-byte chunks, 5.5 s).
  Both bounded by `VYK_HEREDOC_HOLD_MAX`; both fold into the same
  state-machine work.
- Exit: `fuzz/chunk_invariance.fcyr` covers all 46 corpora; the
  every-offset split is clean on all 46.

### 2.9.0 — Size and tooling *(minor)*

- **Binary size.** The default `vyk` is ~490 KB and the DCE build
  (what releases ship) ~400 KB, against 1.13.0's 300 KB soft cap. The
  cheapest lever: strip comments when embedding — the blobs carry each
  `.cyml` verbatim and most of their ~232 KB is comment text. Then
  revisit the cap or the blob encoding (ADR 0014).
- Replace `scripts/embed-grammars.sh` — its escaping is gawk-only
  (`gsub` backslash doubling is a no-op under POSIX awk) — with
  cyrius's `[embed]` manifest section (6.6.19) or a POSIX rewrite.
- Real-corpus mutation fuzz over vidya snapshots; fold the audits'
  sweep scripts (real-file coverage sweep, poison A/B, every-offset
  split, the 2.6.x heredoc harness) into `scripts/` so the next audit
  reruns them instead of rebuilding them.
- Script the loaded-host latency protocol (short runs, alternating
  versions, paired ratios — `performance.md`) so every refresh uses it.

### 2.9.1 — Closeout audit *(patch)*

- The CLAUDE.md hardening step over everything 2.7.0 – 2.9.0 changed
  (number literals, grammar polish, the streaming engine, size and
  tooling), with the empirical sweeps re-run over the whole library —
  by then from `scripts/`, not rebuilt by hand. No 2.7.x or 2.8.x
  closeout before it.

---

## Backlog — consumer-driven, no fixed slot

Taken only when a consumer asks; each becomes a pinned minor when it
does.

- **Incremental retokenization** (`retokenize_range`) for live editors
  (cyim). Additive → a 2.x minor; breaking → 3.0.0.
- **New grammars** — a NASM / MASM grammar (would take `.asm`, which
  2.6.2 stopped claiming), MDX, Lean 4, shell variants beyond
  bash / zsh / sh / dash, whatever a consumer needs.
- **Consumer-routed detection** — an additive
  `detect_language_registered(path)` that walks the registry, if a
  consumer wants vyakarana to route its own grammars
  ([ADR 0025](../adr/0025-detection-declared-by-grammars.md)).
- **Literal shapes ADR 0027 left out** — variable-length delimiters
  (Rust `r#"…"#`, C++ `R"d(…)d"`, Lua `[==[…]==]`, Ruby `<<~EOS`, PHP
  `<<<EOT`, Swift `#"…"#`; ADR 0023 says extend the heredoc rule),
  non-identifier string prefixes (C# `@"…"` / `$"…"`), SQL `N'…'`,
  Julia string macros.
- **Number shapes ADR 0026 left out** — leading- / trailing-dot floats
  (`.5`, `1.`) and suffixes as part of the literal (`1.5f`, `2j`,
  `1u32`), if a consumer wants them coloured as one token.
- **Regex rule type** — only under the constraint above.
- **3.0.0** — only for a consumer-driven contract break (token kinds,
  `Token` layout, the streaming API). None is planned.

---

## Risks

| Risk | Mitigation |
|---|---|
| A grammar needs a distinction the ten kinds cannot express | Defer adding a kind; check whether a theme can distinguish by token text first |
| Consumers want parsing, not tokens | Point them at a parser library; vyakarana stops at tokens |
| Streaming complexity keeps concentrating in the drain (pending fast path, marker window, compose prefix-hold, heredoc hold and watch) | 2.8.0's state-machine work; until then every drain change is gated by the every-offset split over all non-compose corpora |
| Gates that pass on inputs too narrow to fail — the recurring theme of the 2.3.4, 2.5.2 and 2.6.x audits | Every new gate is shown to fail against the previous release before it ships |
