#!/usr/bin/env bash
# Multi-file swiftc allows top-level code only in main.swift; keep backup-folder.swift as the source name.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-backup-folder}"
BUILD_DIR="$(mktemp -d)"
cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

ln -s "$ROOT/backup-folder.swift" "$BUILD_DIR/main.swift"
ln -s "$ROOT/Retention.swift" "$BUILD_DIR/Retention.swift"
swiftc -O -o "$ROOT/$OUT" "$BUILD_DIR/main.swift" "$BUILD_DIR/Retention.swift"
