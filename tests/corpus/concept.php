<?php
// vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
// Re-sync when vidya adds a PHP reference sample.
//
// Lexing + parsing of arithmetic expressions, modern PHP.

declare(strict_types=1);

namespace Vyakarana\Concept;

/*
 * Multi-line block comment exercising the slash-star pair rule
 * across multiple lines. Same shape as C / Java / C++.
 */

// ── Tokens ───────────────────────────────────────────────────────────

enum TokenKind: string {
    case Number = 'number';
    case Plus   = 'plus';
    case Minus  = 'minus';
    case Star   = 'star';
    case Slash  = 'slash';
    case LParen = 'lparen';
    case RParen = 'rparen';
    case Eof    = 'eof';
}

final readonly class Token {
    public function __construct(
        public TokenKind $kind,
        public string $text,
        public int $pos,
    ) {}

    public function __toString(): string {
        return "Token({$this->kind->value}, {$this->text}, {$this->pos})";
    }
}

// ── Lexer ────────────────────────────────────────────────────────────

final class Lexer {
    private int $pos = 0;

    public function __construct(private readonly string $source) {}

    private function skipWhitespace(): void {
        while ($this->pos < strlen($this->source) && ctype_space($this->source[$this->pos])) {
            $this->pos++;
        }
    }

    public function next(): Token {
        $this->skipWhitespace();
        $start = $this->pos;

        if ($this->pos >= strlen($this->source)) {
            return new Token(TokenKind::Eof, '', $this->pos);
        }

        $c = $this->source[$this->pos];
        switch ($c) {
            case '+': $this->pos++; return new Token(TokenKind::Plus,   '+', $start);
            case '-': $this->pos++; return new Token(TokenKind::Minus,  '-', $start);
            case '*': $this->pos++; return new Token(TokenKind::Star,   '*', $start);
            case '/': $this->pos++; return new Token(TokenKind::Slash,  '/', $start);
            case '(': $this->pos++; return new Token(TokenKind::LParen, '(', $start);
            case ')': $this->pos++; return new Token(TokenKind::RParen, ')', $start);
        }

        if (ctype_digit($c)) {
            while ($this->pos < strlen($this->source) && ctype_digit($this->source[$this->pos])) {
                $this->pos++;
            }
            return new Token(TokenKind::Number, substr($this->source, $start, $this->pos - $start), $start);
        }

        throw new \RuntimeException("unexpected character at {$this->pos}");
    }
}

// ── AST ──────────────────────────────────────────────────────────────

abstract class Expr {
    abstract public function eval(): int;
}

final class NumberExpr extends Expr {
    public function __construct(public readonly int $value) {}
    public function eval(): int { return $this->value; }
}

final class UnaryExpr extends Expr {
    public function __construct(
        public readonly string $op,
        public readonly Expr $operand,
    ) {}
    public function eval(): int { return -$this->operand->eval(); }
}

final class BinOpExpr extends Expr {
    public function __construct(
        public readonly string $op,
        public readonly Expr $left,
        public readonly Expr $right,
    ) {}

    public function eval(): int {
        $a = $this->left->eval();
        $b = $this->right->eval();
        return match ($this->op) {
            '+' => $a + $b,
            '-' => $a - $b,
            '*' => $a * $b,
            '/' => intdiv($a, $b),
            default => throw new \RuntimeException("bad op {$this->op}"),
        };
    }
}

// ── Pratt parser ─────────────────────────────────────────────────────

final class Parser {
    private Lexer $lexer;
    private Token $current;

    public function __construct(string $source) {
        $this->lexer = new Lexer($source);
        $this->current = $this->lexer->next();
    }

    private function advance(): void {
        $this->current = $this->lexer->next();
    }

    private static function infixBp(TokenKind $k): int {
        return match ($k) {
            TokenKind::Plus, TokenKind::Minus => 1,
            TokenKind::Star, TokenKind::Slash => 3,
            default => 0,
        };
    }

    public function parseExpr(int $minBp): Expr {
        $left = $this->parsePrimary();
        while (true) {
            $bp = self::infixBp($this->current->kind);
            if ($bp === 0 || $bp < $minBp) break;
            $op = $this->current->text;
            $this->advance();
            $right = $this->parseExpr($bp + 1);
            $left = new BinOpExpr($op, $left, $right);
        }
        return $left;
    }

    private function parsePrimary(): Expr {
        if ($this->current->kind === TokenKind::Minus) {
            $this->advance();
            return new UnaryExpr('-', $this->parsePrimary());
        }
        if ($this->current->kind === TokenKind::LParen) {
            $this->advance();
            $inner = $this->parseExpr(0);
            if ($this->current->kind !== TokenKind::RParen) {
                throw new \RuntimeException('expected )');
            }
            $this->advance();
            return $inner;
        }
        if ($this->current->kind === TokenKind::Number) {
            $v = (int) $this->current->text;
            $this->advance();
            return new NumberExpr($v);
        }
        throw new \RuntimeException("unexpected token {$this->current}");
    }
}

// ── Demo ─────────────────────────────────────────────────────────────

$cases = [
    ['1 + 2',       3],
    ['2 * 3 + 4',   10],
    ['(1 + 2) * 3', 9],
    ['-5 + 3',      -2],
];

foreach ($cases as [$input, $expected]) {
    $got = (new Parser($input))->parseExpr(0)->eval();
    printf("%-15s => %d (expected %d)\n", $input, $got, $expected);
    if ($got !== $expected) {
        throw new \RuntimeException("mismatch at \"{$input}\"");
    }
}

<?php
// 2.3.2 error-hole coverage: PHP's backtick operator is
// shell_exec() by another spelling.
$listing = `ls -l`;
echo $listing;
