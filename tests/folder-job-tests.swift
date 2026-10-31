import Foundation

private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

private func assert(_ condition: Bool, _ message: String) {
    if !condition { fail(message) }
}

private func waitUntil(_ deadline: Date, _ predicate: () -> Bool) -> Bool {
    while Date() < deadline {
        if predicate() { return true }
        _ = DispatchSemaphore(value: 0).wait(timeout: .now() + 0.01)
    }
    return predicate()
}

private final class Flight: @unchecked Sendable {
    private let lock = NSLock()
    private var inside = 0
    private(set) var maxInside = 0
    private(set) var entered = 0

    func enter() -> Int {
        lock.lock()
        inside += 1
        entered += 1
        if inside > maxInside { maxInside = inside }
        let now = inside
        lock.unlock()
        return now
    }

    func leave() {
        lock.lock()
        inside -= 1
        lock.unlock()
    }

    func snapshot() -> (inside: Int, maxInside: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (inside, maxInside)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []
    private var cancelled = false

    func append(_ value: Int, cancelledFlag: Bool) {
        lock.lock()
        values.append(value)
        if cancelledFlag { cancelled = true }
        lock.unlock()
    }

    func snapshot() -> (values: [Int], cancelled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (values, cancelled)
    }
}

@main
struct FolderJobTests {
    static func main() async {
        testSchema()
        testRetention()
        testExampleFile()
        testProductSourcesDoNotSleep()
        await testNoCapOverlap()
        await testCap()
        await testAggregateDoesNotCancel()
        print("folder-job-tests: OK")
    }

    static func testSchema() {
        switch parseBackupConfig("") {
        case .success:
            fail("empty folder list")
        case .failure(let error):
            assert(error.message == "missing folder", "empty list names folder without a line")
            assert(!error.message.contains("line "), "missing key has no line number")
        }

        switch parseBackupConfig("concurrency = 1\n") {
        case .success:
            fail("concurrency without folders")
        case .failure(let error):
            assert(error.message == "missing folder", "missing folder")
        }

        let relative = """
        [[folder]]
        source = "relative/path"
        dest = "/ABS/BACKUP"
        """
        switch parseBackupConfig(relative) {
        case .success:
            fail("relative path")
        case .failure(let error):
            assert(error.message.contains("line "), "relative path names the line")
            assert(error.message.contains("source"), "relative path names the key")
            assert(!error.message.contains("relative/path"), "relative path echoes the value")
        }

        switch parseBackupConfig("concurrency = 0\n[[folder]]\nsource = \"/ABS/SOURCE\"\ndest = \"/ABS/BACKUP\"\n") {
        case .success:
            fail("concurrency 0")
        case .failure(let error):
            assert(error.message.contains("line "), "concurrency 0 names the line")
            assert(error.message.contains("concurrency"), "concurrency 0 names the key")
            assert(!error.message.contains("0"), "concurrency 0 echoes the value")
        }

        switch parseBackupConfig("concurrency = -3\n[[folder]]\nsource = \"/ABS/SOURCE\"\ndest = \"/ABS/BACKUP\"\n") {
        case .success:
            fail("negative concurrency")
        case .failure(let error):
            assert(!error.message.contains("-3"), "negative concurrency echoes the value")
        }

        switch parseBackupConfig("concurrency = \"2\"\n[[folder]]\nsource = \"/ABS/SOURCE\"\ndest = \"/ABS/BACKUP\"\n") {
        case .success:
            fail("string concurrency")
        case .failure:
            break
        }

        switch parseBackupConfig("ratio = 1.5\n") {
        case .success:
            fail("float")
        case .failure(let error):
            assert(!error.message.contains("1.5"), "float echoes the value")
        }

        let normalized = """
        [[folder]]
        source = "/ABS/SOURCE/"
        dest = "/ABS/other/../BACKUP"
        """
        switch parseBackupConfig(normalized) {
        case .failure(let error):
            fail("single normalized dest \(error.message)")
        case .success(let config):
            assert(config.concurrency == nil, "absent concurrency")
            assert(config.folders.count == 1, "one folder")
            assert(config.folders[0].source == "/ABS/SOURCE", "trailing slash stripped by lexical normalize")
            assert(config.folders[0].dest == "/ABS/BACKUP", "dot-dot collapsed")
        }

        let slashes = """
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP"
        [[folder]]
        source = "/ABS/SOURCE-2"
        dest = "/ABS//BACKUP"
        """
        switch parseBackupConfig(slashes) {
        case .success:
            fail("double slash is the same dest")
        case .failure(let error):
            assert(error.message.contains("duplicate dest"), "double slash duplicate")
            assert(!error.message.contains("/ABS"), "duplicate echoes the path")
        }

        let dotdot = """
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP"
        [[folder]]
        source = "/ABS/SOURCE-2"
        dest = "/ABS/other/../BACKUP"
        """
        if case .success = parseBackupConfig(dotdot) {
            fail("dot-dot is the same dest")
        }

        let caseOnly = """
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/Backup"
        [[folder]]
        source = "/ABS/SOURCE-2"
        dest = "/ABS/backup"
        """
        switch parseBackupConfig(caseOnly) {
        case .success:
            fail("case-only dest")
        case .failure(let error):
            assert(!error.message.contains("Backup"), "case duplicate echoes the path")
            assert(!error.message.contains("backup"), "case duplicate echoes the lower path")
        }

        let inside = """
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/SOURCE/nested"
        [[folder]]
        source = "/ABS/SOURCE-2"
        dest = "/ABS/BACKUP-DIR-2"
        """
        switch parseBackupConfig(inside) {
        case .failure(let error):
            fail("dest inside source is not a schema error: \(error.message)")
        case .success(let config):
            assert(config.folders.count == 2, "inside pair still parsed")
            assert(config.folders[0].dest == "/ABS/SOURCE/nested", "inside dest kept")
        }

        let capped = """
        concurrency = 2
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP-DIR"
        [[folder]]
        source = "/ABS/SOURCE-2"
        dest = "/ABS/BACKUP#DIR"
        """
        switch parseBackupConfig(capped) {
        case .failure(let error):
            fail("hash in dest \(error.message)")
        case .success(let config):
            assert(config.concurrency == 2, "cap 2")
            assert(config.folders[0].dest == "/ABS/BACKUP-DIR", "file order first")
            assert(config.folders[1].dest == "/ABS/BACKUP#DIR", "hash kept in dest")
            assert(config.folders[1].source == "/ABS/SOURCE-2", "file order second")
        }

        testSymlinkDestinations()
    }

    static func testRetention() {
        let worked = """
        retention = ["4h", "15m/8h", "30m/16h", "1h/24h", "1d/30d"]
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP"
        """
        switch parseBackupConfig(worked) {
        case .failure(let error):
            fail("worked example \(error.message)")
        case .success(let config):
            assert(config.folders.count == 1, "worked one folder")
            let tiers = config.folders[0].retentionTiers
            assert(tiers.count == 5, "worked tier count")
            assert(tiers[0].intervalSeconds == 0 && tiers[0].ageSeconds == 4 * 3600, "worked keep-all 4h")
            assert(tiers[1].intervalSeconds == 15 * 60 && tiers[1].ageSeconds == 8 * 3600, "worked 15m/8h")
            assert(tiers[4].intervalSeconds == 86400 && tiers[4].ageSeconds == 30 * 86400, "worked 1d/30d")
        }

        let explicitDefault = """
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP"
        retention = ["48h", "1d/60d"]
        """
        switch parseBackupConfig(explicitDefault) {
        case .failure(let error):
            fail("explicit default \(error.message)")
        case .success(let config):
            assert(config.folders[0].retentionTiers == SnapshotRetention.defaultTiers, "48h 1d/60d matches defaultTiers")
        }

        let equalIntervals = """
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP"
        retention = ["60s", "1m"]
        """
        switch parseBackupConfig(equalIntervals) {
        case .failure(let error):
            fail("60s 1m \(error.message)")
        case .success(let config):
            let tiers = config.folders[0].retentionTiers
            assert(tiers.count == 2, "two tiers")
            assert(tiers[0].intervalSeconds == 0 && tiers[0].ageSeconds == 60, "60s keep-all tier")
            assert(tiers[1].intervalSeconds == 60 && tiers[1].ageSeconds == 120, "1m interval tier")
        }

        let inheritRoot = """
        retention = ["4h"]
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP"
        """
        switch parseBackupConfig(inheritRoot) {
        case .failure(let error):
            fail("inherit root \(error.message)")
        case .success(let config):
            assert(config.folders[0].retentionTiers.count == 1, "inherited one tier")
            assert(config.folders[0].retentionTiers[0].ageSeconds == 4 * 3600, "inherited 4h")
        }

        let overrideFolder = """
        retention = ["4h"]
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP"
        retention = ["48h", "1d/60d"]
        """
        switch parseBackupConfig(overrideFolder) {
        case .failure(let error):
            fail("override folder \(error.message)")
        case .success(let config):
            assert(config.folders[0].retentionTiers == SnapshotRetention.defaultTiers, "folder override default tiers")
        }

        assertRetentionFailure(
            """
            [[folder]]
            source = "/ABS/SOURCE"
            dest = "/ABS/BACKUP"
            retention = []
            """,
            contains: "empty retention"
        )

        assertRetentionFailure(
            """
            [[folder]]
            source = "/ABS/SOURCE"
            dest = "/ABS/BACKUP"
            retention = ["1w"]
            """,
            contains: "bad retention tier"
        )

        assertRetentionFailure(
            """
            [[folder]]
            source = "/ABS/SOURCE"
            dest = "/ABS/BACKUP"
            retention = ["48h", "2d"]
            """,
            contains: "retention ages must increase"
        )

        assertRetentionFailure(
            """
            [[folder]]
            source = "/ABS/SOURCE"
            dest = "/ABS/BACKUP"
            retention = ["1h/8h", "15m/16h"]
            """,
            contains: "retention interval larger than the next tier"
        )

        assertRetentionFailure(
            """
            retention = ["1w"]
            [[folder]]
            source = "/ABS/SOURCE"
            dest = "/ABS/BACKUP"
            retention = ["48h", "1d/60d"]
            """,
            contains: "bad retention tier"
        )

        assertRetentionFailure(
            """
            [[folder]]
            source = "/ABS/SOURCE"
            dest = "/ABS/BACKUP"
            retention = 4
            """,
            contains: "expected an array of strings for retention"
        )

        let goodConfig = """
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP"
        """
        guard case .success(let current) = parseBackupConfig(goodConfig) else {
            fail("good config for reload")
        }
        let badReload = """
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "/ABS/BACKUP"
        retention = ["48h", "2d"]
        """
        let decision = decideBackupConfigReload(current: current, read: parseBackupConfig(badReload))
        switch decision {
        case .keepAndLog(let line):
            assert(
                line.hasPrefix("config reload rejected: config parse error: "),
                "reload reject prefix got \(line)"
            )
            assert(line.contains("retention ages must increase"), "reload reject reason")
        default:
            fail("bad reload should keep-and-log")
        }
        guard case .success(let same) = parseBackupConfig(goodConfig) else {
            fail("re-read good")
        }
        let sameDecision = decideBackupConfigReload(current: current, read: .success(same))
        switch sameDecision {
        case .unchanged:
            assert(sameDecision.logLine == nil, "unchanged has no log")
        default:
            fail("equal re-read should be unchanged")
        }
    }

    static func assertRetentionFailure(_ text: String, contains fragment: String) {
        switch parseBackupConfig(text) {
        case .success:
            fail("expected failure for \(fragment)")
        case .failure(let error):
            assert(error.message.contains("line "), "retention error names line")
            assert(error.message.contains("retention"), "retention error names key class")
            assert(error.message.contains(fragment), "expected \(fragment) in \(error.message)")
            assert(!error.message.contains("/ABS"), "retention error echoes path")
            assert(!error.message.contains("1w"), "retention error echoes bad token")
            assert(!error.message.contains("2d"), "retention error echoes bad token")
        }
    }

    static func testSymlinkDestinations() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("folder-job-\(UUID().uuidString)", isDirectory: true)
        let real = root.appendingPathComponent("real", isDirectory: true)
        let linkA = root.appendingPathComponent("link-a")
        let linkB = root.appendingPathComponent("link-b")
        defer { try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: real, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: linkA, withDestinationURL: real)
            try fm.createSymbolicLink(at: linkB, withDestinationURL: real)
        } catch {
            fail("symlink fixture")
        }
        let text = """
        [[folder]]
        source = "/ABS/SOURCE"
        dest = "\(linkA.path)"
        [[folder]]
        source = "/ABS/SOURCE-2"
        dest = "\(linkB.path)"
        """
        switch parseBackupConfig(text) {
        case .success:
            fail("symlink destinations")
        case .failure(let error):
            assert(error.message.contains("duplicate dest"), "symlink duplicate")
            assert(!error.message.contains(linkA.path), "symlink error echoes path")
            assert(!error.message.contains(linkB.path), "symlink error echoes other path")
        }
    }

    static func testExampleFile() {
        guard let text = try? String(contentsOfFile: "backup-folder.example.toml", encoding: .utf8) else {
            fail("missing backup-folder.example.toml")
        }
        switch parseBackupConfig(text) {
        case .failure(let error):
            fail("example config \(error.message)")
        case .success(let config):
            assert(config.concurrency == nil, "example leaves concurrency commented")
            assert(config.folders.count == 2, "example folders")
            assert(config.folders[0].source == "/ABS/SOURCE", "example source")
            assert(config.folders[0].dest == "/ABS/BACKUP-DIR", "example dest")
            assert(config.folders[1].source == "/ABS/SOURCE-2", "example source 2")
            assert(config.folders[1].dest == "/ABS/BACKUP-DIR-2", "example dest 2")
        }
    }

    static func testProductSourcesDoNotSleep() {
        for path in [
            "Sources/backup-folder/FolderJob.swift",
            "Sources/backup-folder/BackupConfig.swift",
        ] {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                fail("missing \(path)")
            }
            for banned in ["Task.sleep", "usleep", "sleep(", "DispatchSemaphore", "cancelAll", "DispatchQueue.sync"] {
                assert(!text.contains(banned), "\(path) contains \(banned)")
            }
        }
        guard let backup = try? String(contentsOfFile: "Sources/backup-folder/BackupConfig.swift", encoding: .utf8) else {
            fail("missing BackupConfig.swift")
        }
        assert(!backup.contains("func lexicalNormalize"), "BackupConfig copies lexicalNormalize")
    }

    static func testNoCapOverlap() async {
        let flight = Flight()
        let pairs = [
            FolderPair(source: "/ABS/SOURCE-0", dest: "/ABS/BACKUP-0"),
            FolderPair(source: "/ABS/SOURCE-1", dest: "/ABS/BACKUP-1"),
        ]
        let status = await FolderJob.run(pairs: pairs, concurrency: nil) { _ in
            _ = flight.enter()
            let overlapped = waitUntil(Date().addingTimeInterval(2)) {
                flight.snapshot().maxInside >= 2
            }
            let tooMany = flight.snapshot().inside > 2
            let cancelled = Task.isCancelled
            flight.leave()
            if cancelled { return 8 }
            if tooMany || !overlapped { return 9 }
            return 0
        }
        assert(status == 0, "no-cap overlap status \(status)")
        assert(flight.entered == 2, "no-cap entered \(flight.entered)")
        assert(flight.maxInside >= 2, "no-cap max \(flight.maxInside)")
    }

    static func testCap() async {
        let flight = Flight()
        var pairs: [FolderPair] = []
        for index in 0..<4 {
            pairs.append(FolderPair(source: "/ABS/SOURCE-\(index)", dest: "/ABS/BACKUP-\(index)"))
        }
        let status = await FolderJob.run(pairs: pairs, concurrency: 2) { _ in
            let now = flight.enter()
            if now > 2 {
                flight.leave()
                return 7
            }
            let overlapped = waitUntil(Date().addingTimeInterval(2)) {
                flight.snapshot().maxInside >= 2
            }
            let tooMany = flight.snapshot().maxInside > 2 || flight.snapshot().inside > 2
            let cancelled = Task.isCancelled
            flight.leave()
            if cancelled { return 8 }
            if tooMany || !overlapped { return 7 }
            return 0
        }
        assert(status == 0, "cap status \(status) max \(flight.maxInside)")
        assert(flight.entered == 4, "cap entered \(flight.entered)")
        assert(flight.maxInside == 2, "cap max \(flight.maxInside)")
    }

    static func testAggregateDoesNotCancel() async {
        let counter = Counter()
        let pairs = [
            FolderPair(source: "/ABS/SOURCE-0", dest: "/ABS/BACKUP-0"),
            FolderPair(source: "/ABS/SOURCE-1", dest: "/ABS/BACKUP-1"),
            FolderPair(source: "/ABS/SOURCE-2", dest: "/ABS/BACKUP-2"),
        ]
        let mixed = await FolderJob.run(pairs: pairs, concurrency: nil) { pair in
            let index = Int(pair.source.suffix(1)) ?? -1
            counter.append(index, cancelledFlag: Task.isCancelled)
            return index == 1 ? 1 : 0
        }
        let mixedSnap = counter.snapshot()
        assert(mixed == 1, "aggregate 1 got \(mixed)")
        assert(mixedSnap.values.count == 3, "a 1 stops siblings")
        assert(!mixedSnap.cancelled, "Task.isCancelled set")
        assert(Set(mixedSnap.values) == Set([0, 1, 2]), "missing a folder")

        let ordered = Counter()
        let orderedStatus = await FolderJob.run(pairs: pairs, concurrency: 1) { pair in
            let index = Int(pair.source.suffix(1)) ?? -1
            ordered.append(index, cancelledFlag: Task.isCancelled)
            return 0
        }
        assert(orderedStatus == 0, "cap 1 status")
        assert(ordered.snapshot().values == [0, 1, 2], "file order \(ordered.snapshot().values)")

        let severe = await FolderJob.run(
            pairs: [
                FolderPair(source: "/ABS/SOURCE-0", dest: "/ABS/BACKUP-0"),
                FolderPair(source: "/ABS/SOURCE-1", dest: "/ABS/BACKUP-1"),
            ],
            concurrency: nil
        ) { pair in
            pair.source.hasSuffix("0") ? 2 : 1
        }
        assert(severe == 2, "aggregate 2 and 1 got \(severe)")
        assert(FolderJob.aggregate([0, 2, 1]) == 2, "aggregate helper")
    }
}
