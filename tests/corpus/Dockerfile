# vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
# Re-sync when vidya adds a Dockerfile reference sample.
#
# Demonstrates a multi-stage build with build-arg defaults,
# common instruction heads, JSON-form CMD/ENTRYPOINT, and
# both UPPER / lower / Mixed case to exercise ADR 0011.

# syntax=docker/dockerfile:1.7

# ── Build stage ─────────────────────────────────────────────────────

ARG  RUST_VERSION=1.78
ARG  TARGET=x86_64-unknown-linux-gnu

FROM rust:${RUST_VERSION} AS builder

WORKDIR /work

# Cache the cargo registry layer.
COPY Cargo.toml Cargo.lock ./
RUN  mkdir -p src \
  && echo 'fn main() {}' > src/main.rs \
  && cargo build --release --target=$TARGET \
  && rm -rf src target/release/deps/concept*

# Now bring in the real source and build it.
COPY src ./src
RUN  cargo build --release --target=$TARGET

# ── Runtime stage — case-mixing on purpose to exercise ADR 0011 ────

from gcr.io/distroless/cc:latest

label maintainer="vyakarana@example.com" \
      org.opencontainers.image.source="https://github.com/example/concept" \
      org.opencontainers.image.licenses="GPL-3.0-only"

User 65532:65532

WorkDir /app

Copy --from=builder /work/target/x86_64-unknown-linux-gnu/release/concept /app/concept

env  CONCEPT_LOG=info \
     CONCEPT_PORT=8080

expose 8080/tcp

healthcheck --interval=30s --timeout=3s --retries=3 \
    cmd ["/app/concept", "--health-check"]

# JSON-form (exec form) ENTRYPOINT — recommended over shell form.
EntryPoint ["/app/concept"]
CMD        ["--listen", "0.0.0.0:8080"]
