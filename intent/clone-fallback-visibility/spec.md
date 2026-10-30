# spec.md — clone fallback visibility

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-29) |
| Status | Draft 1 |
| Stage | 2 · Design |

## 1. Summary

`backup-folder.swift` lines 49–51 fall from a non-zero `clonefile` into `copyItem`. A successful `copyItem` does not log and does not increment `failures`, so line 59 still logs `OK snapshot`. Line 27 creates `dest` with `try?`. `log` (lines 20–25) writes the file only; a failed write is swallowed. This intent makes a full copy visible and makes a failed `dest` create exit non-zero. It does not change which runs publish.

## 2. Goals and non-goals

**Goals**

- G1. A file stored by `copyItem` after `clonefile` fails is reported, with the errno from that `clonefile`.
- G2. The `OK` line states how many files were full copies.
- G3. Every line `log` writes also goes to stderr.
- G4. If `dest` cannot be created, the process writes the reason to stderr and exits 1 before the walk.

**Non-goals**

- Do not treat a successful full copy as an item failure, and do not withhold `OK` for that reason.
- Do not change snapshot names, retention, the containment check, symlink handling, or the rule that `failures > 0` still publishes. Those are the later intents.
- Do not call `clonefile` on a directory.
- Do not read or write `~/Backups` or `~/Backups/bin/backup-folder`. Do not push a `v*` tag.

**Release phasing.** G1–G4 ship in this intent’s only phase. Untagged requirements in this file belong to that phase.

## 3. Principles

- P1. `clonefile`’s errno is read before any other call. A later `copyItem` must not replace it.
- P2. The smoke success line stays `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`.

## 4. Users and scenarios

- A backup on another volume cannot APFS-clone. The run still publishes, and the log shows a full copy rather than a bare `OK`.
- The operator points `dest` at a directory that cannot be created. The process exits 1 and the reason is on stderr.

## 5. Functional requirements

1. When `clonefile` returns non-zero and `copyItem` succeeds, append one log line `WARNING: clonefile failed for <path> (errno <n>); full copy`. `<path>` is the source file path. `<n>` is the errno captured immediately after `clonefile`. Do not increment `failures`.
2. When `clonefile` returns non-zero and `copyItem` throws, keep the current `ERROR: copy <path>: <error>` line and the `failures` increment.
3. Replace the success line with `OK snapshot <ts> (<count> files, <fallbacks> full copies)`. `<count>` stays the current non-directory walk of the published snapshot. `<fallbacks>` is the number of requirement 1 events in that run. Zero is printed as `0`.
4. `log` writes that same line to stderr and to `dest/backup.log`. Usage and the containment refusal stay stderr-only; they stay off the log, matching lines 10 and 15.
5. The log line’s timestamp formatter sets its locale to `en_US_POSIX`. The snapshot-name formatter is unchanged in this intent.
6. `createDirectory` for `dest` is not `try?`. On failure, write `ERROR: cannot create <dest>: <error>` to stderr, do not start the walk, and exit 1.
7. The existing APFS smoke fixture (two regular files) logs `2 files, 0 full copies`.

## 6. Acceptance criteria

- AC1. `bash tests/macos-smoke.sh` exits 0 and prints `macos-smoke: build OK, clonefile probe OK, snapshot OK, COW OK`. The success log contains `2 files, 0 full copies`.
- AC2. The relative-path and missing-argument cases still exit 2.
- AC3. The GitHub Actions job `macos` is green. The CodeQL job is green. Its build line is unchanged because this phase adds no Swift file.
- AC4. No `v*` tag is pushed. `~/Backups` is not used.

## 7. Design decisions

**D1 — The required check is `macos`.** `.github/workflows/test.yml` job `macos` runs on `macos-latest` with `timeout-minutes: 20` and `bash tests/macos-smoke.sh`. There is no Linux job on `main`. Do not add a job that type-checks or links `backup-folder.swift`.

**D2 — CodeQL stays.** Commit `7625d0226f3df4e7ab81f4571b0ff74d09232320` (`#2`) added `.github/workflows/codeql.yml`: Swift, `macos-26`, `build-mode: manual`, `swiftc -O -o backup-folder backup-folder.swift`, timeout 30 minutes. Do not remove it and do not change the runner pin. `AGENTS.md` still says CodeQL is not enabled; correct that sentence in the first build phase that edits `AGENTS.md` (snapshot-identity phase 0), not in this docs change.

**D3 — Release stays tag-driven.** `.github/workflows/release.yml` runs on `v*` tags. This phase does not change its build line and does not push a tag.

**D4 — Do not touch the installed backup.** Never read or write `~/Backups` or `~/Backups/bin/backup-folder`. Merging does not install on Roger.

**D5 — Who builds, and when it merges.** Spec, plan, and review use Grok 4.7 High. The build phase uses Composer 2.5. One phase is one branch and one pull request. The coordinator squash-merges only when the `macos` check is green, then deletes the branch. A cancelled check is not green.

**D6 — What the runner cannot prove.** A macOS runner cannot prove live `~/Backups`, Full Disk Access, LaunchAgents, or iCloud directory-clone refusal. Do not call `clonefile` on a directory.

**D7 — History and the protect script.** Ruleset 26167970 requires a pull request, a signed commit, linear history, squash merge, and delete-branch-on-merge, and it blocks deletion and force-push. Do not force-push. Do not edit `.github/scripts/protect-main-branch.sh` or `.github/workflows/protect-main.yml`. The script’s PUT body sets deletion, non-fast-forward, and required check `macos` only.

**D8 — Build order.** clone-fallback-visibility phase 0, then honest-snapshot phase 0, then snapshot-identity phase 0, then snapshot-identity phase 1, then path-containment phase 0, then clone-walk phase 0. Start a phase only after the previous one is merged.

**D9 — A full copy stays a success.** The README says a normal copy is used when cloning a file fails. G1 reports that path. It does not fail the run. A cross-volume fallback is not required in CI: the runner has one APFS volume for the smoke dir, and AC1 locks the zero-fallback line on that volume.

## 8. Open questions

None.
