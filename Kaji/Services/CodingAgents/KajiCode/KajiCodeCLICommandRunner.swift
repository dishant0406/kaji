import Foundation

struct KajiCodeCLICommandResult: Equatable {
    let exitCode: Int32
    let output: String
}

protocol KajiCodeCLICommandRunning {
    func run(
        binaryURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) throws -> KajiCodeCLICommandResult
}

struct KajiCodeCLICommandRunner: KajiCodeCLICommandRunning {
    func run(
        binaryURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 30
    ) throws -> KajiCodeCLICommandResult {
        let result = try AIGatewayProcessRunner.run(
            executableURL: binaryURL,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        )
        return KajiCodeCLICommandResult(exitCode: result.exitCode, output: result.output)
    }
}
