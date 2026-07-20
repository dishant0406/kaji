import Foundation

struct KajiCodeCLICommandResult: Equatable {
    let exitCode: Int32
    let output: String
}

protocol KajiCodeCLICommandRunning {
    func run(binaryURL: URL, arguments: [String], timeout: TimeInterval) throws -> KajiCodeCLICommandResult
}

struct KajiCodeCLICommandRunner: KajiCodeCLICommandRunning {
    func run(binaryURL: URL, arguments: [String], timeout: TimeInterval = 30) throws -> KajiCodeCLICommandResult {
        let result = try AIGatewayProcessRunner.run(
            executableURL: binaryURL,
            arguments: arguments,
            timeout: timeout
        )
        return KajiCodeCLICommandResult(exitCode: result.exitCode, output: result.output)
    }
}
