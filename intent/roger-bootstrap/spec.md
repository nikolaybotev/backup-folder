# spec.md — deployment bootstrap hub

| | |
|---|---|
| Derived from | [intent.md](intent.md) (2026-10-30) |
| Status | Draft 2 |
| Stage | 2 · Design |

## 1. Summary

The public repo `nikolaybotev/backup-folder` becomes the host-specific setup hub. It keeps the snapshot tool, gains placeholder LaunchAgent and LaunchDaemon templates, gains setup and restore docs whose steps are each marked manual or scripted, and gains an install script that downloads pinned release binaries into `~/bin` after a signature check. GitHub Actions on a `v*` tag attests each published binary. This change does not rename the repo, does not cut a release, and does not install anything on the deployment Mac.

The Drop Box watcher stays a separate intent. This spec only says where its binary is installed and that the setup doc points at that intent's LaunchAgent template.

## 2. Goals and non-goals

**Goals**

- G1. One public repo holds the deployment Mac's setup and restore docs, with every step marked manual or scripted.
- G2. LaunchAgent and LaunchDaemon templates ship with placeholders. Secrets and tunnel addresses are filled from 1Password when the maintainer installs them.
- G3. A `v*` tag builds the deployment Mac tool binaries that exist in the repo, attests them, and uploads them to a GitHub release.
- G4. An install script downloads the pinned binaries into `~/bin` and refuses a file whose attestation does not verify.
- G5. The hub stays separate from `OWNER/bootstrap` (`~/.bootstrap`).

**Non-goals**

- Renaming the GitHub repo or the `backup-folder` binary. A name is proposed in D1 and left to the maintainer.
- Implementing, configuring, or re-deciding the Drop Box watcher. Readiness, the webhook actor, the config schema, and the watcher plist body belong to `intent/drop-box-watcher/`.
- Changing snapshot behavior, retention, or any snapshot-bug fix.
- Pushing a tag, publishing a GitHub release, or setting a real version pin.
- Deploying to the deployment Mac: no `launchctl`, no write to `~/Backups`, no copy into `~/bin` from CI or from an agent.
- Vendoring `OWNER/bootstrap`, and writing a second `~/.gitconfig` from this repo.
- Changing the AWS WireGuard server, or choosing the private IPv6 range the runbook's to-do asks for.
- Apple Developer ID codesign or notarization (see Q6).
- Turning on Remote Login, inventing energy-setting clicks, or inventing the self-hosted runner procedure (see Q2–Q4).

**Release phasing.** G1–G5 are this change. The repo rename, Apple notarization, the IPv6 range move, the first `v*` tag, and the first real pin are later. They wait on the maintainer. Untagged requirements in this spec belong to this change.

## 3. Principles

- P1. The repo is public. Placeholders stay in git. The WireGuard server public key, public IP, port, private key, preshared key, tunnel addresses, webhook URL, webhook key, and any other secret are filled from 1Password at install time.
- P2. The maintainer approves every install on the deployment Mac and runs it himself, with a heads-up. Merging to `main` does not deploy and does not publish a release.
- P3. `~/.bootstrap` remains the general dev bootstrap. This hub documents calling it and does not absorb it.
- P4. The snapshot binary stays `backup-folder`. The project name Cairn is not a repo name and not a binary name.
- P5. One build phase is one pull request. The build agent opens it ready for review and does not merge. The coordinator squash-merges only when the required checks are green. A cancelled check is not green.
- P6. Where this spec and a later plan disagree, this spec wins. A departure is written back into `plan.md` in the same change.

## 4. Users and scenarios

The maintainer is the only person who runs these steps on the deployment Mac. An agent may edit the repo. An agent does not SSH to the deployment Mac, bootstrap a plist, or run the install script against a home directory.

- **New Mac.** Follow `docs/setup.md` from top to bottom. Manual steps need a person at the keyboard. Script steps are commands he runs.
- **Files restored onto an existing Mac.** Follow `docs/restore.md`. iCloud repopulates Desktop and Documents. He re-fills secrets from 1Password and re-loads agents that are missing.
- **A new build of a tool.** He pushes a `v*` tag when he wants a release. The workflow attests and uploads. A later change, outside these phases, sets the pin. He then runs the install script, with a heads-up. These phases do not do that tag or that pin.
- **Cloud agent on Linux.** It can edit templates, docs, and the install script. It cannot run `clonefile`, `launchctl`, or the macOS APFS smoke test.

## 5. Functional requirements

### 5.1 Docs

FR1. `docs/setup.md` follows the step catalog in section 5.4 in that order. `docs/restore.md` covers the restore catalog in section 5.5. Each step is a Markdown bullet whose text starts with `Manual:` or `Script:`. Caveats are paragraphs, so a bullet test can require every bullet to be marked.

FR2. The docs state that the maintainer runs them, that CI does not, and that a heads-up comes before anything is installed on the deployment Mac.

FR3. The docs do not contain a WireGuard key, a tunnel address, an endpoint host or port, a 1Password secret or 1Password item URI path, a personal source-folder name, or a GPG key id. They name the placeholder tokens from section 5.2 and say to fill them from 1Password.

### 5.2 Templates

FR4. `launchd/wg0.conf.template` is exactly this file. `PersistentKeepalive = 25` is the only literal. Every other value is a placeholder token.

```ini
[Interface]
PrivateKey = [PRIVATE_KEY]
Address = [INTERFACE_ADDRESS]
DNS = [DNS]

[Peer]
PublicKey = [SERVER_PUBLIC_KEY]
PresharedKey = [PRESHARED_KEY]
AllowedIPs = [ALLOWED_IPS]
Endpoint = [SERVER_PUBLIC_IP]:[PORT]
PersistentKeepalive = 25
```

FR5. `launchd/com.wireguard.wg0.plist.template` is a LaunchDaemon template:

- Label `com.wireguard.wg0`.
- Program arguments `/opt/homebrew/bin/wg-quick`, `up`, `wg0`.
- `RunAtLoad` true, `KeepAlive` true.
- `PATH` is `/opt/homebrew/sbin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
- Standard error path `/var/log/wireguard-wg0.err`.
- No keys, no tunnel addresses, and no endpoint.

The filled plist is installed at `/Library/LaunchDaemons/com.wireguard.wg0.plist`, owned `root:wheel`, mode `644`. The filled config is installed at `/opt/homebrew/etc/wireguard/wg0.conf`, mode `600`. Those copies happen on the Mac, from the setup doc, not in CI.

FR6. `launchd/backup-folder.plist.template` becomes a per-folder LaunchAgent template:

- Label `com.nikolay.backup.NAME`. The token is `NAME`, not an angle bracket, so the file is well-formed XML.
- Program arguments `/Users/USER/bin/backup-folder`, `/ABS/SOURCE`, `/ABS/BACKUP-DIR`.
- `StartCalendarInterval` with `Minute` `0` and no hour, so it fires at minute 0 of every hour.
- `RunAtLoad` false.
- No `StartInterval`. No real home directory, source path, or backup path.

FR7. This change does not add a drop-box-watcher plist or a watcher config schema. The setup doc tells the maintainer to install the LaunchAgent template that `intent/drop-box-watcher/` adds, and to point it at `~/bin/drop-box-watcher`.

### 5.3 Release and install

FR8. `.github/workflows/release.yml` stays triggered only by tags matching `v*`, on `macos-latest` (GitHub-hosted). It builds `backup-folder` with `swiftc -O -o backup-folder backup-folder.swift`. When `drop-box-watcher.swift` exists in the repo root, it also builds `drop-box-watcher` with `swiftc -O -o drop-box-watcher drop-box-watcher.swift`. This change does not add that source file. If the watcher intent needs a different compile line, that intent edits this workflow.

FR9. After the build, the workflow attests each binary with `actions/attest@v4` (`subject-path` set to that binary). The job permissions include `id-token: write`, `attestations: write`, and `contents: write`. It then runs `gh attestation verify` on each binary with `--repo nikolaybotev/backup-folder`, `--signer-workflow nikolaybotev/backup-folder/.github/workflows/release.yml`, and `--deny-self-hosted-runners`. The verify command may be retried a few times to wait for the attestation API. If verify fails, the job fails before upload. The upload stays `softprops/action-gh-release@v2`, and the asset name is the binary name.

FR10. `pins.txt` in the repo root has one tool per line, `name tag`, plus `#` comments. Both tools ship as `unpinned`:

```
backup-folder unpinned
drop-box-watcher unpinned
```

A later change outside these phases replaces `unpinned` with a real `v*` tag after the maintainer has published that release. No phase in this plan does that.

FR11. `scripts/install-tools.sh` reads `pins.txt` (override with `PINS_FILE`). For each `unpinned` tool it prints a skip and continues. For each tag that matches `v` plus digits and dots, it downloads that release asset from `nikolaybotev/backup-folder` (override with `GH_REPO`) into a temp file, runs the same `gh attestation verify` flags as FR9, and only then moves the file to `$HOME/bin/<tool>` mode `755`. A tag that is neither `unpinned` nor `v` plus digits and dots makes the script exit non-zero and install nothing. The tool name must match `^[a-z0-9][a-z0-9-]*$`. Verify failure deletes the temp file, leaves any existing `~/bin` binary in place, and exits non-zero. The refusal check takes the uid as an argument: uid 0 is refused, and so is an install directory whose path has a component named `Backups`. The script's main path passes the effective uid. It does not call `launchctl`, `sudo`, or `op`, and it does not read or write `~/Backups`.

FR12. Snapshot directories are home-mirrored: each one is `~/Backups` plus the source path relative to the home directory. `scripts/ensure-backup-dirs.sh` takes those absolute paths as arguments. It creates each directory and parents, and it does not delete anything. It exits non-zero if an argument is relative, contains a `..` component, or names an existing file. It has no default path and no baked-in source-folder names. Those names stay out of git and are supplied at install time. CI does not run it.

### 5.4 Setup step catalog

`docs/setup.md` includes every row. The Doc column is the mark the bullet uses. Where that mark differs from the runbook, the reason is in the decisions.

| # | Doc | Step |
|---|---|---|
| 1 | Manual | Apple ID / iCloud sign-in during account setup. iCloud Drive with Desktop & Documents turned on. |
| 2 | Manual | In Finder, Desktop and Documents are Keep Downloaded, whole folders, so tools and backups see local files. |
| 3 | Manual | FileVault on. No auto-login. After a reboot he logs in once, via Screen Sharing, before iCloud syncs. |
| 4 | Manual | Screen Sharing on. |
| 5 | Manual | Remote Login (SSH) is not turned on by this doc. See Q2. |
| 6 | Manual | Energy: the machine should avoid sleep and start after power failure. Exact clicks wait on Q3. The doc states the goal and does not invent a click path. |
| 7 | Manual | Choose a computer name. |
| 8 | Script | Run the general bootstrap, with its confirm prompt: `sh -c "$(curl -fsSL https://raw.github.com/OWNER/bootstrap/main/install.sh)"`. That curl is not enough on a fresh Mac. `install.Darwin.sh` is `sh -e` and calls `jq` before it opens the Homebrew and mise pages, and a fresh Mac does not ship `jq`, so the script can exit before those pages open. Updates later use `~/.bootstrap/update`. This repo does not copy that repo. See D3. |
| 9 | Manual | Finish the Homebrew and mise installs that the bootstrap opens in a browser. See D3. |
| 10 | Script | `brew install wireguard-tools wireguard-go`. |
| 11 | Script | `brew install gh git gnupg pinentry`. |
| 12 | Manual | `gh auth login` for the `OWNER` GitHub account. |
| 13 | Manual | Generate a new GPG signing key on the new hardware, add it to GitHub, and make it unlock without a prompt for agent commits. Passwords live in 1Password. The doc does not record any previous key id. See D12. |
| 14 | Manual | Set `user.signingkey` in the gitconfig the bootstrap wrote. That gitconfig already sets `commit.gpgsign` and `tag.gpgsign`. This repo does not ship a gitconfig. |
| 15 | Manual | Install the Grok Bot app and sign in. Register this Mac. Grant Files & Folders for Desktop and Documents only. Downloads, iCloud Drive, and Removable Volumes stay off. |
| 16 | Manual | Install Cursor and sign in. |
| 17 | Manual | The deployment Mac self-hosted runner is named as a step and left unfinished until Q4. The doc does not invent a runner token, label, or install command. |
| 18 | Manual | Install the 1Password app, sign in, and install the 1Password CLI (`op`). |
| 19 | Manual | Install iStat Menus and MacVim. |
| 20 | Manual | Fill `launchd/wg0.conf.template` from 1Password into `/opt/homebrew/etc/wireguard/wg0.conf` and `chmod 600` it. The filled file is not committed. |
| 21 | Script | Install `launchd/com.wireguard.wg0.plist.template` to `/Library/LaunchDaemons/com.wireguard.wg0.plist` with `sudo`, `chown root:wheel`, `chmod 644`, then `sudo launchctl enable system/com.wireguard.wg0` and `sudo launchctl bootstrap system` on that plist. |
| 22 | Script | Check with `sudo wg` and `sudo launchctl print system/com.wireguard.wg0`. Stop with `sudo launchctl bootout system/com.wireguard.wg0`. |
| 23 | Manual | If the WireGuard GUI app is installed, turn off On-Demand and delete its tunnel. It keeps keys in the login keychain and fights the daemon. Do not use `sudo brew services start wireguard-tools`. |
| 24 | Manual | External 2 TB SSD as APFS: volume `External`, and Time Machine volume `Time Machine volume` with an 800 GB quota. Time Machine backs up the Mac. Assistants stay off `External`. This step needs a heads-up before the disk is touched. |
| 25 | Manual | Point Time Machine at `Time Machine volume`. |
| 26 | Script | Run `scripts/install-tools.sh` once `pins.txt` names real tags. Until then the script skips unpinned tools. The destination is `~/bin`. |
| 27 | Manual | Accept the macOS Desktop and Documents prompts for each new binary. Repeat after every new binary. Unidentified-developer prompts are part of this step until Q6 is answered. |
| 28 | Script | Run `scripts/ensure-backup-dirs.sh` with the absolute home-mirrored snapshot directories. Each one is `~/Backups` plus the source path relative to the home directory. Those paths are arguments at install time, not files in git, and the source-folder names stay out of git. The script creates directories and does not delete. |
| 29 | Script | For each backup source, copy `launchd/backup-folder.plist.template` into `~/Library/LaunchAgents/`, replace `NAME`, `USER`, `/ABS/SOURCE`, and `/ABS/BACKUP-DIR`, and `launchctl bootstrap gui/$(id -u)` that plist. The source folders are chosen at install time and are not written in the doc. |
| 30 | Script | Install the drop-box-watcher LaunchAgent from the template `intent/drop-box-watcher/` adds, with the binary at `~/bin/drop-box-watcher`. This doc does not define that plist. |
| 31 | Manual | Write `~/.config/drop-box-watcher/config.toml` mode `0600`. The webhook URL and key come from 1Password (`op read` or paste). The schema is the watcher intent's. The file is not committed. |
| 32 | Manual | Create `~/Desktop/Drop Box` with a space in the name. |

A caveat paragraph, not a bullet: with FileVault, nothing including the VPN starts on a cold boot until the disk is unlocked. For a planned restart, `sudo fdesetup authrestart` brings the VPN and Screen Sharing back unattended. After a power loss, someone unlocks the Mac locally. The watcher is a per-user LaunchAgent, so it starts at login, and its own startup scan covers files that arrived while it was down. That scan is specified by the watcher intent, not here.

### 5.5 Restore step catalog

`docs/restore.md` distinguishes a new Mac (use `docs/setup.md`) from putting files back on an existing Mac:

| # | Doc | Step |
|---|---|---|
| R1 | Manual | Restore files from Time Machine (`Time Machine volume`) or from the home-mirrored snapshot directories under `~/Backups` (`~/Backups` plus the source path relative to the home directory), as needed. |
| R2 | Manual | iCloud repopulates Desktop and Documents. Keep Downloaded still applies to those two folders. |
| R3 | Manual | Re-fill `wg0.conf` and the watcher `config.toml` from 1Password. Modes stay `600` and `0600`. |
| R4 | Script | Re-run the WireGuard daemon install and the LaunchAgent installs from the setup doc when those plists are missing. |
| R5 | Script | Re-run `scripts/install-tools.sh` for any pinned tool whose `~/bin` binary is missing or should move to the pin. |
| R6 | Manual | Accept Desktop and Documents prompts for any binary that was replaced. |
| R7 | Manual | If the hardware changed: update the machine id in the deployment Mac's profile, the `file-access-policy` skill, and shared memory. Re-check the Drop Box dispatcher routine and the daily backup health check routine. This is bot-side work. It is not a command on the Mac, and this repo does not perform it. |

## 6. Acceptance criteria

| AC | Check |
|---|---|
| AC1 | `bash tests/setup-docs.sh` exits 0. Every bullet in `docs/setup.md` and `docs/restore.md` starts with `- Manual:` or `- Script:`, and the catalog anchors from the plan are present. |
| AC2 | `bash tests/no-secrets.sh` exits 0. `wg0.conf.template` matches FR4. Both plists parse. The scanned trees (`intent/`, `launchd/`, `docs/`, `scripts/`, `README.md`, `pins.txt`, `.github/workflows/`) contain no 1Password item URI, no WireGuard-key-shaped token, no IPv4 literal, no IPv6 literal, and no numeric port suffix (a colon followed by a decimal integer). The test does not embed the runbook's real addresses, prefix, or port. The backup template has no `StartInterval`. |
| AC3 | `launchd/com.wireguard.wg0.plist.template` has the label, program, PATH, `RunAtLoad`, `KeepAlive`, and standard-error path from FR5, and no endpoint or key. Checked by `tests/no-secrets.sh`. |
| AC4 | `launchd/backup-folder.plist.template` has the label, `~/bin` path, calendar minute 0, and `RunAtLoad` false from FR6. Checked by `tests/no-secrets.sh`. |
| AC5 | `bash tests/release-workflow.sh` exits 0. `release.yml` triggers on `v*` tags, runs on `macos-latest`, calls `actions/attest` with `subject-path` set to each binary, and has the permissions and verify flags from FR9 (`id-token: write`, `attestations: write`, `contents: write`). It does not require `artifact-metadata: write`. The ban on a `schedule` key and the ban on a push `branches` key apply to `release.yml` only. The `v*` tag trigger stays. |
| AC6 | `bash tests/install-tools-test.sh` exits 0 without network. Unpinned tools are skipped. A pin that is neither `unpinned` nor `v` plus digits and dots exits non-zero and installs nothing. A stub `gh` that writes the temp file and exits 0 leaves `$HOME/bin/<tool>` at mode `755`. The test checks statically that the script contains the FR9 verify flags and does not contain `launchctl`, `sudo`, or `op`. The uid check is called with uid 0 as an argument, so the test does not run as root. A `Backups` destination is refused. |
| AC7 | `bash tests/ensure-backup-dirs-test.sh` exits 0. The script creates a temp directory, refuses a relative path and a `..` path, and does not delete an existing marker file. |
| AC8 | No workflow under `.github/workflows/` runs `scripts/install-tools.sh`, `launchctl`, or a write under `Backups`. Checked by `tests/release-workflow.sh` for `release.yml` and by `tests/no-secrets.sh` for the workflow directory. |
| AC9 | `README.md` still leads with the snapshot tool, names the hourly-at-minute-0 template and `~/bin`, and links `docs/setup.md` and `docs/restore.md`. |
| AC10 | `AGENTS.md` names the install script, the secret rule, and that a tag push is the only release. `REVIEW.md` exists and uses the Bugs, Security, and Compliance passes from the skill, specialized as the plan says. |

## 7. Design decisions

**D1 — Repo name stays; proposed name is `roger-bootstrap`.** Every phase in this plan uses `nikolaybotev/backup-folder` in workflow files, the install script, and attestation flags. The proposed GitHub name is `roger-bootstrap`. It fits because the repo will hold two tools, the install script, the launchd templates, and the setup docs, while the snapshot binary keeps the name `backup-folder`, and the general bootstrap keeps `~/.bootstrap` and `OWNER/bootstrap`. A later phase would otherwise rename the repo to Cairn or to `host`. Cairn is closed by the project preference that the repo and the binary are not renamed to the project name. `host` is the Mac and the bot, and it does not say bootstrap. The maintainer decides whether to rename (Q1). This change does not rename anything. Verified 2026-10-30: the GitHub repo is public, named `backup-folder`, default branch `main`.

**D2 — Call `OWNER/bootstrap`; do not vendor it.** The setup doc runs the installer in setup catalog step 8. Verified 2026-10-30 from that public repo: the README gives that curl command and `~/.bootstrap/update`. `install.Darwin.sh` writes `~/.gitconfig` from a template whose `user.name` and `user.email` are placeholders, sets `commit.gpgsign` and `tag.gpgsign` to true, and leaves `signingkey` empty. This hub does not ship a gitconfig and does not hard-code a name or email.

**D3 — Homebrew and mise are manual click-through, and the bootstrap curl is not enough on a fresh Mac.** The runbook called them a scripted result of the dev bootstrap. Verified 2026-10-30: `install.Darwin.sh` is 61 lines. Its shebang is `sh -e`. Line 46 sets the git email with `jq` before the script reaches `open https://brew.sh` and `open https://mise.en.dev` (the last two lines). A fresh macOS system does not ship `jq`, so catalog step 8 can exit before those pages open. The setup doc says that curl is not enough on a fresh Mac. This repo still does not vendor `OWNER/bootstrap` and does not grow a second installer. The doc marks the bootstrap command as Script and the browser installs as Manual. `brew install` lines after Homebrew exists stay Script. The setup doc runs that bootstrap and the Homebrew click-through before the first `brew install`, which is earlier than the runbook's section order, because those brew commands need Homebrew. Templates assume Apple Silicon Homebrew at `/opt/homebrew`, which is what the runbook and the settled watcher note both use.

**D4 — "Signed" means a GitHub artifact attestation.** The release job uses `actions/attest@v4`. The install script trusts a binary only when `gh attestation verify` accepts it for this repo and for `.github/workflows/release.yml`, and rejects an attestation from a self-hosted runner. Verified 2026-10-30: `release.yml` on `main` (`7625d02`) only builds and uploads; `gh release list` is empty; GitHub's docs describe `actions/attest` and `gh attestation verify <file> --repo OWNER/REPO` for binaries, including `--signer-workflow` and `--deny-self-hosted-runners`, and public repos can use the public Sigstore instance. A GPG signature on the asset would need a private key in CI, which this workflow does not have. Apple notarization is Q6, not this change.

**D5 — Install into `~/bin` only.** The script's only install path is `$HOME/bin/<tool>`. It does not touch `~/Backups` or `~/Backups/bin`. Moving an older binary out of `~/Backups/bin` is something the maintainer does on the Mac, in the same window as the watcher install, and this repo does not do it. This matches the settled watcher install location.

**D6 — The public WireGuard template placeholders every tunnel value.** The runbook's filled-in addresses, and the IPv6 prefix its to-do says to abandon, are not copied into git. That to-do points at a prefix published in Ben Hardill's article [Setting up WireGuard IPv6](https://blog.hardill.me.uk/2021/04/20/setting-up-wireguard-ipv6/) (checked 2026-10-30). The replacement range is chosen when the AWS server changes, which is outside this repo. 1Password item URI paths are not committed; the item names were not given, and the template does not need them. The maintainer fills the tokens with `op` or by paste at install time.

**D7 — Personal source-folder names stay out of git. The layout rule stays.** The runbook names three backup sources and a home-mirrored `~/Backups` layout. The public docs and the directory script do not contain those names. Each snapshot directory is `~/Backups` plus the source path relative to the home directory. He passes those absolute paths when he installs the LaunchAgents and when he runs `scripts/ensure-backup-dirs.sh`. The existing snapshot source comment in `backup-folder.swift` is left as it is; this change does not add folder names.

**D8 — Backup agents fire at minute 0 under `com.nikolay.*`.** The template on `main` uses label `local.backup-folder.FOLDER`, `StartInterval` 3600, and `RunAtLoad` false. The runbook asks for `com.nikolay.backup-<name>` hourly at minute 0. The new template uses label `com.nikolay.backup.NAME`, `StartCalendarInterval` minute 0, and `RunAtLoad` false so loading the agent does not take an extra snapshot. `NAME` is the XML-safe form of the runbook's `<name>`. The program path is `/Users/USER/bin/backup-folder` because a plist does not expand `~`. Editing the template does not reload any agent on the deployment Mac.

**D9 — WireGuard is the custom LaunchDaemon.** The daemon plist matches the runbook: `wg-quick up wg0`, `RunAtLoad`, `KeepAlive`, the Homebrew PATH, and stderr at `/var/log/wireguard-wg0.err`. Load and unload use `launchctl bootstrap` and `bootout` on the system domain, as the runbook says. `brew services` is not used. The GUI app's tunnel is removed so it does not keep a second copy of the keys. The runbook cites a private note and [this article](https://barrowclift.me/articles/wireguard-server-on-macos); the field list here is taken from the runbook.

**D10 — The watcher is not re-specified.** Settled elsewhere, and only consumed here: the binary path is `~/bin/drop-box-watcher`; it is a per-user LaunchAgent; the config path is `~/.config/drop-box-watcher/config.toml` mode `0600`; the watch folder is `~/Desktop/Drop Box`. Readiness, FSEvents, the webhook actor, ignore rules, and the plist body stay in the watcher intent. This spec does not repeat them.

**D11 — No phase publishes a release.** `pins.txt` ships with both tools `unpinned`. No phase pushes a tag or sets a real pin. `AGENTS.md` already says a release exists only after a `v*` tag push runs `release.yml`. That remains the rule. The release workflow change is inert until the maintainer pushes a tag.

**D12 — A new GPG key is created on the new hardware.** The runbook says the old key is not backed up and names the key currently on the machine. This repo does not record that key id. The bootstrap gitconfig turns signing on. He sets `user.signingkey` to the new key and keeps the passphrase in 1Password.

**D13 — Build and merge.** Spec, plan, and review use Grok 4.7 High. Each build phase is a fresh Composer 2.5 agent, one branch, one pull request, opened ready for review. That agent does not merge. The coordinator squash-merges when the `macos` check and the `CodeQL (Swift)` check are green, then deletes the branch. A cancelled check is not green. If Composer 2.5 cannot be launched, stop and ask. Do not substitute a model. Verified 2026-10-30 on `7625d02`: job `macos` is `.github/workflows/test.yml` (`macos-latest`, timeout 20 minutes) and runs `tests/macos-smoke.sh`; job `CodeQL (Swift)` is `.github/workflows/codeql.yml` (`macos-26`, timeout 30 minutes). These phases may add steps to the `macos` job. They do not add a Linux CI job and they do not edit `.github/workflows/codeql.yml`. PR #6, merged 2026-10-30, deletes `.github/scripts/protect-main-branch.sh` and `.github/workflows/protect-main.yml`, and it replaces the CodeQL bullet in `AGENTS.md`. Bootstrap phases must not recreate that script or rewrite that paragraph. They also must not recreate the deleted workflow.

**D14 — Step marks are machine-checked.** Bullets start with `- Manual:` or `- Script:`. Caveats, including FileVault and `fdesetup authrestart`, are paragraphs. The catalog is the list a review can diff against the runbook.

## 8. Open questions

Q1. **Rename the GitHub repo to `roger-bootstrap`?** Phases keep `nikolaybotev/backup-folder` until the maintainer says yes. The binary stays `backup-folder` either way.

Q2. **Turn Remote Login (SSH) on, or leave it off?** The setup doc does not enable it.

Q3. **Which energy settings match always-on** (avoid sleep, start after power failure)? The doc states the goal and does not invent the clicks.

Q4. **What should the setup doc say about the deployment Mac self-hosted runner** beyond installing Cursor and signing in? Mac builds and tests for this repo stay on the GitHub-hosted `macos` and `CodeQL (Swift)` jobs. The runner is not a build machine for this repo.

Q5. **What else must a restore install** (Xcode, Command Line Tools, other LaunchAgents, other apps)? The hub does not install them until the maintainer names them. Released binaries are how these tools get onto the Mac, so a restore does not need a local Swift compile for `backup-folder`.

Q6. **Add Apple Developer ID notarization later?** Attestations are the signature the install script checks. They do not satisfy Gatekeeper. Until this is answered, the manual prompt step covers unidentified-developer dialogs, and the install script does not strip the quarantine attribute.
