# plan.md — One backup job

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 2 |
| Status | Draft 2 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

The pull request that adds this folder does not start Phase 0. Phase 0 starts only when someone says to build. Each phase is one branch and one pull request, opened ready for review, with a conventional commit. Build threads for this intent use Grok 4.7 High. A phase does not merge itself. The coordinator squash-merges only when the required checks `macos` and `linux` are both green. A cancelled check is not green. Do not push a `v*` tag. Do not add a release label. Do not install, load, or reload anything. Do not run `launchctl`. Do not write a live config or a live pin. Do not write under a home `Backups` directory.

Merging a phase to `main` runs job `publish`, which may push the next patch tag. That is the existing release workflow. It is not a stop.

## Stops

None.

## This pull request

Files: `intent/one-backup-job/`, and the port-scan exception in `tests/no-secrets.sh`.

On main, the port scan flags every colon-and-digits match, including the minute notation in the captured prompt of `intent/one-backup-job/intent.md`. This pull request ignores that one phrase there, after the Original prompt heading, and nowhere else. A colon and digits in any other file, after any other prefix, or after other whitespace still fails. Do not weaken the address, key, or 1Password item URI checks.

DoD: `bash tests/no-secrets.sh` exits 0 (healthy: `no-secrets: all checks passed`). `git diff --name-only origin/main` lists only this folder and `tests/no-secrets.sh`.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `bash tests/linux-unit.sh`, `bash tests/build-entry-test.sh`, `main.swift` absent from the diff | 0 |
| AC2 | `swiftc` of ToolConfig, BackupConfig, FolderJob, and `tests/folder-job-tests.swift`; `./folder-job-tests` | 1 |
| AC3 | `bash tests/macos-smoke.sh` on the `macos` job | 1 |
| AC4 | `bash tests/no-secrets.sh`, `bash tests/setup-docs.sh` | 1 |
| AC5 | `bash tests/linux-unit.sh`; `bash tests/macos-watcher.sh` on the `macos` job | 2 |
| AC6 | diff does not touch release, CodeQL, or protect-main; timeouts unchanged | 0, 1, 2 |
| AC7 | this pull request | this pull request |

## Phase 0 — Shared TOML subset

Files: `Package.swift`, `Sources/ToolConfig/TomlSubset.swift`, `drop-box-watcher/Config.swift`, `drop-box-watcher/main.swift`, `tests/linux-unit.sh`, `tests/drop-box-watcher-tests.swift`, `tests/build-entry-test.sh`.

Do not edit: `Sources/backup-folder/main.swift`, `Retention.swift`, `PathCheck.swift`, `WalkPolicy.swift`, `launchd/`, `docs/`, `README.md`, `AGENTS.md`, `REVIEW.md`, `scripts/install-tools.sh`, `scripts/ensure-backup-dirs.sh`, `pins.txt.example`, `.github/workflows/release.yml`, `.github/workflows/codeql.yml`, `.github/scripts/protect-main-branch.sh`, `.github/workflows/test.yml` timeouts, or any other `intent/` folder.

1. Add target `ToolConfig`. Settings are per target. Set `-target arm64-apple-macos12.0` and `.swiftLanguageMode(.v5)` on `ToolConfig` itself. Foundation only. `drop-box-watcher` depends on it. `backup-folder` does not yet.
2. Move the scanner and `configPermissionsAcceptable(at:)` into `Sources/ToolConfig/TomlSubset.swift`. Both are `public`. `parseTomlSubset` returns the table in spec requirement 3. The permission predicate is unchanged (spec requirement 4). Delete the function from `Config.swift`. Do not leave a wrapper: `linux-unit.sh` compiles `TomlSubset.swift` and `Config.swift` in one invocation, and a second definition is a duplicate symbol.
3. `drop-box-watcher/Config.swift` keeps `parseConfigTOML`, `loadConfig`, and `ConfigLoadError`. It checks permissions before reading. It maps the document through the current watcher schema. `#if canImport(ToolConfig)` imports the module. `drop-box-watcher/main.swift` uses the same import and calls the public predicate. The stderr line stays `config permissions too open`. `linux-unit.sh` adds `Sources/ToolConfig/TomlSubset.swift` to the existing `swiftc` file list. It does not add `drop-box-watcher/main.swift` (that file imports `BuildStamp`) or `Sources/backup-folder/main.swift`. The `macos` job's `bash scripts/build.sh` is what compiles `drop-box-watcher/main.swift`.
4. Extend `tests/drop-box-watcher-tests.swift`. `parseTomlSubset` accepts an integer and an array of tables, and rejects a float. The watcher schema rejects any integer value and any `[[table]]`. Do not drop the current accept/reject cases or the `0400` permission case.
5. `tests/build-entry-test.sh` requires the `ToolConfig` target name in `Package.swift`. Leave the existing greps in place.

DoD:

```
bash tests/linux-unit.sh
bash tests/build-entry-test.sh
test -z "$(git diff --name-only -- Sources/backup-folder/main.swift)"
```

Healthy lines: `linux-unit: OK`, `build-entry-test: all checks passed`.

### Build notes (Phase 0)

Added only after the phase lands.

## Phase 1 — One backup job

Files: `Sources/backup-folder/main.swift`, `Sources/backup-folder/BackupConfig.swift`, `Sources/backup-folder/FolderJob.swift`, `Package.swift`, `tests/folder-job-tests.swift`, `.github/workflows/test.yml` (one Linux step only), `tests/macos-smoke.sh`, `launchd/backup-folder.plist.template`, `backup-folder.example.toml`, `docs/backup-job.md`, `docs/setup.md`, `docs/restore.md`, `README.md`, `AGENTS.md`, `REVIEW.md`, `tests/no-secrets.sh`, `tests/setup-docs.sh`.

Do not edit: `Retention.swift` decision rules, `drop-box-watcher/` (reload is Phase 2), `scripts/install-tools.sh`, `scripts/ensure-backup-dirs.sh`, `pins.txt.example`, release, CodeQL, protect-main, timeouts, or any other `intent/` folder. Do not add `Sources/backup-folder/main.swift` to a Linux `swiftc` line.

1. `backup-folder` depends on `ToolConfig`. `BackupConfig.swift` implements spec requirement 7. It calls `PathContainment.lexicalNormalize` and does not copy that function. Foundation only, `#if canImport(ToolConfig)`.
2. `FolderJob.swift` implements spec requirements 9 and 10: non-throwing task group, `DispatchQueue.global().async` plus a continuation, no `DispatchQueue.sync`, no semaphore on the cooperative pool, no `cancelAll`, file order, cap. It takes a synchronous runner `(pair) -> Int32`. `aggregate` is the max of the statuses.
3. Refactor the one-folder body in `Sources/backup-folder/main.swift` so every former `exit` is a returned `Int32`, with locals per call (log path, failure count, and that call's formatters). The two-argument command calls it and exits with the status. It does not open the config file, and it still strips only one trailing slash. `--version` and `--version --verbose` stay as they are and win before any other parsing. `--config` requires the next argument to be an absolute path. There is no default path. Any other arguments print usage to stderr and exit 2, and the usage names both forms. `--config` checks `configPermissionsAcceptable` before reading. A missing path is that failure, exit 2, not a separate I/O error. A read that throws after the predicate returned true exits 2 and starts no folder. On schema success the job runs `FolderJob` once. The stderr lock serializes one write per line and is released before `clonefile`. `backup.log` is only that destination's file.
4. Add the Linux step to job `linux` in `.github/workflows/test.yml`, beside the retention step, without changing `timeout-minutes` or job names:

```
swiftc -parse-as-library -o folder-job-tests \
  Sources/ToolConfig/TomlSubset.swift \
  Sources/backup-folder/PathCheck.swift \
  Sources/backup-folder/BackupConfig.swift \
  Sources/backup-folder/FolderJob.swift \
  tests/folder-job-tests.swift
./folder-job-tests
```

`tests/folder-job-tests.swift` uses `@main` and has no top-level code. Checked 2026-10-31: without `-parse-as-library`, that entry point fails to compile. The test covers AC2, including the `..`, double-slash, case-only, and symlink destination cases. A sequential runner must fail the overlap case within a few seconds, not hang until the job cap. The fake runner may block; the product files must not sleep.

5. Extend `tests/macos-smoke.sh` with the AC3 `--config` cases, including containment beside a good folder (exit 2), a busy destination beside a good folder (the busy log is `skipped; dest busy`, the other folder publishes, exit 0), and two symlink paths to one existing directory (exit 2, nothing published). Keep the final echo `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. Use `mktemp` paths and mode `0600` for the valid file. Do not raise the job timeout.
6. Replace `launchd/backup-folder.plist.template` per spec requirement 14. Add `backup-folder.example.toml` and `docs/backup-job.md` per requirements 15 and 16. Rewrite the setup bullet in place (count stays 33). In `docs/restore.md`, change the words "backup-folder agents" in the intro sentence and in the LaunchAgent Script bullet so they mean the one backup agent. Leave the rest of the intro in place, including `wireguard-go`, `does not install Xcode`, `GnuPG`, `Grok Bot`, `1Password CLI`, and `not operators of the machine`. The bullet count stays 7. Update `README.md` "How it runs" to both command lines and the one agent. Human-facing text does not say that success is exit 0.
7. Update the plist assertions in `tests/no-secrets.sh` to the new label and arguments. Keep the assertions that reject `StartInterval`, require `StartCalendarInterval` minute 0 with no `Hour`, and require `RunAtLoad` false. Add assertions that `KeepAlive`, `StandardOutPath`, and `StandardErrorPath` are absent. In `tests/setup-docs.sh`, `grep -F` of `com.nikolaybotev.backup` also matches `com.nikolaybotev.backup.NAME`, so require the new label, `--config`, and the `/ABS/PATH/TO/HOME` placeholders in `docs/setup.md`, and fail if `docs/setup.md` still contains `com.nikolaybotev.backup.NAME`. Require links to `backup-job.md` and `backup-folder.example.toml` there. The old label stays in `docs/backup-job.md`.
8. Update the architecture bullets in `AGENTS.md`: one agent, config path, `ToolConfig`, and that a folder status does not cancel siblings (explicit statuses are appropriate there). Update the Commands CI bullet and the "Things agents get wrong" bullet so the `linux` job runs the folder-job `swiftc` and still does not compile `Sources/backup-folder/main.swift`. Update the `REVIEW.md` Bugs line per spec requirement 19.

DoD, from the repo root, on Linux:

```
swiftc -parse-as-library -o folder-job-tests \
  Sources/ToolConfig/TomlSubset.swift \
  Sources/backup-folder/PathCheck.swift \
  Sources/backup-folder/BackupConfig.swift \
  Sources/backup-folder/FolderJob.swift \
  tests/folder-job-tests.swift
./folder-job-tests
bash tests/linux-unit.sh
bash tests/build-entry-test.sh
bash tests/no-secrets.sh
bash tests/setup-docs.sh
```

The `macos` job runs `bash tests/macos-smoke.sh`. Do not claim that smoke passed unless that job did. Healthy Linux lines include `linux-unit: OK`, `build-entry-test: all checks passed`, `no-secrets: all checks passed`, and `setup-docs: all checks passed`.

### Build notes (Phase 1)

Added only after the phase lands.

## Phase 2 — Watcher reload

Files: `drop-box-watcher/ConfigReload.swift`, `drop-box-watcher/ConfigWatch.swift`, `drop-box-watcher/main.swift`, `drop-box-watcher/Watcher.swift` only if retarget needs a hook, `tests/linux-unit.sh`, `tests/drop-box-watcher-tests.swift`, `tests/macos-watcher.sh`.

Do not edit: `Sources/backup-folder/main.swift`, `Readiness.swift` (no new sleep, no reload logic), the backup plist, `docs/`, release, CodeQL, protect-main, or timeouts. Do not add `Task.sleep`, `usleep`, or `sleep(` to the watcher product sources. The harness may poll, as it already does.

1. `ConfigReload.swift` is Foundation only. Given the current config and a read result, it returns keep-and-log, unchanged, or apply-and-log, per spec requirement 17. `linux-unit.sh` adds only this file to its `swiftc` list. It does not add `drop-box-watcher/main.swift` (that file imports `BuildStamp`), `ConfigWatch.swift`, or `Watcher.swift` (those import `CoreServices`). Tests cover AC5's three decision cases. Reasons do not contain the webhook key or the file body.
2. `ConfigWatch.swift` opens an FSEvents stream on the parent directory, with file-level events, and ignores events for any other file name. It does not use a directory vnode source as the only watch. Re-read by path. A torn read may reject; a later complete read may apply. Mode is checked before the bytes are read. Validation, including the watch directory and opening the new log, finishes before any live setting changes. On failure, log `config reload rejected: <reason>` on the current operational log and do not exit. If that log write fails, write the same line to stderr and still do not exit. Equality is the validated fields, including the webhook key. On equality, do not log and do not retarget. On a real change, write `config reloaded` to the current operational log, then swap watch folder, webhook, ignore list, and log path. Posts already started keep their URL.
3. `tests/linux-unit.sh` greps `ConfigReload.swift` for `Task.sleep`, `usleep`, and `sleep(`, the same way it greps `Readiness.swift`. Do not add those calls to `ConfigWatch.swift` either.
4. Startup is unchanged: the first failure exits 2. After the watch is armed, read once more and pass that read through the same decision.
5. Extend `tests/macos-watcher.sh` per AC5. Keep the three healthy lines `macos-watcher: build OK`, `macos-watcher: notify OK`, and `macos-watcher: unchanged OK`.

DoD on Linux: `bash tests/linux-unit.sh` (healthy: `linux-unit: OK`). The `macos` job runs `bash tests/macos-watcher.sh`.

### Build notes (Phase 2)

Added only after the phase lands.
