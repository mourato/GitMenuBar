#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

APP_PATH="${1:-}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

usage() {
  echo "Usage: $0 [--dry-run] /path/to/App.app" >&2
}

[[ -n "$APP_PATH" ]] || { usage; exit 2; }
[[ "$(uname -s)" == "Darwin" ]] || { echo "This script only supports macOS." >&2; exit 1; }
[[ -x "$LSREGISTER" ]] || { echo "Launch Services tool not found: $LSREGISTER" >&2; exit 1; }
[[ -d "$APP_PATH" ]] || { echo "Canonical app not found: $APP_PATH" >&2; exit 1; }
[[ -f "$APP_PATH/Contents/Info.plist" ]] || { echo "App Info.plist not found: $APP_PATH" >&2; exit 1; }

APP_NAME="$(basename "$APP_PATH" .app)"
APP_BUNDLE_IDENTIFIER="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
[[ -n "$APP_BUNDLE_IDENTIFIER" ]] || { echo "App bundle identifier is missing: $APP_PATH" >&2; exit 1; }

dump_path="$(mktemp "${TMPDIR:-/tmp}/${APP_NAME}.launch-services.XXXXXX")"
trap 'rm -f "$dump_path"' EXIT
"$LSREGISTER" -dump > "$dump_path"

unregistered=0
while IFS= read -r registered_path; do
  [[ -n "$registered_path" && "$registered_path" != "$APP_PATH" ]] || continue
  if (( DRY_RUN )); then
    printf 'Would unregister: %s\n' "$registered_path"
  else
    "$LSREGISTER" -u "$registered_path"
    printf 'Unregistered: %s\n' "$registered_path"
  fi
  unregistered=$((unregistered + 1))
done < <(
  awk -v expected="$APP_BUNDLE_IDENTIFIER" '
    function flush() {
      if (path != "" && identifier == expected) print path
    }
    /^bundle id:/ {
      flush()
      path = ""
      identifier = ""
    }
    /^path:[[:space:]]/ {
      path = $0
      sub(/^[^:]+:[[:space:]]*/, "", path)
      sub(/[[:space:]]+\(0x[[:xdigit:]]+\)$/, "", path)
    }
    /^identifier:[[:space:]]/ {
      identifier = $0
      sub(/^[^:]+:[[:space:]]*/, "", identifier)
    }
    END { flush() }
  ' "$dump_path" | sort -u
)

if (( DRY_RUN )); then
  printf 'Would register canonical app: %s\n' "$APP_PATH"
  printf 'Found %d stale %s registration(s).\n' "$unregistered" "$APP_NAME"
else
  "$LSREGISTER" -f "$APP_PATH"
  printf 'Registered canonical app: %s\n' "$APP_PATH"
  printf 'Removed %d stale %s registration(s).\n' "$unregistered" "$APP_NAME"
fi
