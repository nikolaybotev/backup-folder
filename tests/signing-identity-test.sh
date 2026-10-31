#!/usr/bin/env bash
# Behavior of scripts/signing-identity.sh. Identities in this file are
# values the test sets, not a certificate subject.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/signing-identity.sh"

fail() {
  echo "signing-identity-test: $*" >&2
  exit 1
}

ok() {
  echo "signing-identity-test: $*"
}

[[ -f "$SCRIPT" ]] || fail "missing $SCRIPT"

run_identity() {
  local identity="${1-}"
  local input="${2-}"
  if [[ -n "$identity" ]]; then
    printf '%s' "$input" | SIGN_IDENTITY="$identity" bash "$SCRIPT"
  else
    printf '%s' "$input" | env -u SIGN_IDENTITY bash "$SCRIPT"
  fi
}

configured="configured-identity-$$"
got="$(run_identity "$configured" '  1) AAAA "other-identity"')" || fail "configured SIGN_IDENTITY should succeed"
[[ "$got" == "$configured" ]] || fail "expected configured value, got: $got"
ok "SIGN_IDENTITY is the configured value"

fixture=$'  1) ABCDEF0123 "fixture-identity"\n     1 valid identities found\n'
got="$(run_identity "" "$fixture")" || fail "one identity should succeed"
[[ "$got" == "fixture-identity" ]] || fail "expected fixture identity, got: $got"
ok "one quoted identity is parsed"

if run_identity "" $'     0 valid identities found\n' >/dev/null; then
  fail "zero identities should fail"
fi
ok "zero identities fail"

two=$'  1) AAAA "one-identity"\n  2) BBBB "two-identity"\n'
if run_identity "" "$two" >/dev/null; then
  fail "two identities should fail"
fi
ok "two identities fail"

if run_identity "" "" >/dev/null; then
  fail "empty input should fail"
fi
ok "empty input fails"

if grep -nE 'SIGN_IDENTITY="[^$][^"]*"' "$SCRIPT" "$ROOT/.github/workflows/release.yml"; then
  fail "SIGN_IDENTITY must not be assigned a quoted literal"
fi
ok "no quoted SIGN_IDENTITY literal"

echo "signing-identity-test: all checks passed"
