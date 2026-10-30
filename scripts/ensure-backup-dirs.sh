#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ensure-backup-dirs: $*" >&2
  exit 1
}

if [[ $# -lt 1 ]]; then
  fail "requires at least one absolute directory path"
fi

for path in "$@"; do
  if [[ "$path" != /* ]]; then
    fail "relative path refused: $path"
  fi
  IFS=/ read -ra parts <<<"${path#/}"
  for part in "${parts[@]}"; do
    if [[ "$part" == ".." ]]; then
      fail "path contains .. component: $path"
    fi
  done
  if [[ -e "$path" && ! -d "$path" ]]; then
    fail "existing file at path: $path"
  fi
  mkdir -p "$path"
done
