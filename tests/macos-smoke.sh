#!/usr/bin/env bash
# Smoke coverage for CI: build on macOS and prove APFS copy-on-write clone behavior
# on a GitHub-hosted runner (temp dirs on the boot volume). Not a substitute for
# live ~/Backups, Full Disk Access, or LaunchAgent scheduling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -x "$ROOT/backup-folder" ]]; then
  echo "Missing backup-folder binary; run bash scripts/build.sh" >&2
  exit 1
fi

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
CONFIG_TMP="$(mktemp -d)"
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
  rm -rf "$SRC" "$DEST" "$FAIL_SRC" "$FAIL_DEST" "${CONTAIN_SRC:-}" "$LINK_SRC" "$LINK_DEST" "$FIFO_SRC" "$FIFO_DEST" "${LINK_HIDDEN:-}"
  if [[ -n "${CONFIG_TMP:-}" ]]; then
    rm -rf "$CONFIG_TMP"
  fi
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

LINK_HIDDEN="$(mktemp -d)"
mkdir -p "$LINK_HIDDEN/realdir"
printf 'symlink-target\n' >"$LINK_HIDDEN/realdir/inside.txt"
ln -s "$LINK_HIDDEN/realdir" "$LINK_SRC/linkdir"
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
if [[ "$(readlink "$link_entry")" != "$LINK_HIDDEN/realdir" ]]; then
  echo "Symlink target mismatch for $link_entry" >&2
  printf '  expected: %q\n' "$LINK_HIDDEN/realdir" >&2
  printf '  got:      %q\n' "$(readlink "$link_entry")" >&2
  exit 1
fi
link_inside_leak=0
while IFS= read -r _leak_path; do
  [[ -z "$_leak_path" ]] && continue
  link_inside_leak=1
done < <(find "$LINK_DEST/$link_snap" -name inside.txt -type f -print 2>/dev/null || true)
if [[ -d "$link_entry" && ! -L "$link_entry" ]] || [[ "$link_inside_leak" -eq 1 ]]; then
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
set +e
wait "$FIFO_PID"
fifo_exit=$?
set -e
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

run_job_config() {
  local mode="$1"
  local body="$2"
  local cfg="$CONFIG_TMP/job.toml"
  printf '%s\n' "$body" >"$cfg"
  chmod "$mode" "$cfg"
  set +e
  "$ROOT/backup-folder" --config "$cfg" >/dev/null 2>"$CONFIG_TMP/job.err"
  JOB_RC=$?
  set -e
}

JOB_A_SRC="$CONFIG_TMP/a-src"
JOB_A_DEST="$CONFIG_TMP/a-dest"
JOB_B_SRC="$CONFIG_TMP/b-src"
JOB_B_DEST="$CONFIG_TMP/b-dest"
mkdir -p "$JOB_A_SRC" "$JOB_B_SRC"
printf 'job-a\n' >"$JOB_A_SRC/a.txt"
printf 'job-b\n' >"$JOB_B_SRC/b.txt"
run_job_config 600 "$(cat <<EOF
[[folder]]
source = "$JOB_A_SRC"
dest = "$JOB_A_DEST"

[[folder]]
source = "$JOB_B_SRC"
dest = "$JOB_B_DEST"
EOF
)"
if [[ "$JOB_RC" -ne 0 ]]; then
  echo "Expected exit 0 for two config folders, got ${JOB_RC}" >&2
  cat "$CONFIG_TMP/job.err" >&2 || true
  exit 1
fi
if [[ "$(count_snapshot_dirs "$JOB_A_DEST")" -ne 1 || "$(count_snapshot_dirs "$JOB_B_DEST")" -ne 1 ]]; then
  echo "Expected one snapshot in each config destination" >&2
  ls -la "$JOB_A_DEST" "$JOB_B_DEST" >&2
  exit 1
fi
if ! grep -q 'OK snapshot' "$JOB_A_DEST/backup.log" || ! grep -q 'OK snapshot' "$JOB_B_DEST/backup.log"; then
  echo "Config job missing OK snapshot in a destination log" >&2
  exit 1
fi

MISS_SRC="$CONFIG_TMP/missing-src"
MISS_DEST="$CONFIG_TMP/missing-dest"
MISS_OK_SRC="$CONFIG_TMP/missing-ok-src"
MISS_OK_DEST="$CONFIG_TMP/missing-ok-dest"
mkdir -p "$MISS_OK_SRC"
printf 'present\n' >"$MISS_OK_SRC/a.txt"
run_job_config 600 "$(cat <<EOF
[[folder]]
source = "$MISS_SRC"
dest = "$MISS_DEST"

[[folder]]
source = "$MISS_OK_SRC"
dest = "$MISS_OK_DEST"
EOF
)"
if [[ "$JOB_RC" -ne 1 ]]; then
  echo "Expected exit 1 when one config source is missing, got ${JOB_RC}" >&2
  cat "$CONFIG_TMP/job.err" >&2 || true
  exit 1
fi
if [[ "$(count_snapshot_dirs "$MISS_OK_DEST")" -ne 1 ]]; then
  echo "Missing-source case should still publish the other folder" >&2
  ls -la "$MISS_OK_DEST" >&2 || true
  exit 1
fi
if [[ "$(count_snapshot_dirs "$MISS_DEST")" -ne 0 ]]; then
  echo "Missing source must not publish a snapshot" >&2
  ls -la "$MISS_DEST" >&2
  exit 1
fi

DUP_SRC_A="$CONFIG_TMP/dup-src-a"
DUP_SRC_B="$CONFIG_TMP/dup-src-b"
DUP_DEST="$CONFIG_TMP/dup-dest"
mkdir -p "$DUP_SRC_A" "$DUP_SRC_B"
printf 'dup-a\n' >"$DUP_SRC_A/a.txt"
printf 'dup-b\n' >"$DUP_SRC_B/b.txt"
run_job_config 600 "$(cat <<EOF
[[folder]]
source = "$DUP_SRC_A"
dest = "$DUP_DEST"

[[folder]]
source = "$DUP_SRC_B"
dest = "$DUP_DEST"
EOF
)"
if [[ "$JOB_RC" -ne 2 ]]; then
  echo "Expected exit 2 for duplicate dest, got ${JOB_RC}" >&2
  cat "$CONFIG_TMP/job.err" >&2 || true
  exit 1
fi
if [[ -d "$DUP_DEST" ]]; then
  echo "Duplicate dest must not create a destination" >&2
  ls -la "$DUP_DEST" >&2
  exit 1
fi

LOOSE_SRC="$CONFIG_TMP/loose-src"
LOOSE_DEST="$CONFIG_TMP/loose-dest"
mkdir -p "$LOOSE_SRC"
printf 'loose\n' >"$LOOSE_SRC/a.txt"
run_job_config 644 "$(cat <<EOF
[[folder]]
source = "$LOOSE_SRC"
dest = "$LOOSE_DEST"
EOF
)"
if [[ "$JOB_RC" -ne 2 ]]; then
  echo "Expected exit 2 for mode 0644 config, got ${JOB_RC}" >&2
  cat "$CONFIG_TMP/job.err" >&2 || true
  exit 1
fi
if [[ -d "$LOOSE_DEST" ]]; then
  echo "Mode 0644 config must not start a folder" >&2
  ls -la "$LOOSE_DEST" >&2
  exit 1
fi

IN_SRC="$CONFIG_TMP/in-src"
IN_GOOD_SRC="$CONFIG_TMP/in-good-src"
IN_GOOD_DEST="$CONFIG_TMP/in-good-dest"
mkdir -p "$IN_SRC" "$IN_GOOD_SRC"
printf 'inside\n' >"$IN_SRC/a.txt"
printf 'beside\n' >"$IN_GOOD_SRC/a.txt"
run_job_config 600 "$(cat <<EOF
[[folder]]
source = "$IN_SRC"
dest = "$IN_SRC/nested"

[[folder]]
source = "$IN_GOOD_SRC"
dest = "$IN_GOOD_DEST"
EOF
)"
if [[ "$JOB_RC" -ne 2 ]]; then
  echo "Expected exit 2 when one dest is inside its source, got ${JOB_RC}" >&2
  cat "$CONFIG_TMP/job.err" >&2 || true
  exit 1
fi
if [[ "$(count_snapshot_dirs "$IN_GOOD_DEST")" -ne 1 ]]; then
  echo "Containment beside a good folder should still publish that folder" >&2
  ls -la "$IN_GOOD_DEST" >&2 || true
  exit 1
fi
if [[ -e "$IN_SRC/nested" ]]; then
  echo "Dest inside source must not be created" >&2
  ls -la "$IN_SRC" >&2
  exit 1
fi

BUSY_SRC="$CONFIG_TMP/busy-src"
BUSY_DEST="$CONFIG_TMP/busy-dest"
BUSY_OK_SRC="$CONFIG_TMP/busy-ok-src"
BUSY_OK_DEST="$CONFIG_TMP/busy-ok-dest"
mkdir -p "$BUSY_SRC" "$BUSY_DEST" "$BUSY_OK_SRC"
printf 'busy-src\n' >"$BUSY_SRC/a.txt"
printf 'busy-ok\n' >"$BUSY_OK_SRC/a.txt"
"$ROOT/hold-lock" "$BUSY_DEST" &
HOLD_PID=$!
sleep 1
run_job_config 600 "$(cat <<EOF
[[folder]]
source = "$BUSY_SRC"
dest = "$BUSY_DEST"

[[folder]]
source = "$BUSY_OK_SRC"
dest = "$BUSY_OK_DEST"
EOF
)"
kill "$HOLD_PID" 2>/dev/null || true
wait "$HOLD_PID" 2>/dev/null || true
HOLD_PID=""
if [[ "$JOB_RC" -ne 0 ]]; then
  echo "Expected exit 0 when one config dest is busy, got ${JOB_RC}" >&2
  cat "$CONFIG_TMP/job.err" >&2 || true
  exit 1
fi
if ! grep -q 'skipped; dest busy' "$BUSY_DEST/backup.log"; then
  echo "Busy config dest missing skipped; dest busy:" >&2
  cat "$BUSY_DEST/backup.log" >&2 || true
  exit 1
fi
if [[ "$(count_snapshot_dirs "$BUSY_DEST")" -ne 0 ]]; then
  echo "Busy config dest must not gain a snapshot" >&2
  ls -la "$BUSY_DEST" >&2
  exit 1
fi
if [[ "$(count_snapshot_dirs "$BUSY_OK_DEST")" -ne 1 ]]; then
  echo "Busy dest beside a good folder should still publish that folder" >&2
  ls -la "$BUSY_OK_DEST" >&2 || true
  exit 1
fi

SAME_REAL="$CONFIG_TMP/same-real"
SAME_LINK_A="$CONFIG_TMP/same-link-a"
SAME_LINK_B="$CONFIG_TMP/same-link-b"
mkdir -p "$SAME_REAL"
ln -s "$SAME_REAL" "$SAME_LINK_A"
ln -s "$SAME_REAL" "$SAME_LINK_B"
run_job_config 600 "$(cat <<EOF
[[folder]]
source = "$CONFIG_TMP/same-src-a"
dest = "$SAME_LINK_A"

[[folder]]
source = "$CONFIG_TMP/same-src-b"
dest = "$SAME_LINK_B"
EOF
)"
if [[ "$JOB_RC" -ne 2 ]]; then
  echo "Expected exit 2 for two symlink dests to one directory, got ${JOB_RC}" >&2
  cat "$CONFIG_TMP/job.err" >&2 || true
  exit 1
fi
if [[ "$(count_snapshot_dirs "$SAME_REAL")" -ne 0 ]]; then
  echo "Symlink dests to one directory must publish nothing" >&2
  ls -la "$SAME_REAL" >&2
  exit 1
fi

echo "macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK"
