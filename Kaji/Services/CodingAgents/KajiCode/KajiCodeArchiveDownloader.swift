import CryptoKit
import Foundation

enum KajiCodeArchiveDownloader {
    static let maximumArchiveBytes: Int64 = 400 * 1024 * 1024

    static func download(
        asset: KajiCodeChannelAsset,
        destination: URL,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) async throws -> URL {
        guard asset.size > 0, asset.size <= maximumArchiveBytes else { throw KajiCodeInstallError.invalidAssetSize }
        let (data, response) = try await session.data(from: asset.url)
        guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else {
            throw KajiCodeInstallError.downloadFailed
        }
        guard Int64(data.count) == asset.size else { throw KajiCodeInstallError.invalidAssetSize }
        guard sha256(data: data) == asset.sha256.lowercased() else { throw KajiCodeInstallError.checksumMismatch }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func sha256(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
