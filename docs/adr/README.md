# Architecture Decision Records

Decisions whose rationale needs to outlive the conversation that
produced them. Format roughly follows the
[Michael Nygard template](https://github.com/joelparkerhenderson/architecture-decision-record/blob/main/locales/en/templates/decision-record-template-by-michael-nygard/index.md):
Context → Decision → Consequences, with a Status line at the top.

Start a new ADR by copying [`template.md`](template.md) — it
captures the section shape we use here (Context, Decision,
Consequences with positive / negative / when-to-revisit
sub-blocks).

## Index

| #    | Title                                                                                     | Status   | Date       |
|------|-------------------------------------------------------------------------------------------|----------|------------|
| 0001 | [Corpus sync policy — checked-in snapshot](0001-corpus-sync-policy.md)                    | Accepted | 2026-04-23 |
| 0002 | [Token storage — contiguous 12-byte records via `tokenbuf`](0002-token-storage-layout.md) | Accepted | 2026-04-23 |
| 0003 | [Shell string expansions are not re-tokenized in M1](0003-string-expansion-not-retokenized.md) | Accepted | 2026-04-23 |
| 0004 | [Shell built-ins emit as `ident`, not `keyword`](0004-shell-builtins-as-ident.md)         | Accepted | 2026-04-23 |
| 0005 | [M2 rule-type scope — narrow spec rules + configured default scanner](0005-m2-rule-type-scope.md) | Accepted | 2026-04-23 |
| 0006 | [Stand-in corpus when vidya doesn't cover a bundled language](0006-standin-corpus-policy.md) | Accepted | 2026-04-23 |
| 0007 | [Rust grammar treats `$` as `ident_start`](0007-rust-dollar-in-ident-start.md)            | Accepted | 2026-05-08 |
| 0008 | [TOML grammar handles triple-quoted strings](0008-toml-triple-quoted-strings.md)         | Accepted | 2026-05-08 |
| 0009 | [`unicode_ident` default + C block comments](0009-unicode-ident-default.md)               | Accepted | 2026-05-08 |
| 0010 | [`char_literal` default](0010-char-literal-default.md)                                    | Accepted | 2026-05-08 |
| 0011 | [`case_insensitive_keywords` default](0011-case-insensitive-keywords-default.md)         | Accepted | 2026-05-08 |
| 0012 | [LSP semantic-tokens bridge mapping](0012-lsp-semantic-tokens-bridge.md)                  | Accepted | 2026-05-08 |
| 0013 | [Grammar composition rule](0013-grammar-composition-rule.md)                              | Accepted | 2026-05-08 |
| 0014 | [Embedded grammar blobs in the dist bundle](0014-embedded-grammar-blobs.md)                | Accepted | 2026-05-08 |
| 0015 | [Content-based language detection](0015-content-based-detection.md)                        | Accepted | 2026-05-08 |
| 0016 | [`compose_fenced` rule type for markdown fences](0016-compose-fenced-rule.md)              | Accepted | 2026-05-08 |
| 0017 | [Streaming tokenizer API (2.0)](0017-streaming-api.md)                                     | Accepted | 2026-05-08 |
| 0018 | [Vendored stdlib snapshot is gitignored, not committed](0018-vendored-stdlib-gitignored.md) | Accepted | 2026-05-27 |
| 0019 | [`compose_region` rule type for open-ended regions](0019-compose-region-rule.md)           | Accepted | 2026-07-31 |
| 0020 | [When `TK_ERROR` is correct and when it is a grammar hole](0020-tk-error-adjudication.md) | Accepted | 2026-07-31 |

## Conventions

- **Filename:** `NNNN-short-kebab-title.md`, zero-padded to four digits.
- **Never edit Accepted ADRs in place** — if a decision needs to
  change, open a new ADR that marks the old one Superseded and
  update this index.
- **Keep them short.** An ADR is a record, not an essay. If you
  find yourself writing more than a page of Context, the decision
  is probably more than one decision.
- **Small decisions don't need ADRs.** File these for choices with
  cross-module or cross-milestone blast radius: data layouts, on-disk
  formats, policy picks, anything that'll confuse a future reader
  who asks "why did they do it that way?"
