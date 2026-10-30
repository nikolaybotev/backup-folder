import Foundation

/// Append-only operational log (FR4). Never writes secrets, Authorization, or request bodies.
final class OperationalLog: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var lastDeliveryErrorKey: String?
    private var lastDeliveryErrorLogTime: Date?
    private var skippedIdenticalDeliveryErrors = 0

    init?(path: String) {
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return nil
        }
        self.handle = handle
        try? handle.seekToEnd()
    }

    func writeLine(_ line: String, at time: Date = Date()) {
        let forbidden = Self.redactionViolations(in: line)
        if !forbidden.isEmpty {
            assertionFailure("log redaction: \(forbidden.joined(separator: ", "))")
            return
        }
        let stamp = Self.timestampFormatter.string(from: time)
        let text = "\(stamp) \(line)\n"
        lock.lock()
        defer { lock.unlock() }
        if let data = text.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    /// Logs a webhook delivery failure with at-most-once per 60s for identical status+error pairs (FR4 / D12).
    func logDeliveryFailure(status: Int?, errorDescription: String, at time: Date = Date()) {
        let key = "\(status.map(String.init) ?? "transport")|\(errorDescription)"
        lock.lock()
        defer { lock.unlock() }
        if lastDeliveryErrorKey == key,
           let last = lastDeliveryErrorLogTime,
           time.timeIntervalSince(last) < 60 {
            skippedIdenticalDeliveryErrors += 1
            return
        }
        var line = "webhook delivery failed"
        if let status {
            line += " status=\(status)"
        }
        line += " error=\(errorDescription)"
        if skippedIdenticalDeliveryErrors > 0 {
            line += " skipped_identical=\(skippedIdenticalDeliveryErrors)"
            skippedIdenticalDeliveryErrors = 0
        }
        lastDeliveryErrorKey = key
        lastDeliveryErrorLogTime = time
        writeLineUnlocked(line, at: time)
    }

    func clearDeliveryFailureRateLimit() {
        lock.lock()
        defer { lock.unlock() }
        lastDeliveryErrorKey = nil
        lastDeliveryErrorLogTime = nil
        skippedIdenticalDeliveryErrors = 0
    }

    private func writeLineUnlocked(_ line: String, at time: Date) {
        let forbidden = Self.redactionViolations(in: line)
        if !forbidden.isEmpty { return }
        let stamp = Self.timestampFormatter.string(from: time)
        let text = "\(stamp) \(line)\n"
        if let data = text.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    static func redactionViolations(in line: String) -> [String] {
        var hits: [String] = []
        if line.contains("Authorization:") || line.localizedCaseInsensitiveContains("authorization: bearer") {
            hits.append("authorization")
        }
        if line.contains("Bearer ") {
            hits.append("bearer")
        }
        return hits
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()
}
