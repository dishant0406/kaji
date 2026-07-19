import Foundation
import IOKit

public let closedLidSelectorIndex: UInt32 = 12

public struct ClosedLidSelectorProbeResult: Sendable, Equatable {
    public let enableResult: kern_return_t
    public let restoreResult: kern_return_t

    public init(enableResult: kern_return_t, restoreResult: kern_return_t) {
        self.enableResult = enableResult
        self.restoreResult = restoreResult
    }

    public var isAvailable: Bool {
        enableResult == KERN_SUCCESS && restoreResult == KERN_SUCCESS
    }
}

public protocol ClosedLidSelectorDriving: Sendable {
    func setEnabled(_ enabled: Bool) -> kern_return_t
}

public struct IOPMRootDomainClosedLidSelectorDriver: ClosedLidSelectorDriving {
    public init() {}

    public func setEnabled(_ enabled: Bool) -> kern_return_t {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return kIOReturnNotFound }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == KERN_SUCCESS else { return openResult }
        defer { IOServiceClose(connection) }
        var input: UInt64 = enabled ? 1 : 0
        return withUnsafePointer(to: &input) { pointer in
            IOConnectCallScalarMethod(connection, closedLidSelectorIndex, pointer, 1, nil, nil)
        }
    }
}

public enum ClosedLidSelectorCapabilityProbe {
    public static func run(driver: any ClosedLidSelectorDriving) -> ClosedLidSelectorProbeResult {
        let enableResult = driver.setEnabled(true)
        let restoreResult = driver.setEnabled(false)
        return ClosedLidSelectorProbeResult(enableResult: enableResult, restoreResult: restoreResult)
    }
}
