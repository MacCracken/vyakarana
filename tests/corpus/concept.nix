# Vidya — Lexing and Parsing in Nix
#
# Nix is the functional, lazy-evaluated configuration language
# that powers NixOS, home-manager, and the broader Nix
# ecosystem. A "tokenizer" here is itself a value: a function
# from a string to a list of attribute sets.

{ pkgs ? import <nixpkgs> { } }:

let
  /* Predicate helpers. Nix has only single-arg functions;
     "multi-arg" is currying. The `c: ...` syntax is one lambda,
     `c: x: ...` is two nested lambdas. */
  isDigit = c: c >= "0" && c <= "9";
  isLetter = c:
    (c >= "a" && c <= "z")
    || (c >= "A" && c <= "Z")
    || c == "_";
  isSpace = c: c == " " || c == "\t" || c == "\n";

  keywords = [ "if" "while" "for" "def" "class" ];

  # Recursive set: the tokenizer state machine. `rec` lets
  # entries reference each other by name without a `let`
  # wrapper. Note `'` in `iter'` — Haskell-style prime.
  lexer = rec {
    classify = c:
      if isDigit c then "digit"
      else if isLetter c then "letter"
      else if isSpace c then "space"
      else "punct";

    iter = state: i:
      if i >= builtins.stringLength state.src then state
      else
        let
          c = builtins.substring i 1 state.src;
          kind = classify c;
        in iter' (state // { kind = kind; }) (i + 1);

    iter' = state: nextI:
      let
        token = {
          kind = state.kind;
          start = state.start or 0;
          len = nextI - (state.start or 0);
        };
      in state // {
        tokens = state.tokens ++ [ token ];
      };
  };


  # Multi-line indented strings using `'' ... ''`. Useful for
  # config-file content, scripts embedded in derivations.
  helpText = ''
    Tokenize a string with the trivial lexer.

    Example:
      lexer.iter { src = "42 hi"; tokens = [ ]; } 0
  '';


  # Attribute-set destructuring with `@` pattern preserves the
  # original argument so callers can pass extra fields without
  # the lambda having to enumerate them.
  toJSON = { src, tokens, ... }@all:
    builtins.toJSON {
      inherit src tokens;
      total = builtins.length tokens;
    };


  # Inherit pulls names from another scope into the current
  # set without re-binding.
  reexports = { inherit (lexer) classify iter; };


  # Set merge `//` — right side wins on conflicts.
  defaults = { mode = "lex"; verbose = false; };
  config   = defaults // { verbose = true; depth = 3; };

in
{
  inherit (lexer) classify iter;
  inherit helpText toJSON reexports config;

  # Drive it. `with config; ...` brings the keys into scope.
  example = with config; {
    inherit mode verbose;
    notes = "Lex demo built with ${mode} mode";
  };
}

# 2.3.2 error-hole coverage: `~` opens a home-relative path
# literal. Path literals themselves stay a documented gap; this
# just keeps the leading `~` off TK_ERROR.
{
  configFile = ~/.config/vyakarana/config.toml;
  cacheDir = ~/.cache/vyakarana;
}
