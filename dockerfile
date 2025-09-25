# syntax=docker/dockerfile:1.7
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base deps in one layer and clean
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl unzip python3 lftp gzip tar ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 using Docker's TARGETARCH mapping
ARG TARGETARCH
RUN set -eux; \
    if [ "$TARGETARCH" = "amd64" ]; then ARCH=x86_64; \
    elif [ "$TARGETARCH" = "arm64" ]; then ARCH=aarch64; \
    else echo "Unsupported arch: $TARGETARCH" >&2; exit 1; fi; \
    curl -fsSLo /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip"; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscliv2.zip

WORKDIR /app

COPY . /app/

ENTRYPOINT ["/app/scripts/entrypoint.sh"]
