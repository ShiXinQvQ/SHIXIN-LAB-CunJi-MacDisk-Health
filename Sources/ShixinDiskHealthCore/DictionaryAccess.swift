import Foundation

typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func dictionary(_ key: String) -> JSONObject? {
        self[key] as? JSONObject
    }

    func array(_ key: String) -> [Any]? {
        self[key] as? [Any]
    }

    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func bool(_ key: String) -> Bool? {
        self[key] as? Bool
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? Int64 { return Int(value) }
        if let value = self[key] as? Double { return Int(value) }
        if let value = self[key] as? String { return Int(value) }
        return nil
    }

    func int64(_ key: String) -> Int64? {
        if let value = self[key] as? Int64 { return value }
        if let value = self[key] as? Int { return Int64(value) }
        if let value = self[key] as? Double { return Int64(value) }
        if let value = self[key] as? String { return Int64(value) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let value = self[key] as? Double { return value }
        if let value = self[key] as? Int { return Double(value) }
        if let value = self[key] as? Int64 { return Double(value) }
        if let value = self[key] as? String { return Double(value) }
        return nil
    }
}
