# vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
# Re-sync when vidya adds an Elixir reference sample.
#
# Lexing + parsing of arithmetic expressions, idiomatic Elixir.

defmodule Vyakarana.Concept do
  @moduledoc """
  Pratt-style arithmetic expression evaluator. Demonstrates the
  Elixir token surface: atoms, do/end blocks, the pipe operator,
  pattern matching in function clauses, and module attributes.
  """

  # ── Tokens ─────────────────────────────────────────────────────────

  @kinds [:number, :plus, :minus, :star, :slash, :lparen, :rparen, :eof]

  defmodule Token do
    @enforce_keys [:kind, :text, :pos]
    defstruct [:kind, :text, :pos]
  end

  # ── Lexer ──────────────────────────────────────────────────────────
  # Emits a list of %Token{} structs for an input string.

  def tokenize(source) do
    source
    |> String.graphemes()
    |> tokenize_loop([], 0)
    |> Enum.reverse()
  end

  defp tokenize_loop([], acc, pos) do
    [%Token{kind: :eof, text: "", pos: pos} | acc]
  end

  defp tokenize_loop([" " | rest], acc, pos), do: tokenize_loop(rest, acc, pos + 1)
  defp tokenize_loop(["\t" | rest], acc, pos), do: tokenize_loop(rest, acc, pos + 1)
  defp tokenize_loop(["\n" | rest], acc, pos), do: tokenize_loop(rest, acc, pos + 1)

  defp tokenize_loop(["+" | rest], acc, pos), do: tokenize_loop(rest, [tok(:plus,   "+", pos) | acc], pos + 1)
  defp tokenize_loop(["-" | rest], acc, pos), do: tokenize_loop(rest, [tok(:minus,  "-", pos) | acc], pos + 1)
  defp tokenize_loop(["*" | rest], acc, pos), do: tokenize_loop(rest, [tok(:star,   "*", pos) | acc], pos + 1)
  defp tokenize_loop(["/" | rest], acc, pos), do: tokenize_loop(rest, [tok(:slash,  "/", pos) | acc], pos + 1)
  defp tokenize_loop(["(" | rest], acc, pos), do: tokenize_loop(rest, [tok(:lparen, "(", pos) | acc], pos + 1)
  defp tokenize_loop([")" | rest], acc, pos), do: tokenize_loop(rest, [tok(:rparen, ")", pos) | acc], pos + 1)

  defp tokenize_loop([c | _] = chars, acc, pos) when c in ~w(0 1 2 3 4 5 6 7 8 9) do
    {digits, rest} = Enum.split_while(chars, &digit?/1)
    text = Enum.join(digits)
    tokenize_loop(rest, [tok(:number, text, pos) | acc], pos + String.length(text))
  end

  defp tokenize_loop([c | _], _acc, pos) do
    raise "unexpected character #{inspect(c)} at #{pos}"
  end

  defp tok(kind, text, pos), do: %Token{kind: kind, text: text, pos: pos}

  defp digit?(c), do: c in ~w(0 1 2 3 4 5 6 7 8 9)

  # ── AST ────────────────────────────────────────────────────────────

  defmodule Number,  do: defstruct [:value]
  defmodule Unary,   do: defstruct [:op, :operand]
  defmodule BinOp,   do: defstruct [:op, :left, :right]

  # ── Pratt parser ───────────────────────────────────────────────────
  # Returns {expr, remaining_tokens}.

  @infix_bp %{
    plus: 1, minus: 1,
    star: 3, slash: 3
  }

  def parse(source) do
    tokens = tokenize(source)
    {expr, _rest} = parse_expr(tokens, 0)
    expr
  end

  defp parse_expr(tokens, min_bp) do
    {left, tokens} = parse_primary(tokens)
    parse_infix(tokens, left, min_bp)
  end

  defp parse_infix([%Token{kind: kind} = _tok | _] = tokens, left, min_bp) do
    bp = Map.get(@infix_bp, kind, 0)

    cond do
      bp == 0 or bp < min_bp ->
        {left, tokens}

      true ->
        [%Token{text: op_text} | rest] = tokens
        {right, rest} = parse_expr(rest, bp + 1)
        parse_infix(rest, %BinOp{op: op_text, left: left, right: right}, min_bp)
    end
  end

  defp parse_primary([%Token{kind: :minus} | rest]) do
    {operand, rest} = parse_primary(rest)
    {%Unary{op: "-", operand: operand}, rest}
  end

  defp parse_primary([%Token{kind: :lparen} | rest]) do
    {inner, rest} = parse_expr(rest, 0)
    case rest do
      [%Token{kind: :rparen} | rest2] -> {inner, rest2}
      _ -> raise "expected )"
    end
  end

  defp parse_primary([%Token{kind: :number, text: text} | rest]) do
    {%Number{value: String.to_integer(text)}, rest}
  end

  defp parse_primary([tok | _]) do
    raise "unexpected token #{inspect(tok)}"
  end

  # ── Evaluator ──────────────────────────────────────────────────────

  def eval(%Number{value: v}), do: v
  def eval(%Unary{operand: e}), do: -eval(e)
  def eval(%BinOp{op: op, left: l, right: r}) do
    a = eval(l)
    b = eval(r)
    case op do
      "+" -> a + b
      "-" -> a - b
      "*" -> a * b
      "/" -> div(a, b)
    end
  end
end

# ── Demo ─────────────────────────────────────────────────────────────

cases = [
  {"1 + 2",       3},
  {"2 * 3 + 4",   10},
  {"(1 + 2) * 3", 9},
  {"-5 + 3",      -2}
]

Enum.each(cases, fn {input, expected} ->
  got = input |> Vyakarana.Concept.parse() |> Vyakarana.Concept.eval()
  IO.puts("#{String.pad_trailing(input, 15)} => #{got} (expected #{expected})")
  ^expected = got
end)
