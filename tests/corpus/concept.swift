// vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
// Re-sync when vidya adds a Swift reference sample.
//
// Lexing + parsing of arithmetic expressions, idiomatic Swift.

import Foundation

/*
 * Multi-line block comment using Swift's slash-star pair form.
 * Swift block comments are nestable per the spec; vyakarana's
 * pair rule is greedy and closes at the first slash-star
 * close. Documented gap, same shape as Rust.
 */

// ── Tokens ───────────────────────────────────────────────────────────

enum TokenKind {
    case number
    case plus
    case minus
    case star
    case slash
    case lparen
    case rparen
    case eof
}

struct Token {
    let kind: TokenKind
    let text: String
    let pos: Int
}

// ── Lexer ────────────────────────────────────────────────────────────

final class Lexer {
    private let source: [Character]
    private var pos: Int = 0

    init(_ source: String) {
        self.source = Array(source)
    }

    private func peek() -> Character? {
        guard pos < source.count else { return nil }
        return source[pos]
    }

    private func skipWhitespace() {
        while let c = peek(), c.isWhitespace {
            pos += 1
        }
    }

    func next() -> Token {
        skipWhitespace()
        let start = pos

        guard let c = peek() else {
            return Token(kind: .eof, text: "", pos: pos)
        }

        switch c {
        case "+": pos += 1; return Token(kind: .plus,   text: "+", pos: start)
        case "-": pos += 1; return Token(kind: .minus,  text: "-", pos: start)
        case "*": pos += 1; return Token(kind: .star,   text: "*", pos: start)
        case "/": pos += 1; return Token(kind: .slash,  text: "/", pos: start)
        case "(": pos += 1; return Token(kind: .lparen, text: "(", pos: start)
        case ")": pos += 1; return Token(kind: .rparen, text: ")", pos: start)
        default: break
        }

        if c.isNumber {
            while let d = peek(), d.isNumber {
                pos += 1
            }
            let text = String(source[start..<pos])
            return Token(kind: .number, text: text, pos: start)
        }

        fatalError("unexpected character '\(c)' at \(pos)")
    }
}

// ── AST ──────────────────────────────────────────────────────────────

indirect enum Expr {
    case number(Int64)
    case unary(Character, Expr)
    case binop(Character, Expr, Expr)

    func eval() -> Int64 {
        switch self {
        case .number(let v): return v
        case .unary(_, let e): return -e.eval()
        case .binop(let op, let l, let r):
            let a = l.eval()
            let b = r.eval()
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            case "/": return a / b
            default:  fatalError("bad op \(op)")
            }
        }
    }
}

// ── Pratt parser ─────────────────────────────────────────────────────

final class Parser {
    private let lexer: Lexer
    private var current: Token

    init(_ source: String) {
        let l = Lexer(source)
        self.lexer = l
        self.current = l.next()
    }

    private func advance() {
        current = lexer.next()
    }

    private static func infixBp(_ k: TokenKind) -> Int {
        switch k {
        case .plus, .minus:  return 1
        case .star, .slash:  return 3
        default:             return 0
        }
    }

    func parseExpr(_ minBp: Int) -> Expr {
        var left = parsePrimary()
        while true {
            let bp = Self.infixBp(current.kind)
            if bp == 0 || bp < minBp { break }
            let op = Character(current.text)
            advance()
            let right = parseExpr(bp + 1)
            left = .binop(op, left, right)
        }
        return left
    }

    private func parsePrimary() -> Expr {
        if current.kind == .minus {
            advance()
            return .unary("-", parsePrimary())
        }
        if current.kind == .lparen {
            advance()
            let inner = parseExpr(0)
            guard current.kind == .rparen else {
                fatalError("expected )")
            }
            advance()
            return inner
        }
        if current.kind == .number {
            let v = Int64(current.text) ?? 0
            advance()
            return .number(v)
        }
        fatalError("unexpected token")
    }
}

// ── Demo ─────────────────────────────────────────────────────────────

let cases: [(String, Int64)] = [
    ("1 + 2",       3),
    ("2 * 3 + 4",   10),
    ("(1 + 2) * 3", 9),
    ("-5 + 3",      -2),
]

for (input, expected) in cases {
    let got = Parser(input).parseExpr(0).eval()
    let line = """
        \(input.padding(toLength: 15, withPad: " ", startingAt: 0)) \
        => \(got) (expected \(expected))
        """
    print(line)
    precondition(got == expected, "mismatch at \"\(input)\"")
}
