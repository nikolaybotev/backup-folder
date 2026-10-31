# intent.md — One backup job

| | |
|---|---|
| Author | Maintainer |
| Captured | 2026-10-31 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [snapshot identity](../snapshot-identity/intent.md), [Drop Box watcher](../drop-box-watcher/intent.md) |

## Problem

Adding a folder means adding another LaunchAgent. Each agent is its own process, started hourly at minute 0, with that folder's source and destination on the command line. The destination layout, log, and retention already work. The watcher has its own config file and reads it once at start.

## Proposed outcome

One LaunchAgent backs up every configured folder. Adding a folder is a config entry. Each folder still gets its own log, its own snapshot history, and its own failure. The watcher and the backup job share one config library. The watcher picks up a valid edit and keeps running through an invalid one.

## Affected users and systems

- **Users:** the person who adds a folder and who migrates from one agent per folder to one agent.
- **Systems:** this repo. The backup command, the watcher, the LaunchAgent template, and the example config. Not a live machine.

## Constraints and principles

- The single-folder command stays.
- Snapshot names, retention, and each destination's `backup.log` stay, so history already on disk still applies.
- One folder's failure does not cancel the others. The process exit reflects any failure.
- Folders run at the same time, one task per folder, unless a config cap says otherwise. The default is all of them at once.
- The cutover on a machine is out of scope. Nothing in this change installs, loads, or reloads an agent.
- Docs stay generic. Prose about the repo says "this repo". Placeholders stand in for paths.

## Open questions (carried into spec.md)

1. One shared config file, or one library and two files?
2. What is the backup config schema, including an optional concurrency cap?
3. Which process exit code represents a mix of folder results, including a destination that is already locked?
4. How does a long-running watcher see a replaced config file without exiting when the new text is bad?

## Original prompt (verbatim)

```
Write the design for nikolaybotev/backup-folder and open one pull request. Do not implement the code. Do not merge. Do not install anything or touch a machine. Do not add a Co-authored-by trailer.

Follow this repo's intent/spec/plan layout (a new intent folder). This pull request is the design only. Docs stay generic and author-agnostic, the way PR #30 did: no hostnames, no machine names, no personal paths. Prose about the repo says "this repo". Do not copy current setting values into the docs. Human-facing docs do not state the obvious. Agent-facing files may keep explicit expectations such as "(healthy: exit 0)".

Design:

1. backup-folder becomes one LaunchAgent, label prefix com.nikolaybotev (for example com.nikolaybotev.backup), hourly at :00. It reads a config file (for example ~/.config/backup-folder/config.toml) listing source/dest pairs and backs up each. Adding a folder is one config entry, not a new LaunchAgent. Each folder runs isolated: one failure does not stop the rest, and the overall exit reflects any failure. Each destination keeps its own backup.log and the same snapshot layout, naming, and retention, so existing backup history carries over unchanged. Keep the single-folder CLI (`backup-folder <src> <dest>`) working.

2. Parallelism stays as it is today. The single job backs up all configured folders concurrently, one actor/task per folder, as if separate processes were still running side by side. Each task is fully isolated, with its own log, errors, and exit status. The job waits for all of them and reports any failure. Consider an optional concurrency cap in the config. Default: all folders at once.

3. A small shared config library: one format, one validator, clear errors, used by both backup-folder and drop-box-watcher. The watcher hot-reloads its config when the file changes. An invalid edit keeps the last good config and logs why. It never crashes. The backup job just reads the config each run.

4. Generic template LaunchAgent, example config, and migration notes for going from N per-folder jobs to one. The cutover on a live machine is out of scope. Do not plan to install or reload anything.

Personal data stays out of the repo, including intents, specs, plans, docs, commits, and pull request text. No street names, addresses, parcel numbers, account or loan figures, employer details, family or contact details, or private-network IPs, keys, or hostnames. No notes about what was scrubbed or for whom. The owner's name may remain only in LICENSE. Public text stays generic.

Report the pull request URL.
```
