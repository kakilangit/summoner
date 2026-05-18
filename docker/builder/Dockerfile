# Summoner Builder Image
#
# Contains Elixir, OTP, Rust toolchain, and build tools.
# Rebuild only when Elixir, OTP, or Rust versions change.
#
# Build:
#   make builder.push

ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.5
ARG DEBIAN_VERSION=trixie-20260505

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential git curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Rust toolchain (required for nulid NIF compilation)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Hex + Rebar
RUN mix local.hex --force && \
    mix local.rebar --force
