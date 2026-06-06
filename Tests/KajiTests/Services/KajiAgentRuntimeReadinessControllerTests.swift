import Foundation
import Testing

@testable import Kaji

@MainActor
struct KajiAgentRuntimeReadinessControllerTests {
    @Test
    func resolvesRuntimeOffMainFlow() async {
        let controller = KajiAgentRuntimeReadinessController { _ in .missingRuntime }
        var didCheck = false
        var resolutions: [KajiAgentLaunchResolution] = []

        controller.refresh(
            configuration: KajiAgentRuntimeConfiguration(projectPath: "/tmp/project", sessionDirectory: nil, approvalMode: "read"),
            currentReadiness: .missingRuntime,
            force: true
        ) {
            didCheck = true
        } onResolution: {
            resolutions.append($0)
        }
        await waitUntil { !resolutions.isEmpty }

        #expect(didCheck)
        #expect(resolutions == [.missingRuntime])
    }

    @Test
    func skipsDuplicateReadyRefreshWithoutForce() async {
        let controller = KajiAgentRuntimeReadinessController { _ in .missingRuntime }
        let configuration = KajiAgentRuntimeConfiguration(projectPath: "/tmp/project", sessionDirectory: nil, approvalMode: "read")
        var checks = 0
        var resolutions: [KajiAgentLaunchResolution] = []

        controller.refresh(configuration: configuration, currentReadiness: .missingRuntime, force: true) {
            checks += 1
        } onResolution: {
            resolutions.append($0)
        }
        await waitUntil { resolutions.count == 1 }
        controller.refresh(configuration: configuration, currentReadiness: .ready, force: false) {
            checks += 1
        } onResolution: {
            resolutions.append($0)
        }
        await Task.yield()

        #expect(checks == 1)
        #expect(resolutions == [.missingRuntime])
    }

    @Test
    func ignoresStaleResolutionFromForcedRefresh() async {
        let spy = ReadinessResolverSpy()
        let controller = KajiAgentRuntimeReadinessController { _ in
            if spy.nextCall() == 1 {
                Thread.sleep(forTimeInterval: 0.05)
                return .missingRuntime
            }
            return .missingBun
        }
        let configuration = KajiAgentRuntimeConfiguration(projectPath: "/tmp/project", sessionDirectory: nil, approvalMode: "read")
        var resolutions: [KajiAgentLaunchResolution] = []

        controller.refresh(configuration: configuration, currentReadiness: .checking, force: true) {} onResolution: {
            resolutions.append($0)
        }
        controller.refresh(configuration: configuration, currentReadiness: .checking, force: true) {} onResolution: {
            resolutions.append($0)
        }
        await waitUntil { resolutions.count == 1 }
        try? await Task.sleep(for: .milliseconds(80))

        #expect(resolutions == [.missingBun])
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<50 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class ReadinessResolverSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func nextCall() -> Int {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return calls
    }
}
