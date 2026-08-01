// vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
// Re-sync when vidya adds a C++ reference sample.
//
// Lexing + parsing of arithmetic expressions, modern C++ idioms.

#include <cstdint>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace vyakarana::concept {

// ── Tokens ───────────────────────────────────────────────────────────

enum class TokenKind {
    Number,
    Plus,
    Minus,
    Star,
    Slash,
    LParen,
    RParen,
    Eof,
};

struct Token {
    TokenKind kind;
    std::string text;
    std::size_t pos;
};

// ── Lexer ────────────────────────────────────────────────────────────

class Lexer {
public:
    explicit Lexer(std::string source) : source_(std::move(source)), pos_(0) {}

    Token next() {
        skipWhitespace();
        const std::size_t start = pos_;

        if (pos_ >= source_.size()) {
            return Token{TokenKind::Eof, "", pos_};
        }

        const char c = source_[pos_];
        switch (c) {
            case '+': ++pos_; return Token{TokenKind::Plus,   "+", start};
            case '-': ++pos_; return Token{TokenKind::Minus,  "-", start};
            case '*': ++pos_; return Token{TokenKind::Star,   "*", start};
            case '/': ++pos_; return Token{TokenKind::Slash,  "/", start};
            case '(': ++pos_; return Token{TokenKind::LParen, "(", start};
            case ')': ++pos_; return Token{TokenKind::RParen, ")", start};
            default: break;
        }

        if (isDigit(c)) {
            while (pos_ < source_.size() && isDigit(source_[pos_])) {
                ++pos_;
            }
            return Token{TokenKind::Number, source_.substr(start, pos_ - start), start};
        }

        throw std::runtime_error("unexpected character at " + std::to_string(pos_));
    }

private:
    static bool isDigit(char c) { return c >= '0' && c <= '9'; }

    void skipWhitespace() {
        while (pos_ < source_.size() && std::isspace(static_cast<unsigned char>(source_[pos_]))) {
            ++pos_;
        }
    }

    std::string source_;
    std::size_t pos_;
};

// ── AST ──────────────────────────────────────────────────────────────

struct Expr {
    virtual ~Expr() = default;
    virtual std::int64_t eval() const = 0;
};

using ExprPtr = std::unique_ptr<Expr>;

struct NumberExpr final : Expr {
    std::int64_t value;
    explicit NumberExpr(std::int64_t v) : value(v) {}
    std::int64_t eval() const override { return value; }
};

struct UnaryExpr final : Expr {
    char op;
    ExprPtr operand;
    UnaryExpr(char o, ExprPtr e) : op(o), operand(std::move(e)) {}
    std::int64_t eval() const override { return -operand->eval(); }
};

struct BinOpExpr final : Expr {
    char op;
    ExprPtr left;
    ExprPtr right;
    BinOpExpr(char o, ExprPtr l, ExprPtr r)
        : op(o), left(std::move(l)), right(std::move(r)) {}

    std::int64_t eval() const override {
        const auto a = left->eval();
        const auto b = right->eval();
        switch (op) {
            case '+': return a + b;
            case '-': return a - b;
            case '*': return a * b;
            case '/': return a / b;
            default:  throw std::runtime_error("bad op");
        }
    }
};

// ── Pratt parser ─────────────────────────────────────────────────────

class Parser {
public:
    explicit Parser(std::string source)
        : lexer_(std::move(source)), current_(lexer_.next()) {}

    ExprPtr parseExpr(int minBp) {
        ExprPtr left = parsePrimary();
        while (true) {
            const int bp = infixBp(current_.kind);
            if (bp == 0 || bp < minBp) {
                break;
            }
            const char op = current_.text[0];
            advance();
            ExprPtr right = parseExpr(bp + 1);
            left = std::make_unique<BinOpExpr>(op, std::move(left), std::move(right));
        }
        return left;
    }

private:
    void advance() { current_ = lexer_.next(); }

    static int infixBp(TokenKind k) {
        switch (k) {
            case TokenKind::Plus:
            case TokenKind::Minus: return 1;
            case TokenKind::Star:
            case TokenKind::Slash: return 3;
            default:               return 0;
        }
    }

    ExprPtr parsePrimary() {
        if (current_.kind == TokenKind::Minus) {
            advance();
            return std::make_unique<UnaryExpr>('-', parsePrimary());
        }
        if (current_.kind == TokenKind::LParen) {
            advance();
            ExprPtr inner = parseExpr(0);
            if (current_.kind != TokenKind::RParen) {
                throw std::runtime_error("expected )");
            }
            advance();
            return inner;
        }
        if (current_.kind == TokenKind::Number) {
            std::int64_t v = std::stoll(current_.text);
            advance();
            return std::make_unique<NumberExpr>(v);
        }
        throw std::runtime_error("unexpected token");
    }

    Lexer lexer_;
    Token current_;
};

}  // namespace vyakarana::concept

int main() {
    using vyakarana::concept::Parser;
    const std::vector<std::pair<std::string, std::int64_t>> cases = {
        {"1 + 2",       3},
        {"2 * 3 + 4",   10},
        {"(1 + 2) * 3", 9},
        {"-5 + 3",      -2},
    };
    for (const auto& [input, expected] : cases) {
        const auto got = Parser(input).parseExpr(0)->eval();
        std::cout << input << " => " << got << " (expected " << expected << ")\n";
        if (got != expected) {
            throw std::runtime_error("mismatch");
        }
    }
}

// 2.3.2 error-hole coverage: C++14 digit separators and a
// backslash line continuation in a macro. Both are in c.cyml
// already; cpp.cyml had simply diverged.
constexpr long kMaxTokens = 1'000'000;

#define TRACE_TOKEN(k, n) \
    do { (void)(k); (void)(n); } while (0)
