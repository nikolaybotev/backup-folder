# plan.md — Release builds

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

The pull request that adds this folder does not start these phases. A phase starts only when someone says to build. One phase is one pull request, opened ready for review. The build agent does not merge. It does not push a tag, does not set a real pin, does not run `scripts/install-roger-tools.sh`, and does not create a certificate or a secret.

No phase edits ruleset 26167970. No phase adds a PAT, a GitHub App token, or a bypass. No phase adds a required status check. Job id `publish` stays off the ruleset.

## Stops

**Version-bump push (D9).** `GITHUB_TOKEN` cannot push the patch-bump commit onto `main`. Ruleset 26167970 requires a verified signature and a pull request, `bypass_actors` is null, and a `git commit` from Actions is not a verified signature. The `publish` job still attempts that fast-forward with its own `contents: write` token. When the ruleset rejects it, the job exits non-zero with the FR11 message and does not create a tag.

The first release does not take that path. A `VERSION` of `0.1.0` with no `v0.1.0` tag is a `release` result, which creates a tag and a GitHub release without a new commit. Every later automatic patch does push a commit, and that push stays blocked until Roger makes it possible. This plan does not choose how.

A missing signing secret is not this stop. FR12 fails that run before a git write. Nikolay and Roger set the two secrets from the Mac.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `bash tests/build-entry-test.sh` | 0 |
| AC2 | `macos` job: `bash scripts/build.sh` then the two smokes | 0 |
| AC3 | `bash tests/build-entry-test.sh` | 0 |
| AC4 | `bash tests/build-entry-test.sh` | 0 |
| AC5 | `bash tests/release-version-test.sh` | 1 |
| AC6 | `bash tests/release-workflow.sh` | 1 |
| AC7 | `bash tests/install-roger-tools-test.sh` | 2 |
| AC8 | `bash tests/no-secrets.sh` and `bash tests/setup-docs.sh` | 2 |
| AC9 | `bash tests/linux-unit.sh` and the retention and path tests | 0 |
| AC10 | Diff of the spec pull request is only `intent/release-builds/` | this folder |

## Phase 0 — Package and build script

Files: `Package.swift`, `Sources/backup-folder/main.swift`, `Sources/backup-folder/Retention.swift`, `Sources/backup-folder/PathCheck.swift`, `Sources/backup-folder/WalkPolicy.swift`, `scripts/build.sh`, `.gitignore`, `.github/workflows/test.yml`, `.github/workflows/codeql.yml`, `.github/workflows/release.yml`, `tests/macos-smoke.sh`, `tests/macos-watcher.sh`, `tests/build-entry-test.sh`, `AGENTS.md`, `README.md`. Delete `backup-folder.swift`, `Retention.swift`, `PathCheck.swift`, `WalkPolicy.swift`, and `tests/build-backup-folder.sh` from the repo root.

1. Add `Package.swift` as FR1. Move the snapshot sources as FR2. `main.swift` is the old `backup-folder.swift` contents. Change the gitignore entry `backup-folder` to `/backup-folder` so only the root binary is ignored.
2. Add `scripts/build.sh` as FR3 and FR4. `chmod +x` it. Darwin check first. `SIGN_IDENTITY` unset means `codesign --sign - --force`. A set value means `codesign --sign "$SIGN_IDENTITY" --force --options runtime`.
3. Point the `macos` job at `bash scripts/build.sh` before the smokes, with `SIGN_IDENTITY` unset. Leave `timeout-minutes: 5` and `runs-on: macos-latest`. The next step runs `codesign -dv` on each repo-root binary and fails unless the output contains `Signature=adhoc`. Update both smokes so they do not compile `backup-folder` or `drop-box-watcher`. They fail with the build-script name if a binary is missing. Leave the `swiftc` lines for `clonefile-probe` and `hold-lock`.
4. Point the `linux` compile lines at `Sources/backup-folder/Retention.swift` and `Sources/backup-folder/PathCheck.swift`. Do not add `walk-tests`. Do not run `swift build` or `scripts/build.sh`. Leave `timeout-minutes: 5`.
5. Replace the CodeQL manual build with `bash scripts/build.sh`. Change nothing else in that workflow.
6. Replace the two compile steps in `release.yml` with `bash scripts/build.sh`. Leave the tag trigger, the job id `macos`, attestation, and the upload until Phase 1. `SIGN_IDENTITY` stays unset on that temporary step.
7. Add `tests/build-entry-test.sh`. It greps the files for AC1, AC3, and AC4 and exits non-zero on a miss. It does not compile. Run it from the `macos` job and the `linux` job.
8. Update `AGENTS.md` and the `README.md` build section to `bash scripts/build.sh`. The build section says a set `SIGN_IDENTITY` selects the certificate and an unset variable is ad-hoc. The openssl procedure, TCC paragraph, and watcher install rewrite wait for Phase 2. When rewriting the `linux` sentence, list the retention and path compiles that `test.yml` actually runs. Do not claim that `walk-tests` runs.

DoD: `bash tests/build-entry-test.sh` and `bash tests/linux-unit.sh` exit 0 on Linux, and the retention and path binaries pass from the new paths. The phase is done when the pull request's `macos` and `linux` checks are green.

## Phase 1 — Version and publish job

Files: `VERSION`, `scripts/release-version.sh`, `tests/release-version-test.sh`, `tests/release-workflow.sh`, `.github/workflows/release.yml`, `.github/workflows/test.yml`, `AGENTS.md`.

1. Add `VERSION` containing `0.1.0` and a newline.
2. Add `scripts/release-version.sh` with the FR10 table and the patch increment. Add `tests/release-version-test.sh` for AC5, using a temporary git repo. No network and no push.
3. Replace `release.yml` with the FR9 workflow. Job id `publish` only. Call `scripts/release-version.sh`. Implement FR11, FR12, FR13, FR14, and FR15. The keychain trap runs on failure. Secret values are not echoed. `base64 --decode` reads the p12 secret. `SIGN_IDENTITY` is `Nikolay Botev Code Signing` only in the `release` branch, and only for the `bash scripts/build.sh` step.
4. Rewrite `tests/release-workflow.sh` for AC6. Match the job id under `jobs:`, not the substring `macos` inside `macos-latest`. Keep the attestation assertions. Drop the assertions that require a tag trigger and that forbid every `branches:` key.
5. Run `tests/release-version-test.sh` and `tests/release-workflow.sh` from the `macos` and `linux` jobs. Do not change their timeouts.
6. Update the `AGENTS.md` release sentence so it describes the `publish` job on a push to `main`.

The pull request does not push a tag and does not set the secrets. After it is on `main`, the `publish` run is the first-release path (D1, S4). If the signing secrets are absent, that run fails with the FR12 line and uploads nothing.

DoD: `bash tests/release-version-test.sh` and `bash tests/release-workflow.sh` exit 0. `bash tests/linux-unit.sh` still prints `linux-unit: OK`.

## Phase 2 — Install script and docs

Files: `scripts/install-roger-tools.sh`, `tests/install-roger-tools-test.sh`, `README.md`, `docs/setup.md`, `tests/setup-docs.sh`, `AGENTS.md`.

1. Change the installer to FR16. The stub `gh` in the test must serve `SHA256SUMS` and the binary. A wrong hash exits non-zero and leaves `~/bin` unchanged. Remove the attestation strings from the script and from the test's required source checks.
2. Add the README code-signing section from FR18, including the TCC paragraph and `-days 3650`. Commands read the password and the p12 from files. They do not echo them. No 1Password item URI.
3. Point the watcher install steps at `scripts/install-roger-tools.sh`, `pins.txt`, and `launchd/drop-box-watcher.plist.template`. Say that a merge does not install on Roger.
4. Add one `Manual:` bullet to `docs/setup.md` for that section. Update the watcher LaunchAgent bullet so it names the template in the repo. Set the setup bullet count in `tests/setup-docs.sh` from 32 to 33. Keep the restore count at 7 and keep every existing anchor. Add the anchor `Nikolay Botev Code Signing`.

`pins.txt` stays `unpinned` on both lines.

DoD: `bash tests/install-roger-tools-test.sh`, `bash tests/no-secrets.sh`, and `bash tests/setup-docs.sh` exit 0.

## Phase 3 — Pin the first release

Files: `pins.txt`.

This phase does not start until `gh release view v0.1.0 --repo nikolaybotev/backup-folder` succeeds. Then set both lines to `v0.1.0`. Do not run the installer. Do not write under `~/bin` or `~/Backups`.

The pull request body lists the steps Nikolay runs, and nobody else:

1. Finish the README code-signing section once: openssl, `security import`, `add-trusted-cert -p codeSign`, a copy in 1Password, `gh secret set` from a pipe or a file, then delete the temp files.
2. `export SIGN_IDENTITY="Nikolay Botev Code Signing"` and `bash scripts/build.sh` for a local build. Omit the variable for an ad-hoc build.
3. After this pin is on `main`, `bash scripts/install-roger-tools.sh` downloads `v0.1.0` and checks `SHA256SUMS`.

DoD: `pins.txt` contains `backup-folder v0.1.0` and `drop-box-watcher v0.1.0`, and `bash tests/install-roger-tools-test.sh` still exits 0 against a fixture. The unpinned skip case stays in that test.

### After the first publish

The coordinating note that follows a green `publish` run for `v0.1.0` includes those three steps. It does not claim later patch releases work while the D9 stop is open. It does not say the installer was run.
