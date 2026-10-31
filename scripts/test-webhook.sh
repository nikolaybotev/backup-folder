#!/bin/sh
CFG="${1:-$HOME/.config/drop-box-watcher/config.toml}"

if [ ! -r "$CFG" ]; then
  echo "test-webhook: config file missing or unreadable: $CFG" >&2
  exit 2
fi

val() {
  awk -F'"' -v k="$1" '
    /^[[:space:]]*\[/ { s = ($0 ~ /^[[:space:]]*\[webhook\]/) }
    s && $1 ~ "^[[:space:]]*" k "[[:space:]]*=" { print $2; exit }
  ' "$CFG"
}

if ! awk '/^[[:space:]]*\[webhook\]/ { found = 1; exit } END { exit !found }' "$CFG"; then
  echo "test-webhook: missing [webhook] section in config" >&2
  exit 2
fi

url="$(val url)"
key="$(val key)"

if [ -z "$url" ] && [ -z "$key" ]; then
  echo "test-webhook: missing [webhook] url and key in config" >&2
  exit 2
fi

if [ -z "$url" ]; then
  echo "test-webhook: missing webhook url in config" >&2
  exit 2
fi

if [ -z "$key" ]; then
  echo "test-webhook: missing webhook key in config" >&2
  exit 2
fi

printf 'url = "%s"\nheader = "Authorization: Bearer %s"\n' "$url" "$key" |
  curl -sS -K - -X POST \
    -H 'Content-Type: application/json' \
    -d '{"source":"manual","files":[]}' \
    -w '\nHTTP %{http_code}\n'
