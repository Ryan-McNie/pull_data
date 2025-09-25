#!/usr/bin/env bash
set -euo pipefail
mkdir -p output

docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -v "$(pwd)/output":/app/output \
  pull_data "$@"
