# backup-folder

Small macOS command-line tool that snapshots a folder with APFS copy-on-write clones.

This repo is also the setup hub for the Mac. First-time setup and restore after data loss are documented in [`docs/setup.md`](docs/setup.md) and [`docs/restore.md`](docs/restore.md). The maintainer runs those checklists; CI does not install them on the deployment Mac.

```
backup-folder <src> <dest>
```

Both paths must be absolute. Before creating the backup directory, the tool refuses when the destination is the same as the source or is inside it, comparing lexically normalized paths and symlink-resolved paths (including symlink cycles). It creates `dest` if needed and writes a log at `dest/backup.log`.

Each run clones every file from `src` into a new snapshot directory named `yyyy-MM-dd_HHmmss-<pid>`, with `-2`, `-3`, and so on if that name is already taken. Legacy directories named `yyyy-MM-dd_HHmm` from before this naming change are still recognized for retention. Cloning is file by file (`clonefile` with `CLONE_NOFOLLOW`) because a whole-directory clone is refused inside iCloud-managed folders. Each file is an APFS copy-on-write clone, and a normal copy is used if cloning that file fails; the log records when a file was stored as a full copy. The snapshot is built in a temporary `.inprogress-<name>` directory and renamed into place when every item succeeded.

If another run is already walking or pruning the same `dest`, the tool logs `skipped; dest busy` and exits without starting a new walk. Stale `.inprogress-*` directories under `dest` are removed only while the dest lock is held.

The tool does this in-process and does not shell out, so a Full Disk Access grant applies to this binary only.

## Build

On macOS:

```
swiftc -O -o backup-folder backup-folder.swift
```

## Retention

After each snapshot the tool prunes `dest`, considering snapshot directories in chronological order. Both `yyyy-MM-dd_HHmm` and `yyyy-MM-dd_HHmmss-<pid>` names are candidates:

- Every snapshot from the last 48 hours is kept.
- After that, one snapshot per day is kept for 60 days (the earliest that day).
- Anything older than 60 days is deleted, as is any extra snapshot on a day that already has its daily keeper.

## How it runs

Run one LaunchAgent per folder. Each agent invokes `~/bin/backup-folder` hourly at minute 0 with that folder's source and home-mirrored backup directory. The template label is `com.nikolay.backup.NAME` (replace `NAME`, `USER`, `/ABS/SOURCE`, and `/ABS/BACKUP-DIR` in [`launchd/backup-folder.plist.template`](launchd/backup-folder.plist.template)). Copy the filled plist to `~/Library/LaunchAgents/` and load it with `launchctl bootstrap gui/$(id -u)`. Loading agents on the Mac is manual; CI does not install them.

## macOS for a real build and test

`clonefile` and `launchd` are macOS-only, so building a binary that can take snapshots and scheduling it needs a Mac.

Cloud agents boot the default image and run [`.cursor/install.sh`](.cursor/install.sh). That installs `libncurses6` (the Swift Linux toolchain needs `libncurses.so.6`, `libform.so.6`, and `libpanel.so.6`), then [mise](https://mise.jdx.dev/) and the Swift release pinned in [`mise.toml`](mise.toml). The Linux toolchain can read and edit this file. It cannot APFS-clone files or load a LaunchAgent.

## drop-box-watcher

`drop-box-watcher` watches one folder (the deployment Mac's iCloud **Drop Box** folder on Desktop; Apple's iCloud exclude list uses the name `Dropbox`, which is not this folder). When a file is fully present on disk, it POSTs a nudge to a Grok Bot routine webhook. The deployment Mac lists the folder and moves files; the watcher does not.

Example config: [`drop-box-watcher.example.toml`](drop-box-watcher.example.toml). LaunchAgent template: [`launchd/drop-box-watcher.plist.template`](launchd/drop-box-watcher.plist.template) (label `com.nikolay.drop-box-watcher`).

**Manual install on a Mac (the maintainer or the deployment Mac; not CI or cloud agents):**

1. Put the release or locally built binary at `$HOME/bin/drop-box-watcher`.
2. Copy the example config to `$HOME/.config/drop-box-watcher/config.toml`, replace every `/ABS/PATH/TO/HOME` placeholder with your absolute home path, set the real webhook URL and routine key, and run `chmod 0600` on that file. Keep this directory outside iCloud Desktop and Documents and outside `~/Backups`.
3. Copy the filled plist to `$HOME/Library/LaunchAgents/com.nikolay.drop-box-watcher.plist`, replacing the same absolute-path placeholders (including the binary, config, and log paths in `ProgramArguments`, `StandardOutPath`, and `StandardErrorPath`).
4. Load the agent: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nikolay.drop-box-watcher.plist`.

The first run may prompt for Desktop folder access. Merging to `main` does not publish a binary; the maintainer pushes a `v*` tag when a GitHub release should exist. CI and agents do not copy the binary into `~/bin`, write the real config, or load this LaunchAgent.
