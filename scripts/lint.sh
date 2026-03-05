#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

SOURCES=(GitMenuBar GitMenuBarTests)

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "SwiftFormat not installed. Run: brew install swiftformat" >&2
    exit 1
fi

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "SwiftLint not installed. Run: brew install swiftlint" >&2
    exit 1
fi

echo "Running SwiftFormat (lint mode)..."
swiftformat --lint --config .swiftformat "${SOURCES[@]}"

echo "Running SwiftLint..."
swiftlint lint --config .swiftlint.yml "${SOURCES[@]}"

echo "Lint checks passed"
