// vyakarana stand-in -- not from vidya. See docs/adrs/0006.
// Re-sync when vidya adds a JS reference sample.

'use strict';

const STANDIN = true;
const NOTE = "vyakarana stand-in for JS; delete when vidya ships a sample.";

// ── Tokens ───────────────────────────────────────────────────────────

const TokenKind = Object.freeze({
    Number:  'number',
    Plus:    'plus',
    Minus:   'minus',
    Star:    'star',
    Slash:   'slash',
    LParen:  'lparen',
    RParen:  'rparen',
    Eof:     'eof',
});

class Token {
    constructor(kind, text, pos) {
        this.kind = kind;
        this.text = text;
        this.pos  = pos;
    }
    toString() {
        return `Token(${this.kind}, ${this.text}, ${this.pos})`;
    }
}

// ── Lexer ────────────────────────────────────────────────────────────

class Lexer {
    constructor(source) {
        this.source = source;
        this.pos = 0;
    }

    peek() {
        return this.pos < this.source.length ? this.source[this.pos] : null;
    }

    advance() {
        return this.pos < this.source.length ? this.source[this.pos++] : null;
    }

    skipWhitespace() {
        while (this.pos < this.source.length && /\s/.test(this.source[this.pos])) {
            this.pos++;
        }
    }

    next() {
        this.skipWhitespace();
        if (this.pos >= this.source.length) {
            return new Token(TokenKind.Eof, '', this.pos);
        }
        const start = this.pos;
        const ch = this.source[this.pos];

        if (/[0-9]/.test(ch)) {
            while (this.pos < this.source.length && /[0-9]/.test(this.source[this.pos])) {
                this.pos++;
            }
            return new Token(TokenKind.Number, this.source.slice(start, this.pos), start);
        }

        const ops = {
            '+': TokenKind.Plus,
            '-': TokenKind.Minus,
            '*': TokenKind.Star,
            '/': TokenKind.Slash,
            '(': TokenKind.LParen,
            ')': TokenKind.RParen,
        };
        if (ops[ch] !== undefined) {
            this.pos++;
            return new Token(ops[ch], ch, start);
        }

        throw new Error(`unexpected character '${ch}' at position ${start}`);
    }
}

// ── Pratt parser ─────────────────────────────────────────────────────

function parseExpr(lexer, minBp = 0) {
    let lhs;
    let tok = lexer.next();

    if (tok.kind === TokenKind.Number) {
        lhs = Number(tok.text);
    } else if (tok.kind === TokenKind.Minus) {
        const inner = parseExpr(lexer, 9);
        lhs = -inner;
    } else if (tok.kind === TokenKind.LParen) {
        lhs = parseExpr(lexer, 0);
        const close = lexer.next();
        if (close.kind !== TokenKind.RParen) {
            throw new Error(`expected ')' at ${close.pos}`);
        }
    } else {
        throw new Error(`expected expression at ${tok.pos}, got ${tok.kind}`);
    }

    for (;;) {
        const op = lexer.next();
        const bp = bindingPower(op.kind);
        if (bp === null || bp <= minBp) {
            lexer.pos -= (op.kind === TokenKind.Eof ? 0 : op.text.length);
            break;
        }
        const rhs = parseExpr(lexer, bp);
        lhs = applyOp(op.kind, lhs, rhs);
    }
    return lhs;
}

function bindingPower(kind) {
    switch (kind) {
        case TokenKind.Plus:
        case TokenKind.Minus:
            return 1;
        case TokenKind.Star:
        case TokenKind.Slash:
            return 3;
        default:
            return null;
    }
}

function applyOp(kind, lhs, rhs) {
    switch (kind) {
        case TokenKind.Plus:  return lhs + rhs;
        case TokenKind.Minus: return lhs - rhs;
        case TokenKind.Star:  return lhs * rhs;
        case TokenKind.Slash: return lhs / rhs;
        default: throw new Error(`unknown op ${kind}`);
    }
}

// ── Smoke check ──────────────────────────────────────────────────────

const cases = [
    { input: '1 + 2',            expected: 3  },
    { input: '2 + 3 * 4',        expected: 14 },
    { input: '(2 + 3) * 4',      expected: 20 },
    { input: '10 - 4 / 2',       expected: 8  },
];

for (const { input, expected } of cases) {
    const lexer = new Lexer(input);
    const got = parseExpr(lexer);
    if (got !== expected) {
        throw new Error(`mismatch: ${input} => ${got} !== ${expected}`);
    }
}

console.log(`${cases.length} cases passed`);
