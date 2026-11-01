FROM rust:bookworm@sha256:9181b56c2a21ab1d5e73cffe04fc762426d30aa7fac3c91141dd033f49a7fc8b AS rust-tools
FROM cirrusci/flutter:stable@sha256:32e7d16c7e1458d3135e945ceec82c5d43bfda289526f850711f3908fb927502

ARG DEBIAN_FRONTEND=noninteractive
ARG FLUTTER_VERSION=3.47.9
ARG FLUTTER_ARCHIVE_SHA256=25ed8c3c29d51a7353f2a944310b478af8214920639524b19c50a19e6c044c5a

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    libglu1-mesa \
    openjdk-17-jdk \
    postgresql-client \
    python3 \
    unzip \
    xz-utils \
    zip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /tmp/flutter.tar.xz \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && printf '%s  %s\n' "$FLUTTER_ARCHIVE_SHA256" /tmp/flutter.tar.xz | sha256sum --check - \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && git config --system --add safe.directory /opt/flutter \
    && rm /tmp/flutter.tar.xz

COPY --from=rust-tools /usr/local/rustup /usr/local/rustup
COPY --from=rust-tools /usr/local/cargo /usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo
ENV PATH="/opt/flutter/bin:/usr/local/cargo/bin:${PATH}"

WORKDIR /workspace

CMD ["bash"]
