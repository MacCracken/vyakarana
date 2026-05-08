<script>
  // Vidya — Lexing and Parsing in Svelte
  //
  // Svelte SFCs feel close to Vue's shape but the syntactic
  // sugar is different: `{#if}` / `{#each}` blocks instead of
  // directives, single-brace interpolation, reactive
  // declarations via `$:`.

  const KEYWORDS = new Set(["if", "while", "for", "def", "class"]);

  let source = "";
  let tokens = [];

  function isDigit(c) {
    return c >= "0" && c <= "9";
  }

  function isLetter(c) {
    return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c === "_";
  }

  function tokenize() {
    const out = [];
    let i = 0;
    while (i < source.length) {
      const c = source[i];
      if (isDigit(c)) {
        const start = i;
        while (i < source.length && isDigit(source[i])) i++;
        out.push({ kind: "number", start, len: i - start });
      } else if (isLetter(c)) {
        const start = i;
        while (
          i < source.length &&
          (isLetter(source[i]) || isDigit(source[i]))
        ) {
          i++;
        }
        const text = source.slice(start, i);
        out.push({
          kind: KEYWORDS.has(text) ? "keyword" : "ident",
          start,
          len: i - start,
        });
      } else if (c === " " || c === "\t" || c === "\n") {
        i++;
      } else {
        out.push({ kind: "punct", start: i, len: 1 });
        i++;
      }
    }
    tokens = out;
  }

  // Reactive declaration. Recomputes whenever `source` changes.
  $: tokenCount = tokens.length;
</script>


<article class="lexer-demo">
  <header>
    <h1>Lexer Demo</h1>
    <p>Tokenize a string and render the spans.</p>
  </header>

  <section>
    <input
      type="text"
      placeholder="enter text"
      class="source-input"
      bind:value={source}
    />
    <button on:click={tokenize} disabled={!source}>Tokenize</button>
  </section>

  {#if tokenCount > 0}
    <ul>
      {#each tokens as tok, i (i)}
        <li>
          <code>{tok.kind}</code>
          <span class="span">[{tok.start}..{tok.start + tok.len}]</span>
        </li>
      {/each}
    </ul>
  {:else}
    <p>No tokens yet.</p>
  {/if}
</article>


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
