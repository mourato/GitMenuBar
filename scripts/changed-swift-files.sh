#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

{
    git diff --name-only --diff-filter=ACMR HEAD -- '*.swift'
    git ls-files --others --exclude-standard -- '*.swift'
} | sort -u
