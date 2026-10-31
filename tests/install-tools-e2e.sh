#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="$ROOT/scripts/install-tools.sh"
# shellcheck source=tests/install-tools-gh-stub.sh
source "$ROOT/tests/install-tools-gh-stub.sh"

fail() {
  echo "install-tools-e2e: $*" >&2
  exit 1
}

ok() {
  echo "install-tools-e2e: $*"
}

assert_executable_755() {
  local path="$1"
  [[ -f "$path" && -x "$path" ]] || fail "expected executable file: $path"
  local mode
  mode="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%OLp' "$path")"
  [[ "$mode" == "755" ]] || fail "expected mode 755 for $path, got $mode"
}

run_stub_e2e() {
  local tag="${1:-v0.1.14}"
  local e2e_home
  e2e_home="$(mktemp -d "${TMPDIR:-/tmp}/install-tools-e2e.XXXXXX")"
  cleanup() {
    rm -rf "$e2e_home"
  }
  trap cleanup EXIT

  export HOME="$e2e_home"
  export PATH="${e2e_home}/bin-stub:${PATH:-/usr/bin:/bin}"
  install_tools_write_gh_stub "${e2e_home}/bin-stub"

  local pins log
  pins="$(mktemp "${TMPDIR:-/tmp}/install-tools-e2e-pins.XXXXXX")"
  log="${e2e_home}/gh-args.log"
  cat >"$pins" <<EOF
backup-folder ${tag}
drop-box-watcher ${tag}
EOF
  export GH_ARGS_LOG="$log"
  : >"$log"

  PINS_FILE="$pins" bash "$INSTALL_SCRIPT" || fail "end-to-end install failed (tag ${tag})"

  assert_executable_755 "${e2e_home}/bin/backup-folder"
  assert_executable_755 "${e2e_home}/bin/drop-box-watcher"

  local downloads
  downloads="$(grep -c 'release download' "$log" || true)"
  [[ "$downloads" -eq 2 ]] || fail "expected two release downloads, got ${downloads}"
  grep -q -- '--clobber' "$log" || fail "release download must pass --clobber"
  while IFS= read -r line; do
    [[ "$line" == *"release download"* ]] || continue
    [[ "$line" == *"--clobber"* ]] || fail "each release download must include --clobber: $line"
  done <"$log"

  ok "both tools installed executable at ${tag} (faithful gh stub)"
  trap - EXIT
  cleanup
}

run_real_e2e() {
  local tag="${INSTALL_TOOLS_E2E_TAG:-v0.1.14}"
  command -v gh >/dev/null 2>&1 || return 0
  gh auth status >/dev/null 2>&1 || return 0

  local e2e_home
  e2e_home="$(mktemp -d "${TMPDIR:-/tmp}/install-tools-e2e-real.XXXXXX")"
  cleanup() {
    rm -rf "$e2e_home"
  }
  trap cleanup EXIT

  export HOME="$e2e_home"
  unset GH_ARGS_LOG

  local pins
  pins="$(mktemp "${TMPDIR:-/tmp}/install-tools-e2e-real-pins.XXXXXX")"
  cat >"$pins" <<EOF
backup-folder ${tag}
drop-box-watcher ${tag}
EOF

  PINS_FILE="$pins" bash "$INSTALL_SCRIPT" || fail "real gh end-to-end install failed (tag ${tag})"

  assert_executable_755 "${e2e_home}/bin/backup-folder"
  assert_executable_755 "${e2e_home}/bin/drop-box-watcher"

  ok "both tools installed executable at ${tag} (real gh)"
  trap - EXIT
  cleanup
}

[[ -x "$INSTALL_SCRIPT" ]] || chmod +x "$INSTALL_SCRIPT"

run_stub_e2e "v0.1.14"

if [[ "${INSTALL_TOOLS_E2E_REAL_GH:-}" == "1" ]]; then
  run_real_e2e
fi

echo "install-tools-e2e: all checks passed"
