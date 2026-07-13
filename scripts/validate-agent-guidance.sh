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
require_file .agents/SKILLS_INDEX.md
require_file .agents/review-profiles/thermo-gitmenubar.md
require_text AGENTS.md '## Execution Policy'
require_text AGENTS.md 'Every implementation plan must contain an `## Execution profile` section'
require_text AGENTS.md 'global:improve'
require_text AGENTS.md 'global:thermo-nuclear-code-quality-review'
require_text .agents/SKILLS_INDEX.md 'global:improve'
require_text .agents/SKILLS_INDEX.md 'global:thermo-nuclear-code-quality-review'

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
  "$ROOT/AGENTS.md" "$ROOT/.agents/SKILLS_INDEX.md" "$ROOT/.agents/review-profiles/thermo-gitmenubar.md" "$ROOT/plans/README.md" "$ROOT/plans"/*.md)

if ((errors > 0)); then
  echo "guidance-check: failed with $errors error(s)" >&2
  exit 1
fi

echo "guidance-check: passed"
