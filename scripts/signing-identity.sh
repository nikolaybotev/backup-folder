#!/usr/bin/env bash
# Print the single quoted name from `security find-identity -p codesigning`
# text on stdin. Count only the matching-identities section.
# Names under "Valid identities only" do not count. Zero names or more
# than one in the matching section fail.
set -euo pipefail

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
