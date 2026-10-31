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

func parseBackupConfig(_ text: String) -> Result<ParsedBackupConfig, BackupConfigError> {
    let root: [String: TomlValue]
    switch parseTomlSubset(text) {
    case .failure(let error):
        return .failure(BackupConfigError(message: error.message))
    case .success(let table):
        root = table
    }

    for (key, value) in root where key != "concurrency" && key != "folder" {
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

    let folders = drafts.map { FolderPair(source: $0.source, dest: $0.dest) }
    return .success(ParsedBackupConfig(folders: folders, concurrency: concurrency))
}

private struct FolderDraft {
    var source: String
    var dest: String
    var destLine: Int
}

private func parseFolderRow(_ row: [String: TomlValue]) -> Result<FolderDraft, BackupConfigError> {
    var source: String?
    var dest: String?
    var destLine = 0
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
    return .success(FolderDraft(source: source, dest: dest, destLine: destLine))
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
