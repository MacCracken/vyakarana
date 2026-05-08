-- vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
-- Re-sync when vidya adds a Lua reference sample.
--
-- Lexing + parsing of arithmetic expressions, idiomatic Lua.

--[[
Multi-line block comment using Lua's --[[ ... ]] long-bracket
form. The simple version (no = padding) is recognised by this
grammar; the variable-padded form (--[==[ ... ]==]) is a
documented gap.
]]

-- ── Tokens ───────────────────────────────────────────────────────────

local Token = {}
Token.NUMBER = "number"
Token.PLUS   = "plus"
Token.MINUS  = "minus"
Token.STAR   = "star"
Token.SLASH  = "slash"
Token.LPAREN = "lparen"
Token.RPAREN = "rparen"
Token.EOF    = "eof"

local function make_token(kind, text, pos)
    return { kind = kind, text = text, pos = pos }
end

-- ── Lexer ────────────────────────────────────────────────────────────

local Lexer = {}
Lexer.__index = Lexer

function Lexer.new(source)
    local self = setmetatable({}, Lexer)
    self.source = source
    self.pos = 1
    return self
end

local function is_digit(c)
    return c and c >= '0' and c <= '9'
end

function Lexer:peek()
    return self.source:sub(self.pos, self.pos)
end

function Lexer:skip_whitespace()
    while self.pos <= #self.source and self:peek():match("%s") do
        self.pos = self.pos + 1
    end
end

function Lexer:next()
    self:skip_whitespace()
    local start = self.pos

    if self.pos > #self.source then
        return make_token(Token.EOF, "", self.pos)
    end

    local c = self:peek()
    if c == "+" then self.pos = self.pos + 1; return make_token(Token.PLUS,   "+", start) end
    if c == "-" then self.pos = self.pos + 1; return make_token(Token.MINUS,  "-", start) end
    if c == "*" then self.pos = self.pos + 1; return make_token(Token.STAR,   "*", start) end
    if c == "/" then self.pos = self.pos + 1; return make_token(Token.SLASH,  "/", start) end
    if c == "(" then self.pos = self.pos + 1; return make_token(Token.LPAREN, "(", start) end
    if c == ")" then self.pos = self.pos + 1; return make_token(Token.RPAREN, ")", start) end

    if is_digit(c) then
        while self.pos <= #self.source and is_digit(self:peek()) do
            self.pos = self.pos + 1
        end
        return make_token(Token.NUMBER, self.source:sub(start, self.pos - 1), start)
    end

    error(string.format("unexpected character %q at %d", c, self.pos))
end

-- ── AST ──────────────────────────────────────────────────────────────

local function number_expr(value)
    return { kind = "number", value = value }
end

local function unary_expr(op, operand)
    return { kind = "unary", op = op, operand = operand }
end

local function binop_expr(op, left, right)
    return { kind = "binop", op = op, left = left, right = right }
end

local function eval(e)
    if e.kind == "number" then return e.value end
    if e.kind == "unary"  then return -eval(e.operand) end
    if e.kind == "binop"  then
        local a = eval(e.left)
        local b = eval(e.right)
        if e.op == "+" then return a + b end
        if e.op == "-" then return a - b end
        if e.op == "*" then return a * b end
        if e.op == "/" then return a // b end
        error("bad op " .. e.op)
    end
    error("bad expr kind " .. tostring(e.kind))
end

-- ── Pratt parser ─────────────────────────────────────────────────────

local INFIX_BP = {
    [Token.PLUS]  = 1,
    [Token.MINUS] = 1,
    [Token.STAR]  = 3,
    [Token.SLASH] = 3,
}

local Parser = {}
Parser.__index = Parser

function Parser.new(source)
    local self = setmetatable({}, Parser)
    self.lexer = Lexer.new(source)
    self.current = self.lexer:next()
    return self
end

function Parser:advance()
    self.current = self.lexer:next()
end

function Parser:parse_expr(min_bp)
    local left = self:parse_primary()
    while true do
        local bp = INFIX_BP[self.current.kind] or 0
        if bp == 0 or bp < min_bp then break end
        local op = self.current.text
        self:advance()
        local right = self:parse_expr(bp + 1)
        left = binop_expr(op, left, right)
    end
    return left
end

function Parser:parse_primary()
    if self.current.kind == Token.MINUS then
        self:advance()
        return unary_expr("-", self:parse_primary())
    end
    if self.current.kind == Token.LPAREN then
        self:advance()
        local inner = self:parse_expr(0)
        if self.current.kind ~= Token.RPAREN then
            error("expected )")
        end
        self:advance()
        return inner
    end
    if self.current.kind == Token.NUMBER then
        local v = tonumber(self.current.text)
        self:advance()
        return number_expr(v)
    end
    error("unexpected token " .. self.current.kind)
end

-- ── Demo ─────────────────────────────────────────────────────────────

local cases = {
    { "1 + 2",       3 },
    { "2 * 3 + 4",   10 },
    { "(1 + 2) * 3", 9 },
    { "-5 + 3",      -2 },
}

for _, case in ipairs(cases) do
    local input, expected = case[1], case[2]
    local got = eval(Parser.new(input):parse_expr(0))
    print(string.format("%-15s => %d (expected %d)", input, got, expected))
    assert(got == expected, "mismatch at " .. input)
end
