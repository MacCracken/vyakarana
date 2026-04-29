<!-- vyakarana stand-in -- not from vidya. See docs/adr/0006. -->

# Lexing and Parsing

Turning source text into *structured representations* -- the front end of every compiler, interpreter, and language tool. **Lexing** (tokenization) breaks character streams into meaningful tokens. **Parsing** arranges tokens into trees according to grammar rules.

## Best Practices

- Separate lexing from parsing
- Use **recursive descent** for hand-written parsers
- Make the lexer produce *spans*, not just token types
- Prefer peek-based lookahead over stream rewinding

### Performance Numbers

| Tool       | Throughput |
|------------|-----------:|
| ripgrep    | 5000 MB/s  |
| python re  | 500 MB/s   |
| rustc      | 200 MB/s   |

A hand-written DFA lexer is roughly 10x faster than a regex-based one.

## Gotchas

> Greedy tokenization breaks on multi-character operators. Always try the longest match first.

### Left recursion

A grammar rule like `expr -> expr + term` translates to infinite recursion. Fix: rewrite as `expr -> term (('+' | '-') term)*`.

```rust
fn parse_expr(&mut self) -> Expr {
    let mut left = self.parse_term();
    while matches!(self.peek(), Token::Plus | Token::Minus) {
        let op = self.advance();
        let right = self.parse_term();
        left = Expr::Binary(Box::new(left), op, Box::new(right));
    }
    left
}
```

See [the Rust book](https://doc.rust-lang.org/book/) for more detail. Also try `rustc --explain E0308` for specific diagnostics.

---

## Ordered List

1. Tokenize
2. Parse
3. Evaluate

## Nested Emphasis

A *mix of **bold italic*** sometimes shows up in prose, and ~~strikethrough~~ handles deletion markup. Inline code like `fn foo()` stays verbatim.

End of sample.
