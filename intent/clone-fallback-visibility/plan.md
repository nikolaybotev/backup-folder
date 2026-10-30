# plan.md — clone fallback visibility

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

Global phase 1 of 6. [D8](spec.md).

## Stops

None.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `bash tests/macos-smoke.sh` on the `macos` runner, including `4 files, 0 full copies` (see Build notes) | 0 |
| AC2 | same script, exit 2 cases | 0 |
| AC3 | GitHub Actions jobs `macos` and CodeQL | 0 |
| AC4 | diff has no tag and no `~/Backups` path | 0 |

## Phase 0 — Log clone fallback

Files: `backup-folder.swift`, `tests/macos-smoke.sh`, `README.md`, `AGENTS.md` only if a command in this phase changes (it should not).

1. In `cloneTree`, when `clonefile` returns non-zero, read `errno` before `copyItem`. On a successful copy, log `WARNING: clonefile failed for <path> (errno <n>); full copy` and count a fallback. Do not increment `failures`.
2. Change the success line to `OK snapshot <ts> (<count> files, <fallbacks> full copies)`.
3. Make `log` write the same line to stderr. Set that formatter’s locale to `en_US_POSIX`. Leave the snapshot-name formatter alone.
4. Replace `try?` on `dest`’s `createDirectory` with a catch that writes `ERROR: cannot create <dest>: <error>` to stderr and exits 1.
5. In `tests/macos-smoke.sh`, after the success snapshot, assert the log contains the file count the fixture actually snapshots (`4 files, 0 full copies`; see Build notes). Leave the directory-name filter `_[0-9]{4}$` as it is. Leave the final echo as it is.
6. Update the README sentence that describes the fallback so it says the log records a full copy. Do not describe retention or names differently.
7. Do not add a Swift file. Do not edit `release.yml`, `codeql.yml`, `test.yml`, or the protect-main script.

DoD: the pull request’s `macos` job is green and the CodeQL job is green. On the Linux cloud VM, before opening the PR, `swiftc -parse backup-folder.swift` exits 0. Do not claim the smoke script passed locally.

### Build notes (Phase 0)

**Departure from spec (AC1 / FR7):** [spec.md](spec.md) assumes the smoke fixture is two regular files (`a.txt`, `sub/b.txt`). The same `$SRC` temp dir also holds `clone-probe-src.txt` and `clone-probe-dst.txt` from the clonefile probe, so the published snapshot logs `4 files, 0 full copies`. Phase 0 asserts that count instead of `2 files, 0 full copies`.
