# spec.md — Release builds

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-30) |
| Status | Draft 1 |
| Stage | 2 · Design |

## 1. Summary

`backup-folder` and `drop-box-watcher` are built from one Swift package by `bash scripts/build.sh`. The `macos` job and a local build use that command. A push to `main` runs a release job named `publish`. That job signs both arm64 binaries with the self-signed identity `Nikolay Botev Code Signing`, attaches SHA-256 checksums, and publishes one GitHub release for both tools.

The first release is `0.1.0`. Later merges that do not already set a new minor or major get an automatic patch bump. One tag covers both executables. Minor and major change only when a person edits `VERSION` in a pull request.

This spec pull request adds the intent folder only. It does not add `Package.swift`, a script, or a workflow.

## 2. Goals and non-goals

**Goals**

- G1. One package and one build script produce both executables.
- G2. A merge to `main` publishes one GitHub release with both arm64 binaries and checksums.
- G3. The release job signs with `Nikolay Botev Code Signing`. A local build uses that identity when `SIGN_IDENTITY` is set, and ad-hoc signing when it is not.
- G4. `scripts/install-roger-tools.sh` installs a pinned release with `gh release download` and a checksum check.
- G5. Docs describe the one-time certificate setup, TCC, and the watcher install from a pinned release.

**Non-goals**

- A paid Apple Developer membership, Developer ID, notarization, or a Gatekeeper assessment.
- Generating a certificate, a key, a `.p12`, or a secret. Running `gh secret set`. Printing a secret value.
- Setting a real pin in the spec pull request, or before tag `v0.1.0` exists.
- Running `scripts/install-roger-tools.sh` against a home directory, `launchctl`, or any write under `~/Backups` or `~/bin`.
- A new required status check. Editing ruleset 26167970. A PAT or a bypass actor.
- Intel binaries, a Linux product build, or `swift build` on the `linux` job.
- Changing snapshot behavior or watcher behavior.
- A webhook URL, a routine key, a WireGuard key, a public IP, or a port in the repo.

**Release phasing.** Untagged requirements ship in this intent. The pin update is the last phase and waits until tag `v0.1.0` exists. The spec pull request does not start a build phase.

## 3. Principles

- P1. `bash scripts/build.sh` is the only product build. Callers do not invent a second `swiftc` line for either executable.
- P2. The release job fails closed. Missing signing secrets do not become an ad-hoc signature. A rejected version-bump push does not become a tag.
- P3. The version-bump commit does not bump again.
- P4. Checksums are taken after signing. The install script trusts the checksum file from that release, not a local rebuild.
- P5. Nikolay approves every install on Roger. A merge publishes a release. It does not install it.
- P6. The spec wins over the plan. A departure is written into the plan under that phase.

## 4. Users and scenarios

Nikolay is the only person who creates the certificate, sets the two repo secrets, and runs the installer on Roger. An agent may edit the repo. An agent does not create key material, set secrets, push a tag by hand, or run the installer.

- **S1. Local build on Roger.** He exports `SIGN_IDENTITY` as `Nikolay Botev Code Signing` and runs `bash scripts/build.sh`. The script signs with the login-keychain certificate.
- **S2. Local build without the variable.** The same command ad-hoc signs. Desktop access may be prompted again after that rebuild.
- **S3. Pull request.** The `macos` job runs `bash scripts/build.sh` with `SIGN_IDENTITY` unset. The `linux` job does not build the package. Required checks stay `macos` and `linux`.
- **S4. First merge that contains `VERSION` `0.1.0`.** No `v0.1.0` tag exists. The `publish` job releases that commit as `v0.1.0` and does not bump first.
- **S5. Later merge that leaves `VERSION` unchanged.** The job pushes one patch-bump commit, then a following run releases that version. The bump run does not release, and the release run does not bump.
- **S6. Minor or major.** A person sets `VERSION` to the new number in a pull request. The merge releases that number when its tag does not exist yet. The bot does not choose a minor or a major.
- **S7. Install.** After a later phase sets `pins.txt` to a tag that exists, Nikolay runs `bash scripts/install-roger-tools.sh`. The script downloads the assets and checks SHA-256.

## 5. Functional requirements

### 5.1 Build

FR1. `Package.swift` uses `// swift-tools-version: 6.0`. It declares executable products `backup-folder` and `drop-box-watcher` and no libraries. It does not set a platforms list.

FR2. The snapshot sources move to `Sources/backup-folder/`. `backup-folder.swift` becomes `Sources/backup-folder/main.swift` because the file has top-level code and Swift Package Manager only allows that code in `main.swift`. `Retention.swift`, `PathCheck.swift`, and `WalkPolicy.swift` move into the same directory. The watcher target's path stays `drop-box-watcher/`, which already contains `main.swift`. `.gitignore` ignores only the root binary `/backup-folder`, so `Sources/backup-folder/` is tracked. `/drop-box-watcher` stays ignored as the watcher binary, with the existing exceptions for the source directory.

FR3. `scripts/build.sh` takes no arguments. It is the product build.

- It refuses to run unless `uname` reports Darwin, with a message that the script requires macOS, and exits non-zero.
- It runs `swift build -c release --product backup-folder --product drop-box-watcher` from the repo root.
- It copies `.build/release/backup-folder` and `.build/release/drop-box-watcher` onto those names at the repo root.
- It then signs each copied binary.

FR4. Signing inside `scripts/build.sh` depends only on `SIGN_IDENTITY`.

- When `SIGN_IDENTITY` is set and non-empty, the command is `codesign --sign "$SIGN_IDENTITY" --force --options runtime` on each binary. No `--timestamp`. No notarization.
- When `SIGN_IDENTITY` is unset or empty, the command is `codesign --sign - --force` on each binary.
- The script does not read the p12, does not create a keychain, and does not print `SIGN_IDENTITY` if it looks like a secret. The value in use is a certificate common name.

FR5. The `macos` job in `.github/workflows/test.yml` runs `bash scripts/build.sh` once, with `SIGN_IDENTITY` unset, before the smoke scripts. `tests/macos-smoke.sh` and `tests/macos-watcher.sh` use the repo-root binaries and do not compile either product. A missing product binary fails the smoke and names `bash scripts/build.sh`. Test helpers `tests/clonefile-probe.swift` and `tests/hold-lock.swift` may still be compiled with `swiftc` inside the smoke. `tests/build-backup-folder.sh` is deleted once every caller uses `scripts/build.sh`. The job stays `runs-on: macos-latest` and `timeout-minutes: 5`. Its id stays `macos`.

FR6. The `linux` job does not run `swift build`, `scripts/build.sh`, or `swiftc` on `Sources/backup-folder/main.swift`. It keeps compiling `Sources/backup-folder/Retention.swift` with `tests/retention-tests.swift` and `Sources/backup-folder/PathCheck.swift` with `tests/path-tests.swift`. It does not gain a `walk-tests` step. `timeout-minutes` stays 5. The job id stays `linux`.

FR7. The CodeQL manual build step becomes `bash scripts/build.sh` with `SIGN_IDENTITY` unset. The workflow does not gain a `pull_request` trigger. The job name stays `CodeQL (Swift)`, `runs-on` stays `macos-26`, `timeout-minutes` stays 30, and the schedule stays `0 6 * * *` on push to `main`.

### 5.2 Version

FR8. `VERSION` at the repo root is one line matching `MAJOR.MINOR.PATCH` of non-negative integers, optional trailing newline, no `v` prefix, no prerelease. The file starts as `0.1.0`. The tag for a release is `v` plus that line. One tag ships both executables. The bot's only write to the file is a patch increment. A minor or major number appears only because a pull request edited the file.

FR9. `.github/workflows/release.yml` triggers on `push` to `main` only. It has no `pull_request`, no `schedule`, and no tag trigger. Its only job id is `publish`. That job has no `name` key and no `timeout-minutes` key. It is not a required check. The `macos` and `linux` jobs are not redefined there. `runs-on` is `macos-latest`. Permissions on that job are `contents: write`, `id-token: write`, and `attestations: write`. Concurrency group is `release-main` with `cancel-in-progress: false`.

FR10. `scripts/release-version.sh` is the decision the workflow calls. It prints one of `release`, `bump`, or `noop`. A bump commit is a commit whose subject is exactly `chore: bump version to X.Y.Z`, whose `X.Y.Z` equals the `VERSION` file, and whose only changed path is `VERSION`.

| Head commit | Tag `v` + VERSION | Result |
|---|---|---|
| Bump commit | Present | `noop` |
| Bump commit | Absent | `release` |
| Any other commit | Absent | `release` |
| Any other commit | Present | `bump` |

- `release` tags and publishes the current `VERSION`. It does not change the file.
- `bump` writes the next patch (`0.1.9` becomes `0.1.10`), commits it with subject `chore: bump version to ` plus the new number, and fast-forwards that commit to `main`. It does not tag and does not publish. The push is what starts the run that releases the new number.
- `noop` exits 0. It does not commit, tag, or publish.
- An ill-formed `VERSION` fails the job before a commit or a tag.
- The bump commit message does not contain a skip-ci marker.
- A second evaluation of a bump commit never increments again. That is the guard.

FR11. The `bump` push uses the job's `GITHUB_TOKEN` through the checkout credentials. It is a fast-forward. It does not force-push. If the push is rejected, the job prints `release: version-bump push to main was rejected (ruleset 26167970). No tag was created.` and exits non-zero. It does not create a tag, does not upload a release, and does not try another credential. There is no PAT and no ruleset change in this repo.

### 5.3 Sign, checksum, publish

FR12. Every `release` or `bump` run checks the signing secrets before it writes git and before it creates a keychain. `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD` must both be non-empty. A missing one prints `release: missing ` plus that secret's name and exits non-zero. The value is not printed. A `noop` run does not read them.

FR13. A `release` run signs with the identity. A `bump` run does not.

- Decode the base64 secret with `base64 --decode`, which accepts the wrapped output of macOS `base64`. The p12 file stays under the runner temp directory.
- Create a temporary keychain there. Its password is a random value generated in the job, not a repo secret and not logged.
- Import the p12 with the p12 password. Allow `codesign` to use the key with `security set-key-partition-list`. Do not run `spctl`. Do not run `add-trusted-cert` on the runner.
- Set `SIGN_IDENTITY` to `Nikolay Botev Code Signing` and run `bash scripts/build.sh`.
- Verify each binary with `codesign --verify --strict`. Do not use `spctl`. A self-signed certificate is not expected to pass a Gatekeeper assessment.
- A trap on exit always deletes the temporary keychain, restores the previous keychain search list, and deletes the p12 file. The trap runs on failure too.
- The `macos` job and the CodeQL job do not receive these secrets and do not create this keychain.

FR14. After verify, the `release` run checks `uname -m` is `arm64` and that `file` on each binary reports `arm64`. It writes `SHA256SUMS` with `shasum -a 256` of the two signed binaries, two spaces between hash and name, as `shasum` prints. The checksum file covers the signed bytes.

FR15. The `release` run still attests each binary with `actions/attest` and verifies with `gh attestation verify` using the repo, the signer workflow path of this release workflow, and `--deny-self-hosted-runners`, including the existing retry loop. Attestation is not the install check. The upload uses `softprops/action-gh-release@v2` with `tag_name` set to `v` plus `VERSION`, the target commit set to the commit that was just built, `generate_release_notes` true, and files `backup-folder`, `drop-box-watcher`, and `SHA256SUMS`. If that tag already exists, the run does not upload and does not move the tag. The `bump` result does not upload.

### 5.4 Install, pins, docs

FR16. `scripts/install-roger-tools.sh` keeps the current refusal rules: uid 0, a path component named `Backups`, an invalid tool name, and a pin that is neither `unpinned` nor `v` plus numeric components. `unpinned` skips. A real pin downloads that release asset with `gh release download` and downloads `SHA256SUMS` the same way. It checks the tool's line with `shasum -a 256 -c`. On mismatch or download failure it deletes the temp file, leaves any existing binary in `~/bin`, and exits non-zero. On success it moves the file to `~/bin/<tool>` mode `755`. It does not build from source, does not call `gh attestation verify`, `launchctl`, `sudo`, or `op`, and does not read or write `~/Backups`.

FR17. `pins.txt` stays the pin list. Both lines stay `unpinned` through the build phases that land the package, the workflow, and the installer. A later phase sets both lines to `v0.1.0` only after that tag is a published release. That phase does not run the installer. The spec pull request does not change `pins.txt`.

FR18. Docs:

- `README.md` tells a person to build with `bash scripts/build.sh` and no other compile line. Roger's local release build exports `SIGN_IDENTITY=Nikolay Botev Code Signing` first.
- A short code-signing section matches Nikolay's procedure: `/usr/bin/openssl` (LibreSSL) creates a self-signed RSA 2048 certificate whose subject is `/CN=Nikolay Botev Code Signing` and whose extended key usage is code signing, then `pkcs12` exports it. Validity in that recreation procedure is 3650 days so the documented default is not the 30-day `req -x509` default. `security import` loads the p12 into the login keychain. `security add-trusted-cert -p codeSign` trusts it for code signing. A copy of the p12 goes into 1Password. `gh secret set` reads `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD` from a pipe or a file. Temp files are deleted. The section does not contain a password, a p12 body, a secret value, or a 1Password item URI.
- The same section says Desktop access is tied to the code signature. An ad-hoc signature changes every rebuild, so a later ad-hoc build may prompt again. Builds signed with `Nikolay Botev Code Signing` keep that identity, which is why the release job uses it.
- The watcher install steps say both binaries come from `scripts/install-roger-tools.sh` once `pins.txt` names a published tag. They name `launchd/drop-box-watcher.plist.template`. They say a merge does not install on Roger, and that CI and agents do not copy binaries into `~/bin`, write the real config, or load the agent.
- `docs/setup.md` gains one `Manual:` bullet for that one-time signing setup and points the watcher LaunchAgent bullet at the template that is already in the repo. `tests/setup-docs.sh` expects 33 setup bullets and keeps every existing anchor. `docs/restore.md` stays at 7 bullets.

FR19. `AGENTS.md` names `bash scripts/build.sh` as the macOS product build, says the `linux` job does not build the package, and says a release is published by the `publish` job on a push to `main`. It does not say a `v*` tag push is the only way a release runs. It still says agents do not set a real pin, do not run the installer against Roger, and do not edit GitHub rulesets.

FR20. No phase adds a required status check. The required contexts stay `macos` and `linux`. Job id `publish` must not be added to ruleset 26167970.

## 6. Acceptance criteria

AC1. `Package.swift` lists executable products `backup-folder` and `drop-box-watcher`, and `// swift-tools-version: 6.0`. `bash scripts/build.sh` with `SIGN_IDENTITY` unset is the command in the `macos` job, in the CodeQL manual build, and in `README.md`.

AC2. On macOS, `bash scripts/build.sh` exits 0, writes both repo-root binaries, and `codesign -dv` on each shows an ad-hoc signature when `SIGN_IDENTITY` is unset. The `macos` smoke still prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. The watcher smoke still prints `macos-watcher: build OK`, `macos-watcher: notify OK`, and `macos-watcher: unchanged OK`.

AC3. `tests/macos-smoke.sh` and `tests/macos-watcher.sh` do not invoke `swiftc` on either product. `tests/build-backup-folder.sh` is gone. `.github/workflows/test.yml` still has `timeout-minutes: 5` on `macos` and on `linux`, and the `linux` job does not contain `scripts/build.sh` or `swift build`.

AC4. `.github/workflows/codeql.yml` has no `pull_request` key, schedule `0 6 * * *`, job name `CodeQL (Swift)`, `runs-on: macos-26`, and `timeout-minutes: 30`.

AC5. `bash tests/release-version-test.sh` exits 0. It covers the FR10 table, the `0.1.9` to `0.1.10` increment, an ill-formed version, a bump subject that also changes another path, and a second decision on a bump commit that does not increment again.

AC6. `bash tests/release-workflow.sh` exits 0. It requires the `publish` job, the `main` push trigger, the two secret names, `SIGN_IDENTITY`, `codesign --verify --strict`, `SHA256SUMS`, `uname -m`, and the attestation flags. It rejects a `pull_request` trigger, a `schedule` trigger, a tag trigger, a job id `macos` or `linux` inside `release.yml`, `spctl`, and `timeout-minutes` on `publish`.

AC7. `bash tests/install-roger-tools-test.sh` exits 0. A pinned install with a stub `gh` fails when the checksum does not match and succeeds when it does. The script source does not contain `gh attestation verify`.

AC8. `bash tests/no-secrets.sh` and `bash tests/setup-docs.sh` exit 0. The signing section names `Nikolay Botev Code Signing`, `MACOS_SIGNING_P12_BASE64`, and `MACOS_SIGNING_P12_PASSWORD`, and the repo contains no p12 and no password value.

AC9. `bash tests/linux-unit.sh` still prints `linux-unit: OK`. The retention and path tests still pass from the moved sources.

AC10. The spec pull request's diff is only `intent/release-builds/`. No later phase pushes a tag by hand, sets `pins.txt` to a real tag before `v0.1.0` exists, or runs the installer.

## 7. Design decisions

**D1 — VERSION file, semver, first release 0.1.0, automatic patch bump.** Nikolay closed this. Nothing has been released yet, so `0.1.0` is the first ship. One tag ships both binaries. A patch bump needs no person to classify the change. Minor and major are not automatic: a person edits `VERSION` in a pull request, and FR10 releases that value when its tag is absent instead of patch-bumping it first. The file on `main` after a release still reads as that released version. The next unchanged merge is what patch-bumps. Checked 2026-10-30: the repo has no tags and no GitHub releases.

**D2 — Identity `Nikolay Botev Code Signing`.** Nikolay replaced ad-hoc-only signing and replaced the documentation-only certificate. The release job imports `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD` into a temporary keychain, signs with that common name, verifies with `codesign --verify --strict`, and always deletes the keychain. Missing secrets fail the job. There is no ad-hoc fallback on that job. Hardened runtime is `--options runtime` with no timestamp and no notarization. `spctl` is not used, because a self-signed certificate will not pass Gatekeeper assessment. `scripts/build.sh` signs with `SIGN_IDENTITY` when it is set and otherwise uses `codesign --sign -`. Roger's local builds set `SIGN_IDENTITY` to `Nikolay Botev Code Signing`. The certificate is self-signed, RSA 2048, extended key usage code signing, created with `/usr/bin/openssl` on macOS and a LibreSSL pkcs12 export, stored in the login keychain, and trusted for `codeSign`. This draft did not generate a key, a certificate, or a p12, and it did not run `gh secret set`.

**D3 — arm64 release assets.** Checked 2026-10-30. Workflow run 41104339464 on `9ddd15a` used the `macos` job label `macos-latest` and logged image `macos-26-arm64`. GitHub's hosted-runner table lists `macos-latest` as the arm64 macOS image. The release fails if `uname -m` is not `arm64`. Intel labels exist and are not used.

**D4 — One command.** The command is `bash scripts/build.sh` with no arguments. The `macos` job, CodeQL, the release job, and a local build all use it. `SIGN_IDENTITY` is the only signing difference. The `macos` job leaves it unset, which is the same command a local ad-hoc build runs.

**D5 — Tools version 6.0.** The `macos-latest` image in run 41104339464 lists default Xcode 26.6. Apple's Xcode system requirements list that Xcode's compiler as Swift 6.3, and the Swift.org announcement for Swift 6.3.3 says Xcode 26.6 contains it. `mise.toml` pins Swift 6.4 for the Linux toolchain only. A tools version of 6.4 would be newer than the runner's compiler. Tools version 6.0 is accepted by Swift 6.3. This draft did not run `swift --version` on the runner. The image readme lists Xcode and does not print a Swift version line.

**D6 — Checksums install, attestation stays on publish.** Nikolay asked for a checksum-verified download. The install script stops calling `gh attestation verify`. The publish job still attests, because `release.yml` on `9ddd15a` already does and this intent does not remove that check. Checksums are computed after `codesign` so they match the bytes that are uploaded.

**D7 — Bump guard.** The guard is FR10. The commit the workflow pushes is classified as a bump commit, and a bump commit takes `release` or `noop`, never `bump`. A re-run after the tag exists takes `noop`. The commit message does not skip CI, so `macos` and `linux` still run on that push; those jobs do not bump the version.

**D8 — Job id `publish`.** Required checks are the contexts `macos` and `linux` from ruleset 26167970, integration id 15368. `release.yml` on `9ddd15a` uses job id `macos` and a tag trigger, so it does not run on pull requests. The new workflow runs on every push to `main`, where the `test` workflow also has a job id `macos`. A second job id `macos` would make those checks ambiguous. The release job id is `publish`. It is not added to the ruleset. No new required job is introduced.

**D9 — GITHUB_TOKEN cannot push the version-bump commit.** This is the open gate in the plan. Checked 2026-10-30 with `gh api repos/nikolaybotev/backup-folder/rulesets/26167970`. The ruleset is active, target branch, include `~DEFAULT_BRANCH`, `bypass_actors` null. Its rules are deletion, non-fast-forward, required linear history, required signatures, pull request (squash only, zero required reviews), and required status checks `linux` and `macos` with the strict policy. It is the only ruleset on the repo. A commit created by `git commit` under `GITHUB_TOKEN` is not a verified signature, so required signatures rejects it. A direct push is also not a pull request, and there is no bypass actor. This spec does not add a PAT, a GitHub App token, or a bypass. Tag creation is not covered by this ruleset: there is no tag ruleset, and the tag list was empty. This draft did not push a tag. The `actions` permissions endpoint returned 403, so the default workflow token permission was not read. The `publish` job sets `contents: write` itself. That permission is what lets the job attempt the push. It does not satisfy the ruleset.

**D10 — Pins wait for the tag.** `pins.txt` on `9ddd15a` is `backup-folder unpinned` and `drop-box-watcher unpinned`. The first real pin is `v0.1.0`, and only a phase that can see that release sets it. The spec pull request does not.

**D11 — Certificate lifetime in the doc.** The recreation steps use `-days 3650`. Nikolay did not state a lifetime. The openssl `req -x509` default is 30 days, which would rotate the identity the TCC note is trying to keep stable. This draft did not inspect his certificate.

**D12 — TCC copy.** Desktop access follows the code signature. The docs say an ad-hoc rebuild may prompt again, and that the stable identity is what the release job and Roger's `SIGN_IDENTITY` builds use. This draft did not prompt TCC on a Mac.

## 8. Open questions

None. D9 is a gate for Roger, not a choice this spec still needs from Nikolay.

## 9. Surfaces

| Surface | Owns |
|---|---|
| `Package.swift` and `scripts/build.sh` | Build both executables and sign them |
| `scripts/release-version.sh` | `release`, `bump`, or `noop` |
| Job `publish` | Keychain, verify, checksums, attestation, tag, GitHub release |
| `scripts/install-roger-tools.sh` and `pins.txt` | Download a pinned release and check SHA-256 |
| `README.md` and `docs/setup.md` | One-time certificate steps, TCC, watcher install |
| Ruleset 26167970 | Stays as Roger set it. This repo does not edit it |

## 10. What was checked

Checked 2026-10-30 against `main` at `9ddd15ad4f41c4b84cf0ac09ed59c4e4dcf0cd49`:

- `.github/workflows/release.yml` triggers on tags `v*`, job id `macos`, `runs-on: macos-latest`, builds `backup-folder` with `tests/build-backup-folder.sh` and `drop-box-watcher` with a `swiftc` file list, attests both, verifies with `gh attestation verify`, and uploads the two binaries. It does not sign, does not write a checksum, and has no `timeout-minutes`.
- `.github/workflows/test.yml` jobs `macos` and `linux` each set `timeout-minutes: 5`. The `linux` job compiles the retention tests and the path tests. It does not compile `walk-tests`. `AGENTS.md` at that commit says the `linux` job compiles `walk-tests`. The workflow file is the one this spec follows.
- `.github/workflows/codeql.yml` has no `pull_request` key. It pushes on `main` and schedules `0 6 * * *`. Job name `CodeQL (Swift)`, `runs-on: macos-26`, `timeout-minutes: 30`. The manual build calls `tests/build-backup-folder.sh` and a `swiftc` file list.
- `scripts/install-roger-tools.sh` downloads with `gh release download` and verifies with `gh attestation verify`. It does not check a checksum. `pins.txt` lists both tools as `unpinned`.
- `tests/build-backup-folder.sh` symlinks `backup-folder.swift` to `main.swift` beside the three other snapshot sources because top-level code has to live in `main.swift`.
- `README.md` still shows a one-file `swiftc` build and says Nikolay pushes a `v*` tag. `docs/setup.md` still says the watcher plist is not in the repo. `launchd/drop-box-watcher.plist.template` is on `main`.
- `tests/setup-docs.sh` requires 32 `Manual:` or `Script:` bullets in `docs/setup.md` and 7 in `docs/restore.md`. `tests/no-secrets.sh` scans `intent/`.
- `.gitignore` ignores the path name `backup-folder` in any directory and ignores `/drop-box-watcher` with exceptions for the source tree.
- Ruleset 26167970, as recorded in D9. Tag count 0. No releases. Actions permissions request returned 403.
- Runner architecture, as recorded in D3, from run 41104339464 and from GitHub's hosted-runner documentation.
- Xcode 26.6 on that image readme, and the Swift 6.3 compiler figures in D5.

This draft did not create a certificate, did not run `gh secret set`, did not push a tag, and did not run the installer.
