# intent.md — path containment

| | |
|---|---|
| Author | Nikolay |
| Captured | 2026-10-29 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [snapshot-identity](../snapshot-identity/intent.md) |

## Problem

The tool decides that the backup directory is outside the source by comparing strings after stripping one trailing slash. An extra slash or a `..` component can put the backup inside the source, and the walk will copy the backup into itself.

## Proposed outcome

The run refuses when the normalized backup path is the source or is inside the source, including through extra slashes, `..`, and a symlink. A sibling directory whose name only starts with the source name is still allowed.

## Affected users and systems

- **Users:** the person who passes the two paths, including a path copied with an extra slash.
- **Systems:** `backup-folder` on macOS, the Linux test job, and the `macos` smoke check. Not `~/Backups`, and not the binary installed on Roger.

## Constraints and principles

- The refusal message stays `backup dir must not be inside source`, and the exit stays 2.
- A destination that lines 14–15 of `backup-folder.swift` refuse today stays refused, including when a symlink would resolve it outside the source. [clone-walk](../clone-walk/intent.md) is the following phase and does not replace this check.
- `/tmp/foo` as source and `/tmp/foobar` as dest stay allowed.
- Nothing in this change reads or writes `~/Backups` or `~/Backups/bin/backup-folder`.

## Open questions (carried into spec.md)

1. None. Normalization happens before the walk, and source `/` stays refused.

## Original prompt (verbatim)

> Then write the intent(s) from your findings and fix all the issues you identified, plus anything else you find. Split them into one or more intents as you judge best, following the ai-native-sdlc skill: spec and plan, then an independent review, then build, with one phase per PR, merged only when checks pass.
>
> The standing rule hasn't changed: nothing touches ~/Backups or the installed binary on Roger. When a release is ready, report it to me and I'll arrange the rollout with Nikolay. Send me PR links and a short status as each phase lands.

## Source

Findings that prompted this work are in `/cursor/stores/bc-c9ff0ffd-b9bd-509f-8397-dfe181f02de7/internal/orientation.md` (subagent `bc-12045930-2ffb-5845-b318-ca116bfe0f1d`). This section does not restate them.
