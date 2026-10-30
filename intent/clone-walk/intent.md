# intent.md — clone walk

| | |
|---|---|
| Author | the maintainer |
| Captured | 2026-10-29 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [path-containment](../path-containment/intent.md) |

## Problem

A symlink to a directory is walked as a directory, and a special file is handed to `copyItem`. The walk has no record of directories it has already entered, and a path that disappears between the listing and the copy is dropped without counting as a failure.

## Proposed outcome

A symlink is copied as a symlink. A fifo, socket, or device is not read. A directory cycle stops the walk. Any of those failures fails the snapshot instead of publishing a short tree.

## Affected users and systems

- **Users:** the person whose source contains a symlink or a special file.
- **Systems:** `backup-folder` on macOS, the Linux test of the cycle decision, and the `macos` smoke check. Not `~/Backups`, and not the binary installed on the deployment Mac.

## Constraints and principles

- Cloning stays file by file. A directory is never passed to `clonefile`.
- This phase ships after honest-snapshot, so a new item failure does not publish.
- Nothing in this change reads or writes `~/Backups` or `~/Backups/bin/backup-folder`.

## Open questions (carried into spec.md)

1. None. Symlinks are cloned with `CLONE_NOFOLLOW`. Special files are not copied.

## Original prompt (verbatim)

> Then write the intent(s) from your findings and fix all the issues you identified, plus anything else you find. Split them into one or more intents as you judge best, following the ai-native-sdlc skill: spec and plan, then an independent review, then build, with one phase per PR, merged only when checks pass.
>
> The standing rule hasn't changed: nothing touches ~/Backups or the installed binary on the deployment Mac. When a release is ready, report it to me and I'll arrange the rollout with the maintainer. Send me PR links and a short status as each phase lands.

## Source

Findings that prompted this work are in `/cursor/stores/bc-c9ff0ffd-b9bd-509f-8397-dfe181f02de7/internal/orientation.md` (subagent `bc-12045930-2ffb-5845-b318-ca116bfe0f1d`). This section does not restate them.
