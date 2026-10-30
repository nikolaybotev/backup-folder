# plan.md — Drop Box watcher

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 2 |
| Status | Draft 2 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

Build phases are Composer 2.5, one phase per pull request, opened ready for review. The coordinator squash-merges a phase only when its required checks are green. A phase does not merge itself. Do not push a `v*` tag. Do not install or load anything on Roger. Do not edit `backup-folder.swift`, `tests/clonefile-probe.swift`, `tests/macos-smoke.sh`, `launchd/backup-folder.plist.template`, or any intent directory other than this one. Do not edit the CodeQL sentence in `AGENTS.md`. Branch protection is outside this intent.

`swiftc -parse` does not typecheck the Darwin watcher. The macOS CI build does.

## Stops

Phase 1 stops if the macOS runner never delivers a local create to either trigger. AC6 still requires one nudge for `note.txt`, unchanged bytes, no nudge for `.DS_Store`, and a second nudge after the file grows. Record the evidence in that phase's build notes and leave the phase unfinished. Do not add a sleep on the readiness path. A script that exits 0 on the build and the exit-2 checks alone is not Phase 1 done.

The unmeasured FSEvents flags on Roger are not a stop. [spec.md](spec.md) FR9 keeps both triggers and rechecks every event. AC11 says the implementation PR records that the measurement was not run.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `bash tests/linux-unit.sh` | 0 |
| AC2 | `bash tests/linux-unit.sh` | 0 |
| AC3 | `bash tests/linux-unit.sh` | 0 |
| AC4 | `bash tests/linux-unit.sh` | 0 |
| AC5 | `bash tests/linux-unit.sh` | 0, extended in 1 when `Watcher.swift` exists |
| AC6 | `bash tests/macos-watcher.sh` | 1 |
| AC7 | `bash tests/macos-smoke.sh` via the `macos` job | 1 |
| AC8 | CodeQL manual build compiles `drop-box-watcher` | 1 |
| AC9 | `bash tests/linux-unit.sh` | 2 |
| AC10 | `bash tests/linux-unit.sh` | 2 |
| AC11 | PR text only. No command | 1 |

## Phase 0 — Darwin-free core

Files: `drop-box-watcher/Config.swift`, `drop-box-watcher/Readiness.swift`, `drop-box-watcher/Log.swift`, `drop-box-watcher/WebhookNotifier.swift`, `drop-box-watcher/WebhookHTTP.swift`, `tests/drop-box-watcher-tests.swift`, `tests/linux-unit.sh`, `.github/workflows/test.yml`, `AGENTS.md`

1. Add the five sources. They implement FR3, FR4, FR7's pure decision (a value type, not `URLUbiquitousItemDownloadingStatus`, and no call to `startDownloadingUbiquitousItem`), and FR11. `WebhookHTTP.swift` is the production transport. It imports `FoundationNetworking` only under `canImport`. The notifier depends on a transport and a clock protocol so tests do not sleep and do not open a socket.
2. Add `tests/drop-box-watcher-tests.swift` with the AC1–AC5 cases, including the AC4 case whose failed immediate resend waits 4s. The fake key is a fixed test string, and the log assertion fails if that string appears. The clock records requested delays and returns when the wait is cancelled.
3. Add `tests/linux-unit.sh`. It compiles the five sources plus the test file with `swiftc` into a temp binary, runs it, and prints `linux-unit: OK`. It does not compile `Watcher.swift` or `main.swift`. It exits non-zero on a compiler or test failure. It greps `drop-box-watcher/Readiness.swift` for `Task.sleep`, `usleep`, `sleep(`, and `startDownloadingUbiquitousItem`, and fails if it finds one. It skips the `Watcher.swift` sleep grep until that file exists.
4. Add a job whose id is `linux`, with no separate `name` key, so the check context is `linux`. It runs on `ubuntu-latest` with `timeout-minutes: 20`. `ubuntu-latest` has neither `mise` nor `swiftc`. The job follows `.cursor/install.sh` through `mise install` and `mise reshim` (mise if missing, `libncurses6` when needed, `mise trust`, Swift 6.4 from `mise.toml`). It does not run the skills installer at the end of that script. Then it runs `bash tests/linux-unit.sh`. Leave the `macos` job unchanged in this phase, including `timeout-minutes: 20` and `bash tests/macos-smoke.sh`.
5. Update `AGENTS.md` in the same commit to document `bash tests/linux-unit.sh` only. Do not change the CodeQL sentence. Do not rewrite unrelated lines.

Do not add `Watcher.swift` in this phase. The PR body names the new check context `linux`.

DoD: `bash tests/linux-unit.sh` exits 0 and prints `linux-unit: OK`.

## Phase 1 — Watcher process and macOS proof

Files: `drop-box-watcher/Watcher.swift`, `drop-box-watcher/main.swift`, `tests/macos-watcher.sh`, `.github/workflows/test.yml`, `.github/workflows/codeql.yml`, `.gitignore`, `AGENTS.md`

1. Add `Watcher.swift` for FR5, FR6, FR8, FR9, and FR10, and for the `startDownloadingUbiquitousItem(at:)` call. The watcher applies the Phase 0 decision on every event recheck and on the startup scan. A request-download result makes that one call, logs a thrown error, and does not claim. `presentedSubitemDidDisappear(at:)` only drops claim keys for that path. A direct child is `deletingLastPathComponent().standardizedFileURL` equal to the stored standardized folder URL. The presenter queue is serial and named `drop-box-watcher`. The FSEvents callback dispatches onto that queue before it reads or writes watcher state. `submit` goes through `WebhookNotifier` only, so the queue does not wait for HTTP. A failed `FSEventStreamCreate` is logged and the presenter and scan still run.

**Departure (Phase 1 build):** `NSFileCoordinator.addFilePresenter` must run on the main run loop after `dispatchMain()` is entered. `start()` logs synchronously, then enqueues presenter registration, FSEvents, and the startup scan on `DispatchQueue.main` so the process does not abort before the operational log line is written.
2. Add `main.swift`. One config argument. Exit 2 for FR2, FR3, FR4, and a missing watch folder. Hold the watcher and call `dispatchMain()`. `main` enqueues only through `WebhookNotifier`.
3. Add `tests/macos-watcher.sh` for AC6. Build with `swiftc -O` of all seven sources into a temp binary. Assert exit 2 for no arguments and for a mode `0644` config. Start a loopback HTTP server, run the watcher on a non-ubiquitous temp folder whose path may go through a symlink such as `/tmp`, write `note.txt`, and poll up to 10 seconds for one POST whose `files` array is `["note.txt"]` and whose `Authorization` header is `Bearer` plus the test key. Assert the file bytes are unchanged. Write `.DS_Store` and assert it is not named. Append to `note.txt` and assert a second POST. The poll is harness-only. The script exits non-zero when that create never arrives. Print `macos-watcher: build OK, notify OK, unchanged OK` only after those posts.
4. Point the `macos` job at `bash tests/macos-smoke.sh`, then `bash tests/macos-watcher.sh`, then `bash tests/linux-unit.sh`. Leave `tests/macos-smoke.sh` unchanged, including its success line (AC7).
5. Extend the CodeQL manual build with the same seven-source `swiftc -O` file list (AC8). Keep the job name `CodeQL (Swift)`.

**Departure (Phase 1 build):** The plan originally used `-o drop-box-watcher` at the repo root. The source tree lives in `drop-box-watcher/`, so that output path is a directory and the linker fails. CodeQL writes the binary to `"$RUNNER_TEMP/drop-box-watcher"` instead. Local and macOS smoke builds still use a temp path (see step 3).
6. Gitignore the `drop-box-watcher` binary the way `backup-folder` is gitignored.
7. Extend `tests/linux-unit.sh` so the `Watcher.swift` sleep grep from AC5 runs now that the file exists.
8. Update `AGENTS.md` with the `swiftc` build line and the `macos-watcher` success line. Leave the CodeQL sentence unchanged.

The PR body states that the Roger iCloud measurement was not run and that the agent did not install the tool (AC11). It does not invent flags or callbacks. Do not add a sleep on the readiness path to make the smoke pass.

DoD: `bash tests/macos-watcher.sh` exits 0 on macOS and prints `macos-watcher: build OK, notify OK, unchanged OK`, which means AC6 happened: one nudge for `note.txt`, unchanged bytes, no nudge for `.DS_Store`, and a second nudge after the file grows. If the runner never delivers the create, that is the stop above: record the evidence in the build notes and leave the phase unfinished. `bash tests/macos-smoke.sh` still prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. On a Linux builder, before opening the PR, `bash tests/linux-unit.sh` exits 0. The phase is not done until the `macos` check on the pull request is green because that smoke passed.

### Phase 1 build notes

- **GitHub Actions run 41041102335 (`b855772`):** Build OK; AC6 poll timed out with empty POST log and empty operational log file. The watcher process was still running at cleanup (SIGTERM after the 10s poll). Empty log did not mean a wrong log path: nothing in `start()` wrote on the success path before this fix. Likely bug: smoke `watch_folder` is a `/tmp` symlink while FSEvents paths use the resolved directory, so `isDirectChild` rejected every recheck. Fixed by comparing symlink-resolved parents (FR6). Added one `started watch_folder=…` line so a future no-event stop shows the process reached `start()`.
- **GitHub Actions run 41042980545 (`3a514bf`):** Build OK; still no POST and empty log without `started watch_folder=`. Watcher still alive at cleanup (SIGTERM). Not the planned no-create stop. Startup line was after `startFSEvents()`; log writes did not call `synchronize()`. Harness did not require startup log before the AC6 drop. Fixed by logging first in `start()`, flushing log writes, URL-based watch-folder check in `main`, and harness liveness/startup checks (stderr captured).
- **GitHub Actions run 41044544469 (`13e6680`):** Build OK; watcher died within ~0.3s with empty log, stderr, and stdout. Not the planned no-create stop (no startup line). Cause: `NSFileCoordinator.addFilePresenter` ran synchronously before `dispatchMain()` had started the main run loop, aborting the process without a Swift error line. CodeQL also failed because `tests/build-backup-folder.sh` joined `$ROOT` with an absolute `$RUNNER_TEMP/...` path. Fixed by scheduling presenter/FSEvents/scan on the main queue inside `dispatchMain()`, using absolute `-o` paths in the build script, and printing watcher exit code plus stdout/stderr in the smoke harness.
- **GitHub Actions run 41046141085 (`52b5421`):** Build OK; watcher exit code 2 during startup wait with empty stdout, stderr, and log (no `fputs` text captured). Guard fired before `start()`: `isDirectoryKey` on the symlinked smoke `watch_folder` rejected a valid directory. Fixed with `watchFolderIsDirectory` (symlink + resolved path + `fileExists`), `fflush(stderr)` on every failure path, and matching `ERROR:` lines in the operational log before `exit(2)`.
- **GitHub Actions run 41048226608 (`54a4336`):** Build OK; AC6 poll timed out with empty POST log, empty operational log in diagnostics, and watcher still running (SIGTERM at cleanup). Not the planned no-create stop (no `started watch_folder=` in job output). FSEvents and presenter registration both waited on `DispatchQueue.main.async`; the log kept one long-lived `FileHandle`, so harness `grep`/`cat` on the log path could disagree with what the process had appended. Fixed by path-based append with per-line `synchronize()`, resolving the watch folder for `presentedItemURL`, starting FSEvents synchronously in `start()`, logging `registered file presenter`, and requiring that line in the harness before the AC6 drop.
- **GitHub Actions run 41048955709 (`fd37881`):** Same nudge timeout with empty posts and empty log in diagnostics; registration gate did not fail. The harness used `grep`/`SECONDS` without requiring a non-empty log file, so a wait could not be trusted against an empty path. Fixed by parsing `[log].path` from config and requiring it to equal the harness path, waiting with Python on non-zero byte size and substring match (printing log path and head on success), POSIX `O_APPEND`/`fsync` log writes, an `operational_log path=` line before `start()`, `RunLoop.main.perform` for presenter registration, and main-queue `Task` submission for webhooks.
- **GitHub Actions run 41050433038 (`c8bd11d`):** Log path matched and startup lines appeared (`operational_log path=`, `started watch_folder=`, `fsevents stream started`), then the presenter gate timed out after 5s with no `registered file presenter` line while the process stayed alive. Cause: `RunLoop.main.perform` before `dispatchMain()` does not run on the GCD main run loop that `dispatchMain()` drives, so `registerOnMainRunLoop()` never executed. Fixed by enqueueing registration with `DispatchQueue.main.async` before `dispatchMain()` and logging `registering file presenter` immediately before `addFilePresenter`.
- **GitHub Actions run 41050786016 (`589cfb5`) — planned stop (Phase 1 unfinished):** `linux` and CodeQL (Swift) passed. `macos-watcher` build OK. Operational log path matched config. Harness gates passed on `operational_log path=…`, `started watch_folder=…/watch-real`, `fsevents stream started`, `registering file presenter`, and `registered file presenter` (log stopped at 388 bytes with no delivery lines). After the AC6 drop of `note.txt`, the harness polled 10s with empty POST log; watcher still running at cleanup (exit unknown, then SIGTERM). stdout/stderr empty. This matches the stop in **Stops** above: startup reached `start()` and both triggers were registered, but the Actions runner delivered no local create webhook within the AC6 poll. Do not weaken AC6 or add readiness sleep to pass this runner. Phase 2 must not start until macOS AC6 passes on a runner that delivers the create (or product work resumes with new evidence). A red `macos` job on a plan-only follow-up commit is expected.

## Phase 2 — Install surface and release asset

Files: `launchd/drop-box-watcher.plist.template`, `drop-box-watcher.example.toml`, `README.md`, `.github/workflows/release.yml`, `tests/drop-box-watcher-tests.swift`, `tests/linux-unit.sh`, `AGENTS.md`

1. Add the plist template from FR12. Placeholders only.
2. Add `drop-box-watcher.example.toml` from FR3 with placeholder paths and `https://example.invalid/routine` as the URL. Include the ignore list from D11. No secret.
3. Add the README install section from FR13, including the `Dropbox` versus `Drop Box` name, the `launchctl bootstrap` line, the Desktop prompt, and the statements that CI does not install the agent and a merge does not publish a release.
4. Update `release.yml` so the tag build compiles `drop-box-watcher` with the Phase 1 file list and uploads it next to `backup-folder` (AC10). Do not push a tag.
5. Extend the Darwin-free tests so they parse the example file (AC9) and fail unless `release.yml` mentions `drop-box-watcher` and the plist template has the label, `RunAtLoad`, `KeepAlive`, and `ThrottleInterval`, and has no `StartInterval`.
6. Update `AGENTS.md`: both release assets, the manual install path, and the rule that an agent does not copy the binary into `~/bin` or load the agent. Leave the CodeQL sentence unchanged.

DoD: `bash tests/linux-unit.sh` exits 0 and prints `linux-unit: OK`.
