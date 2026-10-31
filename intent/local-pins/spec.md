# spec.md — Local pins

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-30) |
| Status | Draft 3 |
| Stage | 2 · Design |

## 1. Summary

Stop tracking the pin file. The installer reads `~/.config/backup-folder/pins.txt` on the machine that runs it. The repo keeps `pins.txt.example` as the format, with both tools `unpinned`. Rename `scripts/install-tools.sh` to `scripts/install-tools.sh` and rename its test the same way. Do not use the name `scripts/install.sh`.

Merging this change to `main` still publishes the next patch tag. That is acceptable, because the pin file is not in the commit. This spec does not change publish-on-merge. Nothing is installed.

## 2. Goals and non-goals

**Goals**

- G1. `pins.txt` is not tracked. The live pin file is `~/.config/backup-folder/pins.txt`.
- G2. `pins.txt.example` documents the format and contains no real pin.
- G3. The installer and its test are `scripts/install-tools.sh` and `tests/install-tools-test.sh`.
- G4. Live references outside prior `intent/` folders use those names and the local pin path.
- G5. Install behavior stays: `~/bin` only, refuse uid 0, refuse a path component named `Backups`, `gh release download`, `gh attestation verify`, no build from source.

**Non-goals**

- Editing `.github/workflows/release.yml` or `scripts/release-version.sh`.
- Adding `release:minor` or `release:major`, or otherwise suppressing the patch tag.
- Switching the installer to `SHA256SUMS`. [release-builds](../release-builds/spec.md) FR16 describes that checksum design. It has not landed. This change does not land it.
- Setting a real pin, writing `~/.config/backup-folder/pins.txt`, running the installer, or writing under `~/Backups` or a real `~/bin`.
- Renaming or editing `.cursor/install.sh`.
- Editing `README.md`, prior `intent/` folders, or the LaunchAgent templates.
- A new required check, a timeout change, or CodeQL on pull requests.
- Secrets, a webhook URL, or keys.

**Release phasing.** All of G1–G5 ship in one implementation pull request. Untagged requirements belong to that release. The pull request that adds this folder does not implement them.

## 3. Principles

- P1. A pin lives on the machine that uses it. A git commit does not carry one.
- P2. The installer name is generic. It installs the tools named in the local pin file. It is not named for the deployment Mac.
- P3. Docs may still say that Mac is named the deployment Mac, and that the maintainer runs the script there.
- P4. Publish-on-merge stays. A patch tag from this merge is acceptable because the pin file is not in the commit.
- P5. Agents and CI do not install anything.

## 4. Users and scenarios

- **the maintainer** copies `pins.txt.example` to `~/.config/backup-folder/pins.txt`, edits the tags there, and runs `bash scripts/install-tools.sh` on the Mac. This spec does not do that.
- **CI and agents** run `bash tests/install-tools-test.sh` against a temporary `HOME`. They do not write the live pin file and do not run the installer against a home directory.

Scenarios:

- **S1. Pinned install.** The local file names a `v*` tag. The script downloads that release asset and verifies the attestation, then moves it to `~/bin/<tool>` mode `755`.
- **S2. Unpinned.** The script prints a skip and installs nothing.
- **S3. Missing pin file.** The script exits non-zero and installs nothing. It does not create `~/.config/backup-folder`.
- **S4. Merge.** A merge to `main` still runs job `publish`. With no release label, that publishes the next patch tag. The commit contains `pins.txt.example` with `unpinned` lines, not a live pin.

## 5. Functional requirements

FR1. Remove `pins.txt` from git. Add `/pins.txt` to `.gitignore`, the same root-anchored style as `/backup-folder` and `/drop-box-watcher`. That pattern ignores a repo-root `pins.txt` and does not ignore `pins.txt.example`.

FR2. Add `pins.txt.example` at the repo root. The installer does not read that path. Comments are `#` comments, the same rule the installer already uses: it strips from the first `#` to the end of the line and skips a line that is then empty. Comments state that the live file is `~/.config/backup-folder/pins.txt`, that this example is not the live pin, and that a data line is a tool name plus either `unpinned` or a `v*` tag (`v` plus numeric components). The only data lines are:

```
backup-folder unpinned
drop-box-watcher unpinned
```

No data line is a real tag. Do not write `v0.1.1` or any other `v*` pin into the example.

FR3. `scripts/install-tools.sh` is the installer. `tests/install-tools-test.sh` is its test. `scripts/install-tools.sh` and `tests/install-tools-test.sh` are gone from the tree. The matching test name is `tests/install-tools-test.sh`, not `tests/install.sh`.

FR4. When `PINS_FILE` is unset or empty, the script reads `${HOME}/.config/backup-folder/pins.txt`. It does not default to `$ROOT/pins.txt`. `PINS_FILE` and `GH_REPO` still override. The default repo stays `nikolaybotev/backup-folder`. A missing pin file exits non-zero and installs nothing. The script does not create `~/.config/backup-folder`.

FR5. Install behavior otherwise stays as `scripts/install-tools.sh` behaves on `616a904`. The destination is `${HOME}/bin` only. The sourced refusal function returns non-zero for uid 0 and for any path component named `Backups`. The main path passes the effective uid and `${HOME}/bin`. `unpinned` skips. A tag that is neither `unpinned` nor `v` plus numeric components exits non-zero and installs nothing. The tool name must match `^[a-z0-9][a-z0-9-]*$`. A real pin uses `gh release download` and then `gh attestation verify` with `--repo nikolaybotev/backup-folder`, `--signer-workflow nikolaybotev/backup-folder/.github/workflows/release.yml`, and `--deny-self-hosted-runners`. Verify or download failure deletes the temp file, leaves any existing `~/bin` binary in place, and exits non-zero. Success moves the file to `~/bin/<tool>` and `chmod 755`. The script does not build from source and does not call `launchctl`, `sudo`, or `op`. It does not read or write `~/Backups`. The main path runs only when the file is executed, not when it is sourced.

FR6. The script and the test contain no case-insensitive legacy host-name token. Log lines use the prefix `install-tools:`. The temp-file prefix is `install-tools.`. The sourced function is `install_refuse` (it was `legacy_install_refuse`). The test's healthy line is `install-tools-test: all checks passed`.

FR7. Update live references. Do not edit prior folders under `intent/`. Do not edit `README.md`.

- `AGENTS.md` names `scripts/install-tools.sh`, `tests/install-tools-test.sh`, and `~/.config/backup-folder/pins.txt`. The installer bullet, the pins bullet, and the `~/bin` convention each point at that live path or at `pins.txt.example`. None of them names a tracked `pins.txt` as the pin list. `pins.txt.example` is the format and is not the live pin. Agents do not write the live pin file, do not commit a real pin, and do not run the installer against a home directory. Sentences that name the Mac the deployment Mac stay.
- `docs/setup.md` and `docs/restore.md` name `scripts/install-tools.sh` and `~/.config/backup-folder/pins.txt`, and link `pins.txt.example`. They do not link `../pins.txt`. They keep the existing `Script:` bullets. `docs/setup.md` stays at 33 `Manual:` or `Script:` bullets. `docs/restore.md` stays at 7.
- `tests/setup-docs.sh` requires the anchor `install-tools.sh` where it now requires `install-tools.sh`, in both the setup list and the restore list. It also requires `.config/backup-folder/pins.txt` and `pins.txt.example` in both docs.
- `.github/workflows/test.yml` runs `bash tests/install-tools-test.sh` in the `macos` job. The step name does not say the deployment Mac. The `linux` job does not gain this step. Job names stay `macos` and `linux`. `timeout-minutes` stay 5 on both. No new job.
- `tests/no-secrets.sh` always scans `pins.txt.example`. It still scans `pins.txt` when that file exists, and it does not fail because `pins.txt` is absent. Its workflow ban matches `scripts/install-tools.sh` and still matches `scripts/install-tools.sh`, plus `launchctl` and `Backups`.
- `tests/release-workflow.sh` fails if any file under `.github/workflows/` contains `install-tools.sh` or `install-tools.sh`. `install-tools.sh` is not a substring of `install-tools-test.sh`, so the `macos` step that runs the test does not trip that ban. The same is already true of `install-tools.sh` and `install-tools-test.sh`.

FR8. `.github/workflows/codeql.yml` stays without a `pull_request` trigger. `.github/workflows/release.yml` and `scripts/release-version.sh` are unchanged.

FR9. The spec-and-plan pull request's diff is only `intent/local-pins/`. The implementation pull request does not run the installer against a home directory, does not write `~/.config/backup-folder/pins.txt`, does not touch `~/Backups`, and does not commit a real pin.

## 6. Acceptance criteria

AC1. `git ls-files` does not list `pins.txt`, `scripts/install-tools.sh`, or `tests/install-tools-test.sh`. It lists `pins.txt.example`, `scripts/install-tools.sh`, and `tests/install-tools-test.sh`. `git check-ignore -q pins.txt` succeeds. `git check-ignore -q pins.txt.example` does not.

AC2. After the installer's `#` strip and blank-line skip, the only lines in `pins.txt.example` are `backup-folder unpinned` and `drop-box-watcher unpinned`. The raw file contains no `v` followed by a digit.

AC3. With `PINS_FILE` unset, a temporary `HOME`, and no pin file, `bash scripts/install-tools.sh` exits non-zero and creates neither a `~/bin` binary nor `~/.config/backup-folder`. Copying `pins.txt.example` to `$HOME/.config/backup-folder/pins.txt`, comments included, and running with `PINS_FILE` unset exits 0 and installs nothing. The test supplies that temporary `HOME`. It does not use a real home.

AC4. `bash tests/install-tools-test.sh` exits 0 and prints `install-tools-test: all checks passed`. It keeps the current cases: uid 0 refused, a `Backups` path component refused, both tools `unpinned`, an invalid pin, a tool name with a slash, `bad..name`, and a stub `gh` that leaves mode `755`. It checks the attestation flags and the absence of `launchctl`, `sudo`, and `op`. Neither the script nor the test matches the legacy host-name token case-insensitively.

AC5. `bash tests/setup-docs.sh`, `bash tests/no-secrets.sh`, and `bash tests/release-workflow.sh` exit 0.

AC6. Outside `intent/`, the pre-rename install script basename appears only in the workflow bans in `tests/no-secrets.sh` and `tests/release-workflow.sh`. `docs/setup.md`, `docs/restore.md`, and `AGENTS.md` contain no markdown link target `../pins.txt` and no backticked `` `pins.txt` ``. Links to `pins.txt.example` stay.

AC7. `git diff` against the implementation's parent shows no change to `.github/workflows/release.yml`, `scripts/release-version.sh`, `.github/workflows/codeql.yml`, `README.md`, `.cursor/install.sh`, or any `timeout-minutes` line. `.github/workflows/test.yml` still has jobs `macos` and `linux` only, each with `timeout-minutes: 5`. The `linux` job does not run the install test.

AC8. The spec-and-plan pull request's diff is only `intent/local-pins/`.

AC9. Merging the spec-and-plan pull request, and merging the implementation pull request, each still run job `publish` on `main`. With neither `release:minor` nor `release:major` on the merged pull request, `scripts/release-version.sh` emits the next patch tag and `publish` can publish it. That is acceptable. The pin file is not in either commit. This spec does not change that behavior and does not name the tag, because another merge can land first.

## 7. Design decisions

**D1 — The pin file is local.** Remove tracked `pins.txt` and gitignore `/pins.txt`. The live file is `~/.config/backup-folder/pins.txt`. The script reads that path. `pins.txt.example` documents the format and is not the live pin. It ships with both tools `unpinned` and no real `v*` tag. Why: a tracked pin is a commit, and a merge to `main` publishes a release. A local file removes that coupling. What was rejected: keeping `pins.txt` in git, and putting a real pin in the example. Checked on `616a904`: `git ls-files` lists `pins.txt`; `.gitignore` does not match it; both data lines are `unpinned`.

**D2 — The script is `scripts/install-tools.sh`.** Rename the legacy install script and its test to `scripts/install-tools.sh` and `tests/install-tools-test.sh`. Update every live reference in `AGENTS.md`, `docs/setup.md`, `docs/restore.md`, `tests/setup-docs.sh`, and `.github/workflows/test.yml`. The new script name has no the legacy host-name token. Why: the script installs whatever tools the local pin file names. It is not specific to the machine named the deployment Mac.

Rejected alternative: `scripts/install.sh`. The maintainer asked to use that name only if nothing else install-related makes it ambiguous. It is ambiguous. Do not rename to `scripts/install.sh`.

On main, `.cursor/install.sh` is the Cloud Agent environment installer. README.md says cloud agents run it: it apt-installs libncurses6, then mise and the pinned Swift toolchain. A second file named `install.sh`, even under `scripts/`, would collide with that name.

Also present, and not install scripts: `launchd/backup-folder.plist.template`, `launchd/drop-box-watcher.plist.template`, `launchd/com.wireguard.wg0.plist.template`, `docs/setup.md`. Those do not change the name.

Checked on `616a904` before freezing the name. `.cursor/environment.json` sets `"install": "bash .cursor/install.sh"`. `README.md` says cloud agents run that script, and that it installs `libncurses6`, then mise and the Swift release pinned in `mise.toml`. The script itself installs the mise binary first when `~/.local/bin/mise` is missing, then apt-installs `libncurses6` when `libncurses.so.6` is absent, then runs `mise install`. It also pipes `https://raw.githubusercontent.com/nikolaybotev/local-skills/main/install.sh`. `git ls-files` lists `.cursor/install.sh` and `scripts/install-tools.sh`, and no `scripts/install.sh`. The three plist templates and `docs/setup.md` are present. `docs/setup.md` links `raw.github.com/nikolaybotev/bootstrap/main/install.sh`. That link does not change the chosen name. The chosen name remains `scripts/install-tools.sh`.

**D3 — Publish-on-merge stays.** `.github/workflows/release.yml` runs job `publish` on every push to `main`. `scripts/release-version.sh` prints `tag vMAJOR.MINOR.PATCH` with the patch incremented when the merged pull request has neither `release:minor` nor `release:major`. Merging the spec-and-plan pull request does that. Merging the implementation pull request does that again. Both are acceptable, because neither commit contains the pin file. This spec does not edit the workflow, the version script, or the labels. On `616a904` the only `vMAJOR.MINOR.PATCH` tag is `v0.1.1`. This spec does not freeze the next number. Another merge can land first.

**D4 — Attestation stays.** The installer on `616a904` uses `gh release download` and `gh attestation verify`. It does not check `SHA256SUMS` and it does not build from source. Keep that. Do not implement the checksum design in release-builds FR16 as part of this change. Why: the assignment says the renamed script still uses those two `gh` commands. What was rejected: changing verification while renaming the file.

**D5 — Prior intents stay put.** `intent/roger-bootstrap/` and `intent/release-builds/` still say `pins.txt` is tracked and the script is `scripts/install-tools.sh`. Those folders record what was decided then. This spec supersedes the tracked pin file and the later release-builds phase that would write a real tag into that tracked file. It does not rewrite those folders. Live files outside `intent/` follow D1 and D2.

**D6 — Script-local names drop the legacy host-name token.** Log prefix `install-tools:`, temp prefix `install-tools.`, function `install_refuse`. Why: those strings exist only to name this script, and the test sources the function. Docs and `AGENTS.md` still name the Mac the deployment Mac. What was rejected: leaving `legacy_install_refuse` and `install-tools:` inside the renamed script.

## 8. Open questions

None.

## 9. What was checked

Checked 2026-10-30 against `main` at `616a90432c3db4c3f347b1a4c6bcc2e443f59daa`. `git status -sb` showed `main...origin/main` with no ahead or behind. The only `v*` semver tag was `v0.1.1`.

- `pins.txt` is tracked. `.gitignore` does not match it (`git check-ignore` printed nothing). Its data lines are `backup-folder unpinned` and `drop-box-watcher unpinned`.
- `scripts/install-tools.sh` sets `PINS_FILE` default to `$ROOT/pins.txt`, where `ROOT` is the repo root. It strips from the first `#` on a line and skips a line that is then empty. It defines `legacy_install_refuse`, writes a temp file with prefix `install-tools.`, logs with prefix `install-tools:`, downloads with `gh release download`, and verifies with `gh attestation verify` and the three flags in FR5. Install destination is `${HOME}/bin`. There is no `launchctl`, `sudo`, `op`, `swift`, `swiftc`, or `build.sh` in that file.
- `tests/install-tools-test.sh` points at that script, sources `legacy_install_refuse`, and sets `PINS_FILE` to a temp file. Its last line is `install-tools-test: all checks passed`. Ran it on this commit: exit 0. The test sets `HOME` to a temp directory. Did not run the installer against a real home.
- `docs/setup.md` has 33 `Manual:` or `Script:` bullets. `docs/restore.md` has 7. Both link `scripts/install-tools.sh` and `pins.txt`. `tests/setup-docs.sh` requires the anchor `install-tools.sh` in each file. Ran `bash tests/setup-docs.sh`: exit 0.
- `.github/workflows/test.yml` jobs `macos` and `linux` each set `timeout-minutes: 5`. The `macos` job runs `bash tests/install-tools-test.sh`. The `linux` job does not. The step name is `Install the deployment Mac tools script test`.
- `tests/no-secrets.sh` scans `pins.txt` when the file exists, and its workflow regex is `scripts/install-roger-tools\.sh`, `launchctl`, and `Backups`. `tests/release-workflow.sh` fails when a workflow file contains the substring `install-tools.sh`. That substring is not inside `install-tools-test.sh`. Ran `bash tests/no-secrets.sh` and `bash tests/release-workflow.sh`: both exit 0.
- `.github/workflows/release.yml` triggers on push to `main` and runs job `publish`. `.github/workflows/codeql.yml` has no `pull_request` key. It pushes on `main` and schedules `0 6 * * *`, job name `CodeQL (Swift)`, `timeout-minutes: 30`.
- `scripts/release-version.sh` was read and not executed. With no `release:minor` or `release:major` label, it increments the patch component of the highest `vMAJOR.MINOR.PATCH` tag. It was not run here because the unlabeled path calls `gh pr view`.
- `.cursor/install.sh`, `.cursor/environment.json`, and the README sentence are recorded under D2. `README.md` does not mention `install-roger-tools` or `pins.txt`. It still says merging to `main` does not publish a binary. That sentence is stale relative to `release.yml` and is out of scope for this change.
- `AGENTS.md` mentions the installer and `pins.txt` in the install-tools bullet, the pins bullet, the `~/bin` convention, and the "do not run the installer" bullet.

This check did not write a pin file, did not run the installer against a home directory, and did not touch `~/Backups`.
