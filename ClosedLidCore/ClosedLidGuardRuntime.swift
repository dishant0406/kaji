import Darwin
import Foundation
import IOKit

public final class ClosedLidGuardSession: @unchecked Sendable {
    private let driver: any ClosedLidSelectorDriving
    private let heartbeatTimeoutNanoseconds: UInt64
    private let now: @Sendable () -> UInt64
    private var state: ClosedLidGuardState = .disarmed
    private var evidence: ClosedLidStandardSessionEvidence?

    public init(
        driver: any ClosedLidSelectorDriving,
        heartbeatTimeout: TimeInterval = closedLidGuardDefaultHeartbeatTimeout,
        now: @escaping @Sendable () -> UInt64 = ClosedLidContinuousClock.nowNanoseconds
    ) {
        self.driver = driver
        heartbeatTimeoutNanoseconds = UInt64(max(heartbeatTimeout, 0.001) * 1_000_000_000)
        self.now = now
        _ = driver.setEnabled(false)
    }

    deinit {
        _ = driver.setEnabled(false)
    }

    public var isArmed: Bool { state == .armed }

    public func handle(_ request: ClosedLidGuardRequest) -> ClosedLidGuardResponse {
        switch request.command {
        case .arm:
            let result = driver.setEnabled(true)
            if result == KERN_SUCCESS {
                let timestamp = now()
                state = .armed
                evidence = ClosedLidStandardSessionEvidence(
                    sessionID: UUID(),
                    armedMonotonicNanoseconds: timestamp,
                    lastHeartbeatMonotonicNanoseconds: timestamp,
                    heartbeatCount: 0
                )
            } else {
                restore()
            }
            return response(id: request.id, selectorResult: result)
        case .disarm:
            let result = driver.setEnabled(false)
            if result == KERN_SUCCESS {
                state = .disarmed
                evidence = nil
            }
            return response(id: request.id, selectorResult: result)
        case .heartbeat:
            guard state == .armed, let current = evidence else {
                return response(id: request.id, selectorResult: kIOReturnNotOpen)
            }
            evidence = ClosedLidStandardSessionEvidence(
                sessionID: current.sessionID,
                armedMonotonicNanoseconds: current.armedMonotonicNanoseconds,
                lastHeartbeatMonotonicNanoseconds: now(),
                heartbeatCount: current.heartbeatCount + 1
            )
            return response(id: request.id, selectorResult: KERN_SUCCESS)
        case .status:
            return response(id: request.id, selectorResult: KERN_SUCCESS)
        case .shutdown:
            let result = driver.setEnabled(false)
            if result == KERN_SUCCESS {
                state = .disarmed
                evidence = nil
            }
            return response(id: request.id, selectorResult: result, shouldExit: true)
        }
    }

    public func restore() {
        _ = driver.setEnabled(false)
        state = .disarmed
        evidence = nil
    }

    public func restoreIfHeartbeatExpired() -> Bool {
        guard state == .armed, let evidence else { return false }
        let timestamp = now()
        guard timestamp >= evidence.lastHeartbeatMonotonicNanoseconds,
              timestamp - evidence.lastHeartbeatMonotonicNanoseconds >= heartbeatTimeoutNanoseconds
        else { return false }
        restore()
        return true
    }

    private func response(
        id: UUID,
        selectorResult: kern_return_t,
        shouldExit: Bool = false
    ) -> ClosedLidGuardResponse {
        ClosedLidGuardResponse(
            id: id,
            state: state,
            selectorResult: selectorResult,
            evidence: evidence,
            shouldExit: shouldExit
        )
    }
}

public final class ClosedLidGuardRuntime {
    private let parentPID: pid_t
    private let inputDescriptor: Int32
    private let output: FileHandle
    private let session: ClosedLidGuardSession
    private let parentIsAlive: @Sendable (pid_t) -> Bool
    private let pollInterval: TimeInterval
    private var reader: ClosedLidJSONLineReader
    private let signalState = ClosedLidGuardSignalState()
    private var signalSources: [DispatchSourceSignal] = []

    public init(
        parentPID: pid_t,
        inputDescriptor: Int32 = STDIN_FILENO,
        output: FileHandle = .standardOutput,
        session: ClosedLidGuardSession,
        pollInterval: TimeInterval = 0.25,
        parentIsAlive: @escaping @Sendable (pid_t) -> Bool = ClosedLidGuardRuntime.liveParentIsAlive
    ) {
        self.parentPID = parentPID
        self.inputDescriptor = inputDescriptor
        self.output = output
        self.session = session
        self.pollInterval = min(max(pollInterval, 0.01), 1)
        self.parentIsAlive = parentIsAlive
        reader = ClosedLidJSONLineReader(descriptor: inputDescriptor)
    }

    deinit {
        session.restore()
    }

    public func run() -> Int32 {
        installSignalHandlers()
        defer {
            signalSources.forEach { $0.cancel() }
            session.restore()
        }
        while !signalState.received {
            guard parentIsAlive(parentPID) else { return 0 }
            if session.restoreIfHeartbeatExpired() { return 0 }
            do {
                let frame = try reader.nextFrame(timeout: pollInterval)
                let request = try JSONDecoder().decode(ClosedLidGuardRequest.self, from: frame)
                let response = session.handle(request)
                try output.write(contentsOf: ClosedLidJSONLineCodec.encode(response))
                if response.shouldExit { return response.selectorResult == KERN_SUCCESS ? 0 : 1 }
            } catch ClosedLidGuardProtocolError.timedOut {
                continue
            } catch ClosedLidGuardProtocolError.endOfFile {
                return 0
            } catch {
                return 1
            }
        }
        return 0
    }

    public static func liveParentIsAlive(_ pid: pid_t) -> Bool {
        guard pid > 1 else { return false }
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            Darwin.signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global(qos: .userInitiated))
            source.setEventHandler { [signalState] in signalState.received = true }
            source.resume()
            signalSources.append(source)
        }
    }
}

public enum ClosedLidContinuousClock {
    public static func nowNanoseconds() -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        guard timebase.denom != 0 else { return 0 }
        return UInt64(Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom))
    }
}

private final class ClosedLidGuardSignalState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var received: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
