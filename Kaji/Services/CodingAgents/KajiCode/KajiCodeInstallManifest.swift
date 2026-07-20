import Foundation

struct KajiCodeInstallManifest: Codable, Equatable {
    var activeVersion: String
    var previousVersion: String?
    var protocolVersion: Int
    var platform: String
    var sourceURL: URL
    var sha256: String
    var installedAt: Date
    var binaryPath: String
    var smokeOutput: String
    var channelURL: URL
}

enum KajiCodeInstallState: Equatable {
    case missing
    case installed(KajiCodeInstallManifest)
    case needsRepair(String)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}
