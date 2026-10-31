# spec.md — Signing identity

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-31) |
| Status | Draft 1 |
| Stage | 2 · Design |

Where the first prompt and the later corrections disagree, the later correction wins. The cloud-install boundary is the last of those.

## 1. Summary

The release job signs with the signing identity. That identity is `SIGN_IDENTITY` when the variable is set, and otherwise the single codesigning identity on the certificate imported from `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD`. A missing identity fails the release. A local build with `SIGN_IDENTITY` unset stays ad-hoc.

LaunchAgent labels for `backup.NAME` and `drop-box-watcher` use the prefix `com.nikolaybotev.`. The open label note in [intent/generic-docs/plan.md](../generic-docs/plan.md) is closed.

Prose about this repo says "this repo". Distribution entry points may name the canonical repository. This repo's workflows may use `${{ github.repository }}`. Human-facing docs do not spell out the obvious. Agent-facing files keep explicit expectations.

## 2. Goals and non-goals

**Goals**

- G1. Remove every certificate subject. Releases still sign with the certificate from the existing signing secrets.
- G2. Rename the two LaunchAgent prefixes in templates, tests, and docs, and close the open decision in `intent/generic-docs/plan.md`.
- G3. Apply the three writing rules and add them to `REVIEW.md`.

**Non-goals**

- Notarization, `spctl`, a new secret, or a second `codesign --verify --strict` block.
- Renaming historical intent folders, or rewriting their LaunchAgent label strings.
- Changing `scripts/build.sh` ad-hoc behavior when `SIGN_IDENTITY` is unset.
- Reading `GITHUB_REPOSITORY` inside `scripts/install-tools.sh` or `.cursor/install.sh`.
- Merging this pull request, installing anything, or editing rulesets.

**Release phasing.** All untagged requirements are this change.

## 3. Principles

- P1. The spec wins over the plan. A departure is recorded in `plan.md` in the same change.
- P2. Name settings. Do not copy their current values.
- P3. A fork of this repo's own workflow can publish with `${{ github.repository }}`. An installer still defaults to the canonical repository unless `GH_REPO` is set.

## 4. Users and scenarios

- **S1. Release.** Job `publish` imports the p12 into a temporary keychain. `SIGN_IDENTITY` is unset. The job reads the codesigning identity from that keychain, exports it, and `scripts/build.sh` signs both binaries. `codesign --verify --strict` still runs on both.
- **S2. Release with `SIGN_IDENTITY` set.** The job uses that value and does not parse `security find-identity` output.
- **S3. Missing identity.** The matching-identities section has zero quoted names, or more than one, and `SIGN_IDENTITY` is unset. The job exits non-zero before `scripts/build.sh`.
- **S4. Local build.** `SIGN_IDENTITY` unset. `scripts/build.sh` ad-hoc signs. `SIGN_IDENTITY` set. The script signs with that value.
- **S5. Install.** `scripts/install-tools.sh` with `GH_REPO` unset downloads and verifies against its default repository. With `GH_REPO` set, both the download and the verify use that value. The script does not read `GITHUB_REPOSITORY`.
- **S6. Docs.** A reader of the README and `docs/setup.md` sees the signing identity and the `com.nikolaybotev.` labels, and is not told to set an environment variable before installing.

## 5. Functional requirements

FR1. `.github/workflows/release.yml` does not assign a quoted literal to `SIGN_IDENTITY`. After the p12 import, when `SIGN_IDENTITY` is unset, the job runs `security find-identity -p codesigning` on that keychain only and pipes the text to `bash scripts/signing-identity.sh`. It does not pass `-v`. When `SIGN_IDENTITY` is set, it keeps that value. If the identity is empty or the helper exits non-zero, the job fails with `release: missing signing identity`. It then exports `SIGN_IDENTITY` and `VERSION` and runs `bash scripts/build.sh` once, still before `codesign --verify --strict`.

FR2. `scripts/signing-identity.sh` prints `SIGN_IDENTITY` and exits 0 when that variable is non-empty. Otherwise it reads find-identity text on stdin and prints the single double-quoted name from the matching-identities section. Names under `Valid identities only` do not count, so one certificate is one identity whether or not it is trusted. Zero names or more than one in that section exit non-zero and print `signing-identity: missing signing identity`. The helper does not call `security` and does not read `GITHUB_REPOSITORY`.

FR3. `scripts/build.sh` stays as it is: `codesign --sign "$SIGN_IDENTITY" --force --options runtime` when `SIGN_IDENTITY` is set, and `codesign --sign - --force` when it is unset. It does not name a certificate subject.

FR4. The certificate subject is not written anywhere in the repo, including examples, tests, and intent files. Docs name `SIGN_IDENTITY`, `MACOS_SIGNING_P12_BASE64`, and `MACOS_SIGNING_P12_PASSWORD`. Wording inside a verbatim prompt block is not a reason to keep the subject.

FR5. These strings replace `com.nikolay.backup.NAME` and `com.nikolay.drop-box-watcher` in the plist templates, the tests that lock them, `README.md`, `docs/setup.md`, and `AGENTS.md`:

- `com.nikolaybotev.backup.NAME`
- `com.nikolaybotev.drop-box-watcher`

The README steps that name the watcher plist file use `com.nikolaybotev.drop-box-watcher.plist`. `intent/generic-docs/plan.md` closes its open label decision by pointing at this change and the prefix `com.nikolaybotev.`. Historical intent folders keep their folder names and their historical `com.nikolay.` label strings.

FR6. `REVIEW.md` gains three review items, checked on the compliance pass:

1. Prose about this repo says "this repo". `.cursor/install.sh` is only for setting up Cursor Cloud Agent environments, never GitHub Actions or anything else. It hardcodes `nikolaybotev/local-skills` with no override and no environment variable. A fork override belongs only on this repo's own distribution entry points (its installer and release install commands), and only where it is cheap. Do not derive a repository identity from `GITHUB_REPOSITORY` in code that other repositories' CI may run. This repo's own workflows may use `${{ github.repository }}`. Install instructions do not depend on an environment variable the reader must set. Wording inside a verbatim prompt block stays out of scope.
2. Docs, tests, and workflows name the setting (environment variable, secret, or config key). They do not copy its current value. Tests assert behavior against the configured value.
3. README and user and setup docs do not spell out what a competent reader already knows. Agent-facing files keep explicit expectations such as "(healthy: exit 0)". That includes `AGENTS.md`, `REVIEW.md`, skills, and intents written for agents.

FR7. Prose that names this repo's owner, name, or URL says "this repo", outside verbatim prompt blocks and outside distribution entry points. `scripts/install-tools.sh` keeps a default `GH_REPO` of the canonical repository. `gh release download` and `gh attestation verify` both use `$GH_REPO` (`--repo` and `--signer-workflow`). The script does not read `GITHUB_REPOSITORY`. `.github/workflows/release.yml` attestation flags use `${{ github.repository }}`. `docs/setup.md` still tells the reader to run `scripts/install-tools.sh` without setting `GH_REPO`. `.cursor/install.sh` hardcodes `https://raw.githubusercontent.com/nikolaybotev/local-skills/main/install.sh`, with no override and no environment variable. It is Cursor Cloud Agent environment setup only, not GitHub Actions.

FR8. `tests/signing-identity-test.sh` drives FR2 with a `SIGN_IDENTITY` the test sets and with fixture find-identity text the test writes. It does not contain a certificate subject. `tests/release-workflow.sh` requires the FR1 strings, rejects a quoted `SIGN_IDENTITY` assignment, requires both attestation flags from FR7, and runs `tests/signing-identity-test.sh`. `tests/install-tools-test.sh` reads the installer's default repository from the script and checks that an unset `GH_REPO` uses it, and that a `GH_REPO` the test sets is what download and verify pass. The test does not contain the canonical owner or name as a literal expectation.

FR9. Human-facing docs lose the certificate subject and do not gain "(healthy: …)" notes. `AGENTS.md` keeps its existing "(healthy: …)" lines. The release bullet says the job signs with the signing identity from `SIGN_IDENTITY` or from the imported certificate, and that a missing identity fails the job.

## 6. Acceptance criteria

AC1. `bash tests/signing-identity-test.sh` exits 0. `bash tests/release-workflow.sh` exits 0. The release workflow contains `security find-identity -p codesigning`, `scripts/signing-identity.sh`, `release: missing signing identity`, and `${{ github.repository }}` on both attestation verifies. It does not pass `-v` to `find-identity` and does not assign `SIGN_IDENTITY` a quoted literal.

AC2. `bash tests/install-tools-test.sh` exits 0. `scripts/install-tools.sh` contains no `GITHUB_REPOSITORY`. Download and verify use `$GH_REPO`.

AC3. `bash tests/setup-docs.sh` and `bash tests/no-secrets.sh` exit 0. The backup template label is `com.nikolaybotev.backup.NAME`. The watcher template label is `com.nikolaybotev.drop-box-watcher`. `bash tests/linux-unit.sh` exits 0.

AC4. `README.md`, `docs/setup.md`, and `docs/restore.md` contain no `(healthy:` notes. `AGENTS.md` still contains `(healthy: exit 0)`.

AC5. `intent/generic-docs/plan.md` records the label prefix decision closed with `com.nikolaybotev.`. No historical intent directory is renamed.

## 7. Design decisions

**D1 — Identity comes from the variable or the imported certificate.** Checked `origin/main` at `fef266d`: `.github/workflows/release.yml` assigns `SIGN_IDENTITY` a quoted literal, then runs `bash scripts/build.sh` once. `scripts/build.sh` signs with `"$SIGN_IDENTITY"` when the variable is set and with `codesign --sign -` when it is unset. This change deletes the literal. The job keeps importing `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD` into the temporary keychain. When `SIGN_IDENTITY` is unset it asks that keychain only, with `security find-identity -p codesigning`, and keeps the single quoted name from the matching-identities section. `-v` asks only for identities that pass trust evaluation. This job imports the p12 and does not trust it, so a self-signed certificate is absent from the valid-identities section and the release would exit before `scripts/build.sh`. Without `-v`, that certificate is one quoted name under Matching identities. The same name also appears under Valid identities only when the certificate is trusted; the parser ignores that section, so one certificate is still one identity. This environment has no `security` command, so the parser is tested against that text shape, not against a live keychain. Zero names or more than one in the matching-identities section fail the release before the build. What was rejected: hardcoding the subject, passing `-v`, counting every quoted name in the whole listing, and searching the login keychain, which can see a different identity.

**D2 — Labels use `com.nikolaybotev.`.** The open note is the last paragraph of `intent/generic-docs/plan.md` on `fef266d`. It left the prefix for a later decision. This change picks `com.nikolaybotev.` for `backup.NAME` and `drop-box-watcher` in the templates, tests, and docs, and closes that paragraph. Historical intent folders stay put, and their old label strings stay as the record of those changes. What was rejected: a prefix that hides the publisher, and editing every historical intent's label.

**D3 — Writing rules, as corrected.** Rule 1: prose says "this repo". `.cursor/install.sh` hardcodes `nikolaybotev/local-skills` for Cursor Cloud Agent environments only, with no override and no environment variable. A fork override belongs only on this repo's installer and release install commands, and only where it is cheap: `GH_REPO` on `scripts/install-tools.sh`. Do not read `GITHUB_REPOSITORY` in code other repositories' CI may run. This repo's workflows may use `${{ github.repository }}`. Install instructions do not require an environment variable. Rule 2: name the setting; tests assert the configured value. Rule 3 applies only to the README and `docs/setup.md` and `docs/restore.md`. `AGENTS.md` keeps `(healthy: …)`. Verbatim prompt blocks stay quotations, including a repository URL, and stay out of the review item. They do not keep a certificate subject (FR4). What was rejected: deriving every repository reference from `GITHUB_REPOSITORY`, adding a fork override to `.cursor/install.sh`, and stripping healthy-line notes from agent files.

**D4 — Installer default stays canonical.** Checked `scripts/install-tools.sh` on `fef266d`: `GH_REPO` defaults to the canonical repository and `gh release download` uses `$GH_REPO`, but `gh attestation verify` repeats a fixed `--repo` and `--signer-workflow`. This change points both flags at `$GH_REPO`. The default assignment stays, so `docs/setup.md` can keep "run `scripts/install-tools.sh`" with no `GH_REPO` step. Checked `.cursor/install.sh` on `fef266d`: it curls a fixed local-skills install script and reads no repository variable. This change sets that URL to `https://raw.githubusercontent.com/nikolaybotev/local-skills/main/install.sh` and does not add an override. What was rejected: making either script follow `GITHUB_REPOSITORY`.

## 8. Open questions

None.
