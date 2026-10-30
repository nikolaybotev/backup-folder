#!/usr/bin/env bash
# Multi-file swiftc allows top-level code only in main.swift; keep backup-folder.swift as the source name.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-backup-folder}"
if [[ "$OUT" == /* ]]; then
  OUTPUT="$OUT"
else
  OUTPUT="$ROOT/$OUT"
fi

BUILD_DIR="$(mktemp -d)"
cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

ln -s "$ROOT/backup-folder.swift" "$BUILD_DIR/main.swift"
ln -s "$ROOT/Retention.swift" "$BUILD_DIR/Retention.swift"
ln -s "$ROOT/PathCheck.swift" "$BUILD_DIR/PathCheck.swift"
ln -s "$ROOT/WalkPolicy.swift" "$BUILD_DIR/WalkPolicy.swift"
SWIFTC_OPT="${SWIFTC_OPT:--O}"
swiftc ${SWIFTC_OPT} -o "$OUTPUT" "$BUILD_DIR/main.swift" "$BUILD_DIR/Retention.swift" "$BUILD_DIR/PathCheck.swift" "$BUILD_DIR/WalkPolicy.swift"
