# plan.md — Drop Box watcher

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 2 |
| Status | Draft 2 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

Build phases are Composer 2.5, one phase per pull request, opened ready for review. The coordinator squash-merges a phase only when its required checks are green. A phase does not merge itself. Do not push a `v*` tag. Do not install or load anything on the deployment Mac. Do not edit `backup-folder.swift`, `tests/clonefile-probe.swift`, `tests/macos-smoke.sh`, `launchd/backup-folder.plist.template`, or any intent directory other than this one. Do not edit the CodeQL sentence in `AGENTS.md`. Branch protection is outside this intent.

`swiftc -parse` does not typecheck the Darwin watcher. The macOS CI build does.

## Stops

Phase 1 stops if the macOS runner never delivers a local create to either trigger. AC6 still requires one nudge for `note.txt`, unchanged bytes, no nudge for `.DS_Store`, and a second nudge after the file grows. Record the evidence in that phase's build notes and leave the phase unfinished. Do not add a sleep on the readiness path. A script that exits 0 on the build and the exit-2 checks alone is not Phase 1 done.

The unmeasured FSEvents flags on the deployment Mac are not a stop. [spec.md](spec.md) FR9 keeps both triggers and rechecks every event. AC11 says the implementation PR records that the measurement was not run.

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
2. Add `main.swift`. One config argument. Exit 2 for FR2, FR3, FR4, and a missing watch folder. Hold the watcher and call `dispatchMain()`. `main` enqueues only through `WebhookNotifier`.
3. Add `tests/macos-watcher.sh` for AC6. Build with `swiftc -O` of all seven sources into a temp binary. Assert exit 2 for no arguments and for a mode `0644` config. Start a loopback HTTP server, run the watcher on a non-ubiquitous temp folder whose path may go through a symlink such as `/tmp`, write `note.txt`, and poll up to 10 seconds for one POST whose `files` array is `["note.txt"]` and whose `Authorization` header is `Bearer` plus the test key. Assert the file bytes are unchanged. Write `.DS_Store` and assert it is not named. Append to `note.txt` and assert a second POST. The poll is harness-only. The script exits non-zero when that create never arrives. Print `macos-watcher: build OK, notify OK, unchanged OK` only after those posts.
4. Point the `macos` job at `bash tests/macos-smoke.sh`, then `bash tests/macos-watcher.sh`, then `bash tests/linux-unit.sh`. Leave `tests/macos-smoke.sh` unchanged, including its success line (AC7).
5. Extend the CodeQL manual build with the same `swiftc -O -o drop-box-watcher` file list (AC8). Keep the job name `CodeQL (Swift)`.
6. Gitignore the `drop-box-watcher` binary the way `backup-folder` is gitignored.
7. Extend `tests/linux-unit.sh` so the `Watcher.swift` sleep grep from AC5 runs now that the file exists.
8. Update `AGENTS.md` with the `swiftc` build line and the `macos-watcher` success line. Leave the CodeQL sentence unchanged.

The PR body states that the deployment Mac iCloud measurement was not run and that the agent did not install the tool (AC11). It does not invent flags or callbacks. Do not add a sleep on the readiness path to make the smoke pass.

DoD: `bash tests/macos-watcher.sh` exits 0 on macOS and prints `macos-watcher: build OK, notify OK, unchanged OK`, which means AC6 happened: one nudge for `note.txt`, unchanged bytes, no nudge for `.DS_Store`, and a second nudge after the file grows. If the runner never delivers the create, that is the stop above: record the evidence in the build notes and leave the phase unfinished. `bash tests/macos-smoke.sh` still prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. On a Linux builder, before opening the PR, `bash tests/linux-unit.sh` exits 0. The phase is not done until the `macos` check on the pull request is green because that smoke passed.

## Phase 2 — Install surface and release asset

Files: `launchd/drop-box-watcher.plist.template`, `drop-box-watcher.example.toml`, `README.md`, `.github/workflows/release.yml`, `tests/drop-box-watcher-tests.swift`, `tests/linux-unit.sh`, `AGENTS.md`

1. Add the plist template from FR12. Placeholders only.
2. Add `drop-box-watcher.example.toml` from FR3 with placeholder paths and `https://example.invalid/routine` as the URL. Include the ignore list from D11. No secret.
3. Add the README install section from FR13, including the `Dropbox` versus `Drop Box` name, the `launchctl bootstrap` line, the Desktop prompt, and the statements that CI does not install the agent and a merge does not publish a release.
4. Update `release.yml` so the tag build compiles `drop-box-watcher` with the Phase 1 file list and uploads it next to `backup-folder` (AC10). Do not push a tag.
5. Extend the Darwin-free tests so they parse the example file (AC9) and fail unless `release.yml` mentions `drop-box-watcher` and the plist template has the label, `RunAtLoad`, `KeepAlive`, and `ThrottleInterval`, and has no `StartInterval`.
6. Update `AGENTS.md`: both release assets, the manual install path, and the rule that an agent does not copy the binary into `~/bin` or load the agent. Leave the CodeQL sentence unchanged.

DoD: `bash tests/linux-unit.sh` exits 0 and prints `linux-unit: OK`.
