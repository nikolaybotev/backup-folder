#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

for pattern in 'Task.sleep' 'usleep' 'sleep(' 'startDownloadingUbiquitousItem'; do
  if grep -q "$pattern" drop-box-watcher/Readiness.swift; then
    echo "linux-unit: forbidden pattern $pattern in Readiness.swift" >&2
    exit 1
  fi
done

for pattern in 'Task.sleep' 'usleep' 'sleep(' 'exit('; do
  for file in drop-box-watcher/ConfigReload.swift drop-box-watcher/ConfigWatch.swift; do
    if grep -q "$pattern" "$file"; then
      echo "linux-unit: forbidden pattern $pattern in $file" >&2
      exit 1
    fi
  done
done

for file in drop-box-watcher/Watcher.swift drop-box-watcher/WatchScope.swift; do
  if [[ -f "$file" ]]; then
    for pattern in 'Task.sleep' 'usleep' 'sleep(' 'Timer' 'asyncAfter'; do
      if grep -q "$pattern" "$file"; then
        echo "linux-unit: forbidden pattern $pattern in $file" >&2
        exit 1
      fi
    done
  fi
done

if [[ -f drop-box-watcher/WatchScope.swift ]]; then
  if grep -q 'startDownloadingUbiquitousItem' drop-box-watcher/WatchScope.swift; then
    echo "linux-unit: forbidden pattern startDownloadingUbiquitousItem in WatchScope.swift" >&2
    exit 1
  fi
fi

TMPDIR="${TMPDIR:-/tmp}"
BIN="$(mktemp "$TMPDIR/linux-unit-XXXXXX")"
trap 'rm -f "$BIN"' EXIT

swiftc -O \
  Sources/ToolConfig/TomlSubset.swift \
  drop-box-watcher/Config.swift \
  drop-box-watcher/ConfigReload.swift \
  drop-box-watcher/Readiness.swift \
  drop-box-watcher/WatchScope.swift \
  drop-box-watcher/Log.swift \
  drop-box-watcher/WebhookHTTP.swift \
  drop-box-watcher/WebhookNotifier.swift \
  tests/drop-box-watcher-tests.swift \
  -o "$BIN"

"$BIN"
echo "linux-unit: OK"
