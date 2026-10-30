#!/usr/bin/env bash
# Smoke coverage for CI: build on macOS and prove APFS copy-on-write clone behavior
# on a GitHub-hosted runner (temp dirs on the boot volume). Not a substitute for
# live ~/Backups, Full Disk Access, or LaunchAgent scheduling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swiftc -O -o backup-folder backup-folder.swift Retention.swift
swiftc -O -o clonefile-probe tests/clonefile-probe.swift

SRC="$(mktemp -d)"
DEST="$(mktemp -d)"
FAIL_SRC="$(mktemp -d)"
FAIL_DEST="$(mktemp -d)"
cleanup() {
  chmod -R u+rwx "$FAIL_SRC" 2>/dev/null || true
  rm -rf "$SRC" "$DEST" "$FAIL_SRC" "$FAIL_DEST"
}
trap cleanup EXIT

mount_point="$(df "$SRC" | awk 'NR==2 {print $NF}')"
if ! diskutil info "$mount_point" 2>/dev/null | grep -qi 'apfs'; then
  echo "Expected APFS for clonefile smoke test on mount ${mount_point}" >&2
  diskutil info "$mount_point" >&2 || true
  exit 1
fi

probe_src="$SRC/clone-probe-src.txt"
probe_dst="$SRC/clone-probe-dst.txt"
printf 'clone-probe\n' >"$probe_src"
rm -f "$probe_dst"
"$ROOT/clonefile-probe" "$probe_src" "$probe_dst"
test "$(cat "$probe_dst")" = "clone-probe"
printf 'mutated-probe\n' >"$probe_src"
test "$(cat "$probe_dst")" = "clone-probe"

printf 'fixture-one\n' >"$SRC/a.txt"
mkdir -p "$SRC/sub"
printf 'fixture-two\n' >"$SRC/sub/b.txt"

"$ROOT/backup-folder" "$SRC" "$DEST"

if ! grep -q 'OK snapshot' "$DEST/backup.log"; then
  echo "backup.log missing OK line:" >&2
  cat "$DEST/backup.log" >&2 || true
  exit 1
fi
if ! grep -q '4 files, 0 full copies' "$DEST/backup.log"; then
  echo "backup.log missing expected file/fallback counts:" >&2
  cat "$DEST/backup.log" >&2 || true
  exit 1
fi

snap=""
snap_count=0
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  snap="$name"
  snap_count=$((snap_count + 1))
done < <(
  find "$DEST" -maxdepth 1 -mindepth 1 -type d -print \
    | sed 's|.*/||' \
    | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$' || true
)
if [[ "$snap_count" -ne 1 || -z "$snap" ]]; then
  echo "Expected exactly one snapshot directory, found count=${snap_count}" >&2
  ls -la "$DEST" >&2
  exit 1
fi

test "$(cat "$DEST/$snap/a.txt")" = "fixture-one"
test "$(cat "$DEST/$snap/sub/b.txt")" = "fixture-two"

printf 'mutated\n' >"$SRC/a.txt"
test "$(cat "$DEST/$snap/a.txt")" = "fixture-one"

set +e
"$ROOT/backup-folder" relative/path "$DEST" >/dev/null 2>&1
[[ $? -eq 2 ]]
"$ROOT/backup-folder" >/dev/null 2>&1
[[ $? -eq 2 ]]
set -e

mkdir -p "$FAIL_SRC/locked"
printf 'fixture-fail\n' >"$FAIL_SRC/locked/inside.txt"
chmod 000 "$FAIL_SRC/locked"

set +e
"$ROOT/backup-folder" "$FAIL_SRC" "$FAIL_DEST" >/dev/null 2>&1
fail_exit=$?
set -e
if [[ "$fail_exit" -ne 1 ]]; then
  echo "Expected exit 1 for unreadable subdirectory fixture, got ${fail_exit}" >&2
  exit 1
fi
if ! grep -q 'not publishing' "$FAIL_DEST/backup.log" 2>/dev/null; then
  echo "failure fixture backup.log missing not publishing:" >&2
  cat "$FAIL_DEST/backup.log" >&2 || true
  exit 1
fi
if grep -q 'OK snapshot' "$FAIL_DEST/backup.log" 2>/dev/null; then
  echo "failure fixture must not log OK snapshot:" >&2
  cat "$FAIL_DEST/backup.log" >&2
  exit 1
fi
fail_snap_count=0
while IFS= read -r _fail_name; do
  [[ -z "$_fail_name" ]] && continue
  fail_snap_count=$((fail_snap_count + 1))
done < <(
  find "$FAIL_DEST" -maxdepth 1 -mindepth 1 -type d -print \
    | sed 's|.*/||' \
    | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$' || true
)
if [[ "$fail_snap_count" -ne 0 ]]; then
  echo "failure fixture should leave no snapshot directory, found count=${fail_snap_count}" >&2
  ls -la "$FAIL_DEST" >&2
  exit 1
fi

echo "macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK"
