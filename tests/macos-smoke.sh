#!/usr/bin/env bash
# Smoke coverage for CI: build on macOS and prove APFS copy-on-write clone behavior
# on a GitHub-hosted runner (temp dirs on the boot volume). Not a substitute for
# live ~/Backups, Full Disk Access, or LaunchAgent scheduling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swiftc -O -o backup-folder backup-folder.swift

SRC="$(mktemp -d)"
DEST="$(mktemp -d)"
cleanup() { rm -rf "$SRC" "$DEST"; }
trap cleanup EXIT

mount_point="$(df "$SRC" | awk 'NR==2 {print $NF}')"
if ! diskutil info "$mount_point" 2>/dev/null | grep -qi 'apfs'; then
  echo "Expected APFS for clonefile smoke test on mount ${mount_point}" >&2
  diskutil info "$mount_point" >&2 || true
  exit 1
fi

printf 'fixture-one\n' >"$SRC/a.txt"
mkdir -p "$SRC/sub"
printf 'fixture-two\n' >"$SRC/sub/b.txt"

"$ROOT/backup-folder" "$SRC" "$DEST"

if ! grep -q 'OK snapshot' "$DEST/backup.log"; then
  echo "backup.log missing OK line:" >&2
  cat "$DEST/backup.log" >&2 || true
  exit 1
fi

mapfile -t snaps < <(
  find "$DEST" -maxdepth 1 -mindepth 1 -type d -print \
    | sed 's|.*/||' \
    | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$' || true
)
if [[ "${#snaps[@]}" -ne 1 ]]; then
  echo "Expected exactly one snapshot directory, found: ${snaps[*]:-<none>}" >&2
  ls -la "$DEST" >&2
  exit 1
fi
snap="${snaps[0]}"

test "$(cat "$DEST/$snap/a.txt")" = "fixture-one"
test "$(cat "$DEST/$snap/sub/b.txt")" = "fixture-two"

src_inode="$(stat -f '%i' "$SRC/a.txt")"
snap_inode="$(stat -f '%i' "$DEST/$snap/a.txt")"
if [[ "$src_inode" != "$snap_inode" ]]; then
  echo "Expected APFS clone to share inode before mutation (src=${src_inode}, snap=${snap_inode})" >&2
  exit 1
fi

printf 'mutated\n' >"$SRC/a.txt"
test "$(cat "$DEST/$snap/a.txt")" = "fixture-one"

set +e
"$ROOT/backup-folder" relative/path "$DEST" >/dev/null 2>&1
[[ $? -eq 2 ]]
"$ROOT/backup-folder" >/dev/null 2>&1
[[ $? -eq 2 ]]
set -e

echo "macos-smoke: build OK, snapshot OK, APFS clone inode + COW OK"
