#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

usage() {
    cat <<'EOF'
Usage: scripts/lint.sh [path ...]

Lint the full app and test targets, or only the explicitly provided Swift paths.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "SwiftFormat not installed. Run: brew install swiftformat" >&2
    exit 1
fi

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "SwiftLint not installed. Run: brew install swiftlint" >&2
    exit 1
fi

if [[ $# -gt 0 ]]; then
    echo "Linting targeted Swift paths..."
    TARGETS=("$@")
else
    echo "Linting full Swift targets..."
    TARGETS=(GitMenuBar GitMenuBarTests gitmenubar)
fi

echo "Running SwiftFormat (lint mode)..."
swiftformat --lint --config .swiftformat "${TARGETS[@]}"

echo "Running SwiftLint..."
swiftlint lint --strict "${TARGETS[@]}"

echo "Lint checks passed"
