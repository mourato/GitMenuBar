#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${PROJECT_DIR}/scripts/config/app_identity.sh"

XCODEPROJ="${PROJECT_DIR}/${XCODEPROJ_NAME}"
DERIVED_DATA_PATH=""
SCHEME="${APP_SCHEME}"
CONFIGURATION="Debug"
DESTINATION="platform=macOS"
ACTION="build"
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            XCODEPROJ="$2"
            shift 2
            ;;
        --scheme)
            SCHEME="$2"
            shift 2
            ;;
        --configuration|-c)
            CONFIGURATION="$2"
            shift 2
            ;;
        --derived-data)
            DERIVED_DATA_PATH="$2"
            shift 2
            ;;
        --destination)
            DESTINATION="$2"
            shift 2
            ;;
        --action)
            ACTION="$2"
            shift 2
            ;;
        --)
            shift
            EXTRA_ARGS+=("$@")
            break
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ! -d "${XCODEPROJ}" ]]; then
    echo "Error: Xcode project not found at ${XCODEPROJ}" >&2
    exit 1
fi

CMD=(
    xcodebuild
    -project "${XCODEPROJ}"
    -scheme "${SCHEME}"
    -configuration "${CONFIGURATION}"
)

if [[ -n "${DERIVED_DATA_PATH}" ]]; then
    CMD+=( -derivedDataPath "${DERIVED_DATA_PATH}" )
fi

CMD+=(
    -destination "${DESTINATION}"
    "${ACTION}"
)

if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    CMD+=("${EXTRA_ARGS[@]}")
fi

"${CMD[@]}"
