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

# Copy only what you need, setting executable bits at copy time
# and normalize line-endings for shell scripts.
# (The 'sed' step removes CR if present.)
COPY --chmod=755 entrypoint.sh /app/entrypoint.sh
COPY --chmod=755 scripts/ /app/scripts/
COPY --chmod=644 . /app/

# Normalize CRLF -> LF for any *.sh that may have Windows line endings
RUN find /app -type f -name "*.sh" -exec sed -i 's/\r$//' {} +

# Ensure entrypoint has a proper shebang, e.g.:
#   #!/usr/bin/env bash
# (add that inside your entrypoint.sh file)
ENTRYPOINT ["/app/entrypoint.sh"]
