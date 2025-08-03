FROM debian:bookworm-slim

ARG VERSION

LABEL org.opencontainers.image.title="Seafd"
LABEL org.opencontainers.image.description="Dockerized Seafile client for a CLI server."
LABEL org.opencontainers.image.version=${VERSION:-"1.0.0"}
LABEL org.opencontainers.image.authors="Luthfi Tri Atmaja <luthfi.personal@gmail.com>"
LABEL org.opencontainers.image.url="https://github.com/luthfiampas/seafd"
LABEL org.opencontainers.image.licenses="MIT"

RUN apt-get update && \
    apt-get install --no-install-recommends --yes \
      ca-certificates \
      libfuse2 \
      seafile-cli \
      oathtool && \
    apt-get clean && \
    apt-get autoclean && \
    rm -rf \
      /var/lib/apt/lists/* \
      /var/log/fsck/*.log \
      /var/log/apt/*.log \
      /var/cache/debconf/*.dat-old \
      /tmp/* \
      /var/tmp/*

COPY VERSION .
COPY entrypoint.sh .

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
