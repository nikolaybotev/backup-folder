#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "setup-docs: $*" >&2
  exit 1
}

ok() {
  echo "setup-docs: $*"
}

SETUP="$ROOT/docs/setup.md"
RESTORE="$ROOT/docs/restore.md"

[[ -f "$SETUP" ]] || fail "missing $SETUP"
[[ -f "$RESTORE" ]] || fail "missing $RESTORE"

count_marked_bullets() {
  local file="$1"
  grep -Ec '^- (Manual|Script):' "$file" || true
}

setup_count="$(count_marked_bullets "$SETUP")"
restore_count="$(count_marked_bullets "$RESTORE")"

if [[ "$setup_count" -ne 33 ]]; then
  fail "docs/setup.md must have 33 Manual/Script bullets (found $setup_count)"
fi
if [[ "$restore_count" -ne 7 ]]; then
  fail "docs/restore.md must have 7 Manual/Script bullets (found $restore_count)"
fi

while IFS= read -r line; do
  if [[ "$line" =~ ^-[[:space:]] ]] && [[ ! "$line" =~ ^-[[:space:]]+(Manual|Script): ]]; then
    fail "bullet without Manual/Script mark: $line"
  fi
done < "$SETUP"

while IFS= read -r line; do
  if [[ "$line" =~ ^-[[:space:]] ]] && [[ ! "$line" =~ ^-[[:space:]]+(Manual|Script): ]]; then
    fail "bullet without Manual/Script mark: $line"
  fi
done < "$RESTORE"

require_anchor() {
  local file="$1"
  local anchor="$2"
  if ! grep -Fq "$anchor" "$file"; then
    fail "$(basename "$file") missing anchor: $anchor"
  fi
}

setup_anchors=(
  'Keep Downloaded'
  'FileVault'
  'Screen Sharing'
  'Remote Login'
  'Choose a computer name'
  'raw.github.com/OWNER/bootstrap/main/install.sh'
  'jq'
  'fresh Mac'
  'mise.en.dev'
  'wireguard-tools'
  'gh auth login'
  'gnupg'
  'pinentry'
  'signingkey'
  'Grok Bot'
  'self-hosted'
  '1Password'
  'iStat Menus'
  'MacVim'
  'wg0.conf'
  'chmod 600'
  'com.wireguard.wg0'
  'brew services'
  'fdesetup'
  'Time Machine volume'
  'External'
  'install-tools.sh'
  'code-signing'
  'ensure-backup-dirs.sh'
  'home-mirrored'
  'com.nikolay.backup.NAME'
  'drop-box-watcher.plist.template'
  'Drop Box'
  'config.toml'
  '.config/backup-folder/pins.txt'
  'pins.txt.example'
)

restore_anchors=(
  'Time Machine volume'
  'home-mirrored'
  'Keep Downloaded'
  'config.toml'
  'install-tools.sh'
  'file-access policy'
  '.config/backup-folder/pins.txt'
  'pins.txt.example'
)

for a in "${setup_anchors[@]}"; do
  require_anchor "$SETUP" "$a"
done

for a in "${restore_anchors[@]}"; do
  require_anchor "$RESTORE" "$a"
done

ok "all checks passed"
