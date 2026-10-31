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

untrusted=$'Policy: Code Signing\n  Matching identities\n  1) ABCDEF0123 "fixture-identity" (CSSMERR_TP_NOT_TRUSTED)\n     1 identities found\n\n  Valid identities only\n     0 valid identities found\n'
preset="preset-identity-$$"
got="$(run_identity "$preset" "$untrusted")" || fail "a pre-set SIGN_IDENTITY must not replace the parsed identity"
[[ "$got" == "fixture-identity" ]] || fail "expected fixture identity, got: $got"
ok "a pre-set SIGN_IDENTITY is ignored"
got="$(run_identity "" "$untrusted")" || fail "untrusted identity should succeed"
[[ "$got" == "fixture-identity" ]] || fail "expected fixture identity, got: $got"
ok "one matching identity is parsed"

trusted=$'Policy: Code Signing\n  Matching identities\n  1) ABCDEF0123 "fixture-identity"\n     1 identities found\n\n  Valid identities only\n  1) ABCDEF0123 "fixture-identity"\n     1 valid identities found\n'
got="$(run_identity "" "$trusted")" || fail "trusted identity should succeed once"
[[ "$got" == "fixture-identity" ]] || fail "expected one identity when it is also valid, got: $got"
ok "a trusted identity is counted once"

if run_identity "" $'Policy: Code Signing\n  Matching identities\n     0 identities found\n\n  Valid identities only\n     0 valid identities found\n' >/dev/null; then
  fail "zero identities should fail"
fi
ok "zero identities fail"

two=$'  Matching identities\n  1) AAAA "one-identity"\n  2) BBBB "two-identity"\n     2 identities found\n\n  Valid identities only\n     0 valid identities found\n'
if run_identity "" "$two" >/dev/null; then
  fail "two identities should fail"
fi
ok "two identities fail"

valid_only=$'  Valid identities only\n  1) AAAA "only-valid"\n     1 valid identities found\n'
if run_identity "" "$valid_only" >/dev/null; then
  fail "a name outside matching identities should fail"
fi
ok "names outside matching identities do not count"

if run_identity "" "" >/dev/null; then
  fail "empty input should fail"
fi
ok "empty input fails"

if grep -nE 'SIGN_IDENTITY="[^$][^"]*"' "$SCRIPT" "$ROOT/.github/workflows/release.yml"; then
  fail "SIGN_IDENTITY must not be assigned a quoted literal"
fi
ok "no quoted SIGN_IDENTITY literal"

if grep -n 'find-identity -v' "$SCRIPT" "$ROOT/.github/workflows/release.yml"; then
  fail "find-identity must not pass -v"
fi
ok "find-identity does not pass -v"

if grep -n 'SIGN_IDENTITY' "$SCRIPT"; then
  fail "signing-identity.sh must not read SIGN_IDENTITY"
fi
ok "helper does not read SIGN_IDENTITY"

echo "signing-identity-test: all checks passed"
