# intent.md — Drop Box watcher

| | |
|---|---|
| Author | Maintainer (relayed by coordinator) |
| Captured | 2026-10-30 |
| Status | Draft |
| Stage | 1 · Plan |
| Feeds | [spec.md](spec.md) → [plan.md](plan.md) |

## Problem

The Grok Bot on the deployment Mac notices a file in the iCloud-synced "~/Desktop/Drop Box" only on its hourly poll. A file can sit in the folder until that poll.

## Proposed outcome

Once a dropped file is fully present on the Mac, the bot wakes within seconds. The bot still lists the folder and moves each file. The new tool only sends the wake-up.

## Affected users and systems

- **Users:** The operator, who drops files into the folder, and the Grok Bot that handles them.
- **Systems:** the backup-folder repository, a per-user LaunchAgent in the operator login session, iCloud Drive for Desktop, and the bot's routine webhook.

## Constraints and principles

- Readiness comes from an Apple file-state signal. There is no settle delay and no readiness timer.
- The watcher never moves, renames, edits, or deletes a file.
- The webhook URL, the webhook secret, and the watched folder live in a config file outside the repository. The repository ships an example with placeholders.
- Agents do not install the tool on the deployment Mac.
- The snapshot tool stays as it is. This change does not fix snapshot bugs.

## Open questions (carried into spec.md)

1. Which Authorization header does the Grok Bot routine webhook expect where a public document says?
2. Which FSEvents flags and NSFilePresenter callbacks fire on the deployment Mac when a placeholder becomes current, and when a file is renamed into the folder?

## Original prompt (verbatim)

````
New intent from the maintainer (relayed by the coordinator): live Drop Box notifications.
Take it through spec, plan, build and review to the end. Decide yourself wherever you can; send maintainer-only questions to the coordinator, who relays them, and keep going meanwhile.

Goal: when the operator drops a file into the iCloud-synced "~/Desktop/Drop Box" on deployment Mac, The Grok Bot on the deployment Mac should be woken within seconds (today it polls hourly, then moves each file into the owning bot's folder).

Build: a new Swift command-line watcher in github.com/nikolaybotev/backup-folder (repo rename can come later), run as a per-user LaunchAgent on the deployment Mac (macOS, Apple silicon). It watches the folder with macOS file system notifications and, once a dropped file is fully present locally, POSTs to a Grok Bot routine webhook.

Requirements:
1. Research first, no guessing: is there an official macOS API that reports when an iCloud Drive file has finished syncing/downloading locally (NSMetadataQuery ubiquitous item attributes, URLResourceValues ubiquitousItem* keys, NSFilePresenter/NSFileCoordinator, FileProvider)? Note: Desktop & Documents in iCloud, not an app container. Cite Apple docs; size-stability debounce only as a justified fallback.
2. Webhook URL, webhook secret and watched folder come from a plain config file referenced by the LaunchAgent plist (no Keychain, maintainer decision), kept outside the repo with 0600 perms. Ship an example config only. Use the Grok Bot routine webhook request/header format if documented; otherwise make the auth header configurable and ask the deployment Mac.
3. Notify only: never move, rename, edit or delete files. Ignore .DS_Store and hidden/temp files. Log to a file. Webhook delivery goes through a single Swift actor (WebhookNotifier), the only code that talks to the webhook; see the Webhook delivery section.
4. Payload is a nudge (event time plus ready file names); The bot relists the folder itself.
5. Ship install docs and a LaunchAgent plist (com.nikolay.* label, RunAtLoad/KeepAlive). Do not install on the deployment Mac; the operator installs it. One-time macOS Desktop-access prompt is fine.
6. Follow the repo's CI/CD, CodeQL and branch protection; tests where practical (config parsing, debounce, readiness via a mockable interface).
7. Cursor models only: Grok 4.7 High for coordination/spec/plan/review, Composer 2.5 for build.

Report to the coordinator when merged: PR link, chosen API and why, config format, install steps.

Locations (proposed by the coordinator; adjust if there is a better macOS convention): config at ~/.config/drop-box-watcher/config.toml (0600, outside iCloud Desktop/Documents and outside ~/Backups), passed to the watcher by the LaunchAgent plist; log at ~/Library/Logs/drop-box-watcher.log.

Config format (maintainer decision): TOML at ~/.config/drop-box-watcher/config.toml. Starting sample for the operator (refine names as needed, keep it this simple):
watch_folder = "/Users/USER/Desktop/Drop Box"
[webhook] url = "...", key = "..."  (from the Grok Bot routine panel, which also shows an Authorization header format; send the key the way that header expects)
[behavior] ignore = [".DS_Store", ".*", "*.icloud", "*.download", "*.crdownload", "*.part"]
[log] path = "/Users/USER/Library/Logs/drop-box-watcher.log"

No fixed settle delays or timers (Firm rule): readiness must come from an Apple API signal, not a wait. Settled design below.

## Readiness design (settled; no timers, no settle delay)
Apple has no single push event that says "iCloud sync complete" for an unsandboxed tool watching ~/Desktop. The documented way is an event trigger plus a check of per-file iCloud state:
1. FSEvents stream (FSEventStreamCreate, kFSEventStreamCreateFlagFileEvents) on the watch folder. Use FSEvents latency 0 (no batching wait).
2. On each created/modified/renamed/xattr/inode-meta event, read URLResourceValues: isUbiquitousItem, ubiquitousItemDownloadingStatus (needs no entitlement).
3. If ubiquitous and not .current: FileManager.startDownloadingUbiquitousItem(at:), then wait for the next FSEvent and re-check.
4. When .current (or not ubiquitous): coordinated read with NSFileCoordinator (waits for any coordinated writer and makes sure the file is downloaded), then POST the webhook once per file (keyed by path+inode+size).
5. Ignore temp names (.DS_Store, .*, *.icloud, *.download, *.crdownload, *.part); browsers rename into place when done, and that rename triggers the post.
Don't use NSMetadataQuery ubiquitous scopes (they need an iCloud container entitlement and don't cover Desktop & Documents), File Provider (it's for providers), or brctl/bird (private; debugging only).
Verify on the deployment Mac and record the results in the PR: which FSEvents flags fire when a placeholder turns into a full file, and whether Finder and AirDrop writes are coordinated.
Sources: developer.apple.com/documentation/foundation/urlresourcevalues/ubiquitousitemdownloadingstatus, .../coreservices/file_system_events, .../foundation/nsfilecoordinator, .../foundation/filemanager/startdownloadingubiquitousitem(at:), developer.apple.com/forums/thread/87235.
Alternative trigger to test: an NSFilePresenter registered on the watch folder (presentedSubitemDidChange). If on-device testing shows its callbacks catch iCloud materialization more reliably than FSEvents, use it as the trigger or alongside FSEvents. Either way, the status check and coordinated read stay the same.

## iCloud log trace from the deployment Mac (10/29/2026, macOS 27.2, `brctl log -z -b -f --last 14h`)
What the logs show and how it maps to the Swift API (the first mapping is from Apple's docs; the others are inferred from the logs and should be confirmed in your on-device test):
- `dls` (dataless placeholder) flag → ubiquitousItemDownloadingStatus `.notDownloaded`.
- `fetch-content … why:materialization` job in flight → ubiquitousItemIsDownloading == true.
- Download done → `update-item … diffs:dataless`, then `FS snapshot mutation … (no dls) diffs:content|dataless` → `.current`.
- `ul:uploading` / `ul:uploaded` → ubiquitousItemIsUploading / ubiquitousItemIsUploaded.
- "Excluded From Sync Due To Filename" (BRCloudDocsErrorDomain 83, seen when the folder was named "Dropbox") → ubiquitousItemIsExcludedFromSync.
- Moves and renames inside iCloud keep the item ID (`diffs:filename|parentID|structure`); a move out of an excluded folder shows up as a brand-new item.
Rules for the watcher:
- A file is ready when it's `.current` and not downloading. Never act on `.downloaded`, which means a stale local copy.
- If it's `.notDownloaded`, call startDownloadingUbiquitousItem and re-check on the next change event.
- Don't wait for isUploaded. Files dropped on the deployment Mac itself start out `.current` but not yet uploaded, and moving them doesn't need the upload to finish.
- At startup, log an error if the watch folder reports ubiquitousItemIsExcludedFromSync.
- `brctl status` and `brctl dump` return Access denied (error 141). Logs shorten names to first letter, letter count and last letter (for example, `D{6}x` = "Drop Box").
- Not observed yet: a real cloud arrival into Drop Box from another device. Test one in the PR.
Excerpt and a read-only Swift state checker are on the bot host at /workspace/brctl-trace/ (dropbox_trace_2026-10-29_excerpt.txt, ubq_state.swift); include them when sending the brief.

## Live cloud-arrival test on the deployment Mac (10/29/2026, 6:41 PM PDT)
Confirmed: `dls` = .notDownloaded, `fetch-content why:materialization` in flight = isDownloading, then `diffs:dataless` with `dls` cleared = .current. `.downloaded` never appeared.
Two kinds of arrival, and the watcher must handle both:
1. A brand-new file from another device (a 10.5 MB JPG):
   - A placeholder appears under its final name and full size, with no data (.notDownloaded).
   - iCloud fetches it on its own.
   - 2.3 seconds later, the content and an xattr land in place on the same inode, and the file becomes .current.
   - Never act on the create event. Act when the file reads .current, after an in-place content or xattr change on the existing file.
2. A file moved in iCloud from another folder into Drop Box: there's no download at all. It shows up as a rename into the folder (FSEvents ItemRenamed), and the file is already .current. The watcher must treat a rename into the folder as an arrival.
Local `mv` keeps the iCloud item ID and inode (`diffs:parentID|structure`, then a brief re-upload).
Still to confirm on the deployment Mac: the exact FSEvents flags or NSFilePresenter callback that fires when a placeholder finishes downloading.
Excerpt is on the bot host at /workspace/brctl-trace/cloud_arrival_2026-10-29_excerpt.txt.

## Head start: Google AI prototype (reference only)
The maintainer got prototype Swift from Google AI Mode. It's saved verbatim at /workspace/briefs/google-ai-prototype.swift on the bot host (4 snippets; include it when sending the brief). Reuse what fits, but this brief's design and rules win wherever they conflict. The cleaned core below already applies the changes.
What it does: an NSFilePresenter on a folder, a serial OperationQueue, a coordinated read in presentedSubitemDidChange, then a switch on ubiquitousItemDownloadingStatus. `.notDownloaded`/`.downloaded` call startDownloadingUbiquitousItem, `.current` prints success, and a boot scan enumerates the folder first. It has no timers, sleeps, NSMetadataQuery, Keychain or force unwraps. It also has no webhook POST, ignore list, dedup, logging, config or plist.
Keep:
- The NSFilePresenter skeleton: presentedItemURL, a serial presentedItemOperationQueue, addFilePresenter/removeFilePresenter, and a strong top-level reference.
- The status switch: `.current` = ready; `.notDownloaded` and `.downloaded` (outdated) = startDownloadingUbiquitousItem, then wait for the next event. No retry or timeout timers; the next event re-checks.
- The startup scan, which catches files that arrived while the watcher was down. It sends one nudge for everything that's ready, not one per file.
Change:
- Path: use the TOML watch_folder (~/Desktop/Drop Box, iCloud Desktop & Documents), not ~/Library/Mobile Documents/com~apple~CloudDocs/..., and never url(forUbiquityContainerIdentifier:), which needs an entitlement. Snippet 2 also lets `monitor` go out of scope right away.
- Order: check status first and coordinate only once the file is `.current`. The prototype does a coordinated read before checking, which on a placeholder forces a download and blocks the serial queue. Log coordination errors (snippets 3–4 drop them).
- Arrivals: also implement presentedSubitemDidAppear(at:) and presentedSubitem(at:didMoveTo:). Run FSEvents alongside the presenter (or as a fallback). Every event only triggers a state re-check, so a create event on a placeholder reads `.notDownloaded` and is never acted on.
- On-device test (record it in the PR): does presentedSubitemDidChange fire (a) for a cloud move into the folder (a rename that's already `.current`) and (b) when a placeholder materializes in place? Which FSEvents flags fire for each? Keep whichever trigger catches both, or keep both.
- Scan only the folder root (no recursion), apply the ignore list, and skip directories.
- Dedup per file (path + inode + size) so the presenter and FSEvents together send one nudge per file.
- Replace RunLoop.current.run() with dispatchMain(), since the presenter runs on its queue and FSEvents on a dispatch queue. Replace print with the [log] file and never log the key.
- Add the URLSession POST nudge, the TOML config, the excluded-from-sync startup check, and the LaunchAgent plist. None of these are in the prototype.
- Decline its offer of "retry/timeout logic" for stuck downloads; that would be a timer.
```swift
import Foundation
import CoreServices

/// Readiness from Apple's per-file iCloud state only. No timers.
func isReady(_ url: URL, ignored: (String) -> Bool, log: (String) -> Void) -> Bool {
    guard !ignored(url.lastPathComponent),
          let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isUbiquitousItemKey,
                  .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey]),
          v.isRegularFile == true else { return false }            // gone, dir, or ignored
    guard v.isUbiquitousItem == true else { return true }          // plain local file
    if v.ubiquitousItemDownloadingStatus == .current, v.ubiquitousItemIsDownloading != true { return true }
    // .notDownloaded or .downloaded (outdated): ask iCloud for it; the next event re-checks.
    do { try FileManager.default.startDownloadingUbiquitousItem(at: url) }
    catch { log("startDownloading \(url.lastPathComponent): \(error)") }
    return false
}

final class DropBoxWatcher: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let q = OperationQueue(); q.name = "drop-box-watcher"; q.maxConcurrentOperationCount = 1; return q
    }()
    private let folder: URL
    private let ignored: (String) -> Bool
    private let notify: ([String]) -> Void   // one POST per call: {event_time, files}
    private let log: (String) -> Void
    private var nudged = Set<String>()       // "path|inode|size"; prune keys whose file is gone
    private var stream: FSEventStreamRef?

    init(folder: URL, ignored: @escaping (String) -> Bool,
         notify: @escaping ([String]) -> Void, log: @escaping (String) -> Void) {
        self.folder = folder.standardizedFileURL; presentedItemURL = self.folder
        self.ignored = ignored; self.notify = notify; self.log = log
        super.init()
    }

    func start() {
        if (try? folder.resourceValues(forKeys: [.ubiquitousItemIsExcludedFromSyncKey]))?
            .ubiquitousItemIsExcludedFromSync == true { log("ERROR: watch folder is excluded from iCloud sync") }
        NSFileCoordinator.addFilePresenter(self)
        startFSEvents()
        presentedItemOperationQueue.addOperation { self.scan() }   // startup scan
    }

    /// Startup scan: root only, ONE nudge for everything already ready.
    func scan() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        handle(urls)
    }

    /// Every trigger lands here (on the serial queue) and only re-checks state.
    func handle(_ urls: [URL]) {
        let ready = urls.filter { $0.deletingLastPathComponent().standardizedFileURL == folder }
                        .compactMap(claimIfReady)
        if !ready.isEmpty { notify(ready) }
    }

    private func claimIfReady(_ url: URL) -> String? {
        guard isReady(url, ignored: ignored, log: log),
              let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let ino = a[.systemFileNumber], let size = a[.size] else { return nil }
        let key = "\(url.path)|\(ino)|\(size)"
        guard !nudged.contains(key) else { return nil }
        var err: NSError?; var ok = false
        NSFileCoordinator(filePresenter: self).coordinate(readingItemAt: url, options: [], error: &err) { _ in ok = true }
        guard ok else { log("coordinate \(url.lastPathComponent): \(String(describing: err))"); return nil }
        nudged.insert(key)
        return url.lastPathComponent
    }

    // NSFilePresenter triggers. ON-DEVICE TEST: which fire for a cloud move-in and for materialization?
    func presentedSubitemDidChange(at url: URL) { handle([url]) }
    func presentedSubitemDidAppear(at url: URL) { handle([url]) }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { handle([newURL]) }

    // FSEvents alongside the presenter (or as a fallback). Latency 0: delivery only, no settle wait.
    private func startFSEvents() {
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<DropBoxWatcher>.fromOpaque(info).takeUnretainedValue()
            let urls = ((unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []).map { URL(fileURLWithPath: $0) }
            me.presentedItemOperationQueue.addOperation { me.handle(urls) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents |
                                             kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, cb, &ctx, [folder.path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0, flags)
        else { log("ERROR: FSEventStreamCreate failed"); return }
        FSEventStreamSetDispatchQueue(s, DispatchQueue(label: "drop-box-watcher.fsevents"))
        FSEventStreamStart(s); stream = s
    }
}

/// Nudge only; The bot relists the folder. Never log the key.
func postNudge(_ files: [String], url: URL, key: String, log: @escaping (String) -> Void) {
    var req = URLRequest(url: url); req.httpMethod = "POST"
    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") // CHANGE: match the routine panel's header format
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject:
        ["event_time": ISO8601DateFormatter().string(from: Date()), "files": files])
    URLSession.shared.dataTask(with: req) { _, resp, err in
        log("POST \(files.count) file(s): \((resp as? HTTPURLResponse)?.statusCode ?? -1) \(err.map { "\($0)" } ?? "")")
    }.resume()
}

// Entry point: load TOML (watch_folder, [webhook] url/key, [behavior] ignore, [log] path), then:
// let watcher = DropBoxWatcher(folder: cfg.watchFolder, ignored: cfg.matchesIgnore,
//     notify: { postNudge($0, url: cfg.webhookURL, key: cfg.webhookKey, log: logger) }, log: logger)
// watcher.start()   // top-level let keeps a strong reference for the process lifetime
// dispatchMain()    // CHANGE from the prototype's RunLoop.current.run()
```

## Webhook delivery (one actor)
- All readiness signals (each file that reaches .current, renames into the folder, and the startup scan) are sent to one `actor WebhookNotifier`, the only code that talks to the webhook. It fully controls timing, frequency and retries.
- No concurrent calls: at most one POST in flight or one retry loop at a time. New events that arrive during a POST or a backoff wait are merged into a pending set (deduped by path+inode+size) and never start a second call.
- Merging: when a new event arrives during a backoff wait, cancel the wait and retry right away with the merged set. A later success sends everything pending.
- Retries: exponential backoff (for example 1s, 2s, 4s and so on) capped at 30 seconds, retrying indefinitely until it succeeds. No cutoff after an hour, and the 11 PM sweep is the final backstop. Log each failure, but rate-limit repeated identical errors.
- Success means 2xx. On success, clear the delivered items from the pending set. Events that arrived during that POST start a new send right away.
- The payload is only a nudge (The bot relists the folder), so merging is safe. The payload can list the merged file names for logging, but the bot does not rely on them.
- Readiness itself never waits. These timers exist only for retrying a failed delivery.
- This section replaces the simple POST in the Google head-start code. Route that code through WebhookNotifier.

## Install location and session (decided 2026-10-29)
- Install the watcher binary at ~/bin/drop-box-watcher. The operator will also move backup-folder from ~/Backups/bin to ~/bin in the same install window, so there's one round of macOS access prompts. Install docs and the plist should use ~/bin paths.
- It's a per-user LaunchAgent, not a LaunchDaemon. iCloud only syncs in a logged-in session, and The deployment Mac keeps FileVault on with no auto-login. After a reboot the watcher starts at login, and its startup scan catches anything that arrived in the meantime.
````
