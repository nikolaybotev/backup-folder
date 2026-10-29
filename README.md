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

Run one hourly LaunchAgent per folder. Each agent invokes this binary with that folder's source and backup directory. A template with placeholder paths is in [`launchd/backup-folder.plist.template`](launchd/backup-folder.plist.template). Copy it to `~/Library/LaunchAgents/`, replace the placeholders, and load it with `launchctl`.

## macOS for a real build and test

`clonefile` and `launchd` are macOS-only, so building a binary that can take snapshots and scheduling it needs a Mac.

Cloud agents use the Linux image in [`.cursor/environment.json`](.cursor/environment.json) (Swift toolchain on Ubuntu) to read, edit, and type-check. That image cannot APFS-clone files or load a LaunchAgent.
