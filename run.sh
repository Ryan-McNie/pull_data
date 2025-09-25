#!/bin/bash

# Ensure output folder exists
mkdir -p output

# Run the container with volume mount and pass all arguments
docker run --rm -it \
  -v "$(pwd)/output":/output \
  pull_data "$@"
