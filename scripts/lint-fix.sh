#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"
STYLE_CONFIG_DIR="${AGENT_CONFIG_HOME:-${HOME}/.agents}/skills/swift-conventions/config"

SOURCES=(GitMenuBar GitMenuBarTests)

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "SwiftFormat not installed. Run: brew install swiftformat" >&2
    exit 1
fi

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "SwiftLint not installed. Run: brew install swiftlint" >&2
    exit 1
fi

echo "Applying SwiftFormat..."
swiftformat --config "${STYLE_CONFIG_DIR}/.swiftformat" "${SOURCES[@]}"

echo "Applying SwiftLint fixes..."
swiftlint lint --config "${STYLE_CONFIG_DIR}/.swiftlint.yml" --fix "${SOURCES[@]}"

echo "Lint fix pass completed"
