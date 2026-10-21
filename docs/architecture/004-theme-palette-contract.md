# 004 — Theme-palette contract

> **Affects:** every consumer that renders vyakarana tokens
> with colour. owl, cyim, vidya, and the bundled
> `vyk --theme=<name>` mode all hit the same surface.

## What the contract is

vyakarana classifies each input byte into one of **ten token
kinds** (defined in `src/token.cyr`):

| TK_*           | `kind_name()`   | Palette slot       |
|----------------|-----------------|--------------------|
| `TK_IDENT`         | `ident`        | identifier        |
| `TK_KEYWORD`       | `keyword`      | reserved-word     |
| `TK_STRING`        | `string`       | string-literal    |
| `TK_NUMBER`        | `number`       | number-literal    |
| `TK_COMMENT`       | `comment`      | comment           |
| `TK_OPERATOR`      | `operator`     | operator          |
| `TK_PUNCTUATION`   | `punctuation`  | punctuation       |
| `TK_WHITESPACE`    | `whitespace`   | whitespace        |
| `TK_PREPROCESSOR`  | `preprocessor` | preprocessor      |
| `TK_ERROR`         | `error`        | error / fallback  |

The contract is:

1. **The set of ten kinds is stable.** Adding an eleventh
   kind, or removing one, is a breaking change. ADR + CHANGELOG
   `Breaking` entry required. The 10-slot floor is documented
   in [overview.md](overview.md) "Frozen public contracts."
2. **The string returned by `kind_name(k)` is the stable
   identifier.** Themes index palettes by this string, not by
   the integer `TK_*` value. Renaming `keyword` to `kw` would
   be breaking even if `TK_KEYWORD` kept its integer value.
3. **vyakarana never picks colours.** The tokenizer's job is
   classification. Mapping each `kind_name` to a colour, font
   weight, or any other rendering attribute is the
   **renderer**'s job.
4. **Consumers may apply secondary palettes via token text.**
   ADRs [0004](../adr/0004-shell-builtins-as-ident.md) and
   [0007](../adr/0007-rust-dollar-in-ident-start.md) both end
   with "themes can introspect token text" — a renderer that
   wants `local`/`declare`/`export` to look distinct from
   other shell `ident`s, or `@Override` distinct from regular
   Java idents, does that lookup itself. The tokenizer hands
   over enough information; the theme decides what to do with
   it.

## Why it's not derivable from code

A reader of `src/token.cyr` sees the integer constants and the
`kind_name` lookup, but they cannot tell from the code alone
that **renaming a `kind_name` is breaking**. The names are not
just labels for debug output — they're the keys consumers
hardcode in their theme code and files. owl's `src/theme.cyr`
dispatches on `kind_name(kind)`, and its user themes
(`~/.config/owl/themes/<name>.cyml`) have lines like:

```
token.keyword = 141
token.string  = 113
token.ident   = -1     # -1 = no colour, the terminal default
```

Once one consumer's theme file is written and shipped, the
name `keyword` is contractually stable.

## Why not promote new kinds when more granularity is wanted?

There's a recurring temptation to add kinds: `keyword_control`
vs `keyword_declaration`, or `string_doc` vs `string_regular`.
**The 10-slot floor is the right level of abstraction for the
following reasons:**

1. **Themes that learn one grammar's tokens understand all
   grammars.** A user who's customised the `keyword` slot for
   their Rust code gets the same colour for SQL `SELECT`,
   Lua `function`, OCaml `let rec`, and so on. Adding
   sub-kinds breaks that uniformity.
2. **Sub-distinctions are renderer-side, not tokenizer-side.**
   "`fn` should be more saturated than `if`" is a theme call,
   not a classification call. A theme can choose to look at
   token *text*: `if (kind == "keyword" && text in {"fn",
   "let"})`. The tokenizer hands over enough signal.
3. **Adding a kind is backwards-incompatible.** Existing
   consumers don't switch on the new kind, so their renderers
   silently fall back to the default palette colour — which
   may not be the colour the new kind logically deserves.
4. **The 10-slot palette is what owl, cyim, kybernet, and
   themes-of-themes were sized against.** Pre-1.0 design was
   intentional ([design spec §3, §12](../../vyakarana-design-spec.md):
   the `Token` type locked in M0);
   we don't churn it.

## How `vyk --theme=<name>` uses the contract

`src/theme.cyr` (added in 1.10.0) maps each `kind_name` to an
ANSI escape string. The `default` theme is the canonical
**reference palette**: it's what consumers should aim for if
they want their theme to match vyakarana's own diagnostic
output. The `dark` theme is a variant tuned for dark-background
terminals; `none` strips colour entirely (useful in pipes /
non-tty contexts).

A new theme is a new clause in `src/theme.cyr`'s `theme_color()`
and a name in `theme_resolve()`. `vyk` reads no theme files —
themes are compiled in. The other direction shipped instead:
`vyk --export-theme=vscode|helix|iterm` (1.11.1, 1.12.1;
`src/theme_export.cyr`) writes a bundled palette out in an
editor's own format.

## When it can break (and how to spot it)

- **Renaming a `kind_name`.** The compiler doesn't catch this
  — the rename succeeds, but every theme file in every
  downstream consumer breaks silently. Mitigation: any change
  to `kind_name` requires an ADR + CHANGELOG `Breaking` entry
  and is scheduled for a major release (3.0 or later).
- **Adding an eleventh kind.** Same shape — silent fallback
  in consumers. Same mitigation.
- **Reordering the integer values of `TK_*` constants.** Less
  visible to themes (they key by name), but breaks anyone
  reading the binary tokenbuf bytes directly. Mitigation: the
  integer values are also stable per
  [ADR 0002](../adr/0002-token-storage-layout.md) (12-byte
  contiguous record).

## Where to verify

- `src/token.cyr` — the canonical TK_* definitions and
  `kind_name`. Don't edit without an ADR.
- `src/theme.cyr` (1.10.0+) — the bundled themes.
- Downstream consumer themes (owl's `src/theme.cyr` and its
  user-theme files; cyim's highlighting) — where the contract
  matters most. This note is what they reference.
