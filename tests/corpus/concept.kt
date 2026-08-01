// vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
// Re-sync when vidya adds a Kotlin reference sample.
//
// Lexing + parsing of arithmetic expressions, Kotlin idioms.

package com.example.vyakarana

import kotlin.text.StringBuilder

// ── Tokens ───────────────────────────────────────────────────────────

enum class TokenKind {
    NUMBER, PLUS, MINUS, STAR, SLASH, LPAREN, RPAREN, EOF
}

data class Token(val kind: TokenKind, val text: String, val pos: Int) {
    override fun toString(): String = "Token($kind, $text, $pos)"
}

// ── Lexer ────────────────────────────────────────────────────────────

class Lexer(private val source: String) {
    private var pos: Int = 0

    private fun peek(): Char =
        if (pos < source.length) source[pos] else '_'

    private fun skipWhitespace() {
        while (pos < source.length && source[pos].isWhitespace()) {
            pos++
        }
    }

    fun next(): Token {
        skipWhitespace()
        val start = pos

        if (pos >= source.length) {
            return Token(TokenKind.EOF, "", pos)
        }

        val c = source[pos]
        when (c) {
            '+' -> { pos++; return Token(TokenKind.PLUS,   "+", start) }
            '-' -> { pos++; return Token(TokenKind.MINUS,  "-", start) }
            '*' -> { pos++; return Token(TokenKind.STAR,   "*", start) }
            '/' -> { pos++; return Token(TokenKind.SLASH,  "/", start) }
            '(' -> { pos++; return Token(TokenKind.LPAREN, "(", start) }
            ')' -> { pos++; return Token(TokenKind.RPAREN, ")", start) }
        }

        if (c.isDigit()) {
            while (pos < source.length && source[pos].isDigit()) {
                pos++
            }
            return Token(TokenKind.NUMBER, source.substring(start, pos), start)
        }

        error("unexpected character '$c' at $pos")
    }
}

// ── AST ──────────────────────────────────────────────────────────────

sealed interface Expr
data class NumberExpr(val value: Long) : Expr
data class BinOpExpr(val op: Char, val left: Expr, val right: Expr) : Expr
data class UnaryExpr(val op: Char, val operand: Expr) : Expr

// ── Pratt parser ─────────────────────────────────────────────────────

class Parser(source: String) {
    private val lexer = Lexer(source)
    private var current: Token = lexer.next()

    private fun advance(): Token {
        val prev = current
        current = lexer.next()
        return prev
    }

    private fun infixBp(k: TokenKind): Int = when (k) {
        TokenKind.PLUS, TokenKind.MINUS -> 1
        TokenKind.STAR, TokenKind.SLASH -> 3
        else -> 0
    }

    fun parseExpr(minBp: Int): Expr {
        var left: Expr = parsePrimary()
        while (true) {
            val bp = infixBp(current.kind)
            if (bp == 0 || bp < minBp) break
            val op = current.text[0]
            advance()
            val right = parseExpr(bp + 1)
            left = BinOpExpr(op, left, right)
        }
        return left
    }

    private fun parsePrimary(): Expr {
        if (current.kind == TokenKind.MINUS) {
            advance()
            return UnaryExpr('-', parsePrimary())
        }
        if (current.kind == TokenKind.LPAREN) {
            advance()
            val inner = parseExpr(0)
            check(current.kind == TokenKind.RPAREN) { "expected )" }
            advance()
            return inner
        }
        if (current.kind == TokenKind.NUMBER) {
            val v = current.text.toLong()
            advance()
            return NumberExpr(v)
        }
        error("unexpected token $current")
    }
}

// ── Evaluator ────────────────────────────────────────────────────────

fun eval(e: Expr): Long = when (e) {
    is NumberExpr -> e.value
    is UnaryExpr  -> -eval(e.operand)
    is BinOpExpr  -> when (e.op) {
        '+' -> eval(e.left) + eval(e.right)
        '-' -> eval(e.left) - eval(e.right)
        '*' -> eval(e.left) * eval(e.right)
        '/' -> eval(e.left) / eval(e.right)
        else -> error("op ${e.op}")
    }
}

// ── Demo ─────────────────────────────────────────────────────────────

fun main() {
    val cases = listOf(
        "1 + 2"          to 3L,
        "2 * 3 + 4"      to 10L,
        "(1 + 2) * 3"    to 9L,
        "-5 + 3"         to -2L,
    )
    for ((input, expected) in cases) {
        val got = eval(Parser(input).parseExpr(0))
        println("%-15s => %d (expected %d)".format(input, got, expected))
        require(got == expected) { "mismatch at \"$input\"" }
    }
}

// 2.3.2 error-hole coverage: backtick-escaped identifiers. The
// test-naming idiom below is the most common Kotlin use of them.
fun `tokenizes an empty input`() { }

val `object` = "reserved word used as a name"
