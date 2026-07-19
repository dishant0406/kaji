import Foundation
import Testing
@testable import KajiPowerHelperProtocol

struct KajiPowerHelperProtocolTests {
    @Test func parsesSleepDisabledWithoutDependingOnWhitespaceOrSurroundingLocale() {
        let output = """
        System-wide power settings:
         Currently in use:
          standbydelayhigh      4200
          SleepDisabled         1
          tcpkeepalive          1
        """
        #expect(PMSetStateParser.sleepDisabled(from: output) == true)
        #expect(PMSetStateParser.sleepDisabled(from: "SleepDisabled\t0") == false)
        #expect(PMSetStateParser.sleepDisabled(from: "ModoReposo 1") == nil)
        #expect(PMSetStateParser.sleepDisabled(from: "SleepDisabled yes") == nil)
    }

    @Test func commandsAreFixedAndContainNoShell() {
        #expect(PMSetCommand.readState.executableURL.path == "/usr/bin/pmset")
        #expect(PMSetCommand.readState.arguments == ["-g"])
        #expect(PMSetCommand.setSleepDisabled(true).arguments == ["-a", "disablesleep", "1"])
        #expect(PMSetCommand.setSleepDisabled(false).arguments == ["-a", "disablesleep", "0"])
    }

    @Test func watchdogClampsTimeoutAndExpiresAtBoundary() {
        let origin = Date(timeIntervalSince1970: 1_000)
        var watchdog = PowerHelperWatchdog(timeout: 1, now: origin)
        #expect(watchdog.timeout == 10)
        #expect(!watchdog.shouldRestore(at: origin.addingTimeInterval(9.9)))
        #expect(watchdog.shouldRestore(at: origin.addingTimeInterval(10)))
        watchdog.heartbeat(at: origin.addingTimeInterval(8))
        #expect(!watchdog.shouldRestore(at: origin.addingTimeInterval(17.9)))
        #expect(watchdog.shouldRestore(at: origin.addingTimeInterval(18)))
        #expect(PowerHelperWatchdog(timeout: 1_000).timeout == 30)
    }
}
