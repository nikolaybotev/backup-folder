# intent.md — Mac setup decisions

| | |
|---|---|
| Author | — |
| Captured | 2026-10-31 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [roger-bootstrap](../roger-bootstrap/intent.md), [generic-docs](../generic-docs/intent.md), [release-builds](../release-builds/intent.md) |

## Problem

The setup and restore docs still leave earlier questions open: Remote Login, energy settings, an unfinished self-hosted runner step, notarization, and what a restore may install. The release job already verifies both signed binaries, and that check has to stay. The repo name stays `backup-folder`.

## Proposed outcome

The live docs state those decisions as instructions for any Mac. The release verify stays where it is, and the existing release-workflow test locks both binaries so the check cannot disappear. Nothing is installed. Agents do not apply the settings.

## Affected users and systems

- **Users:** a person following the setup and restore docs on a Mac. CI and agents, who must not apply those settings or install anything.
- **Systems:** this repo. `docs/setup.md`, `docs/restore.md`, and `tests/release-workflow.sh`. Not the historical `intent/` folders.

## Constraints and principles

- The repo name stays `backup-folder`. Setup docs stay generic for any Mac: no hostnames, no machine name.
- The setup doc is instructions. Agents who build this repo are not operators of the machine and do not apply the settings.
- Nothing is installed. No pin is set. No tag is pushed by hand. Rulesets are not edited.
- Install timing stays on hold.
- Historical `intent/` folders stay untouched.
- WireGuard templates stay placeholders.
- Apple Developer ID notarization is out of scope. There is no plan to notarize.

## Open questions (carried into spec.md)

None. The decisions below are closed.

## Original prompt

```
Repo: https://github.com/nikolaybotev/backup-folder. Branch from current origin/main. Open one spec pull request only. Do not change product code, workflows, or docs outside `intent/mac-setup-decisions/`. Do not merge. Do not install anything, do not apply machine settings, do not touch pins, secrets, or rulesets.

Follow the repo's existing intent shape (see `intent/generic-docs/` and `intent/local-pins/`): write `intent/mac-setup-decisions/intent.md`, `spec.md`, and `plan.md` together. Link the folder to `intent/roger-bootstrap/`, `intent/generic-docs/`, and `intent/release-builds/`. Do not edit those older folders. Historical intent files stay untouched.

Check the live files before the spec hardens, and record what you checked: `.github/workflows/release.yml`, `.github/workflows/test.yml`, `tests/release-workflow.sh`, `docs/setup.md`, `docs/restore.md`, `AGENTS.md`. Quote the current codesign lines.

Decisions, all closed (D-numbers, do not leave them as open questions):

1. Add `codesign --verify --strict` on the release binaries in CI. Not `spctl`. If `release.yml` already runs that command on both signed binaries, do not invent a second copy; lock it with the existing release-workflow static test so it cannot disappear. If it is missing, the plan's build phase adds it where the release binaries are signed (the publish job), on both `backup-folder` and `drop-box-watcher`, after signing and before the tag push. The PR `macos` job's ad-hoc `Signature=adhoc` check stays. No notarization.

2. Do not rename the repo. The name stays `backup-folder`. It is a public tools repo. Setup docs stay generic for any Mac: no hostnames, no machine name, per the already-merged generic-docs pass. If `docs/setup.md` or `docs/restore.md` still leave the rename open, the build phase closes that sentence.

3. Remote Login (SSH) is on. The setup doc says so. It does not enable SSH; it only instructs.

4. Energy settings, written as instructions, not as steps an agent runs: Low Power Mode off; "Prevent automatic sleeping when the display is off" on; "Wake for network access" on; "Start up when power is connected" set to "After power failure".

5. The setup doc is instructions for setting up such a Mac, nothing more. Agents who build this repo are not operators of the machine and do not apply these settings. Do not add self-hosted-runner operations. Installing Cursor and signing in can stay as an app-setup instruction.

6. A restore installs nothing beyond the bootstrap repo plus: Grok Bot app, Cursor app, 1Password app and CLI (`op`), Homebrew with gh, git, and GnuPG via the separate dev bootstrap, and wireguard-tools and wireguard-go from Homebrew. No Xcode. No other LaunchAgents to add.

7. Apple Developer ID notarization is out of scope, with no plans. Docs must not leave it open or imply a later phase.

Install timing stays on hold. The plan's build phase does not run an installer, does not set a pin, does not push a tag by hand, and does not edit rulesets. One build phase, one later pull request, after this spec pull request is reviewed. Required checks are `macos` and `linux`. Conventional commit. PR body says this is the spec only.

WireGuard templates stay placeholders.
```

## Closed decisions

- D1. `codesign --verify --strict` on both release binaries. Not `spctl`. Do not add a second copy if the publish job already runs it. Lock it with `tests/release-workflow.sh`. The pull-request `macos` job keeps `Signature=adhoc`. No notarization.
- D2. The repo name stays `backup-folder`. Setup docs stay generic for any Mac. No hostnames. No machine name.
- D3. Remote Login (SSH) is on. The setup doc instructs. It does not enable SSH.
- D4. Energy settings are instructions only: Low Power Mode off; "Prevent automatic sleeping when the display is off" on; "Wake for network access" on; "Start up when power is connected" set to "After power failure".
- D5. The setup doc is instructions. Agents are not operators and do not apply the settings. Do not add self-hosted-runner operations. Installing Cursor and signing in stays an app-setup instruction.
- D6. A restore installs nothing beyond the bootstrap repo plus the Grok Bot app, the Cursor app, the 1Password app and CLI (`op`), Homebrew with `gh`, `git`, and GnuPG via the separate dev bootstrap, and `wireguard-tools` and `wireguard-go` from Homebrew, plus the existing LaunchAgent repeat and the `scripts/install-tools.sh` re-run. No Xcode. No other LaunchAgents to add.
- D7. Apple Developer ID notarization is out of scope. There is no plan to notarize. Docs must not leave it open or imply a later phase.
- D8. Install timing stays on hold. The build phase does not run an installer, does not set a pin, does not push a tag by hand, and does not edit rulesets.
