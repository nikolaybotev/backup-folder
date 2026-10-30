# plan.md — clone walk

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

Global phase 6 of 6. Start after path-containment phase 0 is merged. honest-snapshot is already merged, so item failures do not publish.

## Stops

None.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `swiftc -o walk-tests WalkPolicy.swift tests/walk-tests.swift && ./walk-tests` | 0 |
| AC2 | `macos` smoke symlink assertion and fifo case with a 10-second kill | 0 |
| AC3 | Actions `macos`, `linux`, and CodeQL; three `swiftc` lines list `WalkPolicy.swift` | 0 |
| AC4 | diff has no tag, no `~/Backups` path, and no directory `clonefile` | 0 |

## Phase 0 — Clone links, skip special files, stop cycles

Files: `WalkPolicy.swift`, `tests/walk-tests.swift`, `backup-folder.swift`, `tests/macos-smoke.sh`, `.github/workflows/test.yml`, `.github/workflows/release.yml`, `.github/workflows/codeql.yml`, `README.md`, `AGENTS.md`.

1. Add `WalkPolicy.swift` (Foundation only, no top-level executable code) with the enter-or-stop decision, and a Linux main that tests a first visit, a repeat, and a missing id. `backup-folder.swift` stays the only main in the binary compile. Call the new function from the directory branch.
2. Replace the `fileExists` branch with `attributesOfItem` and the five requirements in the spec. Leave regular-file fallback logging in place. Do not call `clonefile` on a directory. Do not edit `PathCheck.swift`, and do not drop its lexical refusal.
3. Add the walk-test command to the `linux` job. Do not compile `backup-folder.swift` there.
4. Add `WalkPolicy.swift` to the three `swiftc -O -o backup-folder` lines.
5. Extend the smoke script with a `mktemp` source that holds a directory symlink, and with a fifo case guarded by a 10-second kill. Keep the success echo. Restore permissions and remove the fifo in the trap.
6. Update the README walk paragraph: symlinks are cloned as symlinks, special files are not copied, and a failed item does not publish. Update the `AGENTS.md` build command so it lists the new file.

DoD: the walk-test command exits 0 locally, and `swiftc -parse backup-folder.swift` exits 0. The pull request’s `macos`, `linux`, and CodeQL jobs are green. The fifo case must not be able to run for the rest of the 20-minute job.

### Build notes (Phase 0)

Added only after the phase lands.
