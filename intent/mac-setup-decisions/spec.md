# spec.md — Mac setup decisions

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-31) |
| Status | Draft 2 |
| Stage | 2 · Design |

## 1. Summary

Close the remaining setup and restore questions in the live docs, and lock the release verify that is already there.

`.github/workflows/release.yml` already runs `codesign --verify --strict` on both `backup-folder` and `drop-box-watcher` in job `publish`, after `bash scripts/build.sh` and before the tag push. This change does not add a second copy. Phase 0 tightens `tests/release-workflow.sh` so both commands cannot disappear. The pull-request `macos` job keeps its ad-hoc `Signature=adhoc` check. There is no notarization and no `spctl`.

`docs/setup.md` states that Remote Login (SSH) is on, states the four energy settings, does not add a self-hosted runner, and states that Apple Developer ID notarization is out of scope. It instructs. It does not enable SSH and it does not apply energy settings. `docs/restore.md` states the closed install set. The repo name stays `backup-folder`.

The pull request that adds this folder does not edit those docs or the workflow. Phase 0 does. Nothing is installed.

Merging this spec to `main` still runs job `publish`. This spec does not change publish-on-merge.

## 2. Goals and non-goals

**Goals**

- G1. Both release binaries stay covered by `codesign --verify --strict` in job `publish`, and `tests/release-workflow.sh` fails if either command disappears.
- G2. `docs/setup.md` states the closed Remote Login, energy, self-hosted, and notarization decisions as instructions.
- G3. `docs/restore.md` states the closed restore install set. No Xcode. No other LaunchAgent.
- G4. The repo name stays `backup-folder`. The setup and restore docs stay generic for any Mac.

**Non-goals**

- A second `codesign --verify --strict` block in `.github/workflows/release.yml`. The commands are already there.
- Editing `.github/workflows/test.yml`. The `Signature=adhoc` checks stay.
- `spctl`, `notarytool`, stapling, or Apple Developer ID notarization. There is no plan to notarize.
- Renaming the repo. The rejected name `roger-bootstrap` is not written into `docs/setup.md` or `docs/restore.md`.
- Adding a self-hosted runner token, label, or install command.
- Adding a LaunchAgent, a plist, or an Xcode install.
- Removing setup steps that a new Mac already has and that a restore does not add: `pinentry`, iStat Menus, and MacVim stay in `docs/setup.md` only.
- Running an installer, setting a pin, pushing a tag by hand, or editing rulesets. Install timing stays on hold.
- Editing `AGENTS.md`, product sources, `launchd/`, `scripts/`, `.github/workflows/release.yml`, `.github/workflows/test.yml`, or any older folder under `intent/`.
- A new required check, a timeout change, or CodeQL on pull requests.

**Release phasing.** G1–G4 ship in one build pull request, Phase 0, after this spec pull request is reviewed and its commits are on `main`. Untagged requirements belong to that release. The pull request that adds this folder does not implement them.

## 3. Principles

- P1. The setup doc is instructions for setting up a Mac. Agents who build this repo are not operators of the machine and do not apply the settings.
- P2. The reader is any Mac user. The docs do not name a hostname or a machine.
- P3. A historical `intent/` file records what was open then. It is not rewritten so that it matches these closed decisions.
- P4. Publish-on-merge stays. Agents do not push a tag by hand. This spec does not name the next tag.
- P5. Agents and CI do not install anything.
- P6. Where this spec and the plan disagree, this spec wins.

## 4. Users and scenarios

- **A person with a Mac** reads `docs/setup.md` and `docs/restore.md` and applies the settings. This spec does not do that.
- **CI and agents** run `bash tests/release-workflow.sh` and `bash tests/setup-docs.sh`. They do not run the docs, do not enable SSH, and do not change energy settings.

Scenarios:

- **S1. Release verify.** Job `publish` signs both binaries in `scripts/build.sh`, then runs `codesign --verify --strict` on each, then later pushes the tag. The static test requires both command lines.
- **S2. Setup instructions.** The checklist says Remote Login (SSH) is on and lists the four energy settings. It does not run those changes.
- **S3. Restore install set.** The restore doc names the closed set and does not add Xcode or another LaunchAgent.
- **S4. Spec merge.** A merge to `main` still runs job `publish`. With no release label, that can publish the next patch tag. The commit is this folder only.

## 5. Functional requirements

FR1. Phase 0 does not edit `.github/workflows/release.yml`. On this commit the publish job already has both lines, after `bash scripts/build.sh` and before `git push origin "refs/tags/${tag}"`:

```
codesign --verify --strict ./backup-folder
codesign --verify --strict "$watcher_bin"
```

`scripts/build.sh` signs each binary before those lines run: `codesign --sign "$SIGN_IDENTITY" --force --options runtime` when `SIGN_IDENTITY` is set, and `codesign --sign - --force` when it is unset. The publish job sets `SIGN_IDENTITY` before the single `bash scripts/build.sh`. Do not add another verify. Do not add `spctl`.

FR2. Phase 0 edits `tests/release-workflow.sh` only to lock FR1. Keep every current `require_in_release` call and every current ban, including the ban that fails when `release.yml` contains `spctl`. Add both exact strings:

```
codesign --verify --strict ./backup-folder
codesign --verify --strict "$watcher_bin"
```

Fail unless `codesign --verify --strict` occurs exactly twice in `.github/workflows/release.yml`. Fail unless both of those lines are after the line `bash scripts/build.sh` and before the line `git push origin "refs/tags/`. Do not add a second test file.

FR3. `.github/workflows/test.yml` stays. The `macos` job still has both lines:

```
codesign -dv ./backup-folder 2>&1 | grep -q 'Signature=adhoc'
codesign -dv "$watcher_bin" 2>&1 | grep -q 'Signature=adhoc'
```

Phase 0 does not replace them with `codesign --verify --strict`.

FR4. `docs/setup.md` stays at 33 `Manual:` or `Script:` bullets. `docs/restore.md` stays at 7. Do not add or remove one of those bullets. Do not edit any bullet other than the four setup bullets and the one restore bullet named below.

The setup intro paragraph becomes:

```
Run this checklist on your Mac. GitHub Actions and cloud agents do not run these steps. Give a heads-up before anything in this doc is installed or changed on the Mac. Agents who build this repo are not operators of the machine and do not apply these settings.
```

Replace only these setup bullets.

- Remote Login becomes: `Manual: Remote Login (SSH) is on. This doc only instructs that setting. It does not enable SSH.`
- Energy becomes: `Manual: Energy settings, as instructions only: Low Power Mode off; "Prevent automatic sleeping when the display is off" on; "Wake for network access" on; "Start up when power is connected" set to "After power failure". This doc does not apply those settings.`
- Self-hosted becomes: `Manual: This doc does not add a self-hosted runner, a runner token, a runner label, or a runner install command. Installing Cursor and signing in is the app-setup instruction in the step above.`
- The privacy bullet becomes: `Manual: Accept the macOS Desktop and Documents privacy prompts for each new binary. Repeat after every new binary. Apple Developer ID notarization is out of scope. There is no plan to notarize.`

Leave `Manual: Install Cursor and sign in.` unchanged. Leave the `pinentry`, iStat Menus, and MacVim steps unchanged. Leave the FileVault caveat unchanged. Leave the install-tools bullet unchanged.

FR5. In `docs/restore.md`, keep the two intro paragraphs and add this paragraph after them. It is not a bullet.

```
A restore installs nothing beyond the bootstrap repo plus the Grok Bot app, the Cursor app, the 1Password app and the 1Password CLI (`op`), Homebrew with `gh`, `git`, and GnuPG via the separate dev bootstrap, and `wireguard-tools` and `wireguard-go` from Homebrew, plus the existing LaunchAgent repeat and the `scripts/install-tools.sh` re-run. The LaunchAgent repeat is the WireGuard daemon and the backup-folder and drop-box-watcher agents when their plists are missing. The re-run is for a pinned tool whose `~/bin` binary is missing or should move to the pin. It does not install Xcode. It does not add any other LaunchAgent. Agents who build this repo are not operators of the machine and do not install these items.
```

That paragraph is the closed install set. The existing restore bullets stay, including that LaunchAgent repeat and that re-run. They are not an added LaunchAgent. Delete only the sentence `Other apps or tools beyond this hub stay open until you name them.` from the hardware-change bullet. Leave the rest of that bullet.

FR6. `docs/setup.md` and `docs/restore.md` do not contain `roger-bootstrap`, `(Q2)`, `(Q3)`, `(Q4)`, `(Q5)`, `(Q6)`, `stays open`, `left unfinished`, `notarization is decided`, or `until you name them`. They do not contain a hostname or a machine name. Checked on this commit, neither file leaves a rename open, so Phase 0 does not add a rename sentence and does not rename the repo. The name in commands stays `nikolaybotev/backup-folder`.

FR7. `tests/setup-docs.sh` keeps the counts 33 and 7 and keeps every current anchor. Add these setup anchors: `Remote Login (SSH) is on`, `does not enable SSH`, `Low Power Mode`, `Prevent automatic sleeping when the display is off`, `Wake for network access`, `After power failure`, `does not apply those settings`, `does not add a self-hosted runner`, `Apple Developer ID notarization is out of scope`, `There is no plan to notarize`, `not operators of the machine`. Add these restore anchors: `wireguard-go`, `does not install Xcode`, `GnuPG`, `Grok Bot`, `1Password CLI`, `not operators of the machine`. Fail if either doc contains a forbidden string from FR6. Do not add a CI job. `macos` and `linux` stay the required checks.

FR8. The spec pull request's diff is only `intent/mac-setup-decisions/`. Phase 0 does not run an installer, does not write a pin file, does not push a tag, does not edit a ruleset, does not run `launchctl`, and does not write under `~/Backups`. Install timing stays on hold: do not add a schedule, and do not change the heads-up sentences except for the setup sentence FR4 adds.

FR9. Apple Developer ID notarization is out of scope. The docs use the FR4 privacy bullet and no other notarization sentence. In that privacy bullet, do not leave the decision open, do not use the word "until", and do not point at a later phase for notarization. The "until" ban is that sentence only. FR4 leaves the install-tools bullet and the FileVault caveat unchanged, so `Until then the script skips unpinned tools.` and `until the disk is unlocked.` stay.

## 6. Acceptance criteria

AC1. The spec pull request's diff is only `intent/mac-setup-decisions/`.

AC2. On the Phase 0 commit, `.github/workflows/release.yml` is unchanged from its parent. `bash tests/release-workflow.sh` exits 0. The test requires both exact verify lines in FR2, requires that the substring `codesign --verify --strict` occur exactly twice, requires both lines after `bash scripts/build.sh` and before `git push origin "refs/tags/`, and still fails if the workflow contains `spctl`.

AC3. `.github/workflows/test.yml` is unchanged from the Phase 0 commit's parent. It still contains `Signature=adhoc` twice.

AC4. `bash tests/setup-docs.sh` exits 0 and prints `setup-docs: all checks passed`. `docs/setup.md` has 33 `Manual:` or `Script:` bullets. `docs/restore.md` has 7. The FR4 and FR5 sentences are present. The FR6 strings are absent.

AC5. `bash tests/no-secrets.sh` exits 0. `git diff` against the Phase 0 commit's parent shows no change under `launchd/`, `scripts/`, `.github/workflows/`, `AGENTS.md`, `README.md`, or any `intent/` path other than an appended build note on `intent/mac-setup-decisions/plan.md`.

AC6. Phase 0 does not run an installer, does not set a pin, does not push a tag, and does not edit a ruleset. The branch is not merged in Phase 0.

AC7. Merging the spec pull request still runs job `publish` on `main`. With neither `release:minor` nor `release:major` on that pull request, `scripts/release-version.sh` emits the next patch tag and `publish` can publish it. This spec does not change that behavior and does not name the tag, because another merge can land first.

## 7. Design decisions

**D1 — Lock the verify that is already there.** Job `publish` already runs `codesign --verify --strict` on `./backup-folder` and on `"$watcher_bin"`. Do not invent a second copy. Phase 0 locks both lines in `tests/release-workflow.sh`. The existing test only requires the substring once, so deleting one of the two lines would still pass. The count of two and the two exact lines close that gap. `spctl` stays banned. Why: the command is present on both binaries, after signing and before the tag push. What was rejected: adding the same two lines again in `release.yml`, and using `spctl`. Checked 2026-10-31 on `081dfdde8382b6e1d1df5f82e2958b715be97efb`. Quoted in section 9.

**D2 — The repo name stays `backup-folder`.** It is a public tools repo. Do not rename it to `roger-bootstrap`. Setup docs stay generic for any Mac: no hostnames, no machine name, as [generic-docs](../generic-docs/spec.md) already required. Checked on this commit: `docs/setup.md` and `docs/restore.md` do not contain `roger-bootstrap` and do not leave a rename open. Phase 0 does not add a rename sentence. Why: the generic-docs pass already removed the old caveat. What was rejected: renaming the repo, and writing the rejected name back into the docs.

**D3 — Remote Login (SSH) is on.** The setup bullet says so. The doc only instructs. It does not enable SSH. Why: the old bullet left the choice open. What was rejected: a command that turns SSH on, and leaving `(Q2)` in the doc.

**D4 — Energy settings are four instructions.** Low Power Mode off. "Prevent automatic sleeping when the display is off" on. "Wake for network access" on. "Start up when power is connected" set to "After power failure". The doc says it does not apply those settings. Why: the old bullet stated a goal and left the clicks open. What was rejected: steps an agent runs, and leaving `(Q3)` in the doc.

**D5 — Agents are not operators.** The setup intro says so. Do not add self-hosted-runner operations. The unfinished self-hosted bullet is closed by saying the doc does not add a runner, a token, a label, or an install command. `Manual: Install Cursor and sign in.` stays the app-setup instruction. Why: the setup doc is instructions for a Mac, nothing more. What was rejected: inventing a runner token, label, or install command, and leaving the step unfinished.

**D6 — The restore install set is closed.** The restore paragraph names the app set and also names the existing LaunchAgent repeat and the `scripts/install-tools.sh` re-run. The repeat is the WireGuard daemon and the backup-folder and drop-box-watcher agents when their plists are missing. The re-run is for a pinned tool whose `~/bin` binary is missing or should move to the pin. No Xcode. No other LaunchAgent is added. `pinentry`, iStat Menus, and MacVim stay on the setup checklist and are not added to restore. Why: the old hardware bullet left other apps open, and the closed set has to name the reinstalls that the restore doc already has. What was rejected: an Xcode step, a new LaunchAgent, and `until you name them`.

**D7 — Notarization is out of scope.** There is no plan to notarize. The privacy bullet states that and does not point at a later phase. The word "until" is banned only in that privacy bullet. The install-tools bullet keeps `Until then the script skips unpinned tools.` The FileVault caveat keeps `until the disk is unlocked.` The release path stays `codesign --verify --strict`, not `spctl`. Why: an open "until notarization is decided" sentence would leave the question open, and a docs-wide "until" ban would delete sentences FR4 keeps. What was rejected: notarization, a later notarization phase, and `spctl`.

**D8 — Install timing stays on hold.** Phase 0 does not run an installer, does not set a pin, does not push a tag by hand, and does not edit rulesets. The heads-up sentences stay. Why: when a machine is installed is not decided here. What was rejected: a schedule, a pin commit, and a hand-pushed tag.

**D9 — Publish-on-merge stays.** `.github/workflows/release.yml` runs job `publish` on every push to `main`. `scripts/release-version.sh` prints `tag vMAJOR.MINOR.PATCH` with the patch incremented when the merged pull request has neither `release:minor` nor `release:major`. Merging the spec pull request does that. This spec does not edit the workflow, the version script, or the labels. This spec does not name the next tag. Why: the workflow is already on `main`. What was rejected: a release label, a skipped publish, or a hand-pushed tag.

**D10 — Older intent folders stay historical.** [roger-bootstrap](../roger-bootstrap/spec.md), [generic-docs](../generic-docs/spec.md), and [release-builds](../release-builds/spec.md) are not edited. Live docs follow this spec. Why: those folders record what was decided then. What was rejected: rewriting them so their old open questions disappear.

## 8. Open questions

None.

## 9. What was checked

Checked 2026-10-31 against `main` at `081dfdde8382b6e1d1df5f82e2958b715be97efb`. `git status -sb` showed `main...origin/main`. `git rev-parse HEAD` and `git rev-parse origin/main` were that same commit. `scripts/release-version.sh` was read and not executed. The unlabeled path calls `gh pr view`.

Codesign lines on that commit:

`.github/workflows/release.yml`

```
124:          security import "$P12" -k "$KEYCHAIN" -P "$MACOS_SIGNING_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
125:          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN"
130:          bash scripts/build.sh
138:          codesign --verify --strict ./backup-folder
139:          codesign --verify --strict "$watcher_bin"
220:              git push origin "refs/tags/${tag}"
```

The file has no `spctl`. Those two `--verify --strict` lines are the only ones. `scripts/build.sh` signs inside that `bash scripts/build.sh` step:

```
54:    codesign --sign "$SIGN_IDENTITY" --force --options runtime "$bin"
56:    codesign --sign - --force "$bin"
```

`.github/workflows/test.yml`

```
28:          codesign -dv ./backup-folder 2>&1 | grep -q 'Signature=adhoc'
34:          codesign -dv "$watcher_bin" 2>&1 | grep -q 'Signature=adhoc'
```

`tests/release-workflow.sh`

```
62:require_in_release 'codesign --verify --strict' "codesign verify strict"
107:if grep -q 'spctl' "$RELEASE_YML"; then
108:  fail "release.yml must not use spctl"
```

Line 62 requires the substring once. One remaining verify line would still satisfy it. `AGENTS.md` line 7 says an unset `SIGN_IDENTITY` ad-hoc signs with `codesign -s -`. The `macos` job and the CodeQL manual build leave `SIGN_IDENTITY` unset.

Docs on that commit:

- `docs/setup.md` line 11: `Manual: Remote Login (SSH) is not turned on by this doc. Whether to enable it stays open (Q2).`
- `docs/setup.md` line 12: `Manual: Energy: the machine should avoid sleep and start after power failure. The exact System Settings clicks stay open (Q3); this doc states the goal only.`
- `docs/setup.md` line 22: `Manual: Install Cursor and sign in.`
- `docs/setup.md` line 23: `Manual: A **self-hosted** runner is named as a step and left unfinished. This doc does not invent a runner token, label, or install command.`
- `docs/setup.md` line 34: `Manual: Accept the macOS Desktop and Documents privacy prompts for each new binary. Repeat after every new binary. Unidentified-developer prompts are part of this step until Apple notarization is decided (Q6).`
- `docs/restore.md` line 15 ends with `Other apps or tools beyond this hub stay open until you name them.`
- Neither doc contains `roger-bootstrap`. Neither leaves a rename sentence open. `docs/setup.md` has 33 `Manual:` or `Script:` bullets. `docs/restore.md` has 7.
- `tests/setup-docs.sh` requires those counts and the anchors `Remote Login` and `self-hosted`. It does not yet require the closed sentences.

Ran `bash tests/release-workflow.sh` and `bash tests/setup-docs.sh` on this commit. Both exited 0.

`.github/workflows/release.yml` triggers on push to `main` and runs job `publish`. `.github/workflows/test.yml` jobs `macos` and `linux` each set `timeout-minutes: 5`. This check did not run an installer, did not write a pin file, did not push a tag, and did not edit a ruleset.
