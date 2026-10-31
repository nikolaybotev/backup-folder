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
[[ "$text" == *'--repo "$GH_REPO"'* ]] || fail "download or verify must pass --repo from GH_REPO"
[[ "$text" == *'--signer-workflow "${GH_REPO}/.github/workflows/release.yml"'* ]] \
  || fail "signer-workflow must use GH_REPO"
if grep -q 'GITHUB_REPOSITORY' "$INSTALL_SCRIPT"; then
  fail "install script must not read GITHUB_REPOSITORY"
fi
[[ "$text" == *"--deny-self-hosted-runners"* ]] || fail "missing --deny-self-hosted-runners"
grep -qE 'gh release download[^;]*--clobber' "$INSTALL_SCRIPT" \
  || fail "release download must pass --clobber for pre-created mktemp output"
case "$text" in
  *launchctl*) fail "install script must not contain launchctl" ;;
  *sudo*) fail "install script must not contain sudo" ;;
esac
if grep -qE '(^|[^a-z])op([^a-z]|$)' <<<"$text"; then
  fail "install script must not contain op"
fi

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

# Stub gh: faithful release download (existing --output without --clobber fails).
# shellcheck source=tests/install-tools-gh-stub.sh
source "$ROOT/tests/install-tools-gh-stub.sh"
install_tools_write_gh_stub "$TMP_HOME/bin-stub"

default_repo="$(sed -n 's/^GH_REPO="${GH_REPO:-\([^}]*\)}"$/\1/p' "$INSTALL_SCRIPT")"
[[ -n "$default_repo" ]] || fail "installer has no default repository"

cat >"$PINS" <<'EOF'
backup-folder v1.0.0
EOF
GH_ARGS_LOG="$TMP_HOME/gh-args.log"
export GH_ARGS_LOG
: >"$GH_ARGS_LOG"
env -u GH_REPO PINS_FILE="$PINS" bash "$INSTALL_SCRIPT" || fail "pinned install with stub gh failed"
dest="$TMP_HOME/bin/backup-folder"
[[ -f "$dest" ]] || fail "expected installed binary"
ok "pinned install succeeds when mktemp output path already exists"
mode="$(stat -c '%a' "$dest" 2>/dev/null || stat -f '%OLp' "$dest")"
[[ "$mode" == "755" ]] || fail "expected mode 755, got $mode"
grep -F -- "--repo ${default_repo}" "$GH_ARGS_LOG" >/dev/null || fail "unset GH_REPO did not use the installer default"
grep -F -- "--signer-workflow ${default_repo}/.github/workflows/release.yml" "$GH_ARGS_LOG" >/dev/null \
  || fail "unset GH_REPO did not verify with the installer default"
ok "stub gh install leaves mode 755"
ok "unset GH_REPO uses the installer default"

: >"$GH_ARGS_LOG"
GH_REPO="fixture-owner/fixture-repo" PINS_FILE="$PINS" bash "$INSTALL_SCRIPT" \
  || fail "pinned install with GH_REPO override failed"
grep -F -- "--repo fixture-owner/fixture-repo" "$GH_ARGS_LOG" >/dev/null \
  || fail "GH_REPO override was not passed to gh"
grep -F -- "--signer-workflow fixture-owner/fixture-repo/.github/workflows/release.yml" "$GH_ARGS_LOG" >/dev/null \
  || fail "GH_REPO override was not used for signer-workflow"
if [[ "$default_repo" != "fixture-owner/fixture-repo" ]]; then
  if grep -F -- "--repo ${default_repo}" "$GH_ARGS_LOG" >/dev/null; then
    fail "GH_REPO override still passed the installer default"
  fi
fi
ok "GH_REPO override is the configured repository"

echo "install-tools-test: all checks passed"
