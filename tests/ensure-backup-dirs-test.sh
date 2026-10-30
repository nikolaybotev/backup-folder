#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/ensure-backup-dirs.sh"

fail() {
  echo "ensure-backup-dirs-test: $*" >&2
  exit 1
}

ok() {
  echo "ensure-backup-dirs-test: $*"
}

[[ -x "$SCRIPT" ]] || chmod +x "$SCRIPT"

BASE="$(mktemp -d "${TMPDIR:-/tmp}/ensure-backup-dirs.XXXXXX")"
cleanup() {
  rm -rf "$BASE"
}
trap cleanup EXIT

TARGET="${BASE}/snap/nested/dir"
bash "$SCRIPT" "$TARGET" || fail "create failed"
[[ -d "$TARGET" ]] || fail "directory not created"
bash "$SCRIPT" "$TARGET" || fail "second run failed"
ok "create and idempotent second run"

if bash "$SCRIPT" "relative/path" 2>/dev/null; then
  fail "relative path should fail"
fi
ok "refuses relative path"

BAD="${BASE}/../outside"
if bash "$SCRIPT" "$BAD" 2>/dev/null; then
  fail "path with .. should fail"
fi
ok "refuses .. component"

FILE="${BASE}/existing-file"
touch "$FILE"
if bash "$SCRIPT" "$FILE" 2>/dev/null; then
  fail "existing file should fail"
fi
ok "refuses existing file"

MARKER="${BASE}/marker.txt"
echo "keep" >"$MARKER"
NEWDIR="${BASE}/another/backup"
bash "$SCRIPT" "$NEWDIR" || fail "create beside marker failed"
[[ -f "$MARKER" ]] || fail "marker file was deleted"
grep -q keep "$MARKER" || fail "marker file was altered"
ok "does not delete adjacent marker file"

echo "ensure-backup-dirs-test: all checks passed"
