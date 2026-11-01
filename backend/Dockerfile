# Development/building here only. Production on the Pi is a native executable.
FROM rust:bookworm@sha256:9181b56c2a21ab1d5e73cffe04fc762426d30aa7fac3c91141dd033f49a7fc8b AS tools
WORKDIR /work
# Optional public corporate CA for development, never disable TLS verification.
RUN --mount=type=secret,id=dev_ca \
    if [ -f /run/secrets/dev_ca ]; then \
      cp /run/secrets/dev_ca /usr/local/share/ca-certificates/dev-ca.crt && update-ca-certificates; \
    fi
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY migrations ./migrations
COPY docs ./docs
COPY tests ./tests
RUN cargo fetch --locked

FROM tools AS builder
RUN cargo build --locked --release

FROM debian:bookworm-slim AS runtime
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin replab
COPY --from=builder /work/target/release/replab-server /usr/local/bin/replab-server
USER 10001:10001
EXPOSE 8443
ENTRYPOINT ["replab-server"]
CMD ["serve"]
