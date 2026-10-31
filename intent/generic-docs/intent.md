# intent.md — Generic docs

| | |
|---|---|
| Author | Maintainer |
| Captured | 2026-10-30 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [local-pins](../local-pins/intent.md) |

## Problem

The README, the setup and restore checklists, and the agent guides still describe this repo as the setup for one deployment Mac. The first deployment Mac is an example only, not the audience.

## Proposed outcome

Long-lived docs read as instructions for any Mac user. Placeholders stand in for a home directory and a user name. A later reader can see whether the machine name remains, and the grooming pull request waits for that review before it merges. Nothing is installed.

## Affected users and systems

- **Users:** any person setting up these tools on a Mac. The maintainer, who reviews whether the machine name remains. CI and agents, who must not install anything.
- **Systems:** the public repo `nikolaybotev/backup-folder`. The long-lived docs and the templates and scripts those docs describe. Not the historical `intent/` folders.

## Constraints and principles

- The first deployment Mac is an example only. The docs are not written for that machine.
- Secrets, the WireGuard server public key, and the server public IP stay out of the repo.
- Nothing is installed. `scripts/install-tools.sh` is not renamed in this change.
- Existing `intent/` folders stay historical records.
- The grooming pull request is not merged until the maintainer has reviewed the remaining host-name list in chat.

## Open questions (carried into spec.md)

None. The decisions below close the scope, the script name, and the merge gate. The spec records whether any the deployment Mac example is kept.

## Original prompt (verbatim)

```
Queue a small docs-grooming pass on backup-folder, to start after the local-pins-file / install-tools.sh change merges. Goal: the README, docs/setup.md, templates' comments and other user-facing docs describe the tools generically for any Mac user, written for any Mac user. The deployment Mac is just the first deployment; at most mention the deployment as an example. Use placeholders or $HOME/$(id -un) rather than hardcoded the deployment Mac paths/names where practical. Include revisiting naming that bakes in one machine (e.g. if the installer name should change later once .cursor/install.sh ambiguity is reconsidered, propose it rather than doing it). Go through the normal SDLC (PR, agent review). Keep secrets, WireGuard server public key and public IP out of the repo as before. Nothing gets installed on a live home.
```

## Scope clarification (verbatim)

```
Scope clarification: intent/, spec and plan files are out of scope — they stay untouched as historical records. Groom only the long-lived permanent docs (README, docs/, AGENTS.md/REVIEW.md-style guides, template comments, script usage text).
```

## Addition (verbatim)

```
Addition: after the grooming PR is ready (before merge), report back a list of every remaining mention of the deployment Mac (the machine name, the Bonjour name, host-specific paths or wording) in the long-lived docs. For each: file path with a GitHub link to the line on the PR branch, the exact sentence quoted, and one line on why it's kept. If none remain, say so. The maintainer will review that list in chat and decide whether a host name should be mentioned at all or the docs stay fully generic, so don't merge the grooming PR until that review completes.
```

## Kickoff decisions (verbatim)

```
Decisions already made, record them and do not re-litigate:

- D1. Groom only long-lived docs: README, docs/, AGENTS.md, REVIEW.md, comments in launchd templates, and usage text in scripts. Do not edit existing intent folders.
- D2. Write for any Mac user. The first deployment Mac is an example only and at most an example. Prefer placeholders or $HOME and $(id -un). No hardcoded host paths or machine names except where the spec explicitly keeps an example.
- D3. Do not rename scripts/install-tools.sh in this change. .cursor/install.sh is the Cloud Agent environment installer, which is why scripts/install.sh was rejected. The plan may propose that rename as a later decision. It does not do it.
- D4. The implementation pull request is not merged until the maintainer reviews the remaining host-name list in chat. The spec says the list is produced from the implementation branch before merge: file, GitHub line link, exact sentence, one line why kept. If none remain, say so.
- D5. Never commit the WireGuard server public key, public IP, or port, or any secret. Templates keep placeholders. Nothing is installed. Do not run install scripts against a home directory. Do not touch ~/Backups.
```
