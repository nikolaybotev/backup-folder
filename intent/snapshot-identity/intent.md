# intent.md — snapshot identity

| | |
|---|---|
| Author | Maintainer |
| Captured | 2026-10-29 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [honest-snapshot](../honest-snapshot/intent.md) |

## Problem

Two runs that share a minute share one snapshot path. The later run deletes the earlier run’s temp directory. A name that changes shape without a matching retention parser is kept forever.

## Proposed outcome

Each run has its own snapshot name. A second run for the same dest waits or skips instead of deleting the first run’s tree. Retention still applies the 48-hour and 60-day rules to names already on disk and to the new names.

## Affected users and systems

- **Users:** anyone who starts a backup while another is running, including an hourly LaunchAgent overlapping a manual run.
- **Systems:** `backup-folder` on macOS, the `macos` smoke check, a new Linux test job for the pure retention function, CodeQL, and the release build line. Not `~/Backups`, and not the binary installed on the deployment Mac.

## Constraints and principles

- Old `yyyy-MM-dd_HHmm` directories must remain eligible for pruning. A format change that the parser rejects would keep every new snapshot, and a parser that understands only the new form would keep every old one.
- The temp directory of a live run is not deleted by another run.
- Nothing in this change reads or writes `~/Backups` or `~/Backups/bin/backup-folder`.

## Open questions (carried into spec.md)

1. None. Uniqueness is a suffix on a second-resolution name, and the lock is non-blocking.

## Original prompt (verbatim)

> Then write the intent(s) from your findings and fix all the issues you identified, plus anything else you find. Split them into one or more intents as you judge best, following the ai-native-sdlc skill: spec and plan, then an independent review, then build, with one phase per PR, merged only when checks pass.
>
> The standing rule has not changed: nothing touches ~/Backups or the installed binary on the deployment Mac. When a release is ready, send PR links and a short status to the coordinator for rollout approval.

## Source

Findings that prompted this work are in `/cursor/stores/bc-c9ff0ffd-b9bd-509f-8397-dfe181f02de7/internal/orientation.md` (subagent `bc-12045930-2ffb-5845-b318-ca116bfe0f1d`). This section does not restate them.
