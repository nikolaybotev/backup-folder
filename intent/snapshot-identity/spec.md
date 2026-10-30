# spec.md — snapshot identity

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-29) |
| Status | Draft 1 |
| Stage | 2 · Design |

## 1. Summary

Lines 33–37 format `yyyy-MM-dd_HHmm` with a `DateFormatter` that sets neither locale nor time zone, use that string for both `.inprogress-<ts>` and the final directory, and `removeItem` the temp path on every start. Two runs in that minute share the path: the second deletes the first’s tree, and a `moveItem` onto an existing final name fails and leaves the temp behind. The plist’s `StartInterval` is 3600, so a repeated local hour can format two starts to the same minute. Line 64 admits only `^\d{4}-\d{2}-\d{2}_\d{4}$`. Line 66 uses the same formatter’s `date(from:)`. On Swift 6.4.1 Linux (locale `en_001`, zone `Etc/UTC`, `isLenient == false`) that formatter parsed `2026-10-29_1200` and returned nil for `2026-10-29_120000`, `2026-10-29_120000-99`, `2026-99-99_9999`, `2026-10-29_1260`, and `2026-02-31_0000`. A nil parse hits `continue` and the directory is never deleted. This intent gives each run a unique name, refuses to start a second walk while one holds the dest, and teaches retention both name shapes in the same change that starts writing the new shape.

## 2. Goals and non-goals

**Goals**

- G1. Publish names of the form `yyyy-MM-dd_HHmmss-<pid>` with an extra `-<n>` only when that name is taken. Format them with locale `en_US_POSIX`.
- G2. Retention keeps today’s 48-hour and 60-day decisions for old `yyyy-MM-dd_HHmm` names and applies the same decisions to the new names.
- G3. A run holds a non-blocking exclusive lock on `dest/.backup-folder.lock` for the whole walk and prune. A busy dest logs a skip and does not delete a temp directory.
- G4. Stale `.inprogress-*` directories are removed only while that lock is held.
- G5. The decision function is Darwin-free and tested on Linux. The `macos` smoke stays green at every phase.

**Non-goals**

- Do not store a time-zone offset in the name. An ambiguous civil time can be off by one hour when it is parsed back. The suffix still makes the directory unique.
- Do not change the 48-hour or 60-day numbers.
- Do not make the Linux job a required ruleset check, and do not edit the protect-main script.
- Do not read or write `~/Backups` or `~/Backups/bin/backup-folder`. Do not push a `v*` tag.

**Release phasing.** Phase 0 extracts the current decisions and does not change names. Phase 1 writes the new names, the lock, and the reap. Both are this intent. Neither ships without the other staying mergeable: phase 1 is the one that changes names, and it updates the parser in that same pull request.

## 3. Principles

- P1. A name this program does not understand is left in place.
- P2. The lock is taken before any `removeItem` of a temp directory.
- P3. `backup-folder.swift` is not compiled on the Linux job.

## 4. Users and scenarios

- Two starts in the same minute get two directories. The first tree is still there after the second finishes.
- A start while a run holds the lock does not walk and does not delete `.inprogress-*`.
- A directory named `yyyy-MM-dd_HHmm` from before this change is still pruned on the same ages as today.
- A crashed run’s `.inprogress-*` directory is removed by the next run that acquires the lock.

## 5. Functional requirements

1. Phase 0 moves the keep-or-delete decision into a new file `Retention.swift` that imports Foundation only. `backup-folder.swift` calls it. Generated names stay `yyyy-MM-dd_HHmm`. The smoke filter `_[0-9]{4}$` stays.
2. The decision, for candidate names, oldest instant first, is the current loop. `age <= 48 * 3600`: keep, and do not mark the day. Else if `age > 60 * 86400` or the day is already marked: delete. Else: keep and mark the day. The day is the ten-character `yyyy-MM-dd` prefix. Constants are `48 * 3600` and `60 * 86400`.
3. A name that is not a candidate is omitted. Omitting it means the binary does not delete it. Non-candidates include `.inprogress-*`, `backup.log`, `.backup-folder.lock`, and any string that is not an old or, in phase 1, a new snapshot name. An old name with an impossible date (`2026-99-99_9999`, `2026-02-31_0000`, `2026-10-29_1260`) is not a candidate. Do not let a date parser roll those into a real day.
4. Phase 0 candidates are only `^\d{4}-\d{2}-\d{2}_\d{4}$` with a real calendar date and a valid hour and minute. Seconds are 0. Tests pass an explicit `TimeZone` and an explicit `now`.
5. Phase 1 candidates add `^\d{4}-\d{2}-\d{2}_\d{6}(-\d+)+$` with a valid hour, minute, and second. The instant uses the six time digits. The `-<digits>` groups do not change the instant. Sort by instant, then by full name.
6. Phase 1 formats the stamp with `DateFormatter`, locale `en_US_POSIX`, `timeZone` `TimeZone.current`, and `dateFormat` `yyyy-MM-dd_HHmmss`. The final name is `<stamp>-<pid>`. If `dest/<name>` or the temp path exists, try `<stamp>-<pid>-2`, `-3`, and so on. The temp path is `dest/.inprogress-<name>`.
7. Create the temp directory with `createDirectory` on that exact path. Do not `removeItem` a temp path before that create, except for the stale reap in requirement 9.
8. The lock file is `dest/.backup-folder.lock`. Take `flock` with `LOCK_EX|LOCK_NB` before the reap and hold it through publish or failure cleanup and through prune. If the lock is busy (`EWOULDBLOCK`), log `skipped; dest busy`, do not remove any temp, do not log `OK`, and exit 0. Any other lock failure exits 1.
9. While holding the lock, remove directories directly under `dest` whose names start with `.inprogress-`. Do not remove the lock file, `backup.log`, or snapshot directories. Then create this run’s temp directory.
10. On publish, `moveItem` the temp path to `dest/<name>`. `moveItem` does not replace an existing directory. If it throws, log `ERROR: rename failed`, exit 1, and leave the temp for the next locked reap.
11. A failed walk still follows honest-snapshot: no `moveItem`, no `OK`, exit 1, and delete only this run’s temp. That delete happens while the lock is held.
12. Linux tests cover requirement 2 at the exact boundaries `48 * 3600`, `48 * 3600 + 1`, `60 * 86400`, and `60 * 86400 + 1`; two names on one day both older than 48 hours; a name inside 48 hours that must not cause an older sibling of that day to be dropped; a negative age; an impossible date; and, in phase 1, one old name and one new name in the same minute.
13. The macOS smoke, after phase 1, still accepts one successful run as one directory, then runs the tool again and expects a second directory with a different name. A held lock produces `skipped; dest busy`, exit 0, and no extra directory.

## 6. Acceptance criteria

- AC1. Phase 0: `swiftc -o retention-tests Retention.swift tests/retention-tests.swift && ./retention-tests` exits 0 on Linux. `backup-folder.swift` is not in that compile.
- AC2. Phase 0: `bash tests/macos-smoke.sh` still expects `_[0-9]{4}$` and passes. The Actions `macos` job and the CodeQL job are green. CodeQL, `release.yml`, and the smoke script compile `backup-folder.swift` and `Retention.swift`.
- AC3. Phase 1: the Linux tests cover old and new names and exit 0. Two sequential macOS runs produce two directories. A busy lock skips. The smoke echo is unchanged.
- AC4. No `v*` tag. No path under `~/Backups`. The Linux job is not added to the ruleset.

## 7. Design decisions

**D1–D8.** Same decisions as [clone-fallback-visibility/spec.md](../clone-fallback-visibility/spec.md). Phase 0 of this intent is global phase 3. Phase 1 is global phase 4.

**D9 — Parser and name format land together.** A Linux `DateFormatter` with `yyyy-MM-dd_HHmm` returned nil for a six-digit time and for a suffixed name (Swift 6.4.1, 2026-10-30). Line 66 would then keep those directories forever. Phase 1 updates the candidate rules in the same pull request that starts writing the new names. Phase 0 does not write the new names, so the old smoke filter remains the guard.

**D10 — Do not sort the mixed forms as bare strings.** Compare parsed instants, then the full name. The day key stays the ten-character prefix, which both forms share.

**D11 — The lock does not wait.** `StartInterval` is 3600 and launchd can start another process while one is running. A blocking lock would pile up processes. A skip exits 0 because the holder is the backup for that dest. The log line is not `OK snapshot`.

**D12 — Locale pin.** The source never sets `locale` or `timeZone` on the name formatter. Phase 1 sets `en_US_POSIX` and `TimeZone.current` so the stamp stays digits. This VM’s formatter reported locale `en_001`; a 12-hour rewrite was not observed here. The pin is so the name stays inside the regex, not because a rewritten name was seen.

**D13 — Linux Swift install.** `.cursor/install.sh` runs `cd /workspace`, which is not the GitHub checkout. The Linux job installs mise and `libncurses6` from the checkout and uses the `swift = "6.4"` pin in `mise.toml`. It does not install skills. Job timeout is 30 minutes. It is not a required check.

## 8. Open questions

None.
