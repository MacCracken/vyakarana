// vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
// Re-sync when vidya adds a Java reference sample.
//
// Lexing + parsing of arithmetic expressions. Mirrors the
// content/lexing_and_parsing/ pattern (rust.rs, go.go, etc.).

package com.example.vyakarana;

import java.util.ArrayList;
import java.util.List;

/*
 * Multi-line block comment exercising the slash-star pair rule
 * across multiple lines. C/C++/Java family share this shape.
 */

public final class ConceptParser {

    // ── Tokens ───────────────────────────────────────────────────────

    public enum TokenKind {
        NUMBER, PLUS, MINUS, STAR, SLASH, LPAREN, RPAREN, EOF
    }

    public static final class Token {
        public final TokenKind kind;
        public final String text;
        public final int pos;

        public Token(TokenKind kind, String text, int pos) {
            this.kind = kind;
            this.text = text;
            this.pos = pos;
        }

        @Override
        public String toString() {
            return String.format("Token(%s, %s, %d)", kind, text, pos);
        }
    }

    // ── Lexer ────────────────────────────────────────────────────────

    public static final class Lexer {
        private final String source;
        private int pos = 0;

        public Lexer(String source) {
            this.source = source;
        }

        private char peek() {
            return pos < source.length() ? source.charAt(pos) : '\0';
        }

        private void skipWhitespace() {
            while (pos < source.length() && Character.isWhitespace(source.charAt(pos))) {
                pos++;
            }
        }

        public Token next() {
            skipWhitespace();
            int start = pos;

            if (pos >= source.length()) {
                return new Token(TokenKind.EOF, "", pos);
            }

            char c = source.charAt(pos);

            switch (c) {
                case '+': pos++; return new Token(TokenKind.PLUS,   "+", start);
                case '-': pos++; return new Token(TokenKind.MINUS,  "-", start);
                case '*': pos++; return new Token(TokenKind.STAR,   "*", start);
                case '/': pos++; return new Token(TokenKind.SLASH,  "/", start);
                case '(': pos++; return new Token(TokenKind.LPAREN, "(", start);
                case ')': pos++; return new Token(TokenKind.RPAREN, ")", start);
                default:
                    break;
            }

            if (Character.isDigit(c)) {
                while (pos < source.length() && Character.isDigit(source.charAt(pos))) {
                    pos++;
                }
                String text = source.substring(start, pos);
                return new Token(TokenKind.NUMBER, text, start);
            }

            throw new IllegalStateException(
                String.format("unexpected character '%c' at %d", c, pos));
        }
    }

    // ── Pratt parser ─────────────────────────────────────────────────

    public sealed interface Expr permits NumberExpr, BinOpExpr, UnaryExpr {}
    public record NumberExpr(long value) implements Expr {}
    public record BinOpExpr(char op, Expr left, Expr right) implements Expr {}
    public record UnaryExpr(char op, Expr operand) implements Expr {}

    public static final class Parser {
        private final Lexer lexer;
        private Token current;

        public Parser(String source) {
            this.lexer = new Lexer(source);
            this.current = lexer.next();
        }

        private Token advance() {
            Token prev = current;
            current = lexer.next();
            return prev;
        }

        private static int infixBp(TokenKind k) {
            return switch (k) {
                case PLUS, MINUS -> 1;
                case STAR, SLASH -> 3;
                default -> 0;
            };
        }

        public Expr parseExpr(int minBp) {
            Expr left = parsePrimary();
            while (true) {
                int bp = infixBp(current.kind);
                if (bp == 0 || bp < minBp) break;
                char op = current.text.charAt(0);
                advance();
                Expr right = parseExpr(bp + 1);
                left = new BinOpExpr(op, left, right);
            }
            return left;
        }

        private Expr parsePrimary() {
            if (current.kind == TokenKind.MINUS) {
                advance();
                return new UnaryExpr('-', parsePrimary());
            }
            if (current.kind == TokenKind.LPAREN) {
                advance();
                Expr inner = parseExpr(0);
                if (current.kind != TokenKind.RPAREN) {
                    throw new IllegalStateException("expected )");
                }
                advance();
                return inner;
            }
            if (current.kind == TokenKind.NUMBER) {
                long val = Long.parseLong(current.text);
                advance();
                return new NumberExpr(val);
            }
            throw new IllegalStateException("unexpected token " + current);
        }
    }

    // ── Demo ─────────────────────────────────────────────────────────

    public static long eval(Expr e) {
        return switch (e) {
            case NumberExpr n  -> n.value();
            case UnaryExpr u   -> -eval(u.operand());
            case BinOpExpr b   -> switch (b.op()) {
                case '+' -> eval(b.left()) + eval(b.right());
                case '-' -> eval(b.left()) - eval(b.right());
                case '*' -> eval(b.left()) * eval(b.right());
                case '/' -> eval(b.left()) / eval(b.right());
                default  -> throw new IllegalStateException("op " + b.op());
            };
        };
    }

    public static void main(String[] args) {
        List<String> cases = new ArrayList<>(List.of(
            "1 + 2",
            "2 * 3 + 4",
            "(1 + 2) * 3",
            "-5 + 3"
        ));
        long[] expected = { 3L, 10L, 9L, -2L };
        for (int i = 0; i < cases.size(); i++) {
            long got = eval(new Parser(cases.get(i)).parseExpr(0));
            System.out.printf("%-15s => %d (expected %d)%n",
                cases.get(i), got, expected[i]);
            assert got == expected[i] : "mismatch at " + cases.get(i);
        }
    }
}

// 2.3.2 error-hole coverage: a `\u` escape inside a char
// literal. ADR 0010's char scanner models 'C', '\C' and
// '\xHH', so the four-hex form needs the operator fallback.
class UnicodeEscapes {
    static final char A = '\u0041';
    static final char NL = '\n';
}
