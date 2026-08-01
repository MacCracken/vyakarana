-- vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
-- Re-sync when vidya adds a Haskell reference sample.
--
-- Lexing + parsing of arithmetic expressions, idiomatic Haskell.

{- Block-comment form using brace-dash. Nestable per spec; the
   pair-rule scanner is greedy so a real nested form would close
   at the first dash-brace. Documented gap, same shape as Rust. -}

module Vyakarana.Concept where

import Data.Char (isDigit, isSpace)
import Data.List (uncons)

-- ── Tokens ──────────────────────────────────────────────────────────

data TokenKind
  = TkNumber Int
  | TkPlus
  | TkMinus
  | TkStar
  | TkSlash
  | TkLParen
  | TkRParen
  | TkEof
  deriving (Show, Eq)

data Token = Token
  { tkKind :: TokenKind
  , tkText :: String
  , tkPos  :: Int
  } deriving (Show)

-- ── Lexer ───────────────────────────────────────────────────────────

tokenize :: String -> [Token]
tokenize source = go 0 source
  where
    go pos [] = [Token TkEof "" pos]
    go pos s@(c:cs)
      | isSpace c   = go (pos + 1) cs
      | c == '+'    = Token TkPlus   "+" pos : go (pos + 1) cs
      | c == '-'    = Token TkMinus  "-" pos : go (pos + 1) cs
      | c == '*'    = Token TkStar   "*" pos : go (pos + 1) cs
      | c == '/'    = Token TkSlash  "/" pos : go (pos + 1) cs
      | c == '('    = Token TkLParen "(" pos : go (pos + 1) cs
      | c == ')'    = Token TkRParen ")" pos : go (pos + 1) cs
      | isDigit c   =
          let (digits, rest) = span isDigit s
              n = length digits
              v = read digits :: Int
          in Token (TkNumber v) digits pos : go (pos + n) rest
      | otherwise   = error ("unexpected character " ++ [c] ++ " at " ++ show pos)

-- ── AST ─────────────────────────────────────────────────────────────

data Expr
  = ENum Int
  | EUnary Char Expr
  | EBinOp Char Expr Expr
  deriving (Show)

-- ── Pratt parser ────────────────────────────────────────────────────

infixBp :: TokenKind -> Int
infixBp TkPlus  = 1
infixBp TkMinus = 1
infixBp TkStar  = 3
infixBp TkSlash = 3
infixBp _       = 0

parseExpr :: Int -> [Token] -> (Expr, [Token])
parseExpr minBp tokens =
  let (left, rest) = parsePrimary tokens
  in parseInfix minBp left rest

parseInfix :: Int -> Expr -> [Token] -> (Expr, [Token])
parseInfix minBp left tokens =
  case tokens of
    [] -> (left, tokens)
    (t : rest) ->
      let bp = infixBp (tkKind t)
      in if bp == 0 || bp < minBp
           then (left, tokens)
           else
             let op            = head (tkText t)
                 (right, rest2) = parseExpr (bp + 1) rest
             in parseInfix minBp (EBinOp op left right) rest2

parsePrimary :: [Token] -> (Expr, [Token])
parsePrimary (t : rest)
  | tkKind t == TkMinus =
      let (operand, rest') = parsePrimary rest
      in (EUnary '-' operand, rest')
  | tkKind t == TkLParen =
      let (inner, rest') = parseExpr 0 rest
      in case rest' of
           (t' : rest'') | tkKind t' == TkRParen -> (inner, rest'')
           _ -> error "expected )"
  | otherwise =
      case tkKind t of
        TkNumber v -> (ENum v, rest)
        _          -> error ("unexpected token " ++ show t)
parsePrimary [] = error "unexpected end of input"

-- ── Evaluator ───────────────────────────────────────────────────────

eval :: Expr -> Int
eval (ENum v)        = v
eval (EUnary _ e)    = - (eval e)
eval (EBinOp op l r) =
  let a = eval l
      b = eval r
  in case op of
       '+' -> a + b
       '-' -> a - b
       '*' -> a * b
       '/' -> a `div` b
       _   -> error ("bad op " ++ [op])

-- ── Demo ────────────────────────────────────────────────────────────

main :: IO ()
main = do
  let cases =
        [ ("1 + 2",       3)
        , ("2 * 3 + 4",   10)
        , ("(1 + 2) * 3", 9)
        , ("-5 + 3",      -2)
        ]
  mapM_ runCase cases
  where
    runCase (input, expected) =
      let tokens   = tokenize input
          (e, _)   = parseExpr 0 tokens
          got      = eval e
      in do
        putStrLn (pad 15 input ++ " => " ++ show got
                  ++ " (expected " ++ show expected ++ ")")
        if got == expected
          then return ()
          else error ("mismatch at " ++ input)

    pad n s = s ++ replicate (max 0 (n - length s)) ' '

-- 2.3.2 error-hole coverage: `$` is Haskell's application
-- operator and one of the most-used operators in the language.
describeAll :: [String] -> IO ()
describeAll = mapM_ $ putStrLn . pad 15
