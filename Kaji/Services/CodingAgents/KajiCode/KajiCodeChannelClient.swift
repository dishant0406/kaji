import Foundation

enum KajiCodeChannelClient {
    static func fetch(
        url: URL = KajiCodePaths.channelURL(),
        cacheURL: URL = KajiCodePaths.channelCacheURL(),
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) async throws -> KajiCodeChannel {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else {
            throw KajiCodeInstallError.channelFetchFailed
        }
        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: cacheURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> KajiCodeChannel {
        try JSONDecoder().decode(KajiCodeChannel.self, from: data)
    }
}
