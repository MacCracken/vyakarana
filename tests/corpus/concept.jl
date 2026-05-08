#!/usr/bin/env julia
# Vidya — Lexing and Parsing in Julia
#
# Julia's just-in-time compilation and rich type system make
# tokenizers feel slightly different from Python: type
# annotations are first-class, multiple-dispatch shapes the
# function definitions, and broadcasting (`.` operator) is
# everywhere.

#=
Block comments span multiple lines. Useful at module headers
to describe purpose, invariants, references. (Avoid quoting
the closing marker inline; the tokenizer doesn't track
nesting and would close the comment early.)
=#


# Backtick command literal — Julia's shell-out syntax.
shell_cmd = `echo hello`
println(shell_cmd)


module Lexer

export tokenize, Token, TokenKind

@enum TokenKind begin
    DIGIT
    LETTER
    SPACE
    PUNCT
end


struct Token
    kind::TokenKind
    start::Int
    len::Int
    text::String
end


function classify_byte(c::Char)::TokenKind
    if c >= '0' && c <= '9'
        return DIGIT
    elseif (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
        return LETTER
    elseif c == ' ' || c == '\t' || c == '\n'
        return SPACE
    else
        return PUNCT
    end
end


function read_number(src::String, start::Int)::Token
    i = start
    value = 0
    while i <= length(src) && classify_byte(src[i]) == DIGIT
        digit = Int(src[i]) - Int('0')
        value = value * 10 + digit
        i += 1
    end
    Token(DIGIT, start, i - start, string(value))
end


function read_ident(src::String, start::Int)::Token
    i = start
    while i <= length(src) && classify_byte(src[i]) != SPACE && classify_byte(src[i]) != PUNCT
        i += 1
    end
    Token(LETTER, start, i - start, src[start:i-1])
end


function tokenize(src::String)::Vector{Token}
    tokens = Token[]
    i = 1
    while i <= length(src)
        kind = classify_byte(src[i])
        if kind == SPACE
            i += 1
        elseif kind == DIGIT
            tok = read_number(src, i)
            push!(tokens, tok)
            i += tok.len
        elseif kind == LETTER
            tok = read_ident(src, i)
            push!(tokens, tok)
            i += tok.len
        else
            push!(tokens, Token(PUNCT, i, 1, string(src[i])))
            i += 1
        end
    end
    tokens
end

end  # module Lexer


# Drive it. `using .Lexer` is the local-module import form.
using .Lexer

src = "42 abc 7 xyz"
toks = tokenize(src)

for t in toks
    println("$(t.kind): $(t.text) [$(t.start)..$(t.start + t.len - 1)]")
end


# Comprehension + range. Julia's broadcasting via `.` is the
# idiomatic loop-replacement.
squares = [i^2 for i in 1:10]
println("squares = ", squares)


# Multiple dispatch on type. Same name, different signatures.
classify(x::Int)    = "integer: $x"
classify(x::Float64) = "float: $x"
classify(x::String)  = "string: $x"

println(classify(42))
println(classify(3.14))
println(classify("hello"))


# Try/catch/finally — Julia's exception model.
try
    if length(toks) > 1000
        error("too many tokens: $(length(toks))")
    end
    println("ok")
catch err
    println("error: $err")
finally
    println("done")
end


# Macros and string interpolation. `@time` measures and prints
# the elapsed wall time; `$(expr)` interpolates into the
# string.
n = 100
@time begin
    s = sum(i for i in 1:n)
    println("sum 1..$n = $s")
end
