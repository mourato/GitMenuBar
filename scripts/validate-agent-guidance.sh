#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

error() {
  echo "guidance-check: $*" >&2
  errors=$((errors + 1))
}

require_text() {
  local file="$1"
  local pattern="$2"
  if ! rg -q -- "$pattern" "$ROOT/$file"; then
    error "$file is missing required text: $pattern"
  fi
}

require_file() {
  if [[ ! -f "$ROOT/$1" ]]; then
    error "missing file: $1"
  fi
}

require_file AGENTS.md
require_file .agents/review-profiles/thermo-gitmenubar.md
require_text AGENTS.md '## Execution Policy'
require_text AGENTS.md 'Every implementation plan must contain an `## Execution profile` section'
require_text AGENTS.md 'global:improve'
require_text AGENTS.md 'global:thermo-nuclear-code-quality-review'

overlay_names=(
  accessibility-audit
  apple-design
  code-quality
  delivery-workflow
  macos-app-engineering
  menubar
  swift-conventions
)

route_pair_present() {
  local file="$1"
  local global_skill="$2"
  local overlay="$3"
  rg -Fq -- "\`$global_skill\` + \`$overlay\`" "$file"
}

profile_route_present() {
  local file="$1"
  local global_skill="$2"
  local overlay="$3"
  rg -Fq -- "\`$global_skill\` to \`$overlay\`" "$file"
}

for name in "${overlay_names[@]}"; do
  if ! route_pair_present "$ROOT/AGENTS.md" "global:$name" ".agents/overlays/$name.md"; then
    error "AGENTS.md is missing route pair: global:$name -> .agents/overlays/$name.md"
  fi
done

profile="$ROOT/.agents/review-profiles/thermo-gitmenubar.md"
for pair in \
  'global:menubar|.agents/overlays/menubar.md' \
  'global:delivery-workflow|.agents/overlays/delivery-workflow.md'; do
  IFS='|' read -r global_skill overlay <<< "$pair"
  if ! profile_route_present "$profile" "$global_skill" "$overlay"; then
    error ".agents/review-profiles/thermo-gitmenubar.md is missing route pair: $global_skill -> $overlay"
  fi
done

route_fixture="$(mktemp)"
trap 'rm -f "$route_fixture"' EXIT
sed 's#`global:menubar` + `.agents/overlays/menubar.md`#`global:menubar` + `.agents/overlays/apple-design.md`#' \
  "$ROOT/AGENTS.md" > "$route_fixture"
if route_pair_present "$route_fixture" 'global:menubar' '.agents/overlays/menubar.md'; then
  error "route-pair negative check accepted a swapped overlay"
fi

for name in "${overlay_names[@]}"; do
  overlay="$ROOT/.agents/overlays/$name.md"
  if [[ ! -f "$overlay" ]]; then
    error "missing overlay: .agents/overlays/$name.md"
    continue
  fi
  for metadata in \
    'kind: project-overlay' \
    "extends: $name" \
    'project: GitMenuBar' \
    'precedence: project'; do
    if ! rg -q -- "^$metadata$" "$overlay"; then
      error ".agents/overlays/$name.md is missing metadata: $metadata"
    fi
  done
  if [[ -d "$ROOT/.agents/skills/$name" ]]; then
    error "same-name local skill directory remains: .agents/skills/$name"
  fi
done

for file in AGENTS.md .agents/review-profiles/*.md; do
  for name in "${overlay_names[@]}"; do
    if rg -q -- "\.agents/skills/$name(/|\`|\"|')" "$ROOT/$file"; then
      error "$file contains stale local path for deleted generic skill: $name"
    fi
  done
done

shopt -s nullglob
plans=("$ROOT"/plans/*.md)
for plan in "${plans[@]}"; do
  [[ "$(basename "$plan")" == "README.md" ]] && continue
  relative="${plan#"$ROOT"/}"
  for pattern in \
    '^## Execution profile$' \
    '\*\*Recommended profile\*\*:' \
    '\*\*Risk/lane\*\*:' \
    '\*\*Parallelizable\*\*:' \
    '\*\*Reviewer required\*\*:' \
    '\*\*Rationale\*\*:' \
    '\*\*Escalate when\*\*:'; do
    if ! rg -q -- "$pattern" "$plan"; then
      error "$relative is missing execution-profile field: $pattern"
    fi
  done
done

while IFS=$'\t' read -r file link; do
  file="${file#"$ROOT/"}"
  [[ -z "$link" || "$link" == \#* || "$link" == http://* || "$link" == https://* || "$link" == mailto:* ]] && continue
  [[ "$link" == global:* ]] && continue
  target="${link%%#*}"
  [[ -z "$target" ]] && continue
  if [[ "$target" = /* ]]; then
    path="$target"
  else
    path="$(dirname "$ROOT/$file")/$target"
  fi
  if [[ ! -e "$path" ]]; then
    error "$file has broken Markdown link: $link"
  fi
done < <(perl -ne 'while (/\]\(([^)]+)\)/g) { print "$ARGV\t$1\n" }' \
  "$ROOT/AGENTS.md" "$ROOT/.agents/review-profiles"/*.md \
  "$ROOT/.agents/overlays"/*.md "$ROOT/plans/README.md" "$ROOT/plans"/*.md)

if ((errors > 0)); then
  echo "guidance-check: failed with $errors error(s)" >&2
  exit 1
fi

echo "guidance-check: passed"
