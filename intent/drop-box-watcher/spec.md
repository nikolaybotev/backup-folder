# spec.md — Drop Box watcher

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-30) |
| Status | Draft 2 |
| Stage | 2 · Design |

## 1. Summary

`drop-box-watcher` is a second command-line tool in this repository. A per-user LaunchAgent runs it in the deployment Mac's login session. It watches one folder. When a regular file in that folder is fully present on disk, one Swift actor POSTs a nudge to a Grok Bot routine webhook. The deployment Mac lists the folder and moves the files. The watcher does not.

The snapshot tool is unchanged. Nothing in this spec installs software on the deployment Mac or publishes a release by itself.

## 2. Goals and non-goals

**Goals**

- G1. Wake the routine within seconds of a file becoming fully present in the watched folder, including a file that arrived while the watcher was not running.
- G2. Treat an iCloud placeholder as not ready, ask iCloud to download it, and nudge only after Apple reports the file current and no download is in flight.
- G3. Treat a rename into the folder of a file that is already current as an arrival.
- G4. Deliver nudges through one actor, one HTTP call at a time, retrying a failed delivery until it succeeds.
- G5. Ship an example config, a LaunchAgent template, and install notes a person can follow. Keep the real config and the secret out of git.

**Non-goals**

- Moving, renaming, editing, or deleting files. Listing the folder and sorting files stays the deployment Mac's work.
- The 11 PM sweep, the hourly poll, and any other bot routine. Those stay the backstop the maintainer named. This spec does not define how they work.
- A settle delay, a size-stability debounce, or any timer on the readiness path.
- NSMetadataQuery, File Provider, `brctl`, Keychain, and `url(forUbiquityContainerIdentifier:)`.
- Renaming the repository or the `backup-folder` binary.
- Snapshot-bug fixes, and any edit to `backup-folder.swift`, its probe, its smoke script, or its LaunchAgent template.
- An installer that copies a binary into `~/bin`. A person does that.
- Installing or loading the agent on the deployment Mac. The maintainer approves a rollout. A merge to `main` does not deploy. A release exists only after a `v*` tag runs the release workflow.
- Persistent dedup across restarts, and a second webhook client.

**Release phasing.** Every untagged requirement in this spec is in the first release of the watcher. There is no later-release slice inside this intent. Dropping one of the two event triggers, after the deployment Mac has measured them, would be a new intent.

## 3. Principles

- P1. A file is ready only because of its current Apple file state, observed when an event arrives or when the startup scan runs. The process does not wait for a file to settle.
- P2. `WebhookNotifier` is the only type that talks to the webhook. Readiness code enqueues work and returns.
- P3. A nudge is safe to repeat. The deployment Mac lists the folder. The payload names are a hint.
- P4. The secret stays in the config file. Logs, process arguments, and the repository do not contain it.
- P5. The spec wins over the plan. A departure is written into the plan under that phase.

## 4. Users and scenarios

The maintainer drops a file into the iCloud Desktop folder from another device, or moves one in from elsewhere in iCloud, or saves one on the deployment Mac. The watcher nudges the deployment Mac. The deployment Mac handles the file.

S1. **Cloud file, new.** A placeholder appears under the final name. The watcher does not nudge. iCloud fills the file in place. The next change event finds the file current, and one nudge names it.

S2. **Cloud move-in.** A file renamed into the folder is already current. That rename is an arrival and produces a nudge.

S3. **Local file.** A regular file that is not an iCloud item is ready as soon as it is in the folder.

S4. **Browser download.** Partial names (`*.part`, `*.download`, `*.crdownload`) are ignored. The rename to the final name is the event that can nudge.

S5. **Restart or login.** After boot, FileVault stays locked until someone logs in. The LaunchAgent starts at login. One startup scan nudges once for every file that is already ready. Files that arrived while the Mac was logged out are in that scan.

S6. **Webhook down.** Ready files are remembered and retried until a 2xx response. A new ready file during a wait is included and the wait ends. Readiness itself does not pause.

## 5. Functional requirements

FR1. **Program.** The tool is compiled with `swiftc` from the Swift sources under `drop-box-watcher/`. There is no `Package.swift`. The binary name is `drop-box-watcher`.

FR2. **Arguments.** The process takes one argument, the path of the config file. Any other argc logs to standard error and exits 2.

FR3. **Config file.** The file is TOML, mode with no group or other permission bits (`mode & 0o077 == 0`), checked before the file is parsed. A looser mode exits 2 and does not parse the secret. The parser accepts only this shape:

- `watch_folder`, a basic string, absolute path.
- `[webhook]` with basic strings `url` and `key`. `key` is non-empty. `url` is `https`, or `http` whose host is `127.0.0.1` or `localhost` and which has an explicit port.
- `[behavior]` with `ignore`, an array of basic strings. Each pattern is a file name: no `/`. `*` matches any run of characters in that name. Every other character is literal and case-sensitive.
- `[log]` with basic string `path`.
- `#` comments, blank lines, and basic-string escapes `\\` and `\"`.
- Unknown keys, duplicate keys, missing required keys, other TOML types, and literal or multiline strings are errors and exit 2.

The shipped example uses placeholders of the same kind as `launchd/backup-folder.plist.template`. It is not a home directory path and it has no secret.

FR4. **Logging.** Operational lines go to `[log].path`, opened for append. The process may create that file. It does not create missing parent directories. If the file cannot be opened, exit 2. Standard output and standard error of the LaunchAgent point at the same path so failures before the config loads land there too. A log line never contains the webhook key, the Authorization value, or the request body. Delivery failures are logged. The same status-and-error pair is logged on its first occurrence and then at most once per 60 seconds, and the next logged line includes how many identical failures were skipped. A success clears that pair.

FR5. **Folder.** `watch_folder` must exist and be a directory or the process exits 2. The process does not create it. At startup, if `ubiquitousItemIsExcludedFromSync` is true on that folder, log an error and keep running. iCloud excludes the folder name `Dropbox`; the watched folder's name is `Drop Box`.

FR6. **What is considered.** The watch folder is stored as a standardized file URL. A path is a direct child only when `deletingLastPathComponent().standardizedFileURL` equals that URL, the comparison in the brief. A config path and an FSEvents path that differ by a symlink (`/tmp` and `/private/tmp`) still match. Directories are skipped. Symbolic links are not followed and are skipped. Ignored names are skipped. The startup scan passes `.skipsHiddenFiles` and still applies the ignore list. FSEvents does not skip hidden names, so the ignore list is what drops them.

FR7. **Readiness decision.** This is a pure value. It does not call `FileManager`, it does not call `startDownloadingUbiquitousItem(at:)`, and it does not sleep. Inputs are the ignore result, whether the path is a regular file, a directory, or a symbolic link, whether it is ubiquitous, `ubiquitousItemDownloadingStatus`, and whether a download is in flight.

- Ignored, not a regular file, a directory, or a symbolic link: skip.
- Not ubiquitous: ready.
- Ubiquitous, status `.current`, and `ubiquitousItemIsDownloading` is not true: ready.
- Any other ubiquitous result, including `.notDownloaded`, `.downloaded`, `.current` while a download is in flight, and a missing status: request download.

The watcher applies this value on every event recheck and on the startup scan. A request-download result calls `FileManager.startDownloadingUbiquitousItem(at:)`, logs a thrown error, and does not claim the file. The next event reads the status again. There is no retry timer. Phase 1 owns that call. Phase 0 owns only the value.

`.current` means a local copy exists and is the most up-to-date version known to the device. `.downloaded` means a local copy exists and is stale. `.notDownloaded` means it has not been downloaded. A stale or missing local copy is never a nudge.

FR8. **Claim.** A ready file is claimed only after a coordinated read. Build `NSFileCoordinator` with the watcher as its file presenter and call `coordinate(readingItemAt:options:error:byAccessor:)` with empty options. If the accessor does not run, log the error and do not claim. The claim identity is the triple (standardized path, inode, size in bytes), from `FileManager` attributes `.systemFileNumber` and `.size`. A second claim of the same triple does nothing. The set lives in memory. A path that no longer exists is dropped from the set. `presentedSubitemDidDisappear(at:)` drops claim keys for that path and does not nudge. A later file at that path is a new claim. A restart starts empty: the startup scan claims every file that is ready then.

FR9. **Triggers.** Both of these are on:

- An `NSFilePresenter` for the watch folder, on a serial `OperationQueue` named `drop-box-watcher`. Implement `presentedSubitemDidChange(at:)`, `presentedSubitemDidAppear(at:)`, `presentedSubitem(_:didMoveTo:)`, and `presentedSubitemDidDisappear(at:)`. The first three recheck FR7. The move callback rechecks the new URL. `presentedSubitemDidDisappear(at:)` only removes claim keys for that path. It does not nudge and it does not request a download.
- An FSEvents stream on the watch folder, created with `FSEventStreamCreate`, `sinceWhen` of `kFSEventStreamEventIdSinceNow`, latency `0`, and flags `kFSEventStreamCreateFlagFileEvents`, `kFSEventStreamCreateFlagUseCFTypes`, and `kFSEventStreamCreateFlagNoDefer`. Schedule it with `FSEventStreamSetDispatchQueue` on a queue named `drop-box-watcher.fsevents`. The callback hops onto the presenter queue before it touches watcher state. Do not filter on event flags. Every path event rechecks FR7.

Start order: add the presenter, start the stream, then run the startup scan on the presenter queue. `main` holds the watcher for the process lifetime and calls `dispatchMain()`. If stream creation fails, log an error and keep the presenter and the scan. The code does not choose a trigger from a list of flags. the deployment Mac's later measurement records which callbacks fired; it does not change this requirement.

FR10. **Startup scan.** Enumerate the folder root only, direct children per FR6. Apply the FR7 decision to each child. A request-download child gets `startDownloadingUbiquitousItem(at:)` and is not claimed. Claim every ready child. Submit one batch for all of them.

FR11. **Notifier.** `actor WebhookNotifier` is the only webhook speaker. `WebhookHTTP` is its production transport and the only type that uses `URLSession`. The watcher and `main` enqueue only through `WebhookNotifier`. `submit` merges claims into a pending set and returns without waiting for HTTP. At most one POST or one retry loop runs at a time.

- The body is a JSON object with `event_time` and `files`. `event_time` is UTC ISO-8601 from `ISO8601DateFormatter` with `.withInternetDateTime`, taken when that request is built (`1970-01-01T00:00:00Z` shape). `files` is the basenames of the merged claims, first-seen order, no duplicates. No other fields.
- The request is `POST`, `Content-Type: application/json`, and `Authorization: Bearer <key>`.
- Success is an HTTP status from 200 through 299. On success, drop the claims that were in that request. Claims that arrived during the request start a new send immediately. The backoff sequence resets.
- Any other outcome, including a transport error, a timeout, and a non-2xx status, keeps those claims pending. The wait before the next try is 1s, then 2s, 4s, 8s, 16s, then 30s forever. A submit that arrives during a wait cancels the wait and sends immediately. If that send fails, the next wait is the next step in the same sequence, not a reset to 1s.
- The HTTP request timeout is 60 seconds. A hung accept must not stall the pending set.
- An empty pending set does not send.

FR12. **LaunchAgent template.** Label `com.nikolay.drop-box-watcher`. `RunAtLoad` true. `KeepAlive` true. `ThrottleInterval` 10. No `StartInterval` and no `WatchPaths`. `ProgramArguments` is the binary path and the config path, both absolute placeholders (`/ABS/PATH/TO/HOME/...`), because `launchd.plist(5)` passes that array to `execvp(3)`, which does not expand `~`. `StandardOutPath` and `StandardErrorPath` use the absolute placeholder for the log file. The template lives at `launchd/drop-box-watcher.plist.template`.

FR13. **Install notes.** The README tells a person to put the binary at `$HOME/bin/drop-box-watcher`, the real config at `$HOME/.config/drop-box-watcher/config.toml` with mode `0600`, and the plist at `$HOME/Library/LaunchAgents/com.nikolay.drop-box-watcher.plist` with placeholders replaced by absolute paths; to load it with `launchctl bootstrap gui/$(id -u)`; and that the first run can prompt for Desktop access. The config directory is outside iCloud Desktop and Documents and outside `~/Backups`. The notes say agents and CI do not perform these steps, and that a merge does not publish a binary. The maintainer tags when a release should exist.

FR14. **Tests and CI.** Darwin-free tests cover the parser, the mode check, ignore matching, the readiness decision, the notifier, and log redaction. They run on the Linux toolchain and on the macOS runner. The macOS job also builds the binary, checks exit 2, and runs a local non-iCloud smoke: a file dropped in a temp folder produces one nudge, the file bytes stay the same, an ignored name produces none, and a size change produces another nudge. That harness may poll for up to 10 seconds. The product code on the readiness path does not sleep. A macOS smoke that never sees the create event does not pass. The existing `macos-smoke` line stays `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. CodeQL's manual build compiles this binary as well as `backup-folder`. The release workflow uploads both binaries on a `v*` tag.

## 6. Acceptance criteria

AC1. `bash tests/linux-unit.sh` exits 0. The parser tests reject an unknown key, a duplicate key, a relative `watch_folder`, an empty key, a non-loopback `http` URL, and a missing table, and they accept `https` and loopback `http` with a port. A mode of `0644` is refused before parse; `0600` and `0400` are accepted.

AC2. The same script's ignore tests match `.DS_Store`, a dotfile, and names ending in `.icloud`, `.download`, `.crdownload`, and `.part`, and they do not match `note.txt`.

AC3. The same script's readiness table matches FR7 for a local file, `.current` without a download, `.current` while downloading, `.downloaded`, `.notDownloaded`, a directory, and a symlink. The not-ready ubiquitous rows are the request-download value. `Readiness.swift` does not mention `startDownloadingUbiquitousItem`.

AC4. The same script drives `WebhookNotifier` with a fake transport and a fake clock: one in-flight POST, a merge of a second file into the follow-up POST, a non-2xx wait of 1s then 2s, a submit during the wait that sends immediately, a 2xx that clears the sent claims, a body of `event_time` plus `files`, and an `Authorization` value of `Bearer` plus the key. After the 1s and 2s waits, a submit during the next wait sends immediately, and a failure of that send records a 4s wait, the next step, rather than starting over at 1s. The log text does not contain the key.

AC5. `Readiness.swift` and `Watcher.swift` contain no sleep call. `bash tests/linux-unit.sh` fails if they do. `Watcher.swift` is scanned once it exists.

AC6. On macOS, `bash tests/macos-watcher.sh` exits 0: the binary builds with `swiftc`, bad arguments and a loose config exit 2, a regular file in a temp folder is nudged once with its basename, the file contents are unchanged, `.DS_Store` is not named, and a longer file is nudged again.

AC7. The `macos` CI job still runs `bash tests/macos-smoke.sh`, which prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`.

AC8. `.github/workflows/codeql.yml` compiles `drop-box-watcher` in the manual build step. The job name stays `CodeQL (Swift)`.

AC9. `bash tests/linux-unit.sh` parses `drop-box-watcher.example.toml` against FR3, and the plist template contains `com.nikolay.drop-box-watcher`, `RunAtLoad`, `KeepAlive`, and `ThrottleInterval`, and does not contain `StartInterval`.

AC10. `.github/workflows/release.yml` uploads `drop-box-watcher` and `backup-folder`. The unit script checks that the workflow names the new binary. No tag is pushed by the implementation phases.

AC11. The iCloud flag measurement on the deployment Mac is not a CI check. The implementation PR states that it was not run. It does not invent flags, callback names, or a claim that the agent was installed.

## 7. Design decisions

**D1 — Second tool in this repository.** The watcher is a new binary beside `backup-folder`. The repository name and the snapshot binary stay. The maintainer settled the repo; a rename is out of scope. Verified: `main` at `7625d02` is still that snapshot tool plus CI.

**D2 — Login LaunchAgent, binary at `~/bin`.** iCloud syncs in a logged-in session, and the deployment Mac keeps FileVault on with no auto-login, so this is a per-user agent, not a LaunchDaemon. It starts at login. The binary path is `~/bin/drop-box-watcher`, which is the install location the maintainer chose. The plist stores that location as an absolute path (D14).

**D3 — TOML config, no Keychain.** URL, secret, folder, ignore list, and log path come from one TOML file the plist passes in. The real file stays outside the repo, outside iCloud Desktop and Documents, and outside `~/Backups`, at `~/.config/drop-box-watcher/config.toml`, mode `0600`. The maintainer rejected Keychain. The subset in FR3 is the whole language the parser implements, so a typo cannot silently drop the secret. Checked on the Linux toolchain on 2026-10-30: `FileManager` posix permissions report `0600` after that mode is set.

**D4 — Notify only, plus one download request.** The process never moves, renames, edits, or deletes a file, and it does not create the watch folder. `startDownloadingUbiquitousItem(at:)` is the one iCloud request, and it is how a placeholder gets contents. The watcher makes that call when the pure FR7 value says request download, on a later event and on the startup scan. Apple's document for that method says it starts a download when the item is not local and synchronizes a local item with the cloud. Checked 2026-10-30 from Apple's documentation JSON.

**D5 — No readiness timer.** the maintainer closed this. FSEvents latency is `0`. Apple's `FSEventStreamCreate` document says latency is the number of seconds the service waits after a kernel event before the callback, so zero adds no wait. The stream also sets `kFSEventStreamCreateFlagNoDefer`, which the brief requires with that latency. The only sleeps are inside `WebhookNotifier`, and only after a failed delivery (D10). A test harness may poll; the product readiness path does not.

**D6 — Status first, coordinate only when ready.** Apple's `coordinate(readingItemAt:options:error:byAccessor:)` document says that if the device has not yet downloaded the file, the call blocks, potentially for a long time, while it downloads. The watcher therefore reads `URLUbiquitousItemDownloadingStatus` first and coordinates only a file that FR7 already calls ready. The coordinator is created with the watcher as file presenter so the read does not deadlock against that presenter. Checked 2026-10-30 from Apple's documentation JSON. Status meanings checked the same day: `.current` is the most up-to-date local copy known to the device; `.downloaded` is a stale local copy; `.notDownloaded` has not been downloaded and the document points at `startDownloadingUbiquitousItem`. the deployment Mac's 2026-10-29 trace, recorded in the intent, saw a placeholder become `.current` in place and never saw `.downloaded`. This draft did not re-run that trace.

**D7 — Both triggers, no flag filter.** the maintainer settled FSEvents and an `NSFilePresenter` together. `NSMetadataQueryUbiquitousDocumentsScope` searches the Documents directories of the app's iCloud container, and `NSMetadataQueryUbiquitousDataScope` searches the rest of that container. Checked 2026-10-30 from Apple's documentation JSON. Those scopes search the app's iCloud container, which is not Desktop. The maintainer rejected them, and rejected File Provider and `brctl`, for this watcher. Every FSEvents callback rechecks state, so an unmeasured flag cannot hide an arrival. Which flags and which presenter methods fire on a cloud arrival is still a measurement for the deployment Mac (section 8). It is not a switch in the code.

**D8 — Dedup triple, memory only.** the maintainer keyed a nudge by path, inode, and size. The identity is that triple as fields, not a joined string. The set is in memory. The startup scan, including the scan after a crash or a login, nudges every file that is ready at that moment. A repeated nudge is safe (P3). There is no on-disk dedup database.

**D9 — Payload and header.** The body is `event_time` plus `files`, basenames only. The deployment Mac relists the folder and does not depend on the names. The header is `Authorization: Bearer <key>`. Cursor's Routines document, fetched 2026-10-30 from `https://cursor.com/help/grok-bot/routines`, says the panel's key is sent that way, that the panel also shows the full header, that a JSON body is delivered to the bot, and that HTTP 200 means the run was accepted and started, not that the bot finished. Any other response means a run did not start. Success for FR11 is any 2xx, which covers that 200. The same page documents routine rate limits of 200 runs an hour for one routine and 300 an hour across routines. A non-2xx from those limits uses the same retry path. A repeated nudge is safe.

**D10 — One actor, delivery waits only.** the maintainer's `WebhookNotifier` is the only webhook speaker. `submit` returns after it merges. The presenter queue does not wait on HTTP. One POST at a time. Pending claims merge. A new claim during a backoff wait cancels the wait and sends. The sequence is 1, 2, 4, 8, 16, then 30 seconds, which is the sequence in the brief with the 30 second cap. A failed immediate resend continues that sequence. Success resets it. The 60 second request timeout is a bound on a hung accept, not a readiness delay. Checked 2026-10-30: `URLSession` and `URLRequest` compile on the Linux toolchain when the file imports `FoundationNetworking` under `canImport`. The UTC ISO-8601 formatter produced `1970-01-01T00:00:00Z` for the Unix epoch on that toolchain.

**D11 — Ignore list and root only.** The sample patterns are the required example list: `.DS_Store`, `.*`, `*.icloud`, `*.download`, `*.crdownload`, `*.part`. Matching is case-sensitive on the file name. The scan does not recurse. Directories and symlinks are skipped so a link cannot name a file outside the folder.

**D12 — Logging.** The secret is never logged. Identical delivery errors are limited to one line per 60 seconds plus a skipped-count, which is the rate limit the brief required. Sixty seconds is the window this draft sets.

**D13 — Process exit and launchd throttle.** Usage, permissions, parse errors, a missing folder, and an unopenable log exit 2, matching `backup-folder`'s bad-argument exit. `KeepAlive` true restarts the process, including after exit 2. `launchd.plist(5)` `ThrottleInterval` defaults to not spawning a job more than once every 10 seconds; the template sets 10 so that bound is visible. `KeepAlive` true also implies `RunAtLoad`; the template sets both because the brief asked for both.

**D14 — Absolute plist paths.** `launchd.plist(5)` maps `ProgramArguments` to `execvp(3)`. A `~/bin/...` string is not an absolute path and is not looked up on `PATH` as a home directory. The template uses `/ABS/PATH/TO/HOME` placeholders. The install notes say to replace them with the absolute home path. The install location remains `~/bin`.

**D15 — Tests split by what Linux can run.** Config, readiness decisions, the notifier, and logging import Foundation only, plus `FoundationNetworking` for the HTTP type. They are the Linux job. `URLUbiquitousItemDownloadingStatus` is not in the Linux Foundation module; that check was compiled here on 2026-10-30 and failed to resolve the symbol. The watcher file that touches FSEvents, the presenter, and that status type is compiled on macOS. `swiftc -parse` is not a typecheck of that file. Swift 6.4.1 on this Linux image compiled an actor and an async `URLSession` call on 2026-10-30.

**D16 — CI shape.** The required macOS check keeps the snapshot smoke and gains the watcher build and the Darwin-free tests. A new `linux` job runs only the Darwin-free script. It follows `.cursor/install.sh` through `mise install` and `mise reshim` so Swift 6.4 is on `PATH`. `ubuntu-latest` has neither `mise` nor `swiftc`. The job does not run the skills installer at the end of that script. The `macos` job keeps `timeout-minutes: 20`. CodeQL stays one Swift job and its build line compiles both binaries. The release workflow uploads both on a tag and is not run by these phases. Branch protection and the CodeQL sentence in `AGENTS.md` are outside this intent.

**D17 — Loopback HTTP.** The real webhook is `https`, because the value is a bearer secret. `http://127.0.0.1` and `http://localhost` with an explicit port are accepted so the macOS smoke can receive a POST without a secret leaving the machine.

## 8. Open questions

None for the maintainer. The intent's header question is closed by D9.

The FSEvents flags and the `NSFilePresenter` callbacks for a cloud arrival on the deployment Mac are still unmeasured. The intent asked for that measurement. This draft does not guess it. FR9 rechecks on every event and keeps both triggers, so the measurement is not an input to the build. The implementation records that the measurement was not run (AC11). The deployment Mac records the result when the tool is installed. A change that drops a trigger belongs in a later intent.

## 9. Surfaces

| Surface | Owns |
|---|---|
| `drop-box-watcher` | Watch the folder, decide readiness, enqueue claims |
| `WebhookNotifier` | The only HTTP client, merge, backoff, and success |
| LaunchAgent `com.nikolay.drop-box-watcher` | Keep that process running in the login session |
| the deployment Mac's routine | List the folder, move files, and the existing sweep |
| `backup-folder` | Snapshots. Unchanged by this intent |
| GitHub release on a `v*` tag | Publish both binaries. It does not install them |

## 10. What was checked

Checked 2026-10-30, before this draft was committed:

- Apple's documentation JSON for `URLUbiquitousItemDownloadingStatus` (`.current`, `.downloaded`, `.notDownloaded`), `FileManager.startDownloadingUbiquitousItem(at:)`, `NSFileCoordinator.coordinate(readingItemAt:options:error:byAccessor:)`, `FSEventStreamCreate`'s latency parameter, `NSMetadataQueryUbiquitousDocumentsScope`, and `NSMetadataQueryUbiquitousDataScope`.
- Cursor's Routines page at `https://cursor.com/help/grok-bot/routines` for the bearer header, the meaning of HTTP 200, and the hourly routine limits.
- `launchd.plist(5)` for `ProgramArguments` (`execvp`), `KeepAlive`, and `ThrottleInterval` (default 10 seconds).
- This VM's Swift 6.4.1: an actor runs; posix mode `0600` is reported; UTC ISO-8601 for the epoch is `1970-01-01T00:00:00Z`; `URLRequest` needs `FoundationNetworking` on Linux; `URLUbiquitousItemDownloadingStatus` is absent on Linux.
- `main` is `7625d02`, the merged CodeQL and timeout pull request. The snapshot sources are the program this spec leaves alone.

the deployment Mac's 2026-10-29 iCloud traces are part of the verbatim intent. They were not re-run here. This VM cannot run FSEvents, `clonefile`, or `launchctl`.
