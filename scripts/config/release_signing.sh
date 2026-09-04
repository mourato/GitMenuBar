#!/bin/bash
# Shared release signing configuration for GitMenuBar packaging and install workflows.

GITMENUBAR_RELEASE_SIGNING_MODE="${GITMENUBAR_RELEASE_SIGNING_MODE:-adhoc}"
GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY="${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY:-${GITMENUBAR_CODE_SIGN_IDENTITY:-Prisma Local Code Signing}}"

gitmenubar_list_user_keychains() {
  local login_keychain="${HOME}/Library/Keychains/login.keychain-db"
  printf '%s\n' "${login_keychain}"

  security list-keychains -d user 2>/dev/null \
    | tr -d '"' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | awk 'NF > 0'
}

gitmenubar_validate_release_signing_mode() {
  case "${GITMENUBAR_RELEASE_SIGNING_MODE}" in
    adhoc|self-signed)
      return 0
      ;;
    *)
      echo "Invalid GITMENUBAR_RELEASE_SIGNING_MODE='${GITMENUBAR_RELEASE_SIGNING_MODE}'. Use 'adhoc' or 'self-signed'." >&2
      return 1
      ;;
  esac
}

gitmenubar_release_signing_description() {
  if [ "${GITMENUBAR_RELEASE_SIGNING_MODE}" = "self-signed" ]; then
    printf 'self-signed (%s)' "${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}"
  else
    printf 'adhoc'
  fi
}

gitmenubar_release_effective_identity() {
  if [ "${GITMENUBAR_RELEASE_SIGNING_MODE}" = "self-signed" ]; then
    printf '%s' "${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}"
  else
    printf '%s' "-"
  fi
}

gitmenubar_autodetect_release_signing_mode() {
  if gitmenubar_codesign_identity_is_stable "${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}" 2 0.10; then
    printf '%s' "self-signed"
  else
    printf '%s' "adhoc"
  fi
}

gitmenubar_codesign_identity_exists() {
  local identity="$1"
  local kc=""

  while IFS= read -r kc; do
    if security find-identity -v -p codesigning "${kc}" 2>/dev/null \
      | awk -F'"' '/"/ { print $2 }' \
      | grep -Fx "${identity}" >/dev/null 2>&1; then
      return 0
    fi
  done < <(gitmenubar_list_user_keychains | awk '!seen[$0]++')

  return 1
}

# Returns:
#   0 -> identity visible in every attempt
#   1 -> identity missing in every attempt
#   2 -> identity visibility is unstable/flaky across attempts
gitmenubar_codesign_identity_is_stable() {
  local identity="$1"
  local attempts="${2:-3}"
  local interval_seconds="${3:-0.20}"
  local observed_present=0
  local observed_missing=0
  local i=1

  while [ "${i}" -le "${attempts}" ]; do
    if gitmenubar_codesign_identity_exists "${identity}"; then
      observed_present=$((observed_present + 1))
    else
      observed_missing=$((observed_missing + 1))
    fi

    if [ "${i}" -lt "${attempts}" ]; then
      sleep "${interval_seconds}"
    fi
    i=$((i + 1))
  done

  if [ "${observed_present}" -eq "${attempts}" ]; then
    return 0
  fi

  if [ "${observed_present}" -eq 0 ]; then
    return 1
  fi

  return 2
}

gitmenubar_print_codesign_identity_diagnostics() {
  local identity="$1"
  local login_keychain="${HOME}/Library/Keychains/login.keychain-db"

  cat >&2 <<EOF
Keychain diagnostics for '${identity}':
  default-keychain: $(security default-keychain -d user 2>/dev/null | tr -d '"' || printf 'unavailable')
  search-list:
$(security list-keychains -d user 2>/dev/null | sed 's/^/    /' || printf '    unavailable\n')
  valid identities:
$(security find-identity -v -p codesigning 2>/dev/null | sed 's/^/    /' || printf '    unavailable\n')
EOF

  if security find-certificate -a -c "${identity}" "${login_keychain}" >/dev/null 2>&1; then
    printf '%s\n' "  certificate entry found in login keychain, but no stable usable identity was detected." >&2
  else
    printf '%s\n' "  certificate entry not found in login keychain." >&2
  fi
}

gitmenubar_require_self_signed_identity() {
  if [ "${GITMENUBAR_RELEASE_SIGNING_MODE}" != "self-signed" ]; then
    return 0
  fi

  local identity_state=1
  if gitmenubar_codesign_identity_is_stable "${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}" 3 0.20; then
    return 0
  else
    identity_state=$?
  fi

  if [ "${identity_state}" -eq 2 ]; then
    cat >&2 <<EOF
Code signing identity '${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}' was detected intermittently.
The keychain visibility is unstable for this shell session.

This can happen when login keychain state changes across sessions (GUI vs non-interactive shell).
Retry the command from the same terminal session where 'security find-identity -v -p codesigning' is stable.
EOF
    gitmenubar_print_codesign_identity_diagnostics "${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}"
    return 1
  fi

  cat >&2 <<EOF
Missing code signing identity '${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}' in keychain.

Create it with:
  ./scripts/setup-self-signed-cert.sh --name "${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}"

Or list available identities:
  security find-identity -v -p codesigning
EOF
  gitmenubar_print_codesign_identity_diagnostics "${GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY}"
  return 1
}
