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
LINK_SRC="$(mktemp -d)"
LINK_DEST="$(mktemp -d)"
FIFO_SRC="$(mktemp -d)"
FIFO_DEST="$(mktemp -d)"
cleanup() {
  chmod -R u+rwx "$FAIL_SRC" 2>/dev/null || true
  rm -f "$FIFO_SRC/pipe.fifo" 2>/dev/null || true
  if [[ -n "${HOLD_PID:-}" ]]; then
    kill "$HOLD_PID" 2>/dev/null || true
    wait "$HOLD_PID" 2>/dev/null || true
  fi
  if [[ -n "${FIFO_PID:-}" ]]; then
    kill "$FIFO_PID" 2>/dev/null || true
    wait "$FIFO_PID" 2>/dev/null || true
  fi
  rm -rf "$SRC" "$DEST" "$FAIL_SRC" "$FAIL_DEST" "${CONTAIN_SRC:-}" "$LINK_SRC" "$LINK_DEST" "$FIFO_SRC" "$FIFO_DEST"
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

assert_file_equals() {
  local file_path="$1"
  local expected="$2"
  local got
  if ! got="$(cat "$file_path" 2>/dev/null)"; then
    echo "Cannot read snapshot file: $file_path" >&2
    ls -la "$(dirname "$file_path")" >&2 || true
    exit 1
  fi
  if [[ "$got" != "$expected" ]]; then
    echo "Snapshot content mismatch: $file_path" >&2
    printf '  expected: %q\n' "$expected" >&2
    printf '  got:      %q\n' "$got" >&2
    exit 1
  fi
}

assert_snapshot_fixtures() {
  local snap_dir="$1"
  local expected_a="$2"
  assert_file_equals "$snap_dir/a.txt" "$expected_a"
  assert_file_equals "$snap_dir/sub/b.txt" "fixture-two"
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
first_snap="$snap"

assert_snapshot_fixtures "$DEST/$snap" "fixture-one"

printf 'mutated\n' >"$SRC/a.txt"
assert_snapshot_fixtures "$DEST/$snap" "fixture-one"

"$ROOT/backup-folder" "$SRC" "$DEST"
snap_count="$(count_snapshot_dirs "$DEST")"
if [[ "$snap_count" -ne 2 ]]; then
  echo "Expected two snapshot directories after second run, found count=${snap_count}" >&2
  ls -la "$DEST" >&2
  exit 1
fi
snaps=()
while IFS= read -r _snap_name; do
  [[ -z "$_snap_name" ]] && continue
  snaps+=("$_snap_name")
done < <(list_snapshot_dirs "$DEST" | sort)
if [[ "${#snaps[@]}" -ne 2 || "${snaps[0]}" == "${snaps[1]}" ]]; then
  echo "Expected two distinct snapshot directory names:" >&2
  printf '%s\n' "${snaps[@]}" >&2
  exit 1
fi
for s in "${snaps[@]}"; do
  if [[ "$s" == "$first_snap" ]]; then
    assert_snapshot_fixtures "$DEST/$s" "fixture-one"
  else
    assert_snapshot_fixtures "$DEST/$s" "mutated"
  fi
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

CONTAIN_SRC="$(mktemp -d)"
set +e
"$ROOT/backup-folder" "${CONTAIN_SRC}//" "${CONTAIN_SRC}/backup" >/dev/null 2>&1
contain_exit=$?
set -e
if [[ "$contain_exit" -ne 2 ]]; then
  echo "Expected exit 2 for doubled-slash source with dest inside, got ${contain_exit}" >&2
  exit 1
fi

mkdir -p "$LINK_SRC/realdir"
printf 'symlink-target\n' >"$LINK_SRC/realdir/inside.txt"
ln -s "$LINK_SRC/realdir" "$LINK_SRC/linkdir"
"$ROOT/backup-folder" "$LINK_SRC" "$LINK_DEST"
link_snap_count="$(count_snapshot_dirs "$LINK_DEST")"
if [[ "$link_snap_count" -ne 1 ]]; then
  echo "Symlink fixture expected one snapshot, found count=${link_snap_count}" >&2
  ls -la "$LINK_DEST" >&2
  exit 1
fi
link_snap="$(list_snapshot_dirs "$LINK_DEST" | head -n 1)"
link_entry="$LINK_DEST/$link_snap/linkdir"
if [[ ! -L "$link_entry" ]]; then
  echo "Expected symlink entry at $link_entry" >&2
  ls -la "$LINK_DEST/$link_snap" >&2
  exit 1
fi
if [[ "$(readlink "$link_entry")" != "$LINK_SRC/realdir" ]]; then
  echo "Symlink target mismatch for $link_entry" >&2
  printf '  expected: %q\n' "$LINK_SRC/realdir" >&2
  printf '  got:      %q\n' "$(readlink "$link_entry")" >&2
  exit 1
fi
if [[ -d "$LINK_DEST/$link_snap/linkdir/inside.txt" ]] || [[ -f "$LINK_DEST/$link_snap/linkdir/inside.txt" ]]; then
  echo "Snapshot must not walk directory symlink target tree" >&2
  find "$LINK_DEST/$link_snap" >&2 || true
  exit 1
fi

mkfifo "$FIFO_SRC/pipe.fifo"
printf 'fifo-fixture\n' >"$FIFO_SRC/ok.txt"
FIFO_PID=""
(
  "$ROOT/backup-folder" "$FIFO_SRC" "$FIFO_DEST" >/dev/null 2>&1
) &
FIFO_PID=$!
fifo_deadline=$((SECONDS + 10))
while kill -0 "$FIFO_PID" 2>/dev/null; do
  if (( SECONDS >= fifo_deadline )); then
    kill "$FIFO_PID" 2>/dev/null || true
    wait "$FIFO_PID" 2>/dev/null || true
    FIFO_PID=""
    echo "Fifo fixture exceeded 10 second limit" >&2
    exit 1
  fi
  sleep 0.2
done
wait "$FIFO_PID"
fifo_exit=$?
FIFO_PID=""
if [[ "$fifo_exit" -eq 0 ]]; then
  echo "Expected non-zero exit for fifo fixture, got ${fifo_exit}" >&2
  exit 1
fi
if ! grep -q 'skip special file' "$FIFO_DEST/backup.log" 2>/dev/null; then
  echo "Fifo fixture backup.log missing skip special file:" >&2
  cat "$FIFO_DEST/backup.log" >&2 || true
  exit 1
fi
fifo_snap_count="$(count_snapshot_dirs "$FIFO_DEST")"
if [[ "$fifo_snap_count" -ne 0 ]]; then
  echo "Fifo fixture should leave no snapshot directory, found count=${fifo_snap_count}" >&2
  ls -la "$FIFO_DEST" >&2
  exit 1
fi

echo "macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK"
