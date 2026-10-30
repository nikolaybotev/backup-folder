# plan.md — honest snapshot

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

Global phase 2 of 6. Start after clone-fallback-visibility phase 0 is merged.

## Stops

None.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | existing `bash tests/macos-smoke.sh` success path | 0 |
| AC2 | new mode-`000` case in that script | 0 |
| AC3 | Actions jobs `macos` and CodeQL | 0 |
| AC4 | diff has no tag and no `~/Backups` path | 0 |

## Phase 0 — Do not publish a failed walk

Files: `backup-folder.swift`, `tests/macos-smoke.sh`, `README.md`.

1. After `cloneTree`, when `failures > 0`, log `ERROR: <n> item(s) failed in <ts>; not publishing`, remove only this run’s temp directory, and exit 1. Skip `moveItem`, the `OK` line, and the prune loop.
2. Leave the `failures == 0` path, the name format, and the prune predicates as they are. Do not count a clone fallback as a failure.
3. Extend `tests/macos-smoke.sh` with a second source and dest from `mktemp`. Create a subdirectory, `chmod 000` it, run the tool, and assert AC2. In the existing `EXIT` trap, `chmod -R u+rwx` the failure fixture before `rm`. Keep the success fixture’s `_[0-9]{4}$` filter and the `4 files, 0 full copies` assertion (plan step 3 previously said `2 files`; main after clone-fallback-visibility uses four counted files in the success smoke).
4. Update the README sentence that says the temp directory is renamed when the walk finishes, so it says the rename happens when every item succeeded.
5. Do not add a Swift file or a Linux job. Do not edit `release.yml`, `codeql.yml`, or the protect-main script.

DoD: the pull request’s `macos` job is green and the CodeQL job is green. On Linux, `swiftc -parse backup-folder.swift` exits 0 before the PR opens. Do not claim the smoke script passed locally. New tests stay inside the 20-minute job; this case is one short process.

### Build notes (Phase 0)

Added only after the phase lands.
