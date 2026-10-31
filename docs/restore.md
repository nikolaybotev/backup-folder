# Restore

Use [`setup.md`](setup.md) for a **new Mac**. Use this doc when files are restored onto an **existing** Mac that already went through setup once.

Run these steps on your Mac. CI does not. Give a heads-up before re-installing agents or binaries on the Mac.

A restore installs nothing beyond the bootstrap repo plus the Grok Bot app, the Cursor app, the 1Password app and the 1Password CLI (`op`), Homebrew with `gh`, `git`, and GnuPG via the separate dev bootstrap, and `wireguard-tools` and `wireguard-go` from Homebrew, plus the existing LaunchAgent repeat and the `scripts/install-tools.sh` re-run. The LaunchAgent repeat is the WireGuard daemon and the backup-folder and drop-box-watcher agents when their plists are missing. The re-run is for a pinned tool whose `~/bin` binary is missing or should move to the pin. It does not install Xcode. It does not add any other LaunchAgent. Agents who build this repo are not operators of the machine and do not install these items.

## Steps

- Manual: Restore files from the Time Machine volume named in setup, or from the **home-mirrored** snapshot directories under `~/Backups` (`~/Backups` plus each source path relative to the home directory), as needed.
- Manual: iCloud repopulates Desktop and Documents. **Keep Downloaded** still applies to those two folders.
- Manual: Re-fill `/opt/homebrew/etc/wireguard/wg0.conf` and the watcher [`config.toml`](setup.md) from 1Password. Keep modes `600` and `0600` respectively.
- Script: When LaunchDaemon or LaunchAgent plists are missing, repeat the WireGuard daemon install and the LaunchAgent install steps from [`setup.md`](setup.md) (WireGuard plist, backup-folder agents, and the drop-box-watcher agent from [`launchd/drop-box-watcher.plist.template`](../launchd/drop-box-watcher.plist.template)).
- Script: Re-run [`scripts/install-tools.sh`](../scripts/install-tools.sh) for any pinned tool whose `~/bin` binary is missing or should move to the pin in `~/.config/backup-folder/pins.txt` (see [`pins.txt.example`](../pins.txt.example)).
- Manual: Accept Desktop and Documents privacy prompts for any binary that was replaced.
- Manual: If the hardware changed: update the machine id, file-access policy, and shared memory that other tools keep for this Mac. Re-check the Drop Box dispatcher routine and the daily backup health check routine. This is bot-side work, not a command on the Mac, and this repo does not perform it.
