import Foundation
import Network

final class MonacoAssetServer: @unchecked Sendable {
    static let shared = MonacoAssetServer()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "KajiMonacoAssetServer")
    private var listener: NWListener?
    private var port: UInt16?
    private let rootURLProvider: () -> URL?

    init(rootURLProvider: @escaping () -> URL? = MonacoAssetServer.defaultRootURL) {
        self.rootURLProvider = rootURLProvider
    }

    func ensureStarted() -> URL? {
        if let existing = lock.withLock({ port }) {
            return URL(string: "http://127.0.0.1:\(existing)/index.html")
        }
        guard let root = rootURLProvider(), Self.isReadableDirectory(root) else { return nil }
        guard let listener = try? NWListener(using: .tcp, on: .any) else { return nil }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                ready.signal()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection, root: root.standardizedFileURL.resolvingSymlinksInPath())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 2) == .success, let assignedPort = listener.port?.rawValue else {
            listener.cancel()
            return nil
        }
        lock.withLock {
            self.listener = listener
            self.port = assignedPort
        }
        return URL(string: "http://127.0.0.1:\(assignedPort)/index.html")
    }

    func stop() {
        let listener = lock.withLock { () -> NWListener? in
            let value = self.listener
            self.listener = nil
            self.port = nil
            return value
        }
        listener?.cancel()
    }

    private func handle(_ connection: NWConnection, root: URL) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
            let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let response = Self.response(for: raw, root: root)
            connection.send(content: response.data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    static func response(for rawRequest: String, root: URL) -> MonacoAssetHTTPResponse {
        guard let request = MonacoAssetHTTPRequest(raw: rawRequest) else { return .badRequest() }
        guard request.method == "GET" || request.method == "HEAD" else { return .methodNotAllowed() }
        guard let fileURL = resolvedFileURL(for: request.path, root: root) else { return .notFound() }
        guard let data = try? Data(contentsOf: fileURL) else { return .notFound() }
        return MonacoAssetHTTPResponse(
            status: "200 OK",
            contentType: contentType(for: fileURL),
            cacheControl: cacheControl(for: fileURL),
            body: request.method == "HEAD" ? Data() : data
        )
    }

    static func resolvedFileURL(for requestPath: String, root: URL) -> URL? {
        let pathOnly = requestPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? requestPath
        let rawPath = pathOnly == "/" ? "/index.html" : pathOnly
        guard rawPath.hasPrefix("/") else { return nil }
        guard let decoded = rawPath.removingPercentEncoding else { return nil }
        let relative = decoded.dropFirst()
        guard !relative.isEmpty, !relative.contains("\0") else { return nil }
        let candidate = root.appendingPathComponent(String(relative), isDirectory: false).standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
        return candidate
    }

    static func defaultRootURL() -> URL? {
        let candidates = [
            Bundle.appResources.resourceURL?.appendingPathComponent("MonacoEditor", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("MonacoEditor", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
                "Kaji/Resources/MonacoEditor",
                isDirectory: true
            ),
        ]
        return candidates.compactMap(\.self).first(where: isReadableDirectory)
    }

    private static func isReadableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js",
             "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json",
             "map": "application/json; charset=utf-8"
        case "wasm": "application/wasm"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg",
             "jpeg": "image/jpeg"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        case "ttf": "font/ttf"
        default: "application/octet-stream"
        }
    }

    private static func cacheControl(for url: URL) -> String {
        if url.lastPathComponent == "index.html" {
            return "no-cache"
        }
        return "public, max-age=31536000, immutable"
    }
}

struct MonacoAssetHTTPRequest {
    let method: String
    let path: String

    init?(raw: String) {
        let parts = raw.components(separatedBy: "\r\n\r\n")
        guard let head = parts.first else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let tokens = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard tokens.count >= 2 else { return nil }
        method = tokens[0]
        path = tokens[1]
    }
}

struct MonacoAssetHTTPResponse {
    let status: String
    let contentType: String
    let cacheControl: String
    let body: Data

    var data: Data {
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: \(cacheControl)",
            "X-Content-Type-Options: nosniff",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        var payload = Data(header.utf8)
        payload.append(body)
        return payload
    }

    static func badRequest() -> MonacoAssetHTTPResponse {
        MonacoAssetHTTPResponse(
            status: "400 Bad Request",
            contentType: "text/plain; charset=utf-8",
            cacheControl: "no-store",
            body: Data("bad request".utf8)
        )
    }

    static func methodNotAllowed() -> MonacoAssetHTTPResponse {
        MonacoAssetHTTPResponse(
            status: "405 Method Not Allowed",
            contentType: "text/plain; charset=utf-8",
            cacheControl: "no-store",
            body: Data("method not allowed".utf8)
        )
    }

    static func notFound() -> MonacoAssetHTTPResponse {
        MonacoAssetHTTPResponse(
            status: "404 Not Found",
            contentType: "text/plain; charset=utf-8",
            cacheControl: "no-store",
            body: Data("not found".utf8)
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
