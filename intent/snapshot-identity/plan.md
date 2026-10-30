# plan.md — snapshot identity

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

Global phases 3 and 4 of 6. Start phase 0 after honest-snapshot phase 0 is merged. Start phase 1 after this phase 0 is merged.

## Stops

None.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `swiftc -o retention-tests Retention.swift tests/retention-tests.swift && ./retention-tests` | 0 |
| AC2 | `macos` smoke with the old `_[0-9]{4}$` filter; CodeQL compiles both Swift files | 0 |
| AC3 | Linux tests of both name forms; macOS second run and busy-lock skip | 1 |
| AC4 | diff has no tag, no `~/Backups` path, and no protect-main edit | 0, 1 |

## Phase 0 — Extract retention, keep minute names

Files: `Retention.swift`, `tests/retention-tests.swift`, `backup-folder.swift`, `tests/macos-smoke.sh`, `.github/workflows/test.yml`, `.github/workflows/release.yml`, `.github/workflows/codeql.yml`, `AGENTS.md`.

1. Add `Retention.swift` (Foundation only, no top-level executable code) implementing the current keep-or-delete rules for old names. `backup-folder.swift` stays the only main in the binary compile. Wire it to the new file. Keep generating `yyyy-MM-dd_HHmm`. Do not add the lock yet.
2. Add `tests/retention-tests.swift`, a `swiftc` main that exits non-zero on failure, covering the boundary and non-candidate cases in spec requirement 12 for old names. An unknown newer-shaped string is not a candidate in this phase.
3. Add a `linux` job to `.github/workflows/test.yml` on `ubuntu-latest` with `timeout-minutes: 30`. Install Swift from the checkout with mise and `libncurses6`, using `mise.toml`. Do not `cd /workspace`. Do not run `.cursor/install.sh`. Compile and run the retention tests only. Do not pass `backup-folder.swift` to that `swiftc`.
4. Change the `swiftc -O -o backup-folder` line in `tests/macos-smoke.sh`, `.github/workflows/release.yml`, and `.github/workflows/codeql.yml` to compile `backup-folder.swift` and `Retention.swift`. Leave the CodeQL runner `macos-26`. Leave the smoke name filter unchanged.
5. Update `AGENTS.md` in this same change: the build command lists both files, the Linux job exists and does not compile `backup-folder.swift`, and the CodeQL bullet points at `.github/workflows/codeql.yml` instead of saying CodeQL is not enabled.
6. Do not edit the protect-main script. Do not push a tag.

DoD: local `swiftc -o retention-tests Retention.swift tests/retention-tests.swift && ./retention-tests` exits 0, and `swiftc -parse backup-folder.swift` exits 0. The pull request’s `macos` job, `linux` job, and CodeQL job are green.

### Build notes (Phase 0)

- **`linux` job already present.** PR #12 merged before this phase; step 3’s “add a `linux` job” was satisfied by the existing `ubuntu-latest` job running `tests/linux-unit.sh`. This phase adds a **Retention unit tests** step on that job and raises its timeout from 20 to 30 minutes.
- **`AGENTS.md` CodeQL bullet.** Left unchanged (CodeQL already documented on `main`); only the macOS build line and the `linux` job description were updated per coordinator instruction.
- **Names and lock unchanged.** Phase 0 keeps `yyyy-MM-dd_HHmm` names and does not add `.backup-folder.lock` (phase 1).

## Phase 1 — Unique names, lock, and reap

Files: `Retention.swift`, `tests/retention-tests.swift`, `backup-folder.swift`, `tests/macos-smoke.sh`, `tests/hold-lock.swift`, `README.md`, `AGENTS.md` if a command changes.

1. Extend the candidate rules and the sort as in spec requirements 5 and 6. Update the Linux tests so a new-form name is a candidate, including one old name and one new name in the same minute. Impossible dates stay non-candidates.
2. Format the stamp with `en_US_POSIX` and `TimeZone.current`. Choose `<stamp>-<pid>` and the `-2`, `-3` fallbacks. Create the temp directory without a prior `removeItem`, after the locked reap.
3. Take `flock(LOCK_EX|LOCK_NB)` on `dest/.backup-folder.lock` for the whole run. On `EWOULDBLOCK`, log `skipped; dest busy` and exit 0 without deleting temps.
4. While holding the lock, reap direct children named `.inprogress-*`, then walk. On failure, delete only this run’s temp. On success, `moveItem` to the final name.
5. Update the smoke directory filter to the new name form and to the old form. After the first success assertions, run the tool again and expect exactly two snapshot directories with different names and the same fixture contents. Add `tests/hold-lock.swift` (Darwin `flock`, compiled only by the smoke script) to hold the lock and assert the skip. The skip must return inside the 20-minute job; it is non-blocking.
6. Update the README name and retention sentences so both name forms are described and a busy dest skips. Update `AGENTS.md` if the smoke command or the name pattern it documents changed.

DoD: the Linux retention command exits 0. The pull request’s `macos`, `linux`, and CodeQL jobs are green. The smoke echo is still `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`.

### Build notes (Phase 1)

Added only after the phase lands.
