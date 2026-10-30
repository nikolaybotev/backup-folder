# spec.md — honest snapshot

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-29) |
| Status | Draft 1 |
| Stage | 2 · Design |

## 1. Summary

Lines 55–59 of `backup-folder.swift` log a warning when `failures > 0`, then rename the temp directory onto the snapshot name, log `OK`, and exit 0. Lines 64–72 then consider that name. Because the new snapshot is younger than 48 hours, line 68 keeps it and does not mark the day. On a later run, once `age > 48 * 3600`, the oldest name of that calendar day is kept and the later names of that day are deleted. If the incomplete tree is the earliest name of the day, it is the copy that survives until `age > 60 * 86400`. This intent stops a new incomplete tree from receiving a snapshot name. It does not change the age rules, and it does not judge directories already published.

## 2. Goals and non-goals

**Goals**

- G1. `failures > 0` does not call `moveItem`, does not log `OK`, and exits 1.
- G2. The failed run deletes only its own temp directory.
- G3. The failed run does not prune.
- G4. The success path, including a full-copy fallback from the previous intent, still publishes and still prunes.

**Non-goals**

- Do not change the 48-hour or 60-day predicates, the day key, or the oldest-first order.
- Do not detect incomplete trees that already have a snapshot name.
- Do not reap other `.inprogress-*` directories. That waits for the lock in snapshot-identity.
- Do not add new reasons to increment `failures`. The silent `continue` on line 47 stays until clone-walk.
- Do not change snapshot name format.
- Do not read or write `~/Backups` or `~/Backups/bin/backup-folder`. Do not push a `v*` tag.

**Release phasing.** G1–G4 ship in this intent’s only phase.

## 3. Principles

- P1. A directory matching the snapshot-name pattern is a finished snapshot. An unfinished tree keeps the `.inprogress-` prefix until this run deletes it.
- P2. The existing success smoke stays green, including `2 files, 0 full copies` once clone-fallback-visibility has merged.

## 4. Users and scenarios

- One file in the source cannot be copied. The backup directory gains no new snapshot name. The log says the run did not publish. The next successful run is the one retention will see.
- The source copies cleanly, including files that fell back to a full copy. The run still publishes one snapshot and exits 0.

## 5. Functional requirements

1. When `failures > 0` after `cloneTree`, log `ERROR: <n> item(s) failed in <ts>; not publishing`, `removeItem` only this run’s temp path, and exit 1. Do not call `moveItem`. Do not log `OK`. Do not run the prune loop.
2. If that `removeItem` throws, log the error and still exit 1.
3. When `failures == 0`, keep today’s publish: `moveItem` to the snapshot name, log `OK`, then prune. A rename failure still logs `ERROR: rename failed` and exits 1 before prune, as line 56 does now.
4. A successful `copyItem` after a failed `clonefile` is not an item failure. That counter belongs to clone-fallback-visibility.
5. Add a macOS smoke case in a fresh dest. The source contains a subdirectory whose mode is `000`. The run exits 1, the log contains `not publishing`, the log does not contain `OK snapshot`, and the dest has no directory matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$`. The trap restores mode `u+rwx` before deleting the temp dirs.
6. Do not use a FIFO as the failure fixture. `copyItem` on a FIFO can block, and this phase still calls `copyItem` for a non-directory when `clonefile` fails.

## 6. Acceptance criteria

- AC1. The existing success smoke, including the exit-2 cases and `2 files, 0 full copies`, still passes.
- AC2. The new unreadable-directory case exits 1, logs `not publishing`, and leaves no snapshot directory.
- AC3. The `macos` job and the CodeQL job are green. No new Swift file, so the CodeQL `swiftc` line is unchanged.
- AC4. No `v*` tag. No path under `~/Backups`.

## 7. Design decisions

**D1–D8.** Same decisions as [clone-fallback-visibility/spec.md](../clone-fallback-visibility/spec.md). This intent is global phase 2 and starts after that phase is merged.

**D9 — Retention policy is unchanged.** Lines 68–72 already match the README: keep while `age <= 48 * 3600` without marking the day; otherwise delete when `age > 60 * 86400` or the day was already kept; otherwise keep and mark the day. The keeper is the earliest name because the list is sorted ascending. The fix is to not mint a matching name. A second “quality” bit inside retention is rejected.

**D10 — A failed run does not prune.** Today prune runs only after a successful rename (line 56 exits first on rename failure). A copy failure currently publishes and then prunes. After this change a copy failure exits before prune. The next successful publish prunes. That avoids deleting older good snapshots in a run that did not finish its own copy.

**D11 — Delete only this run’s temp.** Line 37 already deletes this run’s `.inprogress-<minute>` at the next start of the same minute. Deleting every `.inprogress-*` here would remove a concurrent run’s tree. Crash leftovers stay until snapshot-identity.

**D12 — Failure fixture.** Mode `000` on a subdirectory fails `contentsOfDirectory` for a non-root runner and increments `failures` through the existing list error. If the `macos` runner can still list that directory, the builder picks another deterministic list or copy failure, records it in this plan’s build notes, and still meets AC2. The fixture is not a FIFO.

## 8. Open questions

None.
