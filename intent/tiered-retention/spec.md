# spec.md — Tiered snapshot retention

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-31) |
| Status | Draft 1 |
| Stage | 2 · Design |

## 1. Summary

A backup config may set `retention` as an ordered list of tiers. Each tier keeps one snapshot per interval until snapshots are that age old. A tier with no interval, or interval 0, keeps every snapshot in its age window. Anything older than the last tier is deleted. The list may sit once at the top of the file and may be overridden on a `[[folder]]` entry. When the key is absent, the tool keeps every snapshot for 48 hours, then the earliest snapshot of each calendar day for 60 days.

The worked example, which is not the default, keeps everything for 4 hours, one snapshot per 15 minutes until 8 hours, one per 30 minutes until 16 hours, one per hour until 24 hours, and one per day until 30 days. On a snapshot every 5 minutes that policy holds 117 snapshots per folder.

Tiers are an array of basic strings. The shared TOML subset does not grow a duration type, a nested table, or a dotted key. Validation runs in the backup schema. The watcher does not read this file. A bad tier list fails `parseBackupConfig`, and the reload decision keeps the last good backup config. The LaunchAgent template keeps its hourly schedule. A 5-minute cadence is documented as a launchd setting.

This change does not install or reload anything.

## 2. Goals and non-goals

**Goals**

- G1. Each folder has an ordered tier list, falling back to an optional file-level list, then to the built-in 48-hour and 60-day rule.
- G2. A tier keeps the earliest snapshot in each interval bucket. Interval 0 keeps every snapshot in that tier. Snapshots older than the last age are deleted.
- G3. Absent `retention` matches today's prune results, including the 48-hour boundary, the 60-day boundary, and the rule that a fresh snapshot does not occupy the day's keeper slot.
- G4. A bad tier list is a config error with a clear message. The file starts no folder.
- G5. The README and the example config document the syntax, the default, and the worked example.
- G6. The schedule stays in launchd. The template's hourly start stays.

**Non-goals**

- Do not change snapshot names, the per-destination lock, or the rule that a failed walk or a failed rename does not prune.
- Do not add a weekly, monthly, or yearly tier. Do not keep snapshots older than the last tier as a long-term archive.
- Do not make the 4-hour-through-30-day list the code default.
- Do not copy a live config into this repo.
- Do not extend `parseTomlSubset` with durations, floats, booleans, inline tables, nested tables, or dotted keys.
- Do not put retention in the watcher config, and do not point the watcher at the backup file.
- Do not add a resident backup process, a watch loop, or `KeepAlive` on the backup agent.
- Do not change `launchd/backup-folder.plist.template`.
- Do not type-check or link `Sources/backup-folder/main.swift` on the Linux job.
- Do not install, load, unload, or reload a LaunchAgent. Do not run `launchctl`. Do not write a live config, a live pin file, or anything under a home `Backups` directory.

**Release phasing.** Configurable tiers, the default, validation, and the docs are this intent. Nothing is tagged for a later release. They land as the phases in [plan.md](plan.md). Untagged requirements belong to those phases. Long-term history stays out of scope.

## 3. Principles

- P1. One prune engine. The built-in rule is the default tier list passed through that engine, not a second loop that can drift.
- P2. The calendar day is the `yyyy-MM-dd` prefix already written in the snapshot name. Sub-day buckets use that same civil clock.
- P3. A backup file that does not validate starts no folder.
- P4. After a good backup config is in hand, a bad re-read does not replace it.
- P5. Operator docs use placeholders. Prose about the repo says "this repo". Human-facing docs do not spell out what a competent reader already knows. Agent-facing files keep explicit expectations such as "(healthy: exit 0)".
- P6. The tool does not choose the launchd schedule.

## 4. Users and scenarios

- A config with no `retention` key prunes as it does today. Directories already on disk stay candidates under the same names.
- A folder sets a short list. A sibling folder omits the key and inherits the file-level list, or the built-in rule when the file-level list is also absent.
- Two snapshots fall in one 15-minute bucket of a tier. The earlier one stays. The later one is deleted after the next successful snapshot of that folder.
- A snapshot older than the last tier is deleted after the next successful snapshot. A snapshot inside a keep-all tier does not occupy a later tier's bucket.
- The tier text is invalid. `backup-folder --config` prints a line-numbered error and exits 2. No folder starts, and nothing is pruned.
- A re-read of a bad tier list, given a last good config, keeps that config and records `config reload rejected:`.
- The operator wants a snapshot every 5 minutes. They change the launchd schedule. The template in this repo still starts hourly at minute 0.

## 5. Functional requirements

1. A tier is an age and an interval, both in integer seconds. Age is how old a snapshot may be and still belong to the tier. Interval 0 means keep every snapshot that belongs to the tier. A positive interval means keep the earliest snapshot in each bucket of that length. The built-in list is `SnapshotRetention.defaultTiers`: interval 0 and age `keepFreshSeconds` (`48 * 3600`), then interval `86400` and age `maxAgeBeforeDayRuleSeconds` (`60 * 86400`). Those two constants in `Sources/backup-folder/Retention.swift` stay the source of the numbers. Checked 2026-10-31.
2. The engine replaces the loop in `SnapshotRetention.namesToPrune`. Callers pass the tier list and a `TimeZone`. The existing defaulted call keeps today's results: default tiers, and the zone only matters for intervals other than 0 and `86400`. Candidates, sort order, and unparsable names stay as they are. `sortedCandidateNames` still orders by parsed instant, then full name. A name that does not parse is left in place. A future snapshot (negative age) belongs to the first tier whose age it does not exceed.
3. Walk candidates oldest instant first. A snapshot belongs to the first tier whose age is greater than or equal to the snapshot's age. The younger tier owns the shared boundary: age equal to 48 hours stays in the keep-all tier, and age equal to 60 days stays in the daily tier. Age one second past the last tier is deleted. Interval 0 keeps the snapshot and does not mark a bucket. A positive interval keeps the snapshot when its bucket is unmarked, then marks that bucket, and deletes a later snapshot in the same bucket of the same tier. A snapshot kept in an earlier tier does not mark a later tier. Checked 2026-10-31: `namesToPrune` uses `continue` inside `keepFreshSeconds` and only then records `String(n.prefix(10))`, which is why a fresh sibling does not drop the day's keeper (`tests/retention-tests.swift`).
4. Bucket keys use the civil clock of the `TimeZone` argument, the same clock the name formatter uses in `runOneFolder` (`TimeZone.current`, locale `en_US_POSIX`, Gregorian). Checked 2026-10-31 in `Sources/backup-folder/main.swift`.
   - Interval `86400`: the key is the ten-character `yyyy-MM-dd` prefix of the name. Do not divide the Unix timestamp by 86400.
   - Interval `N * 86400` for `N > 1`: the key is the civil day count in that time zone divided by `N`. The count is the number of midnights from 1970-01-01 to that civil date, so 1970-01-01 is 0. It is not a 1-based era ordinal. Checked 2026-10-31: in UTC, 2026-10-30 is 20756 and 2026-10-31 is 20757, and those share `// 2`. 2026-10-29 is 20755 and does not. A 1-based count would split 2026-10-30 from 2026-10-31.
   - Any other positive interval: the key is the date prefix plus the index `secondOfDay / interval`, where `secondOfDay` is `hour * 3600 + minute * 60 + second` from the civil components in that time zone. Different dates do not share a bucket. A 15-minute interval aligns to minute 0, 15, 30, and 45 of the local hour. A 30-minute interval aligns to minute 0 and 30. An hour aligns to the local hour.
   - Civil components, not elapsed SI seconds, so a DST fold shares a clock bucket and the earlier absolute instant is the one kept. The product passes `TimeZone.current` at the prune call.
5. The backup schema gains one optional key, `retention`, at the root and inside each `[[folder]]`. The root key is the default. A folder key replaces it for that folder only. Absent on both is `defaultTiers`. The resolved list is stored on the folder pair the job runs. Root and folder are both validated when present. An invalid root fails the file even if every folder overrides it. An invalid folder fails the file. No folder starts. Other root keys stay `concurrency` and `folder` only. Other folder keys stay `source` and `dest` only. Checked 2026-10-31: `parseBackupConfig` in `Sources/backup-folder/BackupConfig.swift` rejects any other key.
6. `retention` is an array of basic strings on one line. Each element matches `keepAll` or `interval "/" age`. `keepAll` and `age` and `interval` are a number and a unit. The number is `0` or a non-zero digit string with no leading zero, no `+`, and no `_`. The unit is `s`, `m`, `h`, or `d`: 1, 60, 3600, and 86400 seconds. No other unit. `4h` and `0/4h` and `0s/4h` are interval 0 and age 4 hours. The worked example is the array `4h`, `15m/8h`, `30m/16h`, `1h/24h`, `1d/30d`. The strings `48h` and `1d/60d` resolve to `defaultTiers`. Checked 2026-10-31 against `Sources/ToolConfig/TomlSubset.swift`: values are strings, integers, arrays of basic strings, root tables, and root arrays of tables. `defineTable` writes `root.entries` only. Dotted keys, inline tables, and bare tokens such as `4h` (`unsupported value`) are parse errors. An array element that is not a basic string is `array elements must be basic strings`. Durations are not a subset type. Nested `[[folder.retention]]` tables are not expressible. The array-of-strings form needs no subset change. `drop-box-watcher/Config.swift` `disallowedWatcherValue` rejects every integer and every array of tables, so a duration token or a tier table added to the subset would still be refused by the watcher schema.
7. Validation, first failure only, after the subset parse. Messages include the line number of the `retention` value and do not include the value text or any path.
   - Not an array of strings: `line N: expected an array of strings for retention`.
   - Empty array: `line N: empty retention`.
   - Element does not match the grammar, the unit is unknown, or the seconds do not fit in `Int`: `line N: bad retention tier`.
   - A parsed age of 0 seconds: `line N: retention age must be greater than 0`.
   - An age less than or equal to the previous age: `line N: retention ages must increase`. Compare seconds, so `48h` then `2d` fails (both are 172800).
   - An interval greater than the next tier's interval: `line N: retention interval larger than the next tier`. Compare seconds, so `60s` then `1m` is equal and allowed. Interval 0 is the number 0, so a keep-all tier may lead and may repeat, and a positive interval followed by interval 0 fails.
   - The worked example passes. The engine does not re-validate. An empty list cannot be loaded. If it were passed in, every candidate would be deleted.
8. `decideBackupConfigReload(current:read:)` lives next to `parseBackupConfig`. It is the backup analogue of `decideConfigReload` in `drop-box-watcher/ConfigReload.swift`. On a failed read it returns keep-and-log with log line `config reload rejected: config parse error: ` plus the parse message, and it does not return a replacement config. On a success equal to a non-nil current it returns unchanged and a nil log line. Otherwise it returns apply with the new config. `runConfigJob` calls it with `current: nil` after the permission check and the read. Apply runs the job. Keep-and-log prints `config parse error: ` plus the message and returns 2, which is today's stderr line, without the reload prefix. Unchanged at startup returns 2. Checked 2026-10-31: `runConfigJob` in `Sources/backup-folder/main.swift` already exits 2 on `parseBackupConfig` failure and starts no folder.
9. Retention cannot live in the file the watcher reloads. Checked 2026-10-31: `drop-box-watcher/main.swift` takes one config path, and `ConfigWatch` re-reads that path from an FSEvents stream on its parent directory. A failed `decideConfigReload` logs `config reload rejected:` and does not call `apply`. That schema has no `retention` key. An unknown key, any integer, and any `[[table]]` fail `parseConfigTOML`. Writing tiers into the watcher file would keep the last good watcher config for an unknown-key error and would never check ages or intervals. Do not use that as the tier test. The hot-reload test calls `decideBackupConfigReload` with a non-nil last good `ParsedBackupConfig` and a failed `parseBackupConfig` of a bad tier list, and asserts keep-and-log plus the unchanged current value. That is the reject path. This intent does not add FSEvents to `backup-folder` and does not edit `ConfigWatch`.
10. Pruning stays where it is. Checked 2026-10-31 in `runOneFolder`: a walk that does not publish returns 1 before prune, a failed `moveItem` returns 1 before prune, and prune runs only after the `OK snapshot` line. A prune I/O error is logged and the folder still returns 0. The two-argument command does not open a config file and passes `defaultTiers`. `--config` passes that folder's resolved list. Each destination is pruned on its own. The instant comes from the snapshot name, not from the directory modification time.
11. The schedule stays outside the tool. Checked 2026-10-31: `launchd/backup-folder.plist.template` has `StartCalendarInterval` with `Minute` 0 and no `Hour`, no `StartInterval`, `RunAtLoad` false, and no `KeepAlive`. No phase edits that file. Docs tell the operator that a 5-minute cadence is `StartInterval` 300 or a `StartCalendarInterval` they write. The template's hourly start stays.
12. Human-facing docs, in the docs phase only. `README.md` keeps the current default bullets (everything for 48 hours, then the earliest of each day for 60 days, then delete). It adds the string-array syntax, the root and per-folder rule, and the worked example labeled as an example. It states the 117 count with the breakdown in requirement 13. It states the 5-minute launchd settings and that the template stays hourly at minute 0. It leaves the in-place-swap `launchctl kickstart` paragraph in "How it runs" as it landed on `main`. `backup-folder.example.toml` shows the worked array only in a comment, so a copied file that still has no `retention` key uses the tool default. `docs/backup-job.md` keeps the point that existing destination directories remain valid, and says an absent `retention` key uses the default policy. Placeholders only. No host, machine, or personal name. No statement that success is exit 0. Do not add or remove Manual/Script bullets in `docs/setup.md` or `docs/restore.md`.
13. Checked 2026-10-31. The worked example's steady count is `4*60/5 + 4*60/15 + 8*60/30 + 8/1 + (30-1) = 48 + 16 + 16 + 8 + 29 = 117`. Each term is that tier's age span divided by its keep interval. The keep-all span is divided by the 5-minute schedule. The daily span is 30 days minus the 24 hours already covered. The snapshot on a shared boundary belongs to the younger tier and is not counted twice. Five minutes divides 15 minutes, 30 minutes, 60 minutes, and one day, so a run every 300 seconds fills every bucket. The tool does not assert that a directory count equals 117. There is no weekly term.

## 6. Acceptance criteria

- AC1. Phase 0: `swiftc -O -o retention-tests Sources/backup-folder/Retention.swift tests/retention-tests.swift && ./retention-tests` exits 0 (healthy: `retention-tests: OK`). The current boundary cases still pass, including age `48 * 3600`, `48 * 3600 + 1`, `60 * 86400`, `60 * 86400 + 1`, the fresh sibling that must not drop the day keeper, and the earliest of a day. New cases cover a 15-minute tier with `TimeZone(secondsFromGMT: 7 * 60)` where local 00:10 and 00:20 are both kept (they share one Unix 15-minute bucket and do not share a civil one), a daily tier with `TimeZone(secondsFromGMT: -7 * 3600)` where `2026-10-29_2350` and `2026-10-30_0010` are both kept, and a 2-day interval in UTC where `2026-10-30` and `2026-10-31` share a bucket and `2026-10-29` does not. `Sources/backup-folder/main.swift` is unchanged in that phase.
- AC2. Phase 1: the Linux folder-job compile includes `Sources/backup-folder/Retention.swift` and still does not include `Sources/backup-folder/main.swift`. `./folder-job-tests` exits 0. It accepts the worked example and `48h` plus `1d/60d`. It rejects an empty array, `1w`, `48h` then `2d`, a larger interval before a smaller one, and `60s` then `1m` as allowed. Error text includes the line number and `retention` and excludes the path and the bad token. Root retention applies to a folder that omits the key. A folder key overrides the root. `decideBackupConfigReload` with a good current config and a bad tier re-read returns keep-and-log (`config reload rejected: config parse error:`), not a replacement config. An equal re-read returns unchanged.
- AC3. Phase 1: `bash tests/macos-smoke.sh` still prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. New cases under `mktemp` run the built `backup-folder` binary. Seeded directories use snapshot names, not modification times. With no `retention` key, a snapshot well inside 48 hours remains and a snapshot older than 60 days is deleted. A 15-minute tier keeps the earlier of two names in one local bucket and deletes the later. One config with two folders applies a short root list to the folder that omits the key and the other folder's own list to its destination. Do not claim this smoke passed unless the `macos` job did.
- AC4. Phase 2: `README.md`, `backup-folder.example.toml`, and `docs/backup-job.md` match requirement 12. `bash tests/no-secrets.sh` and `bash tests/setup-docs.sh` exit 0. Setup still has 33 Manual/Script bullets. Restore still has 7. The launchd template is not in the diff.
- AC5. No phase edits `.github/workflows/release.yml`, `.github/workflows/codeql.yml`, or `.github/scripts/protect-main-branch.sh`. No phase raises `timeout-minutes`. No phase runs `launchctl`, `scripts/install-tools.sh` against a home directory, or `scripts/ensure-backup-dirs.sh` against a live home. No phase pushes a tag. No phase edits `drop-box-watcher/` or `tests/macos-watcher.sh`.
- AC6. This design pull request does not start Phase 0. Its files are this folder. `bash tests/no-secrets.sh` exits 0 (healthy: `no-secrets: all checks passed`).

## 7. Design decisions

**D1 — Array of strings, subset unchanged.** Checked 2026-10-31 in `Sources/ToolConfig/TomlSubset.swift` and `Sources/backup-folder/BackupConfig.swift`. The subset cannot represent nested tier tables under `[[folder]]`, and it has no duration token. An array of basic strings already parses. The backup schema interprets each string. Extending the subset was rejected: the watcher would have to keep refusing the new shapes, and one-backup-job already fixed the subset's limits.

**D2 — Age windows, younger tier owns the boundary.** "Until that age" matches today's `<=` tests. The next tier starts at the next second. Interval 0 keeps every snapshot in the window and does not mark later buckets, which is today's fresh-window `continue`. Deleting anything past the last age is the whole policy. There is no implicit forever tier after it.

**D3 — Civil buckets, prefix for a day.** Checked 2026-10-31: the day key in `Retention.swift` is the name prefix, and the name is formatted in `TimeZone.current`. Dividing the Unix timestamp by the interval was rejected. A whole-hour offset preserves 15-minute boundaries, so the distinguishing 15-minute fixture uses a 7-minute offset. A 7-hour-west offset puts `2026-10-29_2350` and `2026-10-30_0010` on one UTC day and on two prefixes. Multi-day groups use the civil day count from 1970-01-01, and that date is 0. Weekday alignment was rejected with the weekly tier.

**D4 — Default stays in code. The example stays an example.** Absent keys resolve to `defaultTiers`. Writing `48h` and `1d/60d` is the same list. The 4-hour-through-30-day array is valid input and is not `defaultTiers`. The example file shows it in a comment so copying the file does not switch policy. No live config is committed.

**D5 — 117 is the span sum.** Checked 2026-10-31: 48 + 16 + 16 + 8 + 29 = 117, as in requirement 13. A count that adds an extra endpoint in the first 4 hours is a different model. The figure is documentation of a full 5-minute cadence. Tests lock bucket membership, not a directory total of 117.

**D6 — Closed validation.** Strictly increasing ages, each interval no larger than the next, and the unit set `s`, `m`, `h`, `d`. Equal intervals are allowed. `w` is not a unit. Seven days is the string `7d` if someone writes it. The worked example does not. Messages name the line and the failure class and do not echo the value, matching the backup schema's existing rule that a webhook-bearing file must not copy values into errors.

**D7 — Tier reject path is the backup reload decision.** Checked 2026-10-31 in `drop-box-watcher/main.swift`, `drop-box-watcher/ConfigWatch.swift`, `drop-box-watcher/ConfigReload.swift`, and `drop-box-watcher/Config.swift`. The watcher reloads its own file and keeps the last good watcher config on any schema error. Retention is not in that schema, so that reload cannot validate tiers. `decideBackupConfigReload` is the reject path the hot-reload test drives. Startup with no current config still exits 2 on a bad file, which is the first-load rule. A test that passes a current config locks the keep rule. A resident backup process is out of scope because the schedule stays in launchd and the template is not `KeepAlive`.

**D8 — Prune call site stays.** Checked 2026-10-31 in `Sources/backup-folder/main.swift`. Success publishes, then prunes that destination. The new arguments are the resolved tiers and `TimeZone.current`. Names carry the timestamps. Modification times are not read.

**D9 — Template schedule stays.** Checked 2026-10-31 in `launchd/backup-folder.plist.template`. Hourly at minute 0 stays. `StartInterval` 300 and a minute list are operator launchd settings, documented, not shipped in the template.

**D10 — This pull request is the design.** Phase 0 starts when someone says to build. Each later phase is one pull request. A phase does not merge itself. The coordinator squash-merges only when the required checks `macos` and `linux` are green. The build does not push a tag and does not add a release label.

## 8. Open questions

None.
