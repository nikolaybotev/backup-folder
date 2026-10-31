# Review instructions

## Passes

Run three passes and tag each finding with its pass:

- **Bugs:** a published snapshot whose destination is the source or is inside the source (see `Sources/backup-folder/main.swift` path checks and walk). A backup LaunchAgent template that still has `StartInterval`, a real path, the per-folder label `com.nikolaybotev.backup.NAME`, or a source and dest argument pair.
- **Security:** a WireGuard key, endpoint, tunnel address, 1Password item URI path, or personal source-folder name in git. An install script that writes outside `~/bin` or anywhere under `Backups`. No backup paths, hostnames, or personal folder names in tests or fixtures. Path handling that lets `dest` sit inside `src` after `..` or an extra slash is a security finding because the walk copies the backup into itself.
- **Compliance:** the change matches the spec and plan for its intent, and `AGENTS.md`. A departure from the plan that is not written back into `plan.md` in the same change is a compliance finding. The `macos` job must stay green. Agents do not push a `v*` tag by hand; job `publish` in `.github/workflows/release.yml` may publish the next patch tag on a push to `main`. Coordinators squash-merging to `main` must keep `(#N)` at the end of the commit subject so `scripts/release-version.sh` can read the merged pull request's labels. Do not edit `.github/scripts/protect-main-branch.sh` or `.github/workflows/protect-main.yml`.

## Writing rules

Check these on the compliance pass. A miss is a compliance finding.

1. **This repo.** Prose about this repo says "this repo". `.cursor/install.sh` is only for setting up Cursor Cloud Agent environments, never GitHub Actions or anything else. It hardcodes `nikolaybotev/local-skills` with no override and no environment variable. A fork override belongs only on this repo's own distribution entry points (its installer and release install commands), and only where it is cheap. Do not derive a repository identity from `GITHUB_REPOSITORY` in code that other repositories' CI may run. This repo's own workflows may use `${{ github.repository }}`. Install instructions do not depend on an environment variable the reader must set. Wording inside a verbatim prompt block stays out of scope.
2. **Variable config.** Docs, tests, and workflows name the setting (environment variable, secret, or config key). They do not copy its current value. Tests assert behavior against the configured value.
3. **Obvious notes, human-facing docs only.** README and user and setup docs do not spell out what a competent reader already knows. Agent-facing files keep explicit expectations such as "(healthy: exit 0)". That includes `AGENTS.md`, `REVIEW.md`, skills, and intents written for agents.

## What Important means here

Reserve Important for secret or tunnel leaks in git, any workflow other than job `publish` in `.github/workflows/release.yml` that publishes on a push to `main`, a workflow that installs on a machine, a published snapshot name that is a partial tree, two runs sharing one snapshot path, retention keeping that partial as the day's keeper, or a walk that enters `dest` or follows a directory symlink. Style and naming are nits.

## Cap the nits

Report at most five nits per review; summarize the rest as a count.

## Do not report

Formatting the CI already enforces, generated files the repo ignores, and wording inside the verbatim prompt block of any `intent.md`.

Do not report "source `/` is accepted." Line 12 strips the only character of `/`, and line 14 then matches every absolute `dest`. That case is already refused.

Do not ask for a whole-directory `clonefile`. The comment on lines 38–39 says a directory clone is refused inside iCloud-managed folders, and the macOS runner cannot prove that case.
