# backup-folder

Small macOS CLI that snapshots a folder with APFS copy-on-write clones (`backup-folder <src> <dest>`). Design and bug backlog live in the Cairn Project Agent Store, not in this repo.

## Commands

- Build (macOS): `bash scripts/build.sh` (healthy: `backup-folder` and `drop-box-watcher` binaries in the repo root). One Swift package builds both executables. `SIGN_IDENTITY` is only the local-build switch: when it is set, the script signs with that login-keychain identity; when it is unset, it ad-hoc signs with `codesign -s -`. The `macos` job and the CodeQL manual build export `VERSION=v0.0.0` and leave `SIGN_IDENTITY` unset. When `VERSION` is unset locally, the script uses `git describe --tags --dirty`; it exits non-zero when that cannot determine a version and does not invent `0.0.0`. The commit SHA and UTC build time always come from `git rev-parse HEAD` and `date -u +%Y-%m-%dT%H:%MZ`.
- Parse-only (Linux cloud VM): `swiftc -parse Sources/backup-folder/main.swift` (healthy: exit 0). Full type-check and link need Darwin; Linux cannot build this binary while the tool imports `Darwin` and calls `clonefile`.
- Darwin-free unit tests (Linux cloud VM and CI): `bash tests/linux-unit.sh` (healthy: line `linux-unit: OK`). Covers `drop-box-watcher` config, readiness, logging, and webhook notifier logic.
- Build entry static check (Linux or macOS): `bash tests/build-entry-test.sh` (healthy: line `build-entry-test: all checks passed`). Also runs in the `macos` and `linux` CI jobs.
- CI smoke (macOS): `bash tests/macos-smoke.sh` (healthy: line `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`). Snapshot directories match `yyyy-MM-dd_HHmm` or `yyyy-MM-dd_HHmmss-<pid>` (with optional numeric suffixes); the script runs two successful snapshots and a non-blocking busy-lock skip. Requires repo-root binaries from `bash scripts/build.sh`.
- Watcher smoke (macOS): `bash tests/macos-watcher.sh` (healthy: lines `macos-watcher: build OK`, `macos-watcher: notify OK`, and `macos-watcher: unchanged OK`). Uses the repo-root `drop-box-watcher` binary from `bash scripts/build.sh`.
- Secret scan (Linux or macOS): `bash tests/no-secrets.sh` (healthy: line `no-secrets: all checks passed`). Also runs in the `macos` CI job.
- Install tools (Linux or macOS): `bash tests/install-tools-test.sh` (healthy: line `install-tools-test: all checks passed`). The `macos` job also runs `bash tests/install-tools-e2e.sh` (healthy: line `install-tools-e2e: all checks passed`). Run `bash scripts/install-tools.sh` on your Mac when `~/.config/backup-folder/pins.txt` names real `v*` tags; until then unpinned tools are skipped. The script installs only into `~/bin` and does not use `launchctl`.
- Ensure backup directories (Linux or macOS): `bash tests/ensure-backup-dirs-test.sh` (healthy: line `ensure-backup-dirs-test: all checks passed`). Also runs in the `macos` CI job. Pass absolute home-mirrored snapshot paths as arguments to `bash scripts/ensure-backup-dirs.sh`; CI and agents do not run it against a live home.
- Setup and restore docs (Linux or macOS): `bash tests/setup-docs.sh` (healthy: line `setup-docs: all checks passed`). Also runs in the `macos` CI job. Validates `docs/setup.md` and `docs/restore.md` bullet marks and catalog anchors.
- `pins.txt.example` documents each tool and its release tag (`unpinned` until you set a real pin in `~/.config/backup-folder/pins.txt` after a published release). Agents do not write the live pin file, do not commit a real pin, and do not run the install script against a live home.
- Cloud Agent install: `bash .cursor/install.sh` (healthy: `swiftc --version` and skills under `~/.cursor/skills-cursor`).
- Cloud Agent start: `bash .cursor/start.sh` (no-op for this repo).
- CI: `.github/workflows/test.yml` (workflow `test`, jobs `macos` and `linux`) runs on every pull request and on pushes to `main`. Required pull request checks are `macos` and `linux`. The `macos` job exports `VERSION=v0.0.0`, runs `bash scripts/build.sh`, then runs `tests/macos-smoke.sh`, `tests/macos-watcher.sh`, and `tests/linux-unit.sh`, plus script and template checks on `macos-latest`. The `linux` job on `ubuntu-latest` installs Swift via `mise`, runs `tests/build-entry-test.sh`, `tests/linux-unit.sh`, compiles `Sources/backup-folder/Retention.swift` with `tests/retention-tests.swift`, compiles `Sources/backup-folder/PathCheck.swift` with `tests/path-tests.swift`, and compiles `Sources/ToolConfig/TomlSubset.swift`, `Sources/backup-folder/PathCheck.swift`, `Sources/backup-folder/BackupConfig.swift`, `Sources/backup-folder/FolderJob.swift`, and `tests/folder-job-tests.swift` with `swiftc -parse-as-library`; it does not build the package or compile `Sources/backup-folder/main.swift`.
- CodeQL: `.github/workflows/codeql.yml` runs job `CodeQL (Swift)` on pushes to `main` and on a nightly schedule (06:00 UTC), with `timeout-minutes: 30`. The manual build exports `VERSION=v0.0.0` and runs `bash scripts/build.sh`. It does not run on pull requests.
- Release CD: `.github/workflows/release.yml` runs job `publish` on every push to `main`. That job runs `scripts/release-version.sh`, which parses `(#N)` at the end of the squash-merge commit subject for the merged pull request number, then reads that pull request's `release:minor` / `release:major` labels to choose the next tag. It may push one lightweight `vMAJOR.MINOR.PATCH` tag with `GITHUB_TOKEN`, signs both arm64 binaries with the signing identity (always the single identity on the certificate imported from `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD`; the job does not honor a pre-set `SIGN_IDENTITY`; a missing identity fails the job), attests them, writes `SHA256SUMS` with `scripts/release-sha256sums.sh` (release asset basenames), verifies `shasum -a 256 -c SHA256SUMS` against a download-style layout, and publishes one GitHub release. It does not push a commit to `main`. Do not claim a release ran unless that publish job succeeded. Agents do not push tags by hand.
- Branch protection: managed outside this repo with `gh`; agents must not create or change GitHub rulesets.

## Conventions

- Docs follow the solo AI-native SDLC chain when present: `intent/<change>/intent.md` → `spec.md` → `plan.md`. This repo may not have that chain until onboarding intents land.
- Do not commit real backup paths, hostnames, personal folder names, WireGuard keys, tunnel addresses, endpoints, ports, or 1Password item URIs in tests, fixtures, or templates (use the placeholder tokens).
- Do not install the binary into `~/Backups` or `~/Backups/bin/backup-folder` from CI or agent work unless an intent explicitly says so.
- Do not copy `drop-box-watcher` into `~/bin`, write the real watcher config, or load `com.nikolaybotev.drop-box-watcher` from CI or agent work. Follow [`README.md`](README.md) on your Mac when a release pin exists in `~/.config/backup-folder/pins.txt`.

## Architecture

- `Sources/backup-folder/main.swift` is the CLI entry point. `BackupConfig.swift` reads the job config. `FolderJob.swift` runs one task per folder; a folder status does not cancel its siblings (each returns 0, 1, or 2, and the process exit is the maximum). `Retention.swift`, `PathCheck.swift`, and `WalkPolicy.swift` in the same directory hold retention rules, path containment, and directory cycle detection during the clone walk. `Package.swift` and `scripts/build.sh` produce both `backup-folder` and `drop-box-watcher`. `ToolConfig` (`Sources/ToolConfig/`) is the shared TOML subset and permission check. `backup-folder` and `drop-box-watcher` depend on it.
- `drop-box-watcher/` holds the watcher binary sources; `drop-box-watcher.example.toml` and `launchd/drop-box-watcher.plist.template` are install placeholders only. Real config and the routine key stay on the Mac at `~/.config/drop-box-watcher/config.toml` (mode `0600`).
- One LaunchAgent, label `com.nikolaybotev.backup`, runs hourly at minute 0 and reads `~/.config/backup-folder/config.toml` (source and destination pairs). `launchd/backup-folder.plist.template` is that agent (`backup-folder --config` and `/ABS/PATH/TO/HOME/.config/backup-folder/config.toml`). Loading it is manual on a Mac.
- `launchd/com.wireguard.wg0.plist.template` and `launchd/wg0.conf.template` are WireGuard placeholders only. Never commit a WireGuard key, endpoint, tunnel address, or 1Password item URI in git; fill them from 1Password at install time.
- Agents do not load LaunchAgents, run `launchctl`, or write under `~/Backups`.
- `mise.toml` pins Swift for Linux editing in Cloud Agents only.

## Things agents get wrong

- Do not run bare `swift build` for product binaries; use `bash scripts/build.sh` on macOS.
- Do not add a Linux CI job that type-checks or links `Sources/backup-folder/main.swift`; the existing `linux` job runs `tests/linux-unit.sh`, the retention unit tests, the path tests, and the folder-job `swiftc -parse-as-library` test, and it does not compile `Sources/backup-folder/main.swift`.
- Do not claim a GitHub release was published unless the `publish` job on a push to `main` succeeded.
- Squash-merge subjects on `main` must end with `(#N)`. Without that suffix, `scripts/release-version.sh` exits non-zero and job `publish` fails.
- Do not create or change branch protection rulesets in GitHub; branch protection is managed outside this repo with `gh`.
- Cloud Agents on Linux can parse and edit the source but cannot execute `clonefile`, APFS clones, or `launchctl`.
- Agents do not run [`docs/setup.md`](docs/setup.md) or [`docs/restore.md`](docs/restore.md) on a live Mac, do not run `scripts/install-tools.sh` against a live home, and do not run `launchctl` on a live Mac.

## Cursor Cloud specific instructions

- `.cursor/environment.json` runs `bash .cursor/install.sh` and `bash .cursor/start.sh`.
- Install puts Swift 6.4 from `mise.toml` on `PATH`, installs `libncurses6` when needed, and installs skills from `nikolaybotev/local-skills` into `~/.cursor/skills-cursor`. `.cursor/install.sh` is only for Cursor Cloud Agent environments. It hardcodes that repository, with no override and no environment variable.
- Start is a no-op; there is no dev server.
