# vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
# Re-sync when vidya adds a Ruby reference sample.
#
# Lexing + parsing of arithmetic expressions, idiomatic Ruby.

=begin
Multi-line block comment using Ruby's =begin / =end form. These
markers must each appear at column 0 to be recognised by MRI;
this stand-in respects that constraint.
=end

# ── Tokens ───────────────────────────────────────────────────────────

module Vyakarana
  module Concept
    NUMBER = :number
    PLUS   = :plus
    MINUS  = :minus
    STAR   = :star
    SLASH  = :slash
    LPAREN = :lparen
    RPAREN = :rparen
    EOF    = :eof

    Token = Struct.new(:kind, :text, :pos) do
      def to_s
        "Token(#{kind}, #{text}, #{pos})"
      end
    end

    # ── Lexer ──────────────────────────────────────────────────────

    class Lexer
      def initialize(source)
        @source = source
        @pos = 0
      end

      def next_token
        skip_whitespace
        start = @pos

        return Token.new(EOF, '', @pos) if @pos >= @source.length

        c = @source[@pos]
        case c
        when '+' then @pos += 1; return Token.new(PLUS,   '+', start)
        when '-' then @pos += 1; return Token.new(MINUS,  '-', start)
        when '*' then @pos += 1; return Token.new(STAR,   '*', start)
        when '/' then @pos += 1; return Token.new(SLASH,  '/', start)
        when '(' then @pos += 1; return Token.new(LPAREN, '(', start)
        when ')' then @pos += 1; return Token.new(RPAREN, ')', start)
        end

        if digit?(c)
          @pos += 1 while @pos < @source.length && digit?(@source[@pos])
          return Token.new(NUMBER, @source[start...@pos], start)
        end

        raise "unexpected character #{c.inspect} at #{@pos}"
      end

      private

      def digit?(ch)
        ch >= '0' && ch <= '9'
      end

      def skip_whitespace
        @pos += 1 while @pos < @source.length && @source[@pos] =~ /\s/
      end
    end

    # ── AST ────────────────────────────────────────────────────────

    NumberExpr = Struct.new(:value) do
      def eval = value
    end

    UnaryExpr = Struct.new(:op, :operand) do
      def eval = -operand.eval
    end

    BinOpExpr = Struct.new(:op, :left, :right) do
      def eval
        a = left.eval
        b = right.eval
        case op
        when '+' then a + b
        when '-' then a - b
        when '*' then a * b
        when '/' then a / b
        else raise "bad op #{op}"
        end
      end
    end

    # ── Pratt parser ───────────────────────────────────────────────

    class Parser
      INFIX_BP = {
        PLUS  => 1, MINUS => 1,
        STAR  => 3, SLASH => 3,
      }.freeze

      def initialize(source)
        @lexer = Lexer.new(source)
        @current = @lexer.next_token
      end

      def parse_expr(min_bp)
        left = parse_primary
        loop do
          bp = INFIX_BP[@current.kind] || 0
          break if bp == 0 || bp < min_bp

          op = @current.text
          advance
          right = parse_expr(bp + 1)
          left = BinOpExpr.new(op, left, right)
        end
        left
      end

      private

      def advance
        @current = @lexer.next_token
      end

      def parse_primary
        if @current.kind == MINUS
          advance
          return UnaryExpr.new('-', parse_primary)
        end

        if @current.kind == LPAREN
          advance
          inner = parse_expr(0)
          raise 'expected )' unless @current.kind == RPAREN
          advance
          return inner
        end

        if @current.kind == NUMBER
          v = @current.text.to_i
          advance
          return NumberExpr.new(v)
        end

        raise "unexpected token #{@current}"
      end
    end
  end
end

# ── Demo ─────────────────────────────────────────────────────────────

if __FILE__ == $PROGRAM_NAME
  cases = [
    ['1 + 2',       3],
    ['2 * 3 + 4',   10],
    ['(1 + 2) * 3', 9],
    ['-5 + 3',      -2],
  ]
  cases.each do |input, expected|
    got = Vyakarana::Concept::Parser.new(input).parse_expr(0).eval
    printf("%-15s => %d (expected %d)\n", input, got, expected)
    raise "mismatch at #{input.inspect}" unless got == expected
  end
end

# 2.3.2 error-hole coverage: backtick command literal runs the
# string in a subshell. Ordinary Ruby, and it used to emit
# TK_ERROR for each backtick.
host = `hostname`.strip
files = `ls -1`.split("\n")
