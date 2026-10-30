#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="$ROOT/scripts/install-tools.sh"

fail() {
  echo "install-tools-test: $*" >&2
  exit 1
}

ok() {
  echo "install-tools-test: $*"
}

[[ -x "$INSTALL_SCRIPT" ]] || chmod +x "$INSTALL_SCRIPT"

# Static checks on install script source
text="$(<"$INSTALL_SCRIPT")"
[[ "$text" == *"--repo nikolaybotev/backup-folder"* ]] || fail "missing --repo flag"
[[ "$text" == *"--signer-workflow nikolaybotev/backup-folder/.github/workflows/release.yml"* ]] \
  || fail "missing --signer-workflow flag"
[[ "$text" == *"--deny-self-hosted-runners"* ]] || fail "missing --deny-self-hosted-runners"
case "$text" in
  *launchctl*) fail "install script must not contain launchctl" ;;
  *sudo*) fail "install script must not contain sudo" ;;
esac
if grep -qE '(^|[^a-z])op([^a-z]|$)' <<<"$text"; then
  fail "install script must not contain op"
fi

# Source refusal function
# shellcheck source=/dev/null
source "$INSTALL_SCRIPT"

if install_refuse 0 "${HOME}/bin"; then
  fail "expected refusal for uid 0"
fi
ok "refuses uid 0"

if install_refuse 501 "/Users/test/Backups/mirror"; then
  fail "expected refusal for Backups path component"
fi
ok "refuses Backups path component"

# AC3: missing default pin file (PINS_FILE unset)
MISS_HOME="$(mktemp -d "${TMPDIR:-/tmp}/install-test-miss-home.XXXXXX")"
cleanup_miss() {
  rm -rf "$MISS_HOME"
}
trap cleanup_miss EXIT
(
  export HOME="$MISS_HOME"
  unset PINS_FILE
  if bash "$INSTALL_SCRIPT"; then
    exit 1
  fi
  [[ ! -e "$MISS_HOME/bin" ]] || exit 2
  [[ ! -e "$MISS_HOME/.config/backup-folder" ]] || exit 3
) || fail "missing default pin file case failed"
ok "missing default pin file exits non-zero without creating bin or config dir"
trap - EXIT
cleanup_miss

# AC3: default pin path with pins.txt.example copied (PINS_FILE unset)
SUCCESS_HOME="$(mktemp -d "${TMPDIR:-/tmp}/install-test-success-home.XXXXXX")"
cleanup_success() {
  rm -rf "$SUCCESS_HOME"
}
trap cleanup_success EXIT
(
  export HOME="$SUCCESS_HOME"
  unset PINS_FILE
  mkdir -p "$SUCCESS_HOME/.config/backup-folder"
  cp "$ROOT/pins.txt.example" "$SUCCESS_HOME/.config/backup-folder/pins.txt"
  bash "$INSTALL_SCRIPT" || exit 1
  [[ ! -e "$SUCCESS_HOME/bin/backup-folder" ]] || exit 2
  [[ ! -e "$SUCCESS_HOME/bin/drop-box-watcher" ]] || exit 3
) || fail "default pin path with example file failed"
ok "default pin path with example unpinned lines exits 0 without installing"
trap - EXIT
cleanup_success

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/install-test-home.XXXXXX")"
cleanup() {
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT

export HOME="$TMP_HOME"
export PATH="$TMP_HOME/bin-stub:${PATH:-/usr/bin:/bin}"
mkdir -p "$TMP_HOME/bin-stub"

PINS="$(mktemp "${TMPDIR:-/tmp}/pins.XXXXXX")"

# Both unpinned: exit 0, no binaries
cat >"$PINS" <<'EOF'
backup-folder unpinned
drop-box-watcher unpinned
EOF
PINS_FILE="$PINS" bash "$INSTALL_SCRIPT" || fail "unpinned run failed"
[[ ! -e "$TMP_HOME/bin/backup-folder" ]] || fail "unexpected backup-folder binary"
[[ ! -e "$TMP_HOME/bin/drop-box-watcher" ]] || fail "unexpected drop-box-watcher binary"
ok "unpinned skips without installing"

# Invalid pin: non-zero, nothing installed
cat >"$PINS" <<'EOF'
backup-folder not-a-tag
EOF
if PINS_FILE="$PINS" bash "$INSTALL_SCRIPT"; then
  fail "invalid pin should exit non-zero"
fi
[[ ! -e "$TMP_HOME/bin/backup-folder" ]] || fail "invalid pin must install nothing"
ok "invalid pin exits non-zero and installs nothing"

# Invalid tool name with slash
cat >"$PINS" <<'EOF'
bad/name v1.0.0
EOF
if PINS_FILE="$PINS" bash "$INSTALL_SCRIPT"; then
  fail "slash in tool name should exit non-zero"
fi
ok "tool name with slash refused"

cat >"$PINS" <<'EOF'
bad..name v1.0.0
EOF
if PINS_FILE="$PINS" bash "$INSTALL_SCRIPT"; then
  fail "invalid tool name should exit non-zero"
fi
ok "invalid tool name refused"

# Stub gh: write output file and exit 0
cat >"$TMP_HOME/bin-stub/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "attestation" && "${2:-}" == "verify" ]]; then
  exit 0
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      printf 'stub-binary' >"$2"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done
exit 0
STUB
chmod +x "$TMP_HOME/bin-stub/gh"

cat >"$PINS" <<'EOF'
backup-folder v1.0.0
EOF
PINS_FILE="$PINS" bash "$INSTALL_SCRIPT" || fail "pinned install with stub gh failed"
dest="$TMP_HOME/bin/backup-folder"
[[ -f "$dest" ]] || fail "expected installed binary"
mode="$(stat -c '%a' "$dest" 2>/dev/null || stat -f '%OLp' "$dest")"
[[ "$mode" == "755" ]] || fail "expected mode 755, got $mode"
ok "stub gh install leaves mode 755"

echo "install-tools-test: all checks passed"
