# spec.md — One backup job

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-31) |
| Status | Draft 2 |
| Stage | 2 · Design |

## 1. Summary

One LaunchAgent, label `com.nikolaybotev.backup`, runs hourly at minute 0 and reads a TOML file of source and destination pairs. Each pair is one task. Tasks run at the same time unless the file sets a concurrency cap. A task that fails returns a status; it does not cancel the others. The process exit is the highest status. Each destination keeps `backup.log`, the current snapshot names, and the current retention, so history already on disk stays valid.

`backup-folder /abs/source /abs/backup-dir` does not read that file and keeps today's statuses.

A shared library parses one TOML subset and checks permissions. The watcher and the backup job each apply their own schema. The watcher re-reads its file when the file changes. A bad edit logs the reason and leaves the last good config in force. The backup job reads its file once per run.

The template, the example file, and the migration notes use placeholders. This change does not install or reload anything.

## 2. Goals and non-goals

**Goals**

- G1. One backup LaunchAgent lists every folder in a config file.
- G2. Folder tasks are isolated. The process waits for all of them. Its exit status reflects any failure.
- G3. Default scheduling runs every folder at once. An optional positive integer caps how many run at once.
- G4. Destination layout, snapshot names, retention, and `backup.log` stay as they are.
- G5. The two-argument command stays.
- G6. One TOML subset, one permission check, and one error style serve both tools.
- G7. The watcher applies a valid edit and stays up through an invalid one. The backup job does not watch its file.
- G8. The repo ships a generic template, an example config, and migration notes.

**Non-goals**

- Do not install, load, unload, or reload a LaunchAgent. Do not run `launchctl`. Do not write a live config, a live pin file, or anything under a home `Backups` directory.
- Do not perform the cutover from per-folder agents to the one agent.
- Do not change the 48-hour or 60-day retention rules, the snapshot name shapes, or the per-destination lock path.
- Do not merge the watcher file and the backup file into one file.
- Do not add a third-party TOML package.
- Do not type-check or link `Sources/backup-folder/main.swift` on the Linux job.
- Do not change watcher readiness. The reload path does not sleep and does not add a settle timer.
- Do not change `pins.txt`, `scripts/install-tools.sh`, `scripts/ensure-backup-dirs.sh`, the release workflow, or branch protection.
- Do not set `RunAtLoad` to true. Omit `KeepAlive` on the backup agent.
- A process-killing trap is not isolation. Returned statuses are.

**Release phasing.** The library, the backup job, the operator docs, and watcher reload are all this intent. Nothing is tagged for a later release. They land as the phases in [plan.md](plan.md). Untagged requirements belong to those phases.

## 3. Principles

- P1. A folder failure is a status. It is not `exit` of the whole process, and it is not cancellation of sibling tasks.
- P2. The destination directory is the compatibility surface: `backup.log`, `.backup-folder.lock`, snapshot names, and retention.
- P3. A backup file that does not validate starts no folder.
- P4. After the watcher has started from a good file, a bad edit does not stop the process.
- P5. Operator docs use placeholders. Prose about the repo says "this repo". Human-facing docs do not spell out what a competent reader already knows. Agent-facing files keep explicit expectations such as "(healthy: exit 0)".
- P6. Agents do not apply the migration.

## 4. Users and scenarios

- Adding a folder is a new `[[folder]]` entry. It is not a new plist.
- One source is unreadable. The other destination still gets a published snapshot. The process exits non-zero.
- A second process already holds that destination's lock. That folder logs `skipped; dest busy` and contributes status 0. Other folders still run.
- The two-argument command still snapshots one folder and does not consult the config file.
- The watcher is running. Replacing its file with text that does not validate logs the reason, keeps the previous watch folder and webhook, and leaves the process running.
- Replacing that file with a valid file retargets the watch folder, the webhook, the ignore list, and the log path.
- The backup job is a short run. It sees the file as it was at start. The next hour sees a later edit.

## 5. Functional requirements

1. The shared library is a SwiftPM target `ToolConfig` at `Sources/ToolConfig/`. It imports Foundation only. It is Darwin-free. `drop-box-watcher` and, from the backup-job phase, `backup-folder` depend on it. Public entry points are `parseTomlSubset` and `configPermissionsAcceptable(at:)`. No third-party parser.
2. The Linux job compiles those sources in the same `swiftc` invocation as the watcher files. Call sites use `#if canImport(ToolConfig)` so SwiftPM imports the module and the loose `swiftc` compile sees the functions in the same invocation. SwiftPM settings are per target and are not inherited. `ToolConfig` sets `-target arm64-apple-macos12.0` and `.swiftLanguageMode(.v5)` itself. Do not add `Sources/backup-folder/main.swift` to the Linux job.
3. The TOML subset accepts `#` comments to end of line, blank lines, basic strings (`\\` and `\"` only), arrays of basic strings, `[tables]`, `[[array of tables]]`, and integers (optional leading `-`, then digits, no `+`, no underscores). `#` starts a comment only outside a basic string. It rejects literal strings, multiline strings, inline tables, floats, booleans, dates, and dotted keys. A duplicate key in one table is a parse error. The result is a table of values: string, integer, array of strings, table, or array of tables. A fault on one line produces a message that includes that line number and does not include the value text or the raw line. A missing required key names the key and has no line number.
4. `configPermissionsAcceptable(at:)` stays the current predicate. It returns false when `attributesOfItem` fails, including a missing path, and otherwise returns `mode & 0o077 == 0`. It does not test a read bit, so mode `0200` passes. Mode `0600` passes. Mode `0400` passes. Mode `0644` fails. Checked 2026-10-31 against `drop-box-watcher/Config.swift` and the `0400` assertion in `tests/drop-box-watcher-tests.swift`. Do not narrow this to exactly `0600`. A missing path is this failure, exit 2, not a separate I/O error. I/O is a read that throws after the predicate returned true. The watcher keeps the stderr line `config permissions too open` for the predicate failure.
5. Startup and reload check that predicate before reading the file bytes. A too-open file is not parsed.
6. The watcher schema keeps the name `parseConfigTOML` and `loadConfig`, and keeps `ConfigLoadError`. Documents the current Linux tests accept still succeed. Documents those tests reject still fail, including an unknown key, a duplicate key, a literal string, a relative `watch_folder`, an empty webhook key, a missing webhook table, and a non-loopback `http` URL. Any integer value, and any `[[table]]`, is a watcher schema error. The webhook key never appears in an error string.
7. The backup schema is `parseBackupConfig`. Root keys are optional `concurrency` and one or more `[[folder]]` tables, and nothing else. Each folder has `source` and `dest` only. A path that does not start with `/` is an error before normalization (`PathContainment.lexicalNormalize` would turn a relative path into an absolute one). Absolute paths are then compared with `lexicalNormalize` from `Sources/backup-folder/PathCheck.swift`, which strips trailing slashes, drops `.` and empty components, and applies `..`. The two-argument command still strips only one trailing slash before it runs, as it does today. The normalized config path is what duplicate detection and the folder body see. Zero folders is an error. `concurrency` absent means no cap. Present, it must be an integer greater than or equal to 1. Zero, a negative integer, and a non-integer are errors. Two destinations equal after that normalization are an error, compared case-insensitively, so `/ABS/Backup` and `/ABS/backup` are one destination. Checked 2026-10-31: `lexicalNormalize` collapses `/ABS//BACKUP` and `/ABS/other/../BACKUP` to `/ABS/BACKUP`. Case-insensitive compare fails closed on a case-sensitive volume: a pair that differs only by case does not start two tasks. If both destinations exist and resolving symlinks yields the same path, case-insensitively, that is the same error. Schema errors name the line and the key and do not include the value text. A pair whose destination is inside its source is not a schema error.
8. Command lines:
   - `backup-folder --version` and `backup-folder --version --verbose` stay as they are and win before any other parsing.
   - `backup-folder /abs/source /abs/backup-dir` runs that one folder and does not open the config file.
   - `backup-folder --config /abs/config.toml` is the job. The path is required and absolute. There is no default path.
   - Any other arguments print usage to stderr and exit 2. Usage names both forms.
9. The one-folder body returns `Int32`. It does not call `exit` or `fatalError`. The two-argument command exits with that status. The job calls it once per folder from a worker that is not the Swift cooperative thread pool. Checked 2026-10-31: WWDC21 session 10254 describes that pool as one thread per core that must keep making progress, and says Grand Central Dispatch creates more threads when a work item blocks. The same day, Swift 6.4.2 on Linux compiled and ran a non-throwing task group whose children resume a continuation from `DispatchQueue.global().async` (`swiftc -parse-as-library`). `clonefile` and `flock` block. Each folder's body therefore runs inside `DispatchQueue.global().async`, and the task waits with a continuation. Do not call `DispatchQueue.sync` from a task, and do not wait on a semaphore on the cooperative pool. Checked the same day: Apple's `withThrowingTaskGroup` documentation says a throw that leaves the group body cancels the remaining children. The job uses a non-throwing task group. Each child returns a status. The group does not call `cancelAll`. The folder body does not stop because `Task.isCancelled` is set.
10. A concurrency cap of `n` has at most `n` folder bodies in flight. Folders start in file order. When one returns, the next starts. Every folder still runs. No cap means every folder is started without waiting for another to finish. The cap is not a timeout and not a skip.
11. Statuses, unchanged for one folder:
    - `0` when the snapshot is published, including when a later prune logs an error. Checked 2026-10-31: `Sources/backup-folder/main.swift` logs a prune error and does not exit.
    - `0` when the destination lock is busy (`EWOULDBLOCK`): log `skipped; dest busy`, do not remove a temp directory, do not log `OK`.
    - `2` when `PathContainment.refuses` is true, before creating the destination. That includes the destination being the source or inside it, and a symlink cycle in either path. Checked 2026-10-31: `refuses` returns true on `.cycle`, and `main.swift` exits 2 on that result.
    - `1` for the current operational failures (cannot create the destination, cannot read the source, lock errors other than busy, a walk that does not publish).
    - The process exit for `--config` is the maximum of those statuses. It is `0` only when every folder returns `0`. A usage error, a schema error, a permission-predicate failure (including a missing config path), or a read that throws after the predicate returned true exits `2` and starts no folder.
12. Each task has its own destination, its own `backup.log`, and its own lock file `dest/.backup-folder.lock`. Log lines for a folder are written only to that file. The same line is also written to stderr, as today, and those stderr writes are serialized so one line is not torn. The lock around stderr is not held across `clonefile`. Each folder body creates its own log formatter, its own snapshot-name formatter, and its own prune formatters. Checked 2026-10-31: `log` builds a formatter per line, but `nameFormatter`, `oldParseFormatter`, and `newParseFormatter` are created once per process today and must not be shared across tasks. `DateFormatter` is not safe to share. Snapshot names stay `yyyy-MM-dd_HHmmss-<pid>` with `-2`, `-3`, and so on. Old `yyyy-MM-dd_HHmm` directories still age out under the same 48-hour and 60-day rules. One process has one pid. Names are per destination, and duplicate destinations are rejected before tasks start, so the shared pid does not collide inside one destination. There is no new shared log file.
13. Same-process `flock` is not what isolates two configured folders. Apple's `flock(2)` man page (archived, and the macOS 26.3 mirror checked 2026-10-31) says locks are on files and that descriptors from `dup` or `fork` share one lock. It does not define two `open` calls in one process as the way this job separates folders. Duplicate destinations are a config error (requirement 7). Each task still takes the lock, so a different process — the two-argument command, or a per-folder agent that has not been unloaded — still gets `skipped; dest busy` and status `0`.
14. The template `launchd/backup-folder.plist.template` replaces the per-folder template. Label `com.nikolaybotev.backup`. `ProgramArguments` are `/ABS/PATH/TO/HOME/bin/backup-folder`, `--config`, and `/ABS/PATH/TO/HOME/.config/backup-folder/config.toml`. `StartCalendarInterval` minute `0` and no `Hour`. The `RunAtLoad` key is present and false (omitting it fails the existing `is not False` assertion). No `StartInterval`. `KeepAlive`, `StandardOutPath`, and `StandardErrorPath` are absent. No XML comments. No real home, source, or backup path. `tests/no-secrets.sh` today requires label `com.nikolaybotev.backup.NAME` and arguments `/Users/USER/bin/backup-folder`, `/ABS/SOURCE`, `/ABS/BACKUP-DIR`. `tests/setup-docs.sh` requires the anchor `com.nikolaybotev.backup.NAME` in `docs/setup.md`. Those checks move to this label, `--config`, and these placeholders. `docs/backup-job.md` still contains the old label.
15. `backup-folder.example.toml` sits next to the watcher example. It is comments plus two `[[folder]]` entries using `/ABS/SOURCE`, `/ABS/BACKUP-DIR`, `/ABS/SOURCE-2`, and `/ABS/BACKUP-DIR-2`. A commented `concurrency = 2` shows the key. The comment tells the operator to copy it to `~/.config/backup-folder/config.toml`, to use mode `0600`, to replace placeholders, and not to commit the real file. It says `pins.txt` in that directory is a different file. No real path, host, or secret.
16. `docs/backup-job.md` is the migration note. It is human-facing. It says: one agent; a config entry instead of an agent; keep the same destination directories so `backup.log`, snapshot names, and retention still apply; unload each agent whose label is `com.nikolaybotev.backup.NAME` and load `com.nikolaybotev.backup`; if both run against one destination, one of them logs `skipped; dest busy`. It lists the operator's unload and load steps and says a person runs them on the Mac. The build phases do not run those steps, and the note does not claim they have been run. `docs/setup.md` rewrites the existing backup-agent bullet in place and links this note and the example. The Manual/Script bullet count stays 33. `docs/restore.md` rewrites the existing LaunchAgent bullet and the intro sentence so the backup agent is one agent. The bullet count stays 7. `README.md` describes both command lines and the one agent. None of these human-facing files state that success is exit 0.
17. Watcher reload, after a successful start:
    - Use an FSEvents stream on the parent directory of the config path, with file-level events, and ignore events whose last path component is not the config file's name. A vnode watch on the directory does not report an in-place write or a mode change. A vnode watch on the descriptor opened at startup stays on the old inode after a rename-over. Re-read by path. Checked 2026-10-31 against that vnode rule; the watcher already uses FSEvents for the drop-box folder, and this stream is separate from that one.
    - There is no settle timer. A torn in-place read may log `config reload rejected` and a later complete read may log `config reloaded`.
    - Check mode, then read, then parse and validate, including that the watch folder is a directory and that the log path opens, before swapping any live setting.
    - A failure logs `config reload rejected: <reason>` on the current operational log and keeps the last good config. The process does not exit. If the log write fails, the same line goes to stderr, and the process still does not exit.
    - Equal means the validated fields, including the webhook key. A comment-only save logs nothing and does not retarget.
    - A new valid config writes `config reloaded` to the current operational log, then swaps the watch folder, webhook URL and key, ignore list, and log path. Posts already started keep the URL they started with. Later posts use the new URL. The log line does not include the webhook key or the file body.
    - The decision function lives in a Darwin-free file that `tests/linux-unit.sh` compiles and greps for `Task.sleep`, `usleep`, and `sleep(`. `Watcher.swift` imports CoreServices and that script does not compile it.
    - The first load is unchanged: a bad file exits 2. There is no last good config yet.
    - The reload path does not call `Task.sleep`, `usleep`, `sleep(`, or `exit`.
18. The backup job does not watch its file and does not reload during a run.
19. `AGENTS.md` records the one agent, the config path, the shared target, and that a folder status does not cancel siblings. `REVIEW.md` treats a backup template that still has `StartInterval`, a real path, the per-folder label `com.nikolaybotev.backup.NAME`, or a source and dest argument pair, as a bug.

## 6. Acceptance criteria

- AC1. Phase 0: `bash tests/linux-unit.sh` exits 0 (healthy: `linux-unit: OK`). The current watcher accept/reject cases still pass. New cases cover an array of tables, an integer, a float rejected by the parser, and a `[[folder]]` document rejected by the watcher schema. `bash tests/build-entry-test.sh` exits 0 and the package names the `ToolConfig` target. `Sources/backup-folder/main.swift` is unchanged in that phase.
- AC2. Phase 1: `swiftc -parse-as-library` of `Sources/ToolConfig/TomlSubset.swift`, `Sources/backup-folder/PathCheck.swift`, `Sources/backup-folder/BackupConfig.swift`, `Sources/backup-folder/FolderJob.swift`, and `tests/folder-job-tests.swift` exits 0. The test file's entry point is `@main` with an async `main`, and the file has no top-level code. The test exits 0. The `linux` job in `.github/workflows/test.yml` runs that compile and the test. It does not run `swift build` or `scripts/build.sh` (the build-entry check already rejects those). It does not compile `main.swift`. The test shows: schema errors for an empty folder list, a relative path, and `concurrency` of 0; `/ABS//BACKUP` and `/ABS/other/../BACKUP` are the same destination as `/ABS/BACKUP`; `/ABS/Backup` and `/ABS/backup` are the same destination; two existing symlink paths to one directory are an error; with no cap, every fake folder body is in flight together; with cap 2 and four folders, at most two are in flight and all four run; one body returning 1 does not stop the others and the aggregate is 1; a 2 and a 1 aggregate to 2; `Task.isCancelled` is false in those bodies. The overlap test fails within a few seconds if the second body has not entered while the first is still inside the runner.
- AC3. Phase 1: `bash tests/macos-smoke.sh` still prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. The existing two-argument cases stay, including the busy lock (exit 0, log `skipped; dest busy`) and the containment case (exit 2). New cases, under `mktemp` only: `--config` with two folders publishes one snapshot in each dest and exits 0; one missing source still publishes the other folder and exits 1; a duplicate dest exits 2 and publishes nothing; mode `0644` exits 2; one pair whose destination is inside its source still publishes the other folder and exits 2; a destination locked by another process logs `skipped; dest busy`, contributes 0, and the other folder publishes; two existing destinations that resolve to the same directory exit 2 and publish nothing.
- AC4. Phase 1: `bash tests/no-secrets.sh` and `bash tests/setup-docs.sh` exit 0. The backup plist matches requirement 14. Setup still has 33 Manual/Script bullets. Restore still has 7. The example and `docs/backup-job.md` exist and use the placeholders in requirements 15 and 16.
- AC5. Phase 2: `bash tests/linux-unit.sh` exits 0 and covers the reload decision: a bad read keeps the previous config and returns the rejected-log line; an equal config returns no log; a new config returns the new value and `config reloaded`. The product reload path contains no `Task.sleep`, `usleep`, or `sleep(`. `bash tests/macos-watcher.sh` still prints `macos-watcher: build OK`, `macos-watcher: notify OK`, and `macos-watcher: unchanged OK`. It also replaces the live file with invalid text and expects `config reload rejected` while the process stays up and the old folder still notifies; `chmod 0644` does the same; a later valid file for a second folder notifies for that folder.
- AC6. No phase edits `.github/workflows/release.yml`, `.github/workflows/codeql.yml`, or `.github/scripts/protect-main-branch.sh`. No phase raises `timeout-minutes`. No phase runs `launchctl`, `scripts/install-tools.sh` against a home directory, or `scripts/ensure-backup-dirs.sh` against a live home. No phase pushes a tag.
- AC7. This design pull request does not start Phase 0. Its product files are this folder, plus the scan exception the plan describes so the captured prompt's minute notation is not read as a port. `bash tests/no-secrets.sh` exits 0.

## 7. Design decisions

**D1 — Two files, one library.** The backup list is `~/.config/backup-folder/config.toml`. The watcher file stays `~/.config/drop-box-watcher/config.toml`. A combined file was rejected: the watcher file holds a webhook key, the two files change for different reasons, and a backup edit must not reload the watcher. "One format, one validator" is the subset, the permission check, and the error style. Each tool keeps a schema. `pins.txt` in the backup config directory stays the pin file and is not parsed by this library.

**D2 — Library shape.** `ToolConfig` plus `#if canImport(ToolConfig)` (requirement 2). A second TOML implementation inside the watcher was rejected. Emitting a separate Linux module and linking it was rejected for this repo's one-invocation `swiftc` test.

**D3 — Strict subset.** Unknown syntax is a parse error. Unknown keys are a schema error. That keeps one parser and two schemas. The watcher tests do not assert message text; they assert accept or reject. A fault on one line includes that line number. A missing required key names the key and has no line number, matching the current end-of-file checks. Messages do not echo values, so a webhook key cannot land in a log. `#` inside a basic string is not a comment. The current scanner cuts at the first `#` on the line, and no current fixture has a `#` inside a string, so the subset fixes that rather than preserving it.

**D4 — Cap ships, default unlimited.** The optional cap is in this intent, not deferred. Absent means all folders at once, which is today's side-by-side agents. A present cap still runs every folder.

**D5 — Tasks, not actors, and not child processes.** The folder body is one straight-line function with its own locals. An actor would only serialize state the task does not share. Child processes were rejected: the request is one job whose tasks behave as if the old processes were side by side, and Full Disk Access stays on this binary. Blocking work is dispatched off the cooperative pool (requirement 9) so those tasks actually overlap.

**D6 — Max status.** Busy stays 0, as in snapshot-identity D11, because the other holder is doing that destination's backup. Config errors stay 2 and start nothing, so a broken file cannot look like a partial backup. A mix of 1 and 2 is 2 so a path refusal is still visible when another folder also failed the walk.

**D7 — Containment stays per folder.** A destination inside its source, or a symlink cycle, fails that folder with 2. The other folders run. Failing the whole file was rejected because one bad pair would block every other folder. Duplicate destinations are the exception: they are a config error and start nothing, because two tasks on one destination would share a log, a name, and a lock (requirement 13). Identity uses `lexicalNormalize` and a case-insensitive compare so `..`, extra slashes, and case-only pairs cannot slip through. Case-folding can refuse two real directories on a case-sensitive volume. That refusal starts nothing, which is the safe side.

**D8 — Reload validates before it swaps.** A half-applied watch folder with the old webhook is worse than keeping the last good config. Equality skips the log so an atomic save of the same bytes does not churn the watch. Startup still exits 2.

**D9 — One template.** The per-folder plist is replaced, not kept beside the new one. The migration note is what tells the operator the old label shape. Placeholders match the watcher template (`/ABS/PATH/TO/HOME`), so one substitution fills the binary and the config path. Launchd still does not expand `$HOME`.

**D10 — Docs land with the job.** The template, example, and migration note ship in the same phase as `--config`. A merged job with the old per-folder template would describe a command the template does not run. Watcher reload is its own phase; it does not need those docs.

**D11 — This pull request is the design.** Phase 0 starts when someone says to build. Build threads for this intent use Grok 4.7 High. A phase does not merge itself. The coordinator squash-merges only when the required checks `macos` and `linux` are green. Merging may let job `publish` push the next patch tag. The build does not push a tag and does not add a release label.

## 8. Open questions

None.
