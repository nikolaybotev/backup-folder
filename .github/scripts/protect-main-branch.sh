#!/usr/bin/env bash
# Create or update a repository ruleset that blocks main deletion and force-push,
# and requires the macOS CI check. Exits 0 when the ruleset is saved or already
# present; exits 0 on HTTP 403 with a message so rollout can continue (record
# manual settings for Nikolay).
set -euo pipefail

: "${GITHUB_REPOSITORY:?}"

owner="${GITHUB_REPOSITORY%%/*}"
repo="${GITHUB_REPOSITORY##*/}"
api_base="https://api.github.com/repos/${owner}/${repo}"

# GitHub Actions reports this job as check context "macos" (workflow name: test).
required_check="${REQUIRED_CHECK_CONTEXT:-macos}"

ruleset_name="Protect main branch"
payload="$(jq -n \
  --arg name "${ruleset_name}" \
  --arg ctx "${required_check}" \
  '{
    name: $name,
    target: "branch",
    enforcement: "active",
    conditions: {
      ref_name: {
        include: ["refs/heads/main"],
        exclude: []
      }
    },
    rules: [
      { type: "deletion" },
      { type: "non_fast_forward" },
      {
        type: "required_status_checks",
        parameters: {
          strict_required_status_checks_policy: false,
          required_status_checks: [{ context: $ctx }]
        }
      }
    ]
  }')"

list_code="$(
  curl -sS -o /tmp/main-rulesets.json -w '%{http_code}' \
    -H "Authorization: Bearer ${GITHUB_TOKEN:?}" \
    -H "Accept: application/vnd.github+json" \
    "${api_base}/rulesets"
)"

if [[ "${list_code}" == "403" ]]; then
  echo "ruleset_api_forbidden=1"
  cat <<EOF
Could not list rulesets (HTTP 403). Nikolay must apply manually on branch main:
  - Block branch deletion
  - Block force pushes
  - Require status check: ${required_check}
EOF
  exit 0
fi

if [[ "${list_code}" != "200" ]]; then
  echo "Failed to list rulesets (HTTP ${list_code}):" >&2
  cat /tmp/main-rulesets.json >&2
  exit 1
fi

existing_id="$(jq -r --arg n "${ruleset_name}" '.[] | select(.name == $n) | .id' /tmp/main-rulesets.json | head -1)"

if [[ -n "${existing_id}" ]]; then
  http_code="$(
    curl -sS -o /tmp/main-ruleset-out.json -w '%{http_code}' \
      -X PUT \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "${api_base}/rulesets/${existing_id}" \
      -d "${payload}"
  )"
else
  http_code="$(
    curl -sS -o /tmp/main-ruleset-out.json -w '%{http_code}' \
      -X POST \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "${api_base}/rulesets" \
      -d "${payload}"
  )"
fi

if [[ "${http_code}" == "403" ]]; then
  echo "ruleset_api_forbidden=1"
  cat <<EOF
Could not save ruleset (HTTP 403). Nikolay must apply manually on branch main:
  - Block branch deletion
  - Block force pushes
  - Require status check: ${required_check}
EOF
  exit 0
fi

if [[ "${http_code}" =~ ^20 ]]; then
  echo "ruleset_saved=1"
  cat /tmp/main-ruleset-out.json
  exit 0
fi

echo "Failed to save ruleset (HTTP ${http_code}):" >&2
cat /tmp/main-ruleset-out.json >&2
exit 1
