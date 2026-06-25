import Foundation

struct KajiBrowserControlArguments {
    let values: [String: Any]

    func string(_ key: String) -> String? {
        if let value = values[key] as? String { return value }
        if let number = values[key] as? NSNumber { return number.stringValue }
        return nil
    }

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = string(key), !value.isEmpty { return value }
        }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let value = values[key] as? Bool { return value }
        if let value = values[key] as? String { return Bool(value) }
        return (values[key] as? NSNumber)?.boolValue
    }

    func int(_ key: String) -> Int? {
        if let value = values[key] as? Int { return value }
        if let value = values[key] as? String { return Int(value) }
        return (values[key] as? NSNumber)?.intValue
    }

    func double(_ key: String) -> Double? {
        if let value = values[key] as? Double { return value }
        if let value = values[key] as? String { return Double(value) }
        return (values[key] as? NSNumber)?.doubleValue
    }

    func array(_ key: String) -> [Any]? {
        values[key] as? [Any]
    }

    func objects(_ key: String) -> [[String: Any]] {
        array(key)?.compactMap { $0 as? [String: Any] } ?? []
    }

    func strings(_ key: String) -> [String] {
        array(key)?.compactMap { item in
            if let value = item as? String { return value }
            if let number = item as? NSNumber { return number.stringValue }
            return nil
        } ?? []
    }

    func object(_ key: String) -> [String: Any]? {
        values[key] as? [String: Any]
    }
}
