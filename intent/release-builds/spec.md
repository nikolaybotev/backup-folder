# spec.md — Release builds

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-30) |
| Status | Draft 4 |
| Stage | 2 · Design |

## 1. Summary

`backup-folder` and `drop-box-watcher` are built from one Swift package by `bash scripts/build.sh`. The `macos` job and a local build use that command. A push to `main` runs a release job named `publish`. That job signs both arm64 binaries with the self-signed identity `Nikolay Botev Code Signing`, attaches SHA-256 checksums, and publishes one GitHub release for both tools.

There is no `VERSION` file. The release workflow does not push commits to `main`. It tags the merge commit and publishes that tag in the same run. With no tag in the repo yet, the baseline is `v0.1.0`, and the first publish is the bump of that baseline (`v0.1.1` when the pull request has no release label). One tag covers both executables. The `macos` job and the CodeQL manual build export `VERSION=v0.0.0`. The release job sets `VERSION` to the tag it is publishing. `scripts/build.sh` does not invent `0.0.0`.

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
- Setting a real pin in the spec pull request, or before the first published tag exists.
- Running `scripts/install-roger-tools.sh` against a home directory, `launchctl`, or any write under `~/Backups` or `~/bin`.
- A new required status check. Editing ruleset 26167970. A PAT or a bypass actor.
- Intel binaries, a Linux product build, or `swift build` on the `linux` job.
- Changing snapshot behavior or watcher behavior.
- A webhook URL, a routine key, a WireGuard key, a public IP, or a port in the repo.

**Release phasing.** Untagged requirements ship in this intent. The pin update is the last phase and waits until the first published tag exists. The spec pull request does not start a build phase.

## 3. Principles

- P1. `bash scripts/build.sh` is the only product build. Callers do not invent a second `swiftc` line for either executable.
- P2. The release job fails closed. Missing signing secrets do not become an ad-hoc signature. The job does not push a commit to `main`.
- P3. A tag pushed with `GITHUB_TOKEN` does not start another workflow. A commit that already has a semver tag is not given a second one.
- P4. Checksums are taken after signing. The install script trusts the checksum file from that release, not a local rebuild.
- P5. Nikolay approves every install on Roger. A merge publishes a release. It does not install it.
- P6. The spec wins over the plan. A departure is written into the plan under that phase.

## 4. Users and scenarios

Nikolay is the only person who creates the certificate, sets the two repo secrets, and runs the installer on Roger. An agent may edit the repo. An agent does not create key material, set secrets, push a tag by hand, or run the installer.

- **S1. Local build on Roger.** He exports `SIGN_IDENTITY` as `Nikolay Botev Code Signing` and runs `bash scripts/build.sh`. The script signs with the login-keychain certificate.
- **S2. Local build without the variable.** The same command ad-hoc signs. Desktop access may be prompted again after that rebuild.
- **S3. Pull request.** The `macos` job exports `VERSION=v0.0.0` and runs `bash scripts/build.sh` with `SIGN_IDENTITY` unset. The `linux` job does not build the package. Required checks stay `macos` and `linux`.
- **S4. First publish.** No semver tag exists. The baseline is `v0.1.0`. The merged pull request has no release label, so the job tags that commit `v0.1.1` and publishes the release in the same run. It does not push a commit.
- **S5. Later merge, no label.** The latest tag is `v0.1.1`. The job tags `v0.1.2` and publishes it in that same run.
- **S6. Minor or major.** The merged pull request carries `release:minor` or `release:major`. The job bumps that component and publishes the new tag in the same run. It does not choose a minor or a major on its own.
- **S7. Install.** After a later phase sets `pins.txt` to a tag that exists, Nikolay runs `bash scripts/install-roger-tools.sh`. The script downloads the assets and checks SHA-256.

## 5. Functional requirements

### 5.1 Build

FR1. `Package.swift` uses `// swift-tools-version: 6.0`. It declares executable products `backup-folder` and `drop-box-watcher`, and one library target `BuildStamp` that both executables depend on. It does not set a platforms list.

FR2. The snapshot sources move to `Sources/backup-folder/`. `backup-folder.swift` becomes `Sources/backup-folder/main.swift` because the file has top-level code and Swift Package Manager only allows that code in `main.swift`. `Retention.swift`, `PathCheck.swift`, and `WalkPolicy.swift` move into the same directory. The watcher target's path stays `drop-box-watcher/`, which already contains `main.swift`. `.gitignore` ignores only the root binary `/backup-folder`, so `Sources/backup-folder/` is tracked. `/drop-box-watcher` stays ignored as the watcher binary, with the existing exceptions for the source directory.

FR3. `scripts/build.sh` takes no arguments. It is the product build.

- It refuses to run unless `uname` reports Darwin, with a message that the script requires macOS, and exits non-zero.
- It writes `Sources/BuildStamp/BuildStamp.swift` before the compile. That file is gitignored. It holds the version, the full commit SHA from `git rev-parse HEAD`, and the UTC timestamp from `date -u +%Y-%m-%dT%H:%MZ`. CI and a local build use those same two commands. The version is the `VERSION` environment variable when that variable is set and non-empty. Otherwise it is the stdout of `git describe --tags --dirty`. If `git rev-parse HEAD` fails, or `VERSION` is unset and that describe command fails, the script exits non-zero. The script does not invent `0.0.0` or any other version.
- `--version` prints one line and exits 0: the product name, the version, the first 7 characters of the full SHA, and the timestamp. The shape is `backup-folder v0.1.2 (abc1234, built 2026-10-30T18:52Z)`. `drop-box-watcher` uses its own product name and the same parenthetical. `--version --verbose`, in either order, prints the same line with the full SHA in place of the 7 characters. `backup-folder` checks these flags before the two-path usage check. `drop-box-watcher` checks them before the config-path check.
- A release tag stays `vMAJOR.MINOR.PATCH` with no SHA and no timestamp in the tag. The release job sets `VERSION` to that plain tag, so the binaries it ships do not use a `git describe` suffix.
- It runs one `swift build -c release` from the repo root, with no `--product` filter. On Swift 6.3 and on Swift 6.4.1, `swift build -c release --product A --product B` builds only the last product, so this script does not pass `--product`. The unfiltered release build produces both executables.
- It copies `.build/release/backup-folder` and `.build/release/drop-box-watcher` onto those names at the repo root.
- It then signs each copied binary.

FR4. Signing inside `scripts/build.sh` depends only on `SIGN_IDENTITY`.

- When `SIGN_IDENTITY` is set and non-empty, the command is `codesign --sign "$SIGN_IDENTITY" --force --options runtime` on each binary. No `--timestamp`. No notarization.
- When `SIGN_IDENTITY` is unset or empty, the command is `codesign --sign - --force` on each binary.
- The script does not read the p12, does not create a keychain, and does not print `SIGN_IDENTITY` if it looks like a secret. The value in use is a certificate common name.

FR5. The `macos` job in `.github/workflows/test.yml` exports `VERSION=v0.0.0` and runs `bash scripts/build.sh` once, with `SIGN_IDENTITY` unset, before the smoke scripts. That checkout stays at the `actions/checkout` default depth of 1 and does not fetch tags. `git describe --tags` cannot see a tag there: the repo has no tags yet, and depth 1 does not fetch tags. The script still exits non-zero when it cannot determine a version, and it still does not invent `0.0.0`. The job supplies `VERSION` so the build has one. `tests/macos-smoke.sh` and `tests/macos-watcher.sh` use the repo-root binaries and do not compile either product. A missing product binary fails the smoke and names `bash scripts/build.sh`. Test helpers `tests/clonefile-probe.swift` and `tests/hold-lock.swift` may still be compiled with `swiftc` inside the smoke. `tests/build-backup-folder.sh` is deleted once every caller uses `scripts/build.sh`. The job stays `runs-on: macos-latest` and `timeout-minutes: 5`. Its id stays `macos`.

FR6. The `linux` job does not run `swift build`, `scripts/build.sh`, or `swiftc` on `Sources/backup-folder/main.swift`. It keeps compiling `Sources/backup-folder/Retention.swift` with `tests/retention-tests.swift` and `Sources/backup-folder/PathCheck.swift` with `tests/path-tests.swift`. It does not gain a `walk-tests` step. `timeout-minutes` stays 5. The job id stays `linux`.

FR7. The CodeQL manual build step exports `VERSION=v0.0.0` and runs `bash scripts/build.sh` with `SIGN_IDENTITY` unset. That checkout stays at the `actions/checkout` default depth of 1 and does not fetch tags, for the same reason as FR5. The script still does not invent `0.0.0`. The workflow does not gain a `pull_request` trigger. The job name stays `CodeQL (Swift)`, `runs-on` stays `macos-26`, `timeout-minutes` stays 30, and the schedule stays `0 6 * * *` on push to `main`.

### 5.2 Version

FR8. There is no `VERSION` file. The version of a release is a lightweight git tag matching `vMAJOR.MINOR.PATCH`. One tag ships both executables. The workflow never creates a commit and never pushes a branch.

FR9. `.github/workflows/release.yml` triggers on `push` to `main` only. It has no `pull_request`, no `schedule`, and no tag trigger. Checkout fetches tags (`fetch-depth: 0`). Its only job id is `publish`. That job has no `name` key and no `timeout-minutes` key. It is not a required check. The `macos` and `linux` jobs are not redefined there. `runs-on` is `macos-latest`. Permissions on that job are `contents: write`, `id-token: write`, `attestations: write`, and `pull-requests: read`. `pull-requests: read` is what lets the token read labels. Without it the label lookup cannot succeed. Concurrency group is `release-main` with `cancel-in-progress: false`.

FR10. `scripts/release-version.sh` is the decision the workflow calls. It prints `tag <name>` or `noop`.

- The latest tag is the greatest semver among tags matching `vMAJOR.MINOR.PATCH`. Tags that do not match are ignored. When none match, the baseline is `v0.1.0`. That baseline is not created as a tag.
- The next version is a patch bump of that latest tag or baseline. `v0.1.9` becomes `v0.1.10`. `v0.1.0` becomes `v0.1.1`.
- When the merged pull request has label `release:minor`, the next version bumps minor and sets patch to 0. `v0.1.3` becomes `v0.2.0`.
- When it has label `release:major`, the next version bumps major and sets minor and patch to 0. `v0.2.4` becomes `v1.0.0`.
- When it has both labels, the script exits non-zero and prints `release: both release:minor and release:major are set`. The workflow does not create a tag.
- The repository does not have labels `release:minor` and `release:major`. Checked 2026-10-30 with `gh label list`: the list is the ten default GitHub labels. This intent adds those two repository labels. Adding them is not a ruleset change.
- The pull request number is the `(#N)` at the end of the squash subject. Commits on `main` use that shape, including `9ddd15a`. The script reads that pull request's labels. The `publish` token can read them because the job sets `pull-requests: read`. If the subject has no `(#N)`, or the label lookup fails, the script exits non-zero and the job fails. A failed lookup is not treated as no label, and the job does not publish a patch for that failure. A successful read that finds neither label is a patch bump.
- If `HEAD` already has a semver tag, the result is `noop`. A second run on that commit does not compute a new version.

FR11. The only git write is a lightweight tag. The job pushes `refs/tags/<next>` with `GITHUB_TOKEN`. It does not run `git commit`, does not push `main` or any other branch, does not force-push, and does not move a tag that already exists. If the computed name already points at a different commit, the job fails and leaves that tag where it is. A tag push made with `GITHUB_TOKEN` does not start another workflow run. The release is uploaded in this same run for that reason. The workflow also has no tag trigger, so a tag push would not select it even from another token.

### 5.3 Sign, checksum, publish

FR12. Every `publish` run checks the signing secrets before it creates a keychain, before it builds, and before it pushes a tag. The check runs on a run that does not create a tag, including a `noop` whose GitHub release already exists. `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD` must both be non-empty. A missing one prints `release: missing ` plus that secret's name and exits non-zero. The value is not printed.

FR13. A `publish` run that builds sets `SIGN_IDENTITY` to `Nikolay Botev Code Signing` and sets `VERSION` to the plain tag it is publishing, then runs `bash scripts/build.sh` once. The tag it is publishing is the tag it is about to push, or the semver tag already on `HEAD` when that tag's GitHub release is missing. The job does not run the script once without that identity and again with it. The release build is not ad-hoc. A `noop` whose GitHub release already exists does not build.

- Decode the base64 secret with `base64 --decode`, which accepts the wrapped output of macOS `base64`. The p12 file stays under the runner temp directory.
- Create a temporary keychain there. Its password is a random value generated in the job, not a repo secret and not logged.
- Import the p12 with the p12 password. Allow `codesign` to use the key with `security set-key-partition-list`. Do not run `spctl`. Do not run `add-trusted-cert` on the runner.
- Set `SIGN_IDENTITY` to `Nikolay Botev Code Signing` and set `VERSION` to the plain tag being published, then run `bash scripts/build.sh` once. Do not invoke the script before `SIGN_IDENTITY` is set.
- Verify each binary with `codesign --verify --strict`. Do not use `spctl`. A self-signed certificate is not expected to pass a Gatekeeper assessment.
- A trap on exit always deletes the temporary keychain, restores the previous keychain search list, and deletes the p12 file. The trap runs on failure too.
- The `macos` job and the CodeQL job do not receive these secrets and do not create this keychain.

FR14. After verify, the `release` run checks `uname -m` is `arm64` and that `file` on each binary reports `arm64`. It writes `SHA256SUMS` with `shasum -a 256` of the two signed binaries, two spaces between hash and name, as `shasum` prints. The checksum file covers the signed bytes.

FR15. After verify and checksums, the job attests each binary with `actions/attest` and verifies with `gh attestation verify` using the repo, the signer workflow path of this release workflow, and `--deny-self-hosted-runners`, including the existing retry loop. Attestation is not the install check. It then pushes the lightweight tag and uploads with `softprops/action-gh-release@v2`, `tag_name` set to that plain tag, the target commit set to `HEAD`, `generate_release_notes` true, and files `backup-folder`, `drop-box-watcher`, and `SHA256SUMS`. The release body also contains the full commit SHA and the UTC build timestamp that were stamped into the binaries. A failed attest does not push the tag. A `noop` whose release already exists uploads nothing. A `noop` whose tag exists on `HEAD` but whose GitHub release is missing builds, signs, and uploads to that existing tag, and does not create a new tag.

### 5.4 Install, pins, docs

FR16. `scripts/install-roger-tools.sh` keeps the current refusal rules: uid 0, a path component named `Backups`, an invalid tool name, and a pin that is neither `unpinned` nor `v` plus numeric components. `unpinned` skips. A real pin downloads that release asset with `gh release download` and downloads `SHA256SUMS` the same way. It checks the tool's line with `shasum -a 256 -c`. On mismatch or download failure it deletes the temp file, leaves any existing binary in `~/bin`, and exits non-zero. On success it moves the file to `~/bin/<tool>` mode `755`. It does not build from source, does not call `gh attestation verify`, `launchctl`, `sudo`, or `op`, and does not read or write `~/Backups`.

FR17. `pins.txt` stays the pin list. Both lines stay `unpinned` through the build phases that land the package, the workflow, and the installer. A later phase sets both lines to the first published tag only after that release exists. With no release label on that first merge, the tag is `v0.1.1`. That phase does not run the installer. The spec pull request does not change `pins.txt`.

FR18. Docs:

- `README.md` tells a person to build with `bash scripts/build.sh` and no other compile line. Roger's local release build exports `SIGN_IDENTITY=Nikolay Botev Code Signing` first.
- A short code-signing section matches Nikolay's procedure: `/usr/bin/openssl` (LibreSSL) creates a self-signed RSA 2048 certificate whose subject is `/CN=Nikolay Botev Code Signing` and whose extended key usage is code signing, then `pkcs12` exports it. `security import` loads the p12 into the login keychain. `security add-trusted-cert -p codeSign` trusts it for code signing. A copy of the p12 goes into 1Password. `gh secret set` reads `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD` from a pipe or a file. Temp files are deleted. The section does not contain a password, a p12 body, a secret value, or a 1Password item URI.
- The same section says Desktop access is tied to the code signature. An ad-hoc signature changes every rebuild, so a later ad-hoc build may prompt again. Builds signed with `Nikolay Botev Code Signing` keep that identity, which is why the release job uses it.
- The watcher install steps say both binaries come from `scripts/install-roger-tools.sh` once `pins.txt` names a published tag. They name `launchd/drop-box-watcher.plist.template`. They say a merge does not install on Roger, and that CI and agents do not copy binaries into `~/bin`, write the real config, or load the agent.
- `docs/setup.md` gains one `Manual:` bullet for that one-time signing setup and points the watcher LaunchAgent bullet at the template that is already in the repo. `tests/setup-docs.sh` expects 33 setup bullets and keeps every existing anchor. `docs/restore.md` stays at 7 bullets.

FR19. `AGENTS.md` names `bash scripts/build.sh` as the macOS product build, says the `linux` job does not build the package, and says a release is published by the `publish` job on a push to `main`. It does not say a `v*` tag push is the only way a release runs. It still says agents do not set a real pin, do not run the installer against Roger, and do not edit GitHub rulesets.

FR20. No phase adds a required status check. The required contexts stay `macos` and `linux`. Job id `publish` must not be added to ruleset 26167970.

## 6. Acceptance criteria

AC1. `Package.swift` lists executable products `backup-folder` and `drop-box-watcher`, a `BuildStamp` library, and `// swift-tools-version: 6.0`. `bash scripts/build.sh` is the command in the `macos` job, in the CodeQL manual build, and in `README.md`. The `macos` job and the CodeQL manual build export `VERSION=v0.0.0` and leave `SIGN_IDENTITY` unset. `scripts/build.sh` runs `swift build -c release` and does not pass `--product`.

AC2. On macOS, `bash scripts/build.sh` exits 0, writes both repo-root binaries, and `codesign -dv` on each shows an ad-hoc signature when `SIGN_IDENTITY` is unset. With `VERSION` set to `v9.9.9`, `backup-folder --version` prints `backup-folder v9.9.9 (` plus the first 7 characters of `git rev-parse HEAD`, plus `, built ` and a UTC timestamp matching `date -u +%Y-%m-%dT%H:%MZ`. `drop-box-watcher --version` matches with its product name. `--version --verbose` on each prints the full `git rev-parse HEAD` value in that line. The `macos` smoke still prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. The watcher smoke still prints `macos-watcher: build OK`, `macos-watcher: notify OK`, and `macos-watcher: unchanged OK`.

AC3. `tests/macos-smoke.sh` and `tests/macos-watcher.sh` do not invoke `swiftc` on either product. `tests/build-backup-folder.sh` is gone. `.github/workflows/test.yml` still has `timeout-minutes: 5` on `macos` and on `linux`, and the `linux` job does not contain `scripts/build.sh` or `swift build`.

AC4. `.github/workflows/codeql.yml` has no `pull_request` key, schedule `0 6 * * *`, job name `CodeQL (Swift)`, `runs-on: macos-26`, and `timeout-minutes: 30`.

AC5. `bash tests/release-version-test.sh` exits 0. It covers no tags becoming `v0.1.1`, `v0.1.9` becoming `v0.1.10`, `release:minor`, `release:major`, both labels failing, a subject with no pull request number failing, a failed label lookup failing, a successful read with neither label staying a patch, and a `HEAD` that already has a semver tag returning `noop`.

AC6. `bash tests/release-workflow.sh` exits 0. It requires the `publish` job, the `main` push trigger, `fetch-depth: 0`, the two secret names, `pull-requests: read`, `SIGN_IDENTITY` set to `Nikolay Botev Code Signing` before the single `scripts/build.sh` invocation, `VERSION` set to the plain tag being published, `codesign --verify --strict`, `SHA256SUMS`, `uname -m`, a tag ref push, the full SHA in the release body, and the attestation flags. It rejects a second product build in that job, a `pull_request` trigger, a `schedule` trigger, a tag trigger, a job id `macos` or `linux` inside `release.yml`, `spctl`, `git commit`, a push of `main`, `timeout-minutes` on `publish`, and a `VERSION` file. `scripts/build.sh` contains one `swift build -c release` with no `--product` flag, `git rev-parse HEAD`, `git describe --tags --dirty`, and `date -u +%Y-%m-%dT%H:%MZ`. It does not assign `0.0.0`. The secret check in the workflow runs on every `publish` run, including a run that does not create a tag.

AC7. `bash tests/install-roger-tools-test.sh` exits 0. A pinned install with a stub `gh` fails when the checksum does not match and succeeds when it does. The script source does not contain `gh attestation verify`.

AC8. `bash tests/no-secrets.sh` and `bash tests/setup-docs.sh` exit 0. The signing section names `Nikolay Botev Code Signing`, `MACOS_SIGNING_P12_BASE64`, and `MACOS_SIGNING_P12_PASSWORD`, and the repo contains no p12 and no password value.

AC9. `bash tests/linux-unit.sh` still prints `linux-unit: OK`. The retention and path tests still pass from the moved sources.

AC10. The spec pull request's diff is only `intent/release-builds/`. No later phase pushes a tag by hand, sets `pins.txt` to a real tag before a release exists, or runs the installer. There is no `VERSION` file in any phase.

## 7. Design decisions

**D1 — Git tags, no VERSION file, protection unchanged.** Nikolay replaced the VERSION-file scheme. His words: use git tags for the version, no VERSION file, and leave the protection unchanged. The workflow finds the latest `vMAJOR.MINOR.PATCH` tag, or uses `v0.1.0` when none exist, and publishes the next version in the same run. The default bump is patch. Label `release:minor` or `release:major` on the merged pull request selects the other bump. One tag still covers both binaries. Minor and major are not automatic. The baseline `v0.1.0` is not created as a tag, so the first publish with no label is `v0.1.1`. The workflow pushes only that tag, with `GITHUB_TOKEN`, and does not push a commit. Checked 2026-10-30: the repo has no tags and no GitHub releases. Squash subjects on `main` end with `(#N)`, including `9ddd15a`. The same check found no repository labels `release:minor` or `release:major`. `gh label list` returned the ten default GitHub labels. This intent adds those two labels. A failed label lookup fails the publish job. A successful read with neither label stays a patch.

**D2 — Identity `Nikolay Botev Code Signing`.** Nikolay replaced ad-hoc-only signing and replaced the documentation-only certificate. The release job imports `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD` into a temporary keychain, signs with that common name, verifies with `codesign --verify --strict`, and always deletes the keychain. Missing secrets fail the job on every run, including a run that does not create a tag. There is no ad-hoc fallback on that job. The job sets `SIGN_IDENTITY` to `Nikolay Botev Code Signing` before the single `scripts/build.sh` invocation. Hardened runtime is `--options runtime` with no timestamp and no notarization. `spctl` is not used, because a self-signed certificate will not pass Gatekeeper assessment. `scripts/build.sh` signs with `SIGN_IDENTITY` when it is set and otherwise uses `codesign --sign -`. Roger's local builds set `SIGN_IDENTITY` to `Nikolay Botev Code Signing`. The certificate is self-signed, RSA 2048, extended key usage code signing, created with `/usr/bin/openssl` on macOS and a LibreSSL pkcs12 export, stored in the login keychain, and trusted for `codeSign`. This draft did not generate a key, a certificate, or a p12, and it did not run `gh secret set`.

**D3 — arm64 release assets.** Checked 2026-10-30. Workflow run 41104339464 on `9ddd15a` used the `macos` job label `macos-latest` and logged image `macos-26-arm64`. GitHub's hosted-runner table lists `macos-latest` as the arm64 macOS image. The release fails if `uname -m` is not `arm64`. Intel labels exist and are not used.

**D4 — One command.** The command is `bash scripts/build.sh` with no arguments. The `macos` job, the CodeQL manual build, the release job, and a local build all use it. `SIGN_IDENTITY` is the signing switch. `VERSION` is the version half of the stamp. The `macos` job and the CodeQL manual build export `VERSION=v0.0.0` and leave `SIGN_IDENTITY` unset. The release job sets `VERSION` to the plain tag it is publishing and sets `SIGN_IDENTITY` to `Nikolay Botev Code Signing` before the single `scripts/build.sh` invocation. A local build leaves `VERSION` unset and gets `git describe --tags --dirty`. The SHA and the timestamp always come from `git rev-parse HEAD` and `date -u +%Y-%m-%dT%H:%MZ`. The script exits non-zero when it cannot determine a version and does not invent `0.0.0`.

**D13 — Plain tag, SHA and time in the binary.** Nikolay added this. The tag stays `vMAJOR.MINOR.PATCH` with no SHA in the name. Both binaries stamp the full commit SHA and the UTC build timestamp next to the version. `--version` shows a 7-character prefix of that SHA. `--version --verbose` shows the full SHA. The release notes show the full SHA and the same timestamp. `git describe --tags --dirty` is the fallback when `VERSION` is unset. The script exits non-zero when it cannot determine a version and does not invent `0.0.0`. The `macos` job and the CodeQL manual build export `VERSION=v0.0.0`. Those jobs use `actions/checkout` at the default depth of 1, which does not fetch tags, and the repo has no tags yet, so `git describe --tags` cannot see a tag. The release job sets `VERSION` to the plain tag it is publishing.

**D5 — Tools version 6.0.** The `macos-latest` image in run 41104339464 lists default Xcode 26.6. Apple's Xcode system requirements list that Xcode's compiler as Swift 6.3, and the Swift.org announcement for Swift 6.3.3 says Xcode 26.6 contains it. `mise.toml` pins Swift 6.4 for the Linux toolchain only. A tools version of 6.4 would be newer than the runner's compiler. Tools version 6.0 is accepted by Swift 6.3. This draft did not run `swift --version` on the runner. The image readme lists Xcode and does not print a Swift version line. On Swift 6.3 and on Swift 6.4.1, `swift build -c release --product A --product B` builds only the last product. `scripts/build.sh` runs one `swift build -c release` with no `--product` filter so both executables are built. This draft did not re-run that compile.

**D6 — Checksums install, attestation stays on publish.** Nikolay asked for a checksum-verified download. The install script stops calling `gh attestation verify`. The publish job still attests, because `release.yml` on `9ddd15a` already does and this intent does not remove that check. Checksums are computed after `codesign` so they match the bytes that are uploaded.

**D7 — The tag push does not bump again.** The job does not push a commit, so it cannot start itself by a push to `main`. GitHub's `GITHUB_TOKEN` documentation, checked 2026-10-30, says events triggered by that token do not create a new workflow run, except `workflow_dispatch` and `repository_dispatch`. A tag push is not one of those exceptions. The workflow also has no tag trigger. A re-run of the same commit is `noop` once `HEAD` has a semver tag (FR10), so a second click does not mint another version. `macos` and `linux` still run on the original push to `main`. They do not compute a version.

**D8 — Job id `publish`.** Required checks are the contexts `macos` and `linux` from ruleset 26167970, integration id 15368. `release.yml` on `9ddd15a` uses job id `macos` and a tag trigger, so it does not run on pull requests. The new workflow runs on every push to `main`, where the `test` workflow also has a job id `macos`. A second job id `macos` would make those checks ambiguous. The release job id is `publish`. It is not added to the ruleset. No new required job is introduced.

**D9 — Ruleset 26167970 targets the default branch, not tags.** Rechecked 2026-10-30 with `gh api repos/nikolaybotev/backup-folder/rulesets/26167970` and the ruleset list. It is the only ruleset. It is active. Its target is `branch`. Its condition include is `~DEFAULT_BRANCH` only, exclude empty. `bypass_actors` is null. Its rules are deletion, non-fast-forward, required linear history, required signatures, pull request (squash only, zero required reviews), and required status checks `linux` and `macos` with the strict policy. There is no tag ruleset. The tag list length was 0. A lightweight tag is not a commit on `main`, so this ruleset does not apply to the tag push. The workflow does not push a commit, does not add a bypass, and does not add a PAT. This is not an open gate. This draft did not push a tag. The `actions` permissions endpoint returned 403 on the earlier check the same day, so the default workflow token permission was not read. The `publish` job sets `contents: write`, which is what lets it push the tag, plus `id-token: write` and `attestations: write` for attestation, and `pull-requests: read`, which is what lets the token read pull request labels.

**D10 — Pins wait for the tag.** `pins.txt` on `9ddd15a` is `backup-folder unpinned` and `drop-box-watcher unpinned`. The first real pin is the first published tag. With no release label, that tag is `v0.1.1`. Only a phase that can see that release sets the pin. The spec pull request does not.

**D11 — Certificate lifetime.** Nikolay did not specify a certificate lifetime. The docs do not state one. This draft did not inspect his certificate.

**D12 — TCC copy.** Desktop access follows the code signature. The docs say an ad-hoc rebuild may prompt again, and that the stable identity is what the release job and Roger's `SIGN_IDENTITY` builds use. This draft did not prompt TCC on a Mac.

## 8. Open questions

None. D9 is a finding, not a gate. Tags are not protected.

## 9. Surfaces

| Surface | Owns |
|---|---|
| `Package.swift` and `scripts/build.sh` | Build both executables, stamp `--version`, and sign them |
| `scripts/release-version.sh` | Next tag name, or `noop` |
| Job `publish` | Keychain, verify, checksums, attestation, tag push, GitHub release |
| `scripts/install-roger-tools.sh` and `pins.txt` | Download a pinned release and check SHA-256 |
| `README.md` and `docs/setup.md` | One-time certificate steps, TCC, watcher install |
| Ruleset 26167970 | Stays as Roger set it. This repo does not edit it |

## 10. What was checked

Checked 2026-10-30 against `main` at `9ddd15ad4f41c4b84cf0ac09ed59c4e4dcf0cd49`:

- `.github/workflows/release.yml` triggers on tags `v*`, job id `macos`, `runs-on: macos-latest`, builds `backup-folder` with `tests/build-backup-folder.sh` and `drop-box-watcher` with a `swiftc` file list, attests both, verifies with `gh attestation verify`, and uploads the two binaries. It does not sign, does not write a checksum, and has no `timeout-minutes`.
- `.github/workflows/test.yml` jobs `macos` and `linux` each set `timeout-minutes: 5`. The `linux` job compiles the retention tests and the path tests. It does not compile `walk-tests`. `AGENTS.md` at that commit says the `linux` job compiles `walk-tests`. The workflow file is the one this spec follows.
- `.github/workflows/codeql.yml` has no `pull_request` key. It pushes on `main` and schedules `0 6 * * *`. Job name `CodeQL (Swift)`, `runs-on: macos-26`, `timeout-minutes: 30`. The manual build calls `tests/build-backup-folder.sh` and a `swiftc` file list.
- `actions/checkout@v4` in `test.yml`, `codeql.yml`, and `release.yml` sets no `fetch-depth`. The action default is depth 1, which does not fetch tags. The tag list length was 0.
- `gh label list` on 2026-10-30 returned the ten default GitHub labels. `release:minor` and `release:major` were not among them.
- On Swift 6.3 and on Swift 6.4.1, passing `--product` twice to `swift build -c release` builds only the last product. Recorded in D5. This draft did not re-run that compile.
- `scripts/install-roger-tools.sh` downloads with `gh release download` and verifies with `gh attestation verify`. It does not check a checksum. `pins.txt` lists both tools as `unpinned`.
- `tests/build-backup-folder.sh` symlinks `backup-folder.swift` to `main.swift` beside the three other snapshot sources because top-level code has to live in `main.swift`.
- `README.md` still shows a one-file `swiftc` build and says Nikolay pushes a `v*` tag. `docs/setup.md` still says the watcher plist is not in the repo. `launchd/drop-box-watcher.plist.template` is on `main`.
- `tests/setup-docs.sh` requires 32 `Manual:` or `Script:` bullets in `docs/setup.md` and 7 in `docs/restore.md`. `tests/no-secrets.sh` scans `intent/`.
- `.gitignore` ignores the path name `backup-folder` in any directory and ignores `/drop-box-watcher` with exceptions for the source tree.
- Ruleset 26167970, rechecked the same day and recorded in D9. Target `branch`, include `~DEFAULT_BRANCH`, no tag ruleset, tag count 0, no releases. Actions permissions request returned 403.
- GitHub's `GITHUB_TOKEN` document: a tag push with that token does not start a workflow run. The exceptions are `workflow_dispatch` and `repository_dispatch`.
- Runner architecture, as recorded in D3, from run 41104339464 and from GitHub's hosted-runner documentation.
- Xcode 26.6 on that image readme, and the Swift 6.3 compiler figures in D5.

This draft did not create a certificate, did not run `gh secret set`, did not push a tag, and did not run the installer.
