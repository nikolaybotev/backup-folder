import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Append-only operational log (FR4). Never writes secrets, Authorization, or request bodies.
final class OperationalLog: @unchecked Sendable {
    private let path: String
    private let lock = NSLock()
    private var lastDeliveryErrorKey: String?
    private var lastDeliveryErrorLogTime: Date?
    private var skippedIdenticalDeliveryErrors = 0

    init?(path: String) {
        self.path = path
        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard FileManager.default.isWritableFile(atPath: path) else {
            return nil
        }
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
        appendUTF8(text)
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
        appendUTF8(text)
    }

    private func appendUTF8(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var written = 0
            while written < raw.count {
                let chunk = write(fd, base.advanced(by: written), raw.count - written)
                if chunk <= 0 { break }
                written += chunk
            }
        }
        fsync(fd)
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
