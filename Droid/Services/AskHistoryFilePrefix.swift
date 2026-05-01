import Foundation

enum AskHistoryFilePrefix {
    static func lines(url: URL, maxLines: Int = 80, maxBytes: Int = 256 * 1024) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxBytes)) ?? Data()
        let prefix = String(decoding: data, as: UTF8.self)
        return prefix.split(separator: "\n", omittingEmptySubsequences: false).prefix(maxLines).map(String.init)
    }
}
