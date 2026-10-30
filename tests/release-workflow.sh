#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "release-workflow: $*" >&2
  exit 1
}

ok() {
  echo "release-workflow: $*"
}

RELEASE_YML="$ROOT/.github/workflows/release.yml"
[[ -f "$RELEASE_YML" ]] || fail "missing $RELEASE_YML"

release_text="$(<"$RELEASE_YML")"

require_in_release() {
  local needle="$1"
  local desc="$2"
  if [[ "$release_text" != *"$needle"* ]]; then
    fail "release.yml missing $desc (expected substring: $needle)"
  fi
}

require_in_release "actions/attest" "actions/attest"
require_in_release "subject-path" "subject-path"
require_in_release "attestations: write" "attestations: write permission"
require_in_release "id-token: write" "id-token: write permission"
require_in_release "contents: write" "contents: write permission"
require_in_release "macos-latest" "macos-latest runner"
require_in_release "--signer-workflow nikolaybotev/backup-folder/.github/workflows/release.yml" "signer-workflow flag"
require_in_release "--deny-self-hosted-runners" "deny-self-hosted-runners flag"
require_in_release "gh attestation verify" "gh attestation verify"
require_in_release 'tags:' "tag push trigger"
require_in_release '"v*"' "v* tag pattern"

if grep -qE '^[[:space:]]*schedule:' "$RELEASE_YML"; then
  fail "release.yml must not define a schedule trigger"
fi

if grep -qE '^[[:space:]]*branches:' "$RELEASE_YML"; then
  fail "release.yml must not define push branches"
fi

workflow_dir="$ROOT/.github/workflows"
for wf in "$workflow_dir"/*; do
  [[ -f "$wf" ]] || continue
  base="$(basename "$wf")"
  text="$(<"$wf")"
  if [[ "$text" == *"install-tools.sh"* ]]; then
    fail "$base contains install-tools.sh"
  fi
  if [[ "$text" == *"launchctl"* ]]; then
    fail "$base contains launchctl"
  fi
  if [[ "$text" == *"Backups"* ]]; then
    fail "$base contains Backups"
  fi
done

ok "all checks passed"
