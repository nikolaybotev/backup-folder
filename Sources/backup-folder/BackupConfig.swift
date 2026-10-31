import Foundation
#if canImport(ToolConfig)
import ToolConfig
#endif

struct ParsedBackupConfig: Sendable, Equatable {
    var folders: [FolderPair]
    var concurrency: Int?
}

struct BackupConfigError: Error, Equatable, CustomStringConvertible {
    var message: String
    var description: String { message }
}

enum BackupConfigReloadDecision: Equatable {
    case keepAndLog(String)
    case unchanged
    case apply(ParsedBackupConfig)

    var logLine: String? {
        switch self {
        case .keepAndLog(let line):
            return line
        case .unchanged:
            return nil
        case .apply:
            return nil
        }
    }
}

func decideBackupConfigReload(
    current: ParsedBackupConfig?,
    read: Result<ParsedBackupConfig, BackupConfigError>
) -> BackupConfigReloadDecision {
    switch read {
    case .failure(let error):
        let parseLine = "config parse error: \(error.message)"
        if current != nil {
            return .keepAndLog("config reload rejected: \(parseLine)")
        }
        return .keepAndLog(parseLine)
    case .success(let updated):
        if let current, current == updated {
            return .unchanged
        }
        return .apply(updated)
    }
}

func parseBackupConfig(_ text: String) -> Result<ParsedBackupConfig, BackupConfigError> {
    let root: [String: TomlValue]
    switch parseTomlSubset(text) {
    case .failure(let error):
        return .failure(BackupConfigError(message: error.message))
    case .success(let table):
        root = table
    }

    for (key, value) in root where key != "concurrency" && key != "folder" && key != "retention" {
        return .failure(BackupConfigError(message: "line \(value.line): unknown key \(key)"))
    }

    let concurrency: Int?
    if let value = root["concurrency"] {
        guard case .integer(let number) = value.content else {
            return .failure(BackupConfigError(message: "line \(value.line): expected an integer for concurrency"))
        }
        if number < 1 {
            return .failure(
                BackupConfigError(
                    message: "line \(value.line): concurrency must be an integer greater than or equal to 1"
                )
            )
        }
        concurrency = number
    } else {
        concurrency = nil
    }

    let rootRetention: [RetentionTier]?
    if let value = root["retention"] {
        switch parseRetentionValue(value) {
        case .failure(let error):
            return .failure(error)
        case .success(let tiers):
            rootRetention = tiers
        }
    } else {
        rootRetention = nil
    }

    guard let folderValue = root["folder"] else {
        return .failure(BackupConfigError(message: "missing folder"))
    }
    guard case .arrayOfTables(let rows) = folderValue.content else {
        return .failure(BackupConfigError(message: "line \(folderValue.line): expected an array of tables for folder"))
    }
    if rows.isEmpty {
        return .failure(BackupConfigError(message: "missing folder"))
    }

    var drafts: [FolderDraft] = []
    for row in rows {
        switch parseFolderRow(row) {
        case .failure(let error):
            return .failure(error)
        case .success(let draft):
            drafts.append(draft)
        }
    }

    if let message = duplicateDestinationMessage(drafts) {
        return .failure(BackupConfigError(message: message))
    }

    let defaultResolved = rootRetention ?? SnapshotRetention.defaultTiers
    let folders = drafts.map { draft in
        let tiers = draft.retention ?? defaultResolved
        return FolderPair(source: draft.source, dest: draft.dest, retentionTiers: tiers)
    }
    return .success(ParsedBackupConfig(folders: folders, concurrency: concurrency))
}

private struct FolderDraft {
    var source: String
    var dest: String
    var destLine: Int
    var retention: [RetentionTier]?
}

private func parseFolderRow(_ row: [String: TomlValue]) -> Result<FolderDraft, BackupConfigError> {
    var source: String?
    var dest: String?
    var destLine = 0
    var retention: [RetentionTier]?
    for (key, value) in row {
        switch key {
        case "source":
            switch absolutePath(value, key: key) {
            case .failure(let error):
                return .failure(error)
            case .success(let path):
                source = path
            }
        case "dest":
            switch absolutePath(value, key: key) {
            case .failure(let error):
                return .failure(error)
            case .success(let path):
                dest = path
                destLine = value.line
            }
        case "retention":
            switch parseRetentionValue(value) {
            case .failure(let error):
                return .failure(error)
            case .success(let tiers):
                retention = tiers
            }
        default:
            return .failure(BackupConfigError(message: "line \(value.line): unknown key \(key)"))
        }
    }
    guard let source else {
        return .failure(BackupConfigError(message: "missing source"))
    }
    guard let dest else {
        return .failure(BackupConfigError(message: "missing dest"))
    }
    return .success(FolderDraft(source: source, dest: dest, destLine: destLine, retention: retention))
}

private func parseRetentionValue(_ value: TomlValue) -> Result<[RetentionTier], BackupConfigError> {
    guard case .arrayOfStrings(let elements) = value.content else {
        return .failure(
            BackupConfigError(message: "line \(value.line): expected an array of strings for retention")
        )
    }
    if elements.isEmpty {
        return .failure(BackupConfigError(message: "line \(value.line): empty retention"))
    }
    var tiers: [RetentionTier] = []
    tiers.reserveCapacity(elements.count)
    for element in elements {
        guard let parsed = parseRetentionTierString(element) else {
            return .failure(BackupConfigError(message: "line \(value.line): bad retention tier"))
        }
        tiers.append(parsed)
    }
    if let error = validateRetentionTiers(tiers, line: value.line) {
        return .failure(error)
    }
    return .success(tiers)
}

private func parseRetentionTierString(_ element: String) -> RetentionTier? {
    let intervalSeconds: Int
    let ageSeconds: Int
    if let slash = element.firstIndex(of: "/") {
        let left = String(element[..<slash])
        let right = String(element[element.index(after: slash)...])
        guard let interval = parseIntervalToken(left), let age = parseDurationToken(right) else {
            return nil
        }
        intervalSeconds = interval
        ageSeconds = age
    } else {
        guard let age = parseDurationToken(element) else {
            return nil
        }
        intervalSeconds = 0
        ageSeconds = age
    }
    return RetentionTier(intervalSeconds: intervalSeconds, ageSeconds: ageSeconds)
}

private func parseIntervalToken(_ token: String) -> Int? {
    if token == "0" {
        return 0
    }
    return parseDurationToken(token)
}

private func parseDurationToken(_ token: String) -> Int? {
    guard token.count >= 2 else {
        return nil
    }
    guard let unitChar = token.last, "smhd".contains(unitChar) else {
        return nil
    }
    let numPart = String(token.dropLast())
    guard let number = parseTierNumber(numPart) else {
        return nil
    }
    let unitSeconds: Int
    switch unitChar {
    case "s":
        unitSeconds = 1
    case "m":
        unitSeconds = 60
    case "h":
        unitSeconds = 3600
    case "d":
        unitSeconds = 86400
    default:
        return nil
    }
    let total = number * unitSeconds
    if total / unitSeconds != number {
        return nil
    }
    return total
}

private func parseTierNumber(_ text: String) -> Int? {
    if text == "0" {
        return 0
    }
    guard let first = text.first, first >= "1", first <= "9" else {
        return nil
    }
    guard text.dropFirst().allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
        return nil
    }
    return Int(text)
}

private func validateRetentionTiers(_ tiers: [RetentionTier], line: Int) -> BackupConfigError? {
    for tier in tiers {
        if tier.ageSeconds <= 0 {
            return BackupConfigError(message: "line \(line): retention age must be greater than 0")
        }
    }
    for index in 1..<tiers.count {
        if tiers[index].ageSeconds <= tiers[index - 1].ageSeconds {
            return BackupConfigError(message: "line \(line): retention ages must increase")
        }
        if tiers[index - 1].intervalSeconds > tiers[index].intervalSeconds {
            return BackupConfigError(message: "line \(line): retention interval larger than the next tier")
        }
    }
    return nil
}

private func absolutePath(_ value: TomlValue, key: String) -> Result<String, BackupConfigError> {
    guard case .string(let text) = value.content else {
        return .failure(BackupConfigError(message: "line \(value.line): expected a string for \(key)"))
    }
    if !text.hasPrefix("/") {
        return .failure(BackupConfigError(message: "line \(value.line): \(key) must be an absolute path"))
    }
    return .success(PathContainment.lexicalNormalize(text))
}

private func duplicateDestinationMessage(_ drafts: [FolderDraft]) -> String? {
    for index in drafts.indices {
        let dest = drafts[index].dest
        for earlier in drafts[..<index] {
            if sameDestination(earlier.dest, dest) {
                return "line \(drafts[index].destLine): duplicate dest"
            }
        }
    }
    var resolved: [(line: Int, path: String)] = []
    for draft in drafts {
        guard let identity = resolvedExistingDestination(draft.dest) else {
            continue
        }
        for previous in resolved {
            if sameDestination(previous.path, identity) {
                return "line \(draft.destLine): duplicate dest"
            }
        }
        resolved.append((draft.destLine, identity))
    }
    return nil
}

private func sameDestination(_ lhs: String, _ rhs: String) -> Bool {
    lhs.caseInsensitiveCompare(rhs) == .orderedSame
}

private func resolvedExistingDestination(_ path: String) -> String? {
    guard FileManager.default.fileExists(atPath: path) else {
        return nil
    }
    switch PathContainment.resolvePath(path) {
    case .cycle:
        return nil
    case .path(let resolved):
        return resolved
    }
}
