import Foundation

private let testWebhookKey = "test-webhook-key-do-not-log"

private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

private func assert(_ condition: Bool, _ message: String) {
    if !condition { fail(message) }
}

private func writeFile(path: String, contents: String, mode: Int) throws {
    try contents.write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
}

@main
struct DropBoxWatcherTests {
    static func main() async {
        testConfigParser()
        testTomlSubset()
        testConfigPermissions()
        testIgnorePatterns()
        testReadinessTable()
        testLogRedaction()
        await testWebhookNotifier()
        testExampleConfigFile()
        testInstallSurfaceFiles()
        print("drop-box-watcher-tests: OK")
    }

    static func testConfigParser() {
        let validHTTPS = """
        watch_folder = "/tmp/watch"
        [webhook]
        url = "https://example.invalid/routine"
        key = "\(testWebhookKey)"
        [behavior]
        ignore = [".DS_Store", ".*"]
        [log]
        path = "/tmp/log"
        """
        switch parseConfigTOML(validHTTPS) {
        case .success(let cfg):
            assert(cfg.watchFolder == "/tmp/watch", "watch_folder")
            assert(cfg.webhookURL.hasPrefix("https://"), "https url")
        case .failure: fail("valid https config")
        }

        let loopback = """
        watch_folder = "/tmp/watch"
        [webhook]
        url = "http://127.0.0.1:8765/hook"
        key = "k"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        switch parseConfigTOML(loopback) {
        case .success: break
        case .failure: fail("loopback http with port")
        }

        let badRelative = """
        watch_folder = "relative/path"
        [webhook]
        url = "https://example.invalid/routine"
        key = "k"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        if case .success = parseConfigTOML(badRelative) { fail("relative watch_folder") }

        let badHTTP = """
        watch_folder = "/tmp/watch"
        [webhook]
        url = "http://example.com:8080/hook"
        key = "k"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        if case .success = parseConfigTOML(badHTTP) { fail("non-loopback http") }

        let emptyKey = """
        watch_folder = "/tmp/watch"
        [webhook]
        url = "https://example.invalid/routine"
        key = ""
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        if case .success = parseConfigTOML(emptyKey) { fail("empty key") }

        let unknownKey = """
        watch_folder = "/tmp/watch"
        extra = "x"
        [webhook]
        url = "https://example.invalid/routine"
        key = "k"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        if case .success = parseConfigTOML(unknownKey) { fail("unknown key") }

        let duplicate = """
        watch_folder = "/tmp/watch"
        watch_folder = "/tmp/other"
        [webhook]
        url = "https://example.invalid/routine"
        key = "k"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        if case .success = parseConfigTOML(duplicate) { fail("duplicate key") }

        let missingWebhook = """
        watch_folder = "/tmp/watch"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        if case .success = parseConfigTOML(missingWebhook) { fail("missing webhook table") }

        let literalString = """
        watch_folder = '/tmp/watch'
        [webhook]
        url = "https://example.invalid/routine"
        key = "k"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        if case .success = parseConfigTOML(literalString) { fail("literal string") }
    }

    static func testTomlSubset() {
        switch parseTomlSubset("count = -12\nconcurrency = 0\n") {
        case .success(let root):
            guard case .integer(-12) = root["count"]?.content else { fail("negative integer") }
            guard case .integer(0) = root["concurrency"]?.content else { fail("zero integer") }
            assert(root["count"]?.line == 1, "integer line")
        case .failure(let err):
            fail("integer parse \(err.message)")
        }

        let tables = """
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP#DIR"
        [[folder]]
        source = "/ABS/SOURCE-2"
        dest = "/ABS/BACKUP-DIR-2"
        """
        switch parseTomlSubset(tables) {
        case .success(let root):
            guard case .arrayOfTables(let rows) = root["folder"]?.content else { fail("array of tables kind") }
            assert(rows.count == 2, "two folder tables")
            guard case .string("/ABS/SOURCE") = rows[0]["source"]?.content else { fail("folder source") }
            guard case .string("/ABS/BACKUP#DIR") = rows[0]["dest"]?.content else { fail("hash inside string") }
            guard case .string("/ABS/BACKUP-DIR-2") = rows[1]["dest"]?.content else { fail("second dest") }
        case .failure(let err):
            fail("array of tables \(err.message)")
        }

        switch parseTomlSubset("note = \"a\\\"b\"\nslash = \"a\\\\b\"\n") {
        case .success(let root):
            guard case .string("a\"b") = root["note"]?.content else { fail("escaped quote") }
            guard case .string("a\\b") = root["slash"]?.content else { fail("escaped backslash") }
        case .failure(let err):
            fail("escapes \(err.message)")
        }

        switch parseTomlSubset("ratio = 1.5\n") {
        case .failure(let err):
            assert(err.message.contains("line 1"), "float line number")
            assert(!err.message.contains("1.5"), "float value not in error")
        case .success:
            fail("float")
        }

        let rejected = [
            "flag = true",
            "flag = false",
            "name = 'literal'",
            "point = { x = 1 }",
            "when = 1979-05-27",
            "a.b = 1",
            "n = +3",
            "n = 1_000",
            "n = 1.0",
        ]
        for sample in rejected {
            switch parseTomlSubset(sample + "\n") {
            case .success:
                fail("parser accepted a rejected form")
            case .failure(let err):
                assert(err.message.contains("line 1"), "rejected form names the line")
                if let eq = sample.firstIndex(of: "=") {
                    let value = sample[sample.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    if value.count >= 3 {
                        assert(!err.message.contains(value), "error echoes value")
                    }
                }
            }
        }
        let multiline = "name = \"\"\"hello\"\"\"\n"
        if case .success = parseTomlSubset(multiline) { fail("multiline string") }

        let sentinel = "SENTINEL-VALUE-NOT-A-KEY"
        switch parseTomlSubset("k = \"\(sentinel)\"\nk = \"\(sentinel)\"\n") {
        case .failure(let err):
            assert(err.message.contains("line 2"), "duplicate line")
            assert(!err.message.contains(sentinel), "duplicate error echoes value")
        case .success:
            fail("duplicate key")
        }
        switch parseTomlSubset("k = \"\(sentinel)\\q\"\n") {
        case .failure(let err):
            assert(!err.message.contains(sentinel), "escape error echoes value")
            assert(err.message.contains("line 1"), "escape line")
        case .success:
            fail("bad escape")
        }

        let withInteger = """
        watch_folder = "/tmp/watch"
        count = 2
        [webhook]
        url = "https://example.invalid/routine"
        key = "\(sentinel)"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        switch parseTomlSubset(withInteger) {
        case .success(let root):
            guard case .integer(2) = root["count"]?.content else { fail("count integer in document") }
        case .failure(let err):
            fail("document integer \(err.message)")
        }
        switch parseConfigTOML(withInteger) {
        case .success:
            fail("watcher integer value")
        case .failure(let err):
            assert(!String(describing: err).contains(sentinel), "watcher integer error echoes key")
        }

        let innerInteger = """
        watch_folder = "/tmp/watch"
        [webhook]
        url = "https://example.invalid/routine"
        key = "k"
        retries = 4
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        if case .success = parseConfigTOML(innerInteger) { fail("integer inside webhook table") }

        let withTables = """
        watch_folder = "/tmp/watch"
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP-DIR"
        [webhook]
        url = "https://example.invalid/routine"
        key = "\(sentinel)"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        switch parseTomlSubset(withTables) {
        case .failure(let err):
            fail("parser rejected array of tables \(err.message)")
        case .success:
            break
        }
        switch parseConfigTOML(withTables) {
        case .success:
            fail("watcher array of tables")
        case .failure(let err):
            assert(!String(describing: err).contains(sentinel), "watcher table array error echoes key")
        }

        let hashKey = """
        watch_folder = "/tmp/watch"
        [webhook]
        url = "https://example.invalid/routine"
        key = "abc#def"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        switch parseConfigTOML(hashKey) {
        case .success(let cfg):
            assert(cfg.webhookKey == "abc#def", "hash inside webhook key")
        case .failure(let err):
            fail("hash key \(err)")
        }
    }

    static func testConfigPermissions() {
        let dir = FileManager.default.temporaryDirectory.path
        let path644 = dir + "/dbw-cfg-644.toml"
        let path600 = dir + "/dbw-cfg-600.toml"
        let path400 = dir + "/dbw-cfg-400.toml"
        let path200 = dir + "/dbw-cfg-200.toml"
        let pathMissing = dir + "/dbw-cfg-missing.toml"
        let body = """
        watch_folder = "/tmp/watch"
        [webhook]
        url = "https://example.invalid/routine"
        key = "k"
        [behavior]
        ignore = []
        [log]
        path = "/tmp/log"
        """
        defer {
            try? FileManager.default.removeItem(atPath: path644)
            try? FileManager.default.removeItem(atPath: path600)
            try? FileManager.default.removeItem(atPath: path400)
            try? FileManager.default.removeItem(atPath: path200)
        }
        try! writeFile(path: path644, contents: body, mode: 0o644)
        try! writeFile(path: path600, contents: body, mode: 0o600)
        try! writeFile(path: path400, contents: body, mode: 0o400)
        try! writeFile(path: path200, contents: body, mode: 0o200)

        assert(!configPermissionsAcceptable(at: path644), "0644 not acceptable")
        if case .success = loadConfig(from: path644) { fail("0644 must not parse") }
        if case .failure(.permissionsTooOpen) = loadConfig(from: path644) {} else { fail("0644 permissions error") }

        assert(configPermissionsAcceptable(at: path600), "0600 acceptable")
        if case .success = loadConfig(from: path600) {} else { fail("0600 load") }

        assert(configPermissionsAcceptable(at: path400), "0400 acceptable")
        if case .success = loadConfig(from: path400) {} else { fail("0400 load") }

        assert(configPermissionsAcceptable(at: path200), "0200 acceptable")
        assert(!configPermissionsAcceptable(at: pathMissing), "missing path")
    }

    static func testIgnorePatterns() {
        let patterns = [".DS_Store", ".*", "*.icloud", "*.download", "*.crdownload", "*.part"]
        assert(nameMatchesAnyIgnorePattern(".DS_Store", patterns: patterns), ".DS_Store")
        assert(nameMatchesAnyIgnorePattern(".hidden", patterns: patterns), "dotfile")
        assert(nameMatchesAnyIgnorePattern("file.icloud", patterns: patterns), ".icloud")
        assert(nameMatchesAnyIgnorePattern("x.download", patterns: patterns), ".download")
        assert(nameMatchesAnyIgnorePattern("x.crdownload", patterns: patterns), ".crdownload")
        assert(nameMatchesAnyIgnorePattern("x.part", patterns: patterns), ".part")
        assert(!nameMatchesAnyIgnorePattern("note.txt", patterns: patterns), "note.txt not ignored")
    }

    static func testReadinessTable() {
        let patterns = [".DS_Store", ".*"]
        func decide(
            name: String = "note.txt",
            kind: PathEntryKind = .regularFile,
            ub: Bool = false,
            status: UbiquitousDownloadStatus = .missing,
            downloading: Bool = false
        ) -> ReadinessDecision {
            readinessDecision(
                fileName: name,
                ignorePatterns: patterns,
                entryKind: kind,
                isUbiquitous: ub,
                ubiquitousStatus: status,
                ubiquitousDownloadInFlight: downloading
            )
        }
        assert(decide(ub: false) == .ready, "local file")
        assert(decide(ub: true, status: .current, downloading: false) == .ready, "current")
        assert(decide(ub: true, status: .current, downloading: true) == .requestDownload, "current downloading")
        assert(decide(ub: true, status: .downloaded) == .requestDownload, "downloaded")
        assert(decide(ub: true, status: .notDownloaded) == .requestDownload, "notDownloaded")
        assert(decide(kind: .directory) == .skip, "directory")
        assert(decide(kind: .symbolicLink) == .skip, "symlink")
        let text = (try? String(contentsOfFile: "drop-box-watcher/Readiness.swift", encoding: .utf8)) ?? ""
        assert(!text.contains("startDownloadingUbiquitousItem"), "Readiness must not mention download API")
    }

    static func testLogRedaction() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbw-log-\(UUID().uuidString).log").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard let log = OperationalLog(path: path) else { fail("open log") }
        log.logDeliveryFailure(status: 500, errorDescription: "non-2xx")
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        assert(!text.contains(testWebhookKey), "log must not contain webhook key")
        assert(!text.localizedCaseInsensitiveContains("authorization"), "log must not contain authorization")
        let startupLine = "started watch_folder=/tmp/macos-watcher-watch-12345"
        assert(OperationalLog.redactionViolations(in: startupLine).isEmpty, "startup log line must not trip redaction")
        log.writeLine(startupLine)
        let after = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        assert(after.contains("started watch_folder="), "startup line must be written")
    }

    static func testExampleConfigFile() {
        let path = FileManager.default.currentDirectoryPath + "/drop-box-watcher.example.toml"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            fail("missing drop-box-watcher.example.toml")
        }
        assert(!text.contains(testWebhookKey), "example must not embed test key")
        switch parseConfigTOML(text) {
        case .success(let cfg):
            assert(cfg.watchFolder.hasPrefix("/ABS/PATH/TO/HOME/"), "example watch_folder placeholder")
            assert(cfg.webhookURL == "https://example.invalid/routine", "example webhook url")
            assert(cfg.webhookKey == "REPLACE-WITH-ROUTINE-KEY", "example key placeholder")
            assert(cfg.logPath.hasPrefix("/ABS/PATH/TO/HOME/"), "example log path placeholder")
            let wantIgnore = [".DS_Store", ".*", "*.icloud", "*.download", "*.crdownload", "*.part"]
            assert(cfg.ignorePatterns == wantIgnore, "example ignore list")
        case .failure(let err):
            fail("example config parse: \(err)")
        }
    }

    static func testInstallSurfaceFiles() {
        let root = FileManager.default.currentDirectoryPath
        let releasePath = root + "/.github/workflows/release.yml"
        guard let release = try? String(contentsOfFile: releasePath, encoding: .utf8) else {
            fail("missing .github/workflows/release.yml")
        }
        assert(release.contains("drop-box-watcher"), "release.yml must name drop-box-watcher")

        let plistPath = root + "/launchd/drop-box-watcher.plist.template"
        guard let plist = try? String(contentsOfFile: plistPath, encoding: .utf8) else {
            fail("missing launchd/drop-box-watcher.plist.template")
        }
        assert(plist.contains("com.nikolaybotev.drop-box-watcher"), "plist label")
        assert(plist.contains("<key>RunAtLoad</key>"), "RunAtLoad")
        assert(plist.contains("<key>KeepAlive</key>"), "KeepAlive")
        assert(plist.contains("<key>ThrottleInterval</key>"), "ThrottleInterval")
        assert(!plist.contains("StartInterval"), "plist must not contain StartInterval")
    }

    static func testWebhookNotifier() async {
        await testWebhookInFlightMerge()
        await testWebhookBackoffCancelAndSuccess()
        await testWebhookFailedImmediateResendUsesNextBackoffStep()
    }

    static func makeNotifierHarness() -> (
        WebhookNotifier,
        FakeWebhookTransport,
        FakeWebhookSleeper,
        URL
    ) {
        let url = URL(string: "https://example.invalid/routine")!
        let transport = FakeWebhookTransport()
        let sleeper = FakeWebhookSleeper()
        let notifier = WebhookNotifier(
            webhookURL: url,
            webhookKey: testWebhookKey,
            transport: transport,
            sleeper: sleeper
        )
        return (notifier, transport, sleeper, url)
    }

    static func testWebhookInFlightMerge() async {
        let (notifier, transport, sleeper, _) = makeNotifierHarness()
        let claimA = WebhookClaim(standardizedPath: "/tmp/note.txt", inode: 1, size: 10)
        let claimB = WebhookClaim(standardizedPath: "/tmp/other.txt", inode: 2, size: 20)

        transport.blockNextRequest = true
        transport.enqueueResponse(.success(WebhookHTTPResponse(statusCode: 500)))
        await notifier.submit(claims: [claimA])
        await waitUntil { transport.inFlightCount == 1 }
        await notifier.submit(claims: [claimB])
        transport.releaseBlockedRequest()
        await waitUntil { transport.requests.count >= 1 }
        assert(transport.requests[0].authorization == "Bearer \(testWebhookKey)", "authorization header")

        transport.enqueueResponse(.success(WebhookHTTPResponse(statusCode: 500)))
        await waitUntil { !sleeper.pendingSleeps.isEmpty }
        assert(sleeper.pendingSleeps.last == 1, "first backoff 1s")
        sleeper.completeOneSleep()
        await waitUntil { transport.requests.count >= 2 }

        let secondJSON = try! JSONSerialization.jsonObject(with: transport.requests[1].body) as! [String: Any]
        assert(secondJSON["event_time"] != nil, "event_time present")
        let files = secondJSON["files"] as! [String]
        assert(files.contains("note.txt") && files.contains("other.txt"), "merged follow-up POST")
        _ = sleeper
    }

    static func testWebhookBackoffCancelAndSuccess() async {
        let (notifier, transport, sleeper, _) = makeNotifierHarness()
        let claimA = WebhookClaim(standardizedPath: "/tmp/note.txt", inode: 1, size: 10)
        let claimB = WebhookClaim(standardizedPath: "/tmp/other.txt", inode: 2, size: 20)

        transport.enqueueResponse(.success(WebhookHTTPResponse(statusCode: 500)))
        await notifier.submit(claims: [claimA])
        await waitUntil { sleeper.requestedSleeps.count >= 1 }
        assert(sleeper.requestedSleeps[0] == 1, "non-2xx wait 1s")
        sleeper.completeOneSleep()

        transport.enqueueResponse(.success(WebhookHTTPResponse(statusCode: 500)))
        await waitUntil { sleeper.requestedSleeps.count >= 2 }
        assert(sleeper.requestedSleeps[1] == 2, "non-2xx wait 2s")

        transport.enqueueResponse(.success(WebhookHTTPResponse(statusCode: 200)))
        await notifier.submit(claims: [claimB])
        sleeper.cancelOneSleep()
        await waitUntil { transport.requests.count >= 3 }
        let successJSON = try! JSONSerialization.jsonObject(with: transport.requests.last!.body) as! [String: Any]
        assert((successJSON["files"] as! [String]).isEmpty == false, "2xx batch had files")
        await waitUntil { await notifier.pendingCountForTesting() == 0 }

        for req in transport.requests {
            assert(!String(data: req.body, encoding: .utf8)!.contains(testWebhookKey), "body has no key")
            assert(req.authorization == "Bearer \(testWebhookKey)", "bearer on each request")
        }
    }

    static func testWebhookFailedImmediateResendUsesNextBackoffStep() async {
        let (notifier, transport, sleeper, _) = makeNotifierHarness()
        let claimA = WebhookClaim(standardizedPath: "/tmp/note.txt", inode: 1, size: 10)
        let claimB = WebhookClaim(standardizedPath: "/tmp/other.txt", inode: 2, size: 20)

        transport.enqueueResponse(.success(WebhookHTTPResponse(statusCode: 500)))
        await notifier.submit(claims: [claimA])
        await waitUntil { sleeper.requestedSleeps.count >= 1 }
        sleeper.completeOneSleep()

        transport.enqueueResponse(.success(WebhookHTTPResponse(statusCode: 500)))
        await waitUntil { sleeper.requestedSleeps.count >= 2 }
        sleeper.completeOneSleep()

        transport.enqueueResponse(.success(WebhookHTTPResponse(statusCode: 500)))
        await waitUntil { sleeper.requestedSleeps.count >= 3 }
        assert(sleeper.requestedSleeps[2] == 4, "next wait 4s after 1s and 2s")

        transport.enqueueResponse(.success(WebhookHTTPResponse(statusCode: 500)))
        await notifier.submit(claims: [claimB])
        sleeper.cancelOneSleep()
        await waitUntil { transport.requests.count >= 4 }
        await waitUntil { sleeper.requestedSleeps.count >= 4 }
        assert(sleeper.requestedSleeps[3] == 4, "failed immediate resend waits 4s not 1s")
    }

    static func waitUntil(_ predicate: @escaping () async -> Bool, timeout: Double = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        fail("timeout")
    }

    static func waitUntil(_ predicate: @escaping () -> Bool, timeout: Double = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        fail("timeout")
    }
}

final class FakeWebhookTransport: WebhookTransport, @unchecked Sendable {
    struct RecordedRequest: Sendable {
        let authorization: String
        let body: Data
    }

    private struct State {
        var requests: [RecordedRequest] = []
        var queued: [Result<WebhookHTTPResponse, Error>] = []
        var responseIndex = 0
        var blockNextRequest = false
        var inFlightCount = 0
        var blockContinuation: CheckedContinuation<Void, Never>?
    }

    private let stateLock = NSLock()
    private var state = State()

    var blockNextRequest: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return state.blockNextRequest
        }
        set {
            stateLock.lock()
            state.blockNextRequest = newValue
            stateLock.unlock()
        }
    }

    var inFlightCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.inFlightCount
    }

    var requests: [RecordedRequest] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.requests
    }

    func enqueueResponse(_ result: Result<WebhookHTTPResponse, Error>) {
        stateLock.lock()
        state.queued.append(result)
        stateLock.unlock()
    }

    func releaseBlockedRequest() {
        stateLock.lock()
        let cont = state.blockContinuation
        state.blockContinuation = nil
        stateLock.unlock()
        cont?.resume()
    }

    func post(_ request: WebhookHTTPRequest) async throws -> WebhookHTTPResponse {
        let shouldBlock: Bool
        stateLock.lock()
        state.requests.append(RecordedRequest(authorization: request.authorization, body: request.body))
        shouldBlock = state.blockNextRequest
        state.blockNextRequest = false
        state.inFlightCount += 1
        stateLock.unlock()

        if shouldBlock {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                stateLock.lock()
                state.blockContinuation = cont
                stateLock.unlock()
            }
        }

        stateLock.lock()
        state.inFlightCount -= 1
        let idx = state.responseIndex
        state.responseIndex += 1
        let result: Result<WebhookHTTPResponse, Error>
        if idx < state.queued.count {
            result = state.queued[idx]
        } else {
            result = .success(WebhookHTTPResponse(statusCode: 500))
        }
        stateLock.unlock()

        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

final class FakeWebhookSleeper: WebhookSleeper, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requestedSleeps: [Double] = []
    private var continuations: [CheckedContinuation<Void, Error>] = []

    var pendingSleeps: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return requestedSleeps
    }

    func sleep(seconds: Double) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                lock.lock()
                requestedSleeps.append(seconds)
                continuations.append(cont)
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            if !continuations.isEmpty {
                let cont = continuations.removeLast()
                lock.unlock()
                cont.resume(throwing: CancellationError())
            } else {
                lock.unlock()
            }
        }
    }

    func completeOneSleep() {
        lock.lock()
        guard !continuations.isEmpty else {
            lock.unlock()
            return
        }
        let cont = continuations.removeFirst()
        lock.unlock()
        cont.resume()
    }

    func cancelOneSleep() {
        lock.lock()
        guard !continuations.isEmpty else {
            lock.unlock()
            return
        }
        let cont = continuations.removeFirst()
        lock.unlock()
        cont.resume(throwing: CancellationError())
    }
}
