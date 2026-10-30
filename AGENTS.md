# backup-folder

Small macOS CLI that snapshots a folder with APFS copy-on-write clones (`backup-folder <src> <dest>`). Design and bug backlog live in the Cairn Project Agent Store, not in this repo.

## Commands

- Build (macOS): `bash tests/build-backup-folder.sh` (healthy: `backup-folder` binary in the repo root). Symlinks `backup-folder.swift` as `main.swift` beside `Retention.swift` because multi-file `swiftc` only allows top-level code in `main.swift`.
- Parse-only (Linux cloud VM): `swiftc -parse backup-folder.swift` (healthy: exit 0). Full type-check and link need Darwin; Linux cannot build this binary while the tool imports `Darwin` and calls `clonefile`.
- Darwin-free unit tests (Linux cloud VM and CI): `bash tests/linux-unit.sh` (healthy: line `linux-unit: OK`). Covers `drop-box-watcher` config, readiness, logging, and webhook notifier logic.
- CI smoke (macOS): `bash tests/macos-smoke.sh` (healthy: line `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`).
- Secret scan (Linux or macOS): `bash tests/no-secrets.sh` (healthy: line `no-secrets: all checks passed`). Also runs in the `macos` CI job.
- Install tools (Linux or macOS): `bash tests/install-tools-test.sh` (healthy: line `install-tools-test: all checks passed`). Also runs in the `macos` CI job. The maintainer runs `bash scripts/install-tools.sh` on the deployment Mac when `pins.txt` names real `v*` tags; until then unpinned tools are skipped. The script installs only into `~/bin`, refuses root (uid 0), refuses any install path with a `Backups` path component, and does not use `launchctl`.
- Ensure backup directories (Linux or macOS): `bash tests/ensure-backup-dirs-test.sh` (healthy: line `ensure-backup-dirs-test: all checks passed`). Also runs in the `macos` CI job. The maintainer passes absolute home-mirrored snapshot paths as arguments to `bash scripts/ensure-backup-dirs.sh`; CI and agents do not run it against a live home.
- `pins.txt` lists each tool and its release tag (`unpinned` until the maintainer sets a real pin after a published release). Agents do not set a real pin or run the install script against the deployment Mac's home.
- Cloud Agent install: `bash .cursor/install.sh` (healthy: `swiftc --version` and skills under `~/.cursor/skills-cursor`).
- Cloud Agent start: `bash .cursor/start.sh` (no-op for this repo).
- CI: `.github/workflows/test.yml` (workflow `test`, jobs `macos` and `linux`) runs on every pull request and on pushes to `main`. The `macos` job builds with `swiftc` and runs `tests/macos-smoke.sh` on `macos-latest`. The `linux` job on `ubuntu-latest` installs Swift via `mise`, runs `tests/linux-unit.sh`, and compiles only `Retention.swift` with `tests/retention-tests.swift`; it does not compile `backup-folder.swift`.
- CodeQL: `.github/workflows/codeql.yml` runs CodeQL (Swift) on pull requests and on pushes to `main` (plus a weekly schedule).
- Release CD: `.github/workflows/release.yml` runs on tags matching `v*` on `macos-latest`, attests each built binary with GitHub artifact attestation, verifies with `gh attestation verify`, then uploads the binaries to a GitHub release. Merging to `main` does not publish a release; only a `v*` tag push does. Do not claim a release ran unless that tag push happened. The maintainer creates tags when a build is ready for the deployment Mac.
- Branch protection: managed outside this repo by the deployment Mac with `gh`; agents must not create or change GitHub rulesets.

## Conventions

- Docs follow the solo AI-native SDLC chain when present: `intent/<change>/intent.md` → `spec.md` → `plan.md`. This repo may not have that chain until onboarding intents land.
- Do not commit real backup paths, hostnames, personal folder names, WireGuard keys, tunnel addresses, endpoints, ports, or 1Password item URIs in tests, fixtures, or templates (use the placeholder tokens).
- Do not install the binary into `~/Backups` or `~/Backups/bin/backup-folder` from CI or agent work unless an intent explicitly says so.

## Architecture

- `backup-folder.swift` is the CLI entry point; `Retention.swift` holds Darwin-free prune rules (Foundation only).
- `launchd/backup-folder.plist.template` is a per-folder LaunchAgent template (label `com.nikolay.backup.NAME`, hourly at calendar minute 0, binary `/Users/USER/bin/backup-folder`); loading it is manual on a Mac.
- `launchd/com.wireguard.wg0.plist.template` and `launchd/wg0.conf.template` are WireGuard placeholders only. Never commit a WireGuard key, endpoint, tunnel address, or 1Password item URI in git; the maintainer fills them from 1Password at install time.
- Agents do not load LaunchAgents, run `launchctl`, or write under `~/Backups`.
- `mise.toml` pins Swift for Linux editing in Cloud Agents only.

## Things agents get wrong

- Do not run `swift build`; there is no `Package.swift`.
- Do not add a Linux CI job that type-checks or links `backup-folder.swift`; the existing `linux` job runs `tests/linux-unit.sh` and the `Retention.swift` unit tests only.
- Do not claim a GitHub release was published unless a `v*` tag push actually ran `release.yml`.
- Do not create or change branch protection rulesets in GitHub; the deployment Mac maintains them with `gh`.
- Cloud Agents on Linux can parse and edit the source but cannot execute `clonefile`, APFS clones, or `launchctl`.

## Cursor Cloud specific instructions

- `.cursor/environment.json` runs `bash .cursor/install.sh` and `bash .cursor/start.sh`.
- Install puts Swift 6.4 from `mise.toml` on `PATH`, installs `libncurses6` when needed, and installs skills from `OWNER/local-skills` into `~/.cursor/skills-cursor`.
- Start is a no-op; there is no dev server.
