# backup-folder

Small macOS CLI that snapshots a folder with APFS copy-on-write clones (`backup-folder <src> <dest>`). Design and bug backlog live in the Cairn Project Agent Store, not in this repo.

## Commands

- Build (macOS): `swiftc -O -o backup-folder backup-folder.swift` (healthy: `backup-folder` binary in the repo root).
- Parse-only (Linux cloud VM): `swiftc -parse backup-folder.swift` (healthy: exit 0). Full type-check and link need Darwin; Linux cannot build this binary while the tool imports `Darwin` and calls `clonefile`.
- CI smoke (macOS): `bash tests/macos-smoke.sh` (healthy: line `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`).
- Cloud Agent install: `bash .cursor/install.sh` (healthy: `swiftc --version` and skills under `~/.cursor/skills-cursor`).
- Cloud Agent start: `bash .cursor/start.sh` (no-op for this repo).
- CI: `.github/workflows/test.yml` (workflow `test`, job `macos`) runs on every pull request and on pushes to `main`. It builds with `swiftc` and runs `tests/macos-smoke.sh` on `macos-latest`. There is no Linux CI job yet: all runtime logic lives in `backup-folder.swift` and requires Darwin.
- CodeQL: `.github/workflows/codeql.yml` runs CodeQL (Swift) on pull requests and on pushes to `main` (plus a weekly schedule).
- Release CD: `.github/workflows/release.yml` runs on tags matching `v*`, builds on `macos-latest`, and uploads the `backup-folder` binary to a GitHub release. Merging to `main` does not publish a release; only a tag push does. Nikolay creates tags when a build is ready for Roger.
- Branch protection: managed outside this repo by Roger with `gh`; agents must not create or change GitHub rulesets.

## Conventions

- Docs follow the solo AI-native SDLC chain when present: `intent/<change>/intent.md` → `spec.md` → `plan.md`. This repo may not have that chain until onboarding intents land.
- Do not commit real backup paths, hostnames, or personal folder names in tests or fixtures.
- Do not install the binary into `~/Backups` or `~/Backups/bin/backup-folder` from CI or agent work unless an intent explicitly says so.

## Architecture

- `backup-folder.swift` is the entire program (no Swift package manifest).
- `launchd/backup-folder.plist.template` is a per-folder LaunchAgent template; loading it is manual on a Mac.
- `mise.toml` pins Swift for Linux editing in Cloud Agents only.

## Things agents get wrong

- Do not run `swift build`; there is no `Package.swift`.
- Do not add a Linux CI job that type-checks or links this file until Darwin-free logic is extracted; a red Linux job is worse than none.
- Do not claim a GitHub release was published unless a `v*` tag push actually ran `release.yml`.
- Do not create or change branch protection rulesets in GitHub; Roger maintains them with `gh`.
- Cloud Agents on Linux can parse and edit the source but cannot execute `clonefile`, APFS clones, or `launchctl`.

## Cursor Cloud specific instructions

- `.cursor/environment.json` runs `bash .cursor/install.sh` and `bash .cursor/start.sh`.
- Install puts Swift 6.4 from `mise.toml` on `PATH`, installs `libncurses6` when needed, and installs skills from `nikolaybotev/local-skills` into `~/.cursor/skills-cursor`.
- Start is a no-op; there is no dev server.
