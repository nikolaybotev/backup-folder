#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: release-sha256sums.sh write <backup-folder> <drop-box-watcher> [SHA256SUMS]" >&2
  echo "       release-sha256sums.sh verify-artifacts <backup-folder> <drop-box-watcher> <SHA256SUMS>" >&2
  exit 1
}

write_sums() {
  local backup="$1"
  local watcher="$2"
  local out="${3:-SHA256SUMS}"
  local stage
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' RETURN
  cp "$backup" "$stage/backup-folder"
  cp "$watcher" "$stage/drop-box-watcher"
  ( cd "$stage" && shasum -a 256 backup-folder drop-box-watcher ) >"$out"
}

verify_artifacts() {
  local backup="$1"
  local watcher="$2"
  local sums="$3"
  local dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' RETURN
  cp "$backup" "$dir/backup-folder"
  cp "$watcher" "$dir/drop-box-watcher"
  cp "$sums" "$dir/SHA256SUMS"
  ( cd "$dir" && shasum -a 256 -c SHA256SUMS )
}

case "${1:-}" in
  write)
    [[ $# -ge 3 && $# -le 4 ]] || usage
    write_sums "$2" "$3" "${4:-SHA256SUMS}"
    ;;
  verify-artifacts)
    [[ $# -eq 4 ]] || usage
    verify_artifacts "$2" "$3" "$4"
    ;;
  *)
    usage
    ;;
esac
