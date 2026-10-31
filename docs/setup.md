# Setup

Run this checklist on your Mac. GitHub Actions and cloud agents do not run these steps. Give a heads-up before anything in this doc is installed or changed on the Mac.

## Steps

- Manual: Apple ID / iCloud sign-in during account setup. Turn on iCloud Drive with Desktop & Documents.
- Manual: In Finder, set Desktop and Documents to **Keep Downloaded**, whole folders, so tools and backups see local files.
- Manual: Turn FileVault on. Do not enable auto-login. After a reboot, log in once via Screen Sharing before iCloud syncs.
- Manual: Turn Screen Sharing on.
- Manual: Remote Login (SSH) is not turned on by this doc. Whether to enable it stays open (Q2).
- Manual: Energy: the machine should avoid sleep and start after power failure. The exact System Settings clicks stay open (Q3); this doc states the goal only.
- Manual: Choose a computer name. macOS publishes that name plus `.local`.
- Script: Run the general bootstrap, with its confirm prompt: `sh -c "$(curl -fsSL https://raw.github.com/nikolaybotev/bootstrap/main/install.sh)"`. On a **fresh Mac**, that curl alone is not enough: `install.Darwin.sh` is `sh -e` and calls `jq` before it opens the Homebrew and mise pages, and a fresh Mac does not ship `jq`, so the script can exit before those pages open. Later updates use `~/.bootstrap/update`. This repo does not copy `nikolaybotev/bootstrap`.
- Manual: Finish the Homebrew and mise installs that the bootstrap opens in a browser (for example the pages at brew.sh and mise.en.dev). See the bootstrap repo for details.
- Script: `brew install wireguard-tools wireguard-go`.
- Script: `brew install gh git gnupg pinentry`.
- Manual: Run `gh auth login` for the GitHub account that administers the Mac.
- Manual: Generate a new GPG signing key on the new hardware, add it to GitHub, and configure it so agent commits unlock without a prompt. Store passphrases in 1Password. This doc does not record any previous key id (see spec D12).
- Manual: Set `user.signingkey` in the gitconfig the bootstrap wrote. That gitconfig already sets `commit.gpgsign` and `tag.gpgsign`. This repo does not ship a gitconfig.
- Manual: Install the Grok Bot app and sign in. Register this Mac. Grant Files & Folders for Desktop and Documents only. Leave Downloads, iCloud Drive, and Removable Volumes off.
- Manual: Install Cursor and sign in.
- Manual: A **self-hosted** runner is named as a step and left unfinished. This doc does not invent a runner token, label, or install command.
- Manual: Install the 1Password app, sign in, and install the 1Password CLI (`op`).
- Manual: Install iStat Menus and MacVim.
- Manual: Fill [`launchd/wg0.conf.template`](../launchd/wg0.conf.template) from 1Password into `/opt/homebrew/etc/wireguard/wg0.conf` using the placeholder tokens (`[PRIVATE_KEY]`, `[INTERFACE_ADDRESS]`, `[DNS]`, `[SERVER_PUBLIC_KEY]`, `[PRESHARED_KEY]`, `[ALLOWED_IPS]`, `[SERVER_PUBLIC_IP]`, `[PORT]`). Run `chmod 600` on the filled file. Do not commit the filled `wg0.conf`.
- Script: Copy [`launchd/com.wireguard.wg0.plist.template`](../launchd/com.wireguard.wg0.plist.template) to `/Library/LaunchDaemons/com.wireguard.wg0.plist` with `sudo`, then `sudo chown root:wheel` and `sudo chmod 644` that plist. Enable and load with `sudo launchctl enable system/com.wireguard.wg0` and `sudo launchctl bootstrap system /Library/LaunchDaemons/com.wireguard.wg0.plist`.
- Script: Check WireGuard with `sudo wg` and `sudo launchctl print system/com.wireguard.wg0`. To stop the daemon, use `sudo launchctl bootout system/com.wireguard.wg0`.
- Manual: If the WireGuard GUI app is installed, turn off On-Demand and delete its tunnel. It keeps keys in the login keychain and fights the daemon. Do not use `sudo brew services start wireguard-tools`.
- Manual: Attach the external SSD as APFS: volume `External`, and a Time Machine volume you name with an eight-hundred-gigabyte quota. Time Machine backs up the Mac. Keep assistants off `External`. This step needs a heads-up before the disk is touched.
- Manual: Point Time Machine at the Time Machine volume you named.
- Script: Run [`scripts/install-tools.sh`](../scripts/install-tools.sh) once `~/.config/backup-folder/pins.txt` names real release tags (copy [`pins.txt.example`](../pins.txt.example) to that path first). Until then the script skips unpinned tools. Binaries install into `~/bin`.
- Manual: One-time macOS code signing for release builds and CI: follow [nikolaybotev/code-signing](https://github.com/nikolaybotev/code-signing) (identity **Nikolay Botev Code Signing**; repository secrets `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD`). Do not paste a `.p12` body or password into git.
- Manual: Accept the macOS Desktop and Documents privacy prompts for each new binary. Repeat after every new binary. Unidentified-developer prompts are part of this step until Apple notarization is decided (Q6).
- Script: Run [`scripts/ensure-backup-dirs.sh`](../scripts/ensure-backup-dirs.sh) with the absolute **home-mirrored** snapshot directories. Each directory is `~/Backups` plus the source path relative to the home directory. Pass those paths as arguments at install time; source-folder names stay out of git. The script creates directories and does not delete anything.
- Script: For each backup source, copy [`launchd/backup-folder.plist.template`](../launchd/backup-folder.plist.template) into `~/Library/LaunchAgents/`, replace `NAME`, `USER` (the output of `id -un`), `/ABS/SOURCE`, and `/ABS/BACKUP-DIR`, and load with `launchctl bootstrap gui/$(id -u)` on that plist. The template binary path is `/Users/USER/bin/backup-folder` because launchd does not expand `$HOME`. The label pattern is `com.nikolay.backup.NAME`. Choose source folders at install time; do not write personal folder names in git.
- Script: Install the drop-box-watcher LaunchAgent from [`launchd/drop-box-watcher.plist.template`](../launchd/drop-box-watcher.plist.template). Replace each `/ABS/PATH/TO/HOME` placeholder in the template with your absolute home path (`$HOME` on a normal Mac is `/Users/$(id -un)`; launchd needs the absolute path). Point the agent at `~/bin/drop-box-watcher`. The label is `com.nikolay.drop-box-watcher`.
- Manual: Write `~/.config/drop-box-watcher/config.toml` with mode `0600`. The webhook URL and key come from 1Password (`op read` or paste). The schema belongs to the drop-box-watcher intent. Do not commit that file.
- Manual: Create `~/Desktop/Drop Box` (the folder name includes a space).

## Caveats

With FileVault, nothing—including the VPN—starts on a cold boot until the disk is unlocked. For a planned restart, `sudo fdesetup authrestart` brings the VPN and Screen Sharing back unattended. After a power loss, someone unlocks the Mac locally. The watcher is a per-user LaunchAgent, so it starts at login, and its own startup scan covers files that arrived while it was down. That scan is specified by the drop-box-watcher intent, not here.
