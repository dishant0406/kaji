import Foundation

enum KajiAgentHostURIResolver {
    static func resolve(_ frame: KajiAgentRPCFrame, rootPath: String?) -> KajiAgentHostURIResult {
        guard frame.operation == "read", let url = frame.url, url.hasPrefix("kaji-file://") else {
            return .failure("Unsupported Kaji URI request.")
        }
        guard let rootPath else { return .failure("No active Kaji project.") }
        let path = String(url.dropFirst("kaji-file://".count)).removingPercentEncoding ?? ""
        guard !path.isEmpty else { return .failure("Missing file path.") }
        guard let safePath = KajiAgentWorkspacePathResolver.resolve(path, rootPath: rootPath) else {
            return .failure("File path is outside the active Kaji worktree.")
        }
        do {
            let text = try String(contentsOfFile: safePath, encoding: .utf8)
            return .success(content: text, contentType: "text/plain")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

struct KajiAgentHostURIResult {
    let content: String?
    let contentType: String?
    let error: String?

    static func success(content: String, contentType: String) -> Self {
        Self(content: content, contentType: contentType, error: nil)
    }

    static func failure(_ error: String) -> Self {
        Self(content: nil, contentType: nil, error: error)
    }

    func response(id: String) -> KajiAgentRPCFrame {
        KajiAgentRPCFrame(
            id: id,
            type: "host_uri_result",
            error: error,
            isError: error != nil,
            content: content,
            contentType: contentType
        )
    }
}
