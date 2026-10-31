#!/usr/bin/env bash
# Print the signing identity on stdout.
# SIGN_IDENTITY, when set, is that identity.
# Otherwise read `security find-identity -p codesigning` text on stdin
# and print the single quoted name from the matching-identities section.
# Names under "Valid identities only" do not count. Zero names or more
# than one in the matching section fail.
set -euo pipefail

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  printf '%s\n' "$SIGN_IDENTITY"
  exit 0
fi

names=()
in_matching=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == *"Valid identities only"* ]]; then
    in_matching=0
    continue
  fi
  if [[ "$line" == *"Matching identities"* ]]; then
    in_matching=1
    continue
  fi
  if [[ "$in_matching" -eq 1 && "$line" =~ \"([^\"]+)\" ]]; then
    names+=("${BASH_REMATCH[1]}")
  fi
done

if [[ "${#names[@]}" -ne 1 ]]; then
  echo "signing-identity: missing signing identity" >&2
  exit 1
fi
printf '%s\n' "${names[0]}"
