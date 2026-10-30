#!/usr/bin/env bash
# Smoke coverage for CI: build on macOS and prove APFS copy-on-write clone behavior
# on a GitHub-hosted runner (temp dirs on the boot volume). Not a substitute for
# live ~/Backups, Full Disk Access, or LaunchAgent scheduling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash tests/build-backup-folder.sh
swiftc -O -o clonefile-probe tests/clonefile-probe.swift
swiftc -O -o hold-lock tests/hold-lock.swift

SRC="$(mktemp -d)"
DEST="$(mktemp -d)"
FAIL_SRC="$(mktemp -d)"
FAIL_DEST="$(mktemp -d)"
cleanup() {
  chmod -R u+rwx "$FAIL_SRC" 2>/dev/null || true
  if [[ -n "${HOLD_PID:-}" ]]; then
    kill "$HOLD_PID" 2>/dev/null || true
    wait "$HOLD_PID" 2>/dev/null || true
  fi
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

snap_dir_pattern='^([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}|[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}(-[0-9]+)+)$'

count_snapshot_dirs() {
  local root="$1"
  local n=0
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    n=$((n + 1))
  done < <(
    find "$root" -maxdepth 1 -mindepth 1 -type d -print \
      | sed 's|.*/||' \
      | grep -E "$snap_dir_pattern" || true
  )
  echo "$n"
}

list_snapshot_dirs() {
  find "$1" -maxdepth 1 -mindepth 1 -type d -print \
    | sed 's|.*/||' \
    | grep -E "$snap_dir_pattern" || true
}

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

snap_count="$(count_snapshot_dirs "$DEST")"
if [[ "$snap_count" -ne 1 ]]; then
  echo "Expected exactly one snapshot directory, found count=${snap_count}" >&2
  ls -la "$DEST" >&2
  exit 1
fi
snap="$(list_snapshot_dirs "$DEST" | head -n 1)"

test "$(cat "$DEST/$snap/a.txt")" = "fixture-one"
test "$(cat "$DEST/$snap/sub/b.txt")" = "fixture-two"

printf 'mutated\n' >"$SRC/a.txt"
test "$(cat "$DEST/$snap/a.txt")" = "fixture-one"

"$ROOT/backup-folder" "$SRC" "$DEST"
snap_count="$(count_snapshot_dirs "$DEST")"
if [[ "$snap_count" -ne 2 ]]; then
  echo "Expected two snapshot directories after second run, found count=${snap_count}" >&2
  ls -la "$DEST" >&2
  exit 1
fi
mapfile -t snaps < <(list_snapshot_dirs "$DEST" | sort)
if [[ "${#snaps[@]}" -ne 2 || "${snaps[0]}" == "${snaps[1]}" ]]; then
  echo "Expected two distinct snapshot directory names:" >&2
  printf '%s\n' "${snaps[@]}" >&2
  exit 1
fi
for s in "${snaps[@]}"; do
  test "$(cat "$DEST/$s/a.txt")" = "fixture-one"
  test "$(cat "$DEST/$s/sub/b.txt")" = "fixture-two"
done

"$ROOT/hold-lock" "$DEST" &
HOLD_PID=$!
sleep 1
set +e
"$ROOT/backup-folder" "$SRC" "$DEST" >/dev/null 2>&1
busy_exit=$?
set -e
kill "$HOLD_PID" 2>/dev/null || true
wait "$HOLD_PID" 2>/dev/null || true
HOLD_PID=""

if [[ "$busy_exit" -ne 0 ]]; then
  echo "Expected exit 0 when dest lock held, got ${busy_exit}" >&2
  exit 1
fi
if ! grep -q 'skipped; dest busy' "$DEST/backup.log"; then
  echo "backup.log missing skipped; dest busy:" >&2
  cat "$DEST/backup.log" >&2 || true
  exit 1
fi
snap_count="$(count_snapshot_dirs "$DEST")"
if [[ "$snap_count" -ne 2 ]]; then
  echo "Busy lock must not add a snapshot directory, found count=${snap_count}" >&2
  ls -la "$DEST" >&2
  exit 1
fi

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
fail_snap_count="$(count_snapshot_dirs "$FAIL_DEST")"
if [[ "$fail_snap_count" -ne 0 ]]; then
  echo "failure fixture should leave no snapshot directory, found count=${fail_snap_count}" >&2
  ls -la "$FAIL_DEST" >&2
  exit 1
fi

echo "macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK"
