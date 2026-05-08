<template>
  <article class="lexer-demo">
    <header>
      <h1>{{ title }}</h1>
      <p>Tokenize a string and render the spans.</p>
    </header>

    <section>
      <input
        v-model="source"
        type="text"
        placeholder="enter text"
        class="source-input"
      />
      <button @click="tokenize" :disabled="!source">Tokenize</button>
    </section>

    <ul v-if="tokens.length">
      <li v-for="(tok, i) in tokens" :key="i">
        <code>{{ tok.kind }}</code>
        <span class="span">[{{ tok.start }}..{{ tok.start + tok.len }}]</span>
      </li>
    </ul>
    <p v-else>No tokens yet.</p>
  </article>
</template>


<script>
const KEYWORDS = new Set(["if", "while", "for", "def", "class"]);

export default {
  data() {
    return {
      title: "Lexer Demo",
      source: "",
      tokens: [],
    };
  },
  methods: {
    isDigit(c) {
      return c >= "0" && c <= "9";
    },
    isLetter(c) {
      return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c === "_";
    },
    tokenize() {
      const out = [];
      let i = 0;
      while (i < this.source.length) {
        const c = this.source[i];
        if (this.isDigit(c)) {
          const start = i;
          while (i < this.source.length && this.isDigit(this.source[i])) {
            i++;
          }
          out.push({ kind: "number", start, len: i - start });
        } else if (this.isLetter(c)) {
          const start = i;
          while (
            i < this.source.length &&
            (this.isLetter(this.source[i]) || this.isDigit(this.source[i]))
          ) {
            i++;
          }
          const text = this.source.slice(start, i);
          const kind = KEYWORDS.has(text) ? "keyword" : "ident";
          out.push({ kind, start, len: i - start });
        } else if (c === " " || c === "\t" || c === "\n") {
          i++;
        } else {
          out.push({ kind: "punct", start: i, len: 1 });
          i++;
        }
      }
      this.tokens = out;
    },
  },
};
</script>


<style>
.lexer-demo {
  font-family: ui-sans-serif, system-ui, sans-serif;
  max-width: 40rem;
  margin: 2rem auto;
}

.lexer-demo header h1 {
  font-size: 1.5rem;
  font-weight: 600;
}

.source-input {
  width: 100%;
  padding: 0.5rem 0.75rem;
  border: 1px solid #ccc;
  border-radius: 4px;
}

button {
  margin-top: 0.5rem;
  padding: 0.4rem 1rem;
  background: #2c7a7b;
  color: #fff;
  border: 0;
  border-radius: 4px;
  cursor: pointer;
}

button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.span {
  color: #888;
  margin-left: 0.5rem;
}
</style>
