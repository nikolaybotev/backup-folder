#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "release-sha256sums-test: $*" >&2
  exit 1
}

ok() {
  echo "release-sha256sums-test: $*"
}

SCRIPT="$ROOT/scripts/release-sha256sums.sh"
RELEASE_YML="$ROOT/.github/workflows/release.yml"
[[ -x "$SCRIPT" ]] || fail "missing executable $SCRIPT"
[[ -f "$RELEASE_YML" ]] || fail "missing $RELEASE_YML"

release_text="$(<"$RELEASE_YML")"

if [[ "$release_text" == *'shasum -a 256 ./backup-folder "$watcher_bin"'* ]]; then
  fail "release.yml must not hash build-tree paths into SHA256SUMS"
fi

require_in_release() {
  local needle="$1"
  local desc="$2"
  if [[ "$release_text" != *"$needle"* ]]; then
    fail "release.yml missing $desc (expected substring: $needle)"
  fi
}

require_in_release 'bash scripts/release-sha256sums.sh write' "release SHA256SUMS writer"
require_in_release 'bash scripts/release-sha256sums.sh verify-artifacts' "release download-layout checksum verify"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
printf 'backup-bytes\n' >"$work/backup-folder"
printf 'watcher-bytes\n' >"$work/drop-box-watcher"
sums="$work/SHA256SUMS"

bash "$SCRIPT" write "$work/backup-folder" "$work/drop-box-watcher" "$sums"

grep -qE '^[0-9a-f]{64}  backup-folder$' "$sums" || fail "SHA256SUMS must name backup-folder at release layout"
grep -qE '^[0-9a-f]{64}  drop-box-watcher$' "$sums" || fail "SHA256SUMS must name drop-box-watcher at release layout"
grep -q 'drop-box-watcher/drop-box-watcher' "$sums" && fail "SHA256SUMS must not use nested watcher path"

bash "$SCRIPT" verify-artifacts "$work/backup-folder" "$work/drop-box-watcher" "$sums"

printf 'tampered\n' >"$work/drop-box-watcher"
if bash "$SCRIPT" verify-artifacts "$work/backup-folder" "$work/drop-box-watcher" "$sums"; then
  fail "verify-artifacts must fail when a binary does not match SHA256SUMS"
fi

ok "all checks passed"
