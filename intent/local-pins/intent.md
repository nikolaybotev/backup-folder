# intent.md — Local pins

| | |
|---|---|
| Author | Nikolay (relayed by Roger) |
| Captured | 2026-10-30 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |
| Builds on | [release-builds](../release-builds/intent.md) |

## Problem

`pins.txt` is tracked in git. A commit that sets a real pin is also a merge to `main`, and a merge to `main` publishes a release. The install script's name says Roger, but the script installs whatever tools the pin file names.

## Proposed outcome

The live pin file stays on the machine that runs the installer, and it is not committed. The installer has a generic name. Merging the change can still publish the next patch tag, because the pin file is not in the commit. Nothing is installed on Roger.

## Affected users and systems

- **Users:** Nikolay, who writes the local pin file and runs the installer on the Mac. CI and agents, who must not.
- **Systems:** the public repo `nikolaybotev/backup-folder`, the tracked `pins.txt`, `scripts/install-roger-tools.sh`, and `~/.config` on the machine that uses the installer.

## Constraints and principles

- The pin file is local. It is not a git commit, so a pin is not what publishes a release.
- The installer is not named for the Mac named Roger.
- Nothing gets installed on Roger. The change goes through a pull request, agent review, and merge.
- Publish-on-merge stays as it is.

## Open questions (carried into spec.md)

None. The pin path, the script name, and the rejected `scripts/install.sh` name are decided below.

## Original prompt (verbatim)

```
Nikolay's direction on the auto-install script (his words relayed by Roger):
1. pins.txt must not be tracked in git. It is a local file on the machine that uses the auto-install (e.g. under ~/.config), never committed. This also removes the problem of a pin commit publishing a new release.
2. The auto-install script must not have "roger" in its name; give it a generic name.
Make both changes through the normal ai-native SDLC (PR, agent review, merge). Nothing gets installed on Roger.
```

## Kickoff decisions and constraints (verbatim)

```
Decisions already made, record them and do not re-litigate:

- D1. The tracked file pins.txt is removed from git and added to .gitignore. The live pin file is ~/.config/backup-folder/pins.txt. The script reads that path. A committed pins.txt.example documents the format (tool name and v* tag, or unpinned) and is not the live pin. Do not put a real pin in the example.
- D2. Rename scripts/install-roger-tools.sh to scripts/install-tools.sh. Rename its test the same way. Update every reference (AGENTS.md, docs, setup-docs bullet checks, workflows). No "roger" in the new script name.
- Why D2: the script installs whatever tools the local pin file names. It is not specific to the machine named Roger.

Constraints:
- Do not install anything. Do not run the installer against a home directory. Do not touch ~/Backups.
- Do not commit a real pin. Do not change the publish-on-merge behavior in this spec. State plainly that merging this change still publishes the next patch tag, and that is acceptable because the pin file is not in the commit.
- install-tools.sh still installs only into ~/bin, still refuses uid 0 and any path component named Backups, still uses gh release download and gh attestation verify. It does not build from source.
- Required PR checks stay macos and linux. No new required job. Timeouts stay 5. CodeQL stays off pull requests.
- No secrets, webhook URL, or keys.
- Conventional commit. One spec-and-plan pull request. Do not start the code change.

Check the current script, pins.txt, and tests before freezing the paths. Record what you checked. Report the PR URL.
```

## Name correction (verbatim)

```
Nikolay asked: use scripts/install.sh only if nothing else install-related makes that name ambiguous. It is ambiguous. Do not rename to scripts/install.sh.

Keep D2 as scripts/install-tools.sh (and the matching test name). Record this in the spec as a rejected alternative:

On main, `.cursor/install.sh` is the Cloud Agent environment installer. README.md says cloud agents run it: it apt-installs libncurses6, then mise and the pinned Swift toolchain. A second file named install.sh, even under scripts/, would collide with that name.

Also present, and not install scripts: launchd/backup-folder.plist.template, launchd/drop-box-watcher.plist.template, launchd/com.wireguard.wg0.plist.template, docs/setup.md. Those do not change the name.

Everything else in your assignment stands.
```
