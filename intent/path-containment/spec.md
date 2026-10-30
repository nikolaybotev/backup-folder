# spec.md — path containment

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-29) |
| Status | Draft 1 |
| Stage | 2 · Design |

## 1. Summary

Lines 12–15 strip one trailing slash, then refuse when `dest == src` or `dest.hasPrefix(src + "/")`. The same two lines, run on Swift 6.4.1 on 2026-10-30, gave:

| source | dest | refused |
|---|---|---|
| `/` | `/backups` | true |
| `//` | `/backups` | false |
| `/data/photos//` | `/data/photos/backup` | false |
| `/data/photos` | `/data/foo/../photos/backup` | false |
| `/tmp/data` | `/tmp/data2/../data/backup` | false |
| `/tmp/data` | `/tmp/data/backup/../backup` | true |
| `/tmp/foo` | `/tmp/foobar` | false |

There is no symlink resolution in the file. A source of `/` is already refused because `dropLast()` leaves `""` and every absolute dest has prefix `/`. The holes are the extra slash and the `..` form that is not a string prefix. This intent closes those holes before the walk.

## 2. Goals and non-goals

**Goals**

- G1. Refuse when the normalized dest is the normalized source or is inside it.
- G2. Resolve existing symlinks before that comparison.
- G3. Keep allowing a dest that merely shares a string prefix with the source (`/tmp/foo` and `/tmp/foobar`).
- G4. Test the decision on Linux without compiling `backup-folder.swift`.

**Non-goals**

- Do not change snapshot names, retention, publish rules, or how entries inside a tree are copied. Symlink entries are clone-walk.
- Do not read or write `~/Backups` or `~/Backups/bin/backup-folder`. Do not push a `v*` tag.

**Release phasing.** One phase.

## 3. Principles

- P1. The check runs before `createDirectory` of dest, as it does now.
- P2. A component that does not exist yet is not looked up as a symlink. The rest of the path stays lexical. Dest often does not exist yet; the tool creates it after the check.

## 4. Users and scenarios

- `backup-folder // /some/backup` exits 2.
- `backup-folder /data/photos// /data/photos/backup` exits 2.
- `backup-folder /data/photos /data/foo/../photos/backup` exits 2.
- `backup-folder /tmp/foo /tmp/foobar` does not fail the containment check.
- A source path that is a symlink to a directory, with dest inside that directory, exits 2.

## 5. Functional requirements

1. Add `PathCheck.swift`, Foundation only. The binary calls it for the containment decision.
2. Normalize an absolute path by dropping every trailing slash except that `/` stays `/`, dropping empty components and `.`, and applying `..` without climbing above `/`. Compare the results only after a separating `/`, so `/tmp/foo` does not contain `/tmp/foobar`.
3. Before the lexical compare, resolve both paths against the filesystem: walk from the root, and when a component is a symlink, replace it with its target and continue. When a component is missing, keep the remaining components lexical.
4. Refuse when the two results are equal or when dest is inside source, including when source normalizes to `/`. Exit 2 and write `backup dir must not be inside source` to stderr, not to the log.
5. Relative arguments and a missing argument still hit the existing usage line and exit 2, before this check.
6. Linux tests cover every row of the table in section 1. Source `/` and source `///` are refused, because both normalize to `/`. A real symlink created in a temp directory, whose target contains the dest, is refused. The `/tmp/foobar` row must be allowed.
7. One macOS smoke invocation uses a doubled trailing slash on a temp source and a dest inside it, and expects exit 2. Use `mktemp` paths only.

## 6. Acceptance criteria

- AC1. `swiftc -o path-tests PathCheck.swift tests/path-tests.swift && ./path-tests` exits 0 on Linux. `backup-folder.swift` is not in that compile.
- AC2. The `macos` smoke still prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`, and the doubled-slash case exits 2.
- AC3. `macos`, `linux`, and CodeQL are green. The `swiftc` lines in the smoke script, `release.yml`, and `codeql.yml` include `PathCheck.swift` and the files already required by snapshot-identity.
- AC4. No `v*` tag. No path under `~/Backups`.

## 7. Design decisions

**D1–D8.** Same decisions as [clone-fallback-visibility/spec.md](../clone-fallback-visibility/spec.md). This intent is global phase 5, after snapshot-identity phase 1.

**D9 — Source `/` stays refused.** The measured empty-string behavior already refuses it. The normalized rule refuses it because every absolute dest is inside `/`. The implementation does not keep the empty-string trick.

**D10 — The table is the contract.** Those rows were produced by executing the current two lines, not by reading the orientation note. The orientation’s claim that source `/` is accepted is the row this table shows as refused.

**D11 — Symlink resolution is part of the same function the Linux test calls.** Linux Foundation created a symlink and `attributesOfItem` reported `NSFileTypeSymbolicLink` while `fileExists` reported the target (2026-10-30, Swift 6.4.1). The path check uses link-aware resolution, not `fileExists`.

## 8. Open questions

None.
