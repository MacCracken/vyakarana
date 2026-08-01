// vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
// Re-sync when vidya adds a C# reference sample.
//
// Lexing + parsing of arithmetic expressions, modern C# idioms.

using System;
using System.Collections.Generic;

namespace Vyakarana.ConceptParser;

// ── Tokens ───────────────────────────────────────────────────────────

public enum TokenKind
{
    Number,
    Plus,
    Minus,
    Star,
    Slash,
    LParen,
    RParen,
    Eof,
}

public readonly record struct Token(TokenKind Kind, string Text, int Pos);

// ── Lexer ────────────────────────────────────────────────────────────

public sealed class Lexer
{
    private readonly string _source;
    private int _pos;

    public Lexer(string source)
    {
        _source = source;
        _pos = 0;
    }

    private void SkipWhitespace()
    {
        while (_pos < _source.Length && char.IsWhiteSpace(_source[_pos]))
        {
            _pos++;
        }
    }

    public Token Next()
    {
        SkipWhitespace();
        var start = _pos;

        if (_pos >= _source.Length)
        {
            return new Token(TokenKind.Eof, "", _pos);
        }

        var c = _source[_pos];
        switch (c)
        {
            case '+': _pos++; return new Token(TokenKind.Plus,   "+", start);
            case '-': _pos++; return new Token(TokenKind.Minus,  "-", start);
            case '*': _pos++; return new Token(TokenKind.Star,   "*", start);
            case '/': _pos++; return new Token(TokenKind.Slash,  "/", start);
            case '(': _pos++; return new Token(TokenKind.LParen, "(", start);
            case ')': _pos++; return new Token(TokenKind.RParen, ")", start);
        }

        if (char.IsDigit(c))
        {
            while (_pos < _source.Length && char.IsDigit(_source[_pos]))
            {
                _pos++;
            }
            return new Token(TokenKind.Number, _source[start.._pos], start);
        }

        throw new InvalidOperationException($"unexpected character at {_pos}");
    }
}

// ── AST ──────────────────────────────────────────────────────────────

public abstract record Expr
{
    public abstract long Eval();
}

public sealed record NumberExpr(long Value) : Expr
{
    public override long Eval() => Value;
}

public sealed record UnaryExpr(char Op, Expr Operand) : Expr
{
    public override long Eval() => -Operand.Eval();
}

public sealed record BinOpExpr(char Op, Expr Left, Expr Right) : Expr
{
    public override long Eval() => Op switch
    {
        '+' => Left.Eval() + Right.Eval(),
        '-' => Left.Eval() - Right.Eval(),
        '*' => Left.Eval() * Right.Eval(),
        '/' => Left.Eval() / Right.Eval(),
        _   => throw new InvalidOperationException($"bad op {Op}"),
    };
}

// ── Pratt parser ─────────────────────────────────────────────────────

public sealed class Parser
{
    private readonly Lexer _lexer;
    private Token _current;

    public Parser(string source)
    {
        _lexer = new Lexer(source);
        _current = _lexer.Next();
    }

    private void Advance() { _current = _lexer.Next(); }

    private static int InfixBp(TokenKind k) => k switch
    {
        TokenKind.Plus or TokenKind.Minus => 1,
        TokenKind.Star or TokenKind.Slash => 3,
        _                                  => 0,
    };

    public Expr ParseExpr(int minBp)
    {
        var left = ParsePrimary();
        while (true)
        {
            var bp = InfixBp(_current.Kind);
            if (bp == 0 || bp < minBp) break;
            var op = _current.Text[0];
            Advance();
            var right = ParseExpr(bp + 1);
            left = new BinOpExpr(op, left, right);
        }
        return left;
    }

    private Expr ParsePrimary()
    {
        if (_current.Kind == TokenKind.Minus)
        {
            Advance();
            return new UnaryExpr('-', ParsePrimary());
        }
        if (_current.Kind == TokenKind.LParen)
        {
            Advance();
            var inner = ParseExpr(0);
            if (_current.Kind != TokenKind.RParen)
            {
                throw new InvalidOperationException("expected )");
            }
            Advance();
            return inner;
        }
        if (_current.Kind == TokenKind.Number)
        {
            var v = long.Parse(_current.Text);
            Advance();
            return new NumberExpr(v);
        }
        throw new InvalidOperationException($"unexpected token {_current}");
    }
}

// ── Demo ─────────────────────────────────────────────────────────────

public static class Program
{
    public static void Main()
    {
        var cases = new List<(string Input, long Expected)>
        {
            ("1 + 2",       3L),
            ("2 * 3 + 4",   10L),
            ("(1 + 2) * 3", 9L),
            ("-5 + 3",      -2L),
        };
        foreach (var (input, expected) in cases)
        {
            var got = new Parser(input).ParseExpr(0).Eval();
            Console.WriteLine($"{input,-15} => {got} (expected {expected})");
            if (got != expected)
            {
                throw new InvalidOperationException($"mismatch at \"{input}\"");
            }
        }
    }
}

// 2.3.2 error-hole coverage: C# preprocessor directives.
#nullable enable
#region Diagnostics
#if DEBUG
#pragma warning disable CS0168
#endif
#endregion
