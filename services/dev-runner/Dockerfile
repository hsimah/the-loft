# Starter toolchain, based on the applications' existing PHP/Rust + Node tools.
# Build on the target architecture (ARM64 for Fjord), then record the image digest.
FROM docker.io/library/node:22-bookworm AS node
FROM docker.io/library/rust:1-bookworm AS rust
FROM docker.io/library/composer:2 AS composer
FROM docker.io/library/php:8.3-cli-bookworm

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=rust /usr/local/cargo /usr/local/cargo
COPY --from=rust /usr/local/rustup /usr/local/rustup
COPY --from=composer /usr/bin/composer /usr/local/bin/composer
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/tmp/cargo
ENV PATH="/usr/local/cargo/bin:${PATH}"
ENV DISABLE_AUTOUPDATER=1
ARG CLAUDE_VERSION=2.1.278
ARG PNPM_VERSION=12.4.1
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates unzip ripgrep \
        build-essential libonig-dev libzip-dev \
    && docker-php-ext-install mbstring zip pdo_mysql mysqli \
    && ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && npm install --global "@anthropic-ai/claude-code@${CLAUDE_VERSION}" "pnpm@${PNPM_VERSION}" \
    && rm -rf /var/lib/apt/lists/* /root/.npm
WORKDIR /work
# Runtime UID/GID is supplied by the runner to match the checkout's owner.
CMD ["claude", "--version"]
