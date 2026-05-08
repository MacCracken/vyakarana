# Vidya — Lexing and Parsing in Crystal
#
# Crystal is Ruby-shaped on the surface but compiles to a
# native binary with type inference. A tokenizer here looks
# very Ruby-like: byte classification, string handling, keyword
# lookups. The static-typed bits surface in the method
# signatures.

require "set"


abstract class Token
  getter kind : Symbol
  getter start : Int32
  getter len : Int32

  def initialize(@kind, @start, @len)
  end

  def to_s
    "#{kind} [#{start}..#{start + len}]"
  end

  abstract def value : String
end


class NumberToken < Token
  getter num_value : Int32

  def initialize(start : Int32, len : Int32, @num_value)
    super(:number, start, len)
  end

  def value : String
    num_value.to_s
  end
end


class IdentToken < Token
  getter text : String

  def initialize(start : Int32, len : Int32, @text)
    super(:ident, start, len)
  end

  def value : String
    text
  end
end


module Lexer
  KEYWORDS = Set{"if", "while", "for", "def", "class"}

  extend self

  def is_digit?(c : Char) : Bool
    c >= '0' && c <= '9'
  end

  def is_letter?(c : Char) : Bool
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
  end

  def is_space?(c : Char) : Bool
    c == ' ' || c == '\t' || c == '\n'
  end

  def tokenize(src : String) : Array(Token)
    tokens = [] of Token
    i = 0
    while i < src.size
      c = src[i]
      if is_space?(c)
        i += 1
      elsif is_digit?(c)
        start = i
        value = 0
        while i < src.size && is_digit?(src[i])
          digit = src[i].ord - '0'.ord
          value = value * 10 + digit
          i += 1
        end
        tokens << NumberToken.new(start, i - start, value)
      elsif is_letter?(c)
        start = i
        while i < src.size && (is_letter?(src[i]) || is_digit?(src[i]))
          i += 1
        end
        text = src[start, i - start]
        tokens << IdentToken.new(start, i - start, text)
      else
        i += 1
      end
    end
    tokens
  end
end


# Drive it. Note `puts` shape, single-quoted char literals,
# `?` predicates, instance var access via `@`.
src = "42 hello 7 world"
tokens = Lexer.tokenize(src)
tokens.each do |tok|
  puts "#{tok.kind}: #{tok.value}"
end


# Generics + tuple literal + range. Type annotations show
# Crystal's static side.
buckets = Hash(Symbol, Array(Int32)).new { |h, k| h[k] = [] of Int32 }
(1..10).each do |i|
  key = i.even? ? :even : :odd
  buckets[key] << i
end


# Begin/rescue/ensure — Ruby-esque exception shape.
begin
  raise "boom" if buckets[:odd].size > 100
  puts "ok"
rescue ex : Exception
  puts "error: #{ex.message}"
ensure
  puts "cleanup"
end
