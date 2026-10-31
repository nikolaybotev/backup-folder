# intent.md — Signing identity

| | |
|---|---|
| Author | Maintainer |
| Captured | 2026-10-31 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [release-builds](../release-builds/intent.md), [generic-docs](../generic-docs/intent.md) |

## Problem

The release job names the person on the code-signing certificate. LaunchAgent labels still use the `com.nikolay.` prefix. Prose, tests, and workflows also paste this repo's owner and URL, and human-facing docs sometimes spell out what a reader already knows.

## Proposed outcome

The signing identity is configuration. Job `publish` always derives it from the single certificate imported from `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD` and does not honor a pre-set `SIGN_IDENTITY`. `SIGN_IDENTITY` is only the local-build switch in `scripts/build.sh`. LaunchAgent labels use the `com.nikolaybotev.` prefix. Prose says "this repo". Distribution entry points may name the canonical repository. Reviewers can check the three writing rules.

## Affected users and systems

- **Users:** anyone who builds, releases, or installs the tools, including a fork.
- **Systems:** this repo. Job `publish` in `.github/workflows/release.yml`, `scripts/build.sh`, `scripts/install-tools.sh`, the LaunchAgent templates, and the docs and tests that name them.

## Constraints and principles

- One pull request. Spec, plan, and the fix together. Do not merge.
- Do not install anything. Do not touch a machine, LaunchAgents already loaded on a machine, `~/Backups`, rulesets, or git history. Do not delete branches.
- Do not write the certificate subject. Call it the signing identity.
- The publisher prefix `com.nikolaybotev.` is public text.
- Required checks stay `macos` and `linux`.

## Open questions (carried into spec.md)

None. The decisions in the prompt are closed. Later corrections in this file win where they disagree with the first prompt.

## Original prompt (verbatim)

```
Repo: https://github.com/nikolaybotev/backup-folder. Branch from current origin/main (v0.1.13, commit fef266d0236cc2d282f9af66baf63edf98ba1da0). Open one pull request. Do not merge. Do not install anything. Do not touch a Mac, LaunchAgents already loaded on a machine, ~/Backups, rulesets, or history. Do not delete branches.

This pull request is the whole change: spec, plan, and the fix together, one phase. Write `intent/signing-identity/` with intent.md, spec.md, and plan.md, then implement the plan in the same branch. Where plan and spec disagree, the spec wins and you record the departure in plan.md.

Decisions, all closed:

1. Signing identity. Remove every place that names who the code-signing certificate is issued to, including the release workflow, scripts/build.sh, tests/release-workflow.sh, README, AGENTS.md, docs/setup.md, and intents. The identity is configuration. Job publish always derives it from the single certificate imported from MACOS_SIGNING_P12_BASE64 and MACOS_SIGNING_P12_PASSWORD and does not honor a pre-set SIGN_IDENTITY. Refer to it only as "the signing identity". Do not write the current subject name anywhere, including examples and tests. Releases must still be signed with that same identity. A missing identity still fails the release. SIGN_IDENTITY remains only scripts/build.sh's local-build switch: set means sign with that login-keychain identity, unset means ad-hoc. Tests check that behavior against the configured value, not against a literal subject name.

2. LaunchAgent labels. Rename the prefix `com.nikolay.` to `com.nikolaybotev.` for backup.NAME and drop-box-watcher, in the plist templates, tests, and docs. This publisher name is fine in public. Find the open decision in intent/generic-docs/plan.md and close it accordingly. Do not rename unrelated historical intent folders.

3. Three writing rules, applied across README, docs, intents, AGENTS.md, REVIEW.md, scripts, tests, and workflows. Sweep for violations and fix them in this same pull request.
   - No self-references. Never hardcode this repo's owner, name, or URL. In prose say "this repo". In scripts and workflows derive it (git remote, GITHUB_REPOSITORY, or github.repository) so a fork works unchanged. References to other repos are fine.
   - No values of variable config. Do not copy the current value of a setting into docs, tests, or workflows. Name the setting (env var, secret, or config key). Tests assert behavior against the configured value, not a literal.
   - Do not state the obvious. Drop notes a competent reader already knows, such as "(healthy: exit 0)".
   Add these three as review items in REVIEW.md.

Do not mention installed agents, a Mac mini, or a held install in repo text. Conventional commit. Required checks are macos and linux. Reply with the pull request URL, the files changed, and how the release job now obtains the signing identity without a hardcoded subject.
```

## Correction (verbatim)

```
Rule 3 ("don't state the obvious") applies only to human-facing docs: README and user/setup docs. Agent-facing files keep explicit expectations such as "(healthy: exit 0)" because they help smaller models. That includes AGENTS.md, REVIEW.md, skills, and intents written for agents.

Do not strip those from agent-facing files. If you already removed any, restore them. Word the REVIEW.md review item so it matches this limit. Rules 1 and 2 are unchanged.

Still one pull request, still do not merge, still do not install anything or touch a machine.
```

## Rule 1 clarification (verbatim)

```
Rule 1 clarification. Match the pull request and the REVIEW.md item to this. Rules 2 and 3 stay as last corrected (rule 3 is human-facing docs only).

Prose about the repo itself says "this repo". Distribution entry points may hardcode the canonical location: the install command for a release (for example `gh release download` from the canonical repo), a curl|sh one-liner, an installer's default source, or a dependency on another repo such as `.cursor/install.sh` pulling local-skills. Add an optional override for forks where it is cheap. Never derive a repo identity from `GITHUB_REPOSITORY` in code that other repos' CI may run. Inside this repo's own workflows, `${{ github.repository }}` is fine. Do not make install instructions depend on an env var the reader must set.

Still one pull request. Do not merge. Do not install anything or touch a machine.
```

## Cloud install boundary (verbatim)

```
Boundary. Match the pull request and REVIEW.md item to this.

`.cursor/install.sh` is only for setting up Cursor Cloud Agent environments, never GitHub Actions or anything else. Leave it hardcoding nikolaybotev/local-skills with no override and no env var.

Any fork override belongs only on backup-folder's own distribution entry points (its installer and release install commands), and only where it is cheap.

Prose about the repo still says "this repo". Do not derive a repo identity from GITHUB_REPOSITORY in code that other repos' CI may run. Inside this repo's own workflows, `${{ github.repository }}` is fine. Do not make install instructions depend on an env var the reader must set.

Still one pull request. Do not merge. Do not install anything or touch a machine.
```

## Release identity (verbatim)

```
In the release publish job, do not honor a pre-set SIGN_IDENTITY. The job always derives the identity from the single certificate imported from MACOS_SIGNING_P12_BASE64 and MACOS_SIGNING_P12_PASSWORD. Zero identities or more than one still fail before scripts/build.sh. Keep security find-identity -p codesigning on the temporary keychain, no -v, and count quoted names only from the matching-identities section. Export the derived identity for scripts/build.sh.

SIGN_IDENTITY remains only scripts/build.sh's local-build switch: set means sign with that login-keychain identity, unset means ad-hoc.

Releases always use the imported certificate. "The signing identity" stays the generic prose name and is not a literal certificate subject.

Leave .cursor/install.sh hardcoding nikolaybotev/local-skills with no override and no env var. It is only for Cursor Cloud Agent environment setup.
```
