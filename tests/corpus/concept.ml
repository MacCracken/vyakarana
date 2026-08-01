(* vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
   Re-sync when vidya adds an OCaml reference sample.

   Lexing + parsing of arithmetic expressions, idiomatic OCaml. *)

(* ── Tokens ───────────────────────────────────────────────────────── *)

type token_kind =
  | NUMBER of int
  | PLUS
  | MINUS
  | STAR
  | SLASH
  | LPAREN
  | RPAREN
  | EOF

type token = { kind : token_kind; text : string; pos : int }

(* ── Lexer ────────────────────────────────────────────────────────── *)

let is_digit c = c >= '0' && c <= '9'
let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r'

let tokenize source =
  let n = String.length source in
  let rec loop i acc =
    if i >= n then
      List.rev ({ kind = EOF; text = ""; pos = i } :: acc)
    else
      let c = source.[i] in
      if is_space c then
        loop (i + 1) acc
      else
        match c with
        | '+' -> loop (i + 1) ({ kind = PLUS;   text = "+"; pos = i } :: acc)
        | '-' -> loop (i + 1) ({ kind = MINUS;  text = "-"; pos = i } :: acc)
        | '*' -> loop (i + 1) ({ kind = STAR;   text = "*"; pos = i } :: acc)
        | '/' -> loop (i + 1) ({ kind = SLASH;  text = "/"; pos = i } :: acc)
        | '(' -> loop (i + 1) ({ kind = LPAREN; text = "("; pos = i } :: acc)
        | ')' -> loop (i + 1) ({ kind = RPAREN; text = ")"; pos = i } :: acc)
        | c when is_digit c ->
          let start = i in
          let j = ref i in
          while !j < n && is_digit source.[!j] do
            incr j
          done;
          let text = String.sub source start (!j - start) in
          let value = int_of_string text in
          loop !j ({ kind = NUMBER value; text; pos = start } :: acc)
        | _ ->
          failwith (Printf.sprintf "unexpected character %C at %d" c i)
  in
  loop 0 []

(* ── AST ──────────────────────────────────────────────────────────── *)

type expr =
  | Num of int
  | Unary of char * expr
  | BinOp of char * expr * expr

(* ── Pratt parser ─────────────────────────────────────────────────── *)

let infix_bp = function
  | PLUS | MINUS -> 1
  | STAR | SLASH -> 3
  | _ -> 0

let rec parse_expr tokens min_bp =
  let left, tokens = parse_primary tokens in
  parse_infix tokens left min_bp

and parse_infix tokens left min_bp =
  match tokens with
  | t :: rest ->
    let bp = infix_bp t.kind in
    if bp = 0 || bp < min_bp then
      (left, tokens)
    else begin
      let op = t.text.[0] in
      let right, rest = parse_expr rest (bp + 1) in
      parse_infix rest (BinOp (op, left, right)) min_bp
    end
  | [] ->
    (left, tokens)

and parse_primary tokens =
  match tokens with
  | { kind = MINUS; _ } :: rest ->
    let operand, rest = parse_primary rest in
    (Unary ('-', operand), rest)
  | { kind = LPAREN; _ } :: rest ->
    let inner, rest = parse_expr rest 0 in
    begin match rest with
    | { kind = RPAREN; _ } :: rest -> (inner, rest)
    | _ -> failwith "expected )"
    end
  | { kind = NUMBER v; _ } :: rest ->
    (Num v, rest)
  | _ ->
    failwith "unexpected token"

(* ── Evaluator ────────────────────────────────────────────────────── *)

let rec eval = function
  | Num v -> v
  | Unary (_, e) -> - (eval e)
  | BinOp (op, l, r) ->
    let a = eval l in
    let b = eval r in
    match op with
    | '+' -> a + b
    | '-' -> a - b
    | '*' -> a * b
    | '/' -> a / b
    | _ -> failwith (Printf.sprintf "bad op %c" op)

(* ── Demo ─────────────────────────────────────────────────────────── *)

let () =
  let cases = [
    ("1 + 2",       3);
    ("2 * 3 + 4",   10);
    ("(1 + 2) * 3", 9);
    ("-5 + 3",      -2);
  ] in
  List.iter (fun (input, expected) ->
    let tokens = tokenize input in
    let expr, _ = parse_expr tokens 0 in
    let got = eval expr in
    Printf.printf "%-15s => %d (expected %d)\n" input got expected;
    assert (got = expected)
  ) cases

(* 2.3.2 error-hole coverage: polymorphic-variant tags and a
   user-defined operator built from OCaml's symbol characters. *)
type token = [ `Ident of string | `Number of int | `Eof ]

let ( $ ) f x = f x

let describe = function
  | `Ident s  -> "ident " ^ s
  | `Number n -> "number " ^ string_of_int n
  | `Eof      -> "eof"
