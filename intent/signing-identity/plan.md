# plan.md — Signing identity

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

## Stops

None. The prompt's decisions are closed. Do not merge the pull request.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `bash tests/signing-identity-test.sh` and `bash tests/release-workflow.sh` | 0 |
| AC2 | `bash tests/install-tools-test.sh`; `GITHUB_REPOSITORY` absent from `scripts/install-tools.sh` | 0 |
| AC3 | `bash tests/setup-docs.sh`, `bash tests/no-secrets.sh`, `bash tests/linux-unit.sh` | 0 |
| AC4 | `grep '(healthy:'` on `README.md`, `docs/setup.md`, `docs/restore.md` prints nothing; `grep '(healthy: exit 0)' AGENTS.md` matches | 0 |
| AC5 | `intent/generic-docs/plan.md` contains `com.nikolaybotev.`; `git diff --diff-filter=R` shows no renamed intent directory | 0 |

## Phase 0 — Identity, labels, and writing rules

Files: `intent/signing-identity/`, `scripts/signing-identity.sh`, `scripts/install-tools.sh`, `.github/workflows/release.yml`, `tests/signing-identity-test.sh`, `tests/release-workflow.sh`, `tests/install-tools-test.sh`, `tests/no-secrets.sh`, `tests/setup-docs.sh`, `tests/drop-box-watcher-tests.swift`, `launchd/backup-folder.plist.template`, `launchd/drop-box-watcher.plist.template`, `README.md`, `docs/setup.md`, `AGENTS.md`, `REVIEW.md`, and the intent files the writing-rule sweep edits.

1. Add `scripts/signing-identity.sh` per spec FR2. In `.github/workflows/release.yml`, delete the quoted `SIGN_IDENTITY` assignment. When `SIGN_IDENTITY` is unset, pipe `security find-identity -v -p codesigning` on the imported keychain into the helper. Fail with `release: missing signing identity` when the identity is missing. Export `SIGN_IDENTITY` before the single `bash scripts/build.sh`. Point both `gh attestation verify` calls at `${{ github.repository }}`.
2. Leave `scripts/build.sh` on the ad-hoc path when `SIGN_IDENTITY` is unset. Do not add a subject name.
3. Point `scripts/install-tools.sh` verify at `$GH_REPO`. Keep the canonical default. Do not read `GITHUB_REPOSITORY`. Leave `.cursor/install.sh` as Cursor Cloud Agent setup only: hardcode `https://raw.githubusercontent.com/nikolaybotev/local-skills/main/install.sh`, with no override and no environment variable.
4. Rename the two LaunchAgent labels in the templates, tests, `README.md`, `docs/setup.md`, and `AGENTS.md`. Close the open paragraph in `intent/generic-docs/plan.md`. Do not rename intent directories. Do not rewrite historical `com.nikolay.` strings inside other intent files.
5. Remove the certificate subject from every tracked file. In prose outside verbatim prompt blocks, say "this repo" instead of this repo's owner, name, or URL. Leave distribution entry points that name the canonical repository, and leave repository URLs inside verbatim prompt blocks.
6. Add the three review items to `REVIEW.md` in the words of spec FR6. Do not remove `(healthy:` lines from `AGENTS.md`. Do not add them to the README or `docs/`.
7. Lock the behavior in `tests/signing-identity-test.sh`, `tests/release-workflow.sh`, and `tests/install-tools-test.sh` per spec FR8. `tests/release-workflow.sh` runs the signing-identity test so the existing `macos` and `linux` jobs cover it.
8. One conventional commit. One pull request, ready for review. Do not merge.

DoD: every command below exits 0.

```
set -euo pipefail
bash tests/signing-identity-test.sh
bash tests/release-workflow.sh
bash tests/install-tools-test.sh
bash tests/setup-docs.sh
bash tests/no-secrets.sh
bash tests/linux-unit.sh
bash tests/build-entry-test.sh
bash tests/release-version-test.sh
bash tests/ensure-backup-dirs-test.sh
if grep -n '(healthy:' README.md docs/setup.md docs/restore.md; then exit 1; fi
grep -n '(healthy: exit 0)' AGENTS.md
grep -n 'com.nikolaybotev.' intent/generic-docs/plan.md
if grep -n 'GITHUB_REPOSITORY' scripts/install-tools.sh .cursor/install.sh; then exit 1; fi
if git diff --diff-filter=R --name-only HEAD | grep '^intent/'; then exit 1; fi
```

### Build notes (Phase 0)

Implemented in this pull request. No departure from the spec. `tests/release-workflow.sh` runs `tests/signing-identity-test.sh`, so the existing `macos` and `linux` jobs cover it without a new workflow step. On `fef266d`, `.cursor/install.sh` curled `OWNER/local-skills`; spec D4 sets that hardcoded URL to `nikolaybotev/local-skills` and adds no override.
