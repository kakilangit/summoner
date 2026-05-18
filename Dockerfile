# Summoner Application Image
#
# Uses pre-built builder and base images for fast builds.
# Only application code changes trigger a rebuild.

ARG BUILDER_IMAGE="ghcr.io/kakilangit/summoner-builder:latest"
ARG BASE_IMAGE="ghcr.io/kakilangit/summoner-base:latest"

FROM ${BUILDER_IMAGE} AS builder

LABEL org.opencontainers.image.source="https://github.com/kakilangit/summoner"
LABEL org.opencontainers.image.description="Summoner - Local-first AI agent platform"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /app

ENV MIX_ENV="prod"

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy application code
COPY priv priv
COPY lib lib
COPY assets assets

# Compile the application first (generates colocated hooks for esbuild)
RUN mix compile

# Compile assets (needs colocated hooks from mix compile)
RUN mix assets.deploy

# Build the release
COPY config/runtime.exs config/
RUN mix release

# Runtime stage
FROM ${BASE_IMAGE}

WORKDIR /app

RUN chown nobody /app

# Copy the release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/summoner ./

# Copy entrypoint script
COPY --chown=nobody:root entrypoint.sh ./
RUN chmod +x entrypoint.sh

USER nobody

ENV HOME=/app
ENV MIX_ENV=prod
ENV PHX_SERVER=true
ENV DATA_DIR=/app/.summoner

EXPOSE 4000

ENTRYPOINT ["./entrypoint.sh"]
CMD ["start"]
