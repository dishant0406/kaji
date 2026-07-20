import Foundation

struct KajiCodeChannel: Decodable, Equatable {
    let schemaVersion: Int
    let generatedAt: String
    let latest: String
    let entries: [KajiCodeChannelEntry]
}

struct KajiCodeChannelEntry: Decodable, Equatable {
    let version: String
    let protocolVersion: Int
    let minKajiVersion: String
    let maxKajiVersion: String?
    let assets: [String: KajiCodeChannelAsset]
}

struct KajiCodeChannelAsset: Decodable, Equatable {
    let url: URL
    let sha256: String
    let size: Int64
}

struct KajiCodeVersion: Comparable, Equatable {
    let rawValue: String
    private let parts: [Int]

    init(_ value: String) {
        rawValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        parts = cleaned.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    static func < (lhs: KajiCodeVersion, rhs: KajiCodeVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0 ..< count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return lhs.rawValue < rhs.rawValue
    }
}
