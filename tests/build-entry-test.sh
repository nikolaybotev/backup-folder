#!/usr/bin/env bash
# Static checks for release-builds Phase 0 (AC1, AC3, AC4). Does not compile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "build-entry-test: $*" >&2
  exit 1
}

ok() {
  echo "build-entry-test: $*"
}

[[ -f Package.swift ]] || fail "missing Package.swift"
grep -q '// swift-tools-version: 6.0' Package.swift || fail "Package.swift missing tools version 6.0"
grep -q 'backup-folder' Package.swift || fail "Package.swift missing backup-folder product"
grep -q 'drop-box-watcher' Package.swift || fail "Package.swift missing drop-box-watcher product"
grep -q 'BuildStamp' Package.swift || fail "Package.swift missing BuildStamp target"

[[ -f scripts/build.sh ]] || fail "missing scripts/build.sh"
[[ -x scripts/build.sh ]] || fail "scripts/build.sh is not executable"
grep -q 'swift build -c release' scripts/build.sh || fail "build.sh missing swift build -c release"
if grep -E 'swift build.*--product' scripts/build.sh; then
  fail "build.sh must not pass --product to swift build"
fi
if grep -qE '(^|[[:space:]])(ver|version)=.*0\.0\.0' scripts/build.sh; then
  fail "build.sh must not invent 0.0.0"
fi
grep -q 'git rev-parse HEAD' scripts/build.sh || fail "build.sh missing git rev-parse HEAD"
grep -q 'git describe --tags --dirty' scripts/build.sh || fail "build.sh missing git describe"
grep -q 'date -u +%Y-%m-%dT%H:%MZ' scripts/build.sh || fail "build.sh missing UTC timestamp"

TEST_YML="$ROOT/.github/workflows/test.yml"
[[ -f "$TEST_YML" ]] || fail "missing test.yml"
grep -q 'scripts/build.sh' "$TEST_YML" || fail "macos job must run scripts/build.sh"
grep -q 'VERSION=v0.0.0' "$TEST_YML" || fail "test.yml must export VERSION=v0.0.0 for build"
grep -q 'timeout-minutes: 5' "$TEST_YML" || fail "test.yml missing timeout-minutes: 5"
if grep 'linux:' -A200 "$TEST_YML" | grep -q 'scripts/build.sh\|swift build'; then
  fail "linux job must not run scripts/build.sh or swift build"
fi
grep -q 'build-entry-test.sh' "$TEST_YML" || fail "test.yml must run build-entry-test.sh"

CODEQL_YML="$ROOT/.github/workflows/codeql.yml"
[[ -f "$CODEQL_YML" ]] || fail "missing codeql.yml"
grep -q 'scripts/build.sh' "$CODEQL_YML" || fail "CodeQL must run scripts/build.sh"
grep -q 'VERSION=v0.0.0' "$CODEQL_YML" || fail "CodeQL must export VERSION=v0.0.0"
if grep -qE '^[[:space:]]*pull_request:' "$CODEQL_YML"; then
  fail "codeql.yml must not define pull_request trigger"
fi
grep -q '0 6 * * *' "$CODEQL_YML" || fail "codeql.yml missing nightly schedule"
grep -q 'CodeQL (Swift)' "$CODEQL_YML" || fail "codeql.yml missing job name CodeQL (Swift)"
grep -q 'macos-26' "$CODEQL_YML" || fail "codeql.yml must use macos-26"
grep -q 'timeout-minutes: 30' "$CODEQL_YML" || fail "codeql.yml missing timeout-minutes: 30"

grep -q 'scripts/build.sh' README.md || fail "README.md must mention scripts/build.sh"

[[ -f tests/build-backup-folder.sh ]] && fail "tests/build-backup-folder.sh must be deleted"

if grep -E 'swiftc.*drop-box-watcher|swiftc.*backup-folder|swiftc.*Sources/backup-folder/main' tests/macos-smoke.sh tests/macos-watcher.sh 2>/dev/null; then
  fail "smoke scripts must not swiftc-compile either product"
fi

[[ -f Sources/backup-folder/main.swift ]] || fail "missing Sources/backup-folder/main.swift"
[[ -f Sources/backup-folder/Retention.swift ]] || fail "missing Sources/backup-folder/Retention.swift"
[[ -f Sources/backup-folder/PathCheck.swift ]] || fail "missing Sources/backup-folder/PathCheck.swift"

ok "all checks passed"
