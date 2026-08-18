import Foundation

public enum CSVExportSanitizer {
    public static func escape(_ value: String) -> String {
        let formulaSafe = protectFormula(value)
        let escaped = formulaSafe.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\r") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private static func protectFormula(_ value: String) -> String {
        guard let firstCharacter = value.first else { return value }
        let firstNonWhitespace = value.drop(while: \Character.isWhitespace).first
        let startsWithControlCharacter = ["\t", "\r", "\n"].contains(firstCharacter)
        let startsWithFormula = firstNonWhitespace.map { ["=", "+", "-", "@"].contains($0) } ?? false
        guard startsWithControlCharacter || startsWithFormula else {
            return value
        }
        return "'\(value)"
    }
}

public enum SmartPrivacyRedactor {
    private static let sensitiveKeyFragments = [
        "serial", "world_wide", "wwn", "logical_unit_id", "uuid", "udid", "nguid", "eui"
    ]

    public static func redactJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return redactText(text)
        }
        let redacted = redact(object)
        guard let output = try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: output, encoding: .utf8) else {
            return redactText(text)
        }
        return string
    }

    public static func privacySafeDisplayPath(
        _ path: String,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        let home = homeDirectory.hasSuffix("/")
            ? String(homeDirectory.dropLast())
            : homeDirectory
        guard !home.isEmpty, home != "/" else { return path }
        if path == home {
            return "~"
        }
        guard path.hasPrefix("\(home)/") else { return path }
        return "~\(path.dropFirst(home.count))"
    }

    public static func redactText(_ text: String) -> String {
        var redacted = text

        // A truncated JSON object cannot be parsed. If a sensitive key starts a
        // nested container, discard the remainder of the preview rather than
        // risk exposing identifiers from an unterminated object.
        if let expression = try? NSRegularExpression(pattern: containerValuePattern),
           let match = expression.firstMatch(
            in: redacted,
            range: NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
           ),
           let prefixRange = Range(match.range(at: 1), in: redacted) {
            redacted = String(redacted[..<prefixRange.upperBound]) + "<redacted>"
        }

        redacted = redacted.replacingOccurrences(
            of: quotedValuePattern,
            with: "$1\"<redacted>\"",
            options: .regularExpression
        )
        return redacted.replacingOccurrences(
            of: plainValuePattern,
            with: "$1<redacted>",
            options: .regularExpression
        )
    }

    private static func redact(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                if isSensitiveKey(pair.key) {
                    result[pair.key] = "<redacted>"
                } else {
                    result[pair.key] = redact(pair.value)
                }
            }
        }
        if let array = value as? [Any] {
            return array.map(redact)
        }
        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return sensitiveKeyFragments.contains { normalized.contains($0) }
    }

    private static let textSensitiveKey = #"(?:lu[\s_]+wwn(?:[\s_]+device[\s_]+id)?|serial(?:[\s_]+number)?|world[\s_]+wide(?:[\s_]+name)?|wwn|logical[\s_]+unit[\s_]+id|(?:platform[\s_]+)?uuid|(?:provisioning[\s_]+)?udid|nguid|eui(?:[\s_]*64)?)"#
    private static let keyAndSeparator = #"([\"']?\b"# + textSensitiveKey + #"[\"']?\s*[:=]\s*)"#
    private static let containerValuePattern = #"(?is)"# + keyAndSeparator + #"[\{\[]"#
    private static let quotedValuePattern = #"(?i)"# + keyAndSeparator + #"(?:\"(?:\\.|[^\"\r\n])*\"|'[^'\r\n]*')"#
    private static let plainValuePattern = #"(?i)"# + keyAndSeparator + #"[^,}\]\r\n]+"#
}
