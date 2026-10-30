# spec.md — path containment

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-29) |
| Status | Draft 2 |
| Stage | 2 · Design |

## 1. Summary

Lines 12–15 strip one trailing slash, then refuse when `dest == src` or `dest.hasPrefix(src + "/")`. On Swift 6.4.1 those two lines refuse `/` against `/backups`, `/tmp/data` against `/tmp/data/backup/../backup`, and they allow `/tmp/foo` against `/tmp/foobar`. They allow the hole rows: `//` against `/backups`, `/data/photos//` against `/data/photos/backup`, `/data/photos` against `/data/foo/../photos/backup`, and `/tmp/data` against `/tmp/data2/../data/backup`. There is no symlink resolution in the file. A source of `/` is already refused because `dropLast()` leaves `""` and every absolute dest has prefix `/`.

The `refused` column is the result this intent ships. Section 4 states the same outcomes. Tests assert this column.

| source | dest | refused |
|---|---|---|
| `/` | `/backups` | true |
| `//` | `/backups` | true |
| `///` | `/backups` | true |
| `/data/photos//` | `/data/photos/backup` | true |
| `/data/photos` | `/data/foo/../photos/backup` | true |
| `/tmp/data` | `/tmp/data2/../data/backup` | true |
| `/tmp/data` | `/tmp/data/backup/../backup` | true |
| `/tmp/foo` | `/tmp/foobar` | false |

## 2. Goals and non-goals

**Goals**

- G1. Refuse when the lexically normalized dest is the lexically normalized source or is inside it, or when the symlink-resolved dest is the symlink-resolved source or is inside it.
- G2. Resolve a symlink while walking: a relative target joins the link’s directory, an absolute target replaces the path walked so far, `..` applies to that stack, and a cycle is a refusal.
- G3. Keep allowing a dest that merely shares a string prefix with the source (`/tmp/foo` and `/tmp/foobar`).
- G4. Test the decision on Linux without compiling `backup-folder.swift`.

**Non-goals**

- Do not change snapshot names, retention, publish rules, or how entries inside a tree are copied. Symlink entries are [clone-walk](../clone-walk/spec.md), the following phase.
- Do not read or write `~/Backups` or `~/Backups/bin/backup-folder`. Do not push a `v*` tag.

**Release phasing.** One phase.

## 3. Principles

- P1. The check runs before `createDirectory` of dest, as it does now.
- P2. A component that does not exist yet is not looked up as a symlink. Later components still apply `..` on the stack. Dest’s final component often does not exist yet; the tool creates it after the check.
- P3. Inside means the paths are equal, or dest is source plus `/` plus more. `/tmp/foo` does not contain `/tmp/foobar`. A source that is `/` contains every absolute dest.

## 4. Users and scenarios

Each of these exits 2 with `backup dir must not be inside source` on stderr:

- `backup-folder // /some/backup`
- `backup-folder /// /some/backup`
- `backup-folder / /some/backup`
- `backup-folder /data/photos// /data/photos/backup`
- `backup-folder /data/photos /data/foo/../photos/backup`
- `backup-folder /tmp/data /tmp/data2/../data/backup`
- `backup-folder /tmp/data /tmp/data/backup/../backup`
- A source path that is a symlink to a directory, with dest inside that directory. The link target may be absolute or relative.
- Dest `/data/photos/out/backup` when source is `/data/photos` and `out` is a symlink to `/var`. Lines 14–15 refuse this today. Resolution alone would produce `/var/backup` and allow it.
- Dest whose lexical form is outside the source, and whose resolved form is inside, because `..` is applied after a symlink expands.

`backup-folder /tmp/foo /tmp/foobar` does not fail the containment check.

A symlink cycle on either argument exits 2 with the same message. The check returns.

## 5. Functional requirements

1. Add `PathCheck.swift`, Foundation only, no top-level executable code. The binary calls it for the containment decision. `backup-folder.swift` stays the only main in the binary compile.
2. Lexical normalization, used only for the lexical compare: drop every trailing slash except that `/` stays `/`, drop empty components and `.`, and apply `..` without climbing above `/`. Do not feed this collapsed path into the symlink walk. Collapsing `..` first would remove a symlink from the path before the walk sees it.
3. Symlink resolution walks the original absolute path from the root. Strip trailing slashes first. Skip empty components and `.`. Do not pre-collapse `..`. For each remaining component:
   - `..` pops one component from the resolved stack and does not climb above `/`.
   - If the component is missing, push it and keep going. Do not stat later components. `..` among them still pops the stack.
   - If the component is a symlink, read `destinationOfSymbolicLink`. On Swift 6.4.1 that call returns the stored string (`targetdir` for a link created with destination `targetdir`). A relative target is joined to the directory that contains the link. An absolute target replaces the stack. Continue the walk through the replacement, which may itself contain `..` and further links.
   - If the absolute path of a symlink about to be expanded is already on the expansion stack for this resolution, stop. That path is a cycle.
   - Otherwise push the component.
4. Refuse when the lexical compare says dest is inside source, or the resolved compare says dest is inside source. Use principle P3 for both. A cycle is a refusal. Exit 2 and write `backup dir must not be inside source` to stderr, not to the log. One compare allowing the pair does not override the other.
5. Relative arguments and a missing argument still hit the existing usage line and exit 2, before this check.
6. Linux tests assert the `refused` column in section 1 for those exact strings. They also assert, under a temp directory, all of the following as refusals:
   - an absolute symlink as source, with dest inside its target
   - a relative symlink as source, with dest inside the joined target
   - `..` after a symlink, where the lexical dest is outside the source and the resolved dest is inside it
   - source `/data/photos`-shaped, dest `…/out/backup`, with `out` an absolute symlink to a directory outside the source
   - a symlink cycle, absolute or relative, and the call returns
   `/tmp/foo` versus `/tmp/foobar` is allowed. The tests do not create symlinks on the section 1 paths.
7. One macOS smoke invocation uses a doubled trailing slash on a temp source and a dest inside it, and expects exit 2. Use `mktemp` paths only.

## 6. Acceptance criteria

- AC1. `swiftc -o path-tests PathCheck.swift tests/path-tests.swift && ./path-tests` exits 0 on Linux. `backup-folder.swift` is not in that compile. The tests assert the `refused` column and the fixtures in requirement 6.
- AC2. The `macos` smoke still prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`, and the doubled-slash case exits 2.
- AC3. `macos`, `linux`, and CodeQL are green. The `swiftc` lines in the smoke script, `release.yml`, and `codeql.yml` include `PathCheck.swift` and the files already required by snapshot-identity.
- AC4. No `v*` tag. No path under `~/Backups`.

## 7. Design decisions

**D1–D8.** Same decisions as [clone-fallback-visibility/spec.md](../clone-fallback-visibility/spec.md). This intent is global phase 5, after snapshot-identity phase 1. Clone-walk is global phase 6 and stays after this one.

**D9 — Source `/` stays refused.** The measured empty-string behavior already refuses it. The normalized rule refuses it because every absolute dest is inside `/`. The implementation does not keep the empty-string trick. `//` and `///` normalize to `/` and are refused too.

**D10 — The `refused` column is the contract.** Lines 12–15 on Swift 6.4.1 allow the hole rows named in the summary. Tests assert the column in section 1, which refuses those rows, in agreement with section 4. `/tmp/foo` versus `/tmp/foobar` stays allowed.

**D11 — Both compares.** Linux Foundation `attributesOfItem` reported `NSFileTypeSymbolicLink` while `fileExists` reported the target (2026-10-30, Swift 6.4.1). The path check uses `destinationOfSymbolicLink`, not `fileExists`. A resolved-only compare allows source `/data/photos` and dest `/data/photos/out/backup` when `out` points at `/var`, and lines 14–15 refuse that pair today. `createDirectory` would follow `out`, and lines 46–48 still follow a directory symlink until clone-walk. Refuse when either compare says inside.

**D12 — `..` during the walk.** Requirement 2’s collapse is only the lexical compare. The symlink walk applies `..` to the stack after a link has been replaced, so the link affects the resolved path.

## 8. Open questions

None.
