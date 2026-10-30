# Review instructions

## Passes

Run three passes and tag each finding with its pass:

- **Bugs:** a published snapshot that is incomplete, collided, or the wrong tree. The current program does this in `/workspace/backup-folder.swift`:
  - Lines 55–59 log `WARNING` when `failures > 0`, then `moveItem` the temp directory to `dest/<yyyy-MM-dd_HHmm>`, log `OK snapshot`, and fall off the end (exit 0). Retention then runs.
  - Lines 33–37 name the snapshot and the temp directory to the minute and `removeItem` that temp path at the start of every run. There is no lock and no check that `dest/<ts>` is free.
  - Lines 64–72 keep every name matching `^\d{4}-\d{2}-\d{2}_\d{4}$` while `age <= 48 * 3600`, then keep the oldest remaining name of that `yyyy-MM-dd` and delete the later ones, until `age > 60 * 86400`. An incomplete directory that was published under that pattern becomes the daily keeper when it is the earliest name of its day past 48 hours. The publishing run itself does not elect it: the new name is only seconds old, so line 68 keeps it and does not mark the day. A later run does.
  - Lines 49–51: `clonefile(...) != 0` then a successful `copyItem` logs nothing and does not increment `failures`. The run still logs `OK`.
  - Lines 12–15 strip one trailing slash, then refuse only when `dest == src` or `dest.hasPrefix(src + "/")`. Measured with those two lines on Swift 6.4.1: source `/` becomes `""` and is refused; source `//`, source `/data/photos//`, and dest `/data/foo/../photos/backup` are accepted. `/tmp/foo` against `/tmp/foobar` is accepted, which is the correct string result and must stay allowed after normalization.
  - Lines 46–48 treat `fileExists(_:isDirectory:)` as a directory walk. Apple’s documentation for that method says a final symbolic link is traversed and `isDirectory` reflects the target. `CLONE_NOFOLLOW` is only on the non-directory branch (line 49). There is no visited set. Line 47 `else { continue }` drops a missing path without incrementing `failures`.
- **Security:** no backup paths, hostnames, or personal folder names in tests or fixtures. No network calls, no new dependencies, no `Package.swift`. Do not read or write `~/Backups` or `~/Backups/bin/backup-folder`. Path handling that lets `dest` sit inside `src` after `..` or an extra slash is a security finding because the walk copies the backup into itself.
- **Compliance:** the change matches the spec and plan for its intent, and `AGENTS.md`. A departure from the plan that is not written back into `plan.md` in the same change is a compliance finding. The `macos` job must stay green. A phase that changes snapshot names without updating the `_[0-9]{4}$` filter in `tests/macos-smoke.sh` fails compliance. A phase that adds a Swift file to the binary without updating the `swiftc` line in `tests/macos-smoke.sh`, `.github/workflows/release.yml`, and `.github/workflows/codeql.yml` in that same change fails compliance. These phases do not push a `v*` tag. Do not edit `.github/scripts/protect-main-branch.sh` or `.github/workflows/protect-main.yml`.

## What Important means here

Reserve Important for a published name that is a partial tree, two runs sharing one snapshot path, retention keeping that partial as the day’s keeper, a full copy logged as a plain `OK`, or a walk that enters `dest` or follows a directory symlink. Style and naming are nits.

## Cap the nits

Report at most five nits per review; summarize the rest as a count.

## Do not report

Formatting the CI already enforces, generated files the repo ignores, and wording inside the verbatim prompt block of any `intent.md`.

Do not report “source `/` is accepted.” Line 12 strips the only character of `/`, and line 14 then matches every absolute `dest`. That case is already refused.

Do not ask for a whole-directory `clonefile`. The comment on lines 38–39 says a directory clone is refused inside iCloud-managed folders, and the macOS runner cannot prove that case.
