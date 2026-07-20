import Foundation

enum KajiCodeSmokeTester {
    static func smoke(binaryURL: URL, expectedVersion: String?) async throws -> String {
        let result = try await GitProcessRunner.offMainThrowing {
            try AIGatewayProcessRunner.run(
                executableURL: binaryURL,
                arguments: ["--version"],
                timeout: 15
            )
        }
        guard result.exitCode == 0 else { throw KajiCodeInstallError.smokeFailed(result.output) }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let expectedVersion, !expectedVersion.isEmpty, !output.contains(expectedVersion) {
            throw KajiCodeInstallError.smokeFailed("Expected version \(expectedVersion), got \(output).")
        }
        return output
    }
}
