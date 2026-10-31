import Foundation

public struct TomlValue: Equatable {
    public let line: Int
    public let content: Content

    public enum Content: Equatable {
        case string(String)
        case integer(Int)
        case arrayOfStrings([String])
        case table([String: TomlValue])
        case arrayOfTables([[String: TomlValue]])
    }

    public init(line: Int, content: Content) {
        self.line = line
        self.content = content
    }
}

public struct TomlParseError: Error, Equatable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

public func parseTomlSubset(_ text: String) -> Result<[String: TomlValue], TomlParseError> {
    switch TomlSubsetParser().parse(text) {
    case .success(let table):
        return .success(table)
    case .failure(let error):
        return .failure(TomlParseError(message: error.message))
    }
}

/// Returns `false` when permissions are too open (caller should exit 2 without parsing secrets).
public func configPermissionsAcceptable(at path: String) -> Bool {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let perms = attrs[.posixPermissions] as? NSNumber
    else {
        return false
    }
    return perms.uint16Value & 0o077 == 0
}

private final class MutableTable {
    let headerLine: Int
    var entries: [String: BuildValue] = [:]

    init(headerLine: Int) {
        self.headerLine = headerLine
    }
}

private final class MutableTableArray {
    var tables: [MutableTable] = []
}

private struct ParseFailure: Error {
    var message: String
}

private enum BuildValue {
    case string(Int, String)
    case integer(Int, Int)
    case arrayOfStrings(Int, [String])
    case table(MutableTable)
    case arrayOfTables(Int, MutableTableArray)
}

private final class TomlSubsetParser {
    private let root: MutableTable
    private var current: MutableTable

    init() {
        let root = MutableTable(headerLine: 0)
        self.root = root
        self.current = root
    }

    func parse(_ text: String) -> Result<[String: TomlValue], ParseFailure> {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lineNumber = 0
        var start = normalized.startIndex
        var index = normalized.startIndex
        while index < normalized.endIndex {
            if normalized[index] == "\n" {
                lineNumber += 1
                if let message = parseLine(String(normalized[start..<index]), lineNumber) {
                    return .failure(ParseFailure(message: message))
                }
                index = normalized.index(after: index)
                start = index
            } else {
                index = normalized.index(after: index)
            }
        }
        if start < normalized.endIndex {
            lineNumber += 1
            if let message = parseLine(String(normalized[start...]), lineNumber) {
                return .failure(ParseFailure(message: message))
            }
        }
        return .success(freeze(root))
    }

    private func parseLine(_ raw: String, _ line: Int) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") {
            return nil
        }
        if trimmed.hasPrefix("[[") {
            return parseArrayHeader(trimmed, line)
        }
        if trimmed.hasPrefix("[") {
            return parseTableHeader(trimmed, line)
        }
        return parseAssignment(trimmed, line)
    }

    private func parseTableHeader(_ trimmed: String, _ line: Int) -> String? {
        guard let close = trimmed.firstIndex(of: "]") else {
            return lineMessage(line, "bad table header")
        }
        let name = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        let rest = trimmed[trimmed.index(after: close)...]
        if !isCommentOrEmpty(String(rest)) {
            return lineMessage(line, "bad table header")
        }
        return defineTable(name: String(name), line: line, array: false)
    }

    private func parseArrayHeader(_ trimmed: String, _ line: Int) -> String? {
        guard let range = trimmed.range(of: "]]") else {
            return lineMessage(line, "bad table header")
        }
        let name = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<range.lowerBound]
        let rest = trimmed[range.upperBound...]
        if !isCommentOrEmpty(String(rest)) {
            return lineMessage(line, "bad table header")
        }
        return defineTable(name: String(name), line: line, array: true)
    }

    private func defineTable(name rawName: String, line: Int, array: Bool) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        if name.contains(".") {
            return lineMessage(line, "dotted key")
        }
        if !isBareKey(name) {
            return lineMessage(line, "bad table header")
        }
        if root.entries[name] != nil {
            if array, case .arrayOfTables(_, let existing) = root.entries[name] {
                let table = MutableTable(headerLine: line)
                existing.tables.append(table)
                current = table
                return nil
            }
            return lineMessage(line, "duplicate key \(name)")
        }
        if array {
            let table = MutableTable(headerLine: line)
            let tables = MutableTableArray()
            tables.tables.append(table)
            root.entries[name] = .arrayOfTables(line, tables)
            current = table
            return nil
        }
        let table = MutableTable(headerLine: line)
        root.entries[name] = .table(table)
        current = table
        return nil
    }

    private func parseAssignment(_ trimmed: String, _ line: Int) -> String? {
        guard let eq = trimmed.firstIndex(of: "=") else {
            return lineMessage(line, "expected key = value")
        }
        let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
        if key.isEmpty {
            return lineMessage(line, "expected key = value")
        }
        if key.contains(".") {
            return lineMessage(line, "dotted key")
        }
        if !isBareKey(key) {
            return lineMessage(line, "invalid key")
        }
        let valuePart = String(trimmed[trimmed.index(after: eq)...])
        switch parseValue(line, valuePart) {
        case .failure(let error):
            return error.message
        case .success(let value):
            if current.entries[key] != nil {
                return lineMessage(line, "duplicate key \(key)")
            }
            current.entries[key] = value
            return nil
        }
    }

    private func parseValue(_ line: Int, _ raw: String) -> Result<BuildValue, ParseFailure> {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            return .failure(rejected(line, "expected a value"))
        }
        if text.hasPrefix("\"\"\"") || text.hasPrefix("'''") {
            return .failure(rejected(line, "multiline string"))
        }
        if text.hasPrefix("'") {
            return .failure(rejected(line, "literal string"))
        }
        if text.hasPrefix("{") {
            return .failure(rejected(line, "inline table"))
        }
        if text.hasPrefix("\"") {
            switch parseBasicString(in: text, at: text.startIndex, line: line) {
            case .failure(let message):
                return .failure(message)
            case .success(let parsed):
                if let message = trailingCommentOnly(line, String(text[parsed.next...])) {
                    return .failure(ParseFailure(message: message))
                }
                return .success(.string(line, parsed.value))
            }
        }
        if text.hasPrefix("[") {
            switch parseStringArray(in: text, at: text.startIndex, line: line) {
            case .failure(let message):
                return .failure(message)
            case .success(let parsed):
                if let message = trailingCommentOnly(line, String(text[parsed.next...])) {
                    return .failure(ParseFailure(message: message))
                }
                return .success(.arrayOfStrings(line, parsed.items))
            }
        }
        let tokenEnd = text.firstIndex(where: { $0.isWhitespace || $0 == "#" }) ?? text.endIndex
        let token = String(text[..<tokenEnd])
        if let message = trailingCommentOnly(line, String(text[tokenEnd...])) {
            return .failure(ParseFailure(message: message))
        }
        return classifyBare(line, token)
    }

    private func parseBasicString(
        in text: String,
        at start: String.Index,
        line: Int
    ) -> Result<(value: String, next: String.Index), ParseFailure> {
        var index = text.index(after: start)
        var out = ""
        while index < text.endIndex {
            let character = text[index]
            if character == "\\" {
                let next = text.index(after: index)
                if next >= text.endIndex {
                    return .failure(rejected(line, "bad escape"))
                }
                let escaped = text[next]
                if escaped == "\\" || escaped == "\"" {
                    out.append(escaped)
                    index = text.index(after: next)
                    continue
                }
                return .failure(rejected(line, "bad escape"))
            }
            if character == "\"" {
                return .success((out, text.index(after: index)))
            }
            out.append(character)
            index = text.index(after: index)
        }
        return .failure(rejected(line, "unterminated string"))
    }

    private func parseStringArray(
        in text: String,
        at start: String.Index,
        line: Int
    ) -> Result<(items: [String], next: String.Index), ParseFailure> {
        var index = text.index(after: start)
        var items: [String] = []
        var expectValue = true
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
                continue
            }
            if character == "#" {
                return .failure(rejected(line, "unterminated array"))
            }
            if character == "]" {
                return .success((items, text.index(after: index)))
            }
            if character == "," {
                if expectValue {
                    return .failure(rejected(line, "expected a string in the array"))
                }
                expectValue = true
                index = text.index(after: index)
                continue
            }
            if character == "\"" {
                if !expectValue {
                    return .failure(rejected(line, "expected a comma in the array"))
                }
                switch parseBasicString(in: text, at: index, line: line) {
                case .failure(let message):
                    return .failure(message)
                case .success(let parsed):
                    items.append(parsed.value)
                    index = parsed.next
                    expectValue = false
                }
                continue
            }
            return .failure(rejected(line, "array elements must be basic strings"))
        }
        return .failure(rejected(line, "unterminated array"))
    }

    private func classifyBare(_ line: Int, _ token: String) -> Result<BuildValue, ParseFailure> {
        if token.isEmpty {
            return .failure(rejected(line, "expected a value"))
        }
        if isIntegerToken(token) {
            guard let number = Int(token) else {
                return .failure(rejected(line, "invalid integer"))
            }
            return .success(.integer(line, number))
        }
        if isFloatToken(token) {
            return .failure(rejected(line, "float"))
        }
        if isRejectedIntegerToken(token) {
            return .failure(rejected(line, "invalid integer"))
        }
        if token == "true" || token == "false" {
            return .failure(rejected(line, "boolean"))
        }
        if isDateToken(token) {
            return .failure(rejected(line, "date"))
        }
        return .failure(rejected(line, "unsupported value"))
    }

    private func freeze(_ table: MutableTable) -> [String: TomlValue] {
        var out: [String: TomlValue] = [:]
        for (key, value) in table.entries {
            out[key] = freeze(value)
        }
        return out
    }

    private func freeze(_ value: BuildValue) -> TomlValue {
        switch value {
        case .string(let line, let text):
            return TomlValue(line: line, content: .string(text))
        case .integer(let line, let number):
            return TomlValue(line: line, content: .integer(number))
        case .arrayOfStrings(let line, let items):
            return TomlValue(line: line, content: .arrayOfStrings(items))
        case .table(let table):
            return TomlValue(line: table.headerLine, content: .table(freeze(table)))
        case .arrayOfTables(let line, let tables):
            let rows = tables.tables.map { freeze($0) }
            return TomlValue(line: line, content: .arrayOfTables(rows))
        }
    }
}

private func lineMessage(_ line: Int, _ reason: String) -> String {
    "line \(line): \(reason)"
}

private func rejected(_ line: Int, _ reason: String) -> ParseFailure {
    ParseFailure(message: lineMessage(line, reason))
}

private func isCommentOrEmpty(_ rest: String) -> Bool {
    let trimmed = rest.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty || trimmed.hasPrefix("#")
}

private func trailingCommentOnly(_ line: Int, _ rest: String) -> String? {
    if isCommentOrEmpty(rest) {
        return nil
    }
    return lineMessage(line, "unexpected trailing characters")
}

private func isBareKey(_ key: String) -> Bool {
    if key.isEmpty {
        return false
    }
    for character in key {
        let ok = (character >= "A" && character <= "Z")
            || (character >= "a" && character <= "z")
            || (character >= "0" && character <= "9")
            || character == "_"
            || character == "-"
        if !ok {
            return false
        }
    }
    return true
}

private func isASCIIDigit(_ character: Character) -> Bool {
    character >= "0" && character <= "9"
}

private func isIntegerToken(_ token: String) -> Bool {
    var digits = Substring(token)
    if digits.first == "-" {
        digits = digits.dropFirst()
    }
    return !digits.isEmpty && digits.allSatisfy(isASCIIDigit)
}

private func isRejectedIntegerToken(_ token: String) -> Bool {
    var rest = Substring(token)
    if rest.first == "+" || rest.first == "-" {
        rest = rest.dropFirst()
    }
    if rest.isEmpty {
        return false
    }
    var sawDigit = false
    var sawUnderscore = false
    for character in rest {
        if isASCIIDigit(character) {
            sawDigit = true
        } else if character == "_" {
            sawUnderscore = true
        } else {
            return false
        }
    }
    return sawDigit && (token.hasPrefix("+") || sawUnderscore)
}

private func isFloatToken(_ token: String) -> Bool {
    switch token.lowercased() {
    case "inf", "+inf", "-inf", "nan", "+nan", "-nan":
        return true
    default:
        break
    }
    var rest = Substring(token)
    if rest.first == "+" || rest.first == "-" {
        rest = rest.dropFirst()
    }
    var sawDigit = false
    var sawDot = false
    var index = rest.startIndex
    while index < rest.endIndex {
        let character = rest[index]
        if isASCIIDigit(character) {
            sawDigit = true
            index = rest.index(after: index)
            continue
        }
        if character == "." && !sawDot {
            sawDot = true
            index = rest.index(after: index)
            continue
        }
        if (character == "e" || character == "E") && sawDigit {
            index = rest.index(after: index)
            if index < rest.endIndex && (rest[index] == "+" || rest[index] == "-") {
                index = rest.index(after: index)
            }
            var exponentDigits = false
            while index < rest.endIndex && isASCIIDigit(rest[index]) {
                exponentDigits = true
                index = rest.index(after: index)
            }
            return exponentDigits && index == rest.endIndex && (sawDigit || sawDot)
        }
        return false
    }
    return sawDot && sawDigit
}

private func isDateToken(_ token: String) -> Bool {
    if let first = token.first, isASCIIDigit(first), token.contains(":") {
        return true
    }
    let parts = token.split(separator: "-", omittingEmptySubsequences: false)
    if parts.count >= 3, parts[0].count == 4, parts[0].allSatisfy(isASCIIDigit) {
        return true
    }
    return false
}
