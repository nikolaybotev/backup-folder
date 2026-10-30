# intent.md — honest snapshot

| | |
|---|---|
| Author | Nikolay |
| Captured | 2026-10-29 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [clone-fallback-visibility](../clone-fallback-visibility/intent.md) |

## Problem

A walk that loses files is still published under a snapshot name, logged as `OK`, and exited 0. Retention can later keep that directory and delete the complete copies from the same day.

## Proposed outcome

A snapshot name is created only when every item in the walk succeeded. A failed run leaves no directory that retention will consider, exits non-zero, and does not log `OK`. The 48-hour and 60-day rules stay as they are.

## Affected users and systems

- **Users:** the person whose hourly snapshot is the copy they would restore.
- **Systems:** `backup-folder` on macOS and the `macos` smoke check. Not `~/Backups`, and not the binary installed on Roger.

## Constraints and principles

- Retention’s ages and the “earliest that day” rule are the product. The defect is admitting an incomplete tree into that rule.
- Snapshots already stored under a snapshot name are left as they are. This change does not rewrite `~/Backups`.
- Nothing in this change reads or writes `~/Backups` or `~/Backups/bin/backup-folder`.

## Open questions (carried into spec.md)

1. None. An incomplete tree is not given a snapshot name.

## Original prompt (verbatim)

> Then write the intent(s) from your findings and fix all the issues you identified, plus anything else you find. Split them into one or more intents as you judge best, following the ai-native-sdlc skill: spec and plan, then an independent review, then build, with one phase per PR, merged only when checks pass.
>
> The standing rule hasn't changed: nothing touches ~/Backups or the installed binary on Roger. When a release is ready, report it to me and I'll arrange the rollout with Nikolay. Send me PR links and a short status as each phase lands.

## Source

Findings that prompted this work are in `/cursor/stores/bc-c9ff0ffd-b9bd-509f-8397-dfe181f02de7/internal/orientation.md` (subagent `bc-12045930-2ffb-5845-b318-ca116bfe0f1d`). This section does not restate them.
