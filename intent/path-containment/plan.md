# plan.md — path containment

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

Global phase 5 of 6. Start after snapshot-identity phase 1 is merged. The `linux` job already exists.

## Stops

None.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `swiftc -o path-tests PathCheck.swift tests/path-tests.swift && ./path-tests` | 0 |
| AC2 | `macos` smoke, including the doubled-slash exit 2 | 0 |
| AC3 | Actions `macos`, `linux`, and CodeQL; three `swiftc` lines list `PathCheck.swift` | 0 |
| AC4 | diff has no tag and no `~/Backups` path | 0 |

## Phase 0 — Normalize before the containment check

Files: `PathCheck.swift`, `tests/path-tests.swift`, `backup-folder.swift`, `tests/macos-smoke.sh`, `.github/workflows/test.yml`, `.github/workflows/release.yml`, `.github/workflows/codeql.yml`, `README.md`, `AGENTS.md`.

1. Add `PathCheck.swift` (Foundation only, no top-level executable code) and the Linux main `tests/path-tests.swift` covering spec requirements 2, 3, and 6. `backup-folder.swift` stays the only main in the binary compile. Wire the containment check to the new file, before `createDirectory` of dest. Keep the usage exit 2 for non-absolute arguments.
2. Add the path-test command to the existing `linux` job. Do not compile `backup-folder.swift` there.
3. Add `PathCheck.swift` to the `swiftc -O -o backup-folder` line in `tests/macos-smoke.sh`, `release.yml`, and `codeql.yml`, beside the files those lines already compile.
4. Add one doubled-slash smoke invocation on `mktemp` paths and expect exit 2. Leave the success echo unchanged.
5. Update the README sentence that says the tool strips a trailing slash and compares strings, so it describes normalized paths. Update the `AGENTS.md` build command so it lists the new file.

DoD: the path-test command exits 0 locally, and `swiftc -parse backup-folder.swift` exits 0. The pull request’s `macos`, `linux`, and CodeQL jobs are green.

### Build notes (Phase 0)

Added only after the phase lands.
