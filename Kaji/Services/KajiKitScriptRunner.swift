import Foundation

enum KajiKitScriptRunStatus: Equatable {
    case idle
    case running
    case succeeded(Int32)
    case failed(Int32)
}

@MainActor
@Observable
final class KajiKitScriptRunner {
    private var process: Process?
    private var outputPipe: Pipe?

    private(set) var status = KajiKitScriptRunStatus.idle
    private(set) var output = ""
    private(set) var plan: KajiKitScriptRunPlan?

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    func run(_ plan: KajiKitScriptRunPlan) {
        stop()
        self.plan = plan
        output = ""
        status = .running

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [plan.scriptURL.path]
        process.currentDirectoryURL = plan.workingDirectory
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.finish(code: process.terminationStatus)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.output += chunk
            }
        }

        do {
            try process.run()
            self.process = process
            outputPipe = pipe
        } catch {
            output = error.localizedDescription
            status = .failed(1)
        }
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        outputPipe = nil
    }

    private func finish(code: Int32) {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
        status = code == 0 ? .succeeded(code) : .failed(code)
    }
}
