import Foundation

/// Keeps the watcher alive for the process lifetime (FR9 / plan Phase 1 step 2).
enum DropBoxWatcherProcess {
    static var log: OperationalLog!
    static var notifier: WebhookNotifier!
    static var watcher: DropBoxFolderWatcher!
}

func failStderr(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    fflush(stderr)
    exit(2)
}

func fail(_ message: String, log: OperationalLog? = nil) -> Never {
    fputs("\(message)\n", stderr)
    fflush(stderr)
    log?.writeLine("ERROR: \(message)")
    exit(2)
}

func watchFolderIsDirectory(_ url: URL) -> Bool {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
    if let values = try? url.resourceValues(forKeys: keys) {
        if values.isDirectory == true {
            return true
        }
        if values.isSymbolicLink == true {
            let resolved = url.resolvingSymlinksInPath()
            if let resolvedValues = try? resolved.resourceValues(forKeys: [.isDirectoryKey]),
               resolvedValues.isDirectory == true {
                return true
            }
        }
    }
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
        return true
    }
    let resolvedPath = url.resolvingSymlinksInPath().path
    if FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDir), isDir.boolValue {
        return true
    }
    return false
}

guard CommandLine.arguments.count == 2 else {
    failStderr("usage: drop-box-watcher <config-path>")
}
let configPath = CommandLine.arguments[1]

guard configPermissionsAcceptable(at: configPath) else {
    failStderr("config permissions too open")
}

let config: DropBoxWatcherConfig
switch loadConfig(from: configPath) {
case .success(let c):
    config = c
case .failure(.permissionsTooOpen):
    failStderr("config permissions too open")
case .failure(.parse(let msg)):
    failStderr("config parse error: \(msg)")
case .failure(.io(let msg)):
    failStderr("config io error: \(msg)")
}

guard let log = OperationalLog(path: config.logPath) else {
    failStderr("cannot open log file")
}
log.writeLine("operational_log path=\(config.logPath)")

let watchURL = URL(fileURLWithPath: config.watchFolder)
guard watchFolderIsDirectory(watchURL) else {
    fail("watch folder missing or not a directory", log: log)
}

guard let webhookURL = URL(string: config.webhookURL) else {
    fail("invalid webhook url", log: log)
}

let transport = URLSessionWebhookTransport()
let sleeper = RealWebhookSleeper()
let notifier = WebhookNotifier(
    webhookURL: webhookURL,
    webhookKey: config.webhookKey,
    transport: transport,
    sleeper: sleeper,
    log: log
)
DropBoxWatcherProcess.log = log
DropBoxWatcherProcess.notifier = notifier

DropBoxWatcherProcess.watcher = DropBoxFolderWatcher(
    watchFolderURL: watchURL,
    ignorePatterns: config.ignorePatterns,
    notifier: notifier,
    log: log
)
DropBoxWatcherProcess.watcher.start()
DispatchQueue.main.async {
    DropBoxWatcherProcess.watcher.registerOnMainRunLoop()
}
dispatchMain()
