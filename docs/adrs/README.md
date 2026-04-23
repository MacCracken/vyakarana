# Architecture Decision Records

Decisions whose rationale needs to outlive the conversation that
produced them. Format roughly follows the
[Michael Nygard template](https://github.com/joelparkerhenderson/architecture-decision-record/blob/main/locales/en/templates/decision-record-template-by-michael-nygard/index.md):
Context → Decision → Consequences, with a Status line at the top.

## Index

| #    | Title                                                                                     | Status   | Date       |
|------|-------------------------------------------------------------------------------------------|----------|------------|
| 0001 | [Corpus sync policy — checked-in snapshot](0001-corpus-sync-policy.md)                    | Accepted | 2026-04-23 |
| 0002 | [Token storage — contiguous 12-byte records via `tokenbuf`](0002-token-storage-layout.md) | Accepted | 2026-04-23 |
| 0003 | [Shell string expansions are not re-tokenized in M1](0003-string-expansion-not-retokenized.md) | Accepted | 2026-04-23 |
| 0004 | [Shell built-ins emit as `ident`, not `keyword`](0004-shell-builtins-as-ident.md)         | Accepted | 2026-04-23 |

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
