# backup-folder

Small macOS command-line tool that snapshots a folder with APFS copy-on-write clones.

```
backup-folder <src> <dest>
```

Both paths must be absolute. The tool strips a trailing slash, then refuses to run if `dest` is the same as `src` or is inside `src`. It creates `dest` if needed and writes a log at `dest/backup.log`.

Each run clones every file from `src` into a new snapshot directory named `yyyy-MM-dd_HHmm`. Cloning is file by file (`clonefile` with `CLONE_NOFOLLOW`) because a whole-directory clone is refused inside iCloud-managed folders. Each file is an APFS copy-on-write clone, and a normal copy is used if cloning that file fails. The snapshot is built in a temporary `.inprogress-<timestamp>` directory and renamed into place when the walk finishes.

The tool does this in-process and does not shell out, so a Full Disk Access grant applies to this binary only.

## Build

On macOS:

```
swiftc -O -o backup-folder backup-folder.swift
```

## Retention

After each snapshot the tool prunes `dest`, considering snapshot directories in chronological order:

- Every snapshot from the last 48 hours is kept.
- After that, one snapshot per day is kept for 60 days (the earliest that day).
- Anything older than 60 days is deleted, as is any extra snapshot on a day that already has its daily keeper.

## How it runs

Run one LaunchAgent per folder. Each agent invokes `~/bin/backup-folder` hourly at minute 0 with that folder's source and home-mirrored backup directory. The template label is `com.nikolay.backup.NAME` (replace `NAME`, `USER`, `/ABS/SOURCE`, and `/ABS/BACKUP-DIR` in [`launchd/backup-folder.plist.template`](launchd/backup-folder.plist.template)). Copy the filled plist to `~/Library/LaunchAgents/` and load it with `launchctl bootstrap gui/$(id -u)`. Loading agents on the Mac is manual; CI does not install them.

## macOS for a real build and test

`clonefile` and `launchd` are macOS-only, so building a binary that can take snapshots and scheduling it needs a Mac.

Cloud agents boot the default image and run [`.cursor/install.sh`](.cursor/install.sh). That installs `libncurses6` (the Swift Linux toolchain needs `libncurses.so.6`, `libform.so.6`, and `libpanel.so.6`), then [mise](https://mise.jdx.dev/) and the Swift release pinned in [`mise.toml`](mise.toml). The Linux toolchain can read and edit this file. It cannot APFS-clone files or load a LaunchAgent.
