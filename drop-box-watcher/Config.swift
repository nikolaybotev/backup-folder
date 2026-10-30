import Foundation

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

/// Returns `false` when permissions are too open (caller should exit 2 without parsing secrets).
func configPermissionsAcceptable(at path: String) -> Bool {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let perms = attrs[.posixPermissions] as? NSNumber
    else {
        return false
    }
    return perms.uint16Value & 0o077 == 0
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
    var watchFolder: String?
    var webhookURL: String?
    var webhookKey: String?
    var ignorePatterns: [String]?
    var logPath: String?

    var seenWatchFolder = false
    var seenWebhookURL = false
    var seenWebhookKey = false
    var seenIgnore = false
    var seenLogPath = false

    var section = ""
    var lineNumber = 0

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        lineNumber += 1
        var line = String(rawLine)
        if let hash = line.firstIndex(of: "#") {
            line = String(line[..<hash])
        }
        line = line.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }

        if line.hasPrefix("[") {
            guard line.hasSuffix("]"), line.count >= 3 else {
                return .failure(.parse("line \(lineNumber): bad table header"))
            }
            let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if name != "webhook", name != "behavior", name != "log" {
                return .failure(.parse("line \(lineNumber): unknown table [\(name)]"))
            }
            section = name
            continue
        }

        guard let eq = line.firstIndex(of: "=") else {
            return .failure(.parse("line \(lineNumber): expected key = value"))
        }
        let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
        let valuePart = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

        if section.isEmpty {
            if key != "watch_folder" {
                return .failure(.parse("line \(lineNumber): unknown key \(key)"))
            }
            if seenWatchFolder {
                return .failure(.parse("line \(lineNumber): duplicate watch_folder"))
            }
            seenWatchFolder = true
            switch parseBasicString(valuePart, line: lineNumber) {
            case .failure(let e): return .failure(e)
            case .success(let s): watchFolder = s
            }
            continue
        }

        switch section {
        case "webhook":
            if key == "url" {
                if seenWebhookURL { return .failure(.parse("line \(lineNumber): duplicate url")) }
                seenWebhookURL = true
                switch parseBasicString(valuePart, line: lineNumber) {
                case .failure(let e): return .failure(e)
                case .success(let s): webhookURL = s
                }
            } else if key == "key" {
                if seenWebhookKey { return .failure(.parse("line \(lineNumber): duplicate key")) }
                seenWebhookKey = true
                switch parseBasicString(valuePart, line: lineNumber) {
                case .failure(let e): return .failure(e)
                case .success(let s): webhookKey = s
                }
            } else {
                return .failure(.parse("line \(lineNumber): unknown key \(key) in [webhook]"))
            }
        case "behavior":
            if key != "ignore" {
                return .failure(.parse("line \(lineNumber): unknown key \(key) in [behavior]"))
            }
            if seenIgnore { return .failure(.parse("line \(lineNumber): duplicate ignore")) }
            seenIgnore = true
            switch parseStringArray(valuePart, line: lineNumber) {
            case .failure(let e): return .failure(e)
            case .success(let arr):
                for pattern in arr where pattern.contains("/") {
                    return .failure(.parse("line \(lineNumber): ignore pattern must not contain /"))
                }
                ignorePatterns = arr
            }
        case "log":
            if key != "path" {
                return .failure(.parse("line \(lineNumber): unknown key \(key) in [log]"))
            }
            if seenLogPath { return .failure(.parse("line \(lineNumber): duplicate path")) }
            seenLogPath = true
            switch parseBasicString(valuePart, line: lineNumber) {
            case .failure(let e): return .failure(e)
            case .success(let s): logPath = s
            }
        default:
            break
        }
    }

    guard let watchFolder, !watchFolder.isEmpty else {
        return .failure(.parse("missing watch_folder"))
    }
    if !watchFolder.hasPrefix("/") {
        return .failure(.parse("watch_folder must be an absolute path"))
    }
    guard let webhookURL else { return .failure(.parse("missing [webhook] url")) }
    guard let webhookKey else { return .failure(.parse("missing [webhook] key")) }
    if webhookKey.isEmpty { return .failure(.parse("webhook key must be non-empty")) }
    guard let ignorePatterns else { return .failure(.parse("missing [behavior] ignore")) }
    guard let logPath else { return .failure(.parse("missing [log] path")) }

    guard webhookURLAllowed(webhookURL) else {
        return .failure(.parse("webhook url not allowed"))
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

private func parseBasicString(_ valuePart: String, line: Int) -> Result<String, ConfigLoadError> {
    guard valuePart.first == "\"", valuePart.last == "\"", valuePart.count >= 2 else {
        return .failure(.parse("line \(line): value must be a basic string"))
    }
    let inner = String(valuePart.dropFirst().dropLast())
    var out = ""
    var i = inner.startIndex
    while i < inner.endIndex {
        let c = inner[i]
        if c == "\\" {
            let next = inner.index(after: i)
            guard next < inner.endIndex else {
                return .failure(.parse("line \(line): bad escape"))
            }
            let esc = inner[next]
            if esc == "\\" || esc == "\"" {
                out.append(esc)
                i = inner.index(after: next)
            } else {
                return .failure(.parse("line \(line): bad escape"))
            }
        } else {
            out.append(c)
            i = inner.index(after: i)
        }
    }
    return .success(out)
}

private func parseStringArray(_ valuePart: String, line: Int) -> Result<[String], ConfigLoadError> {
    guard valuePart.first == "[", valuePart.last == "]" else {
        return .failure(.parse("line \(line): ignore must be an array"))
    }
    let body = String(valuePart.dropFirst().dropLast())
    var items: [String] = []
    var i = body.startIndex
    while i < body.endIndex {
        while i < body.endIndex, body[i].isWhitespace || body[i] == "," {
            i = body.index(after: i)
        }
        if i >= body.endIndex { break }
        guard body[i] == "\"" else {
            return .failure(.parse("line \(line): array elements must be basic strings"))
        }
        var j = body.index(after: i)
        var escaped = false
        var raw = ""
        while j < body.endIndex {
            let c = body[j]
            if escaped {
                if c != "\\", c != "\"" {
                    return .failure(.parse("line \(line): bad escape"))
                }
                raw.append(c)
                escaped = false
                j = body.index(after: j)
                continue
            }
            if c == "\\" {
                escaped = true
                j = body.index(after: j)
                continue
            }
            if c == "\"" {
                break
            }
            raw.append(c)
            j = body.index(after: j)
        }
        guard j < body.endIndex, body[j] == "\"" else {
            return .failure(.parse("line \(line): unterminated string"))
        }
        items.append(raw)
        i = body.index(after: j)
    }
    return .success(items)
}
