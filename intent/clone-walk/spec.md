# spec.md — clone walk

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-29) |
| Status | Draft 1 |
| Stage | 2 · Design |

## 1. Summary

Lines 46–48 classify with `fileExists(_:isDirectory:)`. Apple’s documentation says that method traverses a final symbolic link and sets `isDirectory` from the target. A symlink to a directory is therefore recursed, and `CLONE_NOFOLLOW` on line 49 never sees it. Line 47’s `else { continue }` skips a missing path and leaves `failures` unchanged, so the run can still log `OK`. Line 50 calls `copyItem` for every non-directory `clonefile` misses, which includes a fifo. There is no set of directories already entered. On Swift 6.4.1 Linux, `attributesOfItem` reported `NSFileTypeSymbolicLink` for a directory link, a broken link, and a file link, while `fileExists` reported the target (and false for the broken link). The same `attributesOfItem` dictionary included `NSFileSystemNumber` and `NSFileSystemFileNumber`. This intent classifies with `attributesOfItem` and publishes only through the honest-snapshot rule.

## 2. Goals and non-goals

**Goals**

- G1. A symlink is reproduced with `clonefile` and `CLONE_NOFOLLOW`, and is not walked and not passed to `copyItem`.
- G2. A fifo, socket, or other non-regular node is logged, counts as a failure, and is not passed to `clonefile` or `copyItem`.
- G3. A directory whose device and inode were already entered counts as a failure and is not entered again.
- G4. A listed name that then disappears counts as a failure. The honest-snapshot rule then refuses to publish.

**Non-goals**

- Do not preserve hard-link identity. Two names that share an inode become two clones. That is what a per-entry clone already does.
- Do not copy directory modes, ACLs, or xattrs as a requirement.
- Do not call `clonefile` on a directory.
- Do not narrow [path-containment](../path-containment/spec.md) to a resolved-only compare. That phase refuses when either the lexically normalized dest or the symlink-resolved dest is inside the source, which keeps a dest that `backup-folder.swift` lines 14–15 refuse today. This phase changes entries inside the tree. It leaves that argument check as specified there.
- Do not read or write `~/Backups` or `~/Backups/bin/backup-folder`. Do not push a `v*` tag.

**Release phasing.** One phase. It depends on honest-snapshot already refusing to publish when `failures > 0`.

## 3. Principles

- P1. Classification uses `attributesOfItem`, which reported the link itself on the Linux Foundation used to check this. It does not use `fileExists(_:isDirectory:)` for the branch decision.
- P2. The fallback log from clone-fallback-visibility still applies to regular files, and only to regular files.

## 4. Users and scenarios

- A symlink to a directory becomes a symlink in the snapshot, not a copy of the target tree.
- A broken symlink becomes a symlink. It is not a missing file.
- A fifo in the source makes the run exit 1 quickly, with no new snapshot directory.
- A directory reached twice through a cycle does not recurse without bound.

## 5. Functional requirements

1. For each listed name, call `attributesOfItem`. On throw, log an error, increment `failures`, and continue to the next name.
2. `NSFileTypeSymbolicLink`: `clonefile` with `CLONE_NOFOLLOW`. On non-zero, log the errno and increment `failures`. Do not call `copyItem`.
3. `NSFileTypeDirectory`: if `(systemNumber, systemFileNumber)` is already in the visited set, log `ERROR: cycle <path>`, increment `failures`, and do not recurse. Otherwise insert the pair and recurse. If either key is missing, increment `failures` and do not recurse.
4. `NSFileTypeRegular`: keep today’s `clonefile` then `copyItem` fallback, including the full-copy warning.
5. Any other type: log `ERROR: skip special file <path> (<type>)`, increment `failures`, and call neither `clonefile` nor `copyItem`.
6. A pure function in `WalkPolicy.swift` (Foundation only) answers whether an id may be entered given the set already seen. Linux tests cover a first visit, a repeat visit, and a missing id. The binary uses that function with the attribute pair.
7. The macOS smoke builds a temp source with a directory symlink and asserts the published entry is a symlink (`test -L`) whose target is the source link’s target, and that the snapshot does not contain a real directory of the target’s children.
8. The macOS smoke also runs against a source that contains a fifo. The process must exit within 10 seconds. The harness kills it and fails the script if it is still running. The exit is non-zero, the log contains `skip special file`, and that dest gains no snapshot directory. The trap removes the fifo.
9. Do not publish when these new failures increment `failures`. That is honest-snapshot’s rule; do not reintroduce `moveItem` on a non-zero `failures`.

## 6. Acceptance criteria

- AC1. `swiftc -o walk-tests WalkPolicy.swift tests/walk-tests.swift && ./walk-tests` exits 0 on Linux.
- AC2. The success smoke echo is unchanged, the symlink assertion holds, and the fifo case exits non-zero within 10 seconds with no snapshot directory.
- AC3. `macos`, `linux`, and CodeQL are green. The three `swiftc` binary lines include `WalkPolicy.swift` and the earlier files.
- AC4. No `v*` tag. No path under `~/Backups`. No `clonefile` call whose path is a directory.

## 7. Design decisions

**D1–D8.** Same decisions as [clone-fallback-visibility/spec.md](../clone-fallback-visibility/spec.md). This intent is global phase 6, after path-containment phase 0 and after honest-snapshot.

**D9 — `copyItem` is only for regular files.** The current non-directory branch has no type test. A fifo fixture is banned in honest-snapshot because that branch can block. This phase removes the call, and the 10-second kill is what keeps a regression inside the 20-minute `macos` job.

**D10 — Broken symlinks are links.** Linux `attributesOfItem` returned `NSFileTypeSymbolicLink` for a link to a missing path, while `fileExists` returned false. Cloning the link is the success path. The old `continue` is not kept.

**D11 — Hard links and directory modes stay out.** The loop clones each directory entry. Preserving inode identity or source directory modes is a different product change and is not required here.

## 8. Open questions

None.
