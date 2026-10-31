# One backup job

One LaunchAgent, label `com.nikolaybotev.backup`, backs up every folder in its config. Adding a folder is a `[[folder]]` entry, not another agent.

Keep the same destination directories. Each destination still has `backup.log`, the same snapshot names, and the same retention, so history already on disk still applies.

Copy [`backup-folder.example.toml`](../backup-folder.example.toml) to `~/.config/backup-folder/config.toml`, set mode `0600`, and replace the placeholders. `pins.txt` in that directory is a different file.

## From one agent per folder

Unload each agent whose label is `com.nikolaybotev.backup.NAME`, then load `com.nikolaybotev.backup`. If an old agent and this one both run against one destination, one of them logs `skipped; dest busy`.

A person runs these steps on the Mac.

1. Copy [`launchd/backup-folder.plist.template`](../launchd/backup-folder.plist.template) into `~/Library/LaunchAgents/com.nikolaybotev.backup.plist`. Replace each `/ABS/PATH/TO/HOME` placeholder with the absolute home path. launchd does not expand `$HOME`.
2. Unload each existing per-folder agent: `launchctl bootout gui/$(id -u)` with that agent's plist path.
3. Load the new agent: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nikolaybotev.backup.plist`.
