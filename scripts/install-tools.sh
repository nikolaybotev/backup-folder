#!/usr/bin/env bash
set -euo pipefail

GH_REPO="${GH_REPO:-nikolaybotev/backup-folder}"
if [[ -z "${PINS_FILE:-}" ]]; then
  PINS_FILE="${HOME}/.config/backup-folder/pins.txt"
fi

# Refusal check: uid 0 or any path component of install_dir named Backups.
# Sourced by tests; pass uid as the first argument.
install_refuse() {
  local uid="$1"
  local install_dir="${2:-${HOME}/bin}"
  if [[ "$uid" -eq 0 ]]; then
    return 1
  fi
  local part="$install_dir"
  while [[ -n "$part" && "$part" != "/" ]]; do
    if [[ "$(basename "$part")" == "Backups" ]]; then
      return 1
    fi
    part="$(dirname "$part")"
  done
  return 0
}

valid_tool_name() {
  local name="$1"
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

valid_pin_tag() {
  local tag="$1"
  [[ "$tag" == "unpinned" ]] || [[ "$tag" =~ ^v[0-9]+(\.[0-9]+)*$ ]]
}

verify_binary() {
  local file="$1"
  gh attestation verify "$file" \
    --repo "$GH_REPO" \
    --signer-workflow "${GH_REPO}/.github/workflows/release.yml" \
    --deny-self-hosted-runners
}

install_pinned_tool() {
  local tool="$1"
  local tag="$2"
  local install_dir="${HOME}/bin"
  local dest="${install_dir}/${tool}"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/install-tools.XXXXXX")"
  if ! gh release download "$tag" --repo "$GH_REPO" --pattern "$tool" --output "$tmp" --clobber; then
    rm -f "$tmp"
    return 1
  fi
  if ! verify_binary "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mkdir -p "$install_dir"
  mv "$tmp" "$dest"
  chmod 755 "$dest"
}

main() {
  if ! install_refuse "$(id -u)" "${HOME}/bin"; then
    echo "install-tools: refused (root or Backups install path)" >&2
    exit 1
  fi

  [[ -f "$PINS_FILE" ]] || {
    echo "install-tools: missing pins file: $PINS_FILE" >&2
    exit 1
  }

  local entries=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    entries+=("$line")
  done <"$PINS_FILE"

  local tool tag
  for line in "${entries[@]}"; do
    read -r tool tag <<<"$line"
    if [[ -z "${tool:-}" || -z "${tag:-}" ]]; then
      echo "install-tools: invalid pins line: $line" >&2
      exit 1
    fi
    if ! valid_tool_name "$tool"; then
      echo "install-tools: invalid tool name: $tool" >&2
      exit 1
    fi
    if ! valid_pin_tag "$tag"; then
      echo "install-tools: invalid pin tag: $tag" >&2
      exit 1
    fi
  done

  for line in "${entries[@]}"; do
    read -r tool tag <<<"$line"
    if [[ "$tag" == "unpinned" ]]; then
      echo "install-tools: skip $tool (unpinned)"
      continue
    fi
    if ! install_pinned_tool "$tool" "$tag"; then
      echo "install-tools: failed to install $tool at $tag" >&2
      exit 1
    fi
    echo "install-tools: installed $tool at $tag"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
