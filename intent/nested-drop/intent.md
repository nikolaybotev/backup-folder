# intent.md — Nested drop

| | |
|---|---|
| Author | Maintainer |
| Captured | 2026-11-02 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [Drop Box watcher](../drop-box-watcher/intent.md) |

## Problem

`drop-box-watcher` notifies for top-level files in the watch folder. A folder dropped into the watch folder (one subfolder holding three markdown files) produced FSEvents and file-presenter callbacks for the subfolder and every file in it, and never logged `webhook enqueue`, so no webhook fired. Top-level file drops enqueue normally.

## Proposed outcome

A file that lands anywhere under the watch folder, at any depth, is enqueued the same way a top-level file is. Ignore rules stay as they are. Readiness stays the iCloud and file-coordination signal, with no settle delay and no timer. A dropped folder that holds several files produces one nudge for the files that are ready together, not one webhook per filesystem event. Deleting an emptied subfolder after that dispatch does not send a webhook. Tests cover nested drops. Docs stay generic.

## Affected users and systems

- **Users:** the person who drops files or folders into the watch folder, and the routine that lists that folder and moves files.
- **Systems:** this repo. The watcher binary, its Darwin-free tests, the macOS watcher smoke, and the watcher paragraphs in the long-lived docs. Not a live backup, not an installed binary, and not a LaunchAgent load.

## Constraints and principles

- Readiness comes from the iCloud and file-coordination signal already shipped. There is no settle delay and no readiness timer. That settled choice stays closed.
- The same ignore list applies (`.DS_Store` and the other current patterns). Patterns stay file names, with no `/`.
- The watcher still does not move, rename, edit, or delete files.
- A directory is not a webhook file. Deleting an emptied subfolder after dispatch does not send a webhook.
- Tests cover nested drops. Docs stay generic. Prose about this repo says "this repo".
- This pull request is the design only. The build is one later phase that lands the behavior, the tests, and the docs together.

## Open questions (carried into spec.md)

1. What is one sensible nudge for a dropped folder, if a timer must not join separate events?

## Original prompt (verbatim)

```
Problem, stated generically: drop-box-watcher notifies for top-level files in the watch folder. A folder dropped into the watch folder (one subfolder holding three markdown files) produced FSEvents and file-presenter callbacks for the subfolder and every file in it, and never logged "webhook enqueue", so no webhook fired. Top-level file drops enqueue normally.

Wanted outcome:
- A file landing anywhere under the watch folder, at any depth, is enqueued just like a top-level file.
- Same ignore rules as today (.DS_Store and the like).
- Same readiness behavior. No settle delays or timers. Readiness comes from the iCloud/file-coordination signal, as today. The settled watcher design stays closed on that point.
- A dropped folder holding several files produces sensible webhook traffic, not one webhook per FSEvent.
- Deleting an emptied subfolder after dispatch does not trigger a webhook.
- Tests for nested drops.
- Docs updated, generic.

The plan's build is one phase that includes the behavior, the tests, and the docs together. This pull request is the design only.

Approved 2026-11-02. Do not implement the watcher in this pull request. Do not merge. Do not install anything. Do not touch live backups or an installed binary. Branch from current main. Conventional commit. Public text stays generic: no hostnames, no machine paths, no personal details. Prose about this repo says "this repo".
```
