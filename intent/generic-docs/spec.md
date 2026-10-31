# spec.md — Generic docs

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-30) |
| Status | Draft 3 |
| Stage | 2 · Design |

## 1. Summary

Rewrite the long-lived docs so they instruct any Mac user. The machine name the deployment Mac is not kept as an example. A home directory in prose is `$HOME` or `~/`. The short user name in `/Users/USER` is the output of `id -un`. The existing `launchctl bootstrap gui/$(id -u)` stays, because that value is the numeric uid. `scripts/install-tools.sh` stays. LaunchAgent labels stay. Historical `intent/` folders stay.

The pull request that adds this folder does not edit those docs. The grooming pull request does. That pull request is not merged until the maintainer has reviewed the remaining host-name list in chat.

Merging this spec-and-plan pull request to `main` still publishes the next patch tag. This spec does not change publish-on-merge. Nothing is installed.

## 2. Goals and non-goals

**Goals**

- G1. `README.md`, `docs/setup.md`, `docs/restore.md`, `AGENTS.md`, and `REVIEW.md` no longer name the machine the deployment Mac, `HOST.local`, `a named Time Machine volume`, `host-bootstrap`, or `file-access-policy`.
- G2. Setup and restore stay the same checklist: 33 `Manual:` or `Script:` bullets in `docs/setup.md`, 7 in `docs/restore.md`. Open items stay open. False sentences that this pass touches are corrected.
- G3. After the grooming commit, the remaining host-name list is in that pull request. The pull request is not merged until the maintainer answers in chat.
- G4. `scripts/install-tools.sh` is not renamed. `com.nikolay.*` labels and `Nikolay Botev Code Signing` are not renamed. Both are proposed as later decisions in the plan, not done here.

**Non-goals**

- Editing any existing folder under `intent/` other than this one. This folder is the current change. Phase 0 does not rewrite this spec. It may append build notes to [plan.md](plan.md) only when it departs.
- Renaming `scripts/install-tools.sh`, `.cursor/install.sh`, the repo, or a LaunchAgent label.
- Editing `launchd/` template bodies, `scripts/`, `pins.txt.example`, `drop-box-watcher.example.toml`, `.github/workflows/release.yml`, or `scripts/release-version.sh`.
- Answering historical Q1–Q6. They stay in [roger-bootstrap](../roger-bootstrap/spec.md).
- A new required check, a timeout change, or CodeQL on pull requests.
- Setting a pin, running an installer, writing a home directory, or writing under `~/Backups`.
- Secrets, a WireGuard key, a server public IP, a port, or a 1Password item URI.

**Release phasing.** G1–G4 ship in one grooming pull request. Untagged requirements belong to that release. The pull request that adds this folder does not implement them. A later decision may rename the installer or the LaunchAgent labels. This change does not.

## 3. Principles

- P1. The reader is any Mac user. The first deployment is not the subject of the instructions.
- P2. A home path in prose is `$HOME` or `~/`. `USER` in `/Users/USER` is the short name from `id -un`. A launchd path stays `/Users/USER` because launchd does not expand `$HOME`. The load command stays `launchctl bootstrap gui/$(id -u)`, where `id -u` is the numeric uid.
- P3. This change keeps no host-name example. The maintainer can still ask for one before the grooming pull request merges.
- P4. A historical `intent/` file records what was decided then. It is not rewritten to match the groomed docs.
- P5. Publish-on-merge stays. A patch tag from merging this spec is acceptable. Agents do not push a tag by hand.
- P6. Agents and CI do not install anything.

## 4. Users and scenarios

- **A Mac user** follows `docs/setup.md` and `docs/restore.md`, and the install sections of `README.md`, without being told to use a particular computer name, hostname, or Time Machine volume name.
- **the maintainer** reads the remaining host-name list from the grooming pull request and says whether that result stands.
- **CI and agents** run `bash tests/setup-docs.sh`. They do not run `docs/setup.md`, `docs/restore.md`, or `scripts/install-tools.sh` on a live Mac.

Scenarios:

- **S1. Generic setup.** The checklist still has the same steps. Computer name, Time Machine volume, and self-hosted runner are described without the machine name.
- **S2. No remaining mention.** The grooming branch has no case-insensitive legacy host-name token in the long-lived set in section 5. The pull request says so. It stays open.
- **S3. Merge of this spec.** A merge to `main` still runs job `publish`. With no release label, that can publish the next patch tag. The commit is this folder only.

## 5. Functional requirements

The long-lived set is `README.md`, `docs/`, `AGENTS.md`, `REVIEW.md`, `launchd/`, `scripts/`, `pins.txt.example`, and `drop-box-watcher.example.toml`.

FR1. After Phase 0, case-insensitive legacy host-name token does not occur in the long-lived set. This spec keeps no example sentence that uses the machine name, `HOST.local`, `a named Time Machine volume`, `host-bootstrap`, or `file-access-policy`.

FR2. `docs/setup.md` stays at 33 bullets that start with `Manual:` or `Script:`. `docs/restore.md` stays at 7. Do not add or remove one of those bullets. Titles become `# Setup` and `# Restore`. Intros address any Mac. GitHub Actions and cloud agents do not run the steps. Ask for a heads-up before install or reinstall. Do not name a machine.

FR3. Rewrite these setup and restore sentences. Leave every other bullet's procedure in place.

- Computer name: the bullet contains `Choose a computer name`. macOS publishes that name plus `.local`. The catalog anchor is `Choose a computer name`. It is not `.local`, because `.local` is contained in today's `HOST.local`, so `grep -F '.local'` passes before this edit.
- Self-hosted runner: the step stays unfinished. Do not invent a runner token, label, or install command.
- External SSD: volume `External` stays. The Time Machine volume is one you name. The quota stays an eight-hundred-gigabyte quota. The next bullet points Time Machine at the volume you named.
- `gh auth login` is for the GitHub account that administers the Mac. Keep the public URLs `nikolaybotev/bootstrap` and `nikolaybotev/code-signing`. Keep the identity name `Nikolay Botev Code Signing`.
- Backup-folder LaunchAgent: `USER` is the output of `id -un`. The template path `/Users/USER/bin/backup-folder` stays, with the reason that launchd does not expand `$HOME`. The label pattern `com.nikolay.backup.NAME` stays.
- Drop-box watcher LaunchAgent: point at `launchd/drop-box-watcher.plist.template` with the link `../launchd/drop-box-watcher.plist.template` from `docs/setup.md`. That bullet tells the reader to replace each `/ABS/PATH/TO/HOME` placeholder in the template with their absolute home path. The token is not in `docs/setup.md` today. It is in the template, in `drop-box-watcher.example.toml`, and in `README.md`. Say that `$HOME` on a normal Mac is `/Users/$(id -un)`, and that launchd needs the absolute path. The label `com.nikolay.drop-box-watcher` stays. Delete the claim that the plist is not in the repo yet. Do not edit the template or the example toml.
- Restore, when plists are missing: the same bullet still points at the setup steps. It names the watcher template as already in the repo. Delete "once its template exists."
- Restore: files come back from the Time Machine volume named in setup, or from the home-mirrored directories under `~/Backups`.
- Hardware change: update the machine id, file-access policy, and shared memory that other tools keep for this Mac. Keep the bot-side caveat and Q5's substance (other apps stay open until you name them). Do not name a skill.

Delete the `docs/setup.md` caveat that asks whether the repo is renamed to `host-bootstrap`. Do not add a replacement caveat. The FileVault caveat stays. Remote Login stays off, including the `(Q2)` parenthetical. Energy settings stay a goal without invented clicks, including `(Q3)`. Notarization stays undecided, including `(Q6)`. The self-hosted bullet may drop `(Q4)` and stays unfinished. The hardware-change bullet keeps Q5's substance and need not keep the token `(Q5)`. Do not answer Q1–Q6.

FR4. `README.md` stops calling the repo the setup hub for the deployment Mac. It still links `docs/setup.md` and `docs/restore.md`, and it still says CI does not install them. Loading LaunchAgents is manual. The watcher watches the iCloud **Drop Box** folder on the Desktop; Apple's exclude list uses `Dropbox`, which is not this folder. The person using the Mac lists that folder and moves files. The manual-install heading does not name a deployment host or operator. Keep `$HOME` in those steps. Keep `com.nikolay.backup.NAME`, `com.nikolay.drop-box-watcher`, and the example identity `Nikolay Botev Code Signing`.

Replace the sentence that says merging to `main` does not publish a binary. State instead that a push to `main` runs job `publish`, which can push the next patch tag and publish a GitHub release, and that agents do not push a tag by hand. Keep the sentence that CI and agents do not copy the binary into `~/bin`, write the real config, or load the LaunchAgent. Keep the existing README instructions that say to replace `/ABS/PATH/TO/HOME` with the absolute home path.

FR5. `AGENTS.md` keeps the same safety rules and drops the machine name. The owner may run `scripts/install-tools.sh` and `scripts/ensure-backup-dirs.sh`. Agents do not run them against a home directory, do not run `launchctl`, do not write a live pin, and do not edit GitHub rulesets. Branch protection stays managed outside this repo with `gh`. Keep `Nikolay Botev Code Signing`, `com.nikolay.backup.NAME`, `com.nikolay.drop-box-watcher`, and `nikolaybotev/local-skills`. The release bullet stays the description of job `publish`.

A case-insensitive legacy host-name token scan does not enforce the following. Rewrite each so the maintainer is not the person doing the work. The first two contain no the legacy host-name token. The last two sit on lines that also name the deployment Mac, and they can remain after that name is deleted. The install-tools bullet is the same hole: operator-specific run phrasing can remain after `on the deployment Mac` is deleted.

- `the maintainer passes absolute home-mirrored snapshot paths` (ensure-backup-dirs bullet).
- `the maintainer fills them from 1Password at install time` (WireGuard template sentence).
- `until the maintainer sets a real pin` (pins bullet).
- operator-specific README follow phrasing the README link (the `~/bin` convention).
- operator-specific run phrasing `bash scripts/install-tools.sh` (install-tools bullet).

`Nikolay Botev Code Signing` stays. Those five phrases are not part of that identity.

FR6. In the `REVIEW.md` compliance bullet, replace only the sentence "These the deployment Mac bootstrap phases do not push a `v*` tag." The replacement says agents do not push a `v*` tag by hand, and that job `publish` in `.github/workflows/release.yml` may publish the next patch tag on a push to `main`. Leave the rest of that bullet, including the spec-and-plan match, the plan-update rule, the green `macos` job, and the sentence about `.github/scripts/protect-main-branch.sh` and `.github/workflows/protect-main.yml`. Those two files are absent on this commit; this change does not add them.

In the Important paragraph, stop treating job `publish` in `.github/workflows/release.yml` as a defect. Keep Important for any other workflow that publishes on a push to `main`, and for a secret or tunnel leak, a workflow that installs on a machine, and the snapshot-integrity cases. Style and naming stay nits.

FR7. Do not edit files in `launchd/`, `scripts/`, `pins.txt.example`, or `drop-box-watcher.example.toml`. Checked on this commit, they contain no the legacy host-name token. The four launchd files have no XML comments. `drop-box-watcher.example.toml` and `pins.txt.example` have generic `#` comments and no machine name. Script usage text does not name a machine. `tests/no-secrets.sh` requires the backup template's `Label` and `ProgramArguments` to stay `com.nikolay.backup.NAME` and `/Users/USER/bin/backup-folder`, `/ABS/SOURCE`, `/ABS/BACKUP-DIR`. `tests/drop-box-watcher-tests.swift` requires the label `com.nikolay.drop-box-watcher`.

FR8. `tests/setup-docs.sh` stays the catalog check. Update only the anchors that FR1 removes, plus the new setup anchor `drop-box-watcher.plist.template` for the link FR3 adds. Require `Choose a computer name`, `Time Machine volume`, and `drop-box-watcher.plist.template` in `docs/setup.md`. Do not use `.local` as that anchor. Do not require `file-access policy` in `docs/setup.md`; that phrase is not a setup step. Require `Time Machine volume` and `file-access policy` in `docs/restore.md`. `file-access policy` replaces the restore anchor `file-access-policy`. Keep every other current anchor, including `install-tools.sh`, `.config/backup-folder/pins.txt`, `pins.txt.example`, `com.nikolay.backup.NAME`, `External`, and `home-mirrored`. Counts stay 33 and 7. Do not add a CI job. `macos` and `linux` stay the required checks. `timeout-minutes` stay 5. CodeQL stays off pull requests.

FR9. The grooming pull request's body reports the remaining host-name list from that branch, before merge. The scan is case-insensitive legacy host-name token over the long-lived set. For each hit: the file path, a GitHub link to that line on the pull request branch (`https://github.com/nikolaybotev/backup-folder/blob/<branch>/<path>#L<line>`), the exact sentence, and one line on why it is kept. If the scan prints nothing, the body says that no host-name mentions remain in the long-lived docs. The scan does not cover GitHub handles, repo URLs, or `com.nikolay`. The body says that in one sentence. What stays is `com.nikolay.*` and `Nikolay Botev Code Signing` (D7), and the repo name plus the public bootstrap and code-signing URLs (D9, FR3). FR2, FR4, and FR5 still remove wording that names a specific person doing setup. The pull request is opened ready for review. It is not merged in Phase 0.

FR10. The spec-and-plan pull request's diff is only `intent/generic-docs/`. Phase 0 does not edit any other folder under `intent/`. It does not run an installer, does not write a home directory, and does not touch `~/Backups`.

## 6. Acceptance criteria

AC1. The spec-and-plan pull request's diff is only `intent/generic-docs/`.

AC2. On the grooming commit, `git grep for legacy host-name tokens` over the long-lived set in section 5 prints nothing. `README.md` does not contain `does not publish a binary`. `docs/setup.md` contains `drop-box-watcher.plist.template` and `Choose a computer name`, and does not contain `not in this repo yet`. `AGENTS.md` does not contain operator-specific install phrasing, operator-specific 1Password fill phrasing, operator-specific pin phrasing, operator-specific README follow phrasing, or operator-specific run phrasing. It still contains `Nikolay Botev Code Signing`.

AC3. `bash tests/setup-docs.sh` exits 0 and prints `setup-docs: all checks passed`. `docs/setup.md` has 33 `Manual:` or `Script:` bullets. `docs/restore.md` has 7.

AC4. `bash tests/no-secrets.sh` and `bash tests/release-workflow.sh` exit 0. `git diff` against the grooming commit's parent shows no change under `launchd/`, `scripts/`, `.github/workflows/release.yml`, `scripts/release-version.sh`, `.github/workflows/codeql.yml`, `.cursor/install.sh`, `pins.txt.example`, or `drop-box-watcher.example.toml`. No `timeout-minutes` line changes. `.github/workflows/test.yml` still has jobs `macos` and `linux` only.

AC5. The grooming pull request body contains the FR9 report. The branch is not merged in Phase 0.

AC6. Merging the spec-and-plan pull request still runs job `publish` on `main`. With neither `release:minor` nor `release:major` on that pull request, `scripts/release-version.sh` emits the next patch tag and `publish` can publish it. That is acceptable. This spec does not change that behavior and does not name the tag, because another merge can land first.

## 7. Design decisions

**D1 — Groom only long-lived docs.** The files are `README.md`, `docs/`, `AGENTS.md`, `REVIEW.md`, comments in `launchd/` templates, and usage text in `scripts/`. Do not edit existing `intent/` folders. Why: those folders are historical records. What was rejected: rewriting `intent/roger-bootstrap/` or `intent/local-pins/` so they stop naming the machine.

**D2 — Write for any Mac user.** The first deployment Mac is an example only and at most an example. Prefer `$HOME`, `~/`, and `$(id -un)`. No hardcoded the deployment Mac path or machine name except where this spec explicitly keeps an example. Why: the docs are the permanent instructions. What was rejected: leaving "deployment Mac" as the frame of the README and the checklists.

**D3 — Do not rename `scripts/install-tools.sh`.** `.cursor/install.sh` is the Cloud Agent environment installer. That is why `scripts/install.sh` was rejected. The plan proposes that rename as a later decision. This change does not do it. Why: [local-pins](../local-pins/spec.md) D2 already chose `scripts/install-tools.sh` for this collision. What was rejected: renaming the script in the same change as the docs.

**D4 — The grooming pull request waits.** It is not merged until the maintainer reviews the remaining host-name list in chat. The list is produced from the implementation branch before merge: file, GitHub line link, exact sentence, one line why kept. If none remain, say so. Why: he decides whether any mention stays. What was rejected: merging on green CI alone.

**D5 — Secrets stay out.** Never commit the WireGuard server public key, public IP, or port, or any secret. Templates keep placeholders. Nothing is installed. Do not run install scripts against a home directory. Do not touch `~/Backups`. Why: the templates already use placeholder tokens. What was rejected: filling `wg0.conf` or running setup on a Mac.

**D6 — No host-name example is kept.** The allowed example set is empty. FR1 is the check. Why: "at most an example" allows zero, and D4 is how the maintainer can ask for one before merge. What was rejected: a sample computer name of the deployment Mac in the setup checklist. Checked: every current hit is listed in section 9. None of them is a placeholder that has to keep the substring the legacy host-name token.

**D7 — Labels and the signing identity stay.** Do not rename `com.nikolay.backup.NAME`, `com.nikolay.drop-box-watcher`, or `Nikolay Botev Code Signing`. They do not contain the legacy host-name token. The labels are what `tests/no-secrets.sh` and `tests/drop-box-watcher-tests.swift` require, and what a loaded agent already uses. The identity is the certificate common name in `.github/workflows/release.yml`. The plan records a later decision for a generic label. This change does not pick one. Why: a label change is an install migration, not a docs pass. What was rejected: editing the plist strings in this change.

**D8 — Correct the two false sentences this pass already has to touch.** On `0b5e84d`, `README.md` says merging to `main` does not publish a binary. `.github/workflows/release.yml` runs job `publish` on every push to `main`. `docs/setup.md` says the drop-box-watcher plist is not in the repo yet. `launchd/drop-box-watcher.plist.template` is in the repo. `REVIEW.md` still lists publish-on-push-to-`main` as Important, which described the repo before publish-on-merge. Fix those while grooming the surrounding text. Do not edit `release.yml`. Why: leaving a false instruction in a paragraph this change rewrites would keep the docs wrong. What was rejected: treating the stale publish sentence as out of scope the way [local-pins](../local-pins/spec.md) did, when this change is the README pass.

**D9 — Historical questions stay historical.** Q1–Q6 stay open in `intent/roger-bootstrap/spec.md`. This change does not answer them and does not edit that file. The user-facing `host-bootstrap` caveat is removed because it is a machine-named proposal, not a setup step. The repo name in commands stays `nikolaybotev/backup-folder`. Why: D1 forbids editing that spec, and D6 forbids keeping `host-bootstrap` in the permanent doc. What was rejected: answering Q1 by renaming the repo, and leaving the proposed name in `docs/setup.md`.

**D10 — The catalog test follows the docs.** `tests/setup-docs.sh` is not a long-lived doc. Phase 0 edits its anchors so AC3 can pass. It does not add a required job. Why: the `macos` job already runs that test, and the old anchors require `HOST.local`, `a named Time Machine volume`, and `file-access-policy`. What was rejected: keeping those anchors by leaving the names in the docs, and replacing `HOST.local` with `.local`. `.local` is contained in `HOST.local`, so that anchor does not prove the computer-name edit. The setup anchor is `Choose a computer name`.

**D11 — Publish-on-merge stays for this spec.** `.github/workflows/release.yml` runs job `publish` on every push to `main`. `scripts/release-version.sh` prints `tag vMAJOR.MINOR.PATCH` with the patch incremented when the merged pull request has neither `release:minor` nor `release:major`. Merging the spec-and-plan pull request does that. This spec does not edit the workflow, the version script, or the labels. This spec does not name the next tag. The tag list is not stable: every unlabeled merge publishes another patch. Why: the kickoff says to state this plainly. What was rejected: a release label, a skipped publish, or a hand-pushed tag. The earlier claim that `0b5e84d` had only `v0.1.1` was a local `git tag -l` list, not the remote. Section 9 records the remote tags seen when this was corrected.

## 8. Open questions

None.

## 9. What was checked

Checked 2026-10-30 against `main` at `0b5e84d057bd266f47d0eccee325e634b28bd7c2` (`feat: local pins file and generic install-tools script (Phase 0) (#26)`). A local `git tag -l 'v*'` on that clone listed only `v0.1.1`. That was not the remote list. Rechecked with `git ls-remote --tags origin` on 2026-10-30, after `b2d70f4` was on `main`: `v0.1.1` at `616a904`, `v0.1.2` at `880c2b5`, `v0.1.3` at `0b5e84d`, `v0.1.4` at `b2d70f4`. `v0.1.3` points at `0b5e84d`. `v0.1.4` is the unlabeled merge of the version-minute fix. This list is not stable. This spec does not name the next tag. `scripts/release-version.sh` was read and not executed. The unlabeled path calls `gh pr view`.

Case-insensitive the legacy host-name token in the long-lived set, and nowhere else in this list:

- `README.md` lines 5, 39, 49, and 53 name the Mac or say "the maintainer or the deployment Mac". Line 60 says merging to `main` does not publish a binary. Line 27 uses `Nikolay Botev Code Signing` as an example identity. Line 49 also distinguishes **Drop Box** from `Dropbox`.
- `docs/setup.md` title and line 3 name the Mac. Line 13 sets the computer name to `the deployment Mac` (`HOST.local`). Line 23 names the the deployment Mac self-hosted runner. Lines 30–31 name `a named Time Machine volume`. Line 45 leaves a rename to `host-bootstrap` open. The file has 33 `Manual:` or `Script:` bullets. Line 37 says the drop-box-watcher plist is not in the repo yet and points at `intent/drop-box-watcher/`.
- `docs/restore.md` title and line 5 name the Mac. Line 9 names `a named Time Machine volume`. Line 12 says to install the drop-box-watcher agent "once its template exists." Line 15 names the deployment Mac's profile and `file-access-policy`. The file has 7 `Manual:` or `Script:` bullets.
- `AGENTS.md` lines 14, 17, 23, 30, 46, and 48 name the deployment Mac or the deployment Mac's home. Line 15 says the operator passes absolute home-mirrored snapshot paths and contains no legacy host-name token. Line 17 also says `until the operator sets a real pin`. Line 30 also says the operator follows the README. Line 37 says `the maintainer fills them from 1Password at install time` and contains no legacy host-name token. Line 14 also names the operator running the installer. Line 22 already describes job `publish` and names `Nikolay Botev Code Signing`. Line 36 names `com.nikolay.backup.NAME` and `/Users/USER/bin/backup-folder`.
- `REVIEW.md` line 9 says "These the deployment Mac bootstrap phases do not push a `v*` tag." The Important paragraph treats a release workflow that publishes on a push to `main` as a defect. `.github/scripts/protect-main-branch.sh` and `.github/workflows/protect-main.yml` are not in the tree.
- `launchd/backup-folder.plist.template`, `launchd/drop-box-watcher.plist.template`, `launchd/com.wireguard.wg0.plist.template`, and `launchd/wg0.conf.template` have no XML comments and no the legacy host-name token. `wg0.conf.template` still uses `[SERVER_PUBLIC_KEY]`, `[SERVER_PUBLIC_IP]`, and `[PORT]`. `drop-box-watcher.example.toml` and `pins.txt.example` have no the legacy host-name token.
- `scripts/install-tools.sh`, `scripts/ensure-backup-dirs.sh`, `scripts/build.sh`, and `scripts/release-version.sh` have no the legacy host-name token. Their usage text does not name a machine. `scripts/install-tools.sh` is the installer name on this commit. There is no `scripts/install.sh`.
- `.cursor/environment.json` sets `"install": "bash .cursor/install.sh"`. `.cursor/install.sh` installs mise when missing, apt-installs `libncurses6` when `libncurses.so.6` is absent, runs `mise install`, and pipes `nikolaybotev/local-skills`'s `install.sh`.
- `tests/setup-docs.sh` requires the anchors `HOST.local`, `a named Time Machine volume` (setup and restore), `file-access-policy`, and `com.nikolay.backup.NAME`, and the counts 33 and 7.
- `tests/no-secrets.sh` requires the backup plist label and program arguments in FR7. `tests/drop-box-watcher-tests.swift` requires `com.nikolay.drop-box-watcher`.
- `.github/workflows/test.yml` jobs `macos` and `linux` each set `timeout-minutes: 5`. The `macos` job runs `bash tests/setup-docs.sh`. The `linux` job does not. `.github/workflows/release.yml` triggers on push to `main` and runs job `publish`. `.github/workflows/codeql.yml` has no `pull_request` key.
- `intent/local-pins/` is on this commit. It was not edited. `docs/setup.md` and `docs/restore.md` already name `scripts/install-tools.sh` and `~/.config/backup-folder/pins.txt`.

This check did not run an installer, did not write a pin file, and did not touch `~/Backups`.
