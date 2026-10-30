# intent.md — clone fallback visibility

| | |
|---|---|
| Author | the maintainer |
| Captured | 2026-10-29 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |

## Problem

A snapshot can be stored as a full copy, and the log still says the run succeeded. A dest that cannot be created can fail with nothing on stderr.

## Proposed outcome

The log and stderr say when a file was stored with a full copy. Creating `dest` either works or the process exits non-zero and says why.

## Affected users and systems

- **Users:** the person who reads `dest/backup.log` and who runs the tool by hand.
- **Systems:** `backup-folder` on macOS, the `macos` smoke check, the CodeQL workflow. Not `~/Backups`, and not the binary installed on the deployment Mac.

## Constraints and principles

- A successful full copy is still a successful snapshot. The README already says a normal copy is used when cloning a file fails.
- Nothing in this change reads or writes `~/Backups` or `~/Backups/bin/backup-folder`.
- This change does not publish a release and does not install the tool.

## Open questions (carried into spec.md)

1. None. The README already chooses a full copy over a failed file.

## Original prompt (verbatim)

> Then write the intent(s) from your findings and fix all the issues you identified, plus anything else you find. Split them into one or more intents as you judge best, following the ai-native-sdlc skill: spec and plan, then an independent review, then build, with one phase per PR, merged only when checks pass.
>
> The standing rule hasn't changed: nothing touches ~/Backups or the installed binary on the deployment Mac. When a release is ready, report it to me and I'll arrange the rollout with the maintainer. Send me PR links and a short status as each phase lands.

## Source

Findings that prompted this work are in `/cursor/stores/bc-c9ff0ffd-b9bd-509f-8397-dfe181f02de7/internal/orientation.md` (subagent `bc-12045930-2ffb-5845-b318-ca116bfe0f1d`). This section does not restate them.
