import Foundation

struct EditorLanguagePair: Equatable {
    let open: String
    let close: String
}

struct EditorLanguagePairSet {
    let pairs: [EditorLanguagePair]
    let openingPairs: [unichar: unichar]
    let closingPairs: [unichar: unichar]

    static let fallback = EditorLanguagePairPolicy.makePairSet(configuredPairs: [])
}

enum EditorLanguagePairPolicy {
    static func makePairSet(configuredPairs: [[String]]) -> EditorLanguagePairSet {
        let pairs = parsedPairs(configuredPairs)
        let effectivePairs = pairs.isEmpty ? fallbackPairs : pairs
        let openingPairs: [unichar: unichar] = Dictionary(uniqueKeysWithValues: effectivePairs.compactMap { pair in
            guard let open = pair.open.utf16.first, let close = pair.close.utf16.first else { return nil }
            return (open, close)
        })
        let closingPairs: [unichar: unichar] = Dictionary(uniqueKeysWithValues: openingPairs.map { ($0.value, $0.key) })
        return EditorLanguagePairSet(pairs: effectivePairs, openingPairs: openingPairs, closingPairs: closingPairs)
    }

    private static func parsedPairs(_ configuredPairs: [[String]]) -> [EditorLanguagePair] {
        configuredPairs.compactMap { pair in
            guard pair.count == 2, pair[0].utf16.count == 1, pair[1].utf16.count == 1 else { return nil }
            return EditorLanguagePair(open: pair[0], close: pair[1])
        }
    }

    private static let fallbackPairs = [
        EditorLanguagePair(open: "(", close: ")"),
        EditorLanguagePair(open: "[", close: "]"),
        EditorLanguagePair(open: "{", close: "}"),
        EditorLanguagePair(open: "\"", close: "\""),
        EditorLanguagePair(open: "'", close: "'"),
    ]
}
