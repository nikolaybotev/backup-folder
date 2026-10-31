# intent.md — Tiered snapshot retention

| | |
|---|---|
| Author | Maintainer |
| Captured | 2026-10-31 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [one backup job](../one-backup-job/intent.md) |

## Problem

Every folder keeps every snapshot for 48 hours, then the earliest snapshot of each calendar day for 60 days. That thinning schedule is fixed. A folder that should keep a finer history for a short while, and then less of it, cannot say so.

## Proposed outcome

Retention is an ordered list of tiers on a folder, with an optional default for the whole file. A tier keeps one snapshot per interval until snapshots are that age old. A file that does not set retention behaves as it does today. A finer schedule is a documented example, not the built-in rule.

## Affected users and systems

- **Users:** the person who edits the backup config and decides how much history a folder keeps.
- **Systems:** this repo. The backup config schema, the retention decision, the README, and the example config. Not the watcher config. Not a live machine.

## Constraints and principles

- An existing config that does not mention retention keeps today's rule, including which snapshot represents a day and when pruning runs.
- The earliest snapshot in a bucket is the one that stays.
- Pruning runs only after a successful snapshot, and only for that folder.
- A bad tier list is rejected with a clear error. It does not start a backup.
- The schedule stays outside the tool. The LaunchAgent template keeps its current schedule.
- The worked example is not the code default. There is no weekly tier. Snapshots older than the last tier are not a long-term archive.
- Docs stay generic. Prose about the repo says "this repo". Placeholders stand in for paths.

## Open questions (carried into spec.md)

None. The design was approved on 2026-10-31. [spec.md](spec.md) records it as decisions after checking the tree.

## Original prompt (verbatim)

```
This design was approved on 2026-10-31. Record it as decisions, not open questions, once you have checked the code. Verify these facts in the current tree before they harden, and name the file you checked: today's retention (what is kept, for how long, which snapshot in a day, when pruning runs); how a day bucket is aligned; the TOML subset in Sources/ToolConfig and what BackupConfig and the watcher accept (tables, arrays, integers, durations); which config file hot-reload watches and how an invalid edit keeps the last good config; the LaunchAgent template's current schedule.

Product requirements:

1. Retention is configurable per [[folder]] entry, with an optional top-level default, as an ordered list of tiers. Each tier means: keep one snapshot per interval until snapshots are that age old. A tier with no interval, or interval 0, keeps every snapshot. Anything older than the last tier's age is deleted.
2. Example deployment, not the built-in default: keep everything for 4h; one per 15 min until 8h; one per 30 min until 16h; one per hour until 24h; one per day until 30 days. On a 5-minute schedule that is 117 snapshots per folder. Check that arithmetic and record it. There is no weekly tier. Long-term history is out of scope.
3. With no retention configured, behavior is exactly today's: everything for 48h, then one per day (the earliest of each day) for 60 days. Existing configs keep working unchanged. Do not copy a machine's live config into the repo. The 48h/60-day behavior is the tool default; the 4h-through-30-day list is a worked example.
4. Within each tier, keep the earliest snapshot in each interval bucket, consistent with today's earliest-of-the-day rule. Pruning still runs only after a successful snapshot, per folder.
5. Validation: tiers must have strictly increasing ages; each interval no larger than the next tier's interval; sensible units. A bad config is rejected with a clear error. Hot reload rejects it and keeps the last good config, the same way other invalid edits work. If retention cannot live in the file the watcher reloads, say where validation runs and how the hot-reload test still drives that reject path. Do not leave this as an open question.
6. Schedule stays outside the tool. Document running every 5 minutes (StartInterval 300 or StartCalendarInterval). Keep the template's default schedule as it is.
7. Docs to plan, not necessarily to edit in this PR unless the plan puts them in a later phase: README and the config reference get the tier syntax, the default, and the worked example. Fully generic. No hostnames, machine names, personal names, or setup details.
8. Tests to plan: unit tests for bucket selection at tier boundaries and for default-equivalence with today's rule; an end-to-end test that runs the real binary against a temp folder with faked snapshot timestamps and checks what survives; a hot-reload test for a bad tier config.
```
