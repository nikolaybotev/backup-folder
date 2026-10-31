# plan.md — Tiered snapshot retention

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

The pull request that adds this folder does not start Phase 0. Phase 0 starts only when someone says to build. Each phase is one branch and one pull request, opened ready for review, with a conventional commit. A phase does not merge itself. The coordinator squash-merges only when the required checks `macos` and `linux` are both green. A cancelled check is not green. Do not push a `v*` tag. Do not add a release label. Do not install, load, or reload anything. Do not run `launchctl`. Do not write a live config or a live pin. Do not write under a home `Backups` directory.

Merging a phase to `main` runs job `publish`, which may push the next patch tag. That is the existing release workflow. It is not a stop.

## Stops

None.

## This pull request

Files: `intent/tiered-retention/`.

DoD: `bash tests/no-secrets.sh` exits 0 (healthy: `no-secrets: all checks passed`). `git diff --name-only origin/main` lists only this folder.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `swiftc -O -o retention-tests Sources/backup-folder/Retention.swift tests/retention-tests.swift && ./retention-tests` | 0 |
| AC2 | folder-job `swiftc` including `Retention.swift`; `./folder-job-tests` | 1 |
| AC3 | `bash tests/macos-smoke.sh` on the `macos` job | 1 |
| AC4 | `bash tests/no-secrets.sh`, `bash tests/setup-docs.sh` | 2 |
| AC5 | diff excludes release, CodeQL, protect-main, watcher, launchd template; timeouts unchanged | 0, 1, 2 |
| AC6 | this pull request | this pull request |

## Phase 0 — Tier engine

Files: `Sources/backup-folder/Retention.swift`, `tests/retention-tests.swift`.

Do not edit: `Sources/backup-folder/main.swift`, `BackupConfig.swift`, `FolderJob.swift`, `drop-box-watcher/`, `launchd/`, `docs/`, `README.md`, `AGENTS.md`, `REVIEW.md`, `.github/workflows/test.yml`, release, CodeQL, protect-main, or any other `intent/` folder.

1. Add `RetentionTier` with `intervalSeconds` and `ageSeconds`. `defaultTiers` is interval 0 with `Int(keepFreshSeconds)`, then interval 86400 with `Int(maxAgeBeforeDayRuleSeconds)`.
2. Replace the body of `namesToPrune` with spec requirements 2 through 4. Default the new arguments so the current call in `main.swift` still compiles and still uses `defaultTiers`. The 86400 key is `String(name.prefix(10))`. The `N * 86400` key uses the civil day ordinal from 1970-01-01 in the given time zone, integer-divided by `N`. Any other positive interval uses the date prefix and `secondOfDay / interval` from Gregorian components in that zone (`en_US_POSIX`).
3. Extend `tests/retention-tests.swift` with the AC1 fixtures. Keep the existing expects. The 7-minute-east zone is `TimeZone(secondsFromGMT: 7 * 60)`. Local `00:10` and `00:20` on one civil day, with `now` about five hours later so both ages sit in a 15-minute tier after a 4-hour keep-all, must both be kept. A same-bucket pair in that tier still deletes the later name. The 7-hour-west zone is `TimeZone(secondsFromGMT: -7 * 3600)`. Names `2026-10-29_2350` and `2026-10-30_0010`, both older than 48 hours and younger than 60 days, must both be kept under the default tiers. The parser that produces those instants uses the same zone as the bucket argument. For interval `2 * 86400` in UTC, the day count is midnights since 1970-01-01 (that date is 0). `2026-10-30` is 20756 and `2026-10-31` is 20757, one bucket, and `2026-10-29` is 20755, the previous bucket. Do not use a 1-based era ordinal.
4. Leave the Linux retention `swiftc` line in `.github/workflows/test.yml` as it is. Do not add `-parse-as-library`. Do not add `main.swift`.

DoD:

```
swiftc -O -o retention-tests Sources/backup-folder/Retention.swift tests/retention-tests.swift
./retention-tests
test -z "$(git diff --name-only -- Sources/backup-folder/main.swift)"
```

Healthy line: `retention-tests: OK`.

### Build notes (Phase 0)

- Added `RetentionTier`, `defaultTiers`, and tier-aware `namesToPrune` with default `tiers` and `timeZone` so `main.swift` is unchanged.
- Bucket keys: `yyyy-MM-dd` prefix for 86400; civil day ordinal from 1970-01-01 divided by `N` for `N * 86400`; date prefix plus `secondOfDay / interval` otherwise (`en_US_POSIX` Gregorian).
- Extended `tests/retention-tests.swift` for 15-minute (+7 min GMT), default daily (−7 h GMT cross-prefix), and 2-day UTC bucket fixtures; existing boundary expects unchanged.

## Phase 1 — Config, wiring, and the real binary

Files: `Sources/backup-folder/BackupConfig.swift`, `Sources/backup-folder/FolderJob.swift`, `Sources/backup-folder/main.swift`, `tests/folder-job-tests.swift`, `tests/macos-smoke.sh`, `.github/workflows/test.yml` (the folder-job `swiftc` file list only).

Do not edit: `Sources/ToolConfig/TomlSubset.swift`, `drop-box-watcher/`, `tests/macos-watcher.sh`, `tests/linux-unit.sh`, `launchd/`, `docs/`, `README.md`, `backup-folder.example.toml`, release, CodeQL, protect-main, timeouts, or any other `intent/` folder. Do not add `Sources/backup-folder/main.swift` to a Linux `swiftc` line.

1. Parse `retention` per spec requirements 5 through 7. Resolve root, then folder override, then `defaultTiers`, onto the folder pair. `FolderJob` carries the resolved list on that pair. Unknown keys stay errors. Duplicate keys stay subset errors.
2. Add `decideBackupConfigReload` per spec requirements 8 and 9. `runConfigJob` calls it with `current: nil`. Apply runs `FolderJob`. Keep-and-log writes `config parse error: ` and the message to stderr and returns 2. Do not write the `config reload rejected:` prefix at startup. Permission and I/O failures stay where they are and stay outside this function.
3. `runOneFolder` takes the tier list and passes it with `TimeZone.current` into `namesToPrune` after the successful publish, at the existing call site. The two-argument command passes `defaultTiers` and does not read a config file. Update the retention comment at the top of `main.swift` so it names the default and a configured list.
4. Add `Sources/backup-folder/Retention.swift` to the folder-job compile in `.github/workflows/test.yml`. Do not change `timeout-minutes` or job names. The command stays:

```
swiftc -parse-as-library -o folder-job-tests \
  Sources/ToolConfig/TomlSubset.swift \
  Sources/backup-folder/Retention.swift \
  Sources/backup-folder/PathCheck.swift \
  Sources/backup-folder/BackupConfig.swift \
  Sources/backup-folder/FolderJob.swift \
  tests/folder-job-tests.swift
./folder-job-tests
```

5. Extend `tests/folder-job-tests.swift` for AC2. Accept the worked example, the explicit default strings, `60s/2h` then `1m/8h`, a root list inherited by a folder that omits the key, and a folder list that overrides the root. Reject empty retention, `1w`, bare `60s` then `1m`, `48h` then `2d`, `1h/8h` then `15m/16h`, and an invalid root even when a folder overrides it. Assert the error strings in spec requirement 7. For the hot-reload case, hold a good `ParsedBackupConfig`, re-parse a document whose ages do not increase, call `decideBackupConfigReload`, and assert keep-and-log with prefix `config reload rejected: config parse error:`. Assert the decision is not apply. Assert an equal re-read is unchanged and has a nil log line. Do not write a `retention` key into a watcher document. The `@main` entry stays, and the file stays free of top-level code.
6. Extend `tests/macos-smoke.sh` for AC3. Build stays `bash scripts/build.sh` as the script already does. Use `mktemp` and mode `0600`. Seed empty directories whose names are snapshot candidates. Format those names with `en_US_POSIX` and `TimeZone.current`, the same zone the binary parses, so the age is the name and not the directory modification time. Keep every seeded age at least 60 seconds inside its tier so the run's own duration cannot cross a boundary. Exact one-second boundaries stay in the Phase 0 tests.
   - No `retention` key: a name about one hour old remains, a name about 100 days old is gone, and the new snapshot remains.
   - One config, two destinations. Root `retention` is `4h`. One folder omits the key and a seeded name about two days old is gone. The other folder sets `48h` and `1d/60d`, and the same two-day-old name remains. Both destinations gain a new snapshot.
   - A folder sets `4h`, `15m/8h`, `1d/30d`. Two seeded names in one local hour, minutes 2 and 7, with the later instant about six hours before the run, so both ages sit inside the 15-minute tier. The earlier name remains and the later name is gone.
7. Keep the final echo `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. Do not raise the job timeout.

DoD, from the repo root, on Linux:

```
swiftc -O -o retention-tests Sources/backup-folder/Retention.swift tests/retention-tests.swift
./retention-tests
swiftc -parse-as-library -o folder-job-tests \
  Sources/ToolConfig/TomlSubset.swift \
  Sources/backup-folder/Retention.swift \
  Sources/backup-folder/PathCheck.swift \
  Sources/backup-folder/BackupConfig.swift \
  Sources/backup-folder/FolderJob.swift \
  tests/folder-job-tests.swift
./folder-job-tests
bash tests/linux-unit.sh
bash tests/no-secrets.sh
test -z "$(git diff --name-only -- launchd drop-box-watcher)"
```

The `macos` job runs `bash tests/macos-smoke.sh`. Do not claim that smoke passed unless that job did. Healthy Linux lines include `retention-tests: OK`, `linux-unit: OK`, and `no-secrets: all checks passed`.

### Build notes (Phase 1)

- `BackupConfig` parses optional root and per-folder `retention` arrays, validates per spec requirement 7, and resolves tiers onto each `FolderPair` (folder override, then root, then `defaultTiers`). Invalid root retention fails even when every folder overrides.
- Added `decideBackupConfigReload`; `runConfigJob` uses it with `current: nil` (startup keep-and-log omits the reload prefix). `runOneFolder` passes resolved tiers and `TimeZone.current` into `namesToPrune`; the two-argument command uses `defaultTiers`.
- AC2 equal-interval acceptance uses explicit `interval/age` strings (`60s/2h` then `1m/8h`); bare `60s` then `1m` is rejected because both ages are 60 seconds.
- Extended `tests/folder-job-tests.swift` for AC2 and `tests/macos-smoke.sh` for default, inherited, and 15-minute bucket retention (AC3). Linux CI folder-job compile includes `Retention.swift`.

## Phase 2 — Docs

Files: `README.md`, `backup-folder.example.toml`, `docs/backup-job.md`, `AGENTS.md`.

Do not edit: product sources, `launchd/`, `drop-box-watcher/`, `docs/setup.md`, `docs/restore.md`, `tests/macos-smoke.sh`, release, CodeQL, protect-main, or timeouts. The `launchctl kickstart` paragraph already in `README.md` "How it runs" remains. This phase does not add that paragraph. Setup stays at 33 Manual/Script bullets. Restore stays at 7.

1. In the README retention section, keep the three default bullets. Add the one-line string array, the rule that a folder key overrides a root key and that an absent key uses the default, and the worked example labeled as an example rather than the default. Give the 117 breakdown from spec requirement 13 (48, 16, 16, 8, 29). In "How it runs", say a 5-minute cadence is launchd `StartInterval` 300 or `StartCalendarInterval`, and that the template stays hourly at minute 0. Keep the `launchctl kickstart` paragraph that is already in that section. Placeholders only. Do not say that success is exit 0. Do not name a host, a machine, or a person.
2. In `backup-folder.example.toml`, comment the worked array at the top and a commented folder override. Do not leave an active `retention` key. A copied file with the placeholders still means the tool default.
3. In `docs/backup-job.md`, keep the sentence that destination directories, `backup.log`, and snapshot names stay valid. Say an absent `retention` key uses the default policy, so directories already on disk still age out under that policy.
4. In `AGENTS.md`, record that retention is an optional root list and an optional per-folder list, and that an absent key keeps every snapshot for 48 hours then the earliest of each day for 60 days. Under "Things agents get wrong", state three expectations: do not edit the backup LaunchAgent template onto a 5-minute schedule; do not put retention in the watcher config; do not treat the 4-hour-through-30-day list as the code default.

DoD:

```
bash tests/no-secrets.sh
bash tests/setup-docs.sh
test -z "$(git diff --name-only -- launchd)"
```

Healthy lines: `no-secrets: all checks passed`, `setup-docs: all checks passed`.

### Build notes (Phase 2)

Added only after the phase lands.
