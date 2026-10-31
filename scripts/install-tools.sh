#!/usr/bin/env bash
set -euo pipefail

GH_REPO="${GH_REPO:-nikolaybotev/backup-folder}"
if [[ -z "${PINS_FILE:-}" ]]; then
  PINS_FILE="${HOME}/.config/backup-folder/pins.txt"
fi

valid_tool_name() {
  local name="$1"
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

valid_pin_tag() {
  local tag="$1"
  [[ "$tag" == "unpinned" ]] || [[ "$tag" =~ ^v[0-9]+(\.[0-9]+)*$ ]]
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
  if ! gh attestation verify "$tmp" \
    --repo "$GH_REPO" \
    --signer-workflow "${GH_REPO}/.github/workflows/release.yml" \
    --deny-self-hosted-runners; then
    rm -f "$tmp"
    return 1
  fi
  mkdir -p "$install_dir"
  mv "$tmp" "$dest"
  chmod 755 "$dest"
}

main() {
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

  local tool tag line
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
