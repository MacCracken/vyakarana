# vyakarana — current state

> **Last refresh:** 2026-08-20 | **Refresh cadence:** every release
> (1.x and 2.x cuts), plus any session that shifts the gates'
> colour or the active task.
>
> **Read this file before doing anything.** 1.0.0–2.4.0 are
> shipped. **2.4.0 is the streaming-correctness cut** — minor
> because token boundaries change. Chunked feeding now produces the
> same tokens as a whole-buffer feed for **15 of 20 corpora**, up
> from 7; `fuzz/streaming.fcyr` has asserted that contract since
> 2.1.4 and passed the whole time, because its inputs were short
> synthetic strings while 13 of 20 real corpus files violated it.
> Five independent root causes, each bisected to an exact token.
> `VYK_STREAM_CAP` is a live-window bound again (an unresolved
> compose opener used to turn it into a permanent total-input
> ceiling), and [ADR 0021](../adr/0021-token-span-width-ceiling.md)
> settles the token-width question. **Still divergent by design:**
> markdown, html, vue, svelte, cyml — see §Next up.
> **2.3.5 adds the `openqasm` grammar** (46 bundled, was
> 45) — the one sample in `vidya/content/lexing_and_parsing/` that
> `vyk` could not tokenize, exiting 4 while the other 11 round-
> tripped clean. vidya renders those samples *through* vyakarana,
> so it was a live consumer gap. Corpus is an ADR-0001 sync, not an
> ADR-0006 stand-in. 909/909 tests. 2.3.5 also cleared the
> documentation drift 2.3.4's audit found but had no room for —
> grammar counts, note 002's pipeline table, the ADR index,
> `agnoshi` as a phantom consumer, and several grammar headers
> filing shipped work under "Known gaps".
> **2.3.4 was the hardening + security sweep** — the first
> full audit since 2.1.x; all of 2.2.x and 2.3.x had shipped without
> one. 14 defects fixed, reproductions in
> [`../audit/2026-08-20-2.3.x-hardening-audit.md`](../audit/2026-08-20-2.3.x-hardening-audit.md).
> Headlines: `vyk` **silently truncated** any file over 1 MiB
> (exit 0, 30% of a 1.5 MB file dropped); streaming a document with
> an embedded `<style>`/fence block was **near-cubic and hung**
> (32 KB: 19.6 s → 89 ms, 221×); chunked streaming **closed strings
> on escaped quotes**; and `#!/bin/bash -e` — any shebang with an
> interpreter argument — **failed detection entirely**. Also a
> one-byte OOB read in `_ds_scan_tag`, the u32 offset wrap past
> 4 GiB, and FINDING-002/003 closed after four months open.
>
> **Two things to carry forward.** (1) Silent degradation was the
> default failure mode everywhere — oversize input, oversize
> grammars, failed `alloc`, wrapped offsets all produced plausible
> wrong output with exit 0. (2) The gates asserted the right things
> on inputs too narrow to exercise them: `fuzz/streaming.fcyr` has
> asserted chunk-invariance since 2.1.4 and passes, while **9 of 14
> real corpora violate it** (see §Next up). Same root cause the
> 2.3.2 `TK_ERROR` audit named. **2.3.3 was the toolchain catch-up** — pin 6.5.4 →
> 6.5.32, `lib/` re-cut at the new pin, and no source-behaviour
> change: no token kind, no `Token` layout change, no public-API
> change, no grammar edit. The bump is measurably inert — the
> same tree built with 6.5.4's and 6.5.32's `cycc` is
> **byte-identical** (396,888 both) and benches within noise on
> all eight rows; the only movement is the stdlib snapshot
> (+4,416 bytes). 898/898 tests. **It also turned the `lint+fmt`
> gate green for the first time** — that gate exited **1** at
> 2.3.2 and at each of the six commits before it, so the
> "lint+fmt exit 0" line this file carried at 2.3.2 was wrong
> the day it was written. (Second time that has happened here;
> see the 2.3.0 note below about the 840/840 claim. Re-run the
> gates; do not carry a "green" claim forward.)
> **2.3.2 closed the `TK_ERROR` holes** — a sweep of
> every printable ASCII byte through all 45 grammars found 44
> emitting `TK_ERROR` for at least one character, and 37 of them
> had a genuine gap ([ADR 0020](../adr/0020-tk-error-adjudication.md)
> records how each character was adjudicated). Backtick command
> substitution in `shell` / `ruby`, Go raw-string struct tags,
> AT&T-syntax `$` immediates in `asm_x86_64`, Haskell `$`,
> JS/TS `#` and `@`, C# `#if`, Zig `\\` multiline strings and
> free text in `html` / `xml` / `yaml` were all error tokens.
> 898/898 tests. **2.3.1 makes CYML parse as CYML** — its markdown
> bodies now route to the markdown grammar through the new
> `compose_region` rule type ([ADR 0019](../adr/0019-compose-region-rule.md)),
> where 1.9.0–2.3.0 merged TOML and markdown into one rule set
> and mis-typed body headings and fenced code blocks. The same
> cut fixed `markdown` emitting `TK_ERROR` for `"`, `'` and `$`,
> which had made this repo's own `README.md` exit 1. 850/850
> tests. **2.3.0 was the toolchain catch-up** — pin 6.1.24 →
> 6.5.4, four minor lines in one step — and it cleared two
> pre-existing gate failures on the way: a vestigial `cyml` entry
> in `[deps] stdlib` that made `cyrius deps` exit 1 on a fresh
> checkout, and eleven `duplicate variable` names that stopped
> `tests/vyakarana.tcyr` compiling at all. Both reproduce under
> the *outgoing* 6.1.24 pin — neither is a 6.5.4 regression.
> **The test gate is green at 840/840 on 6.5.4. It was RED at
> 2.2.2 and 2.2.3** — the suite did not compile under either pin
> (6.0.3 and 6.1.24 both reject the duplicates), so the
> "840/840 passing on 6.1.24" line this file carried was wrong
> the day it was written. Do not carry any pre-2.3.0 "green"
> claim forward without re-running the gates. (2.2.3 was pin
> 6.0.3 → 6.1.24; 2.2.2 was the modernization cut: pin 5.10.5 →
> 6.0.3, vendored `lib/` moved to the `cyrius deps` model —
> gitignored, ADR 0018.) No public-API, token-layout, or grammar
> changes. 46 bundled grammars; 4 fuzz harnesses. No work
> currently in flight. See §Next up.
>
> **Where to find what.** Architecture (system map, frozen
> contracts, durable invariants): [`../architecture/`](../architecture/).
> Decision rationale: [`../adr/`](../adr/). Design context:
> [`../../vyakarana-design-spec.md`](../../vyakarana-design-spec.md).
> Milestones: [`./roadmap.md`](./roadmap.md). Process and rules:
> [`../../CLAUDE.md`](../../CLAUDE.md).
>
> *(This file used to live at the repo root as `HANDOFF.md`.
> Renamed 2026-05-08 to match the AGNOS first-party docs
> standard, which puts live state in `docs/development/state.md`.
> "What is frozen", "Where the code lives", and "Invariants that
> carry forward" moved to `../architecture/overview.md` the same
> day.)*

---

## Current status (2026-08-20)

- **Version:** `2.4.0` in `VERSION`, `src/version_str.cyr`, and
  `dist/vyakarana.cyr`.
- **Toolchain pin:** `cyrius = "6.5.32"` (bumped from 6.5.4 in
  2.3.3; 6.5.4 came from 6.1.24 in 2.3.0). Local devs run
  `cyriusly use 6.5.32`.
- **Gates:** build OK · **909/909** tests · smoke OK · **lint+fmt
  exit 0** · fuzz **5/5** · 0 untracked deferrals. **46 grammars.** `scripts/smoke.sh`
  gained two regression groups in 2.3.4 (oversize input must fail
  loudly; shebangs with interpreter arguments must route) — both
  verified to fail against the pre-fix binary.
- **Chunk-invariance: 15 of 20 corpora clean** as of 2.4.0, gated
  by `fuzz/chunk_invariance.fcyr` at 8 chunk sizes. Still
  divergent, deliberately: **markdown, html, vue, svelte, cyml** —
  the compose grammars. The marker window that fixed the rest
  cannot be applied to them without breaking the compose
  prefix-hold interaction (three attempts, each regressed the
  markdown/fence-rust fuzz case). Coverage never breaks in any
  case; only boundaries move. **Top follow-up** — see §Next up.
- **`lib/` is inert at build time.** On 6.5.32 `cycc` resolves
  stdlib from `~/.cyrius/versions/<pin>/lib`, so the **pin** —
  not the vendored `lib/` — decides what is compiled. Verified
  by appending garbage to `lib/str.cyr` and rebuilding: still
  `OK`. Changing only the pin moves the binary 392,472 →
  396,888. Keep `lib/` synced anyway (it silences the `shadow
  lib` warning and CI populates it fresh), but do not treat it
  as the thing under test. CLAUDE.md's §Gates note used to claim
  the inverse; corrected in 2.3.3.
- **Bench note (2.3.2):** `blob/grammar-load-shell` moved
  33.2 → 36.7 µs (+10.5%) against the 2.3.0 table in
  `./performance.md`. Expected and accounted for: `shell.cyml`
  gained a pair rule and `unicode_ident`, and the embedded blob
  set grew 206,394 → 217,790 bytes across the 37 edited
  grammars, so there is simply more grammar text to parse per
  load. Inside CLAUDE.md's 20% watch threshold, and it is a
  once-per-process cost, not a per-token one. The four tokenize
  rows — the hot path consumers actually run — are all
  fractionally *faster*. Table not refreshed: the documented
  cadence is minor-release boundaries, and this is a patch.
- **What 2.4.0 changed (streaming correctness):**
  - **Chunk-invariance restored for 15 of 20 corpora** (was 7).
    Newly clean: python, rust, go, css, toml, sql, xml, ruby. Five
    independent root causes, each bisected to an exact token in a
    real corpus file — the LF fallback committing block comments
    early; longest-match operator tables merging across the
    boundary; rule START markers needing the same window; a short
    pair rule vouching for a long rule's token; and pending being
    set on an already-closed token. Details in CHANGELOG 2.4.0.
  - **`VYK_STREAM_CAP` is a live-window bound again.** An
    unresolved compose opener used to stop the buffer compacting,
    so the cap became a *total-input* ceiling and feed returned
    `VYK_ERR_OVERFLOW` permanently. `VYK_COMPOSE_HOLD_MAX` (8 MiB)
    bounds the hold; past it, compose routing for that opener is
    abandoned and the bytes tokenize with the outer grammar.
    Verified: 26 MB accepted either way, buffer compacts to 1.
  - **`fuzz/chunk_invariance.fcyr`** gates the contract over
    `tests/corpus/` at 8 chunk sizes. Verified to fail against the
    2.3.5 tokenizer, so it has teeth.
  - **[ADR 0021](../adr/0021-token-span-width-ceiling.md)** decides
    the token-width question: stay u32, 4 GiB per stream is a
    documented enforced contract. Both widening options were
    considered and rejected with reasons.
  - **Known limit, deliberate:** the marker window is applied only
    to grammars with no compose rules, so markdown / html / vue /
    svelte / cyml remain divergent. Three attempts to reconcile it
    with the compose prefix-hold machinery each broke the
    markdown/fence-rust fuzz case, so per CLAUDE.md §Refactoring
    policy it is scoped rather than forced. Top item in §Next up.

- **What 2.3.5 changed:**
  - **`openqasm` grammar** (2.0 + 3.x keyword span). Registered in
    `bootstrap_grammars`, `_detect_5plus` (`.qasm`), the smoke
    language list and corpus loop, and `fuzz/grammar_load.fcyr`'s
    blob count (45 → 46). Gate names stay `ident` per ADR 0004;
    `pi` is a keyword. Zero error tokens, coverage exact on the
    synced vidya sample.
  - **Doc drift from the 2.3.4 audit, cleared.** `tokenize.cyr`'s
    public-symbol list (it wrongly listed the live
    `tokenize_source_handcoded` as removed, and omitted the whole
    pull adapter — and CLAUDE.md now points at that list);
    architecture note 002's pipeline table (missing
    `compose_fenced` / `compose_region`); the ADR index stopping at
    0009; `agnoshi` as a phantom consumer; `SECURITY.md`'s trust
    boundary naming a removed function; and grammar counts across
    nine files. Historical references were left alone — only
    present-tense claims changed.
  - **Deferral cleanup, round two.** `state.md` still asked for a
    `char_literal` default that shipped in 1.2.1; `lua.cyml` and
    `elixir.cyml` filed shipped features under "Known gaps";
    `html.cyml` proposed a "regex-y" fix the design spec rules out
    by name; M4 was unmarked beside two "Landed" siblings.

- **What 2.3.4 changed (hardening + security sweep):**
  - **Four P1s**, all reproduced before fixing: the 1 MiB silent
    truncation, the near-cubic compose-hold hang, escaped-quote
    string closure under chunking, and shebang-with-arguments
    detection failure.
  - **Six P2s**, including a one-byte OOB read in `_ds_scan_tag`
    (public `tokenize_with_grammar` is exposed; `vyk` masked it by
    NUL-terminating), the u32 offset wrap, oversize-grammar
    truncation, and the `alloc()`-unchecked family.
  - **The audit ledger itself was defective.** FINDING-005 (u32
    token fields) was mislabeled in the 1.13 and 2.1.x carryover
    tables as a `_sanitize_for_stderr` issue — which is *also* not
    a real defect; the sanitizer replaces control bytes, it does
    not truncate. So the real finding fell out of tracking and was
    never re-rated when 2.0.0's streaming rewrite invalidated its
    "practical file sizes don't approach this" premise. Carryover
    tables must copy titles verbatim from now on.
  - **Deferral-language audit** (explicitly requested): 10 stale
    grammar-header claims removed after verifying each against the
    same file's own rules, 6 misphrased permanent decisions
    reworded, 4 stale `tokenize_source` references corrected.
    Blob shrank 217,790 → 215,902 bytes.

- **What 2.3.3 changed (toolchain catch-up):**
  - **Pin 6.5.4 → 6.5.32**, four minor lines in one step, with
    **zero dialect fixes needed in `src/`**. Contrast 2.3.0,
    where the equivalent jump cleared two pre-existing gate
    failures on the way.
  - **`lib/` re-cut** with `rm -rf lib && cyrius deps` — a plain
    `cyrius deps` treats a present `lib/<mod>.cyr` as satisfied.
    All 27 vendored modules match the 6.5.32 snapshot; 17 changed
    content (`alloc`, `args`, `assert`, `atomic`, `fmt`, `fnptr`,
    `fs`, `io`, `result`, `string`, all seven `syscalls*`).
  - **The bump is inert, and that was measured, not assumed.**
    Same tree under both compilers → byte-identical binaries and
    bench agreement within noise. Attribution for the +4,416-byte
    binary growth is the 6.5.32 stdlib snapshot, not codegen.
  - **`dist/vyakarana.deps` is new** — 6.5.32's `cyrius distlib`
    emits a stdlib-leaf sidecar next to the bundle (6.5.4's did
    not). It is consumed by downstream `cyrius deps`, so it ships
    with `dist/vyakarana.cyr`; **needs `git add`** on this cut.
  - **`lint+fmt` went red → green.** Three files had failed
    `fmt --check` since at least `09111d0`; the drift reproduces
    under the outgoing 6.5.4 formatter, so it was never a 6.5.32
    regression. Whitespace only — 26 lines of continuation
    indent. `src/theme.cyr:24`'s untracked `for now` deferral was
    reworded, so `cyrlint` is quiet too.

- **What 2.3.2 added (`TK_ERROR` hole audit):**
  - **37 grammars stopped erroring on valid syntax**
    ([ADR 0020](../adr/0020-tk-error-adjudication.md)). A
    printable-ASCII sweep (0x20–0x7E) through all 45 grammars
    found 44 with at least one `TK_ERROR` hole; each character
    was then adjudicated per language, because the same byte is
    a raw string in Go, a command literal in Ruby, an escaped
    identifier in Kotlin and genuinely invalid in C.
  - **Delimited regions got rules, not bare operators** — Go raw
    strings, Kotlin / Swift / MySQL backtick identifiers, Elixir
    charlists, Zig `\\` multiline strings, and shell / ruby /
    crystal / php / makefile / dockerfile command substitution
    (`kind = "string"`, per the precedent `julia.cyml` set).
  - **Missing operators added** — Haskell `$`, Rust `@`, Julia
    `'`, JS/TS `#` and `@`, C# and Swift `#`, Swift `\` key
    paths, scss `%` (the css fix from 2.1.1 that scss missed),
    css/scss `\`, nix `~`, powershell `\`, graphql `.`/`+`/`-`,
    llvm_ir `$`, toml `:`, and `'`/`\` char-literal fallbacks
    across the C-family (ADR 0010 models only `'C'` / `'\C'` /
    `'\xHH'`, so `'A'` fragmented).
  - **`unicode_ident` added to six grammars** — javascript,
    typescript, python, rust, shell, yaml. `const café = 1` was
    two error tokens. Non-ASCII half of the same bug class,
    outside the ASCII sweep that found the rest.
  - **The corpora are why this survived twelve minor releases.**
    One canonical sample per grammar means a shape the sample
    lacks is a shape the gates never tested.
    `tests/corpus/asm_x86_64.s` is `.intel_syntax noprefix` —
    zero `$` bytes — so AT&T immediates, the dominant real-world
    x86-64 dialect, were never tokenized once. Real GNU as from
    `/usr/lib` produced 91 errors in one file; it is 0 now.
  - 48 new probes (850 → 898) plus corpus additions to 29
    ADR-0006 stand-ins; verified load-bearing by reverting
    `grammars/ruby.cyml` and watching smoke fail.
  - **Left erroring on purpose:** `c`, `cyml`, `cyrius`, `json`,
    `lua`, `protobuf`, `terraform` — 8 of 45 counting `markdown`,
    fixed in 2.3.1. `python`'s ASCII rejections stand too; it was
    edited only for `unicode_ident`. Negative probes pin that half.
  - **Open (not operator-list gaps):** Rust's nestable `/* */`
    block comments — backticks inside doc comments still error —
    and the variable-length-delimiter shapes below.
- **What 2.3.1 added (CYML composition):**
  - **`match = "compose_region"` rule type**
    ([ADR 0019](../adr/0019-compose-region-rule.md)). Routes an
    open-ended region through a named grammar. Its `end_before`
    is a *lookahead* terminator left unconsumed for the outer
    grammar, and hitting EOF without it is a normal ending — the
    two things ADR 0013's `compose` cannot do, and both of which
    CYML needs. `GRAMMAR_SIZE` 176 → 184 for the new vec.
  - **`grammars/cyml.cyml` migrated to it.** Bodies route to
    markdown, so a body `# Heading` is a heading rather than a
    TOML comment, and a fence reaches markdown's `compose_fenced`
    and routes on to the tagged grammar — ` ```cyrius ` inside a
    CYML body yields real keywords, two levels deep. The grammar
    had named composition as the fix since 1.9.0; composition
    landed in 1.11.0 and cyml was never migrated.
  - **`grammars/markdown.cyml` prose fix.** `"`, `'` and `$` were
    in neither the operator nor the punctuation list and fell
    through to `TK_ERROR`; `README.md` tripped it 8 times and
    `CONTRIBUTING.md` 21. Pre-existing and independent — found
    only because routing CYML bodies to markdown surfaced it.
  - **`---` in CYML is now `punctuation`, was `operator`** — it
    is a region start marker now. The cut's one visible
    token-output change.
  - `tests/corpus/phase_d.cyml` (vidya snapshot, ADR 0001) plus
    ten `tcyr` probes. The old corpus had neither a body heading
    nor a fence, which is exactly why twelve minor releases of
    green gates proved nothing here.
  - **Open at the time:** a sweep of every printable ASCII byte
    through all 45 grammars found 44 with at least one
    `TK_ERROR` hole. Some are correct (a backtick really is
    invalid in C); some are not — backtick command substitution
    is standard `shell` and `ruby`. Only `markdown` was fixed
    here. **Closed in 2.3.2** — see above and ADR 0020.
- **What 2.3.0 added (toolchain catch-up):**
  - **Toolchain pin `6.1.24` → `6.5.4`.** Four minor lines in
    one step. Every remaining declared stdlib module resolves;
    build / test / smoke / lint / fmt all green, plus `cyrius
    fuzz` 4/4 and `cyrius bench` 8/8 rows flat-or-faster against
    the 2.2.1 baseline — well inside the 20% watch threshold.
    Minor rather than patch because the bump needed source
    changes; see the next two bullets.
  - **`cyrius deps` fixed on a fresh checkout.** `[deps] stdlib`
    listed `"cyml"`. The module still exists — 6.1.24 folded it
    into the `bayan` bundle, where its 17 `cyml_*` symbols live
    now — but the standalone `lib/cyml.cyr` that the deps list
    resolves against is gone (present at 6.1.23, absent at
    6.1.24), so `cyrius deps` exited 1. The entry was vestigial
    either way — zero `cyml_*` symbols anywhere in the repo; the
    grammar loader parses `grammars/*.cyml` with its own
    purpose-built scanner in `src/grammar.cyr`. Removed rather
    than re-pointed at `bayan`, which would vendor an unused
    module. **2.2.3's own pin move is what broke it**, so from
    that cut on CI's resolve step could not have passed on a
    clean checkout; the local build only survived because the
    stale `lib/` held the last copy of `cyml.cyr`.
  - **The test suite compiles again.** `tests/vyakarana.tcyr` is
    one 3,100-line `fn main()` (lines 48–3152), and Cyrius
    rejects a second `var NAME` bound in the same lexical block —
    eleven names were re-declared across test sections. Renamed
    the *later* declarations to section-scoped names:
    `tb_c1-3` / `src_c1-3` → `tb_css1-3` / `src_css1-3` (CSS),
    `gc` → `gc_st` (stress), `tb_r1-3` → `tb_sr1-3` (streaming),
    `saw_arrow` → `saw_tf_arrow` (Terraform). Pure renames — no
    assertion, input, or expected value changed. **2.2.2 and
    2.2.3 both shipped with a red test gate** — their pins,
    6.0.3 and 6.1.24, reject the duplicates identically
    (re-verified against both installed snapshots). The
    duplicate lines themselves accumulated across the
    1.7.0–2.1.3 commits of 2026-05-08 (the six CSS names
    landed first, at 1.7.0 — `var tb_c1` goes 1 → 2 between
    `git show 1.6.0:` and `1.7.0:`); 2.2.0's CHANGELOG
    records 836/836 on 5.10.5 with those lines already in the
    file, but 5.10.5 is no longer installed, so that green is
    unverifiable. 840/840 is the first green run this file can
    vouch for.
  - **Vendored `lib/` re-cut from the 6.5.4 snapshot.** What was
    on disk was a 6.0.x-vintage tree older than even the 6.1.24
    pin: `cyrius deps` treats an already-present `lib/<mod>.cyr`
    as satisfied and never refreshes it, so the pinned stdlib had
    been silently ignored at build time since 2.2.2. Plain
    `cyrius deps` will not fix it — refreshing takes `rm -rf lib
    && cyrius deps`.
  - **`agnoshi` dropped from `cyrius.cyml`'s `[lib]` consumer
    comment.** It is not a consumer and never was. The three
    repos that actually declare `[deps.vyakarana]` are `owl`,
    `cyim`, and `vidya` — all currently pinned at `tag =
    "2.2.3"`.
  - **Nothing to chase downstream.** `dist/vyakarana.cyr` is
    byte-identical to the 2.2.3 bundle apart from its version
    header line (`git diff`: 1 insertion, 1 deletion) — 348,582
    bytes, 4,030 lines by `wc -l` (`cyrius distlib` misreports
    4002; trust `wc -l`). `build/vyk` is 371,472 bytes
    (362.8 KB), *down* 19,312 bytes from the 2.2.1 capture — with
    342 unreachable fns (58,238 bytes) still riding along in that
    total. DCE is opt-in: the default build only reports them,
    and `CYRIUS_DCE=1` NOPs them without changing the size (same
    371,472 bytes, 58,195 of them different). No public-API,
    token-layout, or grammar changes; 45 grammars unchanged.
  - **Toolchain deltas worth knowing** (6.1.24 → 6.5.4; zero
    stdlib functions were *removed* from any module vyakarana
    declares, and the only signature changes add `: Str` to
    `lib/fs.cyr` path helpers we never call): a wrong argument
    count is a hard error since 6.5.1 (was a warning that still
    emitted a binary); a call to a reachable undefined fn is a
    hard error since 6.3.2; `cyrius distlib` exits 1 on a missing
    `[lib] modules` entry since 6.2.52, so
    `scripts/embed-grammars.sh` **must** run before it; the
    initialized-globals cap per compilation unit is 4096, was
    1024 (6.3.41); a bare **top-level** `var X[N]` is `N*8` bytes
    while a function-local `var buf[N]` is still N bytes
    (6.4.10); `&&` now binds tighter than `||`, which were equal
    precedence before (6.3.36); `public` / `private` are
    file-scoped and now reserved keywords (6.5.0). distlib's
    per-module read cap went 256 KB → 1 MB —
    `src/grammar_blobs.cyr` is 204,240 bytes, 78% of the old cap,
    so that is real headroom won.
- **What 2.2.3 added (toolchain pin bump):**
  - **Toolchain pin `6.0.3` → `6.1.24`.** No grammar,
    token-layout, or public-API changes. The original entry here
    claimed all declared stdlib modules resolved and all five
    gates were green — **neither held.** `cyrius deps` exited 1
    on `cyml` and `cyrius test` did not compile at that pin;
    2.3.0 found both. Left in place as history, corrected here.
- **What 2.2.2 added (modernization cut):**
  - **Toolchain pin `5.10.5` → `6.0.3`.** All declared stdlib
    modules resolve in 6.0.3.
  - **Vendored `lib/` gitignored** ([ADR 0018](../adr/0018-vendored-stdlib-gitignored.md)).
    The 20 committed 5.10.5-vintage stdlib files were shadowing
    the version-matched toolchain snapshot, so the pin was
    ignored at build time. `cyrius deps` now repopulates `lib/`
    from the pinned snapshot — matches `patra` / `sigil`.
    Untrack with `git rm -r --cached lib`.
  - **`vyk --list-languages` dispatch fix.** 6.0 annotates
    `vec_get(v, idx): i64`, so `println(vec_get(...))` resolved
    to `println_int` and printed pointer addresses. Bound the
    result through a `var name: cstring` local. Was masked by
    the committed 5.10.5 `lib/`; surfaced once the 6.0.3
    snapshot took over.
  - Pure infrastructure + one-line correctness fix — no
    grammar, token-layout, or public-API changes.
- **What 2.2.1 added (audit-queue wrap-up):**
  - **Compose-rule prefix buffering (FINDING-011 fix).**
    `_stream_compose_prefix_hold(g, buf, buf_len, temp_tb,
    n_temp)` holds back trailing bytes that match a prefix
    of any compose / compose_fenced START marker, plus
    full mid-buffer starts whose end hasn't arrived yet.
    Helper takes `temp_tb` so case (b) skips positions
    already inside an emitted compose TK_PUNCTUATION
    (markdown's `` ``` `` close == open, so an emitted
    close marker would otherwise look like a fresh opener
    with no end).
  - **Defensive `staging == 0` guard** in
    `tokenize_stream_discard_consumed`. From the 2.1.5
    audit recommendations.
  - **Pair-pending overlap guard.** Drain skips caching
    the pending pair-rule fast-path state when the
    trailing partial overlaps the prefix-hold region —
    prevents the pair fast path from racing compose_fenced
    on subsequent drains.
  - **Skip-prefix-hold for committed compose ends.** When
    the last committed token is a TK_PUNCTUATION matching
    a compose end marker, prefix-hold case (a) skips —
    those bytes are claimed by the just-emitted compose
    pair, not a partial upcoming opener.
  - **Fuzz coverage re-enabled.** `fuzz/streaming.fcyr`
    now exercises HTML (`<style>` / `<script>` compose),
    Vue SFC, and Markdown (` ``` `) random-split cases
    across 5 split shapes (2 / 4 / 8 / 16 / 32 chunks).
- **What 2.2.0 added (toolchain pin bump):**
  - **Pin moved 5.10.0 → 5.10.5.** User-requested
    refresh. CI's release-tarball install gets the matching
    bundle automatically.
  - Inherited stdlib drift: `strlen` SWAR + `: i64`
    annotation; `println_int` overload-dispatch target;
    `str_*` `: Str` annotations. None affect vyakarana
    runtime; gates verify byte-equivalent tokenization.
  - Pure infrastructure cut — zero vyakarana code changes.
- **What 2.1.5 added (closeout audit):**
  - **`docs/audit/2026-05-09-2.1.x-closeout-audit.md`** —
    full surface review of every 2.1.x change. Per-function
    bounds analysis on the streaming primitives and the
    seven new grammars. **0 CRITICAL / 0 HIGH / 0 MEDIUM /
    0 LOW (no new findings).**
  - **FINDING-011 filed (deferred):** compose-rule START
    markers split across chunks lose the route. Picked up
    in the next streaming-opt cut.
  - **Recommendations carried forward:** defensive
    `staging == 0` check in `tokenize_stream_discard_consumed`;
    compose-rule prefix buffering (FINDING-011); revisit
    1.13.0 binary-size soft cap; toolchain pin discipline
    (memory captures the rule).
  - No code changes — pure audit.
- **What 2.1.4 added (streaming opts + fuzz):**
  - **`tokenize_stream_discard_consumed(s)`** — drops
    iterated-past tokens from pull-adapter staging.
    Bounds memory in long-running streams.
  - **`tokenbuf_drop_front(tb, n)`** — internal primitive.
  - **`fuzz/streaming.fcyr`** — random-split fuzz harness;
    verifies byte-equivalence vs single-shot tokenize.
    4/4 fuzz harnesses passing (3 → 4).
  - **Trailing-complete heuristic fix.** Pre-2.1.4 a chunk
    ending right after an opening `"` (or other same-byte
    pair marker) committed a 1-byte string token; the
    actual close on the next feed then opened a SECOND
    string. Caught by the fuzz harness; fixed by requiring
    `t_len >= slen + elen` minimum complete length.
  - **Filed gap (next opt cut):** compose-rule START
    markers split across chunks lose the route; needs
    compose-aware prefix buffering. HTML / Vue / Svelte /
    Markdown random-split fuzz cases skipped until the fix.
  - 6 new tcyr probes; 830 → 836 passing.
- **What 2.1.3 added (Terraform / HCL):**
  - **Terraform** (`.tf`, `.tfvars`, `.hcl`) — the HashiCorp
    Configuration Language. Both `#` and `//` line comments
    + `/* */` block. `=>` for-expressions, `...` spread,
    kebab-case idents (`aws_s3_bucket`, `my-bucket`),
    standard arithmetic/comparison/logical operators.
    Block syntax (`resource "type" "name" { … }`) tokenizes
    naturally without special-casing.
  - 5 new tcyr probes; 1 new M3 corpus; bundle 44 → 45.
  - Documented gaps: heredocs (`<<EOT`), `${}` interpolation,
    splat shorthand.
  - **Closes the 2.1.x grammar wave** — 7 grammars added
    (38 → 45) across PowerShell / Crystal / Julia / Vue /
    Svelte / Nix / Terraform.
- **What 2.1.2 added (Nix):**
  - **Nix** (`.nix`) — functional config language for NixOS
    and home-manager. `//` set-merge (NOT line comment),
    `++` list concat, `->` implication, `@` "as" pattern,
    `?` has-attribute. Idents accept `'` (Haskell-prime)
    and `-` (kebab-case). `''…''` indented multi-line
    strings as 2-byte pair. Block + line comments.
  - 6 new tcyr probes; 1 new M3 corpus; bundle 43 → 44.
  - Documented gaps: `${}` interpolation, path literals,
    indented-string escapes.
- **What 2.1.1 added (Vue + Svelte SFC):**
  - **Vue** (`.vue`) — HTML-shaped outer with `@` / `#`
    Vue-shorthand operators. `<script>` → javascript and
    `<style>` → css via compose rules. `<template>` body
    handled by the outer Vue tokenizer (NOT routed through
    html — would lose Vue's own operators).
  - **Svelte** (`.svelte`) — same shape; no `<template>`
    block (template lives at file top level). `$` in
    operators for reactive declarations.
  - **CSS missing `%` operator** fixed in passing — surfaced
    via Vue's `width: 100%` test corpus.
  - 9 new tcyr probes; 2 new M3 corpora; bundle 41 → 43.
  - Documented limitations: Vue directives (`v-if`, `v-for`),
    `{{ }}` mustache, Svelte logic blocks (`{#if}`, `{#each}`),
    attribute-bearing block tags (`<script lang="ts">`) —
    all fall back to outer-grammar tokenization.
- **What 2.1.0 added (first grammar batch):**
  - **PowerShell** — `.ps1` / `.psm1` / `.psd1`. Cmdlet
    Verb-Noun idents (`-` in `ident_cont`), alphabetic
    operators (`-eq` / `-and`), variables via `$` in
    `ident_start`, both string forms, block + line
    comments, case-insensitive keywords.
  - **Crystal** — `.cr`. Ruby-shaped with `?`/`!` in
    `ident_cont` (`empty?`, `push!`), `@` in `ident_start`
    for instance vars.
  - **Julia** — `.jl`. `@` in `ident_start` for macros,
    `!` in `ident_cont` for mutating methods, `::` type
    annotations, triple-quoted strings + backtick command
    literals. Block + line comments expressed as pair
    rules to dodge the `#`/`#=` longest-prefix collision.
  - **`detect_language` refactored** into length-bucket
    helpers (Cyrius caps per-function returns at 64; the
    extension list outgrew it).
  - 15 new tcyr probes; 3 new M3 corpora; bundle 38 → 41.
- **What 2.0.4 added (closeout audit):**
  - **`docs/audit/2026-05-09-2.0.x-closeout-audit.md`** —
    full surface review of every 2.0.x change. Per-function
    bounds analysis on `_stream_grow`,
    `_stream_scan_close`, `_stream_find_pair_rule`,
    `_stream_is_trailing_complete`, drain, pull adapter,
    and pending-pair fast path. Buffer-cap semantics
    documented. **0 CRITICAL / 0 HIGH / 0 MEDIUM / 2 LOW
    (both fixed in-pass).**
  - **FINDING-008 fix.** `_stream_grow` zero-cap
    infinite-loop guard.
  - **FINDING-009 fix.** `_stream_scan_close` zero-elen
    vacuous match guard.
- **What 2.0.3 added (streaming optimization):**
  - **Pending pair-rule fast path.** When drain detects a
    trailing partial pair-rule open (string / block
    comment / preprocessor directive crossing chunk
    boundaries), the stream caches `(rule_idx, scan_resume)`
    and subsequent drains skip the full scanner — looking
    only for the close marker, advancing `scan_resume`
    past already-checked body bytes. Pathological case
    (1 MB string in 1 KB chunks) drops O(N×K) → O(N).
  - Stream record: 72 → 88 bytes (`pending_idx` + `scan_resume`).
  - 9 new probes: 100×10-byte chunks inside an open block
    comment; close marker straddling two feeds; pending
    state clears after close.
- **What 2.0.2 added (pull adapter):**
  - **`tokenize_stream_next(s)`** — iterator-style cursor;
    advances and returns 1, or 0 when exhausted. Refills
    via `_drain` automatically.
  - **`tokenize_stream_kind(s)` / `_start(s)` / `_len(s)`**
    — read the current token (the one just advanced to).
  - **drain / finish accept `out_tb = 0`** to route into
    the stream's internal staging tokenbuf — lets the
    iterator pattern work without managing a tokenbuf
    externally.
  - 11 new tcyr probes covering iteration vs push baseline,
    interleaved feed + iterate, empty-stream EOF, null
    safety. Stream record: 56 → 72 bytes (added staging_tb
    + next_idx).
  - Closes the followup queued from 2.0.0.
- **What 2.0.1 added (rolling-buffer streaming):**
  - **Per-feed drainage.** `tokenize_stream_drain(s, tb)`
    re-runs the scanner over the current buffer, commits
    every token whose extent is fully present, and
    compacts unconsumed bytes to offset 0. `abs_offset`
    keeps token starts absolute across compaction.
  - **Trailing-complete heuristic** lets pair-rule tokens
    (TK_STRING / TK_COMMENT / TK_PREPROCESSOR) commit
    early when their close marker is at the tail. Other
    kinds (operators, idents, numbers, whitespace) wait
    for finish.
  - **`VYK_STREAM_CAP` raised 1 MB → 16 MB** — and now
    bounds the *live buffer* (longest in-progress span),
    not the total input. 100 MB-class files stream
    comfortably.
  - 12 new tcyr probes including a byte-at-a-time stream
    that's byte-equivalent to single-shot tokenize.
- **What 2.0.0 added (streaming tokenizer):**
  - **Push-based streaming primitive
    ([ADR 0017](../adr/0017-streaming-api.md)).** Five
    public entries: `tokenize_stream_new` / `_feed` /
    `_drain` / `_finish` / `_free`. Replaces the 1.x
    `tokenize_source(src, lang)` synchronous entry (which
    was removed entirely; no compat shim). Migration is
    mechanical — five lines instead of one.
  - **2.0.0 sub-cut scope: API surface only.** Internal
    scanner unchanged; feed() buffers, finish() runs
    `tokenize_with_grammar` over the buffered bytes. The
    public contract is stable across the upcoming 2.0.1+
    scanner refactor.
  - **15 new tcyr probes** locking the streaming contract:
    multi-chunk feed byte-equivalent to single-chunk;
    feed-after-finish errors with `VYK_ERR_FINISHED`;
    drain-after-finish is idempotent.
  - Bench overhead: ~5–25% per-call regression from the
    extra alloc + buffer copy. Acceptable for the API-
    surface cut; 2.0.1+ removes it.
- **What 1.13.3 added (RC closeout):**
  - **`docs/development/distribution.md`** — the two
    distribution paths in current use (the
    `dist/vyakarana.cyr` source bundle for `cyrius deps`
    consumers, and the GitHub release tarball). Chooser
    table for consumers, release-procedure walkthrough for
    the operator, and a `cyrius package` status note
    (still upstream-stubware; revisit when ark work
    lands).
  - **`docs/audit/2026-05-09-1.13-closeout-audit.md`** —
    covers every surface added in 1.12.0–1.13.2. **0
    CRITICAL / 0 HIGH / 0 MEDIUM / 0 LOW.** Per-surface
    review with detailed bounds analysis on the
    `compose_fenced` step. Recommendation: dedicated audit
    when 2.0.0 streaming lands.
  - No code changes.
- **What 1.13.2 added (markdown fence routing):**
  - **`match = "compose_fenced"` rule type
    ([ADR 0016](../adr/0016-compose-fenced-rule.md)).**
    Captures language tag from fence info-string
    (`[A-Za-z0-9_+-]+`); routes body through the named
    inner grammar. New scanner step 0b ahead of pair / line
    / words. Falls back to TK_STRING on unknown tag, empty
    tag, or unloaded grammar.
  - **Markdown adopts it** — `` ```rust `` body produces
    TK_KEYWORD for `fn`/`let`; `` ```python `` produces
    TK_KEYWORD for `def`.
  - **Toolchain pin bumped** to `cyrius = "5.10.0"` to
    match local stdlib expectations.
- **What 1.13.1 added (CLI polish cut):**
  - **Error messages split by failure class.**
    `unknown_option_error` / `bad_value_error` /
    `extra_arg_error` / `io_error` / `no_grammar_error` —
    each names the problem and points to the next step
    (allowed values, `--list-languages`, `--help`).
    `usage_error` removed.
  - **`vyk --help` Exit-codes + Examples sections.**
    Documents exits 0–4 explicitly; five canonical
    invocations.
  - **`docs/man/vyk.1`** — groff man page mirroring
    `--help`. Render with `groff -man -Tutf8 …` or `man
    -l`.
  - 9 new smoke probes covering every failure class.
- **What 1.13.0 added (performance baseline cut):**
  - **`tests/bcyr/vyakarana.bcyr`** — 8-benchmark suite
    covering tokenize (shell / rust / json / html-compose),
    detect (path / content / combined), and blob-load.
  - **`docs/development/performance.md`** — binary size +
    per-call latency baseline. Future agents diff against
    this at each minor.
  - Binary size measured: `build/vyk` = 325.9 KB (~26 KB
    over the 300 KB roadmap target — dominated by embedded
    grammar blobs per ADR 0014; soft cap, no fix this cut).
  - Tokenize: 3–26 µs for small inputs. Detect: 30 ns
    (path) / 184 ns (content) / 5 µs (combined asm vote).
    Grammar load: 32 µs.
- **What 1.12.1 added:**
  - **`vyk --export-theme=helix`** — Helix `theme.toml`
    output (`"<scope>" = "<hex>"` per kind). Pairs with
    `--theme=<name>` for palette selection.
  - **`vyk --export-theme=iterm`** — iTerm `.itermcolors`
    plist with the 16 ANSI colours plus background /
    foreground / cursor / selection. Dark variant inverts
    background + foreground.
  - Closes the "deferred until a real consumer asks"
    followup from 1.11.1's CHANGELOG.
- **What 1.12.0 added (M7-prep groundwork):**
  - **Fuzz harnesses** (`fuzz/*.fcyr`) — one per public API
    entry: `tokenize.fcyr`, `detect.fcyr`,
    `grammar_load.fcyr`. Each passes deterministically
    against random / adversarial inputs. CI runs them on
    every PR via a new `cyrius fuzz` step.
  - **Stress probes** in `tests/vyakarana.tcyr` 1.12.0 group
    — runaway pair openers, comment soup, broken UTF-8
    mid-ident, unclosed compose, 6× nested compose, 4KB
    ident run. Coverage invariant holds in every case.
    707 → 717 passing.
  - **Security audit doc**
    `docs/audit/2026-05-09-1.11-closeout-audit.md` — surface
    inventory, per-module review of 1.11.x additions,
    fuzz/stress coverage summary. **0 CRITICAL / 0 HIGH /
    0 MEDIUM / 1 LOW (FINDING-007 — fixed in pass).** Carryover
    table from the 2026-04-23 pre-1.0 audit.
  - **FINDING-007 fix.** `grammar_load` blob copy now clamps
    against `GRAMMAR_FILE_CAP - 1`. Defense-in-depth.
- **What 1.11.2 added (third and final sub-cut of the
  external-integrations wave):**
  - **Content-based language detection** (`src/detect.cyr` +
    ADR 0015). Three public entries:
    `detect_language(path)` (extension/basename, moved from
    main.cyr), `detect_language_from_content(src, len)` (BOM
    strip + shebang interp lookup + signature peek for
    `<?xml` / `<!DOCTYPE html>`), and
    `detect_language_combined(path, src, len)` (path first,
    then asm flavour rescore for `.s` / `.S`, content
    fall-through for extensionless files).
  - **Asm flavour resolution.** `tests/corpus/asm_x86_64.s`
    and `tests/corpus/asm_aarch64.s` now auto-detect
    correctly via weighted-signal scoring on the first 4KB.
    Closes the `.s` ambiguity carried since 1.2.3.
  - **`vyk` flow change.** Source file read happens in
    `main()` before detection, so the same buffer feeds
    detection and tokenization (no second read). The old
    `tokenize_file` is now `tokenize_buf(buf, n, …)`.
  - **`src/detect.cyr` joins `[lib] modules`** so consumers
    pulling `dist/vyakarana.cyr` get the byte API alongside
    `tokenize_source` and `lsp_kind_*`.
- **What 1.11.1 added (second sub-cut of the external-integrations
  wave):**
  - **Grammar composition** (`match = "compose"` rule type +
    ADR 0013). New scanner pipeline step 0 — runs before
    everything else so outer-grammar tokenization doesn't eat
    the start markers. Routes the body bytes between `start`
    and `end` markers through a different grammar named in
    the new `inner` field. Markers emit as `TK_PUNCTUATION`;
    body tokens are recursively produced via the inner
    grammar with offsets shifted into the outer source's
    coordinate system. Graceful degradation when the inner
    grammar isn't loaded (body becomes one `TK_STRING`).
  - **HTML uses compose rules** for `<style>` → `css` and
    `<script>` → `javascript` — closes the 1.7.0 "embedded
    blocks tokenize as plain HTML" gap.
  - **Theme export** (`vyk --export-theme=<format>` flag +
    `src/theme_export.cyr`). VS Code `theme.json` is shipped
    (universal target — VS Code, Cursor, Codium and other
    forks). Pair with `--theme=<name>` to pick the source
    palette. Helix / iTerm formats deferred until a real
    consumer asks.
  - **Self-contained dist bundle** (ADR 0014). Through
    1.11.0 `dist/vyakarana.cyr` called `file_read_all` on
    `grammars/<name>.cyml` at runtime — but `cyrius deps`
    only vendors the bundle file. Consumers following the
    documented integration path got an empty tokenizer with
    no diagnostic. Fixed by inlining every grammar as a
    Cyrius string literal via the new
    `scripts/embed-grammars.sh` (writes
    `src/grammar_blobs.cyr`, gitignored, regenerated on each
    gate run). `grammar_load` consults the blob registry
    first; file-load fallback retained for grammar-author
    dev workflow. Bundle grew 82KB → 253KB.
- **Test count at 1.13.2:** 731/731 (was 717 at 1.13.1; 14 new
  1.13.2 probes covering Rust + Python fence routing, unknown-tag
  fallback, empty-tag fallback, unclosed-fence fall-through,
  `c++` tag accepts; M3 markdown probe refreshed for the new
  fence shape). 3 fuzz harnesses passed then; 4 today.
- **No new grammars at 1.13.2** — 38 bundled then; 45 today.

### 1.10.0 deliverables (recap)

- `vyk --theme=<name>` flag (three bundled themes).
- Architecture note 004 — theme-palette contract.
- Consumer integration guide at
  `docs/guides/consumer-integration.md`.

### Vidya integration — landed

Per the 1.10.0 cut, vidya could adopt vyakarana as its code
renderer whenever it planned a renderer rewrite; it has. Vidya
pins `[deps.vyakarana] tag = "2.2.3"` and drives the 2.x
streaming API from `src/main.cyr` at two call sites — the `vidya
code` CLI and the `GET /code/{topic}/{lang}` route. The `code`
command shipped in vidya 2.7.0 against vyakarana 1.11.1; vidya
2.7.1 migrated both call sites to the streaming API. No
vyakarana cut was needed, and none is now.
- **What 1.9.0 added:** two AGNOS-native grammars —
  **CYML and LLVM-IR**. Token counts: cyml 659, llvm_ir 1194 —
  zero errors on canonical samples. **No new scanner
  extensions needed.**
- **Self-hosting closed.** `build/vyk grammars/cyml.cyml`
  produces zero errors. The grammar file format vyakarana
  uses for its own definitions is now bundled as one of the
  bundled grammars. yukti config (`yukti.cyml`) and vidya
  content samples (`content/<topic>/*.cyml`) all benefit too.
- **First non-stand-in post-M3 corpus.** CYML's
  `tests/corpus/dependencies.cyml` is a real vidya snapshot
  (`content/cyrius/dependencies.cyml`, 233 lines) — not a
  hand-rolled `concept.<ext>` per ADR 0006. Demonstrates the
  reciprocal relationship that ADR 0001 set up: vidya
  becomes a corpus supplier when it has the matching content.
- **Sigil-in-`ident_start` pattern logged** — used 7 times now
  across the bundled set, all with the same shape:
  - `$` — Rust macros (1.1.0, ADR 0007), Zig builtins (1.2.0
    via `@`), PHP variables (1.4.0), Java/Kotlin/Swift
    compiler-generated names (1.3.0/1.3.0/1.4.0), GraphQL
    operation variables (1.6.0).
  - `@` — Java/Kotlin annotations (1.3.0), Zig builtins
    (1.2.0), Elixir module attributes (1.5.0), CSS at-rules
    (1.7.0), GraphQL directives (1.6.0).
  - `%` — Elixir struct/map literals (1.5.0), LLVM-IR locals
    (1.9.0).
  - `!` — LLVM-IR metadata refs (1.9.0).
  - `#` — CSS id selectors / hex colors (1.7.0).
  - `-` — CSS custom properties (`--var`, 1.7.0).
  - `.` — asm directives / labels (1.2.2 / 1.2.3).
  Each grammar adds the byte to `ident_start` (sometimes
  `ident_cont` too), then optionally adds a words-rule entry
  to promote the resulting ident to keyword when the name is
  reserved. Pattern is robust enough to plan around.
- **Test count:** 622/622 (was 599 at 1.8.0; added 23
  assertions across 2 new grammars).
- **Grammars:** 38 bundled (shell, toml, json, cyrius, rust,
  yaml, markdown, c, typescript, javascript, python, go, zig,
  asm_x86_64, asm_aarch64, java, kotlin, cpp, csharp, php,
  ruby, lua, swift, elixir, ocaml, haskell, sql, graphql,
  protobuf, html, xml, css, scss, dockerfile, makefile, ini,
  **cyml, llvm_ir**).
- **Toolchain pin:** `cyrius = "5.10.0"` in `cyrius.cyml`
  (unchanged since 1.0.3).
- **Build state: GREEN on cyrius 5.10.0.** `cyrius build`
  clean; `cyrius test tests/vyakarana.tcyr` 622/622;
  `sh scripts/smoke.sh build/vyk` reports M0+M1+M2+M3 passing
  at v1.9.0. `dist/vyakarana.cyr` regenerated.
- **Consumer pressure:** unchanged. Public `tokenize_source` /
  `tokenbuf` API is unchanged across 1.0.0 → 1.9.0. Grammar
  record stayed at 160 bytes since 1.6.0.

### Language line closed at 1.9.0

The original 1.x roadmap targeted seven language batches
(1.3 – 1.9). With 1.9.0 shipped, **all seven have landed**:
- 1.3.0 — JVM + C-family
- 1.4.0 — Scripting + mobile
- 1.5.0 — Functional tier
- 1.6.0 — Data / query / IDL
- 1.7.0 — Markup + styling
- 1.8.0 — DevOps + infrastructure
- 1.9.0 — AGNOS-native

That's 27 grammars added across the language batches, on top
of 11 starter grammars at v1.0.0. **38 bundled, all-clean** on
their canonical samples. The 1.x line continues with the pre-
2.0 prep waves (1.10–1.13).

### Stand-in corpora — replace when vidya ships

Per [ADR 0006](../adr/0006-standin-corpus-policy.md), eight
grammars (json, yaml, markdown, javascript, java, kotlin, cpp,
csharp, php, ruby, lua, swift) use hand-rolled
`tests/corpus/concept.<ext>` samples. Each is ~150–250 lines
following the lexer+parser theme. When vidya ships reference
samples for any of them, swap the stand-in for the vidya
snapshot and update the corpus README.

### Variable-length-delimiter shapes — collective ADR pending

Four grammars currently document variable-length terminator
forms as deferred:

- **Lua** `[==[ … ]==]` long brackets with `=` padding (1.4.0).
- **Ruby** `<<~HEREDOC … HEREDOC` heredocs (1.4.0).
- **PHP** `<<<EOT … EOT;` heredocs / nowdocs (1.4.0).
- **Swift** `#"…"#`, `##"…"##` raw strings (1.4.0).

The scanner has no variable-length-delimiter pair rule today;
these all share the same scanner shape gap. If a real corpus
forces one of them, expect a collective ADR + scanner extension
that handles all four uniformly.
- **Toolchain pin:** `cyrius = "5.10.0"` in `cyrius.cyml`
  (unchanged since 1.0.3).
- **Build state: GREEN on cyrius 5.10.0.** `cyrius build` clean;
  `cyrius test tests/vyakarana.tcyr` 431/431;
  `sh scripts/smoke.sh build/vyk` reports M0+M1+M2+M3 passing
  at v1.2.2. `dist/vyakarana.cyr` regenerated.
- **Consumer pressure:** unchanged — owl's M3b stays unblocked;
  the public `tokenize_source` / `tokenbuf` API is unaffected.

---

## Known cosmetic gaps (coverage holds; no `error` tokens)

Closed in 1.1.0:

- **Rust macro metavariables** — `$tok:fragment` now tokenizes as
  one `ident`. ADR 0007. Was: 79 errors per macro-heavy sample.
- **TOML triple-quoted strings** — `"""…"""` and `'''…'''` are
  rules now. ADR 0008. Was: 188 errors per content-heavy file.
- **UTF-8 outside strings + C block comments** — `unicode_ident`
  default flag + a `/* … */` pair rule in `c.cyml`. ADR 0009.
  Was: 8 errors per typical vidya C sample.

Still cosmetic-only and genuinely open:

- **F-string prefix**: `f"..."` → `ident(f) + string("...")` in
  Python. Same for r/b/rb/fr prefixes.
- **Block comments in Rust** — Rust's `/* */` is *nestable*, so
  the simple pair rule used for C won't work. Needs a nesting
  variant. Not triggered by the canonical sample.
- **Float literals** — `2.0` splits into `number` + `.` +
  `number`. The scanner has no float support at all
  (`number_decimal` / `_0x` / `_0b` / `_0o` only), so css, scss,
  protobuf, java, graphql and openqasm all carry it. A
  `number_float` default touches every grammar → wants an ADR.
  Surfaced most visibly by 2.3.5's openqasm grammar, where the
  version header `OPENQASM 2.0;` is three tokens.

**Closed, was listed here through 2.3.4:**

- **Char literals** (`'x'`, `'\0'`) — this section asked for "a
  `char_literal = true` default with 2-3 char lookahead". That is
  [ADR 0010](../adr/0010-char-literal-default.md), shipped in
  1.2.1, and `char_literal = true` is set in c / rust / go / zig /
  kotlin / ocaml / lua today. Stale since 1.2.1; caught by the
  2.3.4 deferral audit.

**Out of scope, not deferred:**

- **Python INDENT/DEDENT**: structural tokens Python parsers want
  aren't emitted. Not needed for the tokenizer's correctness bar —
  vyakarana yields spans, not structure. Listed under "waiting on
  a future ADR" through 2.3.4 while the bullet itself said it was
  unnecessary; moved here so it stops reading as pending work.

---

## Past audits

- [2026-04-23 — Pre-1.0 audit](../audit/2026-04-23-audit.md):
  0 CRITICAL / 0 HIGH / 0 MEDIUM-open (one MEDIUM fixed in-pass);
  5 LOW. FINDING-006 fixed in 1.0.1.
- [2026-05-08 — 1.2.x closeout](../audit/2026-05-08-1.2.x-closeout-audit.md):
  scope was the new-language batch (asm × 2, java/kotlin/cpp/csharp/php/ruby/lua/swift/elixir/ocaml/haskell).
- [2026-05-09 — 1.11.x closeout](../audit/2026-05-09-1.11-closeout-audit.md):
  surfaces added in 1.11.0 / 1.11.1 / 1.11.2 (LSP bridge,
  composition, theme export, embedded blobs, content
  detection). 0 CRITICAL / 0 HIGH / 0 MEDIUM / 1 LOW
  (FINDING-007, fixed in-pass). Fuzz + stress coverage
  established.
- [2026-05-09 — 1.13.x closeout](../audit/2026-05-09-1.13-closeout-audit.md):
  surfaces added in 1.12.0–1.13.2 (fuzz harnesses,
  Helix/iTerm theme emitters, bench suite, error-message
  split, man page, compose_fenced rule + scanner step 0b,
  toolchain pin bump). 0 CRITICAL / 0 HIGH / 0 MEDIUM / 0
  LOW. No new findings.
- [2026-05-09 — 2.0.x closeout](../audit/2026-05-09-2.0.x-closeout-audit.md):
  streaming surfaces (push primitive, rolling buffer, pull
  adapter, pending-pair fast path). 0 CRITICAL / 0 HIGH /
  0 MEDIUM / 2 LOW (FINDING-008, FINDING-009 — both fixed
  in-pass).
- [2026-05-09 — 2.1.x closeout](../audit/2026-05-09-2.1.x-closeout-audit.md):
  seven new grammars + streaming opts (discard primitive,
  trailing-complete tightening, streaming fuzz harness).
  **0 CRITICAL / 0 HIGH / 0 MEDIUM / 0 LOW.** FINDING-010
  fixed in 2.1.4 in-pass; **FINDING-011 (compose-rule
  prefix streaming gap) deferred** to the next opt cut.

See `SECURITY.md` for the living state of the audit findings.
Next scheduled audit: whichever cut lands a meaningful new
surface first. FINDING-011 closed in 2.2.1, and neither 2.2.3
nor 2.3.0 added a surface to audit — both were toolchain work
over an unchanged public API.

---

## Next up — open queue

**Priority order after 2.4.0** (2.3.4's audit is
[here](../audit/2026-08-20-2.3.x-hardening-audit.md)):

1. **Chunk-invariance for the compose grammars** — markdown, html,
   vue, svelte, cyml. Everything else is clean and gated by
   `fuzz/chunk_invariance.fcyr`; these five are excluded because the
   marker window in `tokenize_stream_drain` is applied only when the
   grammar has no compose rules. The blocker is that the compose
   machinery reads the commit list as state: `skip_prefix_hold`
   asks "was the last *committed* token a compose close marker?",
   so holding a token back makes that guard miss and prefix-hold
   drops the close token. Three attempts (exempting compose markers
   from the window; keying the guard to a pre-window commit
   boundary) each regressed the markdown/fence-rust fuzz case. The
   real fix is probably to give prefix-hold its own view of the
   tokenization instead of inferring it from `commit_count` — that
   is a refactor, not a patch. Move the five grammars into
   `chunk_invariance.fcyr` as they land.
2. **Residual O(N²) in compose drains.** `VYK_COMPOSE_HOLD_MAX`
   stopped the permanent overflow, and 2.3.4's two fixes took a
   4 KB document from 11.4 s to 69 ms, but growth is still ~O(N^1.6)
   because the buffer cannot compact while a compose opener is held.
   Bounded and no longer fatal; worth revisiting with item 1, since
   both want prefix-hold restructured.
3. **`openqasm` float literals / a `number_float` default.**
   `OPENQASM 2.0;` is three tokens. The scanner has no float support
   at all (`number_decimal` / `_0x` / `_0b` / `_0o`), so css, scss,
   protobuf, java, graphql and openqasm all carry it. Cross-grammar
   scanner change → wants an ADR.
4. **Consumers** — the user is handling this.

Closed waves:

- **1.11.x — external integrations.** LSP bridge (1.11.0,
  ADR 0012); grammar composition + theme export +
  self-contained dist bundle (1.11.1, ADRs 0013–0014);
  content-based detection (1.11.2, ADR 0015).
- **1.12.x — hardening + theme export polish.** Fuzz +
  stress harness + post-1.11 audit (1.12.0); Helix + iTerm
  theme export (1.12.1).
- **1.13.x — RC polish.** Bench baseline (1.13.0), error
  messages + man page (1.13.1), markdown fence routing
  (1.13.2, ADR 0016), distribution + 1.13-closeout audit
  (1.13.3 — 0 findings).
- **2.0.x — streaming tokenizer.** API surface (2.0.0,
  ADR 0017); rolling-buffer per-feed drainage (2.0.1);
  pull adapter (2.0.2).

Shipped since — the 2.1.x grammar batches and the
infrastructure cuts that followed:

- **2.1.0 — PowerShell / Crystal / Julia grammars.** Shipped.
- **2.1.1 — Vue / Svelte single-file components.** Shipped.
- **2.1.2 — Nix grammar.** Shipped.
- **2.1.3 — Terraform / HCL grammar.** Shipped.
- **2.1.4 — Streaming opts + fuzz.** Shipped. Discardable
  pull-adapter staging; streaming-aware fuzz harness;
  trailing-complete heuristic tightened (FINDING-010).
- **2.1.5 — Closeout audit.** Shipped. 0 new findings.
  FINDING-011 (compose-prefix-streaming) deferred to 2.2.1.
- **2.2.0 — Toolchain pin bump.** Shipped. cyrius
  `5.10.0` → `5.10.5`. Pure infrastructure cut.
- **2.2.1 — Audit-queue wrap-up.** Shipped.
  FINDING-011 compose-rule prefix buffering fixed;
  defensive `staging == 0` guard; HTML / Vue / Markdown
  random-split fuzz cases re-enabled.
- **2.2.2 — Modernization cut.** Shipped. Toolchain
  pin `5.10.5` → `6.0.3`; vendored `lib/` gitignored
  ([ADR 0018](../adr/0018-vendored-stdlib-gitignored.md));
  `--list-languages` dispatch fix for 6.0's `vec_get: i64`.
- **2.2.3 — Toolchain pin bump.** Shipped. cyrius
  `6.0.3` → `6.1.24`. Pure infrastructure cut; no vyakarana
  code changes — and, as 2.3.0 discovered, a red test gate.
- **2.3.0 — Toolchain catch-up.** Shipped (this cut). cyrius
  `6.1.24` → `6.5.4`, four minor lines in one step. Vestigial
  `cyml` entry removed from `[deps] stdlib` (it broke `cyrius
  deps` on a fresh checkout at both pins); eleven duplicate
  `var` names in `tests/vyakarana.tcyr` renamed, taking the
  test gate red → green at 840/840; vendored `lib/` re-cut from
  the 6.5.4 snapshot after sitting at 6.0.x vintage since 2.2.2.
  No public-API, token-layout, or grammar changes.

**The 2.1.x window is fully closed; the 2.1.5 audit queue
is now empty.** No work currently in flight. Possible
directions when work resumes:

- **Scanner state-machine optimization.** 2.0.1's
  rescan-and-commit drain is O(buf_len) per call. A real
  state machine would scan only the new bytes since the
  previous commit, dropping per-feed cost from O(buf_len)
  to O(new_bytes). Worth doing if a real consumer surfaces
  a profiling complaint.
- **Real-corpus fuzz harness** (flagged in the 2026-05-09
  1.13-closeout audit's recommendations). Mutates vidya
  snapshots instead of random bytes — catches shape-
  specific regressions.
- **More grammars.** No batch queued; whatever a real
  consumer asks for. Stale-list candidates from the 2.1.x
  selection: MDX (markdown + JSX), shell variants beyond
  bash/zsh/sh/dash, Lean 4, Zig macros.
- **Binary-size cap revisit.** 1.13.0's 300 KB soft cap is
  consistently exceeded (362.8 KB on 6.5.4, down from 381.6 KB
  at the 2.2.1 capture) since ADR 0014's embedded-grammar
  design. Not a security concern; flagged in the 2026-05-09
  2.1.x audit as a 2.x roadmap item.

All consumer-driven. No forced minor; the next cut waits
for a real ask.

Each new grammar is a `grammars/<name>.cyml` plus a
`tests/corpus/<name>.<ext>` (vidya snapshot per
[ADR 0001](../adr/0001-corpus-sync-policy.md)) plus probe
assertions in `tests/vyakarana.tcyr`. The data-driven scanner
already covers the structural shapes; expect each addition to be
mostly grammar-file work unless a language forces a new rule
type (in which case a new ADR per the M2 scope of
[ADR 0005](../adr/0005-m2-rule-type-scope.md)).

**Out-of-scope follow-ups still on the books** (capture before
starting 1.2.0 so they don't drift away):

- Rust byte-char-literal-with-escape (`b'\n'`) — pre-existing
  gap, not addressed by ADR 0007. Likely solved with the same
  `char_literal` scanner default that the C/Rust char-literal
  gap is waiting on.
- Python f-string / r-string / b-string prefixes coalescing into
  the string token. Documented gap; defer until a corpus or a
  consumer asks for it.
- Float literals + datetime literals in TOML
  ([ADR 0008](../adr/0008-toml-triple-quoted-strings.md)
  scoped them out).

Post-1.1 roadmap ([./roadmap.md](./roadmap.md) has the detail):

- **M4** — Theme-palette contract with owl. **Landed** — the
  contract is
  [`../architecture/004-theme-palette-contract.md`](../architecture/004-theme-palette-contract.md),
  with `vyk --theme=` and `--export-theme=` as the shipped
  surface. (Left unmarked through 2.3.4 while M5 and M6 in the
  same list were marked "Landed".)
- **M5** — Streaming tokenizer (iterator API). Memory goes
  O(tokens in flight); enables `owl huge.log`. **Landed** —
  2.0.0–2.0.2.
- **M6** — vidya reverse consumption (vidya starts rendering its
  `content/lexing_and_parsing/` samples through vyakarana).
  **Landed** — vidya 2.7.0 / 2.7.1; see §Vidya integration.
- **M7** — Polish + release candidate.

---

## Cross-repo coordination

- **Consumers all sit at `tag = "2.2.3"`** — `owl`, `cyim`, and
  `vidya`, each pulling `dist/vyakarana.cyr` via
  `[deps.vyakarana]`. **They are now materially behind, and this
  entry used to say the opposite.** The "2.3.0 bundle is
  byte-identical apart from its version header, so bumping buys
  nothing" line was accurate when written — 2.2.3 → 2.3.0 is
  literally 2 changed lines, both the version header — but 2.3.1
  and 2.3.2 landed real grammar fixes after it and nobody
  re-checked. Measured 2026-08-20: **2.2.3 → 2.3.3 is 241 changed
  lines, +19,565 bytes.** A consumer on 2.2.3 is missing the
  CYML compose-region routing fix (2.3.1) and the 37-grammar
  `TK_ERROR` adjudication (2.3.2) — i.e. it still emits error
  tokens for Go struct tags, shell backtick substitution, AT&T
  `$` immediates and the rest. **Bumping consumers now buys
  correctness, not just a tag.** Re-measure before repeating any
  "no churn to chase" claim.
- **owl** (`/home/macro/Repos/owl`) — its M3b was blocked on M1;
  it has long since declared `[deps.vyakarana]` at a cut tag
  (currently 2.2.3). Do **not** sidestep with a path hack.
- **vidya** (`/home/macro/Repos/vidya`) — read before making
  corpus decisions. Already a live consumer: the `vidya code`
  CLI and the `GET /code/{topic}/{lang}` route both render
  through the 2.x streaming API (`tokenize_stream_new` /
  `_feed` / `_finish` / `_free`, ADR 0017) from its
  `src/main.cyr` — added in vidya 2.7.0 against vyakarana
  1.11.1, migrated to streaming in vidya 2.7.1.
- **cyrius** (`/home/macro/Repos/cyrius`) — toolchain. Pinned at
  `6.5.32` in `cyrius.cyml` (bumped from 6.5.4 in 2.3.3; 6.5.4
  came from 6.1.24 in 2.3.0; 6.1.24 from 6.0.3 in 2.2.3, and
  6.0.3 from 5.10.5 in 2.2.2; see
  [ADR 0018](../adr/0018-vendored-stdlib-gitignored.md)). The
  2026-05-07 `include`-graph
  regression filed against 5.9.32
  ([`./issues/2026-05-07-cyrius-include-graph-regression.md`](./issues/2026-05-07-cyrius-include-graph-regression.md))
  is resolved on 5.9.36. If you find another compiler bug, file
  it upstream; don't work around it in vyakarana.

---

*Live status only. Architecture / frozen contracts / module map
live in [`../architecture/`](../architecture/). Refresh history:
2026-04-23 (M0 + M1/M2/M3 same day); 2026-05-07 (cyrius pin
5.9.32 / red); 2026-05-08 (1.0.3 cut + toolchain unblock);
2026-05-08 (1.1.0 cut + modernization fixes + docs reshape per
AGNOS first-party-documentation standard); 2026-05-08 (1.2.0 cut
+ Go and Zig grammars); 2026-05-08 (1.2.1 cut + `char_literal`
flag); 2026-05-08 (1.2.2 cut + `asm_x86_64`); 2026-05-08
(1.2.3 cut + `asm_aarch64` + roadmap restructure); 2026-05-08
(1.2.4 closeout — dead-code cleanup + stale-comment sweep +
1.2.x audit); 2026-05-08 (1.3.0 cut + JVM + C-family —
java/kotlin/cpp/csharp via ADR 0006 stand-ins) — the list then
went unmaintained through the 1.4.0–2.2.3 cuts; 2026-07-31
(2.3.0 cut + pin 6.1.24 → 6.5.4 + test gate red → green).
Next refresh: whenever the next cut ships. Nothing is in
flight, so that waits on a real consumer ask — or on the next
toolchain bump, whichever the user calls first.*
