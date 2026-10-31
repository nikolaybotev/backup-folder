# plan.md — the deployment Mac bootstrap hub

| | |
|---|---|
| Implements | [spec.md](spec.md) Draft 2 |
| Status | Draft 2 |
| Stage | 3 · Build |

Spec wins. Update this file in the same change whenever implementation departs from it.

These phases are not authorized by the docs pull request that adds this folder. They start after review, and only when the maintainer says to build. No phase pushes a tag, sets a real pin, renames the repo, or installs anything on the deployment Mac.

Build agent: Composer 2.5, fresh context, one phase per pull request, opened ready for review. The agent does not merge. If Composer 2.5 cannot be launched, stop and ask. The coordinator squash-merges only when `macos` and `CodeQL (Swift)` are both green, then deletes the branch. A cancelled check is not green.

The build agent reads `AGENTS.md`, `REVIEW.md`, [spec.md](spec.md), and this file. It runs that phase's definition-of-done command locally. It does not run `tests/macos-smoke.sh` on Linux, and it does not add a Linux CI job. The `macos` job on the pull request runs the smoke test and the new checks.

Docs are last so they name templates and scripts that are already on `main`.

PR #6 merged on 2026-10-30. It deletes `.github/scripts/protect-main-branch.sh` and `.github/workflows/protect-main.yml`, and it replaces the CodeQL bullet in `AGENTS.md` (the commands bullet that begins `CodeQL:`). Bootstrap phases must not recreate that script or rewrite that paragraph. They also must not recreate the deleted workflow.

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
| AC6 | `bash tests/install-tools-test.sh` | 3 |
| AC7 | `bash tests/ensure-backup-dirs-test.sh` | 3 |
| AC8 | `bash tests/no-secrets.sh` and `bash tests/release-workflow.sh` | 1 and 2 |
| AC9 | README paragraphs in Phases 1 and 4 | 1 and 4 |
| AC10 | `REVIEW.md` in Phase 1; `AGENTS.md` in Phases 1, 2, 3, and 4 | 1, 2, 3, 4 |

## Phase 1 — Templates and secret scan

Files: `launchd/backup-folder.plist.template`, `launchd/com.wireguard.wg0.plist.template`, `launchd/wg0.conf.template`, `tests/no-secrets.sh`, `.github/workflows/test.yml`, `REVIEW.md`, `AGENTS.md`, `README.md`

1. Replace `launchd/backup-folder.plist.template` with the label, program arguments, `StartCalendarInterval` minute 0, and `RunAtLoad` false from spec FR6. Do not set `Hour`. Remove `StartInterval`.
2. Add `launchd/com.wireguard.wg0.plist.template` with the fields in spec FR5. Well-formed XML plist, same DOCTYPE as the backup template.
3. Add `launchd/wg0.conf.template` as the exact contents in spec FR4.
4. Add `tests/no-secrets.sh` (`set -euo pipefail`). It parses both plists with Python `plistlib` (this works on the Linux cloud VM and on the macOS runner; `plutil` is not required). It asserts the FR5 and FR6 keys and values, asserts minute 0 with no hour key, asserts the backup template has no `StartInterval`, and asserts `wg0.conf.template` matches the FR4 contents aside from one trailing newline. It scans `intent/`, `launchd/`, `docs/` if present, `scripts/` if present, `README.md`, `pins.txt` if present, and `.github/workflows/`. It does not scan itself. The scan fails on a 1Password item URI, on a token matching the WireGuard key shape (43 base64 characters and `=`), on an IPv4 literal (four decimal octets separated by dots), on an IPv6 literal (a compressed or fully written IPv6 address), and on a numeric port suffix (a colon followed by a decimal integer). The patterns must not themselves contain a match, and the test must not embed the runbook's real addresses, prefix, or port. The FR4 placeholder endpoint uses `[PORT]`, which is not a decimal integer. The scan also fails on any workflow file that contains `scripts/install-tools.sh`, `launchctl`, or `Backups`.
5. Add one step to the `macos` job in `.github/workflows/test.yml` that runs `bash tests/no-secrets.sh`. Leave the job name `macos`, the `macos-latest` runner, the timeout, and the smoke step as they are. Do not edit `.github/workflows/codeql.yml`. Do not recreate `.github/scripts/protect-main-branch.sh` or `.github/workflows/protect-main.yml`.
6. Add `REVIEW.md` from the skill asset `assets/REVIEW.md`. Fill Bugs with: a snapshot whose destination is the source or is inside the source; a backup template that still has `StartInterval` or a real path. Fill Security with: a WireGuard key, endpoint, tunnel address, 1Password item URI path, or personal source-folder name in git; an install script that writes outside `~/bin` or anywhere under `Backups`. Fill the Important line with: those leaks, a release workflow that publishes on a push to `main`, and a workflow that installs on a machine. Keep the three passes, the nit cap, and the "do not report" list.
7. In `AGENTS.md`, record the placeholder rule (no WireGuard key, endpoint, or tunnel address in git; values come from 1Password at install time), the backup label and minute-0 schedule, and that agents do not load the templates or write `~/Backups`. Do not rewrite the CodeQL bullet. PR #6 owns that paragraph.
8. In `README.md`, replace only the "How it runs" paragraph so it says one agent per folder, hourly at minute 0, binary `~/bin/backup-folder`, label `com.nikolay.backup.NAME`, and `launchctl bootstrap gui/$(id -u)`. Say that loading it on the deployment Mac is manual.

DoD: `bash tests/no-secrets.sh` exits 0.

**Phase 1 departure (2026-10-30):** Reworded a few lines in `intent/roger-bootstrap/spec.md`, this plan, and `intent/drop-box-watcher/spec.md` so the Phase 1 secret scan can pass over `intent/` without changing requirements. Prose now says "1Password item URI" and "IPv4 loopback address" instead of literals the scan forbids.

## Phase 2 — Attested releases

Files: `.github/workflows/release.yml`, `tests/release-workflow.sh`, `.github/workflows/test.yml`, `AGENTS.md`

1. Keep the trigger as tags matching `v*` on `macos-latest`. Do not add `workflow_dispatch`, a branch push, or a schedule.
2. Build `backup-folder` as today. If `drop-box-watcher.swift` exists in the repo root, build `drop-box-watcher` with the same `swiftc -O -o` form. Do not add the watcher source. Do not edit `.github/workflows/codeql.yml`; the watcher intent updates that compile line if it adds a Swift file.
3. Attest each built binary with `actions/attest@v4` and set `subject-path` to that binary. Set job permissions to `id-token: write`, `attestations: write`, and `contents: write`. Do not set `artifact-metadata: write`. Do not set `push-to-registry`.
4. Verify each binary with `gh attestation verify`, `--repo nikolaybotev/backup-folder`, `--signer-workflow nikolaybotev/backup-folder/.github/workflows/release.yml`, and `--deny-self-hosted-runners`. Retry the verify a few times on failure, then fail the job. Upload only after verify succeeds, via the existing `softprops/action-gh-release@v2` step, asset name equal to the binary name.
5. Do not push a tag and do not create a release from the phase pull request.
6. Add `tests/release-workflow.sh`. It fails unless `release.yml` contains `actions/attest`, `subject-path`, `attestations: write`, `id-token: write`, `contents: write`, the `--signer-workflow` value above, `--deny-self-hosted-runners`, and `macos-latest`. It fails if `release.yml` has a `schedule` key or a push `branches` key. Those two bans apply only to `release.yml`: on main, `codeql.yml` has a `schedule` and `branches`, and `test.yml` has `branches`. It does not require `artifact-metadata: write`. The `v*` tag trigger stays. It fails if any file under `.github/workflows/` contains `install-tools.sh`, `launchctl`, or `Backups`.
7. Add a `macos` job step that runs `bash tests/release-workflow.sh`.
8. Update the `AGENTS.md` release paragraph: a `v*` tag attests each built binary and uploads it; merging to `main` still does not publish; do not claim a release ran unless that tag push happened. Leave the CodeQL bullet unchanged.

DoD: `bash tests/release-workflow.sh` exits 0.

## Phase 3 — Install script and backup directories

Files: `scripts/install-tools.sh`, `scripts/ensure-backup-dirs.sh`, `pins.txt`, `tests/install-tools-test.sh`, `tests/ensure-backup-dirs-test.sh`, `.github/workflows/test.yml`, `AGENTS.md`

1. Add `pins.txt` as the two `unpinned` lines in spec FR10, with a comment that a pin is a `v*` tag and that these phases do not set one.
2. Add `scripts/install-tools.sh` with the behavior in spec FR11. Default repo `nikolaybotev/backup-folder`. It calls `gh` on `PATH`: `gh release download "$tag" --repo "$GH_REPO" --pattern "$tool" --output "$tmp"`. Verify, then `mv` into `$HOME/bin` and `chmod 755`. Create `$HOME/bin` if needed. On verify failure, delete the temp file and do not replace an existing binary. A tag that is neither `unpinned` nor `v` plus digits and dots exits non-zero and installs nothing. Put the uid and destination checks in a function the test can source. The function takes the uid as an argument. The script runs its main path only when executed, not when sourced, and the main path passes the effective uid into that function. The function returns non-zero when the uid argument is 0 or when any path component of the install directory is `Backups`. The script contains the FR9 verify flags and does not contain `launchctl`, `sudo`, or `op`.
3. Add `tests/install-tools-test.sh` using a temp `HOME` and a temp pins file. No network. Cases: both tools `unpinned` exits 0 and creates no binary; a pin that is neither `unpinned` nor `v` plus digits and dots exits non-zero and installs nothing; a pinned tool whose stub `gh` writes the temp file and exits 0 leaves `$HOME/bin/<tool>` at mode `755`; a tool name with a slash or `..` exits non-zero. The test calls the sourced function with uid 0 as an argument and expects a refusal, and it expects a refusal for a `Backups` path component. It statically checks that the script contains `--repo nikolaybotev/backup-folder`, `--signer-workflow nikolaybotev/backup-folder/.github/workflows/release.yml`, and `--deny-self-hosted-runners`, and that the script does not contain `launchctl`, `sudo`, or `op`.
4. Add `scripts/ensure-backup-dirs.sh` with the behavior in spec FR12.
5. Add `tests/ensure-backup-dirs-test.sh` on temp dirs: create succeeds and a second run succeeds; a relative path and a `..` path exit non-zero; an existing file at the path exits non-zero; a marker file placed beside the new directory is still there afterward.
6. Add `macos` job steps for both test scripts.
7. Update `AGENTS.md` with the two script commands, the pin file, and the refusal rules (`~/bin` only, no `Backups`, no root, no `launchctl`). Leave the CodeQL bullet unchanged.

DoD: `bash tests/install-tools-test.sh` exits 0 and `bash tests/ensure-backup-dirs-test.sh` exits 0.

## Phase 4 — Setup and restore docs

Files: `docs/setup.md`, `docs/restore.md`, `tests/setup-docs.sh`, `.github/workflows/test.yml`, `README.md`, `AGENTS.md`

1. Write `docs/setup.md` with a short intro (the maintainer runs it, CI does not, heads-up before any install on the deployment Mac) and one bullet per setup catalog row 1–32, in order, each starting `- Manual:` or `- Script:` as the Doc column says. Caveats, including FileVault and `sudo fdesetup authrestart`, are paragraphs under a Caveats heading.
2. Write `docs/restore.md` with the new-Mac versus existing-Mac distinction and one bullet per restore row R1–R7.
3. Do not copy tunnel addresses, keys, 1Password item URI paths, GPG key ids, or the runbook's personal source-folder names. Point at the template tokens and at 1Password.
4. For catalog step 30, link the watcher intent's template path if that file exists. If it does not, say the template is added by `intent/drop-box-watcher/` and do not invent the plist.
5. Add `tests/setup-docs.sh`. It fails if either doc is missing, if any bullet does not start with `- Manual:` or `- Script:`, if `docs/setup.md` does not have 32 such bullets, if `docs/restore.md` does not have 7 such bullets, or if any anchor below is absent from `docs/setup.md` (restore anchors must be in `docs/restore.md`).

Setup anchors: `Keep Downloaded`, `FileVault`, `Screen Sharing`, `Remote Login`, `HOST.local`, `raw.github.com/nikolaybotev/bootstrap/main/install.sh`, `jq`, `fresh Mac`, `mise.en.dev`, `wireguard-tools`, `gh auth login`, `gnupg`, `pinentry`, `signingkey`, `Grok Bot`, `self-hosted`, `1Password`, `iStat Menus`, `MacVim`, `wg0.conf`, `chmod 600`, `com.wireguard.wg0`, `brew services`, `fdesetup`, `a named Time Machine volume`, `External`, `install-tools.sh`, `ensure-backup-dirs.sh`, `home-mirrored`, `com.nikolay.backup.NAME`, `Drop Box`, `config.toml`.

Restore anchors: `a named Time Machine volume`, `home-mirrored`, `Keep Downloaded`, `config.toml`, `install-tools.sh`, `file-access-policy`.

6. Add a `macos` job step that runs `bash tests/setup-docs.sh`.
7. Add a short README paragraph after the opening description: this repo is also the setup hub for the deployment Mac; setup and restore are `docs/setup.md` and `docs/restore.md`; the maintainer runs them; CI does not install them.
8. Add an `AGENTS.md` pitfall: agents do not run the setup or restore docs, the install script, or `launchctl` against a live machine. Leave the CodeQL bullet unchanged.

DoD: `bash tests/setup-docs.sh` exits 0 and `bash tests/no-secrets.sh` still exits 0.
