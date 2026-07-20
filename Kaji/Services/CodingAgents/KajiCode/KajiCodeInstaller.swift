import Foundation

struct KajiCodeInstallResult: Equatable {
    let state: KajiCodeInstallState
    let message: String
}

enum KajiCodeInstallError: LocalizedError, Equatable {
    case channelFetchFailed
    case noCompatibleVersion
    case invalidAssetSize
    case checksumMismatch
    case downloadFailed
    case unsafeArchive
    case missingBinary
    case extractFailed(String)
    case smokeFailed(String)

    var errorDescription: String? {
        switch self {
        case .channelFetchFailed: "KajiCode channel could not be fetched."
        case .noCompatibleVersion: "No compatible KajiCode version is available for this Kaji build."
        case .invalidAssetSize: "KajiCode archive size did not match the channel manifest."
        case .checksumMismatch: "KajiCode archive checksum did not match the channel manifest."
        case .downloadFailed: "KajiCode archive download failed."
        case .unsafeArchive: "KajiCode archive contains unsafe paths."
        case .missingBinary: "KajiCode archive does not contain the kajicode binary."
        case let .extractFailed(detail): "KajiCode archive extraction failed. \(detail)"
        case let .smokeFailed(detail): "KajiCode smoke test failed. \(detail)"
        }
    }
}

enum KajiCodeInstaller {
    static func state(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> KajiCodeInstallState {
        guard let manifest = KajiCodeInstallStore.read(env: env, fileManager: fileManager) else { return .missing }
        guard fileManager.isExecutableFile(atPath: manifest.binaryPath) else {
            return .needsRepair("Managed KajiCode binary is missing.")
        }
        return .installed(manifest)
    }

    static func installLatest(
        currentKajiVersion: String = KajiVersion.current,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) async -> KajiCodeInstallResult {
        do {
            let channelURL = KajiCodePaths.channelURL(env: env)
            let channel = try await KajiCodeChannelClient.fetch(
                url: channelURL,
                cacheURL: KajiCodePaths.channelCacheURL(env: env),
                fileManager: fileManager
            )
            guard let entry = KajiCodeCompatibilityPolicy.latestCompatibleEntry(
                in: channel,
                currentKajiVersion: currentKajiVersion
            ), let asset = KajiCodeCompatibilityPolicy.asset(for: entry)
            else { throw KajiCodeInstallError.noCompatibleVersion }
            let manifest = try await install(entry: entry, asset: asset, channelURL: channelURL, env: env, fileManager: fileManager)
            return .init(state: .installed(manifest), message: "Installed KajiCode \(manifest.activeVersion).")
        } catch {
            return .init(state: .needsRepair(error.localizedDescription), message: error.localizedDescription)
        }
    }

    static func uninstall(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> KajiCodeInstallResult {
        do {
            let root = KajiCodePaths.root(env: env)
            if fileManager.fileExists(atPath: root.path) { try fileManager.removeItem(at: root) }
            return .init(state: .missing, message: "Uninstalled KajiCode.")
        } catch {
            return .init(state: .needsRepair(error.localizedDescription), message: error.localizedDescription)
        }
    }

    private static func install(
        entry: KajiCodeChannelEntry,
        asset: KajiCodeChannelAsset,
        channelURL: URL,
        env: [String: String],
        fileManager: FileManager
    ) async throws -> KajiCodeInstallManifest {
        let archiveName = asset.url.lastPathComponent
        let archiveURL = KajiCodePaths.downloadsDirectory(env: env).appendingPathComponent(archiveName)
        let previous = KajiCodeInstallStore.read(env: env, fileManager: fileManager)?.activeVersion
        let downloaded = try await KajiCodeArchiveDownloader.download(asset: asset, destination: archiveURL, fileManager: fileManager)
        let installDir = KajiCodePaths.installDirectory(version: entry.version, env: env)
        let binary = try await KajiCodeArchiveExtractor.extract(archiveURL: downloaded, destination: installDir, fileManager: fileManager)
        let smoke = try await KajiCodeSmokeTester.smoke(binaryURL: binary, expectedVersion: entry.version)
        let manifest = KajiCodeInstallManifest(
            activeVersion: entry.version,
            previousVersion: previous == entry.version ? nil : previous,
            protocolVersion: entry.protocolVersion,
            platform: KajiCodePlatform.current,
            sourceURL: asset.url,
            sha256: asset.sha256,
            installedAt: Date(),
            binaryPath: binary.path,
            smokeOutput: smoke,
            channelURL: channelURL
        )
        try KajiCodeInstallStore.write(manifest, env: env, fileManager: fileManager)
        return manifest
    }
}
