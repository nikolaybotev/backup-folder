import CoreServices
import Foundation

/// Watches one folder: readiness, claims, and enqueue to `WebhookNotifier` (FR5–FR10).
final class DropBoxFolderWatcher: NSObject, NSFilePresenter {
    var presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "drop-box-watcher"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    /// Path from config (may be a symlink); used for `NSFilePresenter`.
    private var watchFolderConfigured: URL
    /// Resolved directory path; used for FSEvents and direct-child checks.
    private var watchFolderURL: URL
    private var ignorePatterns: [String]
    private var notifier: WebhookNotifier
    private var log: OperationalLog
    private var claimed: Set<WebhookClaim> = []
    private var presenterGeneration = 0
    private var fseventStream: FSEventStreamRef?
    private let fseventsQueue = DispatchQueue(label: "drop-box-watcher.fsevents")
    /// Separate coordinator for claim reads (avoid re-entrant coordination on the presenter queue).
    private let claimCoordinator = NSFileCoordinator()

    init(
        watchFolderURL: URL,
        ignorePatterns: [String],
        notifier: WebhookNotifier,
        log: OperationalLog
    ) {
        self.watchFolderConfigured = watchFolderURL.standardizedFileURL
        self.watchFolderURL = watchFolderURL.resolvingSymlinksInPath().standardizedFileURL
        self.presentedItemURL = self.watchFolderConfigured
        self.ignorePatterns = ignorePatterns
        self.notifier = notifier
        self.log = log
        super.init()
    }

    deinit {
        if let fseventStream {
            FSEventStreamStop(fseventStream)
            FSEventStreamInvalidate(fseventStream)
            FSEventStreamRelease(fseventStream)
        }
        NSFileCoordinator.removeFilePresenter(self)
    }

    func start() {
        log.writeLine("started watch_folder=\(watchFolderURL.path)")
        startFSEvents()
    }

    func scheduleRegister() {
        let generation = presenterGeneration
        DispatchQueue.main.async { [self] in
            guard generation == self.presenterGeneration else { return }
            self.registerOnMainRunLoop()
        }
    }

    /// Stops the current folder watch, then starts the new folder, ignore list, notifier, and log.
    /// In-flight webhook posts stay on the notifier they already use.
    func retarget(folderURL: URL, ignorePatterns: [String], notifier: WebhookNotifier, log: OperationalLog) {
        presentedItemOperationQueue.addOperation { [self] in
            let previousFolder = self.watchFolderURL.path
            self.invalidateFSEvents(wait: true)
            NSFileCoordinator.removeFilePresenter(self)
            self.watchFolderConfigured = folderURL.standardizedFileURL
            self.watchFolderURL = folderURL.resolvingSymlinksInPath().standardizedFileURL
            self.presentedItemURL = self.watchFolderConfigured
            self.ignorePatterns = ignorePatterns
            self.notifier = notifier
            self.log = log
            if self.watchFolderURL.path != previousFolder {
                self.claimed.removeAll()
            }
            self.presenterGeneration += 1
            self.start()
            self.scheduleRegister()
        }
    }

    func registerOnMainRunLoop() {
        log.writeLine("registering file presenter")
        if let excluded = try? watchFolderURL.resourceValues(forKeys: [.ubiquitousItemIsExcludedFromSyncKey]),
           excluded.ubiquitousItemIsExcludedFromSync == true {
            log.writeLine("ERROR: watch folder is excluded from iCloud sync")
        }
        NSFileCoordinator.addFilePresenter(self)
        log.writeLine("registered file presenter")
        presentedItemOperationQueue.addOperation { [self] in
            self.startupScan()
        }
    }

    private func filesystemEqual(_ a: URL, _ b: URL) -> Bool {
        let pa = a.resolvingSymlinksInPath().standardizedFileURL.path
        let pb = b.resolvingSymlinksInPath().standardizedFileURL.path
        if pa == pb { return true }
        func stripPrivatePrefix(_ path: String) -> String {
            if path.hasPrefix("/private") { return String(path.dropFirst("/private".count)) }
            return path
        }
        return stripPrivatePrefix(pa) == stripPrivatePrefix(pb)
    }

    private func isDirectChild(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        return filesystemEqual(parent, watchFolderURL)
    }

    private func entryKind(for url: URL) -> PathEntryKind {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return .other
        }
        if values.isSymbolicLink == true { return .symbolicLink }
        if values.isDirectory == true { return .directory }
        if values.isRegularFile == true { return .regularFile }
        return .other
    }

    private func ubiquitousState(for url: URL) -> (isUbiquitous: Bool, status: UbiquitousDownloadStatus, downloadInFlight: Bool) {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return (false, .missing, false)
        }
        let isUbiquitous = values.isUbiquitousItem == true
        let downloadInFlight = values.ubiquitousItemIsDownloading == true
        let status: UbiquitousDownloadStatus
        switch values.ubiquitousItemDownloadingStatus {
        case .some(.notDownloaded):
            status = .notDownloaded
        case .some(.downloaded):
            status = .downloaded
        case .some(.current):
            status = .current
        default:
            status = .missing
        }
        return (isUbiquitous, status, downloadInFlight)
    }

    private func dropClaims(forStandardizedPath path: String) {
        claimed = claimed.filter { $0.standardizedPath != path }
    }

    private func pruneClaimsForMissingPaths() {
        claimed = claimed.filter { FileManager.default.fileExists(atPath: $0.standardizedPath) }
    }

    private func recheck(_ url: URL) -> WebhookClaim? {
        let standardized = url.resolvingSymlinksInPath().standardizedFileURL
        let path = standardized.path
        guard isDirectChild(url) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else {
            dropClaims(forStandardizedPath: path)
            return nil
        }

        let fileName = standardized.lastPathComponent
        let kind = entryKind(for: standardized)
        let (isUbiquitous, ubiStatus, inFlight) = ubiquitousState(for: standardized)
        let decision = readinessDecision(
            fileName: fileName,
            ignorePatterns: ignorePatterns,
            entryKind: kind,
            isUbiquitous: isUbiquitous,
            ubiquitousStatus: ubiStatus,
            ubiquitousDownloadInFlight: inFlight
        )

        switch decision {
        case .skip:
            return nil
        case .requestDownload:
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: standardized)
            } catch {
                log.writeLine("startDownloadingUbiquitousItem \(fileName): \(error.localizedDescription)")
            }
            return nil
        case .ready:
            return claimIfReady(standardized)
        }
    }

    private func claimIfReady(_ url: URL) -> WebhookClaim? {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        var coordinationError: NSError?
        var accessorRan = false
        claimCoordinator.coordinate(
            readingItemAt: url,
            options: [.withoutChanges],
            error: &coordinationError
        ) { _ in
            accessorRan = true
        }
        guard accessorRan else {
            let detail = coordinationError?.localizedDescription ?? "unknown"
            log.writeLine("coordinate reading \(url.lastPathComponent): \(detail)")
            return nil
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let inodeNum = attrs[.systemFileNumber] as? NSNumber,
              let sizeNum = attrs[.size] as? NSNumber
        else {
            return nil
        }
        let claim = WebhookClaim(
            standardizedPath: path,
            inode: inodeNum.uint64Value,
            size: sizeNum.uint64Value
        )
        if claimed.contains(claim) {
            return nil
        }
        claimed.insert(claim)
        return claim
    }

    private func enqueueClaims(_ batch: [WebhookClaim]) {
        guard !batch.isEmpty else { return }
        let names = batch.map(\.fileName).joined(separator: ",")
        log.writeLine("webhook enqueue files=\(names)")
        let claims = batch
        DispatchQueue.main.async {
            Task { await self.notifier.submit(claims: claims) }
        }
    }

    private func handleURLs(_ urls: [URL]) {
        pruneClaimsForMissingPaths()
        var batch: [WebhookClaim] = []
        for url in urls {
            if let claim = recheck(url) {
                batch.append(claim)
            }
        }
        enqueueClaims(batch)
    }

    private func startupScan() {
        pruneClaimsForMissingPaths()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: watchFolderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var batch: [WebhookClaim] = []
        for url in urls {
            guard isDirectChild(url) else { continue }
            let fileName = url.lastPathComponent
            let kind = entryKind(for: url)
            let (isUbiquitous, ubiStatus, inFlight) = ubiquitousState(for: url)
            let decision = readinessDecision(
                fileName: fileName,
                ignorePatterns: ignorePatterns,
                entryKind: kind,
                isUbiquitous: isUbiquitous,
                ubiquitousStatus: ubiStatus,
                ubiquitousDownloadInFlight: inFlight
            )
            switch decision {
            case .skip:
                continue
            case .requestDownload:
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                } catch {
                    log.writeLine("startDownloadingUbiquitousItem \(fileName): \(error.localizedDescription)")
                }
            case .ready:
                if let claim = claimIfReady(url) {
                    batch.append(claim)
                }
            }
        }
        enqueueClaims(batch)
    }

    // MARK: - NSFilePresenter

    func presentedSubitemDidChange(at url: URL) {
        log.writeLine("presenter callback subitemDidChange path=\(url.path)")
        handleURLs([url])
    }

    func presentedSubitemDidAppear(at url: URL) {
        log.writeLine("presenter callback subitemDidAppear path=\(url.path)")
        handleURLs([url])
    }

    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        log.writeLine("presenter callback subitemDidMove path=\(newURL.path)")
        handleURLs([newURL])
    }

    func presentedSubitemDidDisappear(at url: URL) {
        dropClaims(forStandardizedPath: url.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    // MARK: - FSEvents (FR9)

    private func fseventsWatchPaths() -> [String] {
        var paths = [watchFolderURL.path, watchFolderConfigured.path]
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    private func invalidateFSEvents(wait: Bool) {
        guard let stream = fseventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        fseventStream = nil
        if wait {
            fseventsQueue.sync {}
        }
        FSEventStreamRelease(stream)
    }

    private func startFSEvents() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DropBoxFolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let pathStrings = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            let summary = pathStrings.joined(separator: ",")
            watcher.log.writeLine("fsevents callback paths=\(summary)")
            let urls = pathStrings.map { URL(fileURLWithPath: $0) }
            watcher.presentedItemOperationQueue.addOperation {
                watcher.handleURLs(urls)
            }
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
        )
        let pathsToWatch = fseventsWatchPaths() as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0,
            flags
        ) else {
            log.writeLine("ERROR: FSEventStreamCreate failed")
            return
        }
        FSEventStreamSetDispatchQueue(stream, fseventsQueue)
        FSEventStreamStart(stream)
        fseventStream = stream
        log.writeLine("fsevents stream started")
    }
}
