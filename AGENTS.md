# backup-folder

Small macOS CLI that snapshots a folder with APFS copy-on-write clones (`backup-folder <src> <dest>`). Design and bug backlog live in the Cairn Project Agent Store, not in this repo.

## Commands

- Build (macOS): `bash tests/build-backup-folder.sh` (healthy: `backup-folder` binary in the repo root). Symlinks `backup-folder.swift` as `main.swift` beside `Retention.swift`, `PathCheck.swift`, and `WalkPolicy.swift` because multi-file `swiftc` only allows top-level code in `main.swift`.
- Build watcher (macOS): `swiftc -O -o drop-box-watcher drop-box-watcher/Config.swift drop-box-watcher/Readiness.swift drop-box-watcher/Log.swift drop-box-watcher/WebhookHTTP.swift drop-box-watcher/WebhookNotifier.swift drop-box-watcher/Watcher.swift drop-box-watcher/main.swift` (healthy: `drop-box-watcher` binary in the repo root).
- Parse-only (Linux cloud VM): `swiftc -parse backup-folder.swift` (healthy: exit 0). Full type-check and link need Darwin; Linux cannot build this binary while the tool imports `Darwin` and calls `clonefile`.
- Darwin-free unit tests (Linux cloud VM and CI): `bash tests/linux-unit.sh` (healthy: line `linux-unit: OK`). Covers `drop-box-watcher` config, readiness, logging, and webhook notifier logic.
- CI smoke (macOS): `bash tests/macos-smoke.sh` (healthy: line `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`). Snapshot directories match `yyyy-MM-dd_HHmm` or `yyyy-MM-dd_HHmmss-<pid>` (with optional numeric suffixes); the script runs two successful snapshots and a non-blocking busy-lock skip.
- Watcher smoke (macOS): `bash tests/macos-watcher.sh` (healthy: lines `macos-watcher: build OK`, `macos-watcher: notify OK`, and `macos-watcher: unchanged OK`).
- Secret scan (Linux or macOS): `bash tests/no-secrets.sh` (healthy: line `no-secrets: all checks passed`). Also runs in the `macos` CI job.
- Install Roger tools (Linux or macOS): `bash tests/install-roger-tools-test.sh` (healthy: line `install-roger-tools-test: all checks passed`). Also runs in the `macos` CI job. Nikolay runs `bash scripts/install-roger-tools.sh` on Roger when `pins.txt` names real `v*` tags; until then unpinned tools are skipped. The script installs only into `~/bin`, refuses root (uid 0), refuses any install path with a `Backups` path component, and does not use `launchctl`.
- Ensure backup directories (Linux or macOS): `bash tests/ensure-backup-dirs-test.sh` (healthy: line `ensure-backup-dirs-test: all checks passed`). Also runs in the `macos` CI job. Nikolay passes absolute home-mirrored snapshot paths as arguments to `bash scripts/ensure-backup-dirs.sh`; CI and agents do not run it against a live home.
- Setup and restore docs (Linux or macOS): `bash tests/setup-docs.sh` (healthy: line `setup-docs: all checks passed`). Also runs in the `macos` CI job. Validates `docs/setup.md` and `docs/restore.md` bullet marks and catalog anchors.
- `pins.txt` lists each tool and its release tag (`unpinned` until Nikolay sets a real pin after a published release). Agents do not set a real pin or run the install script against Roger's home.
- Cloud Agent install: `bash .cursor/install.sh` (healthy: `swiftc --version` and skills under `~/.cursor/skills-cursor`).
- Cloud Agent start: `bash .cursor/start.sh` (no-op for this repo).
- CI: `.github/workflows/test.yml` (workflow `test`, jobs `macos` and `linux`) runs on every pull request and on pushes to `main`. Required pull request checks are `macos` and `linux`. The `macos` job builds with `bash tests/build-backup-folder.sh`, runs `tests/macos-smoke.sh`, `tests/macos-watcher.sh`, and `tests/linux-unit.sh`, plus script and template checks on `macos-latest`. The `linux` job on `ubuntu-latest` installs Swift via `mise`, runs `tests/linux-unit.sh`, compiles `Retention.swift` with `tests/retention-tests.swift`, compiles `PathCheck.swift` with `tests/path-tests.swift`, and compiles `WalkPolicy.swift` with `tests/walk-tests.swift`; it does not compile `backup-folder.swift`.
- CodeQL: `.github/workflows/codeql.yml` runs job `CodeQL (Swift)` on pushes to `main` and on a nightly schedule (06:00 UTC), with `timeout-minutes: 30`. It does not run on pull requests.
- Release CD: `.github/workflows/release.yml` runs on tags matching `v*` on `macos-latest`, attests each built binary with GitHub artifact attestation, verifies with `gh attestation verify`, then uploads the binaries to a GitHub release. Merging to `main` does not publish a release; only a `v*` tag push does. Do not claim a release ran unless that tag push happened. Nikolay creates tags when a build is ready for Roger.
- Branch protection: managed outside this repo by Roger with `gh`; agents must not create or change GitHub rulesets.

## Conventions

- Docs follow the solo AI-native SDLC chain when present: `intent/<change>/intent.md` → `spec.md` → `plan.md`. This repo may not have that chain until onboarding intents land.
- Do not commit real backup paths, hostnames, personal folder names, WireGuard keys, tunnel addresses, endpoints, ports, or 1Password item URIs in tests, fixtures, or templates (use the placeholder tokens).
- Do not install the binary into `~/Backups` or `~/Backups/bin/backup-folder` from CI or agent work unless an intent explicitly says so.

## Architecture

- `backup-folder.swift` is the CLI entry point; `Retention.swift` holds Darwin-free prune rules (Foundation only); `WalkPolicy.swift` holds directory cycle detection used during the clone walk.
- `launchd/backup-folder.plist.template` is a per-folder LaunchAgent template (label `com.nikolay.backup.NAME`, hourly at calendar minute 0, binary `/Users/USER/bin/backup-folder`); loading it is manual on a Mac.
- `launchd/com.wireguard.wg0.plist.template` and `launchd/wg0.conf.template` are WireGuard placeholders only. Never commit a WireGuard key, endpoint, tunnel address, or 1Password item URI in git; Nikolay fills them from 1Password at install time.
- Agents do not load LaunchAgents, run `launchctl`, or write under `~/Backups`.
- `mise.toml` pins Swift for Linux editing in Cloud Agents only.

## Things agents get wrong

- Do not run `swift build`; there is no `Package.swift`.
- Do not add a Linux CI job that type-checks or links `backup-folder.swift`; the existing `linux` job runs `tests/linux-unit.sh`, the `Retention.swift` unit tests, `path-tests`, and `walk-tests`.
- Do not claim a GitHub release was published unless a `v*` tag push actually ran `release.yml`.
- Do not create or change branch protection rulesets in GitHub; Roger maintains them with `gh`.
- Cloud Agents on Linux can parse and edit the source but cannot execute `clonefile`, APFS clones, or `launchctl`.
- Agents do not run [`docs/setup.md`](docs/setup.md) or [`docs/restore.md`](docs/restore.md) on a live Mac, do not run `scripts/install-roger-tools.sh` against Roger's home, and do not run `launchctl` on Roger.

## Cursor Cloud specific instructions

- `.cursor/environment.json` runs `bash .cursor/install.sh` and `bash .cursor/start.sh`.
- Install puts Swift 6.4 from `mise.toml` on `PATH`, installs `libncurses6` when needed, and installs skills from `nikolaybotev/local-skills` into `~/.cursor/skills-cursor`.
- Start is a no-op; there is no dev server.
