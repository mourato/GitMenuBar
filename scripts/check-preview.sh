#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

usage() {
    cat <<'EOF'
Usage: scripts/check-preview.sh [--all] [file ...]

Checks SwiftUI/AppKit UI candidate files for preview coverage.

Default: check changed Swift files under GitMenuBar/Components and GitMenuBar/Pages.
--all:   check all Swift files under GitMenuBar/Components and GitMenuBar/Pages.
file:    check the provided files.
EOF
}

mode="changed"
provided_files=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            mode="all"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            provided_files+=("$1")
            shift
            ;;
    esac
done

if [[ ${#provided_files[@]} -gt 0 ]]; then
    files=("${provided_files[@]}")
elif [[ "${mode}" == "all" ]]; then
    files=()
    while IFS= read -r file; do
        files+=("$file")
    done < <(find GitMenuBar/Components GitMenuBar/Pages -name '*.swift' -type f | sort)
else
    files=()
    while IFS= read -r file; do
        files+=("$file")
    done < <(
        ./scripts/changed-swift-files.sh \
            | grep -E '^GitMenuBar/(Components|Pages)/.*\.swift$' \
            || true
    )
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "check-preview: passed (no changed UI files)"
    exit 0
fi

has_preview() {
    rg -q '#Preview|PreviewProvider' "$1"
}

is_ui_candidate() {
    local file="$1"
    rg -q '^[[:space:]]*(private |public |internal |fileprivate )?(struct|class|final class)[^{:]*:[^{]*\b(View|NSViewRepresentable|NSViewControllerRepresentable)\b' "$file"
}

view_type_names() {
    local file="$1"
    rg -o '^[[:space:]]*(private |public |internal |fileprivate )?(struct|class|final class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[^{:]*:[^{]*\b(View|NSViewRepresentable|NSViewControllerRepresentable)\b' "$file" \
        | sed -E 's/^[[:space:]]*(private |public |internal |fileprivate )?(struct|class|final class)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/' \
        | sort -u
}

is_probe_only_candidate() {
    local file="$1"
    local has_type=0
    local type_name

    while IFS= read -r type_name; do
        has_type=1
        if [[ ! "$type_name" =~ Probe(View)?$ ]]; then
            return 1
        fi
    done < <(view_type_names "$file")

    [[ "$has_type" -eq 1 ]]
}

has_companion_preview() {
    local file="$1"
    local dir
    local type_names_text
    dir="$(dirname "$file")"

    type_names_text="$(view_type_names "$file" || true)"
    [[ -n "$type_names_text" ]] || return 1

    while IFS= read -r preview_file; do
        has_preview "$preview_file" || continue
        while IFS= read -r type_name; do
            if rg -q "\\b${type_name}\\b" "$preview_file"; then
                return 0
            fi
        done <<< "$type_names_text"
    done < <(find "$dir" -maxdepth 1 -name '*Preview.swift' -type f | sort)

    return 1
}

checked_count=0
missing=()

for file in "${files[@]}"; do
    [[ -f "$file" ]] || continue
    [[ "$file" == *.swift ]] || continue
    [[ "$file" == GitMenuBar/Components/* || "$file" == GitMenuBar/Pages/* ]] || continue
    is_ui_candidate "$file" || continue
    is_probe_only_candidate "$file" && continue

    checked_count=$((checked_count + 1))
    if has_preview "$file" || has_companion_preview "$file"; then
        continue
    fi

    missing+=("$file")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "check-preview: missing preview coverage in ${#missing[@]} file(s):" >&2
    for file in "${missing[@]}"; do
        echo "  - $file" >&2
    done
    echo "Add #Preview in the file or a same-directory *Preview.swift companion that references the view." >&2
    exit 1
fi

echo "check-preview: passed (${checked_count} UI candidate file(s) checked)"
