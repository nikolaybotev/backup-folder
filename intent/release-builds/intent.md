# intent.md — Release builds

| | |
|---|---|
| Author | Nikolay (relayed by Roger) |
| Captured | 2026-10-30 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [roger-bootstrap](../roger-bootstrap/intent.md), [drop-box-watcher](../drop-box-watcher/intent.md) |

## Problem

Nikolay is holding off on installing the watcher until backup-folder and drop-box-watcher have a proper build and release, not an ad-hoc `swiftc` command.

## Proposed outcome

Both tools share one Swift package and one build script. A merge to `main` publishes one GitHub release with arm64 macOS binaries and checksums. The release job signs both binaries with the self-signed identity `Nikolay Botev Code Signing`. Roger installs a pinned release with `gh release download` and a checksum check.

The signing paragraphs in the original prompt are not the signing requirement. The signing corrections below replace them. Ad-hoc signing remains only when `SIGN_IDENTITY` is unset.

## Affected users and systems

- **Users:** Nikolay, who approves anything installed on Roger. Roger, who follows the docs and does not install them on his own.
- **Systems:** the public repo `nikolaybotev/backup-folder`, GitHub Actions on `macos-latest`, ruleset 26167970 on `main`, `pins.txt`, `scripts/install-roger-tools.sh`, and `~/bin` on Roger after Nikolay runs the installer.

## Constraints and principles

- One build command for the `macos` job and for a local build: `bash scripts/build.sh`.
- Required pull request checks stay `macos` and `linux`. The release job is not a pull request check and is not a required check.
- `macos` and `linux` keep `timeout-minutes: 5`. `CodeQL (Swift)` stays off pull requests.
- No paid Apple Developer membership, no notarization, and no new required job.
- No PAT and no ruleset edit. Agents do not install anything on Roger, do not set a real pin in the spec pull request, and do not put a secret in git.

## Open questions (carried into spec.md)

None. The version-bump push is a gate in the plan, recorded from the ruleset check, not an open design question.

## Original prompt (verbatim)

```
From Nikolay (his own words, relayed by Roger): he's holding off on installing the watcher until there's a proper build and release process, not an ad-hoc swiftc command. The outcome he wants for backup-folder (both tools, backup-folder and drop-box-watcher):

1. A real build definition: Swift Package Manager (Package.swift) with both executables, plus one small KISS bash script (e.g. scripts/build.sh) that's the single entry point. CI (the macos job) and a local build on Roger must run that same script the same way.
2. A continuous release process: on merge to main, bump the version (propose a simple scheme, e.g. semver from a VERSION file or auto patch bump; say which you picked and why), tag it, and publish a GitHub release with the built arm64 macOS binaries and checksums attached.
3. Signing: no paid Apple Developer membership. Binaries are at least ad-hoc signed (codesign -s -). Note in the docs that macOS ties TCC permissions (Desktop access) to the code signature, so ad-hoc re-signs may re-prompt after upgrades. Lay out the option of a free self-signed code-signing identity on Roger for a stable identity, but don't build that unless Nikolay asks.
4. Update scripts/install-roger-tools.sh and pins.txt so Roger installs a pinned release with gh release download (checksum-verified) instead of building from source, and update the watcher install docs to match.

Keep CI at 5-minute timeouts for macos and linux, and keep CodeQL off pull requests. If you add a new required CI job name, tell me its exact name once it's on main so I can add it to the ruleset. When it's merged, bring me the install steps from a release. Nothing gets installed on Roger without Nikolay's own approval.
```

## Kickoff decisions and constraints (verbatim)

```
Decisions already made (record as D-numbers with the reasoning; do not re-litigate):

- D1. VERSION file, semver, first release 0.1.0, automatic patch bump on every merge to main. One version and one tag cover both executables. Minor and major are not automatic. Why: nothing has been released yet, so 0.1.0 is the first ship; one tag ships both binaries; a patch bump needs no human to classify the change.

Constraints:
- Required PR checks stay `macos` and `linux` only. Do not add a new required job. Release runs on push to main, not as a pull-request check. If the plan truly needs a new required job, stop and name the exact job name; do not add it.
- Job timeout-minutes stay 5 for `macos` and `linux`. `CodeQL (Swift)` stays off pull_request, on push to main and nightly `0 6 * * *`, timeout-minutes 30, job name unchanged, macos-26 pin unchanged.
- Do not create or change GitHub rulesets. Ruleset 26167970 requires signed commits, linear history, squash merges, and blocks force-push and deletion of main. Check whether GITHUB_TOKEN can push the version-bump commit and the tag. If it cannot, write that as an open gate for Roger. Do not invent a PAT or a bypass.
- The version-bump push must not bump again. Specify the guard.
- Ad-hoc `codesign -s -` only. Document TCC (Desktop access is tied to the signature; an ad-hoc re-sign may re-prompt). Describe a free self-signed identity on Roger as an option. Do not implement that identity.
- Release assets: arm64 macOS binaries for both tools, plus checksums. Confirm the GitHub macos runner architecture before freezing that.
- `scripts/build.sh` is the only build entry point for the macos CI job and for a local build. Same invocation.
- `scripts/install-roger-tools.sh` downloads a pinned release with `gh release download` and verifies checksums. It does not build from source. `pins.txt` stays the pin list. Do not set a real pin in this spec PR; the first real pin is the first published tag, and a later phase sets it only when that tag exists. Do not run the installer. Do not touch ~/Backups or ~/bin.
- No webhook URL, routine key, WireGuard key, public IP, or port in the repo.
- Agents must not install anything on Roger.
- Conventional commits. One PR for this spec and plan. Do not start build phases.
- Where you check a fact (current release.yml, test.yml, install script, runner arch, ruleset push rights), record what you checked in the spec.
```

The ad-hoc-only bullet in that constraints list is revoked by the signing corrections.

## Signing correction (verbatim)

```
Nikolay updated item 3. Replace the ad-hoc-only decision. Record this as the signing decision and do not re-litigate it.

He wants a stable self-signed code-signing identity used by both GitHub Actions and local builds, instead of ad-hoc-only signing.

- CI release job: import the identity from two repo secrets, names `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD`, into a temporary keychain, codesign both binaries with it (hardened runtime is fine, no notarization, no paid Apple Developer membership), verify with `codesign --verify`, and always delete the temp keychain. If the secrets are absent, fail the release job clearly. Do not fall back to silent ad-hoc signing on the release job.
- `scripts/build.sh`: sign with the identity named by an env var `SIGN_IDENTITY` when set, otherwise ad-hoc (`codesign -s -`), so a local build on Roger can use the same cert from the login keychain.
- Docs: a short one-time setup section for creating the self-signed code-signing cert on Roger (Keychain Access or openssl), exporting the .p12, keeping a copy in 1Password, and setting the two secrets with `gh secret set` reading from files or stdin so values never get printed.

Do not generate a certificate, a key, a .p12, or any secret. Do not run `gh secret set`. Do not print or invent secret values. Roger and Nikolay do that on the Mac.

The earlier note that a self-signed identity is documentation-only is revoked. Ad-hoc remains the local default when `SIGN_IDENTITY` is unset. The release job requires the secrets.

Keep every other constraint from the original kickoff. This is still spec and plan only.
```

## Signing identity (verbatim)

```
Nikolay is creating the certificate now. Use these details exactly. Do not generate or handle any key material.

- Repo secrets: `MACOS_SIGNING_P12_BASE64` (base64 of the .p12) and `MACOS_SIGNING_P12_PASSWORD`.
- Identity common name: `Nikolay Botev Code Signing`. Self-signed, RSA 2048, EKU codeSigning, created with macOS `/usr/bin/openssl` (LibreSSL) pkcs12 export. On Roger it is in the login keychain, trusted for codeSign.
- CI imports it into a temporary keychain and signs with that identity name. A self-signed cert will not pass Gatekeeper or assessment checks. Verify with `codesign --verify --strict`, not `spctl`. Always delete the temp keychain. If either secret is absent, fail the release job. Do not fall back to ad-hoc on the release job.
- `scripts/build.sh`: when `SIGN_IDENTITY` is set, sign with that identity (Roger’s local builds set it to `Nikolay Botev Code Signing` so they use the login-keychain cert). When unset, ad-hoc `codesign -s -`.
- The one-time setup doc must match this procedure: create with openssl, `security import` plus `add-trusted-cert -p codeSign`, `gh secret set` from stdin, a copy in 1Password, delete the temp files. Do not include secret values, the password, or the .p12.

Still spec and plan only. Keep the other constraints.
```
