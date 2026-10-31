import Foundation
#if canImport(ToolConfig)
import ToolConfig
#endif

struct DropBoxWatcherConfig: Equatable {
    var watchFolder: String
    var webhookURL: String
    var webhookKey: String
    var ignorePatterns: [String]
    var logPath: String
}

enum ConfigLoadError: Error, Equatable {
    case permissionsTooOpen
    case parse(String)
    case io(String)
}

func loadConfig(from path: String) -> Result<DropBoxWatcherConfig, ConfigLoadError> {
    guard configPermissionsAcceptable(at: path) else {
        return .failure(.permissionsTooOpen)
    }
    let text: String
    do {
        text = try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        return .failure(.io(error.localizedDescription))
    }
    return parseConfigTOML(text)
}

func parseConfigTOML(_ text: String) -> Result<DropBoxWatcherConfig, ConfigLoadError> {
    let root: [String: TomlValue]
    switch parseTomlSubset(text) {
    case .failure(let error):
        return .failure(.parse(error.message))
    case .success(let table):
        root = table
    }
    if let message = disallowedWatcherValue(in: root) {
        return .failure(.parse(message))
    }

    var watchFolder: String?
    var watchFolderLine = 0
    var webhookURL: String?
    var webhookKey: String?
    var webhookKeyLine = 0
    var webhookURLLine = 0
    var ignorePatterns: [String]?
    var logPath: String?

    for (key, value) in root {
        switch key {
        case "watch_folder":
            switch requireString(value, key: key) {
            case .failure(let error):
                return .failure(error)
            case .success(let text):
                watchFolder = text
                watchFolderLine = value.line
            }
        case "webhook":
            switch requireTable(value, key: key) {
            case .failure(let error):
                return .failure(error)
            case .success(let table):
                switch parseWebhookTable(table) {
                case .failure(let error):
                    return .failure(error)
                case .success(let webhook):
                    webhookURL = webhook.url
                    webhookURLLine = webhook.urlLine
                    webhookKey = webhook.key
                    webhookKeyLine = webhook.keyLine
                }
            }
        case "behavior":
            switch requireTable(value, key: key) {
            case .failure(let error):
                return .failure(error)
            case .success(let table):
                switch parseBehaviorTable(table) {
                case .failure(let error):
                    return .failure(error)
                case .success(let patterns):
                    ignorePatterns = patterns
                }
            }
        case "log":
            switch requireTable(value, key: key) {
            case .failure(let error):
                return .failure(error)
            case .success(let table):
                switch parseLogTable(table) {
                case .failure(let error):
                    return .failure(error)
                case .success(let path):
                    logPath = path
                }
            }
        default:
            if case .table = value.content {
                return .failure(.parse("line \(value.line): unknown table [\(key)]"))
            }
            return .failure(.parse("line \(value.line): unknown key \(key)"))
        }
    }

    guard let watchFolder, !watchFolder.isEmpty else {
        return .failure(.parse("missing watch_folder"))
    }
    if !watchFolder.hasPrefix("/") {
        return .failure(.parse("line \(watchFolderLine): watch_folder must be an absolute path"))
    }
    guard let webhookURL else {
        return .failure(.parse("missing [webhook] url"))
    }
    guard let webhookKey else {
        return .failure(.parse("missing [webhook] key"))
    }
    if webhookKey.isEmpty {
        return .failure(.parse("line \(webhookKeyLine): webhook key must be non-empty"))
    }
    guard let ignorePatterns else {
        return .failure(.parse("missing [behavior] ignore"))
    }
    guard let logPath else {
        return .failure(.parse("missing [log] path"))
    }
    guard webhookURLAllowed(webhookURL) else {
        return .failure(.parse("line \(webhookURLLine): webhook url not allowed"))
    }

    return .success(
        DropBoxWatcherConfig(
            watchFolder: watchFolder,
            webhookURL: webhookURL,
            webhookKey: webhookKey,
            ignorePatterns: ignorePatterns,
            logPath: logPath
        )
    )
}

func webhookURLAllowed(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
        return false
    }
    if scheme == "https" { return true }
    if scheme != "http" { return false }
    guard let host = url.host?.lowercased() else { return false }
    if host != "127.0.0.1", host != "localhost" { return false }
    return url.port != nil
}

private struct WebhookFields {
    var url: String
    var urlLine: Int
    var key: String
    var keyLine: Int
}

private func parseWebhookTable(_ table: [String: TomlValue]) -> Result<WebhookFields, ConfigLoadError> {
    var url: String?
    var urlLine = 0
    var key: String?
    var keyLine = 0
    for (name, value) in table {
        switch name {
        case "url":
            switch requireString(value, key: name) {
            case .failure(let error):
                return .failure(error)
            case .success(let text):
                url = text
                urlLine = value.line
            }
        case "key":
            switch requireString(value, key: name) {
            case .failure(let error):
                return .failure(error)
            case .success(let text):
                key = text
                keyLine = value.line
            }
        default:
            return .failure(.parse("line \(value.line): unknown key \(name) in [webhook]"))
        }
    }
    guard let url else {
        return .failure(.parse("missing [webhook] url"))
    }
    guard let key else {
        return .failure(.parse("missing [webhook] key"))
    }
    return .success(WebhookFields(url: url, urlLine: urlLine, key: key, keyLine: keyLine))
}

private func parseBehaviorTable(_ table: [String: TomlValue]) -> Result<[String], ConfigLoadError> {
    var ignore: [String]?
    for (name, value) in table {
        if name != "ignore" {
            return .failure(.parse("line \(value.line): unknown key \(name) in [behavior]"))
        }
        switch value.content {
        case .arrayOfStrings(let patterns):
            for pattern in patterns where pattern.contains("/") {
                return .failure(.parse("line \(value.line): ignore pattern must not contain /"))
            }
            ignore = patterns
        default:
            return .failure(.parse("line \(value.line): expected an array of strings for ignore"))
        }
    }
    guard let ignore else {
        return .failure(.parse("missing [behavior] ignore"))
    }
    return .success(ignore)
}

private func parseLogTable(_ table: [String: TomlValue]) -> Result<String, ConfigLoadError> {
    var path: String?
    for (name, value) in table {
        if name != "path" {
            return .failure(.parse("line \(value.line): unknown key \(name) in [log]"))
        }
        switch requireString(value, key: name) {
        case .failure(let error):
            return .failure(error)
        case .success(let text):
            path = text
        }
    }
    guard let path else {
        return .failure(.parse("missing [log] path"))
    }
    return .success(path)
}

private func requireString(_ value: TomlValue, key: String) -> Result<String, ConfigLoadError> {
    guard case .string(let text) = value.content else {
        return .failure(.parse("line \(value.line): expected a string for \(key)"))
    }
    return .success(text)
}

private func requireTable(_ value: TomlValue, key: String) -> Result<[String: TomlValue], ConfigLoadError> {
    guard case .table(let table) = value.content else {
        return .failure(.parse("line \(value.line): expected a table for \(key)"))
    }
    return .success(table)
}

private func disallowedWatcherValue(in root: [String: TomlValue]) -> String? {
    for (_, value) in root {
        if let message = disallowedWatcherValue(value) {
            return message
        }
    }
    return nil
}

private func disallowedWatcherValue(_ value: TomlValue) -> String? {
    switch value.content {
    case .integer:
        return "line \(value.line): integer value is not allowed"
    case .arrayOfTables:
        return "line \(value.line): array of tables is not allowed"
    case .table(let table):
        for (_, child) in table {
            if let message = disallowedWatcherValue(child) {
                return message
            }
        }
        return nil
    case .string, .arrayOfStrings:
        return nil
    }
}
