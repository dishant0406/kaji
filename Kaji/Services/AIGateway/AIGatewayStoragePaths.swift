import Foundation

enum AIGatewayStoragePaths {
    static func supportDirectory() -> URL {
        KajiFileStorage.appSupportDirectory().appendingPathComponent("ai-gateway", isDirectory: true)
    }
}
