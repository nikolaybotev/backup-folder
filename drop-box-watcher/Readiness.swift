import Foundation

/// Stand-in for `URLUbiquitousItemDownloadingStatus` on Linux (FR7).
enum UbiquitousDownloadStatus: Equatable {
    case notDownloaded
    case downloaded
    case current
    case missing
}

enum ReadinessDecision: Equatable {
    case skip
    case ready
    case requestDownload
}

enum PathEntryKind: Equatable {
    case regularFile
    case directory
    case symbolicLink
    case other
}

/// Case-sensitive glob on a file name only: `*` matches any run of characters (FR3 / D11).
func ignorePatternMatches(_ pattern: String, fileName: String) -> Bool {
    globMatch(pattern: Array(pattern), name: Array(fileName), pi: 0, ni: 0)
}

func nameMatchesAnyIgnorePattern(_ fileName: String, patterns: [String]) -> Bool {
    for pattern in patterns where ignorePatternMatches(pattern, fileName: fileName) {
        return true
    }
    return false
}

private func globMatch(pattern: [Character], name: [Character], pi: Int, ni: Int) -> Bool {
    if pi == pattern.count {
        return ni == name.count
    }
    if pattern[pi] == "*" {
        if pi + 1 == pattern.count {
            return true
        }
        var n = ni
        while n <= name.count {
            if globMatch(pattern: pattern, name: name, pi: pi + 1, ni: n) {
                return true
            }
            n += 1
        }
        return false
    }
    if ni == name.count {
        return false
    }
    if pattern[pi] == name[ni] {
        return globMatch(pattern: pattern, name: name, pi: pi + 1, ni: ni + 1)
    }
    return false
}

/// Pure readiness decision (FR7). Does not touch FileManager or iCloud APIs.
func readinessDecision(
    fileName: String,
    ignorePatterns: [String],
    entryKind: PathEntryKind,
    isUbiquitous: Bool,
    ubiquitousStatus: UbiquitousDownloadStatus,
    ubiquitousDownloadInFlight: Bool
) -> ReadinessDecision {
    if nameMatchesAnyIgnorePattern(fileName, patterns: ignorePatterns) {
        return .skip
    }
    switch entryKind {
    case .directory, .symbolicLink, .other:
        return .skip
    case .regularFile:
        break
    }
    if !isUbiquitous {
        return .ready
    }
    if ubiquitousStatus == .current, !ubiquitousDownloadInFlight {
        return .ready
    }
    return .requestDownload
}
