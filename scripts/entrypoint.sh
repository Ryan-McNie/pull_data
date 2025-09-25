#!/bin/bash

COMMAND=$1
shift  # Shift arguments so $2 becomes $1, etc.

case "$COMMAND" in
  pull_obs)
    ./scripts/pull_obs-station_doy.sh "$@"
    ;;
  pull_sbas)
    ./scripts/pull_sbas-doy.sh "$@"
    ;;
  pull_nav)
    ./scripts/pull_nav-doy.sh "$@"
    ;;
  copy_to_s3)
    ./scripts/copy_to_s3-doy.sh "$@"
    ;;
  *)
    echo "Unknown command: $COMMAND"
    echo "Available commands: pull_obs, pull_sbas, pull_nav, copy_to_s3, multi"
    exit 1
    ;;
esac
