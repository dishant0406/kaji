import Foundation
import KajiPowerHelperProtocol
import Observation
import os
import ServiceManagement

private let powerProtectLogger = Logger(subsystem: "app.kaji", category: "PowerProtect")

final class PowerProtectResponseBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?

    @MainActor
    func wait(
        timeout: Duration = .seconds(6),
        start: (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let pending = lock.withLock { () -> Result<Value, Error>? in
                if let result {
                    return result
                }
                self.continuation = continuation
                return nil
            }
            if let pending {
                continuation.resume(with: pending)
                return
            }
            start { [weak self] result in self?.complete(result) }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.complete(.failure(PowerHelperError.connectionFailed))
            }
        }
    }

    private func complete(_ result: Result<Value, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Value, Error>? in
            guard self.result == nil else { return nil }
            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}

@MainActor
protocol PowerProtectManaging: AnyObject {
    var state: PowerHelperRegistrationState { get }
    func probeCapability() async
    func enableVerified() async throws
    func restore() async throws
    func heartbeat() async -> Bool
    func refresh() async
}

@MainActor
protocol PowerProtectServiceManaging: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

extension SMAppService: PowerProtectServiceManaging {}

@MainActor
final class PowerProtectManager: PowerProtectManaging {
    static let shared = PowerProtectManager()

    private(set) var state: PowerHelperRegistrationState = .unavailable
    private var connection: NSXPCConnection?
    private static let requestTimeout = Duration.seconds(6)
    private let service: any PowerProtectServiceManaging
    private let bundle: Bundle

    init(
        service: any PowerProtectServiceManaging = SMAppService.daemon(
            plistName: "com.kaji.app.power-helper.plist"
        ),
        bundle: Bundle = .main
    ) {
        self.service = service
        self.bundle = bundle
    }

    func probeCapability() async {
        guard #available(macOS 13.0, *), installationAssetsAvailable else {
            state = .unavailable
            return
        }
        await refresh()
    }

    func register() async {
        guard installationAssetsAvailable else {
            state = .failed("Power Protect requires a packaged Kaji app containing its signed helper.")
            return
        }
        state = .registering
        do {
            try service.register()
        } catch {
            powerProtectLogger.error("Power Protect registration failed: \(error.localizedDescription, privacy: .public)")
            state = .failed("Helper registration failed: \(error.localizedDescription)")
            return
        }
        let registeredState = registrationState(for: service.status)
        if registeredState == .requiresApproval {
            state = .requiresApproval
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        guard case .ready = registeredState else {
            state = .failed("macOS did not register the Power Protect helper.")
            return
        }
        await refresh()
    }

    func unregister() async throws {
        if service.status == .enabled {
            try await restore()
        }
        invalidateConnection()
        try await service.unregister()
        state = registrationState(for: service.status)
    }

    func enableVerified() async throws {
        try requireEnabled()
        let result = try await setKeepAwake(true)
        guard result.success else {
            state = .failed(result.message ?? PowerHelperError.verificationFailed.localizedDescription)
            throw PowerHelperError.commandFailed(result.message ?? PowerHelperError.verificationFailed.localizedDescription)
        }
        let live = try await fetchState()
        guard live else {
            state = .failed(PowerHelperError.verificationFailed.localizedDescription)
            throw PowerHelperError.verificationFailed
        }
        state = .ready(sleepDisabled: true)
    }

    func restore() async throws {
        try requireEnabled()
        let result = try await restoreRemotely()
        guard result.success else {
            state = .failed(result.message ?? PowerHelperError.verificationFailed.localizedDescription)
            throw PowerHelperError.commandFailed(result.message ?? PowerHelperError.verificationFailed.localizedDescription)
        }
        let live = try await fetchState()
        guard !live else {
            state = .failed(PowerHelperError.verificationFailed.localizedDescription)
            throw PowerHelperError.verificationFailed
        }
        state = .ready(sleepDisabled: false)
    }

    var installationAssetsAvailable: Bool {
        let helper = bundle.bundleURL.appendingPathComponent("Contents/MacOS/KajiPowerHelper")
        let plist = bundle.bundleURL.appendingPathComponent(
            "Contents/Library/LaunchDaemons/com.kaji.app.power-helper.plist"
        )
        return FileManager.default.isExecutableFile(atPath: helper.path)
            && FileManager.default.fileExists(atPath: plist.path)
    }

    func heartbeat() async -> Bool {
        guard service.status == .enabled else {
            state = registrationState(for: service.status)
            return false
        }
        do {
            let active = try await sendHeartbeat()
            let live = try await fetchState()
            state = .ready(sleepDisabled: live)
            return active && live
        } catch {
            invalidateConnection()
            state = .failed(PowerHelperError.connectionFailed.localizedDescription)
            return false
        }
    }

    func refresh() async {
        let registration = registrationState(for: service.status)
        guard case .ready = registration else {
            invalidateConnection()
            state = registration
            return
        }
        do {
            let helperVersion = try await fetchVersion()
            guard helperVersion == kajiPowerHelperVersion else {
                try await reregisterForUpdate()
                return
            }
            state = try await .ready(sleepDisabled: fetchState())
        } catch {
            invalidateConnection()
            state = .failed(PowerHelperError.connectionFailed.localizedDescription)
        }
    }

    private func registrationState(for status: SMAppService.Status) -> PowerHelperRegistrationState {
        switch status {
        case .enabled: .ready(sleepDisabled: false)
        case .requiresApproval: .requiresApproval
        case .notRegistered,
             .notFound: .notRegistered
        @unknown default: .unavailable
        }
    }

    private func requireEnabled() throws {
        switch service.status {
        case .enabled: return
        case .requiresApproval: throw PowerHelperError.requiresApproval
        case .notRegistered,
             .notFound: throw PowerHelperError.notRegistered
        @unknown default: throw PowerHelperError.unavailable
        }
    }

    private func reregisterForUpdate() async throws {
        let restoreResult = try await restoreRemotely()
        guard restoreResult.success else {
            throw PowerHelperError.commandFailed(restoreResult.message ?? "Normal sleep could not be restored before updating the helper.")
        }
        invalidateConnection()
        try await service.unregister()
        try service.register()
        state = registrationState(for: service.status)
    }

    private func helperProxy(onError: @escaping @Sendable (Error) -> Void) throws -> KajiPowerHelperXPCProtocol {
        if connection == nil {
            let newConnection = NSXPCConnection(machServiceName: kajiPowerHelperMachServiceName, options: .privileged)
            newConnection.remoteObjectInterface = NSXPCInterface(with: KajiPowerHelperXPCProtocol.self)
            newConnection.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            newConnection.interruptionHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            newConnection.activate()
            connection = newConnection
        }
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ [weak self] error in
            onError(error)
            Task { @MainActor in self?.connection = nil }
        }) as? KajiPowerHelperXPCProtocol
        else {
            throw PowerHelperError.connectionFailed
        }
        return proxy
    }

    private func invalidateConnection() {
        connection?.invalidate()
        connection = nil
    }

    private func setKeepAwake(_ enabled: Bool) async throws -> (success: Bool, message: String?) {
        let box = PowerProtectResponseBox<(Bool, String?)>()
        return try await box.wait(timeout: Self.requestTimeout) { complete in
            do {
                let proxy = try self.helperProxy { complete(.failure($0)) }
                proxy.setKeepAwake(enabled) { success, message in complete(.success((success, message))) }
            } catch {
                complete(.failure(error))
            }
        }
    }

    private func restoreRemotely() async throws -> (success: Bool, message: String?) {
        let box = PowerProtectResponseBox<(Bool, String?)>()
        return try await box.wait(timeout: Self.requestTimeout) { complete in
            do {
                let proxy = try self.helperProxy { complete(.failure($0)) }
                proxy.restoreNow { success, message in complete(.success((success, message))) }
            } catch {
                complete(.failure(error))
            }
        }
    }

    private func fetchState() async throws -> Bool {
        let box = PowerProtectResponseBox<Bool>()
        return try await box.wait(timeout: Self.requestTimeout) { complete in
            do {
                let proxy = try self.helperProxy { complete(.failure($0)) }
                proxy.getState { success, sleepDisabled, message in
                    if success {
                        complete(.success(sleepDisabled))
                    } else {
                        complete(.failure(PowerHelperError.commandFailed(message ?? "Power state could not be read.")))
                    }
                }
            } catch {
                complete(.failure(error))
            }
        }
    }

    private func fetchVersion() async throws -> Int {
        let box = PowerProtectResponseBox<Int>()
        return try await box.wait(timeout: Self.requestTimeout) { complete in
            do {
                let proxy = try self.helperProxy { complete(.failure($0)) }
                proxy.version { complete(.success($0)) }
            } catch {
                complete(.failure(error))
            }
        }
    }

    private func sendHeartbeat() async throws -> Bool {
        let box = PowerProtectResponseBox<Bool>()
        return try await box.wait(timeout: Self.requestTimeout) { complete in
            do {
                let proxy = try self.helperProxy { complete(.failure($0)) }
                proxy.heartbeat { complete(.success($0)) }
            } catch {
                complete(.failure(error))
            }
        }
    }
}
