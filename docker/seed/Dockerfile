FROM debian:trixie-20260505-slim

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends postgresql-client && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY priv/bundled/seed.sh /seed.sh
RUN chmod +x /seed.sh

ENTRYPOINT ["sh", "/seed.sh"]
