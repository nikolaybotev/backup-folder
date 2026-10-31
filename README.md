# backup-folder

Small macOS command-line tool that snapshots a folder with APFS copy-on-write clones.

First-time setup and restore after data loss are documented in [`docs/setup.md`](docs/setup.md) and [`docs/restore.md`](docs/restore.md). Run those checklists on your Mac; CI does not install them.

```
backup-folder /abs/source /abs/backup-dir
backup-folder --config /abs/config.toml
```

The two-argument command snapshots one folder and does not read a config file. Paths on that command are absolute. Before creating the backup directory, the tool refuses when the destination is the same as the source or is inside it, comparing lexically normalized paths and symlink-resolved paths (including symlink cycles). It creates `dest` if needed and writes a log at `dest/backup.log`.

Each run clones every file from `src` into a new snapshot directory named `yyyy-MM-dd_HHmmss-<pid>`, with `-2`, `-3`, and so on if that name is already taken. Legacy directories named `yyyy-MM-dd_HHmm` from before this naming change are still recognized for retention. Cloning is file by file (`clonefile` with `CLONE_NOFOLLOW`) because a whole-directory clone is refused inside iCloud-managed folders. Each file is an APFS copy-on-write clone, and a normal copy is used if cloning that file fails; the log records when a file was stored as a full copy. The snapshot is built in a temporary `.inprogress-<name>` directory and renamed into place when every item succeeded.

If another run is already walking or pruning the same `dest`, that destination logs `skipped; dest busy` and does not start a new walk. Other folders in a config job still run. Stale `.inprogress-*` directories under `dest` are removed only while the dest lock is held.

The tool does this in-process and does not shell out, so a Full Disk Access grant applies to this binary only.

## Build

On macOS, build both `backup-folder` and `drop-box-watcher` with:

```
bash scripts/build.sh
```

`SIGN_IDENTITY` is only the local-build switch. When it is set, the script signs with that login-keychain identity. When it is unset, the script ad-hoc signs each binary. Job `publish` does not honor a pre-set `SIGN_IDENTITY`. It always signs with the single identity on the certificate imported from `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD`. CI exports `VERSION=v0.0.0` for the `macos` job and the CodeQL manual build. For a local build, omit `VERSION` so the stamp uses `git describe --tags --dirty`; the script exits non-zero when it cannot determine a version and does not invent `0.0.0`. Stamped `--version` output includes the short git SHA; `--version --verbose` includes the full SHA from `git rev-parse HEAD` and the UTC build time from `date -u +%Y-%m-%dT%H:%MZ`.

## Retention

After each snapshot the tool prunes `dest`, considering snapshot directories in chronological order. Both `yyyy-MM-dd_HHmm` and `yyyy-MM-dd_HHmmss-<pid>` names are candidates.

When the config omits `retention`, the tool uses this built-in policy:

- Every snapshot from the last 48 hours is kept.
- After that, one snapshot per day is kept for 60 days (the earliest that day).
- Anything older than 60 days is deleted, as is any extra snapshot on a day that already has its daily keeper.

The config may set `retention` once at the top level and again on a `[[folder]]` entry as an array of tier strings, for example `retention = ["48h", "1d/60d"]`. A folder entry overrides the file-level list for that folder only. When both are absent, the built-in policy above applies. Each element is either an age (`4h`, `48h`) that keeps every snapshot until that age, or `interval/age` (`15m/8h`, `1d/60d`) that keeps the earliest snapshot in each interval bucket until that age. Units are `s`, `m`, `h`, and `d`.

Example (not the default): `retention = ["4h", "15m/8h", "30m/16h", "1h/24h", "1d/30d"]`. With a snapshot every five minutes, that list holds 117 snapshots per folder (48 + 16 + 16 + 8 + 29).

## How it runs

```
backup-folder /abs/source /abs/backup-dir
backup-folder --config /abs/config.toml
```

The two-argument command snapshots one folder. `--config` reads a file of source and destination pairs and backs up each of them. One LaunchAgent, label `com.nikolaybotev.backup`, runs that command hourly at minute 0. The template is [`launchd/backup-folder.plist.template`](launchd/backup-folder.plist.template). Replace each `/ABS/PATH/TO/HOME` placeholder. A five-minute cadence is launchd `StartInterval` 300 or a `StartCalendarInterval` you write; the template in this repo still starts hourly at minute 0. The example config is [`backup-folder.example.toml`](backup-folder.example.toml). Copy the filled plist to `~/Library/LaunchAgents/` and load it with `launchctl bootstrap gui/$(id -u)`. Loading LaunchAgents on the Mac is manual; CI does not install them. Moving from one agent per folder is described in [`docs/backup-job.md`](docs/backup-job.md).

After an in-place swap of `~/bin/backup-folder` while that agent stays loaded, launchd may refuse the next spawn. Run `launchctl kickstart gui/$(id -u)/com.nikolaybotev.backup` once and check that job's log for a clean run.

## macOS for a real build and test

`clonefile` and `launchd` are macOS-only, so building a binary that can take snapshots and scheduling it needs a Mac.

Cloud agents boot the default image and run [`.cursor/install.sh`](.cursor/install.sh). That installs `libncurses6` (the Swift Linux toolchain needs `libncurses.so.6`, `libform.so.6`, and `libpanel.so.6`), then [mise](https://mise.jdx.dev/) and the Swift release pinned in [`mise.toml`](mise.toml). The Linux toolchain can read and edit this file. It cannot APFS-clone files or load a LaunchAgent.

## drop-box-watcher

`drop-box-watcher` watches one folder (the iCloud **Drop Box** folder on Desktop; Apple's iCloud exclude list uses the name `Dropbox`, which is not this folder). When a file is fully present on disk, it POSTs a nudge to a Grok Bot routine webhook. List the folder and move files; the watcher does not.

Example config: [`drop-box-watcher.example.toml`](drop-box-watcher.example.toml). LaunchAgent template: [`launchd/drop-box-watcher.plist.template`](launchd/drop-box-watcher.plist.template) (label `com.nikolaybotev.drop-box-watcher`).

**Manual install on a Mac (not CI or cloud agents):**

1. Put the release or locally built binary at `$HOME/bin/drop-box-watcher`.
2. Copy the example config to `$HOME/.config/drop-box-watcher/config.toml`, replace every `/ABS/PATH/TO/HOME` placeholder with your absolute home path, set the real webhook URL and routine key, and run `chmod 0600` on that file. Keep this directory outside iCloud Desktop and Documents and outside `~/Backups`.
3. Copy the filled plist to `$HOME/Library/LaunchAgents/com.nikolaybotev.drop-box-watcher.plist`, replacing the same absolute-path placeholders (including the binary, config, and log paths in `ProgramArguments`, `StandardOutPath`, and `StandardErrorPath`).
4. Load the agent: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nikolaybotev.drop-box-watcher.plist`.
5. After an in-place swap of `~/bin/drop-box-watcher` while that agent stays loaded, run `launchctl kickstart -k gui/$(id -u)/com.nikolaybotev.drop-box-watcher` once and check that job's log for a clean run.

The first run may prompt for Desktop folder access. A push to `main` runs job `publish` in `.github/workflows/release.yml`, which can push the next patch tag and publish a GitHub release; agents do not push a tag by hand. CI and agents do not copy the binary into `~/bin`, write the real config, or load this LaunchAgent.
