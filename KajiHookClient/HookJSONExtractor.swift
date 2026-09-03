import Foundation

enum HookJSONExtractor {
    static func object(from input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    static func firstText(in value: Any?, keys: [String]) -> String? {
        guard let value else { return nil }
        if let object = value as? [String: Any] {
            for key in keys {
                if let text = object[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                if let text = textContent(from: object[key]), !text.isEmpty {
                    return text
                }
            }
            for child in object.values {
                if let text = firstText(in: child, keys: keys) {
                    return text
                }
            }
        }
        if let items = value as? [Any] {
            for item in items {
                if let text = firstText(in: item, keys: keys) {
                    return text
                }
            }
        }
        return nil
    }

    static func hasTruthyKey(_ object: [String: Any], keys: [String]) -> Bool {
        keys.contains { key in
            guard let value = object[key] else { return false }
            if let text = value as? String {
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !(value is NSNull)
        }
    }

    private static func textContent(from value: Any?) -> String? {
        if let items = value as? [[String: Any]] {
            let text = items.compactMap { item -> String? in
                if let text = item["text"] as? String {
                    return text
                }
                if let text = item["content"] as? String {
                    return text
                }
                return nil
            }.joined(separator: " ")
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
        return nil
    }
}
