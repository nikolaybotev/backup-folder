# plan.md — Drop Box watcher

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

Build phases are Composer 2.5, one phase per pull request, opened ready for review. The coordinator squash-merges a phase only when its required checks are green. A phase does not merge itself. Do not push a `v*` tag. Do not install or load anything on Roger. Do not edit `backup-folder.swift`, `tests/clonefile-probe.swift`, `tests/macos-smoke.sh`, `launchd/backup-folder.plist.template`, `.github/scripts/protect-main-branch.sh`, `.github/workflows/protect-main.yml`, or any intent directory other than this one.

`swiftc -parse` does not typecheck the Darwin watcher. The macOS CI build does.

## Stops

None. The unmeasured FSEvents flags are not a gate. [spec.md](spec.md) FR9 keeps both triggers and rechecks every event. AC11 says the implementation PR records that the measurement was not run.

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

1. Add the five sources. They implement FR3, FR4, FR7's decision function (a value type, not `URLUbiquitousItemDownloadingStatus`), and FR11. `WebhookHTTP.swift` imports `FoundationNetworking` only under `canImport`. The notifier depends on a transport and a clock protocol so tests do not sleep and do not open a socket.
2. Add `tests/drop-box-watcher-tests.swift` with the AC1–AC5 cases. The fake key is a fixed test string, and the log assertion fails if that string appears. The clock records requested delays and returns when the wait is cancelled.
3. Add `tests/linux-unit.sh`. It compiles the five sources plus the test file with `swiftc` into a temp binary, runs it, and prints `linux-unit: OK`. It does not compile `Watcher.swift` or `main.swift`. It exits non-zero on a compiler or test failure. It greps `drop-box-watcher/Readiness.swift` for `Task.sleep`, `usleep`, and `sleep(` and fails if it finds one. It skips the `Watcher.swift` grep until that file exists.
4. Add a job whose id is `linux`, with no separate `name` key, so the check context is `linux`. It runs on `ubuntu-latest` with `timeout-minutes: 20`. The job installs `libncurses6` and Swift 6.4 from `mise.toml` (the Ubuntu image has no `swiftc`; do not run `.cursor/install.sh`, which also installs skills). Then it runs `bash tests/linux-unit.sh`. Leave the `macos` job's script as `bash tests/macos-smoke.sh` in this phase.
5. Update `AGENTS.md` in the same commit: document `bash tests/linux-unit.sh`, and correct the CodeQL sentence so it describes `.github/workflows/codeql.yml` (job `CodeQL (Swift)` on `macos-26`). Do not rewrite unrelated lines.

Do not add `Watcher.swift` in this phase. Do not edit the protect-main script. In the PR body, name the new job `linux` and say Nikolay adds it to the ruleset in the GitHub UI if he wants it required. Do not claim the ruleset changed.

DoD: `bash tests/linux-unit.sh` exits 0 and prints `linux-unit: OK`.

## Phase 1 — Watcher process and macOS proof

Files: `drop-box-watcher/Watcher.swift`, `drop-box-watcher/main.swift`, `tests/macos-watcher.sh`, `.github/workflows/test.yml`, `.github/workflows/codeql.yml`, `.gitignore`, `AGENTS.md`

1. Add `Watcher.swift` for FR5, FR6, FR8, FR9, and FR10. The presenter queue is serial and named `drop-box-watcher`. The FSEvents callback dispatches onto that queue before it reads or writes watcher state. `submit` is called so the queue does not wait for HTTP. A failed `FSEventStreamCreate` is logged and the presenter and scan still run.
2. Add `main.swift`. One config argument. Exit 2 for FR2, FR3, FR4, and a missing watch folder. Hold the watcher and call `dispatchMain()`.
3. Add `tests/macos-watcher.sh` for AC6. Build with `swiftc -O` of all seven sources into a temp binary. Assert exit 2 for no arguments and for a mode `0644` config. Start a loopback HTTP server, run the watcher on a non-ubiquitous temp folder, write `note.txt`, and poll up to 10 seconds for one POST whose `files` array is `["note.txt"]` and whose `Authorization` header is `Bearer` plus the test key. Assert the file bytes are unchanged. Write `.DS_Store` and assert it is not named. Append to `note.txt` and assert a second POST. The poll is harness-only. Print `macos-watcher: build OK, notify OK, unchanged OK`.
4. Point the `macos` job at `bash tests/macos-smoke.sh`, then `bash tests/macos-watcher.sh`, then `bash tests/linux-unit.sh`. Leave `tests/macos-smoke.sh` unchanged, including its success line (AC7).
5. Extend the CodeQL manual build with the same `swiftc -O -o drop-box-watcher` file list (AC8). Keep the job name `CodeQL (Swift)`.
6. Gitignore the `drop-box-watcher` binary the way `backup-folder` is gitignored.
7. Extend `tests/linux-unit.sh` so the `Watcher.swift` sleep grep from AC5 runs now that the file exists.
8. Update `AGENTS.md` with the `swiftc` build line and the `macos-watcher` success line.

The PR body states that the Roger iCloud measurement was not run and that the agent did not install the tool (AC11). It does not invent flags or callbacks. If the hosted macOS runner never delivers a local create event to either trigger, record the evidence in this phase's build notes and keep the exit-2 checks. Do not add a sleep to the product to make the smoke pass.

DoD: `bash tests/macos-watcher.sh` exits 0 on macOS and prints `macos-watcher: build OK, notify OK, unchanged OK`. If that script cannot see a local create through either trigger, the phase's build notes record the evidence and the script still exits 0 on the build and the exit-2 checks. `bash tests/macos-smoke.sh` still prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. On a Linux builder, before opening the PR, `bash tests/linux-unit.sh` exits 0. The phase is not done until the `macos` check on the pull request is green.

## Phase 2 — Install surface and release asset

Files: `launchd/drop-box-watcher.plist.template`, `drop-box-watcher.example.toml`, `README.md`, `.github/workflows/release.yml`, `tests/drop-box-watcher-tests.swift`, `tests/linux-unit.sh`, `AGENTS.md`

1. Add the plist template from FR12. Placeholders only.
2. Add `drop-box-watcher.example.toml` from FR3 with placeholder paths and `https://example.invalid/routine` as the URL. Include the ignore list from D11. No secret.
3. Add the README install section from FR13, including the `Dropbox` versus `Drop Box` name, the `launchctl bootstrap` line, the Desktop prompt, and the statements that CI does not install the agent and a merge does not publish a release.
4. Update `release.yml` so the tag build compiles `drop-box-watcher` with the Phase 1 file list and uploads it next to `backup-folder` (AC10). Do not push a tag.
5. Extend the Darwin-free tests so they parse the example file (AC9) and fail unless `release.yml` mentions `drop-box-watcher` and the plist template has the label, `RunAtLoad`, `KeepAlive`, and `ThrottleInterval`, and has no `StartInterval`.
6. Update `AGENTS.md`: both release assets, the manual install path, and the rule that an agent does not copy the binary into `~/bin` or load the agent.

DoD: `bash tests/linux-unit.sh` exits 0 and prints `linux-unit: OK`.
