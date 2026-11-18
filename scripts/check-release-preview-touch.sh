#!/bin/bash
# Flags PRs that touch SwiftUI previews or DEBUG-only doubles.
# Born from incident #19 follow-up (issue #41): UsageQuotaStripPreview used
# InMemoryAIAPIKeyStore without #if DEBUG; Debug gates passed, Release broke.
# Usage: make validate-release-touch
# Skip consciously: SKIP_RELEASE_TOUCH_CHECK=1 make validate-release-touch
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ "${SKIP_RELEASE_TOUCH_CHECK:-0}" == "1" ]]; then
    echo "validate-release-touch: skipped (SKIP_RELEASE_TOUCH_CHECK=1)"
    exit 0
fi

if ! changed="$(./scripts/changed-swift-files.sh)"; then
    echo "validate-release-touch: failed to discover changed Swift files" >&2
    exit 1
fi

if [[ -z "$changed" ]]; then
    echo "validate-release-touch: passed (no changed Swift files)"
    exit 0
fi

touched=()
while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if [[ "$file" == *Preview*.swift || "$file" == *PreviewDoubles.swift ]]; then
        touched+=("$file")
        continue
    fi
    if grep -q "InMemoryAIAPIKeyStore\|InMemoryAIProviderStoreDataStore" "$file" 2>/dev/null; then
        touched+=("$file")
    fi
done <<< "$changed"

if [[ ${#touched[@]} -eq 0 ]]; then
    echo "validate-release-touch: passed (no preview/doubles touch)"
    exit 0
fi

cat >&2 <<EOF
validate-release-touch: PR touches previews or DEBUG-only doubles:
EOF
for file in "${touched[@]}"; do
    echo "  - $file" >&2
done
cat >&2 <<EOF
Run make build-release before merge (issue #41; incident: UsageQuotaStripPreview + InMemoryAIAPIKeyStore, fix b6fd04f).
Debug gates do not cover this; Release does.
To skip consciously: SKIP_RELEASE_TOUCH_CHECK=1 make validate-release-touch
EOF
exit 1
