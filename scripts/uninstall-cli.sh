#!/bin/bash

set -euo pipefail

LINK_PATH="${HOME}/.local/bin/gitmenubar"

if [[ -L "${LINK_PATH}" || -f "${LINK_PATH}" ]]; then
    rm -f "${LINK_PATH}"
    echo "Removed ${LINK_PATH}"
    exit 0
fi

echo "Not installed: ${LINK_PATH}"
