# plan.md — path containment

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 2 |
| Status | Draft 2 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

Global phase 5 of 6. Start after snapshot-identity phase 1 is merged. Clone-walk stays the following phase. The `linux` job already exists.

## Stops

None.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `swiftc -o path-tests PathCheck.swift tests/path-tests.swift && ./path-tests`, asserting the `refused` column and requirement 6 fixtures | 0 |
| AC2 | `macos` smoke, including the doubled-slash exit 2 | 0 |
| AC3 | Actions `macos`, `linux`, and CodeQL; three `swiftc` lines list `PathCheck.swift` | 0 |
| AC4 | diff has no tag and no `~/Backups` path | 0 |

## Phase 0 — Normalize before the containment check

Files: `PathCheck.swift`, `tests/path-tests.swift`, `backup-folder.swift`, `tests/macos-smoke.sh`, `.github/workflows/test.yml`, `.github/workflows/release.yml`, `.github/workflows/codeql.yml`, `README.md`, `AGENTS.md`.

1. Add `PathCheck.swift` (Foundation only, no top-level executable code) implementing spec requirements 2, 3, and 4: a lexical compare, and a symlink walk that joins a relative target to the link’s directory, replaces the stack with an absolute target, applies `..` on that stack, and treats a cycle as inside. Refuse when either compare says inside. `backup-folder.swift` stays the only main in the binary compile. Wire the containment check to the new file, before `createDirectory` of dest. Keep the usage exit 2 for non-absolute arguments.
2. Add the Linux main `tests/path-tests.swift`. Assert every row of the `refused` column in spec section 1. Those booleans match section 4: the hole rows are refused, and `/tmp/foo` versus `/tmp/foobar` is allowed. Assert the requirement 6 fixtures: an absolute link, a relative link, `..` after a symlink (lexical dest outside, resolved inside), a dest that is lexically inside the source when an intermediate component is a symlink to outside, and a symlink cycle that returns.
3. Add the path-test command to the existing `linux` job. Do not compile `backup-folder.swift` there.
4. Add `PathCheck.swift` to the backup-folder build via `tests/build-backup-folder.sh` (used by `tests/macos-smoke.sh`, `release.yml`, and `codeql.yml`), beside `Retention.swift`. Do not use a single in-place multi-file `swiftc` on `backup-folder.swift` and `PathCheck.swift` (only `main.swift` may hold top-level code).
5. Add one doubled-slash smoke invocation on `mktemp` paths and expect exit 2. Leave the success echo unchanged.
6. Update the README sentence that says the tool strips a trailing slash and compares strings, so it describes the lexical-or-resolved refusal. Update the `AGENTS.md` build command so it lists the new file.

DoD: the path-test command exits 0 locally, and `swiftc -parse backup-folder.swift` exits 0. The pull request’s `macos`, `linux`, and CodeQL jobs are green.

### Build notes (Phase 0)

- Binary build lists `PathCheck.swift` in `tests/build-backup-folder.sh` with an absolute or cwd-relative `-o` path (not `$ROOT/$OUT` when `OUT` is already absolute). `release.yml` and `codeql.yml` invoke that script; they do not embed a separate `swiftc` file list.
- Plan step 2 originally mis-stated one requirement 6 fixture; tests match spec section 6 (`..` after a symlink with lexical outside and resolved inside).
