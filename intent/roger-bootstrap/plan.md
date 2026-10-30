# plan.md — Roger bootstrap hub

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 1 |
| Status | Draft 1 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

These phases are not authorized by the docs pull request that adds this folder. They start after review, and only when Nikolay says to build. No phase pushes a tag, sets a real pin, renames the repo, or installs anything on Roger.

Build agent: Composer 2.5, fresh context, one phase per pull request, opened ready for review. The agent does not merge. If Composer 2.5 cannot be launched, stop and ask. The coordinator squash-merges only when `macos` and `CodeQL (Swift)` are both green, then deletes the branch. A cancelled check is not green.

The build agent reads `AGENTS.md`, `REVIEW.md`, [spec.md](spec.md), and this file. It runs that phase's definition-of-done command locally. It does not run `tests/macos-smoke.sh` on Linux, and it does not add a Linux CI job. The `macos` job on the pull request runs the smoke test and the new checks.

Docs are last so they name templates and scripts that are already on `main`.

## Stops

None. Q1–Q6 in the spec stay open. The docs say so in the steps that depend on them. The build does not wait on the repo rename or on notarization.

## Acceptance-criteria coverage

| AC | Check | Phase |
|---|---|---|
| AC1 | `bash tests/setup-docs.sh` | 4 |
| AC2 | `bash tests/no-secrets.sh` | 1 |
| AC3 | `bash tests/no-secrets.sh` | 1 |
| AC4 | `bash tests/no-secrets.sh` | 1 |
| AC5 | `bash tests/release-workflow.sh` | 2 |
| AC6 | `bash tests/install-roger-tools-test.sh` | 3 |
| AC7 | `bash tests/ensure-backup-dirs-test.sh` | 3 |
| AC8 | `bash tests/no-secrets.sh` and `bash tests/release-workflow.sh` | 1 and 2 |
| AC9 | README paragraphs in Phases 1 and 4 | 1 and 4 |
| AC10 | `REVIEW.md` in Phase 1; `AGENTS.md` in Phases 1, 2, 3, and 4 | 1, 2, 3, 4 |

## Phase 1 — Templates and secret scan

Files: `launchd/backup-folder.plist.template`, `launchd/com.wireguard.wg0.plist.template`, `launchd/wg0.conf.template`, `tests/no-secrets.sh`, `.github/workflows/test.yml`, `REVIEW.md`, `AGENTS.md`, `README.md`

1. Replace `launchd/backup-folder.plist.template` with the label, program arguments, `StartCalendarInterval` minute 0, and `RunAtLoad` false from spec FR6. Do not set `Hour`. Remove `StartInterval`.
2. Add `launchd/com.wireguard.wg0.plist.template` with the fields in spec FR5. Well-formed XML plist, same DOCTYPE as the backup template.
3. Add `launchd/wg0.conf.template` as the exact contents in spec FR4.
4. Add `tests/no-secrets.sh` (`set -euo pipefail`). It parses both plists with Python `plistlib` (this works on the Linux cloud VM and on the macOS runner; `plutil` is not required). It asserts the FR5 and FR6 keys and values, asserts minute 0 with no hour key, asserts the backup template has no `StartInterval`, and asserts `wg0.conf.template` matches the FR4 contents aside from one trailing newline. It scans `launchd/`, `docs/` if present, `scripts/` if present, `README.md`, `pins.txt` if present, and `.github/workflows/`. It does not scan `intent/` or itself. The scan fails on an `op://` URI, on a token matching `[A-Za-z0-9+/]{43}=`, and on any workflow file that contains `scripts/install-roger-tools.sh`, `launchctl`, or `Backups`.
5. Add one step to the `macos` job in `.github/workflows/test.yml` that runs `bash tests/no-secrets.sh`. Leave the job name `macos`, the `macos-latest` runner, the timeout, and the smoke step as they are. Do not edit `.github/workflows/codeql.yml` or `.github/scripts/protect-main-branch.sh`.
6. Add `REVIEW.md` from the skill asset `assets/REVIEW.md`. Fill Bugs with: a snapshot whose destination is the source or is inside the source; a backup template that still has `StartInterval` or a real path. Fill Security with: a WireGuard key, endpoint, tunnel address, `op://` path, or personal source-folder name in git; an install script that writes outside `~/bin` or anywhere under `Backups`. Fill the Important line with: those leaks, a release workflow that publishes on a push to `main`, and a workflow that installs on a machine. Keep the three passes, the nit cap, and the "do not report" list.
7. In `AGENTS.md`, record the placeholder rule (no WireGuard key, endpoint, or tunnel address in git; values come from 1Password at install time), the backup label and minute-0 schedule, and that agents do not load the templates or write `~/Backups`.
8. In `README.md`, replace only the "How it runs" paragraph so it says one agent per folder, hourly at minute 0, binary `~/bin/backup-folder`, label `com.nikolay.backup.NAME`, and `launchctl bootstrap gui/$(id -u)`. Say that loading it on Roger is manual.

DoD: `bash tests/no-secrets.sh` exits 0.

## Phase 2 — Attested releases

Files: `.github/workflows/release.yml`, `tests/release-workflow.sh`, `.github/workflows/test.yml`, `AGENTS.md`

1. Keep the trigger as tags matching `v*` on `macos-latest`. Do not add `workflow_dispatch`, a branch push, or a schedule.
2. Build `backup-folder` as today. If `drop-box-watcher.swift` exists in the repo root, build `drop-box-watcher` with the same `swiftc -O -o` form. Do not add the watcher source. Do not edit `.github/workflows/codeql.yml`; the watcher intent updates that compile line if it adds a Swift file.
3. Attest each built binary with `actions/attest@v4`. Set job permissions to `id-token: write`, `attestations: write`, and `contents: write`.
4. Verify each binary with `gh attestation verify`, `--repo nikolaybotev/backup-folder`, `--signer-workflow nikolaybotev/backup-folder/.github/workflows/release.yml`, and `--deny-self-hosted-runners`. Retry the verify a few times on failure, then fail the job. Upload only after verify succeeds, via the existing `softprops/action-gh-release@v2` step, asset name equal to the binary name.
5. Do not push a tag and do not create a release from the phase pull request.
6. Add `tests/release-workflow.sh`. It fails unless `release.yml` contains `actions/attest`, `attestations: write`, `id-token: write`, the `--signer-workflow` value above, `--deny-self-hosted-runners`, and `macos-latest`. It fails if the workflow has a `schedule` key or a push `branches` key. It fails if any file under `.github/workflows/` contains `install-roger-tools.sh`, `launchctl`, or `Backups`.
7. Add a `macos` job step that runs `bash tests/release-workflow.sh`.
8. Update the `AGENTS.md` release paragraph: a `v*` tag attests each built binary and uploads it; merging to `main` still does not publish; do not claim a release ran unless that tag push happened.

DoD: `bash tests/release-workflow.sh` exits 0.

## Phase 3 — Install script and backup directories

Files: `scripts/install-roger-tools.sh`, `scripts/ensure-backup-dirs.sh`, `pins.txt`, `tests/install-roger-tools-test.sh`, `tests/ensure-backup-dirs-test.sh`, `.github/workflows/test.yml`, `AGENTS.md`

1. Add `pins.txt` as the two `unpinned` lines in spec FR10, with a comment that a pin is a `v*` tag and that these phases do not set one.
2. Add `scripts/install-roger-tools.sh` with the behavior in spec FR11. Default repo `nikolaybotev/backup-folder`. It calls `gh` on `PATH`: `gh release download "$tag" --repo "$GH_REPO" --pattern "$tool" --output "$tmp"`. Verify, then `mv` into `$HOME/bin` and `chmod 755`. Create `$HOME/bin` if needed. On verify failure, delete the temp file and do not replace an existing binary. Put the uid and destination checks in a function the test can source. The script runs its main path only when executed, not when sourced. The function returns non-zero when the uid is 0 or when any path component of the install directory is `Backups`.
3. Add `tests/install-roger-tools-test.sh` using a temp `HOME` and a temp pins file. No network. Cases: both tools `unpinned` exits 0 and creates no binary; a pinned tool with `PATH` pointing at a stub `gh` that exits 1 exits non-zero and leaves `~/bin` unchanged; a tool name with a slash or `..` exits non-zero; the sourced function rejects uid 0 and a `Backups` path component.
4. Add `scripts/ensure-backup-dirs.sh` with the behavior in spec FR12.
5. Add `tests/ensure-backup-dirs-test.sh` on temp dirs: create succeeds and a second run succeeds; a relative path and a `..` path exit non-zero; an existing file at the path exits non-zero; a marker file placed beside the new directory is still there afterward.
6. Add `macos` job steps for both test scripts.
7. Update `AGENTS.md` with the two script commands, the pin file, and the refusal rules (`~/bin` only, no `Backups`, no root, no `launchctl`).

DoD: `bash tests/install-roger-tools-test.sh` exits 0 and `bash tests/ensure-backup-dirs-test.sh` exits 0.

## Phase 4 — Setup and restore docs

Files: `docs/setup.md`, `docs/restore.md`, `tests/setup-docs.sh`, `.github/workflows/test.yml`, `README.md`, `AGENTS.md`

1. Write `docs/setup.md` with a short intro (Nikolay runs it, CI does not, heads-up before any install on Roger) and one bullet per setup catalog row 1–32, in order, each starting `- Manual:` or `- Script:` as the Doc column says. Caveats, including FileVault and `sudo fdesetup authrestart`, are paragraphs under a Caveats heading.
2. Write `docs/restore.md` with the new-Mac versus existing-Mac distinction and one bullet per restore row R1–R7.
3. Do not copy tunnel addresses, keys, `op://` paths, GPG key ids, or the runbook's personal source-folder names. Point at the template tokens and at 1Password.
4. For catalog step 30, link the watcher intent's template path if that file exists. If it does not, say the template is added by `intent/drop-box-watcher/` and do not invent the plist.
5. Add `tests/setup-docs.sh`. It fails if either doc is missing, if any bullet does not start with `- Manual:` or `- Script:`, or if any anchor below is absent from `docs/setup.md` (restore anchors must be in `docs/restore.md`).

Setup anchors: `Keep Downloaded`, `FileVault`, `Screen Sharing`, `Remote Login`, `Roger.local`, `raw.github.com/nikolaybotev/bootstrap/main/install.sh`, `mise.en.dev`, `wireguard-tools`, `gh auth login`, `signingkey`, `Grok Bot`, `self-hosted`, `1Password`, `iStat Menus`, `MacVim`, `wg0.conf`, `chmod 600`, `com.wireguard.wg0`, `brew services`, `TM Roger`, `External`, `install-roger-tools.sh`, `ensure-backup-dirs.sh`, `com.nikolay.backup.NAME`, `Drop Box`, `config.toml`.

Restore anchors: `TM Roger`, `Keep Downloaded`, `config.toml`, `install-roger-tools.sh`, `roger-file-access-policy`.

6. Add a `macos` job step that runs `bash tests/setup-docs.sh`.
7. Add a short README paragraph after the opening description: this repo is also the setup hub for the Mac named Roger; setup and restore are `docs/setup.md` and `docs/restore.md`; Nikolay runs them; CI does not install them.
8. Add an `AGENTS.md` pitfall: agents do not run the setup or restore docs, the install script, or `launchctl` against a live machine.

DoD: `bash tests/setup-docs.sh` exits 0 and `bash tests/no-secrets.sh` still exits 0.
