import Foundation

@MainActor
final class KajiAgentRuntimeReadinessController {
    typealias Resolver = @Sendable (KajiAgentRuntimeConfiguration) -> KajiAgentLaunchResolution

    private let resolver: Resolver
    private var task: Task<Void, Never>?
    private var signature: String?
    private var generation = 0

    init(resolver: @escaping Resolver = KajiAgentRuntimeReadinessController.defaultResolver) {
        self.resolver = resolver
    }

    func refresh(
        configuration: KajiAgentRuntimeConfiguration,
        currentReadiness: KajiAgentReadiness,
        force: Bool,
        onChecking: () -> Void,
        onResolution: @MainActor @Sendable @escaping (KajiAgentLaunchResolution) -> Void
    ) {
        let nextSignature = configuration.signature
        if !force, signature == nextSignature, currentReadiness.isReady { return }
        if !force, task != nil { return }
        task?.cancel()
        generation += 1
        let nextGeneration = generation
        signature = nextSignature
        onChecking()
        task = Task.detached { [resolver, configuration] in
            let resolution = resolver(configuration)
            await MainActor.run { [weak self] in
                self?.finish(
                    resolution,
                    signature: nextSignature,
                    generation: nextGeneration,
                    onResolution: onResolution
                )
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }

    private func finish(
        _ resolution: KajiAgentLaunchResolution,
        signature: String,
        generation: Int,
        onResolution: @MainActor @Sendable (KajiAgentLaunchResolution) -> Void
    ) {
        guard self.signature == signature, self.generation == generation else { return }
        task = nil
        onResolution(resolution)
    }

    nonisolated private static func defaultResolver(_ configuration: KajiAgentRuntimeConfiguration) -> KajiAgentLaunchResolution {
        KajiAgentRuntimeLocator.resolveLaunch(
            projectPath: configuration.projectPath,
            sessionDirectory: configuration.sessionDirectory,
            approvalMode: configuration.approvalMode
        )
    }
}

struct KajiAgentRuntimeConfiguration: Equatable {
    let projectPath: String?
    let sessionDirectory: String?
    let approvalMode: String

    var signature: String {
        [
            projectPath ?? "",
            sessionDirectory ?? "",
            approvalMode,
        ].joined(separator: "\u{1f}")
    }
}
