# Review instructions

## Passes

Run three passes and tag each finding with its pass:

- **Bugs:** a published snapshot whose destination is the source or is inside the source (see `Sources/backup-folder/main.swift` path checks and walk). A backup LaunchAgent template that still has `StartInterval` or a real home, source, or backup path instead of placeholders.
- **Security:** a WireGuard key, endpoint, tunnel address, 1Password item URI path, or personal source-folder name in git. An install script that writes outside `~/bin` or anywhere under `Backups`. No backup paths, hostnames, or personal folder names in tests or fixtures. Path handling that lets `dest` sit inside `src` after `..` or an extra slash is a security finding because the walk copies the backup into itself.
- **Compliance:** the change matches the spec and plan for its intent, and `AGENTS.md`. A departure from the plan that is not written back into `plan.md` in the same change is a compliance finding. The `macos` job must stay green. These Roger bootstrap phases do not push a `v*` tag. Do not edit `.github/scripts/protect-main-branch.sh` or `.github/workflows/protect-main.yml`.

## What Important means here

Reserve Important for secret or tunnel leaks in git, a release workflow that publishes on a push to `main`, a workflow that installs on a machine, a published snapshot name that is a partial tree, two runs sharing one snapshot path, retention keeping that partial as the day's keeper, or a walk that enters `dest` or follows a directory symlink. Style and naming are nits.

## Cap the nits

Report at most five nits per review; summarize the rest as a count.

## Do not report

Formatting the CI already enforces, generated files the repo ignores, and wording inside the verbatim prompt block of any `intent.md`.

Do not report "source `/` is accepted." Line 12 strips the only character of `/`, and line 14 then matches every absolute `dest`. That case is already refused.

Do not ask for a whole-directory `clonefile`. The comment on lines 38–39 says a directory clone is refused inside iCloud-managed folders, and the macOS runner cannot prove that case.
