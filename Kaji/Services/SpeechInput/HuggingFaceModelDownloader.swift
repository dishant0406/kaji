import Foundation

actor HuggingFaceModelDownloader {
    typealias ProgressHandler = @Sendable (SpeechDownloadProgress) -> Void

    private static let maximumTreeDepth = 32
    private static let maximumFileCount = 10000
    private static let maximumListingBytes = 16 * 1024 * 1024
    private static let maximumFileBytes: Int64 = 2 * 1024 * 1024 * 1024
    private static let maximumDownloadBytes: Int64 = 8 * 1024 * 1024 * 1024

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(model: SpeechInputModel, progress: ProgressHandler? = nil) async throws {
        progress?(.listing)
        let files = try await remoteFiles(for: model)
        guard !files.isEmpty else { throw SpeechModelDownloadError.noFiles(model.id) }
        try FileManager.default.createDirectory(at: model.cacheURL, withIntermediateDirectories: true)
        let totalBytes = try totalDownloadBytes(files)
        var completedBytes: Int64 = 0
        for (index, file) in files.enumerated() {
            let destination = try destinationURL(root: model.cacheURL, relativePath: file.localPath)
            if FileManager.default.fileExists(atPath: destination.path) {
                completedBytes += max(0, file.size)
                continue
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let request = try authorizedRequest(url: resolveURL(model: model, path: file.remotePath))
            let baseBytes = completedBytes
            let downloader = SpeechModelFileDownloader(destination: destination, maximumBytes: Self.maximumFileBytes) { written, _ in
                progress?(Self.progress(index: index, count: files.count, completed: baseBytes, written: written, total: totalBytes))
            }
            try await downloader.download(request: request)
            completedBytes += max(0, file.size)
            progress?(Self.progress(index: index + 1, count: files.count, completed: completedBytes, written: 0, total: totalBytes))
        }
        try verify(model)
    }

    private func remoteFiles(for model: SpeechInputModel) async throws -> [SpeechModelRemoteFile] {
        var files: [SpeechModelRemoteFile] = []
        try await collectFiles(path: model.subPath ?? "", model: model, depth: 0, output: &files)
        let missingAux = SpeechModelRemoteFileMapper.missingAuxiliaryFiles(from: files, requiredFiles: model.requiredFiles)
        if !missingAux.isEmpty {
            try await collectRootAuxiliaryFiles(model: model, names: Set(missingAux), output: &files)
        }
        return Array(Set(files)).sorted { $0.remotePath < $1.remotePath }
    }

    private func collectFiles(
        path: String,
        model: SpeechInputModel,
        depth: Int,
        output: inout [SpeechModelRemoteFile]
    ) async throws {
        guard depth <= Self.maximumTreeDepth,
              path.isEmpty || SpeechModelRemoteFileMapper.isSafePath(path)
        else {
            throw SpeechModelDownloadError.downloadLimitExceeded
        }
        let items = try await treeItems(model: model, path: path)
        for item in items {
            if item.type == "directory" {
                try await collectFiles(path: item.path, model: model, depth: depth + 1, output: &output)
            }
            if item.type == "file", SpeechModelRemoteFileMapper.shouldInclude(
                remotePath: item.path,
                subPath: model.subPath,
                requiredFiles: model.requiredFiles
            ) {
                guard output.count < Self.maximumFileCount,
                      let size = item.size,
                      size >= 0,
                      Int64(size) <= Self.maximumFileBytes
                else {
                    throw SpeechModelDownloadError.downloadLimitExceeded
                }
                output.append(SpeechModelRemoteFile(
                    remotePath: item.path,
                    localPath: SpeechModelRemoteFileMapper.localPath(remotePath: item.path, subPath: model.subPath),
                    size: Int64(size)
                ))
            }
        }
    }

    private func collectRootAuxiliaryFiles(
        model: SpeechInputModel,
        names: Set<String>,
        output: inout [SpeechModelRemoteFile]
    ) async throws {
        let items = try await treeItems(model: model, path: "")
        for item in items where item.type == "file" && names.contains((item.path as NSString).lastPathComponent) {
            guard SpeechModelRemoteFileMapper.isSafePath(item.path),
                  output.count < Self.maximumFileCount,
                  let size = item.size,
                  size >= 0,
                  Int64(size) <= Self.maximumFileBytes
            else {
                throw SpeechModelDownloadError.downloadLimitExceeded
            }
            output.append(SpeechModelRemoteFile(remotePath: item.path, localPath: item.path, size: Int64(size)))
        }
    }

    private func treeItems(model: SpeechInputModel, path: String) async throws -> [SpeechModelTreeItem] {
        let request = try authorizedRequest(url: apiURL(model: model, path: path))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, path: path)
        guard data.count <= Self.maximumListingBytes else { throw SpeechModelDownloadError.downloadLimitExceeded }
        do {
            return try JSONDecoder().decode([SpeechModelTreeItem].self, from: data)
        } catch {
            throw SpeechModelDownloadError.invalidResponse(path)
        }
    }

    private func verify(_ model: SpeechInputModel) throws {
        for file in model.requiredFiles {
            guard FileManager.default.fileExists(atPath: model.cacheURL.appendingPathComponent(file).path) else {
                throw SpeechModelDownloadError.missingRequiredFile(file)
            }
        }
    }

    private func validate(response: URLResponse, path: String) throws {
        guard let response = response as? HTTPURLResponse else { return }
        guard let url = response.url, SpeechModelRegistrySecurity.shouldAttachToken(to: url) else {
            throw SpeechModelDownloadError.invalidResponse(path)
        }
        guard 200 ..< 300 ~= response.statusCode else { throw SpeechModelDownloadError.httpStatus(response.statusCode, path) }
    }

    private func totalDownloadBytes(_ files: [SpeechModelRemoteFile]) throws -> Int64 {
        var total: Int64 = 0
        for file in files {
            let (next, overflow) = total.addingReportingOverflow(file.size)
            guard !overflow, file.size >= 0, next <= Self.maximumDownloadBytes else {
                throw SpeechModelDownloadError.downloadLimitExceeded
            }
            total = next
        }
        return total
    }

    private func destinationURL(root: URL, relativePath: String) throws -> URL {
        guard SpeechModelRemoteFileMapper.isSafePath(relativePath) else {
            throw SpeechModelDownloadError.unsafePath(relativePath)
        }
        let standardizedRoot = root.standardizedFileURL
        let destination = standardizedRoot.appendingPathComponent(relativePath).standardizedFileURL
        let rootPrefix = standardizedRoot.path.hasSuffix("/") ? standardizedRoot.path : standardizedRoot.path + "/"
        guard destination.path.hasPrefix(rootPrefix) else { throw SpeechModelDownloadError.unsafePath(relativePath) }
        return destination
    }

    private func authorizedRequest(url: URL) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 120)
        if SpeechModelRegistrySecurity.shouldAttachToken(to: url), let token = Self.huggingFaceToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func apiURL(model: SpeechInputModel, path: String) throws -> URL {
        let suffix = path.isEmpty ? "" : "/\(path.encodedSpeechModelPath)"
        return try makeURL("\(model.registryBaseURL.trimmedSpeechRegistryURL)/api/models/\(model.repo)/tree/\(model.revision)\(suffix)")
    }

    private func resolveURL(model: SpeechInputModel, path: String) throws -> URL {
        try makeURL(
            "\(model.registryBaseURL.trimmedSpeechRegistryURL)/\(model.repo)/resolve/\(model.revision)/\(path.encodedSpeechModelPath)"
        )
    }

    private func makeURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else { throw SpeechModelDownloadError.invalidURL(value) }
        return url
    }

    private static func progress(index: Int, count: Int, completed: Int64, written: Int64, total: Int64) -> SpeechDownloadProgress {
        let fraction = total > 0 ? Double(completed + written) / Double(total) : Double(index) / Double(max(count, 1))
        return SpeechDownloadProgress(fraction: fraction, phaseTitle: "Downloading file \(min(index + 1, count)) of \(count)")
    }

    private static var huggingFaceToken: String? {
        ProcessInfo.processInfo.environment["HF_TOKEN"]
            ?? ProcessInfo.processInfo.environment["HUGGING_FACE_HUB_TOKEN"]
            ?? ProcessInfo.processInfo.environment["HUGGINGFACEHUB_API_TOKEN"]
    }
}

private extension String {
    var encodedSpeechModelPath: String {
        split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    var trimmedSpeechRegistryURL: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
