import CoreServices
import Foundation

struct ConfigWatchSnapshot {
    var config: DropBoxWatcherConfig
    var log: OperationalLog
}

/// FSEvents on the config file's parent directory. Re-reads by path. Does not exit.
final class ConfigWatch {
    private let configPath: String
    private let fileName: String
    private let parentPath: String
    private let queue = DispatchQueue(label: "drop-box-watcher.config-reload")
    private var stream: FSEventStreamRef?
    private let snapshot: () -> ConfigWatchSnapshot
    private let apply: (DropBoxWatcherConfig, OperationalLog) -> Void

    init(
        configPath: String,
        snapshot: @escaping () -> ConfigWatchSnapshot,
        apply: @escaping (DropBoxWatcherConfig, OperationalLog) -> Void
    ) {
        self.configPath = configPath
        let url = URL(fileURLWithPath: configPath)
        self.fileName = url.lastPathComponent
        self.parentPath = url.deletingLastPathComponent().path
        self.snapshot = snapshot
        self.apply = apply
    }

    deinit {
        stop()
    }

    func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watch = Unmanaged<ConfigWatch>.fromOpaque(info).takeUnretainedValue()
            let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            let relevant = paths.contains { path in
                URL(fileURLWithPath: path).lastPathComponent == watch.fileName
            }
            if !relevant { return }
            watch.queue.async {
                watch.reread()
            }
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [parentPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0,
            flags
        ) else {
            snapshot().log.writeLine("ERROR: config FSEventStreamCreate failed")
            return
        }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    /// One more read after the stream is armed, for a change that landed during startup.
    func reloadNow() {
        queue.async { [self] in
            self.reread()
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func reread() {
        let live = snapshot()
        let decision = decideConfigReload(current: live.config, read: loadConfig(from: configPath))
        switch decision {
        case .unchanged:
            return
        case .keepAndLog(let line):
            writeReloadLine(line, log: live.log, logPath: live.config.logPath)
        case .applyAndLog(let updated):
            if let line = rejectionBeforeSwap(updated) {
                writeReloadLine(line, log: live.log, logPath: live.config.logPath)
                return
            }
            guard let newLog = OperationalLog(path: updated.logPath) else {
                writeReloadLine(
                    "config reload rejected: cannot open log file",
                    log: live.log,
                    logPath: live.config.logPath
                )
                return
            }
            writeReloadLine("config reloaded", log: live.log, logPath: live.config.logPath)
            apply(updated, newLog)
        }
    }

    /// Directory and URL checks before any live setting changes. Log open is the caller's next step.
    private func rejectionBeforeSwap(_ updated: DropBoxWatcherConfig) -> String? {
        let folder = URL(fileURLWithPath: updated.watchFolder)
        if !watchFolderIsDirectory(folder) {
            return "config reload rejected: watch folder missing or not a directory"
        }
        if URL(string: updated.webhookURL) == nil {
            return "config reload rejected: invalid webhook url"
        }
        return nil
    }

    private func writeReloadLine(_ line: String, log: OperationalLog, logPath: String) {
        let before = byteCount(at: logPath)
        log.writeLine(line)
        let data = (try? Data(contentsOf: URL(fileURLWithPath: logPath))) ?? Data()
        let start = min(before, data.count)
        let appended = data.subdata(in: start..<data.count)
        let wrote = String(data: appended, encoding: .utf8)?.contains(line) == true
        if !wrote {
            FileHandle.standardError.write(Data("\(line)\n".utf8))
        }
    }

    private func byteCount(at path: String) -> Int {
        guard let number = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber else {
            return 0
        }
        return number.intValue
    }
}
