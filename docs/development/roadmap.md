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
  [2.6.x](../audit/2026-10-20-2.6.x-closeout-audit.md),
  [2.9.x](../audit/2026-10-21-2.9.x-closeout-audit.md)) are the main
  source.
- **Versioning.** A minor when token boundaries change for some input
  (a consumer can see the difference) or a feature lands; a patch
  otherwise. The CLAUDE.md hardening step runs as a closeout patch,
  over everything since the last one — the sweeps from `scripts/audit/`.
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

None. The 2.9.x audit closed the train that the 2.5.x and 2.6.x audits
pinned; what comes next is the backlog below, taken when a consumer asks,
or a user-directed toolchain catch-up.

---

## Backlog — consumer-driven, no fixed slot

Taken only when a consumer asks; each becomes a pinned minor when it
does.

- **Incremental retokenization** (`retokenize_range`) for live editors
  (cyim). Additive → a 2.x minor; breaking → 3.0.0.
- **New grammars** — a NASM / MASM grammar (would take `.asm`, which
  2.6.2 stopped claiming), MDX, Lean 4, shell variants beyond
  bash / zsh / sh / dash, whatever a consumer needs.
- **Incremental tokens inside a long, still-open compose region** — a
  resumable region that re-scans only its body (ADR 0028's "when to
  revisit"); today such a region commits when it closes.
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
  `1u32`), if a consumer wants them coloured as one token. Also a tuple
  index after `.` in Swift and HCL: `t.0.1` lexes as `t . 0.1`. rustc
  does the same for Rust, which a test holds; whether Swift's lexer
  reads `0 . 1` there is unverified — a per-grammar choice once checked
  (2.9.x audit).
- **Python 3.14 template strings** — `t"…"` (and `tr` / `rt`) are not in
  python's `string_prefixes` yet: data only, ADR 0027's mechanism.
- **Heredoc line-index memory** — 36 bytes per line of the scan buffer
  since 2.9.1 (52 in 2.8.0): line ends could be recomputed from the next
  line's start and the tab-stripped half built only when a `<<-` is
  pending, about 20 bytes a line. Matters only for floods of short lines
  after an opener (a 1 MiB one: 43 MB) — 2.9.x audit.
- **Regex rule type** — only under the constraint above.
- **3.0.0** — only for a consumer-driven contract break (token kinds,
  `Token` layout, the streaming API). None is planned.

---

## Risks

| Risk | Mitigation |
|---|---|
| A grammar needs a distinction the ten kinds cannot express | Defer adding a kind; check whether a theme can distinguish by token text first |
| Consumers want parsing, not tokens | Point them at a parser library; vyakarana stops at tokens |
| Streaming complexity keeps concentrating in the drain (holds, watches, groups, the marker window) | Every drain decision reads scanner-reported state (ADR 0028); every drain change is gated by the every-offset split over all 49 corpora |
| Gates that pass on inputs too narrow to fail — the recurring theme of the 2.3.4, 2.5.2 and 2.6.x audits | Every new gate is shown to fail against the previous release before it ships |
