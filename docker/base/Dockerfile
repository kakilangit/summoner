# Summoner Base Image
#
# Runtime image with system libraries, locale, Node.js, and Python.
# Rebuild only when runtime dependencies change.
#
# Build:
#   make base.push

ARG DEBIAN_VERSION=trixie-20260505

FROM debian:${DEBIAN_VERSION}-slim

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 locales ca-certificates \
    git curl ripgrep \
    nodejs npm python3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
