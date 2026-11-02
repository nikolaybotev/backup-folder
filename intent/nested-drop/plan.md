# plan.md — Nested drop

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. An amendment that keeps the goals is written into the spec in the same commit, and the coverage row moves in that commit. An amendment that drops a goal is a cut. A procedure fix that does not contradict the spec is recorded in the plan only.

Build gate: approved 2026-11-02. One build phase. Phase 0 ships in pull request after build.

Merging this design pull request to `main` runs job `publish` in `.github/workflows/release.yml`. With no release label, `scripts/release-version.sh` chooses the next patch tag and may publish a GitHub release of the binaries already on `main`. That is existing behavior, checked 2026-11-02 in that workflow and in `scripts/release-version.sh`. This intent does not change the version scheme. There is no docs-only skip. The build phase is a later pull request; merging that pull request runs the same job again.

## Stops

None. The no-timer rule is already closed in the spec (D2). A macOS smoke that never observes the nested create is a failed check, not a reason to add a sleep on the readiness path.

## This pull request (design only)

Files: `intent/nested-drop/` only.

DoD: `git status --porcelain` is empty after the commit, and `git diff --name-only origin/main` lists only paths under `intent/nested-drop/`. `bash tests/no-secrets.sh` exits 0 and prints `no-secrets: all checks passed`.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `bash tests/linux-unit.sh` | 0 |
| AC2 | `bash tests/linux-unit.sh` readiness rows, and the sleep grep | 0 |
| AC3 | `bash tests/macos-watcher.sh` existing lines | 0 |
| AC4 | `bash tests/macos-watcher.sh` moved-in tree | 0 |
| AC5 | `bash tests/macos-watcher.sh` emptied-folder delete | 0 |
| AC6 | `bash tests/macos-watcher.sh` `level/inner/only.md` | 0 |
| AC7 | `bash tests/setup-docs.sh` and `bash tests/no-secrets.sh` | 0 |

## Phase 0 — Nested scope, smoke, and docs

One pull request. Behavior, tests, and docs land together. Do not split them.

Files: `drop-box-watcher/WatchScope.swift`, `drop-box-watcher/Watcher.swift`, `tests/drop-box-watcher-tests.swift`, `tests/linux-unit.sh`, `tests/macos-watcher.sh`, `README.md`, `docs/setup.md`, `AGENTS.md`.

Do not edit: `drop-box-watcher/Readiness.swift` (behavior), `drop-box-watcher/WebhookNotifier.swift`, `drop-box-watcher/Config.swift`, `drop-box-watcher.example.toml`, `launchd/`, `Sources/`, `scripts/build.sh`, `scripts/release-version.sh`, `scripts/install-tools.sh`, `.github/workflows/release.yml`, `.github/workflows/codeql.yml`, other `intent/` folders, or `Package.swift`. A new Swift file in `drop-box-watcher/` is already part of that target.

1. Add `WatchScope.swift` per spec FR1 and FR2. Foundation only. No sleep, no `Timer`, no `asyncAfter`, no `startDownloadingUbiquitousItem`, no `CoreServices`. The walk root is the watch folder only for an event on the watch folder, the direct-child directory when the event is that directory or anything under it, and the file alone when the event is a direct-child regular file. Candidate order is not part of the contract; tests compare sets of relative paths. Reuse the ignore helpers in `Readiness.swift`. Ignore matches the leaf name only. Do not call snapshot `WalkPolicy`.
2. Change `Watcher.swift` so event rechecks and `startupScan` use that helper. Remove the direct-child gate. The startup call passes `.skipsHiddenFiles`. Event calls pass an empty enumeration option. Keep `readinessDecision`, the coordinated read, the claim triple, and the download request on the candidate files. One pass unions candidates, rechecks each standardized path once, and calls `submit` only when the new claim list is non-empty. Keep the `webhook enqueue files=` log on that path only. `presentedSubitemDidDisappear(at:)` drops that path's claim only. It does not walk and does not submit. A pass drops a claim only when that exact path is gone. The move callback rechecks the new URL through the same scope. Do not change FSEvents flags, latency, queue names, or how `NSFileCoordinator` is constructed.
3. Extend `tests/drop-box-watcher-tests.swift` and call the new test from `main`. Use a temporary directory. Cover a nested file event that returns the other regular files under that top-level child, including a deeper file, and does not return a regular file in a different top-level child; a direct child that does not include siblings; `.DS_Store` inside a subdirectory omitted; a file returned from under a directory whose name matches the ignore list; a symlink to an outside directory not followed; a missing path; a sibling path; the watch-folder walk used at startup; and the `/private` prefix compare. Add `WatchScope.swift` to the `swiftc` line in `tests/linux-unit.sh`. Extend the forbidden-pattern scan so `WatchScope.swift` and `Watcher.swift` reject `Task.sleep`, `usleep`, `sleep(`, `Timer`, and `asyncAfter`, and `WatchScope.swift` also rejects `startDownloadingUbiquitousItem`.
4. Extend `tests/macos-watcher.sh` after the existing `macos-watcher: notify OK` top-level cases and before the config-reload section, on the folder the watcher is already using. Keep every current assertion. For AC4, create the staged tree as a sibling of the real watch directory under the smoke's `$TMPROOT` (the directory `watch-real` lives in), not under `/tmp` beside the symlink. `mv` that subfolder into the real watch directory. That rename stays on one volume even when `$TMPDIR` is not `/tmp`. Assert one new POST by set of names. Assert exactly one new `webhook enqueue` line, and that the line names `a.md`, `b.md`, and `c.md` and does not name `.DS_Store` or the directory. Then `sleep 1` in the harness only and assert that POST count and that enqueue count did not grow. For AC5, delete the three files, remove the emptied directories, `sleep 1` in the harness only, and assert the POST count and the enqueue count did not change. For AC6, create `level/inner/only.md` in the watch folder and assert one new POST of `["only.md"]`. The harness may poll up to 10 seconds, as it does today. Do not add a sleep in Swift. S4 is not a separate fixture.
5. Update `README.md`, the startup-scan sentence in `docs/setup.md`, and the watcher sentences in `AGENTS.md` per spec FR10. State any depth, one nudge for the newly ready files already in that top-level child, the unchanged ignore list, and no nudge when an emptied folder is deleted. In `AGENTS.md`, add the pitfall that a nested regular file is in scope and that a folder drop must not gain a readiness timer. Leave the Manual/Script bullet counts alone.

DoD: Run these on the Phase 0 commit, after steps 3 and 5. `bash tests/linux-unit.sh` exits 0 and prints `linux-unit: OK`. That script fails if the new FR2 cases fail or if `Timer` or `asyncAfter` appears in `WatchScope.swift` or `Watcher.swift`. A tree without those tests is not this phase. `bash tests/setup-docs.sh` and `bash tests/no-secrets.sh` exit 0. `swiftc -parse` is not the check for `Watcher.swift`. The pull request's `macos` and `linux` checks are green. `macos` is green only when `bash tests/macos-watcher.sh` passed, including AC4, AC5, and AC6. A smoke that never sees the nested create fails the job. Do not add a product sleep to make it pass.

### Build notes (Phase 0)

- Directory cycle guard uses `(systemNumber, systemFileNumber)` with a fallback to `deviceIdentifier` when `systemNumber` is absent, so Linux unit tests can walk nested directories (Darwin provides `deviceIdentifier`; Linux exposes `NSFileSystemNumber` as `.systemNumber`).
- Tree walks use `contentsOfDirectory` recursion instead of `FileManager.enumerator` so one bad directory node does not skip an entire subtree via `skipDescendants`. A directory whose device and file number cannot be read is not entered (FR2 / D5). Direct-child detection also treats the configured presenter path as the watch root when it differs from the resolved path.
- macOS smoke polls webhook bodies by set of basenames (order not fixed) and performs folder-drop mutations through the configured watch symlink path so `NSFilePresenter` sees the same volume rename as the config.
