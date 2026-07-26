#!/bin/bash

set -euo pipefail

LINK_PATH="${HOME}/.local/bin/gitmenubar"

if [[ -L "${LINK_PATH}" ]]; then
    rm -f "${LINK_PATH}"
    echo "Removed ${LINK_PATH}"
    exit 0
fi

if [[ -e "${LINK_PATH}" ]]; then
    echo "Error: ${LINK_PATH} exists and is not a symlink. Remove it manually." >&2
    exit 1
fi

echo "Not installed: ${LINK_PATH}"
