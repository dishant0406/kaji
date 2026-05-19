import Foundation

enum LSPMessageFramer {
    static func frame(_ payload: Data) -> Data {
        var data = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
        data.append(payload)
        return data
    }

    static func extractMessages(from buffer: inout Data) -> [Data] {
        var messages: [Data] = []
        while let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
            let headerData = buffer[..<headerRange.lowerBound]
            guard let header = String(data: headerData, encoding: .utf8),
                  let length = contentLength(from: header)
            else {
                buffer.removeSubrange(..<headerRange.upperBound)
                continue
            }
            let bodyStart = headerRange.upperBound
            let bodyEnd = bodyStart + length
            guard buffer.count >= bodyEnd else { break }
            messages.append(buffer[bodyStart ..< bodyEnd])
            buffer.removeSubrange(..<bodyEnd)
        }
        return messages
    }

    private static func contentLength(from header: String) -> Int? {
        let lengths: [Int] = header.components(separatedBy: "\r\n").compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
            return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lengths.first
    }
}
