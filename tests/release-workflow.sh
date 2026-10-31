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
BUILD_SH="$ROOT/scripts/build.sh"
[[ -f "$RELEASE_YML" ]] || fail "missing $RELEASE_YML"
[[ -f "$BUILD_SH" ]] || fail "missing $BUILD_SH"

release_text="$(<"$RELEASE_YML")"
build_text="$(<"$BUILD_SH")"

require_in_release() {
  local needle="$1"
  local desc="$2"
  if [[ "$release_text" != *"$needle"* ]]; then
    fail "release.yml missing $desc (expected substring: $needle)"
  fi
}

require_in_build() {
  local needle="$1"
  local desc="$2"
  if [[ "$build_text" != *"$needle"* ]]; then
    fail "build.sh missing $desc (expected substring: $needle)"
  fi
}

if [[ -f "$ROOT/VERSION" ]]; then
  fail "VERSION file must not exist"
fi

if ! grep -qE '^[[:space:]]*publish:[[:space:]]*$' "$RELEASE_YML"; then
  fail "release.yml must define job id publish"
fi

if grep -E '^[[:space:]]+(macos|linux):[[:space:]]*$' "$RELEASE_YML"; then
  fail "release.yml must not define macos or linux jobs"
fi

require_in_release 'branches:' "push to main branches"
require_in_release 'main' "main branch"
require_in_release 'fetch-depth: 0' "full tag history checkout"
require_in_release 'release-main' "concurrency group release-main"
require_in_release 'pull-requests: read' "pull-requests read permission"
require_in_release 'MACOS_SIGNING_P12_BASE64' "MACOS_SIGNING_P12_BASE64 secret"
require_in_release 'MACOS_SIGNING_P12_PASSWORD' "MACOS_SIGNING_P12_PASSWORD secret"
require_in_release 'release: missing ' "missing-secret error prefix"
require_in_release 'security find-identity -p codesigning "$KEYCHAIN"' "find-identity on the imported keychain"
require_in_release 'SIGN_IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | env -u SIGN_IDENTITY bash scripts/signing-identity.sh)"' "publish always derives the identity"
require_in_release 'bash scripts/signing-identity.sh' "signing-identity helper"
require_in_release 'release: missing signing identity' "missing signing identity fails the release"
require_in_release 'bash scripts/build.sh' "single build.sh invocation"
require_in_release 'codesign --verify --strict' "codesign verify strict"
require_in_release 'SHA256SUMS' "checksum file"
require_in_release 'uname -m' "architecture check"
require_in_release 'refs/tags/' "tag ref push"
require_in_release 'git rev-parse HEAD' "full SHA in release metadata"
require_in_release 'actions/attest' "actions/attest"
require_in_release 'subject-path' "subject-path"
require_in_release 'attestations: write' "attestations write permission"
require_in_release 'id-token: write' "id-token write permission"
require_in_release 'contents: write' "contents write permission"
require_in_release 'macos-latest' "macos-latest runner"
require_in_release '--repo "${{ github.repository }}"' "attestation repo from github.repository"
require_in_release '--signer-workflow "${{ github.repository }}/.github/workflows/release.yml"' "signer-workflow from github.repository"
require_in_release "--deny-self-hosted-runners" "deny-self-hosted-runners flag"
require_in_release 'gh attestation verify' "gh attestation verify"
require_in_release 'scripts/release-version.sh' "release-version.sh"
require_in_release 'base64 --decode' "base64 decode of p12"
require_in_release 'softprops/action-gh-release@v2' "gh release action"

build_count="$(grep -c 'bash scripts/build.sh' "$RELEASE_YML" || true)"
if [[ "$build_count" -ne 1 ]]; then
  fail "release.yml must invoke bash scripts/build.sh exactly once (found $build_count)"
fi

if grep -qE '^[[:space:]]*pull_request:' "$RELEASE_YML"; then
  fail "release.yml must not define pull_request trigger"
fi
if grep -qE '^[[:space:]]*schedule:' "$RELEASE_YML"; then
  fail "release.yml must not define schedule trigger"
fi
if grep -qE '^[[:space:]]*tags:' "$RELEASE_YML"; then
  fail "release.yml must not define tag push trigger"
fi

if grep -qE '^[[:space:]]*timeout-minutes:' "$RELEASE_YML"; then
  fail "release.yml publish job must not set timeout-minutes"
fi

if grep -q 'git commit' "$RELEASE_YML"; then
  fail "release.yml must not run git commit"
fi

if grep -qE 'git push.*main|push origin main|refs/heads/main' "$RELEASE_YML"; then
  fail "release.yml must not push main"
fi

if grep -q 'spctl' "$RELEASE_YML"; then
  fail "release.yml must not use spctl"
fi

verify_count="$(grep -c 'codesign --verify --strict' "$RELEASE_YML" || true)"
if [[ "$verify_count" -ne 2 ]]; then
  fail "release.yml must contain codesign --verify --strict exactly twice (found $verify_count)"
fi

require_in_release 'codesign --verify --strict ./backup-folder' "codesign verify strict on backup-folder"
require_in_release 'codesign --verify --strict "$watcher_bin"' "codesign verify strict on watcher"

build_line_num="$(grep -n 'bash scripts/build.sh' "$RELEASE_YML" | head -1 | cut -d: -f1)"
tag_push_line_num="$(grep -n 'git push origin "refs/tags/' "$RELEASE_YML" | head -1 | cut -d: -f1)"
verify_backup_line_num="$(grep -n 'codesign --verify --strict ./backup-folder' "$RELEASE_YML" | head -1 | cut -d: -f1)"
verify_watcher_line_num="$(grep -n 'codesign --verify --strict "\$watcher_bin"' "$RELEASE_YML" | head -1 | cut -d: -f1)"

if [[ -z "$build_line_num" || -z "$tag_push_line_num" || -z "$verify_backup_line_num" || -z "$verify_watcher_line_num" ]]; then
  fail "could not locate build.sh, tag push, or verify lines in release.yml"
fi

if [[ "$verify_backup_line_num" -le "$build_line_num" || "$verify_watcher_line_num" -le "$build_line_num" ]]; then
  fail "codesign --verify --strict lines must be after bash scripts/build.sh"
fi

if [[ "$verify_backup_line_num" -ge "$tag_push_line_num" || "$verify_watcher_line_num" -ge "$tag_push_line_num" ]]; then
  fail "codesign --verify --strict lines must be before git push origin \"refs/tags/"
fi

if [[ "$release_text" == *'SIGN_IDENTITY'* ]]; then
  sign_line="$(grep -n 'SIGN_IDENTITY' "$RELEASE_YML" | head -1 || true)"
  build_line="$(grep -n 'bash scripts/build.sh' "$RELEASE_YML" | head -1 || true)"
  if [[ -n "$sign_line" && -n "$build_line" ]]; then
    sign_num="${sign_line%%:*}"
    build_num="${build_line%%:*}"
    if [[ "$sign_num" -gt "$build_num" ]]; then
      fail "SIGN_IDENTITY must be set before bash scripts/build.sh"
    fi
  fi
fi

require_in_build 'codesign --sign "$SIGN_IDENTITY"' "sign with SIGN_IDENTITY"
require_in_build 'codesign --sign - --force' "ad-hoc sign when SIGN_IDENTITY is unset"
require_in_build 'swift build -c release' "swift build -c release"
require_in_build 'git rev-parse HEAD' "git rev-parse HEAD"
require_in_build 'git describe --tags --dirty' "git describe fallback"
require_in_build 'date -u +%Y-%m-%dT%H:%MZ' "UTC timestamp"
if grep -q '0\.0\.0' "$BUILD_SH"; then
  fail "build.sh must not assign 0.0.0"
fi
if grep -q '\-\-product' "$BUILD_SH"; then
  fail "build.sh must not pass --product"
fi

workflow_dir="$ROOT/.github/workflows"
for wf in "$workflow_dir"/*; do
  [[ -f "$wf" ]] || continue
  base="$(basename "$wf")"
  text="$(<"$wf")"
  if [[ "$text" == *"install-tools.sh"* ]]; then
    fail "$base contains install-tools.sh"
  fi
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

if grep -nE 'SIGN_IDENTITY="[^$][^"]*"' "$RELEASE_YML" "$BUILD_SH"; then
  fail "SIGN_IDENTITY must not be assigned a quoted literal"
fi

if grep -q 'GITHUB_REPOSITORY' "$RELEASE_YML"; then
  fail "release.yml must not read GITHUB_REPOSITORY"
fi

if grep -q 'find-identity -v' "$RELEASE_YML"; then
  fail "release.yml must not pass -v to find-identity"
fi

identity_if_count="$(grep -cF 'if [[ -z "${SIGN_IDENTITY:-}" ]]' "$RELEASE_YML" || true)"
if [[ "$identity_if_count" -ne 1 ]]; then
  fail "release.yml must check an empty derived identity once (found $identity_if_count)"
fi
find_line="$(grep -n 'security find-identity -p codesigning' "$RELEASE_YML" | head -1 | cut -d: -f1)"
empty_line="$(grep -nF 'if [[ -z "${SIGN_IDENTITY:-}" ]]' "$RELEASE_YML" | head -1 | cut -d: -f1)"
if [[ -z "$find_line" || -z "$empty_line" || "$empty_line" -lt "$find_line" ]]; then
  fail "release.yml must derive the identity before it checks for an empty one"
fi

bash "$ROOT/tests/signing-identity-test.sh"

ok "all checks passed"
