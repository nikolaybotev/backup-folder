#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "release-version-test: $*" >&2
  exit 1
}

ok() {
  echo "release-version-test: $*"
}

SCRIPT="$ROOT/scripts/release-version.sh"
[[ -x "$SCRIPT" ]] || fail "missing $SCRIPT"

run_in_repo() {
  local dir="$1"
  (
    cd "$dir"
    export RELEASE_VERSION_TEST_LABELS="${RELEASE_VERSION_TEST_LABELS-}"
    export RELEASE_VERSION_TEST_LABEL_LOOKUP_FAIL="${RELEASE_VERSION_TEST_LABEL_LOOKUP_FAIL-}"
    "$SCRIPT"
  )
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

init_repo() {
  local branch="${1:-release-test}"
  git -C "$tmpdir" init -b "$branch" >/dev/null
  git -C "$tmpdir" config user.email "test@example.com"
  git -C "$tmpdir" config user.name "Test"
  echo x >"$tmpdir/README.md"
  git -C "$tmpdir" add README.md
  git -C "$tmpdir" commit -m "init" >/dev/null
}

commit_with_subject() {
  local subject="$1"
  echo bump >>"$tmpdir/README.md"
  git -C "$tmpdir" add README.md
  git -C "$tmpdir" commit -m "$subject" >/dev/null
}

assert_tag() {
  local dir="$1"
  local want="$2"
  local labels="${3-}"
  local got
  if [[ $# -ge 3 ]]; then
    RELEASE_VERSION_TEST_LABELS="$labels" got="$(run_in_repo "$dir")"
  else
    unset RELEASE_VERSION_TEST_LABELS
    got="$(run_in_repo "$dir")"
  fi
  if [[ "$got" != "$want" ]]; then
    fail "want '$want', got '$got'"
  fi
}

assert_fail() {
  local dir="$1"
  shift
  if (
    cd "$dir"
    "$@"
    "$SCRIPT"
  ) >/dev/null 2>&1; then
    fail "expected non-zero exit"
  fi
}

init_repo release-test
commit_with_subject "feat: first merge (#1)"
assert_tag "$tmpdir" "tag v0.1.1" ""

git -C "$tmpdir" tag v0.1.9 >/dev/null
commit_with_subject "fix: patch (#2)"
assert_tag "$tmpdir" "tag v0.1.10" ""
git -C "$tmpdir" tag v0.1.10 >/dev/null

commit_with_subject "feat: minor (#3)"
assert_tag "$tmpdir" "tag v0.2.0" $'release:minor'
git -C "$tmpdir" tag v0.2.0 >/dev/null

commit_with_subject "feat: major (#4)"
assert_tag "$tmpdir" "tag v1.0.0" $'release:major'
git -C "$tmpdir" tag v1.0.0 >/dev/null

commit_with_subject "bad: both (#5)"
assert_fail "$tmpdir" env RELEASE_VERSION_TEST_LABELS=$'release:minor\nrelease:major'

commit_with_subject "bad: no pr number"
assert_fail "$tmpdir" env RELEASE_VERSION_TEST_LABELS=""

commit_with_subject "fix: lookup (#6)"
assert_fail "$tmpdir" env RELEASE_VERSION_TEST_LABEL_LOOKUP_FAIL=1

commit_with_subject "fix: patch again (#7)"
assert_tag "$tmpdir" "tag v1.0.1" ""

git -C "$tmpdir" tag v1.0.1 >/dev/null
got="$(run_in_repo "$tmpdir")"
[[ "$got" == "noop" ]] || fail "tag on HEAD want noop, got '$got'"

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$ROOT" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    if git -C "$tmpdir" rev-parse --verify main >/dev/null 2>&1; then
      fail "temp repo must not use branch main alongside real repo work"
    fi
  fi
fi

ok "all checks passed"
