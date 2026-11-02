# spec.md — Nested drop

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-11-02) |
| Status | Draft 1 |
| Stage | 2 · Design |

## 1. Summary

`drop-box-watcher` claims only a direct child of the watch folder, and it skips directories. A folder drop therefore logs FSEvents and file-presenter callbacks for the subfolder and for each file inside it, and never logs `webhook enqueue`.

This change treats a regular file at any depth under the watch folder as in scope. Readiness, the ignore list, the claim triple, and the webhook body stay as they are. One presenter-queue pass submits at most once. A direct-child directory is the walk root for itself and for everything under it, so a complete dropped folder is one nudge. A direct-child file stays a one-file pass. A path that is gone, a directory, or an ignored leaf name is not a nudge. Deleting an emptied subfolder does not submit.

## 2. Goals and non-goals

**Goals**

- G1. A regular file that becomes ready anywhere under the watch folder is claimed and enqueued the same way a ready top-level file is.
- G2. Ignore matching stays the current file-name matcher. A path is ignored only when its own last component matches, including `.DS_Store`, `.*`, `*.icloud`, `*.download`, `*.crdownload`, and `*.part`. Ancestor names are not an extra filter.
- G3. Readiness stays the pure decision and the coordinated read. No settle delay, no readiness timer, FSEvents latency stays `0`.
- G4. A dropped folder whose files are already in the tree when the first in-scope event is handled produces one webhook for those newly ready files, not one webhook per FSEvents or presenter callback.
- G5. Deleting an emptied subfolder after that dispatch does not send a webhook.
- G6. Darwin-free tests cover scope selection. The macOS smoke covers a nested drop and the emptied-folder delete.
- G7. Long-lived docs state the new depth, the shared nudge, and the empty-folder delete, in generic words.

**Non-goals**

- Do not add a sleep, a debounce, or a latency above `0` on the readiness path.
- Do not change `readinessDecision`, the claim triple `(standardized path, inode, size)`, or `WebhookNotifier` retry and merge behavior.
- Do not add JSON fields. `files` stays a list of basenames. Duplicate basenames in one body still collapse. The receiver lists the tree; this repo does not change that routine.
- Do not follow symbolic links, and do not notify for a directory.
- Do not move, rename, edit, or delete files, and do not create the watch folder.
- Do not change the config schema, the example TOML, or the LaunchAgent template.
- Do not edit other `intent/` folders. The drop-box-watcher intent stays the historical record.
- Do not install the binary, write a live config, load a LaunchAgent, or write under a home `Backups` directory.
- Do not add a release label or push a tag by hand. Do not change `scripts/release-version.sh` or `.github/workflows/release.yml`.

**Release phasing.** Behavior, tests, and docs are one build phase. Nothing in this change is cut to a later intent. A new idea after this ships starts a new `intent/<slug>/`.

## 3. Principles

- P1. The settled no-timer rule stays closed. Joining events is a tree walk on the pass that already runs, not a wait.
- P2. A second callback for a claim triple that is already held does nothing.
- P3. The watcher still only notifies. `startDownloadingUbiquitousItem(at:)` remains the one iCloud request, and only when the pure decision says request download.
- P4. Docs and tests stay generic. Prose about this repo says "this repo".

## 4. Users and scenarios

- S1. **Top-level file.** A regular file created in the watch folder is still one nudge with its basename. A later size change is still another nudge. `.DS_Store` is still not named.
- S2. **Nested file.** A regular file created at any depth under the watch folder is one nudge with its basename once it is ready.
- S3. **Dropped folder.** A directory tree moved into the watch folder, already holding its files, produces one nudge. The body names each newly ready markdown file once and does not name the directory or `.DS_Store`.
- S4. **Files that become ready at different times.** Each pass submits only claims that are new in that pass. Extra FSEvents or presenter callbacks for an already claimed triple do not submit again. No timer joins passes.
- S5. **Emptied folder removed.** After the nudge, the files are removed and the empty directories are removed. No further nudge.
- S6. **Startup.** Files already present at any depth are one startup batch, same as today's one batch for the root.

## 5. Functional requirements

FR1. **Scope.** A path is in scope when its symlink-resolved, standardized path is the resolved watch folder or a descendant. Compare with a boundary slash, so a sibling whose name only shares a prefix is out of scope. Strip a leading `/private` on both sides before the compare, the same way the watcher already treats `/tmp` and `/private/tmp` as one folder. A resolved path outside the watch folder is out of scope.

FR2. **Candidates.** Add a Foundation-only helper, `drop-box-watcher/WatchScope.swift`, with no `CoreServices` import and no sleep. Given the resolved watch folder, an event URL, the ignore patterns, and directory-enumeration options, it returns the regular-file URLs that this pass rechecks. It does not claim, coordinate, or call `startDownloadingUbiquitousItem`.

- A missing path returns an empty list.
- An out-of-scope path returns an empty list.
- The event is the watch folder: walk the watch folder.
- The event is a direct-child regular file: return that file alone when its own name is not ignored. Do not include siblings.
- The event is a direct-child directory, including the dropped folder itself: walk that directory and not the rest of the watch folder. A directory is in scope as a walk root; it is not a returned file.
- The event is nested under a direct-child directory: walk that direct-child directory, so one nested file event also returns the other regular files already under that same child, and does not return a regular file that sits in a different top-level child.
- A regular file whose own name matches the ignore list is omitted. A directory name is not an extra filter. Children of a directory whose name would match the list are still returned when their own names do not match.
- Symbolic links are not followed and are not returned. `resolvingSymlinksInPath` on a symlink is only for the scope check, which rejects a target outside the watch folder.
- Each directory inode (device plus file number) is entered at most once per call. A directory whose ids are missing is not entered.
- The startup scan calls this helper on the watch folder with `.skipsHiddenFiles`. Event passes call it without that option. The ignore list still applies on both.

FR3. **Readiness.** Each candidate goes through the existing `readinessDecision` and the existing claim path. Ignored names, directories, and symbolic links still skip. A non-ubiquitous regular file, or a ubiquitous file that is `.current` and not downloading, is ready. Any other ubiquitous result requests `startDownloadingUbiquitousItem(at:)` on that file, logs a thrown error, and does not claim. There is no retry timer. Do not change the decision function.

FR4. **One submit per pass.** One callback's URLs are one pass on the serial presenter queue. The pass unions the candidate lists, rechecks each standardized path once, and calls `submit` once with the claims that were not already held. An empty claim list does not call `submit` and does not log `webhook enqueue`. A later pass that finds the same `(path, inode, size)` does not submit. FSEvents latency stays `0`, with the same flags as today: file events, CF types, and no defer.

FR5. **Disappear and delete.** `presentedSubitemDidDisappear(at:)` drops claim keys for that standardized path only. It does not drop claims for other paths, it does not walk, it does not submit, and it does not request a download. A pass prunes claims whose paths no longer exist, by exact standardized path, and a missing event path adds no candidate. A directory is never a `files` entry. Removing files, then removing the emptied directories, does not submit: the files are gone before the walk can claim them, and the directory was never a claim. A path-prefix compare is not used to drop claims. The FR1 boundary slash is only for deciding what is inside the watch folder.

FR6. **Move.** The move callback still rechecks the new URL only. The new URL goes through FR1. A new URL outside the watch folder adds no candidate and does not submit. The old path's claim is dropped when that path is gone, by FR5 or by the existing missing-path prune.

FR7. **Payload.** Unchanged. The body is `event_time` plus `files`, basenames in first-seen order, duplicates removed. The log line stays `webhook enqueue files=` plus those basenames. The key is still never logged.

FR8. **Triggers.** Keep both the file presenter and the FSEvents stream. Do not filter on event flags. Presenter callbacks for a nested URL stay in scope; Apple's `presentedSubitemDidChange(at:)` document says the item need not be at the top level and may sit in a nested subdirectory. The file-events flag asks for events about individual files in the watched hierarchy.

FR9. **Tests.** Darwin-free tests build a temporary tree and assert the candidate lists in FR2. One nested file event returns the other regular files under that same top-level child, including a deeper file, and does not return a regular file in a different top-level child. A direct-child file does not return siblings. An ignored file name is omitted, including `.DS_Store` inside a subdirectory. A file whose own name does not match is returned even when a parent directory's name matches the ignore list. A symlink to an outside directory contributes nothing. A missing path and a sibling path return empty. The `/private` prefix compare matches. The macOS smoke keeps the current top-level file, `.DS_Store`, grow, and config-reload cases. It adds a same-volume move of a finished tree into the watch folder, a one-second harness quiet period so later callbacks cannot hide a second POST, and an emptied-folder delete, as in the acceptance criteria. The product readiness path still does not sleep. The harness may poll and may wait the same one second the `.DS_Store` case already waits. Files that become ready on later passes (S4) are FR4; they are not a separate smoke, because separating those writes would be a timer.

FR10. **Docs.** In the same build phase, update the watcher paragraph in `README.md`, the startup-scan sentence in `docs/setup.md`, and the watcher sentences in `AGENTS.md`. Say that a ready file at any depth is a nudge, that files already in one top-level child share one nudge for the triples that are new in that pass, that the ignore list is unchanged, and that deleting an emptied folder does not nudge. Do not add a lecture on basename collapse; FR7 holds that. Keep `docs/setup.md` at 33 Manual/Script bullets and `docs/restore.md` at 7. Do not add a hostname, a machine path, or a personal name.

## 6. Acceptance criteria

AC1. `bash tests/linux-unit.sh` exits 0 and prints `linux-unit: OK`. The new scope tests cover FR2: a nested file event returns the sibling regular files under that top-level child, including a deeper file, and does not return a regular file in a different top-level child; a direct-child file does not return siblings; `.DS_Store` inside a subdirectory is omitted; a file under a directory whose name matches the ignore list is still returned when its own name does not match; a symlink to an outside directory contributes nothing; a missing path and a sibling path return empty; the `/private` prefix compare matches. `WatchScope.swift` and `Watcher.swift` contain no `Task.sleep`, `usleep`, `sleep(`, `Timer`, or `asyncAfter`. `WatchScope.swift` contains no `startDownloadingUbiquitousItem`.

AC2. The existing readiness table still matches the current decision, including directory and symlink skip. `Readiness.swift` is unchanged in behavior.

AC3. On macOS, `bash tests/macos-watcher.sh` still prints `macos-watcher: build OK`, `macos-watcher: notify OK`, and `macos-watcher: unchanged OK`, including the top-level file, the ignored `.DS_Store`, the size change, and the config-reload cases.

AC4. In that same smoke, a tree prepared outside the watch folder and moved in on the same volume, containing `a.md`, `b.md`, `nested/c.md`, and `.DS_Store`, produces exactly one new POST. The POST's `files` set is exactly `a.md`, `b.md`, and `c.md`. The operational log gains exactly one new `webhook enqueue` line for that move. The line names those three basenames and does not name `.DS_Store` or the directory. The harness then waits one second and asserts the POST count and the enqueue count are still that one.

AC5. After AC4, the smoke deletes those three files and then the emptied directories. It waits one second in the harness. The POST count is unchanged, and the log gains no new `webhook enqueue` line.

AC6. In that same smoke, creating one regular file two directories down (`level/inner/only.md`) produces exactly one new POST whose `files` array is `["only.md"]`.

AC7. `README.md`, `docs/setup.md`, and `AGENTS.md` match FR10. `bash tests/setup-docs.sh` prints `setup-docs: all checks passed`. `bash tests/no-secrets.sh` prints `no-secrets: all checks passed`.

## 7. Design decisions

**D1 — Descendants are in scope. The direct-child gate is the bug.** Checked in `drop-box-watcher/Watcher.swift` on 2026-11-02. `recheck` returns immediately unless `isDirectChild` is true (`deletingLastPathComponent` equals the resolved watch folder). `readinessDecision` returns `.skip` for a directory. `startupScan` uses `contentsOfDirectory`, which lists one level. A nested file never reaches the claim, so the process never logs `webhook enqueue`. The fix removes that gate and selects candidates with FR2. What was rejected: notifying for the directory path itself. A directory is not a file the routine should move.

**D2 — No timer, restated and closed.** FSEvents is still created with latency `0` and `kFSEventStreamCreateFlagNoDefer`. The only sleeps in the watcher stay inside `WebhookNotifier` after a failed POST. A harness wait is not a product wait. What was rejected: a settle window to coalesce a folder drop. The intent keeps that rule closed.

**D3 — One nudge is one pass over one walk root, not one callback.** Apple's file-events flag, fetched 2026-11-02 from the CoreServices documentation JSON, requests events about individual files in the hierarchy, and it warns that this produces many more events. A callback-per-file submit would be one webhook per event once nested files are eligible. The walk root is the watch folder only when the event is the watch folder. A direct-child directory, including the dropped folder in the intent, is the walk root for itself. A nested path walks that same direct-child directory, so the other files already there are in the same pass. A direct-child regular file stays a one-file pass. The pass submits each new claim once. Later callbacks for those triples find the claim set and do not submit. When the files are already linked into the tree (a same-volume rename), the first pass sees all of them and the POST count is one. When files become ready later, each pass submits only the new triples. That is S4, and it is not a timer. What was rejected: buffering callbacks for a fixed delay, and walking the entire watch folder on every nested event (a nested drop must not depend on unrelated top-level names being new).

**D4 — Ignore rules stay the leaf-name matcher.** Patterns still match one path component, case-sensitive, no `/`, using `nameMatchesAnyIgnorePattern`. `.DS_Store` inside a dropped folder is omitted because its own name matches, the same as at the root. A parent directory whose name matches the list does not hide a child whose name does not match. The intent asked for the same ignore rules, and today's decision tests only the leaf. What was rejected: a new ancestor rule, and a new pattern language.

**D5 — Do not follow symlinks.** Checked on the Linux Foundation in this environment on 2026-11-02. `FileManager.enumerator(at:includingPropertiesForKeys:options:)` listed a directory symlink as `isSymbolicLink` and did not list the file in the outside target. `resolvingSymlinksInPath` on that symlink returned the outside directory. The helper therefore refuses a resolved path outside the watch folder and does not enter a symlink. A missing device or file number does not enter, so a cycle cannot repeat. What was rejected: sharing `WalkPolicy` from the snapshot target. The watcher target does not compile those sources.

**D6 — Payload stays basenames.** The drop-box-watcher spec already locks `event_time` and `files` of basenames, and it says the receiver lists the folder and does not depend on the names. Nested files use that same body. Two files with the same basename still collapse inside one body. What was rejected: relative paths or an extra JSON field. That would be a different contract for the routine.

**D7 — Startup uses the same walk.** A file that arrived while the process was down is the startup scan's job today, at the root only. The scan calls FR2 on the watch folder so a nested file is in the same single batch. `.skipsHiddenFiles` stays on that scan only. Event passes rely on the ignore list, because FSEvents does not skip hidden names. Checked the same day: with `.skipsHiddenFiles`, the enumerator omitted `.DS_Store` and still listed `nested/c.md`.

**D8 — Delete does not walk and does not submit.** The emptied directory is not a regular file, so it is not a candidate. Disappear clears that path's claim only. It does not clear sibling claims and it does not start a walk. The next pass drops a claim only when that exact path is gone, then claims what is still ready and new. A file that is already gone cannot be claimed again. What was rejected: dropping every descendant claim when a directory disappears (a later walk would treat files that are still there as new), and a delete grace timer.

**D9 — Presenter callbacks already name nested URLs.** Fetched 2026-11-02 from Apple's documentation JSON for `presentedSubitemDidChange(at:)`, `presentedSubitemDidAppear(at:)`, and `presentedSubitem(at:didMoveTo:)`. Each says the item need not be at the top level of the presented directory and may itself be inside a nested subdirectory. The observed callbacks for the subfolder and for each file match that, and they match the file-events flag. This draft did not run a watcher on a Mac and does not invent which flags fired.

**D10 — Publish behavior is unchanged.** `.github/workflows/release.yml` runs job `publish` on every push to `main`. `scripts/release-version.sh` reads `(#N)` from the squash-merge subject and, with no `release:minor` or `release:major` label, prints the next patch tag. A merge of this design, and a later merge of the build, can each publish that patch for the binaries already built. This intent does not change that job. Agents do not push a tag by hand.

## 8. Open questions

None. The intent's question is closed by D3.
