# plan.md — Test webhook helper

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

Build gate: maintainer approved 2026-10-31. One build pull request unless a step below proves a real split.

The pull request that adds this folder does not start Phase 0. Phase 0 starts only when someone says to build. The build pull request opens ready for review with a conventional commit. Do not merge from agent work unless assigned. Required checks stay `macos` and `linux`. Do not add a `release:minor` or `release:major` label. Do not install, load, or reload anything. Do not read a live watcher config or routine key.

Merging the build pull request to `main` runs job `publish`, which calls `scripts/release-version.sh`. With no release label on that pull request, the script chooses the next patch tag (for example `v0.1.2` when the latest tag is `v0.1.1`), may push that tag, and publishes a GitHub release uploading only `backup-folder`, `drop-box-watcher`, and `SHA256SUMS`. The helper script is not a release asset. That behavior is existing workflow; this intent does not change the version scheme.

## Stops

None.

## This pull request (design only)

Files: `intent/test-webhook/` only.

DoD: `git diff --name-only origin/main` lists only `intent/test-webhook/`. `bash tests/no-secrets.sh` exits 0 (healthy: `no-secrets: all checks passed`).

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | review `scripts/test-webhook.sh` | 0 |
| AC2 | `tests/test-webhook.sh` negative case | 0 |
| AC3 | `tests/test-webhook.sh` output grep | 0 |
| AC4 | review test fixtures | 0 |
| AC5 | README diff | 0 |
| AC6 | `bash tests/test-webhook.sh` on both jobs | 0 |
| AC7 | `bash tests/release-workflow.sh` | 0 |
| AC7 | design spec requirement 11 | this pull request |

## Phase 0 — Helper, test, docs

Single build pull request. No phase split unless implementation discovers an independent deliverable; none expected.

Files: `scripts/test-webhook.sh`, `tests/test-webhook.sh`, `.github/workflows/test.yml`, `README.md`, `AGENTS.md`.

Do not edit: `drop-box-watcher/`, `Sources/`, `launchd/`, `scripts/build.sh`, `scripts/release-version.sh`, `scripts/install-tools.sh`, `scripts/ensure-backup-dirs.sh`, `.github/workflows/release.yml`, `.github/workflows/codeql.yml`, `.github/scripts/protect-main-branch.sh`, `drop-box-watcher.example.toml`, `pins.txt.example`, or any other `intent/` folder.

1. Implement `scripts/test-webhook.sh` per spec requirements 1–6. Start from the approved sketch in [intent.md](intent.md) Original prompt. Add optional config argument and validation messages. Keep `curl -K -` and the manual JSON body.
2. Add `tests/test-webhook.sh` per requirements 7–8. Reuse the loopback listener pattern from `tests/macos-watcher.sh` (Python 3, ephemeral port, assert Authorization and body). Use dummy key `test-webhook-integration-key` and a temp config under `$TMPDIR`. Never read `~/.config/drop-box-watcher/config.toml` in the test.
3. Add one step to job `linux` and job `macos` in `.github/workflows/test.yml`: `bash tests/test-webhook.sh`. Do not change `timeout-minutes`.
4. Add one sentence to README `## drop-box-watcher` per requirement 9.
5. Extend `AGENTS.md` Commands with `bash tests/test-webhook.sh` (healthy: `test-webhook: OK`) and note that operators on macOS may run `scripts/test-webhook.sh` with the default or an explicit config path.

DoD:

```
bash tests/test-webhook.sh
bash tests/no-secrets.sh
bash tests/release-workflow.sh
bash tests/build-entry-test.sh
```

Healthy lines: `test-webhook: OK`, `no-secrets: all checks passed`, `release-workflow: …`, `build-entry-test: all checks passed`. Pull request CI: jobs `macos` and `linux` green.

### Build notes (Phase 0)

Added only after the phase lands.
