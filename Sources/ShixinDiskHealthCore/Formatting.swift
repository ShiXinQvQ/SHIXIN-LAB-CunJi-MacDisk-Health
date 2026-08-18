import Foundation

public enum SmartFormatting {
    public static func byteString(_ bytes: Double?) -> String {
        guard let bytes else { return noValueText }
        let tb = bytes / 1_000_000_000_000
        let gb = bytes / 1_000_000_000
        if abs(tb) >= 1 {
            return String(format: "%.2f TB", tb)
        }
        return String(format: "%.1f GB", gb)
    }

    public static func sizeString(_ bytes: Int64?) -> String {
        guard let bytes else { return noValueText }
        return byteString(Double(bytes))
    }

    public static func speedMBps(_ value: Double?) -> String {
        guard let value else { return noValueText }
        if value >= 1_000 {
            return String(format: "%.2f GB/s", value / 1_000)
        }
        return String(format: "%.0f MB/s", value)
    }

    public static func seconds(_ value: TimeInterval?) -> String {
        guard let value else { return noValueText }
        if value >= 60 {
            return String(format: "%.1f %@", value / 60, minuteUnitText)
        }
        return String(format: "%.2f %@", value, secondUnitText)
    }

    public static func signedByteString(_ bytes: Double?) -> String {
        guard let bytes else { return noValueText }
        let prefix = bytes >= 0 ? "+" : "-"
        return prefix + byteString(abs(bytes))
    }

    public static func percent(_ value: Int?) -> String {
        guard let value else { return noValueText }
        return "\(value)%"
    }

    public static func celsius(_ value: Int?) -> String {
        guard let value else { return noValueText }
        return "\(value)°C"
    }

    public static func integer<T: BinaryInteger>(_ value: T?) -> String {
        guard let value else { return noValueText }
        let formatter = NumberFormatter()
        formatter.locale = displayLocale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: Int64(value))) ?? "\(value)"
    }

    public static func signedInteger<T: BinaryInteger>(_ value: T?) -> String {
        guard let value else { return noValueText }
        let sign = value >= 0 ? "+" : "-"
        return sign + integer(abs(Int64(value)))
    }

    public static func shortDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    public static func fileDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static var displayLocale: Locale {
        switch UserDefaults.standard.string(forKey: "appLanguagePreference") {
        case "zhHans":
            Locale(identifier: "zh-Hans")
        case "english":
            Locale(identifier: "en")
        case "japanese":
            Locale(identifier: "ja")
        default:
            Locale.autoupdatingCurrent
        }
    }

    private static var noValueText: String {
        switch UserDefaults.standard.string(forKey: "appLanguagePreference") {
        case "english":
            "Not returned"
        case "japanese":
            "未取得"
        default:
            "未返回"
        }
    }

    private static var minuteUnitText: String {
        switch UserDefaults.standard.string(forKey: "appLanguagePreference") {
        case "english":
            "min"
        case "japanese":
            "分"
        default:
            "分钟"
        }
    }

    private static var secondUnitText: String {
        switch UserDefaults.standard.string(forKey: "appLanguagePreference") {
        case "english":
            "s"
        case "japanese":
            "秒"
        default:
            "秒"
        }
    }
}
