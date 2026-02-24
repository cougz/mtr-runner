FROM debian:trixie-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        mtr-tiny \
        bash \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 -s /bin/bash mtr

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER mtr
VOLUME ["/data/mtr"]

ENTRYPOINT ["/entrypoint.sh"]
