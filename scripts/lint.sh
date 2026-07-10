#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

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
    TARGETS=(GitMenuBar GitMenuBarTests)
fi

echo "Running SwiftFormat (lint mode)..."
swiftformat --lint --config .swiftformat "${TARGETS[@]}"

echo "Running SwiftLint..."
swiftlint lint --config .swiftlint.yml "${TARGETS[@]}"

echo "Lint checks passed"
