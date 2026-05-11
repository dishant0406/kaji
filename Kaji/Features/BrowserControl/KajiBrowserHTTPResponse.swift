import Foundation

struct KajiBrowserHTTPResponse {
    let status: String
    let body: String

    var data: Data {
        let bytes = Data(body.utf8)
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(bytes.count)",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        var payload = Data(header.utf8)
        payload.append(bytes)
        return payload
    }
}
