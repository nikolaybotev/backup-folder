#!/usr/bin/env bash
# Print the signing identity on stdout.
# SIGN_IDENTITY, when set, is that identity.
# Otherwise read `security find-identity -v -p codesigning` text on stdin
# and print the single quoted identity. Any other count fails.
set -euo pipefail

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  printf '%s\n' "$SIGN_IDENTITY"
  exit 0
fi

names=()
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ \"([^\"]+)\" ]]; then
    names+=("${BASH_REMATCH[1]}")
  fi
done

if [[ "${#names[@]}" -ne 1 ]]; then
  echo "signing-identity: missing signing identity" >&2
  exit 1
fi
printf '%s\n' "${names[0]}"
