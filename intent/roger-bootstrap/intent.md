# intent.md — the deployment Mac bootstrap hub

| | |
|---|---|
| Author | the deployment Mac |
| Captured | 2026-10-30 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Related | `intent/drop-box-watcher/` (separate change; this folder does not specify the watcher) |

## Problem

A new Mac, a restore, or a repeat setup of the deployment Mac has no single public place that holds local tools, LaunchAgent and LaunchDaemon templates, and the setup steps. `backup-folder` is one snapshot binary. The maintainer's general dev bootstrap (`~/.bootstrap`, GitHub `nikolaybotev/bootstrap`) is a different repo and stays that way. The steps for the deployment Mac live in a private runbook, with each step marked manual or scripted, and the public repo cannot hold the WireGuard server's public key, public IP, or port, or anything else secret.

## Proposed outcome

`backup-folder` is the host-specific bootstrap hub for new hardware, restores, and repeat setups. It hosts the host-local tools (`backup-folder` and `drop-box-watcher`). CI publishes signed GitHub release binaries. An install script downloads those binaries into `~/bin`. The repo holds LaunchAgent and LaunchDaemon plist templates, plus setup and restore docs built from the runbook, each step still marked manual or scripted. Real secrets are filled from 1Password at install time. Nothing is deployed to the deployment Mac unless the maintainer approves it; the operator runs the install, with a heads-up.

## Affected users and systems

- **Users:** the maintainer, who approves and performs setup and restore on the deployment Mac. automation on the deployment Mac that follows the docs during a restore.
- **Systems:** the public GitHub repo `nikolaybotev/backup-folder`, its GitHub Actions release workflow, `~/bin` on the deployment Mac, LaunchAgents and the WireGuard LaunchDaemon on that Mac, and 1Password as the source of secrets at install time. `nikolaybotev/bootstrap` stays the general dev bootstrap.

## Constraints and principles

- The hub stays separate from `~/.bootstrap`.
- The repo is public. Never commit the WireGuard server's public key, its public IP, or its port, and never commit any other secret. Templates keep placeholders. Real values come from 1Password at install time.
- CI publishes signed GitHub release binaries. An install script downloads them into `~/bin`.
- Nothing is deployed to the deployment Mac without the maintainer's approval. The operator handles the install, with a heads-up.
- A rename of the repo may be proposed. The rename is the maintainer's decision. This change does not rename the repo or the `backup-folder` binary.
- The Drop Box watcher is a separate intent. Its design and its install location (`~/bin/drop-box-watcher`, per-user LaunchAgent) stay as already settled. This hub does not re-specify the watcher.
- This change does not cut a GitHub release and does not push a tag.
- Spec, plan, and review use Grok 4.7 High. Each build phase uses Composer 2.5. One phase is one pull request. The coordinator squash-merges only when the required checks are green.

## Open questions (carried into spec.md)

1. Does a repo rename fit, and is the proposed name accepted?
2. Should Remote Login (SSH) be on?
3. What energy settings count as always-on?
4. What should the docs say about the the deployment Mac self-hosted runner?
5. What else is installed on the deployment Mac that a restore must include?
6. Is Apple notarization required in addition to the signature the install script checks?

## Original prompt (verbatim)

> 2. The deployment Mac bootstrap repo. backup-folder becomes the host-specific bootstrap hub for new hardware, restores and repeat setups. It stays separate from the maintainer's general dev bootstrap (~/.bootstrap). It should host the host-local tools (backup-folder, drop-box-watcher). CI should publish signed GitHub release binaries, and an install script should download them into ~/bin. It also holds LaunchAgent/LaunchDaemon plist templates and setup and restore docs, built from the attached setup-runbook.md, which marks each step as manual or scripted. A rename of the repo is open; propose one if it fits. Hard rule: the repo is public, so never commit the WireGuard server's public key or its public IP or port, and nothing secret. Templates keep placeholders, and the real values come from 1Password at install time. Nothing gets deployed to the deployment Mac without the maintainer's approval; I'll handle install on the deployment Mac with a heads-up before changes.
